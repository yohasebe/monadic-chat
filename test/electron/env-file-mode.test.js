// The env file holds API keys, so every write leaves it readable by its owner
// only, whether the write creates the file or replaces an existing one.
// main.js starts the whole app at load, so the writer and the functions that
// call it are taken from the real file and evaluated here.
const fs = require('fs');
const os = require('os');
const path = require('path');

function loadEnvFunctions({ proc = process, execFileSync = () => {} } = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../../app/main.js'), 'utf8');
  const names = ['writeEnvContent', 'readEnvFile', 'writeEnvFile'];
  const bodies = names.map((name) => {
    const m = source.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}\\n`));
    if (!m) throw new Error(`${name} not found in main.js`);
    return m[0];
  });
  const dotenv = { parse: (text) => Object.fromEntries(text.split('\n').filter(Boolean).map((l) => l.split('='))) };
  // eslint-disable-next-line no-new-func
  return new Function('fs', 'path', 'dotenv', 'process', 'execFileSync', `${bodies.join('\n')}\nreturn { ${names.join(', ')} };`)(fs, path, dotenv, proc, execFileSync);
}

const describeUnix = process.platform === 'win32' ? describe.skip : describe;

describeUnix('env file permissions', () => {
  let dir;
  let envPath;
  const env = loadEnvFunctions();

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'env-mode-'));
    envPath = path.join(dir, 'config', 'env');
  });

  afterEach(() => fs.rmSync(dir, { recursive: true, force: true }));

  const mode = () => fs.statSync(envPath).mode & 0o777;

  test('a file created on first read is owner-only', () => {
    expect(env.readEnvFile(envPath)).toEqual({});
    expect(mode()).toBe(0o600);
  });

  test('saving settings narrows an existing world-readable file', () => {
    fs.mkdirSync(path.dirname(envPath), { recursive: true });
    fs.writeFileSync(envPath, 'A=1\n', { mode: 0o644 });
    fs.chmodSync(envPath, 0o644);
    expect(env.writeEnvFile(envPath, { A: '2' })).toBe(true);
    expect(mode()).toBe(0o600);
    expect(fs.readFileSync(envPath, 'utf8')).toBe('A=2\n');
  });

  test('main.js writes the env file only through writeEnvContent', () => {
    const source = fs.readFileSync(path.join(__dirname, '../../app/main.js'), 'utf8');
    const direct = source.split('\n').filter((l) => /writeFileSync\(envPath/.test(l));
    expect(direct).toHaveLength(1);
    expect(direct[0]).toMatch(/mode: 0o600/);
  });
});

// On Windows the file is inside WSL; the mode is set there, after the write.
describe('env file permissions on Windows', () => {
  test('WSL makes the file owner-only after each write, without a shell on the Windows side', () => {
    const calls = [];
    const writes = [];
    const fakeFs = { writeFileSync: (...args) => writes.push(args), chmodSync: () => { throw new Error('not on Windows'); } };
    const source = fs.readFileSync(path.join(__dirname, '../../app/main.js'), 'utf8');
    const body = source.match(/function writeEnvContent\([^)]*\) \{[\s\S]*?\n\}\n/)[0];
    // eslint-disable-next-line no-new-func
    const writeEnvContent = new Function('fs', 'process', 'execFileSync', 'console', `${body}\nreturn writeEnvContent;`)(
      fakeFs, { platform: 'win32' }, (cmd, args) => calls.push([cmd, args]), { error: () => {} });
    writeEnvContent('\\\\wsl$\\Ubuntu\\home\\u\\monadic\\config\\env', 'A=1\n');
    expect(writes).toHaveLength(1);
    expect(calls).toEqual([['wsl.exe', ['--exec', 'sh', '-c', 'chmod 600 "$HOME/monadic/config/env"']]]);
  });
});

// The file written and the file narrowed are the same, wherever WSL's $HOME is.
describe('env file location on Windows', () => {
  const source = fs.readFileSync(path.join(__dirname, '../../app/main.js'), 'utf8');
  const take = (name) => source.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}\\n`))[0];

  // A stand-in for wsl.exe: runs `sh -c` scripts with $HOME set to home and
  // answers wslpath -w as WSL does; records the files chmod was given.
  function fakeWsl(home) {
    const chmodded = [];
    const exec = (cmd, args) => {
      expect(cmd).toBe('wsl.exe');
      const script = args[args.length - 1].replace(/\$HOME/g, home);
      let m = script.match(/^wslpath -w "([^"]+)"$/);
      if (m) return `\\\\wsl$\\Ubuntu${m[1].replace(/\//g, '\\')}\n`;
      m = script.match(/^chmod 600 "([^"]+)"$/);
      if (m) { chmodded.push(`\\\\wsl$\\Ubuntu${m[1].replace(/\//g, '\\')}`); return ''; }
      throw new Error(`unexpected: ${script}`);
    };
    return { exec, chmodded };
  }

  test.each(['/home/u', '/root', '/srv/users/u'])('HOME=%s', (home) => {
    const wsl = fakeWsl(home);
    const fakeFs = { writeFileSync: () => {}, chmodSync: () => {} };
    // eslint-disable-next-line no-new-func
    const fns = new Function('fs', 'path', 'os', 'process', 'execFileSync', 'console',
      `${take('wslMonadicPath')}\n${take('getEnvPath')}\n${take('writeEnvContent')}\nreturn { getEnvPath, writeEnvContent };`)(
      fakeFs, path, { platform: () => 'win32' }, { platform: 'win32' }, wsl.exec, { error: () => {} });
    const envPath = fns.getEnvPath();
    expect(envPath).toBe(`\\\\wsl$\\Ubuntu${home.replace(/\//g, '\\')}\\monadic\\config\\env`);
    fns.writeEnvContent(envPath, 'A=1\n');
    expect(wsl.chmodded).toEqual([envPath]);
  });
});
