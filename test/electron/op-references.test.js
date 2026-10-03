// 1Password references in config/env are read on the host by the app. These
// cases run the real reader against a stand-in op CLI (a script; no 1Password
// is involved) and pin: one `op inject` for all references, per-key reads only
// to explain a failure, failures reported as codes (op's message, which can
// repeat the reference, is never passed on), and values kept for the app run.
const fs = require('fs');
const os = require('os');
const path = require('path');

const {
  isReference, referencesIn, opCandidates, locateOp, classify, resolveReferences, SecretCache
} = require('../../app/op_references');

// A fake op: `inject` turns `KEY={{ op://V/ITEM/f }}` lines into
// `KEY=value-ITEM`; `read` prints `value-ITEM`. A reference whose item is
// "missing" fails the way op does, with the reference in the message.
// A file named "locked" beside it makes every call fail as not signed in.
// Each call is appended to calls.log beside it. (Files, not environment
// variables: changes to process.env in a test do not reach spawned children.)
const FAKE_OP = `#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const here = path.dirname(process.argv[1]);
const [cmd, ...rest] = process.argv.slice(2);
fs.appendFileSync(path.join(here, 'calls.log'), cmd + '\\n');
const input = fs.readFileSync(0, 'utf8');
const item = ref => ref.split('/')[3];
if (fs.existsSync(path.join(here, 'locked'))) {
  process.stderr.write('[ERROR] You are not currently signed in. Please run op signin');
  process.exit(1);
}
if (cmd === 'inject') {
  const out = [];
  for (const line of input.split('\\n').filter(Boolean)) {
    const [key, tpl] = line.split('=');
    const ref = tpl.replace(/[{} ]/g, '');
    if (item(ref) === 'missing') {
      process.stderr.write('[ERROR] "' + ref + '" isn\\'t an item');
      process.exit(1);
    }
    out.push(key + '=value-' + item(ref));
  }
  process.stdout.write(out.join('\\n') + '\\n');
} else if (cmd === 'read') {
  const ref = rest[rest.length - 1];
  if (item(ref) === 'missing') {
    process.stderr.write('[ERROR] "' + ref + '" isn\\'t an item in vault Private');
    process.exit(1);
  }
  process.stdout.write('value-' + item(ref));
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
    expect(calls()).toEqual(['inject', 'read', 'read', 'read']);
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
