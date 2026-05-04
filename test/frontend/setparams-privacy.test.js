/**
 * Privacy session toggle must round-trip through PRIVACY_TOGGLE only —
 * never piggyback on params. setParams() rebuilds params from scratch on
 * every submit; if it wrote privacy_session_enabled there, a stale UI
 * value could shadow the backend's health-checked authoritative state.
 *
 * Locks in three contracts:
 *   1. setParams() does not write params["privacy_session_enabled"].
 *   2. The broadcast clone in monadic.js does not include it either.
 *   3. The toggle change handler explicitly sends PRIVACY_TOGGLE via
 *      safeWsSend.
 */

const fs = require('fs');
const path = require('path');

function loadFile(rel) {
  return fs.readFileSync(path.join(__dirname, '..', '..', rel), 'utf8');
}

function extractFunctionBody(source, name) {
  const startRe = new RegExp(`function\\s+${name}\\s*\\(`);
  const start = source.search(startRe);
  if (start === -1) {
    throw new Error(`Could not locate function ${name}() in ${name}`);
  }
  const openBrace = source.indexOf('{', start);
  let depth = 1;
  let i = openBrace + 1;
  while (i < source.length && depth > 0) {
    const ch = source[i];
    if (ch === '{') depth++;
    else if (ch === '}') depth--;
    i++;
  }
  return source.slice(openBrace + 1, i - 1);
}

describe('Privacy: privacy_session_enabled must not piggyback on params', () => {
  let utilitiesSource;
  let monadicSource;

  beforeAll(() => {
    utilitiesSource = loadFile('docker/services/ruby/public/js/monadic/utilities.js');
    monadicSource = loadFile('docker/services/ruby/public/js/monadic.js');
  });

  test('setParams() does not write params["privacy_session_enabled"]', () => {
    const body = extractFunctionBody(utilitiesSource, 'setParams');
    // Comments mentioning the field are fine — assignment statements are not.
    const lines = body.split('\n').filter(l => !l.trim().startsWith('//'));
    const noCommentBody = lines.join('\n');
    expect(noCommentBody).not.toMatch(/params\s*\[\s*["']privacy_session_enabled["']\s*\]\s*=/);
  });

  test('monadic.js param broadcast clone does not include privacy_session_enabled', () => {
    // The setParamsForBroadcast() helper near the top of monadic.js builds
    // a sanitized copy of params for broadcast. It must
    // not write the privacy field — the backend does not look at it.
    const lines = monadicSource.split('\n').filter(l => !l.trim().startsWith('//'));
    const noCommentSource = lines.join('\n');
    expect(noCommentSource).not.toMatch(/clone\.privacy_session_enabled\s*=/);
  });

  test('the toggle change handler sends PRIVACY_TOGGLE via safeWsSend', () => {
    // Locate the change handler block by anchoring on "check-privacy-session".
    // The body must include a safeWsSend call with message: "PRIVACY_TOGGLE".
    const idx = monadicSource.indexOf('"check-privacy-session"');
    expect(idx).toBeGreaterThan(-1);
    // Look at the surrounding ~2KB window for the handler body.
    const window = monadicSource.slice(idx, idx + 4000);
    expect(window).toMatch(/safeWsSend/);
    expect(window).toMatch(/PRIVACY_TOGGLE/);
  });
});
