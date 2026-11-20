// The Settings key check sends a key to its provider and answers with status
// codes and default model ids only.
const fs = require('fs');
const { URL } = require('url');
const path = require('path');
const keyCheck = require('../../app/key_check');
const opReferences = require('../../app/op_references');

const KEY = 'sk-test-key-check-0123456789';
const EXPECTED_HOSTS = {
  OPENAI_API_KEY: 'api.openai.com',
  ANTHROPIC_API_KEY: 'api.anthropic.com',
  GEMINI_API_KEY: 'generativelanguage.googleapis.com',
  MISTRAL_API_KEY: 'api.mistral.ai',
  XAI_API_KEY: 'api.x.ai',
  DEEPSEEK_API_KEY: 'api.deepseek.com',
  COHERE_API_KEY: 'api.cohere.com',
  ELEVENLABS_API_KEY: 'api.elevenlabs.io',
  TAVILY_API_KEY: 'api.tavily.com'
};

const DEFAULTS = {
  openai: { chat: ['gpt-a', 'gpt-b'], image: ['img-a'], tts: ['tts-a'] },
  anthropic: { chat: ['claude-a'], code: ['claude-a'] },
  gemini: { chat: ['gem-a'], video: ['vid-a'] },
  mistral: { chat: ['mis-a'] },
  xai: { chat: ['grok-a'], tts: ['grok-tts'], audio_transcription: ['xai-stt'] },
  deepseek: { chat: ['ds-a'] },
  cohere: { chat: ['co-a'] }
};

function response(status, body) {
  const text = typeof body === 'string' ? body : JSON.stringify(body);
  return { status, body: null, text: async () => text };
}

// Records every request; answers from a list in order.
function fakeFetch(answers) {
  const calls = [];
  const impl = async (url, options) => {
    calls.push({ url, options });
    const next = answers.shift();
    if (next instanceof Error) throw next;
    return next || response(500, '');
  };
  return { impl, calls };
}

// Where each provider's request goes and where the key sits in it.
function requestViolations(table) {
  const problems = [];
  for (const [envKey, spec] of Object.entries(table)) {
    const url = new URL(spec.url);
    if (url.protocol !== 'https:') problems.push(`${envKey}: not https`);
    if (url.hostname !== EXPECTED_HOSTS[envKey]) problems.push(`${envKey}: host ${url.hostname}`);
    if (spec.url.includes(KEY)) problems.push(`${envKey}: key in URL`);
    const headers = spec.headers(KEY);
    if (!Object.values(headers).some(v => String(v).includes(KEY))) problems.push(`${envKey}: key not in a header`);
  }
  if (Object.keys(table).sort().join() !== Object.keys(EXPECTED_HOSTS).sort().join()) problems.push('key names differ');
  return problems;
}

describe('provider table', () => {
  test('every key goes over https to its own provider, in a header only', () => {
    expect(requestViolations(keyCheck.PROVIDERS)).toEqual([]);
  });

  test('the check above catches a changed host or a key moved into the URL', () => {
    const movedHost = { ...keyCheck.PROVIDERS, OPENAI_API_KEY: { ...keyCheck.PROVIDERS.OPENAI_API_KEY, url: 'https://example.com/v1/models' } };
    const keyInUrl = { ...keyCheck.PROVIDERS, GEMINI_API_KEY: { ...keyCheck.PROVIDERS.GEMINI_API_KEY, url: `https://generativelanguage.googleapis.com/v1beta/models?key=${KEY}`, headers: () => ({}) } };
    expect(requestViolations(movedHost)).toEqual(['OPENAI_API_KEY: host example.com']);
    expect(requestViolations(keyInUrl)).toEqual(['GEMINI_API_KEY: key in URL', 'GEMINI_API_KEY: key not in a header']);
  });

  test.each(Object.keys(EXPECTED_HOSTS))('%s sends one GET to the table URL with the key in a header, without following redirects', async (envKey) => {
    const { impl, calls } = fakeFetch([response(200, { data: [], models: [] })]);
    await keyCheck.checkKey({ envKey, key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe(keyCheck.PROVIDERS[envKey].url);
    expect(calls[0].url).not.toContain(KEY);
    expect(calls[0].options.method).toBe('GET');
    expect(calls[0].options.redirect).toBe('manual');
    expect(Object.values(calls[0].options.headers).join(' ')).toContain(KEY);
  });

  test('a name outside the table is refused before any request', async () => {
    const { impl, calls } = fakeFetch([]);
    for (const envKey of ['TAVILY', 'OPENAI_DEFAULT_MODEL', '__proto__', 'constructor', '']) {
      expect(await keyCheck.checkKey({ envKey, key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl })).toEqual({ status: 'unsupported' });
    }
    expect(calls).toHaveLength(0);
  });

  test.each(['', ' sk-x', 'sk-x\nX-Other: 1', 'sk\u0000x', 'x'.repeat(1001)])('a key text like %j is not sent', async (key) => {
    const { impl, calls } = fakeFetch([]);
    const answer = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer.status).toBe('invalidInput');
    expect(calls).toHaveLength(0);
  });
});

describe('key status', () => {
  test.each([
    [301, 'unexpected'], [302, 'unexpected'], [401, 'rejected'], [498, 'rejected'], [403, 'forbidden'],
    [429, 'rateLimited'], [500, 'serviceError'], [503, 'serviceError'], [404, 'unexpected']
  ])('HTTP %i is %s, with no second request', async (code, status) => {
    const { impl, calls } = fakeFetch([response(code, ''), response(200, { data: [] })]);
    const answer = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer.status).toBe(status);
    expect(calls).toHaveLength(1);
    expect(answer.models.every(m => m.result === 'unknown')).toBe(true);
  });

  test.each([
    ['GEMINI_API_KEY', { error: { code: 400, status: 'INVALID_ARGUMENT', details: [{ reason: 'API_KEY_INVALID' }] } }],
    ['XAI_API_KEY', { code: 'invalid-argument', error: `Incorrect API key provided: ${KEY.slice(0, 6)}***` }]
  ])('%s marks an invalid key with a 400, read as rejected without its text', async (envKey, body) => {
    const { impl } = fakeFetch([response(400, body)]);
    const answer = await keyCheck.checkKey({ envKey, key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer.status).toBe('rejected');
    expect(JSON.stringify(answer)).not.toContain(KEY.slice(0, 6));
  });

  test.each([
    ['GEMINI_API_KEY', { error: { code: 400, status: 'INVALID_ARGUMENT', details: [{ reason: 'OTHER' }] } }],
    ['XAI_API_KEY', { code: 'invalid-argument', error: 'Bad request' }],
    ['OPENAI_API_KEY', { error: { message: 'Incorrect API key provided' } }],
    ['GEMINI_API_KEY', 'not json']
  ])('other 400 answers from %s stay unexpected', async (envKey, body) => {
    const { impl } = fakeFetch([response(400, body)]);
    const answer = await keyCheck.checkKey({ envKey, key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer.status).toBe('unexpected');
  });

  test('a rejection that quotes the key returns no provider text, and nothing is logged', async () => {
    const spies = ['log', 'error', 'warn', 'info'].map(m => jest.spyOn(console, m).mockImplementation(() => {}));
    try {
      const body = { error: { message: `Incorrect API key provided: ${KEY.slice(0, 8)}...${KEY.slice(-4)}` } };
      const { impl } = fakeFetch([response(401, body)]);
      const answer = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
      const text = JSON.stringify(answer);
      expect(text).not.toContain(KEY.slice(0, 8));
      expect(text).not.toContain(KEY.slice(-4));
      expect(text).not.toContain('Incorrect');
      spies.forEach(spy => expect(spy).not.toHaveBeenCalled());
    } finally {
      spies.forEach(spy => spy.mockRestore());
    }
  });

  test('a network failure is unreachable and its message is not returned', async () => {
    const { impl } = fakeFetch([new Error(`connect failed with header ${KEY}`)]);
    const answer = await keyCheck.checkKey({ envKey: 'DEEPSEEK_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer.status).toBe('unreachable');
    expect(JSON.stringify(answer)).not.toContain(KEY);
  });

  test('a provider that does not answer in time is a timeout, body read included', async () => {
    const slow = (url, { signal }) => new Promise((resolve, reject) => {
      signal.addEventListener('abort', () => reject(new Error('aborted')));
    });
    const answer = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: slow, limits: { totalMs: 20 } });
    expect(answer.status).toBe('timeout');

    const slowBody = async (url, { signal }) => ({
      status: 200,
      body: null,
      text: () => new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(new Error('aborted'))))
    });
    const answer2 = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: slowBody, limits: { totalMs: 20 } });
    expect(answer2.status).toBe('timeout');
  });

  test.each([
    ['HTML', '<html>login</html>'],
    ['JSON of another shape', { items: [] }],
    ['a JSON string', '"ok"']
  ])('a 200 with %s is unexpected, not an empty list', async (_name, body) => {
    const { impl } = fakeFetch([response(200, body)]);
    const answer = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer.status).toBe('unexpected');
    expect(answer.models.every(m => m.result === 'unknown')).toBe(true);
  });

  test('a body over the size limit is not read whole', async () => {
    const { Buffer } = require('buffer');
    const chunks = [Buffer.alloc(600), Buffer.alloc(600)];
    let cancelled = false;
    const big = async () => ({
      status: 200,
      body: { getReader: () => ({ read: async () => (chunks.length ? { done: false, value: chunks.shift() } : { done: true }), cancel: async () => { cancelled = true; } }) }
    });
    const answer = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: big, limits: { maxBodyBytes: 1000 } });
    expect(answer.status).toBe('unexpected');
    expect(cancelled).toBe(true);
  });

  test.each(['ELEVENLABS_API_KEY', 'TAVILY_API_KEY'])('%s answers the key status only', async (envKey) => {
    const { impl } = fakeFetch([response(200, { anything: 'private account data' })]);
    const answer = await keyCheck.checkKey({ envKey, key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer).toEqual({ provider: keyCheck.PROVIDERS[envKey].provider, status: 'accepted' });
  });
});

describe('default models', () => {
  test('each category default is matched exactly against the list', async () => {
    const { impl } = fakeFetch([response(200, { data: [{ id: 'gpt-a' }, { id: 'tts-a-2025' }, { id: 'img-a' }] })]);
    const answer = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer).toMatchObject({ status: 'accepted', complete: true });
    expect(answer.models).toEqual([
      { category: 'chat', model: 'gpt-a', source: 'default', result: 'listed' },
      { category: 'image', model: 'img-a', source: 'default', result: 'listed' },
      { category: 'tts', model: 'tts-a', source: 'default', result: 'notListed' }
    ]);
  });

  test('the chat default set in config/env is used and named', async () => {
    const { impl } = fakeFetch([response(200, { data: [{ id: 'gpt-b' }] })]);
    const answer = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, env: { OPENAI_DEFAULT_MODEL: ' gpt-b ' }, fetchImpl: impl });
    expect(answer.models[0]).toEqual({ category: 'chat', model: 'gpt-b', source: 'env', envName: 'OPENAI_DEFAULT_MODEL', result: 'listed' });
    const blank = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, env: { OPENAI_DEFAULT_MODEL: '  ' }, fetchImpl: fakeFetch([response(200, { data: [] })]).impl });
    expect(blank.models[0].model).toBe('gpt-a');
  });

  test('Gemini names lose only their models/ prefix', async () => {
    const { impl } = fakeFetch([response(200, { models: [{ name: 'models/gem-a' }, { name: 'vid-a' }] })]);
    const answer = await keyCheck.checkKey({ envKey: 'GEMINI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer.models.map(m => m.result)).toEqual(['listed', 'listed']);
  });

  test('Mistral aliases count as listed', async () => {
    const { impl } = fakeFetch([response(200, { data: [{ id: 'mis-a-2603', aliases: ['mis-a'] }] })]);
    const answer = await keyCheck.checkKey({ envKey: 'MISTRAL_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer.models[0].result).toBe('listed');
  });

  test('xAI voice and transcription models are not judged from the list', async () => {
    const { impl } = fakeFetch([response(200, { data: [{ id: 'grok-a' }] })]);
    const answer = await keyCheck.checkKey({ envKey: 'XAI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(answer.models.map(m => [m.category, m.result])).toEqual([['chat', 'listed'], ['tts', 'notCheckable'], ['audio_transcription', 'notCheckable']]);
  });

  test('pages are followed with the cursor on the table URL', async () => {
    const { impl, calls } = fakeFetch([
      response(200, { data: [{ id: 'x' }], has_more: true, last_id: 'x' }),
      response(200, { data: [{ id: 'claude-a' }], has_more: false })
    ]);
    const answer = await keyCheck.checkKey({ envKey: 'ANTHROPIC_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: impl });
    expect(calls.map(c => c.url)).toEqual(['https://api.anthropic.com/v1/models?limit=1000', 'https://api.anthropic.com/v1/models?limit=1000&after_id=x']);
    expect(answer).toMatchObject({ status: 'accepted', complete: true });
    expect(answer.models.map(m => m.result)).toEqual(['listed', 'listed']);
  });

  test('a failed later page or a repeated cursor leaves models not found as unknown', async () => {
    const failed = fakeFetch([response(200, { models: [{ name: 'co-x' }], next_page_token: 'p2' }), response(500, '')]);
    const a = await keyCheck.checkKey({ envKey: 'COHERE_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: failed.impl });
    expect(a).toMatchObject({ status: 'accepted', complete: false });
    expect(a.models[0].result).toBe('unknown');

    const loop = fakeFetch([
      response(200, { models: [{ name: 'gem-a' }], nextPageToken: 't' }),
      response(200, { models: [], nextPageToken: 't' })
    ]);
    const b = await keyCheck.checkKey({ envKey: 'GEMINI_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: loop.impl });
    expect(loop.calls).toHaveLength(2);
    expect(b.models.map(m => m.result)).toEqual(['listed', 'unknown']);
  });

  test('page count is capped', async () => {
    let n = 0;
    const endless = async () => response(200, { data: [], has_more: true, last_id: `c${n++}` });
    const answer = await keyCheck.checkKey({ envKey: 'ANTHROPIC_API_KEY', key: KEY, providerDefaults: DEFAULTS, fetchImpl: endless, limits: { maxPages: 3 } });
    expect(n).toBe(3);
    expect(answer.complete).toBe(false);
  });

  test('missing defaults are reported, not filled in', async () => {
    const { impl } = fakeFetch([response(200, { data: [] })]);
    const answer = await keyCheck.checkKey({ envKey: 'OPENAI_API_KEY', key: KEY, providerDefaults: null, fetchImpl: impl });
    expect(answer).toMatchObject({ status: 'accepted', models: [], defaultsUnavailable: true });
  });

  test('the real providerDefaults give every checked provider a chat default', () => {
    const { providerDefaults } = require('../../docker/services/ruby/public/js/monadic/model_spec.js');
    for (const spec of Object.values(keyCheck.PROVIDERS).filter(s => !s.keyOnly)) {
      expect(keyCheck.defaultModels(spec.provider, providerDefaults)[0]).toMatchObject({ category: 'chat' });
    }
  });
});

describe('1Password references', () => {
  test('resolveOne makes one op call, with the reference on stdin, and does not retry', async () => {
    const calls = [];
    const runner = async (cmd, args, input) => { calls.push({ cmd, args, input }); return { code: 1, stdout: '', stderr: 'operation was cancelled by the user' }; };
    const result = await opReferences.resolveOne('op://Vault/Item/key', { op: '/usr/local/bin/op', runner, platform: 'darwin' });
    expect(result).toEqual({ failure: 'cancelled' });
    expect(calls).toHaveLength(1);
    expect(calls[0].input).toBe('{{ op://Vault/Item/key }}\n');
    expect(calls[0].args.join(' ')).not.toContain('Vault');
  });

  test.each(['op://V/I/f\n{{ op://V/I/g }}', 'op://V/I/f }} {{ op://V/I/g', 'sk-not-a-reference'])('resolveOne refuses %j without running op', async (ref) => {
    const runner = jest.fn();
    expect(await opReferences.resolveOne(ref, { op: '/usr/local/bin/op', runner })).toEqual({ failure: 'notFound' });
    expect(runner).not.toHaveBeenCalled();
  });

  test('lookup returns a value only for the same key and reference, and changes nothing', async () => {
    const cache = new opReferences.SecretCache({ resolver: async () => ({ values: { OPENAI_API_KEY: 'value-a' }, failures: {} }) });
    await cache.ensure({ OPENAI_API_KEY: 'op://V/I/a' });
    cache.deliveredFor = 'started';
    const before = JSON.stringify([cache.signature, cache.values, cache.failures, cache.deliveredFor]);
    expect(cache.lookup('OPENAI_API_KEY', 'op://V/I/a')).toBe('value-a');
    expect(cache.lookup('OPENAI_API_KEY', 'op://V/I/b')).toBeNull();
    expect(cache.lookup('XAI_API_KEY', 'op://V/I/a')).toBeNull();
    expect(JSON.stringify([cache.signature, cache.values, cache.failures, cache.deliveredFor])).toBe(before);
  });
});

// The IPC handler is taken from the real main.js and run with fakes.
describe('check-api-key handler', () => {
  const source = fs.readFileSync(path.join(__dirname, '../../app/main.js'), 'utf8');
  const block = source.match(/let keyCheckQueue = [\s\S]*?\nipcMain\.handle\('check-api-key'[\s\S]*?\n\}\);\n/);

  function load({ sender = true, cache, resolveOne, settings = {} } = {}) {
    let handler;
    const fakeIpc = { handle: (channel, fn) => { if (channel === 'check-api-key') handler = fn; } };
    const checks = [];
    const fakeKeyCheck = {
      PROVIDERS: keyCheck.PROVIDERS,
      checkKey: async (args) => { checks.push(args); return { status: 'accepted' }; }
    };
    const fakeOp = { isReference: opReferences.isReference, resolveOne: resolveOne || (async () => ({ value: 'resolved-value' })) };
    // eslint-disable-next-line no-new-func
    new Function('ipcMain', 'isSettingsSender', 'keyCheck', 'opReferences', 'secretCache', 'loadProviderDefaults', 'loadSettings', block[0])(
      fakeIpc, () => sender, fakeKeyCheck, fakeOp, cache || new opReferences.SecretCache(), () => DEFAULTS, () => settings
    );
    return { handler, checks };
  }

  test('is found in main.js', () => {
    expect(block).not.toBeNull();
  });

  test('answers nothing to a sender other than the Settings window', async () => {
    const resolveOne = jest.fn();
    const { handler, checks } = load({ sender: false, resolveOne });
    expect(await handler({}, { envKey: 'OPENAI_API_KEY', value: 'op://V/I/a' })).toBeNull();
    expect(resolveOne).not.toHaveBeenCalled();
    expect(checks).toHaveLength(0);
  });

  test('an unsaved reference is read for this check only and the shared values stay as they were', async () => {
    const cache = new opReferences.SecretCache({ resolver: async () => ({ values: { OPENAI_API_KEY: 'saved-value' }, failures: {} }) });
    await cache.ensure({ OPENAI_API_KEY: 'op://V/I/saved' });
    const before = JSON.stringify([cache.signature, cache.refs, cache.values, cache.failures, cache.deliveredFor]);
    const resolveOne = jest.fn(async () => ({ value: 'typed-value' }));
    const { handler, checks } = load({ cache, resolveOne });
    await handler({}, { envKey: 'OPENAI_API_KEY', value: 'op://V/I/typed' });
    expect(resolveOne).toHaveBeenCalledTimes(1);
    expect(checks[0].key).toBe('typed-value');
    expect(JSON.stringify([cache.signature, cache.refs, cache.values, cache.failures, cache.deliveredFor])).toBe(before);
  });

  test('the value already read for the same reference is reused without asking 1Password', async () => {
    const cache = new opReferences.SecretCache({ resolver: async () => ({ values: { OPENAI_API_KEY: 'saved-value' }, failures: {} }) });
    await cache.ensure({ OPENAI_API_KEY: 'op://V/I/saved' });
    const resolveOne = jest.fn();
    const { handler, checks } = load({ cache, resolveOne });
    await handler({}, { envKey: 'OPENAI_API_KEY', value: 'op://V/I/saved' });
    expect(resolveOne).not.toHaveBeenCalled();
    expect(checks[0].key).toBe('saved-value');
  });

  test('a failed read returns its reason code and sends nothing, not the reference', async () => {
    const { handler, checks } = load({ resolveOne: async () => ({ failure: 'cancelled' }) });
    expect(await handler({}, { envKey: 'OPENAI_API_KEY', value: 'op://V/I/a' })).toEqual({ status: 'opFailed', reason: 'cancelled' });
    expect(checks).toHaveLength(0);
  });

  test('refuses names outside the table and a second check of the same key while one runs', async () => {
    let release;
    const resolveOne = () => new Promise(resolve => { release = () => resolve({ value: 'v' }); });
    const { handler } = load({ resolveOne });
    expect(await handler({}, { envKey: 'PATH', value: 'x' })).toEqual({ status: 'unsupported' });
    const first = handler({}, { envKey: 'OPENAI_API_KEY', value: 'op://V/I/a' });
    expect(await handler({}, { envKey: 'OPENAI_API_KEY', value: 'op://V/I/a' })).toEqual({ status: 'busy' });
    await new Promise(r => setTimeout(r, 0));
    release();
    expect(await first).toEqual({ status: 'accepted' });
  });

  test('never writes the settings file', () => {
    expect(block[0]).not.toMatch(/writeEnvFile|saveSettings|secretCache\.ensure/);
  });
});
