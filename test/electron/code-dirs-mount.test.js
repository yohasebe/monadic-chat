// The shared folder's apps, helpers and services hold code the host loads
// (custom apps, helpers, container definitions). Every
// other container that mounts the shared folder (where code a model writes
// runs) gets them read-only, and monadic.sh makes them, as the user, before
// any container starts.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '../..');
const SERVICES = path.join(ROOT, 'docker/services');
const MONADIC_SH = path.join(ROOT, 'docker/monadic.sh');
const TEXT = fs.readFileSync(MONADIC_SH, 'utf8');

const hasCompose = (() => {
  try { execFileSync('docker', ['compose', 'version'], { stdio: 'ignore' }); return true; } catch { return false; }
})();

describe('apps, helpers and services in the containers', () => {
  (hasCompose ? test : test.skip)('every container that mounts the shared folder gets them read-only, Ruby too', () => {
    const out = execFileSync('docker', ['compose', '-f', path.join(SERVICES, 'compose.yml'), '--profile', '*', 'config', '--format', 'json'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const services = JSON.parse(out).services;
    const sharing = Object.entries(services)
      .filter(([name, s]) => name !== 'ruby_service' && (s.volumes || []).some((v) => v.target === '/monadic/data'));
    expect(sharing.map(([name]) => name).sort()).toEqual(['extractor_service', 'python_service', 'selenium_service']);
    // and the Ruby service, which only reads them
    sharing.push(['ruby_service', services.ruby_service]);
    for (const [name, s] of sharing) {
      for (const dir of ['apps', 'helpers', 'services']) {
        const mount = s.volumes.find((v) => v.target === `/monadic/data/${dir}`);
        expect(mount).toBeDefined();
        expect([name, dir, mount.read_only]).toEqual([name, dir, true]);
        expect(mount.source).toBe(path.join(os.homedir(), 'monadic', 'data', dir));
      }
    }
  });

  // Ask the kernel, not the compose file: mount the shared folder the way
  // compose resolves it for the Python container, and try, as root, every way
  // code a model runs could put code into apps, helpers or services. On Linux (CI) this
  // is the bind mount Docker Desktop's WSL2 backend uses as well.
  const mustRunMounts = process.env.CI === 'true' && process.platform === 'linux';
  const hasDaemon = (() => {
    try { execFileSync('docker', ['info'], { stdio: 'ignore', timeout: 20000 }); return true; } catch { return false; }
  })();
  ((hasCompose && hasDaemon) || mustRunMounts ? test : test.skip)('a container cannot write, link or swap its way into them', () => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'code-dirs-mount-'));
    try {
      const data = path.join(home, 'monadic', 'data');
      for (const dir of ['apps', 'helpers', 'services']) fs.mkdirSync(path.join(data, dir), { recursive: true });
      fs.writeFileSync(path.join(data, 'helpers', 'existing.rb'), 'original');

      const out = execFileSync('docker', ['compose', '-f', path.join(SERVICES, 'compose.yml'), '--profile', '*', 'config', '--format', 'json'],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, HOME: home, DOCKER_CONFIG: process.env.DOCKER_CONFIG || path.join(os.homedir(), '.docker') } });
      const mounts = JSON.parse(out).services.python_service.volumes
        .filter((v) => v.target === '/monadic/data' || v.target.startsWith('/monadic/data/'));
      expect(mounts.map((v) => v.target).sort()).toEqual(['/monadic/data', '/monadic/data/apps', '/monadic/data/helpers', '/monadic/data/services']);
      for (const v of mounts) expect(v.source.startsWith(home)).toBe(true);

      // Pinned by digest (the multi-arch index of busybox:1.37): CI pulls it on every run.
      const image = 'busybox@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e';
      let pulled = false;
      for (let i = 0; i < 3 && !pulled; i++) {
        try { execFileSync('docker', ['pull', '-q', image], { stdio: 'ignore', timeout: 120000 }); pulled = true; } catch { /* retry */ }
      }
      expect(pulled).toBe(true);

      const script = [
        'try() { label=$1; shift; if ( "$@" ) >/dev/null 2>&1; then echo "$label allowed"; else echo "$label refused"; fi; }',
        "try write-apps sh -c 'echo x > /monadic/data/apps/p.rb'",
        "try write-helpers sh -c 'echo x > /monadic/data/helpers/p.rb'",
        "try write-services sh -c 'mkdir -p /monadic/data/services/x && echo x > /monadic/data/services/x/compose.yml'",
        "try rename-services mv /monadic/data/services /monadic/data/s2",
        "try mkdir-apps mkdir /monadic/data/apps/sub",
        "try change-existing sh -c 'echo changed >> /monadic/data/helpers/existing.rb'",
        "try link-into sh -c 'echo x > /monadic/data/h.rb && ln /monadic/data/h.rb /monadic/data/helpers/h.rb'",
        "try link-out sh -c 'ln /monadic/data/helpers/existing.rb /monadic/data/e.rb && echo changed >> /monadic/data/e.rb'",
        "try symlink-into ln -s /monadic/data/x.rb /monadic/data/helpers/x.rb",
        "try rename-helpers mv /monadic/data/helpers /monadic/data/h2",
        "try remove-apps rmdir /monadic/data/apps",
        "try write-data sh -c 'echo x > /monadic/data/ok.txt'",
        // Another case reaches the same folder on a case-insensitive host
        // disk (macOS): it must not get past the mounts there either. On
        // Linux it is a different folder, so only the host check below counts.
        "try case-apps sh -c 'mkdir -p /monadic/data/Apps && echo x > /monadic/data/Apps/c.rb'",
        "try case-services sh -c 'mkdir -p /monadic/data/SERVICES/x && echo x > /monadic/data/SERVICES/x/compose.yml'",
      ].join('\n');
      const args = ['run', '--rm', '--network', 'none'];
      for (const v of mounts) args.push('--mount', `type=bind,src=${v.source},dst=${v.target}${v.read_only ? ',readonly' : ''}`);
      const result = execFileSync('docker', [...args, image, 'sh', '-c', script], { encoding: 'utf8', timeout: 120000 });

      const verdicts = Object.fromEntries(result.trim().split('\n').map((line) => line.split(' ')));
      delete verdicts['case-apps'];
      delete verdicts['case-services'];
      expect(verdicts).toEqual({
        'write-apps': 'refused',
        'write-helpers': 'refused',
        'write-services': 'refused',
        'rename-services': 'refused',
        'mkdir-apps': 'refused',
        'change-existing': 'refused',
        'link-into': 'refused',
        'link-out': 'refused',
        'symlink-into': 'refused',
        'rename-helpers': 'refused',
        'remove-apps': 'refused',
        'write-data': 'allowed', // the shared folder itself stays writable
      });
      // and on the host, nothing changed in them
      expect(fs.readdirSync(path.join(data, 'apps'))).toEqual([]);
      expect(fs.readdirSync(path.join(data, 'services'))).toEqual([]);
      expect(fs.readdirSync(path.join(data, 'helpers'))).toEqual(['existing.rb']);
      expect(fs.readFileSync(path.join(data, 'helpers', 'existing.rb'), 'utf8')).toBe('original');
    } finally {
      // Docker Desktop can hold the bind mounts for a moment after the
      // container exits (rmdir then fails with EACCES), so try again.
      for (let i = 0; ; i++) {
        try { fs.rmSync(home, { recursive: true, force: true }); break; } catch (e) {
          if (i >= 20) throw e;
          Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 500);
        }
      }
    }
  }, 300000);

  // The include file for building user containers is generated, then read by
  // docker compose: it must not be in the shared folder, where code in a
  // container could swap it in between or leave a link in its place.
  test('user containers are built from a file outside the shared folder', () => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'code-dirs-userbuild-'));
    try {
      fs.mkdirSync(path.join(home, 'monadic', 'data', 'services', 'mine'), { recursive: true });
      fs.writeFileSync(path.join(home, 'monadic', 'data', 'services', 'mine', 'compose.yml'), 'services: {}\n');
      const fn = (name) => execFileSync('sed', ['-n', `/^${name}() {/,/^}/p`, MONADIC_SH], { encoding: 'utf8' });
      const script = [fn('normalize_path'), fn('build_user_containers'),
        'acquire_build_lock() { return 0; }; release_build_lock() { :; }; remove_project_dangling_images() { :; }',
        // docker is a stub that prints the file compose was given
        'docker_stub() { while [[ $# -gt 0 ]]; do [[ "$1" == "-f" ]] && echo "COMPOSE_FILE=$2"; shift; done; return 0; }; DOCKER=docker_stub',
        'build_user_containers'].join('\n');
      const run = require('child_process').spawnSync('bash', ['-c', script],
        { env: { ...process.env, HOME: home, HOME_DIR: home }, encoding: 'utf8' });
      const used = (run.stdout.match(/COMPOSE_FILE=(.*)/) || [])[1];
      expect(used).toBe(path.join(home, 'monadic', 'config', 'compose_user.yml'));
      expect(fs.existsSync(path.join(home, 'monadic', 'data', 'compose_user.yml'))).toBe(false);
    } finally {
      fs.rmSync(home, { recursive: true, force: true });
    }
  });

  test('monadic.sh makes them for the user', () => {
    const body = execFileSync('sed', ['-n', '/^ensure_code_dirs() {/,/^}/p', MONADIC_SH], { encoding: 'utf8' });
    expect(body).toMatch(/^ensure_code_dirs\(\) \{/);
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'code-dirs-'));
    try {
      execFileSync('bash', ['-c', `${body}\nensure_code_dirs`], { env: { ...process.env, HOME_DIR: home } });
      for (const dir of ['apps', 'helpers', 'services']) {
        const st = fs.statSync(path.join(home, 'monadic', 'data', dir));
        expect(st.isDirectory()).toBe(true);
        expect(st.uid).toBe(process.getuid());
      }
    } finally {
      fs.rmSync(home, { recursive: true, force: true });
    }
  });

  test('a linked folder or one that cannot be made stops the start', () => {
    const body = execFileSync('sed', ['-n', '/^ensure_code_dirs() {/,/^}/p', MONADIC_SH], { encoding: 'utf8' });
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'code-dirs-'));
    try {
      const data = path.join(home, 'monadic', 'data');
      fs.mkdirSync(path.join(home, 'elsewhere'), { recursive: true });
      fs.mkdirSync(data, { recursive: true });
      fs.symlinkSync(path.join(home, 'elsewhere'), path.join(data, 'apps'));
      const linked = require('child_process').spawnSync('bash', ['-c', `${body}\nensure_code_dirs`], { env: { ...process.env, HOME_DIR: home }, encoding: 'utf8' });
      expect(linked.status).not.toBe(0);
      expect(linked.stdout).toMatch(/apps folder in the shared folder .* is a link/);

      fs.unlinkSync(path.join(data, 'apps'));
      fs.writeFileSync(path.join(data, 'helpers'), 'a file in the way');
      const blocked = require('child_process').spawnSync('bash', ['-c', `${body}\nensure_code_dirs`], { env: { ...process.env, HOME_DIR: home }, encoding: 'utf8' });
      expect(blocked.status).not.toBe(0);
      expect(blocked.stdout).toMatch(/Could not create the helpers folder/);
    } finally {
      fs.rmSync(home, { recursive: true, force: true });
    }
  });

  test('before any container starts: set_docker_compose and ensure_data_dir make them', () => {
    const fnBody = (name) => (TEXT.match(new RegExp(`^${name}\\(\\) \\{\\n([\\s\\S]*?)^\\}`, 'm')) || [])[1] || '';
    expect(fnBody('set_docker_compose')).toMatch(/ensure_code_dirs \|\| exit 1/);
    expect(fnBody('ensure_data_dir')).toMatch(/ensure_code_dirs \|\| exit 1/);
  });

  test('taking containers down does not stop on them, so it stays a way to recover', () => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'code-dirs-teardown-'));
    try {
      const data = path.join(home, 'monadic', 'data');
      fs.mkdirSync(path.join(home, 'elsewhere'), { recursive: true });
      fs.mkdirSync(path.join(data), { recursive: true });
      fs.mkdirSync(path.join(home, 'monadic', 'config'), { recursive: true });
      fs.symlinkSync(path.join(home, 'elsewhere'), path.join(data, 'apps'));
      const fn = (name) => execFileSync('sed', ['-n', `/^${name}() {/,/^}/p`, MONADIC_SH], { encoding: 'utf8' });
      // remove_containers with docker replaced by a stub that records the call
      const script = [fn('ensure_code_dirs'), fn('normalize_path'), fn('set_docker_compose'), fn('remove_containers'),
        // docker is a stub that says when compose is asked to take containers down
        'docker_stub() { [[ "$*" == *" down "* ]] && echo REACHED_DOWN; return 0; }; DOCKER=docker_stub',
        'remove_image() { :; }; remove_container() { :; }; remove_volume() { :; }; remove_project_dangling_images() { :; }',
        'remove_containers',
        'set_docker_compose; echo NOT_STOPPED'].join('\n');
      const run = require('child_process').spawnSync('bash', ['-c', script],
        { env: { ...process.env, HOME: home, HOME_DIR: home, ROOT_DIR: path.join(ROOT, 'docker') }, encoding: 'utf8' });
      expect(run.stdout).toContain('REACHED_DOWN');
      expect(run.stdout).not.toContain('NOT_STOPPED'); // starting still stops
      expect(run.status).not.toBe(0);
    } finally {
      fs.rmSync(home, { recursive: true, force: true });
    }
  });
});
