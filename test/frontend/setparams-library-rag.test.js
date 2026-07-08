/**
 * The Knowledge Base (RAG) session toggle MUST round-trip through the message
 * submit. Unlike the Privacy toggle (backend-only), library_rag_enabled is
 * cleared by RESET (session[:parameters].clear) and the WS LIBRARY_RAG_TOGGLE
 * message only fires on an explicit user toggle — so a session that merely
 * SHOWS the toggle ON (after reset/import/launch) would leave the backend unset
 * and library_search disabled. setParams() carries the toggle's current state
 * on every submit so the backend always matches the visible toggle.
 *
 * Regression guard: if this write is removed, KB retrieval silently breaks on
 * fresh/reset/imported sessions even though the toggle appears ON.
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
    throw new Error(`Could not locate function ${name}() in source`);
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

describe('Knowledge Base: library_rag_enabled must ride the submit params', () => {
  let setParamsBody;

  beforeAll(() => {
    const utilitiesSource = loadFile('docker/services/ruby/public/js/monadic/utilities.js');
    setParamsBody = extractFunctionBody(utilitiesSource, 'setParams');
  });

  test('setParams() writes params["library_rag_enabled"]', () => {
    const noCommentBody = setParamsBody
      .split('\n')
      .filter((l) => !l.trim().startsWith('//'))
      .join('\n');
    expect(noCommentBody).toMatch(/params\s*\[\s*["']library_rag_enabled["']\s*\]\s*=/);
  });

  test('setParams() reads the value from the library-rag-toggle element', () => {
    expect(setParamsBody).toMatch(/library-rag-toggle/);
    // Guard against setting it from a hard-coded literal instead of the toggle.
    expect(setParamsBody).toMatch(/\.checked/);
  });
});
