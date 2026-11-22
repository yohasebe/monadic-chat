/**
 * @jest-environment jsdom
 *
 * Per-app capabilities (library_save, library_search) drive UI visibility through body classes + CSS,
 * not through JS `style.display` mutation. This file pins the body-class
 * contract end to end:
 *
 *   - applyAppCapabilityClasses(name) reads window.apps[name] and toggles
 *     `app-cap-kb-save` / `app-cap-kb-search` on <body>.
 *   - Defaults are KB save & search ON — preserving legacy behavior
 *     for apps that haven't declared the flags. Only an explicit `false`
 *     (or "false") disables, mirroring CAPABILITY_DEFAULTS on the Ruby side.
 *
 * The functions live in docker/services/ruby/public/js/monadic.js. We
 * extract them via the same source-slicing pattern used by
 * other source-level tests so the production code is what's actually
 * exercised, not a hand-rolled copy.
 */

const fs = require('fs');
const path = require('path');

function extractFunctionSource(source, name) {
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
  return source.slice(start, i);
}

describe('applyAppCapabilityClasses (body-class SSOT)', () => {
  let applyAppCapabilityClasses;

  beforeAll(() => {
    const monadicSource = fs.readFileSync(
      path.join(__dirname, '..', '..', 'docker/services/ruby/public/js/monadic.js'),
      'utf8'
    );
    const fnA = extractFunctionSource(monadicSource, 'applyAppCapabilityClasses');
    // eslint-disable-next-line no-new-func
    applyAppCapabilityClasses = new Function(
      `${fnA}; return applyAppCapabilityClasses;`
    )();
    // eslint-disable-next-line no-new-func
  });

  beforeEach(() => {
    document.body.className = '';
    delete window.apps;
  });

  afterEach(() => {
    document.body.className = '';
    delete window.apps;
  });

  describe('applyAppCapabilityClasses', () => {
    it('KB-only app (library_save+search true) sets save+search', () => {
      window.apps = { Chat: { library_save: true, library_search: true } };
      applyAppCapabilityClasses('Chat');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(true);
      expect(cl.contains('app-cap-kb-search')).toBe(true);
    });

    it('Artifact-style app (library_save false, library_search false, no privacy) sets nothing', () => {
      window.apps = { Image: { library_save: false, library_search: false } };
      applyAppCapabilityClasses('Image');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(false);
      expect(cl.contains('app-cap-kb-search')).toBe(false);
    });

    it('KB-save-only app (library_save true, library_search false) covers MonadicHelp / WebInsight class', () => {
      window.apps = { WebInsightOpenAI: { library_save: true, library_search: false } };
      applyAppCapabilityClasses('WebInsightOpenAI');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(true);
      expect(cl.contains('app-cap-kb-search')).toBe(false);
    });

    it('legacy / unknown app (no flags declared) defaults to KB save+search ON', () => {
      window.apps = { CustomLegacy: {} };
      applyAppCapabilityClasses('CustomLegacy');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(true);
      expect(cl.contains('app-cap-kb-search')).toBe(true);
    });

    it('handles string "false" (legacy serialization) the same as boolean false', () => {
      window.apps = { Legacy: { library_save: 'false', library_search: 'false' } };
      applyAppCapabilityClasses('Legacy');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(false);
      expect(cl.contains('app-cap-kb-search')).toBe(false);
    });

    it('clears stale classes when switching from a KB app to an artifact app', () => {
      window.apps = {
        Mail: { library_save: false, library_search: false },
        Image: { library_save: false, library_search: false }
      };
      applyAppCapabilityClasses('Mail');
      applyAppCapabilityClasses('Image');
      expect(document.body.classList.contains('app-cap-kb-save')).toBe(false);
      expect(document.body.classList.contains('app-cap-kb-search')).toBe(false);
    });

    it('disables the KB retrieval toggle (with tooltip) when library_search is false, leaving checked untouched', () => {
      document.body.innerHTML =
        '<input type="checkbox" id="library-rag-toggle">';
      const rag = document.getElementById('library-rag-toggle');
      rag.checked = true; // simulate a persisted "on" preference
      window.apps = { Music: { library_save: false, library_search: false } };
      applyAppCapabilityClasses('Music');
      expect(rag.disabled).toBe(true);
      expect(rag.getAttribute('title')).toMatch(/not available/i);
      expect(rag.checked).toBe(true); // preference preserved, not clobbered
    });

    it('enables the KB retrieval toggle (no tooltip) for a library_search app', () => {
      document.body.innerHTML = '<input type="checkbox" id="library-rag-toggle">';
      window.apps = { Chat: { library_save: true, library_search: true } };
      applyAppCapabilityClasses('Chat');
      const rag = document.getElementById('library-rag-toggle');
      expect(rag.disabled).toBe(false);
      expect(rag.getAttribute('title')).toBeNull();
    });

    it('no-ops safely when appName is null / unknown (does not toggle any class)', () => {
      document.body.classList.add('app-cap-kb-save'); // pre-existing state we should not touch
      window.apps = {};
      applyAppCapabilityClasses(null);
      expect(document.body.classList.contains('app-cap-kb-save')).toBe(true);
      applyAppCapabilityClasses('NotInApps');
      expect(document.body.classList.contains('app-cap-kb-save')).toBe(true);
    });
  });
});
