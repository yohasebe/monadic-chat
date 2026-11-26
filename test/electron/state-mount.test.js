// The workspace ledger lives in ~/monadic/state and the Knowledge Base's own
// files in ~/monadic/library, outside the shared folder, and only the Ruby
// container mounts them: the Python container runs generated code that can
// write the shared folder, and must not reach these.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '../..');
const SERVICES = path.join(ROOT, 'docker/services');
const MONADIC_SH = path.join(ROOT, 'docker/monadic.sh');

const hasCompose = (() => {
  try { execFileSync('docker', ['compose', 'version'], { stdio: 'ignore' }); return true; } catch { return false; }
})();

const FOLDERS = ['state', 'library'];

describe('state and library folder mounts', () => {
  (hasCompose ? test.each(FOLDERS) : test.skip.each(FOLDERS))('docker compose mounts /monadic/%s in the Ruby service only', (folder) => {
    const out = execFileSync('docker', ['compose', '-f', path.join(SERVICES, 'compose.yml'), '--profile', '*', 'config', '--format', 'json'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const services = JSON.parse(out).services;
    const target = `/monadic/${folder}`;
    const mounting = Object.entries(services)
      .filter(([, s]) => (s.volumes || []).some((v) => v.target === target))
      .map(([name]) => name);
    expect(Object.keys(services).length).toBeGreaterThan(3);
    expect(mounting).toEqual(['ruby_service']);

    const mount = services.ruby_service.volumes.find((v) => v.target === target);
    expect(mount.type).toBe('bind');
    expect(mount.source).toBe(path.join(os.homedir(), 'monadic', folder));
  });

  // Run the function as monadic.sh defines it, not a copy of its rule
  function runEnsureStateDir(home) {
    const body = execFileSync('sed', ['-n', '/^ensure_state_dir() {/,/^}/p', MONADIC_SH], { encoding: 'utf8' });
    expect(body).toMatch(/^ensure_state_dir\(\) \{/);
    execFileSync('bash', ['-c', `${body}\nensure_state_dir`], { env: { ...process.env, HOME_DIR: home } });
  }

  test('monadic.sh creates ~/monadic/state and ~/monadic/library for the user, private, before compose mounts them', () => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'state-dir-'));
    try {
      runEnsureStateDir(home);
      FOLDERS.forEach((folder) => {
        const st = fs.statSync(path.join(home, 'monadic', folder));
        expect(st.isDirectory()).toBe(true);
        expect(st.mode & 0o777).toBe(0o700);
        expect(st.uid).toBe(process.getuid());
      });
      runEnsureStateDir(home); // idempotent
    } finally {
      fs.rmSync(home, { recursive: true, force: true });
    }
  });

  test('every path that starts containers creates the state folder first', () => {
    const text = fs.readFileSync(MONADIC_SH, 'utf8');
    const fnBody = (name) => {
      const m = text.match(new RegExp(`^${name}\\(\\) \\{\\n([\\s\\S]*?)^\\}`, 'm'));
      return m ? m[1] : '';
    };
    // start uses start_docker_compose; build and ensure-service go through ensure_data_dir
    expect(fnBody('start_docker_compose')).toMatch(/^\s*ensure_state_dir\s*$/m);
    expect(fnBody('ensure_data_dir')).toMatch(/^\s*ensure_state_dir\s*$/m);
  });
});
