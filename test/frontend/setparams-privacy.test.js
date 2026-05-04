/**
 * Phase 4 SSOT lint: privacy_session_enabled must NOT travel through
 * params. The backend tracks the toggle via PRIVACY_TOGGLE round-trip;
 * leaving a stale params write would shadow the health-checked
 * authoritative state on the next submit.
 *
 * Background: a 2026-05-04 dogfood leak revealed that setParams()
 * was missing the privacy field entirely (so the backend never received
 * the user's toggle intent). The interim fix added it; Phase 4 removed
 * the params field altogether and moved authority to the backend via
 * an explicit PRIVACY_TOGGLE WebSocket message. This test locks in the
 * Phase 4 contract — no privacy_session_enabled writes anywhere in
 * setParams(), and the toggle change handler must use safeWsSend.
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

describe('Phase 4 SSOT: privacy_session_enabled must not piggyback on params', () => {
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
    // a sanitized copy of params for broadcast. After Phase 4 it must
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
