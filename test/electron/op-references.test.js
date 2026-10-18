// 1Password references in config/env are read on the host by the app. These
// cases run the real reader against a stand-in op CLI (a script; no 1Password
// is involved) and pin: one `op inject` for all references, per-key reads only
// to explain a failure, failures reported as codes (op's message, which can
// repeat the reference, is never passed on), and values kept for the app run.
const fs = require('fs');
const os = require('os');
const path = require('path');

const {
  isReference, injectCall, referencesIn, opCandidates, isRunnable, locateOp, run, classify, startedAtFrom,
  resolveReferences, SecretCache
} = require('../../app/op_references');

// A fake op: `inject` replaces each `{{ op://V/ITEM/f }}` in the template on
// stdin with `value-ITEM`, as op does, and fails when an item is "missing",
// with the reference in the message. A file named "locked" beside it makes
// every call fail as not signed in. Like op 2.41, it takes stdin only from
// a pipe (a child of Node gets a socket). Each call's command is appended to
// calls.log beside it, and its whole argv to argv.log. (Files, not
// environment variables: changes to process.env in a test do not reach
// spawned children.)
const FAKE_OP = `#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const here = path.dirname(process.argv[1]);
const [cmd] = process.argv.slice(2);
fs.appendFileSync(path.join(here, 'calls.log'), cmd + '\\n');
fs.appendFileSync(path.join(here, 'argv.log'), process.argv.slice(2).join(' ') + '\\n');
if (process.platform !== 'win32' && !fs.fstatSync(0).isFIFO()) {
  process.stderr.write('[ERROR] expected data on stdin but none found');
  process.exit(1);
}
const input = fs.readFileSync(0, 'utf8');
const item = ref => ref.split('/')[3];
if (fs.existsSync(path.join(here, 'locked'))) {
  process.stderr.write('[ERROR] You are not currently signed in. Please run op signin');
  process.exit(1);
}
if (cmd === 'inject') {
  const out = input.replace(/\\{\\{\\s*(op:\\/\\/[^}\\s]+)\\s*\\}\\}/g, (_m, ref) => {
    if (item(ref) === 'missing') {
      process.stderr.write('[ERROR] "' + ref + '" isn\\'t an item');
      process.exit(1);
    }
    const special = { multiline: 'first\\nsecond', trailingcr: 'end\\r', cronly: '\\r' };
    return special[item(ref)] !== undefined ? special[item(ref)] : 'value-' + item(ref);
  });
  process.stdout.write(out);
} else {
  process.stderr.write('[ERROR] unexpected command ' + cmd);
  process.exit(1);
}
`;

let dir;
let op;
let log;
const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter(Boolean) : []);

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'op-refs-'));
  op = path.join(dir, 'op');
  log = path.join(dir, 'calls.log');
  fs.writeFileSync(op, FAKE_OP, { mode: 0o755 });
});

afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

const REFS = {
  OPENAI_API_KEY: 'op://Test/OPENAI/credential',
  GEMINI_API_KEY: 'op://Test/GEMINI/credential'
};

describe('finding references', () => {
  test('only values that start with op:// are references', () => {
    expect(isReference('op://Test/A/credential')).toBe(true);
    expect(isReference('sk-plain-value')).toBe(false);
    expect(isReference(' op://Test/A/credential')).toBe(false);
    expect(isReference(undefined)).toBe(false);
    expect(referencesIn({ A_API_KEY: 'op://Test/A/credential', B_API_KEY: 'plain', DISTRIBUTED_MODE: 'off' }))
      .toEqual({ A_API_KEY: 'op://Test/A/credential' });
  });

  test('looks beyond PATH for op, since a GUI app does not inherit the shell PATH', () => {
    const mac = opCandidates('darwin', { PATH: '/usr/bin' });
    expect(mac).toEqual(expect.arrayContaining(['/usr/bin/op', '/opt/homebrew/bin/op', '/usr/local/bin/op']));
    expect(opCandidates('darwin', { MONADIC_OP_CLI: '/x/op' })).toEqual(['/x/op']);
    expect(locateOp(['/nope/op', op])).toBe(op);
    expect(locateOp(['/nope/op'])).toBeNull();
  });

  test('skips a candidate it may not run and takes the next one', () => {
    const stray = path.join(dir, 'stray-op');
    fs.writeFileSync(stray, '', { mode: 0o644 });
    expect(isRunnable(stray, 'darwin')).toBe(false);
    expect(isRunnable(dir, 'darwin')).toBe(false);
    expect(isRunnable(op, 'darwin')).toBe(true);
    expect(locateOp([stray, dir, op])).toBe(op);
  });
});

describe('talking to monadic.sh', () => {
  test('gives up on a command that does not answer, instead of waiting for ever', async () => {
    const stuck = path.join(dir, 'stuck');
    fs.writeFileSync(stuck, '#!/bin/sh\nsleep 30\n', { mode: 0o755 });
    const started = Date.now();
    const result = await run(stuck, [], 'payload', 300);
    expect(result.code).toBe(-1);
    expect(classify(result.stderr)).toBe('timeout');
    expect(Date.now() - started).toBeLessThan(5000);
  });

  test('takes only a Docker timestamp from a successful call as the container start', () => {
    const at = '2026-10-04T13:45:01.123456789Z';
    expect(startedAtFrom({ code: 0, stdout: `${at}\n` })).toBe(at);
    expect(startedAtFrom({ code: 0, stdout: `${at}\r\n` })).toBe(at);
    expect(startedAtFrom({ code: 0, stdout: `Welcome to Ubuntu\n${at}\n` })).toBe(at);
    expect(startedAtFrom({ code: 0, stdout: '' })).toBeNull();
    expect(startedAtFrom({ code: 1, stdout: `${at}\n` })).toBeNull();
    expect(startedAtFrom({ code: -1, stdout: '' })).toBeNull();
    expect(startedAtFrom({ code: 0, stdout: 'Error: No such object\n' })).toBeNull();
    expect(startedAtFrom({ code: 0, stdout: `${at}\nsomething after\n` })).toBeNull();
  });
});

describe('the op inject command', () => {
  test('hands the template to op through a pipe, with op\'s path as an argument', () => {
    const [cmd, args] = injectCall('/opt/op dir/op', 'darwin');
    expect(cmd).toBe('/bin/sh');
    expect(args[0]).toBe('-c');
    expect(args[2]).toBe('/opt/op dir/op');
    expect(args[1]).not.toContain('/opt/op dir/op');
    expect(injectCall('/opt/op', 'linux')[0]).toBe('/bin/sh');
  });

  test('runs op directly on Windows', () => {
    expect(injectCall('C:\\op.exe', 'win32')).toEqual(['C:\\op.exe', ['inject']]);
  });

  test('stops op itself, not only the shell, at the timeout', async () => {
    if (process.platform === 'win32') return;
    const stuck = path.join(dir, 'stuck-op');
    fs.writeFileSync(stuck, '#!/bin/sh\necho $$ > "$(dirname "$0")/stuck.pid"\nexec sleep 30\n', { mode: 0o755 });
    const [cmd, args] = injectCall(stuck);
    const result = await run(cmd, args, 'payload', 500);
    expect(classify(result.stderr)).toBe('timeout');
    const pid = Number(fs.readFileSync(path.join(dir, 'stuck.pid'), 'utf8'));
    await new Promise(resolve => setTimeout(resolve, 300));
    expect(() => process.kill(pid, 0)).toThrow();
  });
});

describe('reading references', () => {
  test('reads every reference with a single op inject', async () => {
    const { values, failures } = await resolveReferences(REFS, { op });
    expect(values).toEqual({ OPENAI_API_KEY: 'value-OPENAI', GEMINI_API_KEY: 'value-GEMINI' });
    expect(failures).toEqual({});
    expect(calls()).toEqual(['inject']);
  });

  test('when one fails, reads each on its own to tell which, and keeps the rest', async () => {
    const refs = { ...REFS, XAI_API_KEY: 'op://Test/missing/credential' };
    const { values, failures } = await resolveReferences(refs, { op });
    expect(values).toEqual({ OPENAI_API_KEY: 'value-OPENAI', GEMINI_API_KEY: 'value-GEMINI' });
    expect(failures).toEqual({ XAI_API_KEY: 'notFound' });
    expect(calls()).toEqual(['inject', 'inject', 'inject', 'inject']);
  });

  test('keeps a value that spans lines whole, in one read and in the per-key reads', async () => {
    const refs = { ...REFS, SERVICE_PASSWORD: 'op://Test/multiline/password' };
    const together = await resolveReferences(refs, { op });
    expect(together.values.SERVICE_PASSWORD).toBe('first\nsecond');
    expect(together.values.OPENAI_API_KEY).toBe('value-OPENAI');
    expect(calls()).toEqual(['inject']);

    const oneByOne = await resolveReferences({ ...refs, XAI_API_KEY: 'op://Test/missing/credential' }, { op });
    expect(oneByOne.values.SERVICE_PASSWORD).toBe('first\nsecond');
  });

  test('keeps a carriage return that belongs to the value', async () => {
    const refs = { A_PASSWORD: 'op://Test/trailingcr/password', B_PASSWORD: 'op://Test/cronly/password' };
    const together = await resolveReferences(refs, { op });
    expect(together.values).toEqual({ A_PASSWORD: 'end\r', B_PASSWORD: '\r' });
    const oneByOne = await resolveReferences({ ...refs, XAI_API_KEY: 'op://Test/missing/credential' }, { op });
    expect(oneByOne.values).toEqual({ A_PASSWORD: 'end\r', B_PASSWORD: '\r' });
  });

  test('never puts a reference in argv', async () => {
    const refs = { ...REFS, XAI_API_KEY: 'op://Test/missing/credential' };
    await resolveReferences(refs, { op });
    const argv = fs.readFileSync(path.join(dir, 'argv.log'), 'utf8');
    expect(argv.split('\n').filter(Boolean)).toEqual(['inject', 'inject', 'inject', 'inject']);
    expect(argv).not.toContain('op://');
  });

  test('reports a locked 1Password per key, with a code and not op\'s message', async () => {
    fs.writeFileSync(path.join(dir, 'locked'), '');
    const { values, failures } = await resolveReferences(REFS, { op });
    expect(values).toEqual({});
    expect(failures).toEqual({ OPENAI_API_KEY: 'notSignedIn', GEMINI_API_KEY: 'notSignedIn' });
  });

  test('reports every key when op is not installed, without running anything', async () => {
    const { values, failures } = await resolveReferences(REFS, { op: null });
    expect(values).toEqual({});
    expect(failures).toEqual({ OPENAI_API_KEY: 'opMissing', GEMINI_API_KEY: 'opMissing' });
    expect(calls()).toEqual([]);
  });

  test('a failure never carries the reference text', async () => {
    const refs = { XAI_API_KEY: 'op://SecretVault/missing/credential' };
    const result = await resolveReferences(refs, { op });
    expect(JSON.stringify(result)).not.toContain('SecretVault');
    expect(classify('[ERROR] "op://SecretVault/x/y" isn\'t an item')).toBe('notFound');
  });
});

describe('keeping values for the app run', () => {
  test('reads once, then serves the same values without running op', async () => {
    const resolver = jest.fn(refs => resolveReferences(refs, { op }));
    const cache = new SecretCache({ resolver });
    const first = await cache.ensure(REFS);
    const second = await cache.ensure({ ...REFS });
    expect(first.fresh).toBe(true);
    expect(second.fresh).toBe(false);
    expect(resolver).toHaveBeenCalledTimes(1);
    expect(JSON.parse(cache.payload())).toEqual({ OPENAI_API_KEY: 'value-OPENAI', GEMINI_API_KEY: 'value-GEMINI' });
  });

  test('reads again when the references change or the last read was incomplete', async () => {
    const resolver = jest.fn(refs => resolveReferences(refs, { op }));
    const cache = new SecretCache({ resolver });
    await cache.ensure({ XAI_API_KEY: 'op://Test/missing/credential' });
    expect(cache.needsRead({ XAI_API_KEY: 'op://Test/missing/credential' })).toBe(true);
    await cache.ensure(REFS);
    expect(cache.needsRead(REFS)).toBe(false);
    expect(cache.needsRead({ OPENAI_API_KEY: 'op://Test/OTHER/credential' })).toBe(true);
    expect(resolver).toHaveBeenCalledTimes(2);
  });

  test('clear() drops the values', async () => {
    const cache = new SecretCache({ resolver: refs => resolveReferences(refs, { op }) });
    await cache.ensure(REFS);
    cache.clear();
    expect(cache.hasValues()).toBe(false);
    expect(cache.payload()).toBe('{}');
  });
});
