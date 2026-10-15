// The env file holds API keys, so every write leaves it readable by its owner
// only, whether the write creates the file or replaces an existing one.
// main.js starts the whole app at load, so the writer and the functions that
// call it are taken from the real file and evaluated here.
const fs = require('fs');
const os = require('os');
const path = require('path');

function loadEnvFunctions() {
  const source = fs.readFileSync(path.join(__dirname, '../../app/main.js'), 'utf8');
  const names = ['writeEnvContent', 'readEnvFile', 'writeEnvFile'];
  const bodies = names.map((name) => {
    const m = source.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}\\n`));
    if (!m) throw new Error(`${name} not found in main.js`);
    return m[0];
  });
  const dotenv = { parse: (text) => Object.fromEntries(text.split('\n').filter(Boolean).map((l) => l.split('='))) };
  // eslint-disable-next-line no-new-func
  return new Function('fs', 'path', 'dotenv', 'process', `${bodies.join('\n')}\nreturn { ${names.join(', ')} };`)(fs, path, dotenv, process);
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
