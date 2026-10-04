// monadic.sh used to receive every entry of ~/monadic/config/env, API keys
// included. It now receives only MONADIC_SH_ENV. These cases keep that list
// in step with the scripts: every variable monadic.sh or a compose file reads
// from its environment must be either set by the script itself or listed, and
// nothing that looks like a secret may be listed.
const fs = require('fs');
const path = require('path');
const { MONADIC_SH_ENV, monadicShEnv } = require('../../app/monadic_env');

const ROOT = path.join(__dirname, '../..');
const MONADIC_SH = fs.readFileSync(path.join(ROOT, 'docker/monadic.sh'), 'utf8');

function composeFiles(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return composeFiles(full);
    return /^compose.*\.ya?ml$/.test(entry.name) ? [full] : [];
  });
}

// Names monadic.sh sets itself, or that come from the shell or the script's
// own computations, never from the env file.
const SET_BY_THE_SCRIPTS = new Set([
  'HOST_OS', 'MONADIC_ROOT_DIR', 'MONADIC_VERSION', 'GEMS_FINGERPRINT', 'SUDO_USER',
  'PIPESTATUS', 'SECONDS', 'FORCE_REBUILD', 'MONADIC_RUBY_CONTAINER', 'MONADIC_CHAT_IMAGE_TAG'
]);

function readFromEnvironment() {
  const assigned = new Set(
    [...MONADIC_SH.matchAll(/^\s*(?:export\s+|local\s+|readonly\s+)?([A-Z_][A-Z0-9_]*)=/gm)].map(m => m[1])
  );
  const read = new Set([...MONADIC_SH.matchAll(/\$\{?([A-Z_][A-Z0-9_]*)/g)].map(m => m[1]));
  // Read by name through read_cfg_bool / loops over PY_OPTIONS.
  const pyOptions = MONADIC_SH.match(/^PY_OPTIONS=\(([^)]*)\)/m);
  if (pyOptions) pyOptions[1].trim().split(/\s+/).forEach(name => read.add(name));
  for (const file of composeFiles(path.join(ROOT, 'docker/services'))) {
    for (const m of fs.readFileSync(file, 'utf8').matchAll(/\$\{([A-Z_][A-Z0-9_]*)/g)) read.add(m[1]);
  }
  return [...read].filter(name => name.length > 1 && !assigned.has(name) && !SET_BY_THE_SCRIPTS.has(name)
    && !/^(COMPOSE_|BUILD_RESULT|LATEX_OK|PACKAGE_JSON|SERVICE_NAME)|_DOCKERFILE_CHANGED$/.test(name));
}

describe('the environment passed to monadic.sh', () => {
  test('covers every setting the scripts read from their environment', () => {
    const missing = readFromEnvironment().filter(name => !MONADIC_SH_ENV.includes(name));
    expect(missing).toEqual([]);
  });

  test('lists nothing that looks like a secret', () => {
    expect(MONADIC_SH_ENV.filter(name => /KEY|TOKEN|SECRET|PASS/.test(name))).toEqual([]);
  });

  test('drops API keys and references from the env file', () => {
    const env = monadicShEnv({
      OPENAI_API_KEY: 'fake-key', XAI_API_KEY: 'op://Vault/Item/credential', TAVILY_API_KEY: 'fake',
      PRIVACY_LANGS: 'en,ja', INSTALL_LATEX: 'true', DISTRIBUTED_MODE: 'off'
    });
    expect(env).toEqual({ PRIVACY_LANGS: 'en,ja', INSTALL_LATEX: 'true' });
  });
});
