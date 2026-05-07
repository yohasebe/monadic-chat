/**
 * @jest-environment jsdom
 *
 * Phase 4 of the KB/PF MDSL SSOT refactor: per-app capabilities (privacy_enabled,
 * library_save, library_search) drive UI visibility through body classes + CSS,
 * not through JS `style.display` mutation. This file pins the body-class
 * contract end to end:
 *
 *   - applyAppCapabilityClasses(name) reads window.apps[name] and toggles
 *     `app-cap-pf` / `app-cap-kb-save` / `app-cap-kb-search` on <body>.
 *   - Defaults are KB save & search ON, PF OFF — preserving legacy behavior
 *     for apps that haven't declared the flags. Only an explicit `false`
 *     (or "false") disables, mirroring CAPABILITY_DEFAULTS on the Ruby side.
 *   - applyPrivacyOnClass(bool) toggles `app-privacy-on` independently;
 *     this is a session-scoped flag set in response to backend privacy_state
 *     pushes, not a per-app static capability.
 *
 * The functions live in docker/services/ruby/public/js/monadic.js. We
 * extract them via the same source-slicing pattern used by
 * setparams-privacy.test.js so the production code is what's actually
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

describe('applyAppCapabilityClasses / applyPrivacyOnClass (body-class SSOT for Phase 4)', () => {
  let applyAppCapabilityClasses;
  let applyPrivacyOnClass;

  beforeAll(() => {
    const monadicSource = fs.readFileSync(
      path.join(__dirname, '..', '..', 'docker/services/ruby/public/js/monadic.js'),
      'utf8'
    );
    const fnA = extractFunctionSource(monadicSource, 'applyAppCapabilityClasses');
    const fnB = extractFunctionSource(monadicSource, 'applyPrivacyOnClass');
    // eslint-disable-next-line no-new-func
    applyAppCapabilityClasses = new Function(
      `${fnA}; return applyAppCapabilityClasses;`
    )();
    // eslint-disable-next-line no-new-func
    applyPrivacyOnClass = new Function(`${fnB}; return applyPrivacyOnClass;`)();
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
    it('PF-only app (privacy_enabled true, library_save false, library_search false) sets only app-cap-pf', () => {
      window.apps = { Mail: { privacy_enabled: true, library_save: false, library_search: false } };
      applyAppCapabilityClasses('Mail');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-pf')).toBe(true);
      expect(cl.contains('app-cap-kb-save')).toBe(false);
      expect(cl.contains('app-cap-kb-search')).toBe(false);
    });

    it('KB-only app (no privacy, library_save+search true) sets save+search but not pf', () => {
      window.apps = { Chat: { privacy_enabled: false, library_save: true, library_search: true } };
      applyAppCapabilityClasses('Chat');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-pf')).toBe(false);
      expect(cl.contains('app-cap-kb-save')).toBe(true);
      expect(cl.contains('app-cap-kb-search')).toBe(true);
    });

    it('Artifact-style app (library_save false, library_search false, no privacy) sets nothing', () => {
      window.apps = { Image: { library_save: false, library_search: false } };
      applyAppCapabilityClasses('Image');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-pf')).toBe(false);
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

    it('legacy / unknown app (no flags declared) defaults to KB save+search ON, PF OFF', () => {
      window.apps = { CustomLegacy: {} };
      applyAppCapabilityClasses('CustomLegacy');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-pf')).toBe(false);
      expect(cl.contains('app-cap-kb-save')).toBe(true);
      expect(cl.contains('app-cap-kb-search')).toBe(true);
    });

    it('handles string "false" (legacy serialization) the same as boolean false', () => {
      window.apps = { Legacy: { library_save: 'false', library_search: 'false', privacy_enabled: 'false' } };
      applyAppCapabilityClasses('Legacy');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-pf')).toBe(false);
      expect(cl.contains('app-cap-kb-save')).toBe(false);
      expect(cl.contains('app-cap-kb-search')).toBe(false);
    });

    it('handles string "true" for privacy_enabled (legacy serialization)', () => {
      window.apps = { Legacy: { privacy_enabled: 'true', library_save: false, library_search: false } };
      applyAppCapabilityClasses('Legacy');
      expect(document.body.classList.contains('app-cap-pf')).toBe(true);
    });

    it('clears stale classes when switching from a PF/KB app to an artifact app', () => {
      window.apps = {
        Mail: { privacy_enabled: true, library_save: false, library_search: false },
        Image: { library_save: false, library_search: false }
      };
      applyAppCapabilityClasses('Mail');
      expect(document.body.classList.contains('app-cap-pf')).toBe(true);
      applyAppCapabilityClasses('Image');
      expect(document.body.classList.contains('app-cap-pf')).toBe(false);
      expect(document.body.classList.contains('app-cap-kb-save')).toBe(false);
      expect(document.body.classList.contains('app-cap-kb-search')).toBe(false);
    });

    it('no-ops safely when appName is null / unknown (does not toggle any class)', () => {
      document.body.classList.add('app-cap-pf'); // pre-existing state we should not touch
      window.apps = {};
      applyAppCapabilityClasses(null);
      expect(document.body.classList.contains('app-cap-pf')).toBe(true);
      applyAppCapabilityClasses('NotInApps');
      expect(document.body.classList.contains('app-cap-pf')).toBe(true);
    });
  });

  describe('applyPrivacyOnClass', () => {
    it('adds app-privacy-on when called with true', () => {
      applyPrivacyOnClass(true);
      expect(document.body.classList.contains('app-privacy-on')).toBe(true);
    });

    it('removes app-privacy-on when called with false', () => {
      document.body.classList.add('app-privacy-on');
      applyPrivacyOnClass(false);
      expect(document.body.classList.contains('app-privacy-on')).toBe(false);
    });

    it('coerces truthy / falsy non-boolean values to a boolean toggle', () => {
      applyPrivacyOnClass(1);
      expect(document.body.classList.contains('app-privacy-on')).toBe(true);
      applyPrivacyOnClass(0);
      expect(document.body.classList.contains('app-privacy-on')).toBe(false);
      applyPrivacyOnClass(undefined);
      expect(document.body.classList.contains('app-privacy-on')).toBe(false);
    });

    it('is independent of applyAppCapabilityClasses (orthogonal concerns)', () => {
      window.apps = { Chat: { privacy_enabled: false, library_save: true, library_search: true } };
      applyAppCapabilityClasses('Chat');
      applyPrivacyOnClass(true); // session-scoped, despite app not declaring privacy_enabled
      const cl = document.body.classList;
      expect(cl.contains('app-cap-pf')).toBe(false);
      expect(cl.contains('app-privacy-on')).toBe(true);
      expect(cl.contains('app-cap-kb-save')).toBe(true);
    });
  });
});
