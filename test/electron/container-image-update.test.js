// After a service image is built or pulled, the build must report its own
// result (an older image still there is not a success), and a running
// container must be created again from the new image: a restart keeps it on
// the image it was created from.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const MONADIC_SH = path.join(__dirname, '../../docker/monadic.sh');
const TEXT = fs.readFileSync(MONADIC_SH, 'utf8');

// The functions as monadic.sh defines them, not copies of their rules
function functions(...names) {
  return names.map((name) => {
    const body = execFileSync('sed', ['-n', `/^${name}() {/,/^}/p`, MONADIC_SH], { encoding: 'utf8' });
    expect(body).toMatch(new RegExp(`^${name}\\(\\) \\{`));
    return body;
  }).join('\n');
}

// Runs `call` with the functions against a stand-in docker that records its
// arguments. `answers` is the body of a bash `case "$1"` (one per docker
// subcommand); `images` maps an image reference to its ID (absent: none).
function run(names, call, { answers = '', images = {}, containers = {} } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'image-update-'));
  try {
    const calls = path.join(dir, 'calls');
    const docker = path.join(dir, 'docker');
    const imageCases = Object.entries(images).map(([ref, id]) => `    "${ref}") echo "${id}"; exit 0 ;;`).join('\n');
    const containerCases = Object.entries(containers).map(([name, id]) => `    "${name}") echo "${id}"; exit 0 ;;`).join('\n');
    fs.writeFileSync(docker, `#!/bin/bash
echo "$*" >> "${calls}"
last="\${@: -1}"
case "$1" in
${answers}
  image) case "$last" in
${imageCases}
    esac; exit 1 ;;
  inspect) case "$last" in
${containerCases}
    esac; exit 1 ;;
  ps) printf '%s\\n' ${Object.keys(containers).map((n) => `"${n}"`).join(' ')} ;;
esac
`, { mode: 0o755 });
    const log = path.join(dir, 'build.log');
    const result = spawnSync('bash', ['-c', `${functions(...names)}\n${call.replace(/LOG/g, `"${log}"`)}`], {
      env: { ...process.env, DOCKER: docker, COMPOSE_FILES: '-f "main.yml"' }, encoding: 'utf8'
    });
    const read = (file) => (fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '');
    return { status: result.status, stdout: result.stdout, calls: read(calls).trim().split('\n').filter(Boolean), log: read(log) };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const RECREATE = ['recreate_service_container', 'recreate_python_container'];

describe('putting the Python container on a new image', () => {
  const recreate = ({ composeStatus = 0, running = 'sha256:new', built = 'sha256:new' } = {}) =>
    run(RECREATE, `recreate_python_container LOG "${built}"`, {
      answers: `  compose) echo "compose output"; exit ${composeStatus} ;;`,
      containers: { 'monadic-chat-python-container': running }
    });

  test('creates the container again from the local image, in the app\'s project', () => {
    const { status, calls, log } = recreate();
    expect(status).toBe(0);
    expect(calls[0]).toBe('compose -f main.yml -p monadic-chat --profile python up -d --force-recreate --no-deps ' +
      '--pull never --no-build python_service');
    expect(calls.some((c) => / restart /.test(` ${c} `))).toBe(false);
    expect(log).toContain('compose output');
  });

  test('reports a failure when compose fails, though its output goes through tee', () => {
    expect(recreate({ composeStatus: 1 }).status).not.toBe(0);
  });

  test('reports a failure when the running container is not on the image that was built', () => {
    expect(recreate({ running: 'sha256:old' }).status).not.toBe(0);
  });

  test('does nothing without the ID of the image that was built', () => {
    const { status, calls } = recreate({ built: '' });
    expect(status).not.toBe(0);
    expect(calls).toEqual([]);
  });

  test('the build no longer restarts the container in place', () => {
    expect(TEXT).not.toMatch(/restart python_service/);
    expect(TEXT).toMatch(/if recreate_python_container "\$\{build_log\}" "\$\{built_image\}"; then/);
  });
});

describe('moving a running service container onto a pulled or built image', () => {
  const NAMES = [...RECREATE, 'put_running_service_on_image'];
  const PRIVACY = 'ghcr.io/yohasebe/monadic-privacy:latest';
  const CALL = `put_running_service_on_image LOG privacy privacy_service monadic-chat-privacy-container "${PRIVACY}" "Privacy"`;

  test('creates a running container again when it is on another image', () => {
    let after = 'sha256:old';
    const { status, calls, log } = run(NAMES, CALL, {
      answers: '  compose) exit 0 ;;',
      images: { [PRIVACY]: 'sha256:new' },
      containers: { 'monadic-chat-privacy-container': after }
    });
    expect(status).toBe(0); // the image is in place; the container is reported on its own
    expect(calls.find((c) => c.startsWith('compose'))).toBe('compose -f main.yml -p monadic-chat --profile privacy up -d ' +
      '--force-recreate --no-deps --pull never --no-build privacy_service');
    // the stand-in still reports the old image after compose, so the move is reported as not done
    expect(log).toContain('could not be moved to the new image');
  });

  test('leaves a container alone that already runs the image', () => {
    const { calls } = run(NAMES, CALL, {
      images: { [PRIVACY]: 'sha256:same' },
      containers: { 'monadic-chat-privacy-container': 'sha256:same' }
    });
    expect(calls.some((c) => c.startsWith('compose'))).toBe(false);
  });

  test('does nothing when the service is not running', () => {
    const { calls } = run(NAMES, CALL, { images: { [PRIVACY]: 'sha256:new' } });
    expect(calls.some((c) => c.startsWith('compose'))).toBe(false);
  });
});

describe('whether a pulled or built service image is ready', () => {
  const IMAGE = 'ghcr.io/yohasebe/monadic-extractor:latest';
  const ready = (status, dev, installed) =>
    run(['service_image_ready'], `service_image_ready ${status} ${dev} "${IMAGE}" "Extractor" LOG`,
      { images: installed ? { [IMAGE]: 'sha256:x' } : {} });

  test('ready when the build or pull succeeded and the image is there', () => {
    expect(ready(0, 'true', true).status).toBe(0);
    expect(ready(0, 'false', true).status).toBe(0);
  });

  test('a failed build fails, whatever older image is still there', () => {
    expect(ready(1, 'true', true).status).not.toBe(0);
  });

  test('a failed pull keeps the installed image and says so', () => {
    const { status, log, stdout } = ready(1, 'false', true);
    expect(status).toBe(0);
    expect(log).toContain('could not be downloaded');
    expect(stdout).toContain('[HTML]');
  });

  test('a failed pull with nothing installed fails', () => {
    expect(ready(1, 'false', false).status).not.toBe(0);
  });
});

describe('build results come from the builds themselves', () => {
  test('the menu builds report the function\'s result, not whether an image exists', () => {
    expect(TEXT).toMatch(/if build_ruby_container; then/);
    expect(TEXT).toMatch(/if build_python_container; then/);
    expect(TEXT).toMatch(/if build_selenium_container; then/);
    expect(TEXT).toMatch(/elif \[ \$\{BUILD_RESULT\} -eq 0 \]; then/);
    // (an image that exists is still how start-up decides to start a container)
    for (const [service, label] of [['privacy', 'Privacy'], ['extractor', 'Extractor']]) {
      expect(TEXT).toMatch(new RegExp(`if service_image_ready [^\\n]*monadic-${service}[^\\n]*; then\\n\\s*echo "\\[INFO\\] ${label} container build succeeded\\."`));
    }
    expect(TEXT).toMatch(/if service_image_ready [^\n]*monadic-selenium[^\n]*; then\n\s*echo "Selenium container built successfully"/);
  });

  test('start-up does not take a failed Ruby build for an update', () => {
    // every call looks at the result; none goes on as if it had worked
    const calls = TEXT.split('\n').filter((l) => /\bbuild_ruby_container\b/.test(l) && !/^build_ruby_container\(\) \{|^build_ruby_container\)/.test(l));
    expect(calls.length).toBeGreaterThan(5);
    for (const line of calls) expect(line).toMatch(/if build_ruby_container; then|build_ruby_container \|\| /);
    // a selective rebuild records the update only when every image was updated
    expect(TEXT).toMatch(/if \[ "\$\{updated\}" = true \]; then\n\s*# Save updated container versions after selective rebuild\n\s*save_container_versions "silent"/);
  });

  test('a Ruby build within a larger update leaves the version record to its caller', () => {
    // build_ruby_container records every service's version; while other
    // images are still to be updated, recording must wait for them
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ruby-build-'));
    try {
      const docker = path.join(dir, 'docker');
      fs.writeFileSync(docker, '#!/bin/bash\nexit 0\n', { mode: 0o755 });
      const saved = path.join(dir, 'saved');
      const stubs = ['acquire_build_lock() { return 0; }', 'release_build_lock() { :; }',
        'remove_older_images() { :; }', 'remove_project_dangling_images() { :; }',
        `save_container_versions() { echo saved >> "${saved}"; }`].join('\n');
      const runBuild = (prefix) => spawnSync('bash', ['-c', `${stubs}\n${functions('build_ruby_container')}\n${prefix} build_ruby_container`], {
        env: { ...process.env, DOCKER: docker, ROOT_DIR: path.join(dir, 'root'), HOME_DIR: dir, MONADIC_VERSION: 't' }, encoding: 'utf8'
      });
      expect(runBuild('DEFER_VERSION_SAVE=true').status).toBe(0);
      expect(fs.existsSync(saved)).toBe(false);
      expect(runBuild('').status).toBe(0);
      expect(fs.readFileSync(saved, 'utf8').trim()).toBe('saved');
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
    expect(TEXT).toMatch(/DEFER_VERSION_SAVE=true build_ruby_container \|\| updated=false/);
  });

  test('takes the status of a piped command, never of tee', () => {
    expect(TEXT).not.toMatch(/^\s*if !? ?\$\{DOCKER\} (pull|build|run)[^\n]*\| tee[^\n]*; then/m);
    // the pipe of the whole build is outside eval, where PIPESTATUS can see it
    expect(TEXT).not.toMatch(/eval "[^"\n]*build \$\{use_cache\} 2>&1 \| tee/);
    expect(TEXT).toMatch(/build \$\{use_cache\}" 2>&1 \| tee -a "\$\{log_file\}"\n\s*local build_status=\$\{PIPESTATUS\[0\]\}/);
    // each image build or pull keeps its status right after its tee
    const fetches = TEXT.match(/--profile (privacy|extractor|selenium) (build|pull) \w+" 2>&1 \| tee -a "[^"]+"\n\s*fetched=\$\{PIPESTATUS\[0\]\}/g) || [];
    expect(fetches).toHaveLength(6);
  });
});
