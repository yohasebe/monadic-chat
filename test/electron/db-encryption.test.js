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
const factory = new Function('crypto', 'fs',
  constsBlock + extract('encryptDbExport') + '\n' + extract('decryptDbImport') +
  '\nreturn { encryptDbExport, decryptDbImport };'
);
const { encryptDbExport, decryptDbImport } = factory(crypto, fs);

let tmpDir;

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mqdb-enc-'));
});

afterEach(() => {
  try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) { /* ignore */ }
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
