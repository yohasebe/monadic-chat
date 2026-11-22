'use strict';

const { URL } = require('url');
const { Buffer } = require('buffer');

// Checks an API key from the Settings window against its provider's model
// list, and tells which of the provider's default models are in that list.
//
// The provider, URL and header come only from the table below, chosen by the
// env key name; nothing else from the caller decides where the key goes.
// The key travels in a header over https, redirects are not followed, and
// the caller gets back status codes and model ids from the defaults table
// only: never the key, the provider's response body or an error message,
// which can quote part of the key.

const bearer = key => ({ Authorization: `Bearer ${key}` });
const idsOf = field => list => (Array.isArray(list) ? list : []).map(m => m && m[field]).filter(id => typeof id === 'string');

// keyOnly providers answer whether the key is accepted, with no model list.
const PROVIDERS = {
  OPENAI_API_KEY: {
    provider: 'openai',
    url: 'https://api.openai.com/v1/models',
    headers: bearer,
    read: json => ({ ids: idsOf('id')(json.data), ok: Array.isArray(json.data) })
  },
  ANTHROPIC_API_KEY: {
    provider: 'anthropic',
    url: 'https://api.anthropic.com/v1/models?limit=1000',
    headers: key => ({ 'x-api-key': key, 'anthropic-version': '2023-06-01' }),
    read: json => ({ ids: idsOf('id')(json.data), ok: Array.isArray(json.data),
                     next: json.has_more && json.last_id ? ['after_id', json.last_id] : null })
  },
  GEMINI_API_KEY: {
    provider: 'gemini',
    url: 'https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000',
    headers: key => ({ 'x-goog-api-key': key }),
    // An invalid key is a 400 with this fixed reason.
    rejectedBody: json => Array.isArray(json.error && json.error.details) &&
      json.error.details.some(d => d && d.reason === 'API_KEY_INVALID'),
    read: json => ({ ids: idsOf('name')(json.models).map(n => n.replace(/^models\//, '')), ok: Array.isArray(json.models),
                     next: json.nextPageToken ? ['pageToken', json.nextPageToken] : null })
  },
  MISTRAL_API_KEY: {
    provider: 'mistral',
    url: 'https://api.mistral.ai/v1/models',
    headers: bearer,
    read: json => ({
      ids: (Array.isArray(json.data) ? json.data : []).flatMap(m => [m && m.id, ...((m && Array.isArray(m.aliases)) ? m.aliases : [])])
        .filter(id => typeof id === 'string'),
      ok: Array.isArray(json.data)
    })
  },
  XAI_API_KEY: {
    provider: 'xai',
    url: 'https://api.x.ai/v1/models',
    headers: bearer,
    // An invalid key is a 400 whose message says so; only the test is kept.
    rejectedBody: json => typeof json.error === 'string' && /^Incorrect API key/i.test(json.error),
    read: json => ({ ids: idsOf('id')(json.data), ok: Array.isArray(json.data) }),
    // Voice and transcription go through their own APIs, not this list.
    notListed: ['tts', 'audio_transcription']
  },
  DEEPSEEK_API_KEY: {
    provider: 'deepseek',
    url: 'https://api.deepseek.com/models',
    headers: bearer,
    read: json => ({ ids: idsOf('id')(json.data), ok: Array.isArray(json.data) })
  },
  COHERE_API_KEY: {
    provider: 'cohere',
    url: 'https://api.cohere.com/v1/models?page_size=1000',
    headers: bearer,
    read: json => ({ ids: idsOf('name')(json.models), ok: Array.isArray(json.models),
                     next: json.next_page_token ? ['page_token', json.next_page_token] : null })
  },
  ELEVENLABS_API_KEY: {
    provider: 'elevenlabs',
    url: 'https://api.elevenlabs.io/v1/user',
    headers: key => ({ 'xi-api-key': key }),
    keyOnly: true
  },
  TAVILY_API_KEY: {
    provider: 'tavily',
    url: 'https://api.tavily.com/usage',
    headers: bearer,
    keyOnly: true
  }
};

// The env name that overrides the chat default, per provider.
const CHAT_DEFAULT_ENV = {
  openai: 'OPENAI_DEFAULT_MODEL',
  anthropic: 'ANTHROPIC_DEFAULT_MODEL',
  gemini: 'GEMINI_DEFAULT_MODEL',
  mistral: 'MISTRAL_DEFAULT_MODEL',
  xai: 'GROK_DEFAULT_MODEL',
  deepseek: 'DEEPSEEK_DEFAULT_MODEL',
  cohere: 'COHERE_DEFAULT_MODEL'
};

const LIMITS = {
  totalMs: 20000,        // the whole check, body reads included
  maxPages: 10,
  maxBodyBytes: 8 * 1024 * 1024,
  maxKeyLength: 1000
};

// Status of the key, as the Settings window shows it.
//   accepted     the model list (or account) endpoint answered with data
//   rejected     the provider said the key is not valid (401, 498, or a
//                400 the provider marks as an invalid key)
//   forbidden    the key may be valid but cannot use this endpoint (403)
//   rateLimited  429
//   serviceError 5xx
//   timeout      no full answer in time
//   unreachable  network, DNS or TLS failure
//   unexpected   anything else (redirect, 404, not JSON, unknown shape)
function statusForHttp(code) {
  if (code === 401 || code === 498) return 'rejected';
  if (code === 403) return 'forbidden';
  if (code === 429) return 'rateLimited';
  if (code >= 500 && code <= 599) return 'serviceError';
  return 'unexpected';
}

function isValidKeyText(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= LIMITS.maxKeyLength &&
    value.trim() === value && !/[\u0000-\u001f\u007f]/.test(value);
}

// Reads at most maxBytes of the body; null when it is larger.
async function readCapped(response, maxBytes) {
  if (!response.body || typeof response.body.getReader !== 'function') {
    const text = await response.text();
    return Buffer.byteLength(text) > maxBytes ? null : text;
  }
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      try { await reader.cancel(); } catch (_) { /* nothing to do */ }
      return null;
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks).toString('utf8');
}

function withParam(url, name, value) {
  const u = new URL(url);
  u.searchParams.set(name, value);
  return u.toString();
}

// One GET. Returns { status } or { json }.
async function getJson(fetchImpl, url, headers, signal, maxBodyBytes, rejectedBody) {
  let response;
  try {
    response = await fetchImpl(url, { method: 'GET', headers, redirect: 'manual', signal });
  } catch (_) {
    return { status: signal.aborted ? 'timeout' : 'unreachable' };
  }
  if (response.status === 400 && rejectedBody) {
    // Some providers answer an invalid key with 400. The body is read here
    // only to tell that case apart and is not passed on.
    try {
      const text = await readCapped(response, maxBodyBytes);
      return { status: text !== null && rejectedBody(JSON.parse(text) || {}) ? 'rejected' : 'unexpected' };
    } catch (_) {
      return { status: signal.aborted ? 'timeout' : 'unexpected' };
    }
  }
  if (response.status < 200 || response.status > 299) {
    try { if (response.body && response.body.cancel) await response.body.cancel(); } catch (_) { /* ignore */ }
    return { status: statusForHttp(response.status) };
  }
  let text;
  try {
    text = await readCapped(response, maxBodyBytes);
  } catch (_) {
    return { status: signal.aborted ? 'timeout' : 'unreachable' };
  }
  if (text === null) return { status: 'unexpected' };
  try {
    const json = JSON.parse(text);
    if (!json || typeof json !== 'object') return { status: 'unexpected' };
    return { json };
  } catch (_) {
    return { status: 'unexpected' };
  }
}

// The provider's default model for each category in providerDefaults, with
// the chat default replaced by its env override when one is set.
function defaultModels(provider, providerDefaults, env = {}) {
  const table = (providerDefaults && providerDefaults[provider]) || {};
  const rows = [];
  for (const [category, list] of Object.entries(table)) {
    if (!Array.isArray(list) || typeof list[0] !== 'string') continue;
    let model = list[0];
    let source = 'default';
    const override = category === 'chat' && CHAT_DEFAULT_ENV[provider] ? env[CHAT_DEFAULT_ENV[provider]] : null;
    if (typeof override === 'string' && override.trim()) {
      model = override.trim();
      source = 'env';
    }
    rows.push(source === 'env' ? { category, model, source, envName: CHAT_DEFAULT_ENV[provider] } : { category, model, source });
  }
  return rows;
}

// Checks one key. Never throws; never returns the key or provider text.
async function checkKey({ envKey, key, providerDefaults, env = {}, fetchImpl = fetch, limits = {} }) {
  const spec = Object.prototype.hasOwnProperty.call(PROVIDERS, envKey) ? PROVIDERS[envKey] : null;
  if (!spec) return { status: 'unsupported' };
  if (!isValidKeyText(key)) return { provider: spec.provider, status: 'invalidInput' };
  const lim = { ...LIMITS, ...limits };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), lim.totalMs);
  try {
    const headers = spec.headers(key);
    if (spec.keyOnly) {
      const r = await getJson(fetchImpl, spec.url, headers, controller.signal, lim.maxBodyBytes, spec.rejectedBody);
      return { provider: spec.provider, status: r.status || 'accepted' };
    }

    const ids = new Set();
    let url = spec.url;
    let complete = false;
    let status = null;
    const seenCursors = new Set();
    for (let page = 0; page < lim.maxPages; page++) {
      const r = await getJson(fetchImpl, url, headers, controller.signal, lim.maxBodyBytes, spec.rejectedBody);
      if (r.status) {
        status = page === 0 ? r.status : 'accepted';
        break;
      }
      const { ids: pageIds, ok, next } = spec.read(r.json);
      if (!ok) {
        status = page === 0 ? 'unexpected' : 'accepted';
        break;
      }
      status = 'accepted';
      pageIds.forEach(id => ids.add(id));
      if (!next) { complete = true; break; }
      const [param, cursor] = next;
      if (typeof cursor !== 'string' || seenCursors.has(cursor)) break;
      seenCursors.add(cursor);
      url = withParam(spec.url, param, cursor);
    }

    const accepted = status === 'accepted';
    const notListed = spec.notListed || [];
    const models = defaultModels(spec.provider, providerDefaults, env).map(row => {
      let result;
      if (notListed.includes(row.category)) result = 'notCheckable';
      else if (!accepted) result = 'unknown';
      else if (ids.has(row.model)) result = 'listed';
      else result = complete ? 'notListed' : 'unknown';
      return { ...row, result };
    });
    return { provider: spec.provider, status, complete: accepted && complete, models, defaultsUnavailable: !providerDefaults };
  } catch (_) {
    return { provider: spec.provider, status: 'unexpected' };
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { PROVIDERS, CHAT_DEFAULT_ENV, LIMITS, checkKey, defaultModels, isValidKeyText, statusForHttp };
