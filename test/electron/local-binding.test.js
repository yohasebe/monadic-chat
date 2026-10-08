// The server listens on this machine only. Nothing on the server checks who
// connects, so no setting, inherited variable or start path may publish a
// port to the network.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { monadicShEnv } = require('../../app/monadic_env');

const ROOT = path.join(__dirname, '../..');
const SERVICES = path.join(ROOT, 'docker/services');

function composeFiles() {
  return fs.readdirSync(SERVICES)
    .map((d) => path.join(SERVICES, d))
    .filter((d) => fs.statSync(d).isDirectory())
    .flatMap((d) => fs.readdirSync(d).filter((f) => /^compose(\.dev)?\.yml$/.test(f)).map((f) => path.join(d, f)));
}

describe('published ports', () => {
  test('every port mapping in the compose files is bound to 127.0.0.1', () => {
    const mappings = [];
    for (const file of composeFiles()) {
      const text = fs.readFileSync(file, 'utf8');
      const block = /^\s*ports:\s*\n((?:\s+(?:-.*|#.*)\n)+)/gm;
      let m;
      while ((m = block.exec(text)) !== null) {
        for (const line of m[1].split('\n')) {
          const item = line.match(/^\s*-\s*"([^"]+)"/);
          if (item) mappings.push([path.relative(ROOT, file), item[1]]);
        }
      }
    }
    expect(mappings.length).toBeGreaterThan(5);
    for (const [file, mapping] of mappings) {
      expect(`${file}: ${mapping}`).toMatch(/: 127\.0\.0\.1:/);
    }
  });

  test('no compose file or start script reads HOST_BINDING', () => {
    for (const file of [...composeFiles(), path.join(ROOT, 'docker/monadic.sh')]) {
      expect(`${path.relative(ROOT, file)}: ${fs.readFileSync(file, 'utf8').includes('HOST_BINDING')}`).toMatch(/: false$/);
    }
  });

  // Ask compose itself, with a wide binding inherited from the environment
  const hasCompose = (() => {
    try { execFileSync('docker', ['compose', 'version'], { stdio: 'ignore' }); return true; } catch { return false; }
  })();
  (hasCompose ? test : test.skip)('docker compose resolves every published port to 127.0.0.1', () => {
    const out = execFileSync('docker', ['compose', '-f', path.join(SERVICES, 'compose.yml'), '--profile', '*', 'config', '--format', 'json'],
      { encoding: 'utf8', env: { ...process.env, HOST_BINDING: '0.0.0.0' }, stdio: ['ignore', 'pipe', 'ignore'] });
    const ports = Object.values(JSON.parse(out).services).flatMap((s) => s.ports || []);
    expect(ports.length).toBeGreaterThan(3);
    for (const p of ports) expect(p.host_ip).toBe('127.0.0.1');
  });
});

describe('development servers on the host', () => {
  test.each([
    'docker/services/ruby/bin/monadic_dev',
    'bin/dev_server.sh'
  ])('%s binds Falcon to 127.0.0.1', (file) => {
    const text = fs.readFileSync(path.join(ROOT, file), 'utf8');
    const binds = [...text.matchAll(/falcon serve[^\n]*-b\s+http:\/\/([^:\s/]+)/g)].map((m) => m[1]);
    expect(binds.length).toBeGreaterThan(0);
    for (const host of binds) expect(host).toBe('127.0.0.1');
  });
});

describe('Electron hands no binding to monadic.sh', () => {
  test('HOST_BINDING and DISTRIBUTED_MODE from the env file are not passed on', () => {
    const env = monadicShEnv({ HOST_BINDING: '0.0.0.0', DISTRIBUTED_MODE: 'server', EXTRA_LOGGING: 'true' });
    expect(env).not.toHaveProperty('HOST_BINDING');
    expect(env).not.toHaveProperty('DISTRIBUTED_MODE');
    expect(env).toHaveProperty('EXTRA_LOGGING', 'true');
  });
});
