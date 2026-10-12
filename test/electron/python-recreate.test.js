// After a Python image build, the running container must be created again
// from the new image: a restart keeps it on the image it was created from.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const MONADIC_SH = path.join(__dirname, '../../docker/monadic.sh');

// Run the function as monadic.sh defines it, against a stand-in docker that
// records its arguments and answers as told.
function recreate({ composeStatus = 0, running = 'sha256:new', built = 'sha256:new', latest = built }) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'python-recreate-'));
  try {
    const calls = path.join(dir, 'calls');
    const docker = path.join(dir, 'docker');
    fs.writeFileSync(docker, `#!/bin/bash
echo "$*" >> "${calls}"
case "$1" in
  compose) echo "compose output"; exit ${composeStatus} ;;
  inspect) echo "${running}" ;;
  image) echo "${latest}" ;;
esac
`, { mode: 0o755 });
    const body = execFileSync('sed', ['-n', '/^recreate_python_container() {/,/^}/p', MONADIC_SH], { encoding: 'utf8' });
    expect(body).toMatch(/^recreate_python_container\(\) \{/);
    const log = path.join(dir, 'build.log');
    const result = spawnSync('bash', ['-c', `${body}\nrecreate_python_container "${log}" "${built}"`], {
      env: { ...process.env, DOCKER: docker, COMPOSE_FILES: '-f "main.yml"' }, encoding: 'utf8'
    });
    const read = (file) => (fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '');
    return { status: result.status, calls: read(calls).trim().split('\n').filter(Boolean), log: read(log) };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

describe('putting the Python container on a new image', () => {
  test('creates the container again from the current image, in the app\'s project', () => {
    const { status, calls, log } = recreate({});
    expect(status).toBe(0);
    expect(calls[0]).toBe('compose -f main.yml -p monadic-chat --profile python up -d --force-recreate --no-deps ' +
      '--pull never --no-build python_service');
    expect(calls.some((c) => / restart /.test(` ${c} `))).toBe(false);
    expect(log).toContain('compose output');
  });

  test('reports a failure when compose fails, though its output goes through tee', () => {
    expect(recreate({ composeStatus: 1 }).status).not.toBe(0);
  });

  test('reports a failure when the running container is still on another image', () => {
    expect(recreate({ running: 'sha256:old' }).status).not.toBe(0);
  });

  test('compares with the image that was built, not with what latest points to afterwards', () => {
    // latest was moved to another image meanwhile, and the container followed it
    expect(recreate({ built: 'sha256:built', latest: 'sha256:other', running: 'sha256:other' }).status).not.toBe(0);
  });

  test('does nothing without the ID of the image that was built', () => {
    const { status, calls } = recreate({ built: '' });
    expect(status).not.toBe(0);
    expect(calls).toEqual([]); // docker was never called
  });

  test('the build no longer restarts the container in place', () => {
    const text = fs.readFileSync(MONADIC_SH, 'utf8');
    expect(text).not.toMatch(/restart python_service/);
    expect(text).toMatch(/if recreate_python_container "\$\{build_log\}" "\$\{built_image\}"; then/);
  });

  test('takes the status of a piped command, never of tee', () => {
    const text = fs.readFileSync(MONADIC_SH, 'utf8');
    expect(text).not.toMatch(/^\s*if !? ?\$\{DOCKER\} (pull|build|run)[^\n]*\| tee[^\n]*; then/m);
    // the pipe of the whole build is outside eval, where PIPESTATUS can see it
    expect(text).not.toMatch(/eval "[^"\n]*build \$\{use_cache\} 2>&1 \| tee/);
    expect(text).toMatch(/build \$\{use_cache\}" 2>&1 \| tee -a "\$\{log_file\}"\n\s*local build_status=\$\{PIPESTATUS\[0\]\}/);
  });
});
