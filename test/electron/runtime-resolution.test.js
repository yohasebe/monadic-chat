// monadic.sh resolves the Docker engine the way the Docker CLI chooses it
// (DOCKER_CONTEXT, then DOCKER_HOST, then the current context), uses only a
// local socket, and says whether it is Docker Desktop's. Run against a
// stand-in docker CLI that knows a few contexts.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const SCRIPT = path.join(__dirname, '../../docker/monadic.sh');

const FAKE_DOCKER = `#!/bin/bash
case "$1 $2" in
  "context show") echo "\${FAKE_CURRENT:-desktop-linux}" ;;
  "context inspect")
    case "$3" in
      desktop-linux) echo "unix://$HOME/.docker/run/docker.sock" ;;
      colima) echo "unix://$HOME/.colima/default/docker.sock" ;;
      podman) echo "unix:///var/folders/x/podman-machine-default-api.sock" ;;
      remote) echo "ssh://user@example.com" ;;
      *) exit 1 ;;
    esac ;;
  "info "*|"info") exit 0 ;;
  "version --format") echo "\${FAKE_COMPONENT:-Engine}" ;;
  *) exit 0 ;;
esac
`;

let dir;
beforeAll(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'runtime-resolution-'));
  fs.mkdirSync(path.join(dir, 'bin'));
  fs.writeFileSync(path.join(dir, 'bin', 'docker'), FAKE_DOCKER, { mode: 0o755 });
});
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

function run(command, env = {}) {
  const result = spawnSync('bash', [SCRIPT, command], {
    env: { HOME: dir, PATH: `${path.join(dir, 'bin')}:/usr/bin:/bin`, ...env },
    encoding: 'utf8',
    timeout: 20000
  });
  const report = {};
  for (const line of result.stdout.split('\n')) {
    const at = line.indexOf('=');
    if (at > 0) report[line.slice(0, at)] = line.slice(at + 1);
  }
  return { report, stdout: result.stdout.trim(), status: result.status };
}

describe('the Docker engine monadic.sh uses', () => {
  test("follows the current context and knows Docker Desktop's", () => {
    expect(run('runtime').report).toMatchObject({ origin: 'context', context: 'desktop-linux', desktop: '1', refused: '' });
  });

  test('takes another engine chosen by context as not Docker Desktop', () => {
    expect(run('runtime', { FAKE_CURRENT: 'colima' }).report).toMatchObject({ context: 'colima', desktop: '0', refused: '' });
  });

  test('puts DOCKER_CONTEXT before DOCKER_HOST and the current context', () => {
    const { report } = run('runtime', { DOCKER_CONTEXT: 'podman', DOCKER_HOST: 'unix:///elsewhere.sock' });
    expect(report).toMatchObject({ origin: 'DOCKER_CONTEXT', context: 'podman', desktop: '0', refused: '' });
  });

  test("takes DOCKER_HOST when no context is named, and knows Docker Desktop's socket", () => {
    const { report } = run('runtime', { DOCKER_HOST: `unix://${dir}/.docker/run/docker.sock` });
    expect(report).toMatchObject({ origin: 'DOCKER_HOST', context: '', desktop: '1', refused: '' });
  });

  test.each([
    ['Docker for an engine whose first component is "Engine"', {}, 'Docker'],
    ['the name an engine gives itself as "<Name> Engine"', { FAKE_COMPONENT: 'Podman Engine' }, 'Podman']
  ])('names %s', (_name, env, product) => {
    expect(run('runtime', env).report.product).toBe(product);
  });

  test.each([
    ['a remote context', { FAKE_CURRENT: 'remote' }],
    ['a TCP host', { DOCKER_HOST: 'tcp://10.0.0.5:2375' }],
    ['an SSH host', { DOCKER_HOST: 'ssh://user@example.com' }],
    ['a context with no engine', { DOCKER_CONTEXT: 'missing' }]
  ])('refuses %s, and runs nothing with it', (_name, env) => {
    expect(run('runtime', env).report.refused).not.toBe('');
    expect(run('check', env).stdout).toBe('refused');
    const start = run('start', env);
    expect(start.status).toBe(1);
    expect(start.stdout).toContain('Docker cannot be used');
  });
});
