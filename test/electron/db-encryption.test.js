/**
 * Tests for the Document DB export encryption helpers in main.js.
 *
 * Streaming AES-256-GCM with PBKDF2 (SHA-256) over a per-export salt.
 * The functions read/write actual files because the format includes a
 * trailing auth tag — verifying it requires the full file footprint.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

// Pull encryptDbExport and decryptDbImport out of main.js so we can run
// them in isolation. The file references Electron globals at top scope,
// but the encryption helpers themselves only use built-ins (crypto, fs).
const mainJsPath = path.join(__dirname, '../../app/main.js');
const src = fs.readFileSync(mainJsPath, 'utf8');

function extract(name) {
  // Match `function NAME(...) { ... }` allowing nested braces by counting.
  const re = new RegExp(`function ${name}\\b`);
  const m = re.exec(src);
  if (!m) throw new Error(`Could not find function ${name} in main.js`);
  let i = src.indexOf('{', m.index);
  if (i < 0) throw new Error(`Open brace not found for ${name}`);
  let depth = 1;
  let j = i + 1;
  while (j < src.length && depth > 0) {
    const ch = src[j];
    if (ch === '{') depth++;
    else if (ch === '}') depth--;
    j++;
  }
  return src.slice(m.index, j);
}

const constsBlock = `
const DB_ENC_MAGIC = Buffer.from([0x4d, 0x51, 0x44, 0x42]);
const DB_ENC_VERSION = 0x01;
const DB_ENC_SALT_BYTES = 16;
const DB_ENC_IV_BYTES = 12;
const DB_ENC_TAG_BYTES = 16;
const DB_ENC_HEADER_BYTES = 4 + 1 + DB_ENC_SALT_BYTES + DB_ENC_IV_BYTES;
const DB_ENC_KDF_ITERATIONS = 600000;
`;

// eslint-disable-next-line no-new-func
const noFollow = require('../../app/no_follow_files');
const factory = new Function('crypto', 'fs', 'writeStreamNoFollow', 'readStreamNoFollow', 'openReadNoFollow',
  constsBlock + extract('encryptDbExport') + '\n' + extract('decryptDbImport') +
  '\nreturn { encryptDbExport, decryptDbImport };'
);
const { encryptDbExport, decryptDbImport } = factory(crypto, fs,
  noFollow.writeStreamNoFollow, noFollow.readStreamNoFollow, noFollow.openReadNoFollow);

let tmpDir;

let tmpRoot;

// tmpDir stands for the shared folder, so the staging folder beside it is
// tmpRoot/.staging
beforeEach(() => {
  tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'mqdb-enc-'));
  tmpDir = path.join(tmpRoot, 'data');
  fs.mkdirSync(tmpDir);
});

afterEach(() => {
  try { fs.rmSync(tmpRoot, { recursive: true, force: true }); } catch (_) { /* ignore */ }
});

function runRoundTrip(plainText, passphrase) {
  const plainPath = path.join(tmpDir, 'plain.bin');
  const encPath = path.join(tmpDir, 'plain.bin.enc');
  const decPath = path.join(tmpDir, 'dec.bin');
  fs.writeFileSync(plainPath, plainText);
  return encryptDbExport(plainPath, encPath, passphrase)
    .then(() => decryptDbImport(encPath, decPath, passphrase))
    .then(() => fs.readFileSync(decPath));
}

describe('encryptDbExport / decryptDbImport', () => {
  it('round-trips a small plaintext payload', async () => {
    const result = await runRoundTrip(Buffer.from('hello world\n'), 'correct horse battery');
    expect(result.toString('utf8')).toBe('hello world\n');
  });

  it('round-trips a multi-MB payload that crosses stream chunk boundaries', async () => {
    // Random bytes catch off-by-one errors in the streaming offsets that
    // a repeating pattern would hide.
    const big = crypto.randomBytes(3 * 1024 * 1024);
    const result = await runRoundTrip(big, 'long enough passphrase');
    expect(result.equals(big)).toBe(true);
  });

  it('writes a valid header (magic + version + salt + iv) at the start of the encrypted file', async () => {
    const plainPath = path.join(tmpDir, 'plain.bin');
    const encPath = path.join(tmpDir, 'plain.bin.enc');
    fs.writeFileSync(plainPath, 'header check');
    await encryptDbExport(plainPath, encPath, 'pass1234');
    const buf = fs.readFileSync(encPath);
    expect(buf.subarray(0, 4).equals(Buffer.from([0x4d, 0x51, 0x44, 0x42]))).toBe(true);
    expect(buf[4]).toBe(0x01);
    // 4 magic + 1 version + 16 salt + 12 iv + ciphertext + 16 authTag = 49 + N
    expect(buf.length).toBeGreaterThan(4 + 1 + 16 + 12 + 16);
  });

  it('rejects decryption with the wrong passphrase', async () => {
    const plainPath = path.join(tmpDir, 'plain.bin');
    const encPath = path.join(tmpDir, 'plain.bin.enc');
    const decPath = path.join(tmpDir, 'dec.bin');
    fs.writeFileSync(plainPath, 'sensitive payload');
    await encryptDbExport(plainPath, encPath, 'right-passphrase');
    await expect(decryptDbImport(encPath, decPath, 'wrong-passphrase'))
      .rejects.toThrow(/Decryption failed/);
    // The partial decrypt file should be cleaned up so a stale ciphertext
    // does not get fed back to monadic.sh import.
    expect(fs.existsSync(decPath)).toBe(false);
  });

  it('rejects a tampered ciphertext (auth tag covers ciphertext bytes)', async () => {
    const plainPath = path.join(tmpDir, 'plain.bin');
    const encPath = path.join(tmpDir, 'plain.bin.enc');
    const decPath = path.join(tmpDir, 'dec.bin');
    fs.writeFileSync(plainPath, 'sensitive payload');
    await encryptDbExport(plainPath, encPath, 'pass1234');
    // Flip a bit in the middle of the ciphertext.
    const buf = fs.readFileSync(encPath);
    const flipAt = Math.floor((buf.length - 16 + 4 + 1 + 16 + 12) / 2);
    buf[flipAt] ^= 0x01;
    fs.writeFileSync(encPath, buf);
    await expect(decryptDbImport(encPath, decPath, 'pass1234'))
      .rejects.toThrow(/Decryption failed/);
  });

  it('rejects a file with the wrong magic bytes', async () => {
    const encPath = path.join(tmpDir, 'fake.enc');
    const decPath = path.join(tmpDir, 'dec.bin');
    // Write enough bytes (header + tag) to bypass the truncation guard.
    fs.writeFileSync(encPath, Buffer.alloc(4 + 1 + 16 + 12 + 16, 0xff));
    await expect(decryptDbImport(encPath, decPath, 'pass1234'))
      .rejects.toThrow(/magic mismatch/);
  });

  it('rejects a truncated file', async () => {
    const encPath = path.join(tmpDir, 'short.enc');
    const decPath = path.join(tmpDir, 'dec.bin');
    fs.writeFileSync(encPath, Buffer.from([0x4d, 0x51, 0x44, 0x42, 0x01]));
    await expect(decryptDbImport(encPath, decPath, 'pass1234'))
      .rejects.toThrow(/truncated/);
  });
});

// The files are in the shared folder, where code a model runs can leave a
// link, a FIFO or another file in their place.
describe('what is in place of the files', () => {
  const { execFileSync, spawnSync } = require('child_process');

  it('replaces a link at the export instead of writing through it', async () => {
    const plainPath = path.join(tmpDir, 'plain.bin');
    const victim = path.join(tmpDir, 'victim.txt');
    fs.writeFileSync(plainPath, 'db');
    fs.writeFileSync(victim, 'keep');
    fs.symlinkSync(victim, path.join(tmpDir, 'out.enc'));
    await encryptDbExport(plainPath, path.join(tmpDir, 'out.enc'), 'passphrase-123');
    expect(fs.readFileSync(victim, 'utf8')).toBe('keep');
    expect(fs.lstatSync(path.join(tmpDir, 'out.enc')).isFile()).toBe(true);
  });

  it('replaces a link at the import, and leaves the file in place when decryption fails', async () => {
    const plainPath = path.join(tmpDir, 'plain.bin');
    const encPath = path.join(tmpDir, 'plain.bin.enc');
    const victim = path.join(tmpDir, 'victim.txt');
    fs.writeFileSync(plainPath, 'db');
    fs.writeFileSync(victim, 'keep');
    await encryptDbExport(plainPath, encPath, 'passphrase-123');
    fs.symlinkSync(victim, path.join(tmpDir, 'restored.bin'));
    await expect(decryptDbImport(encPath, path.join(tmpDir, 'restored.bin'), 'wrong-passphrase')).rejects.toThrow();
    expect(fs.lstatSync(path.join(tmpDir, 'restored.bin')).isSymbolicLink()).toBe(true);
    await decryptDbImport(encPath, path.join(tmpDir, 'restored.bin'), 'passphrase-123');
    expect(fs.readFileSync(victim, 'utf8')).toBe('keep');
    expect(fs.readFileSync(path.join(tmpDir, 'restored.bin'), 'utf8')).toBe('db');
    expect(fs.readdirSync(tmpDir).filter((n) => n.endsWith('.part'))).toEqual([]);
    expect(fs.readdirSync(path.join(tmpRoot, '.staging'))).toEqual([]);
  });

  it('does not read a file elsewhere through a link', async () => {
    const secret = path.join(tmpDir, 'secret.txt');
    fs.writeFileSync(secret, 'private');
    fs.symlinkSync(secret, path.join(tmpDir, 'plain.bin'));
    await expect(encryptDbExport(path.join(tmpDir, 'plain.bin'), path.join(tmpDir, 'out.enc'), 'passphrase-123')).rejects.toThrow();
    expect(fs.existsSync(path.join(tmpDir, 'out.enc'))).toBe(false);
  });

  (process.platform === 'win32' ? it.skip : it)('does not block on a FIFO in place of a file', () => {
    execFileSync('mkfifo', [path.join(tmpDir, 'out.enc')]);
    execFileSync('mkfifo', [path.join(tmpDir, 'in.bin')]);
    fs.writeFileSync(path.join(tmpDir, 'plain.bin'), 'db');
    // In a child process, so that a block shows as a timeout, not a hung suite
    const script = `
      const nf = require(${JSON.stringify(path.join(__dirname, '../../app/no_follow_files'))});
      const s = nf.writeStreamNoFollow(${JSON.stringify(path.join(tmpDir, 'out.enc'))});
      s.write('x');
      s.commit().then(() => { let r = 'read-ok';
        try { nf.openReadNoFollow(${JSON.stringify(path.join(tmpDir, 'in.bin'))}); } catch (e) { r = 'read-refused'; }
        console.log('done ' + r); });`;
    const run = spawnSync(process.execPath, ['-e', script], { encoding: 'utf8', timeout: 5000 });
    expect(run.stdout.trim()).toBe('done read-refused');
    expect(fs.lstatSync(path.join(tmpDir, 'out.enc')).isFile()).toBe(true);
  });

  it('does not read a file swapped in after the check', () => {
    const nf = require('../../app/no_follow_files');
    const real = path.join(tmpDir, 'plain.bin');
    const other = path.join(tmpDir, 'other.bin');
    fs.writeFileSync(real, 'db');
    fs.writeFileSync(other, 'private');
    // an fs whose lstat sees the real file, then another file is renamed
    // into its place: open then succeeds, with or without O_NOFOLLOW (which
    // Windows lacks), so only the check after the open can catch it
    const swapping = { ...fs, lstatSync: (p) => {
      const st = fs.lstatSync(p);
      fs.renameSync(other, real);
      return st;
    } };
    expect(() => nf.openReadNoFollow(real, swapping)).toThrow();
  });

  // A write that fails (a full disk) must not be put in place, nor be
  // reported as done; and the file being written is never in the shared
  // folder, where it could be swapped before it is put in place.
  it('does not put a failed write in place', async () => {
    const nf = require('../../app/no_follow_files');
    const target = path.join(tmpDir, 'out.enc');
    fs.writeFileSync(target, 'keep');
    const full = Object.assign(new Error('no space left'), { code: 'ENOSPC' });
    const failingFs = { ...fs, createWriteStream: (p, o) => fs.createWriteStream(p, { ...o,
      fs: { ...fs, write: (...a) => a[a.length - 1](full), writev: (...a) => a[a.length - 1](full) } }) };
    const out = nf.writeStreamNoFollow(target, {}, failingFs);
    out.on('error', () => {});
    out.write('new');
    await expect(out.commit()).rejects.toThrow('no space left');
    expect(fs.readFileSync(target, 'utf8')).toBe('keep');
    expect(fs.readdirSync(path.join(tmpRoot, '.staging'))).toEqual([]);
  });

  it('does not put a stream destroyed before it finished in place', async () => {
    const nf = require('../../app/no_follow_files');
    const target = path.join(tmpDir, 'out.enc');
    fs.writeFileSync(target, 'keep');
    const out = nf.writeStreamNoFollow(target);
    out.on('error', () => {});
    out.write('partial');
    out.destroy(Object.assign(new Error('no space left'), { code: 'ENOSPC' }));
    await expect(out.commit()).rejects.toThrow();
    expect(fs.readFileSync(target, 'utf8')).toBe('keep');
    expect(fs.readdirSync(path.join(tmpRoot, '.staging'))).toEqual([]);
  });

  it('writes outside the shared folder until it is done', async () => {
    const nf = require('../../app/no_follow_files');
    const out = nf.writeStreamNoFollow(path.join(tmpDir, 'out.enc'));
    out.write('x');
    expect(fs.readdirSync(tmpDir)).toEqual([]);
    expect(fs.readdirSync(path.join(tmpRoot, '.staging')).length).toBe(1);
    await out.commit();
    expect(fs.readdirSync(tmpDir)).toEqual(['out.enc']);
  });

  it('leaves nothing behind when the input cannot be read', async () => {
    await expect(encryptDbExport(path.join(tmpDir, 'missing.bin'), path.join(tmpDir, 'out.enc'), 'passphrase-123')).rejects.toThrow();
    await new Promise((r) => setTimeout(r, 60));
    expect(fs.existsSync(path.join(tmpRoot, '.staging')) ? fs.readdirSync(path.join(tmpRoot, '.staging')) : []).toEqual([]);
    expect(fs.readdirSync(tmpDir)).toEqual([]);
  });
});
