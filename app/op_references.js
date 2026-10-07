'use strict';

// Values in ~/monadic/config/env may be 1Password references
// (`OPENAI_API_KEY=op://Vault/Item/field`) instead of the secret itself.
//
// The Ruby container reads config/env but has no op CLI, so the app reads the
// references here, on the host, and streams the results into the container's
// memory-only mount (`monadic.sh deliver-secrets`). The results stay in this
// process's memory until the app quits. They are never written to a file,
// passed in argv or in a child's environment, or printed; neither is the
// reference text, which names the vault and item. Messages carry the key
// name and a reason code only.

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const REFERENCE = /^op:\/\//;
const OP_TIMEOUT_MS = 120000; // leaves time to answer a Touch ID / Hello prompt

function isReference(value) {
  return typeof value === 'string' && REFERENCE.test(value);
}

// { KEY: 'op://...' } for the entries of a parsed env file that are references.
function referencesIn(envConfig) {
  const refs = {};
  for (const [key, value] of Object.entries(envConfig || {})) {
    if (isReference(value)) refs[key] = value;
  }
  return refs;
}

// A GUI app does not inherit the login shell's PATH, so the usual install
// locations are tried as well. MONADIC_OP_CLI names the binary outright.
function opCandidates(platform = process.platform, env = process.env) {
  if (env.MONADIC_OP_CLI) return [env.MONADIC_OP_CLI];
  const exe = platform === 'win32' ? 'op.exe' : 'op';
  const dirs = (env.PATH || env.Path || '').split(path.delimiter).filter(Boolean);
  if (platform === 'darwin') dirs.push('/opt/homebrew/bin', '/usr/local/bin');
  if (platform === 'linux') dirs.push('/usr/bin', '/usr/local/bin', '/snap/bin');
  if (platform === 'win32') {
    if (env.LOCALAPPDATA) dirs.push(path.join(env.LOCALAPPDATA, 'Microsoft', 'WinGet', 'Links'));
    if (env.ProgramFiles) dirs.push(path.join(env.ProgramFiles, '1Password CLI'));
  }
  return [...new Set(dirs)].map(dir => path.join(dir, exe));
}

// A candidate counts only if it is a file this process may run, so a stray
// non-executable `op` earlier on PATH does not hide a working one later.
function isRunnable(file, platform = process.platform) {
  try {
    if (!fs.statSync(file).isFile()) return false;
    if (platform !== 'win32') fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function locateOp(candidates = opCandidates(), runnable = isRunnable) {
  return candidates.find(candidate => runnable(candidate)) || null;
}

// Runs a command with input on stdin. No shell, so nothing is interpreted.
function run(cmd, args, input, timeoutMs = OP_TIMEOUT_MS) {
  return new Promise(resolve => {
    let stdout = '';
    let stderr = '';
    let settled = false;
    const finish = result => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(result);
    };
    let child;
    try {
      child = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    } catch (error) {
      finish({ code: -1, stdout: '', stderr: String(error && error.message) });
      return;
    }
    const timer = setTimeout(() => {
      child.kill();
      finish({ code: -1, stdout: '', stderr: 'timeout' });
    }, timeoutMs);
    child.stdout.on('data', d => { stdout += d.toString(); });
    child.stderr.on('data', d => { stderr += d.toString(); });
    child.on('error', error => finish({ code: -1, stdout: '', stderr: String(error && error.message) }));
    child.on('close', code => finish({ code, stdout, stderr }));
    child.stdin.on('error', () => {});
    child.stdin.end(input || '');
  });
}

// A reason code for a failed op call. op's own message is not shown: it can
// repeat the reference.
function classify(stderr) {
  const text = String(stderr || '').toLowerCase();
  if (text === 'timeout') return 'timeout';
  if (/not (currently )?signed in|sign in|session expired|no accounts|locked/.test(text)) return 'notSignedIn';
  if (/dismiss|cancel|denied|authorization/.test(text)) return 'cancelled';
  if (/isn't (an item|a vault|a field)|not found|could not find|no item|invalid secret reference|invalid reference/.test(text)) return 'notFound';
  return 'failed';
}

// Reads every reference with one `op inject`, so 1Password asks at most once.
// op inject fails as a whole when any reference fails; only then is each one
// read on its own, to tell which keys failed and why.
async function resolveReferences(refs, { op = locateOp(), runner = run } = {}) {
  const keys = Object.keys(refs);
  const values = {};
  const failures = {};
  if (keys.length === 0) return { values, failures };
  if (!op) {
    for (const key of keys) failures[key] = 'opMissing';
    return { values, failures };
  }

  const template = keys.map(key => `${key}={{ ${refs[key]} }}\n`).join('');
  const all = await runner(op, ['inject'], template);
  if (all.code === 0) {
    for (const line of all.stdout.split('\n')) {
      const eq = line.indexOf('=');
      if (eq <= 0) continue;
      const key = line.slice(0, eq);
      const value = line.slice(eq + 1).replace(/\r$/, '');
      if (refs[key] && value) values[key] = value;
    }
    for (const key of keys) if (!values[key]) failures[key] = 'failed';
    return { values, failures };
  }

  for (const key of keys) {
    const one = await runner(op, ['read', '--no-newline', refs[key]], '');
    if (one.code === 0 && one.stdout) values[key] = one.stdout;
    else failures[key] = classify(one.stderr);
  }
  return { values, failures };
}

// The Ruby container's start time from `monadic.sh ruby-started-at`, or null.
// It identifies one start of the container, so anything else on stdout (a
// failed command, a shell banner from WSL) must not be taken for it. Only the
// last line is considered, and only a Docker timestamp is accepted.
const STARTED_AT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;
function startedAtFrom({ code, stdout } = {}) {
  if (code !== 0) return null;
  const lines = String(stdout || '').split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const last = lines[lines.length - 1];
  return last && STARTED_AT.test(last) ? last : null;
}

// Resolved values for the app's lifetime. Read again only when the set of
// references changes or the last attempt left some keys unresolved.
class SecretCache {
  constructor({ resolver = resolveReferences } = {}) {
    this.resolver = resolver;
    this.signature = null;
    this.values = {};
    this.failures = {};
    this.deliveredFor = null;
  }

  static signatureOf(refs) {
    return JSON.stringify(Object.keys(refs).sort().map(key => [key, refs[key]]));
  }

  // Whether ensure(refs) would run op.
  needsRead(refs) {
    const complete = Object.keys(this.failures).length === 0;
    return !(SecretCache.signatureOf(refs) === this.signature && complete);
  }

  // Returns { values, failures, fresh } where fresh tells whether op ran.
  async ensure(refs) {
    const signature = SecretCache.signatureOf(refs);
    if (!this.needsRead(refs)) {
      return { values: this.values, failures: this.failures, fresh: false };
    }
    const { values, failures } = await this.resolver(refs);
    this.signature = signature;
    this.values = values;
    this.failures = failures;
    this.deliveredFor = null;
    return { values, failures, fresh: true };
  }

  hasValues() {
    return Object.keys(this.values).length > 0;
  }

  // The payload for the container: JSON, so no value needs escaping.
  payload() {
    return JSON.stringify(this.values);
  }

  clear() {
    this.signature = null;
    this.values = {};
    this.failures = {};
    this.deliveredFor = null;
  }
}

module.exports = {
  isReference,
  referencesIn,
  opCandidates,
  isRunnable,
  locateOp,
  run,
  classify,
  startedAtFrom,
  resolveReferences,
  SecretCache
};
