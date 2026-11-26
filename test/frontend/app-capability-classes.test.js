/**
 * @jest-environment jsdom
 *
 * The per-app capability library_save drives UI visibility through a body class + CSS,
 * not through JS `style.display` mutation. This file pins the body-class
 * contract end to end:
 *
 *   - applyAppCapabilityClasses(name) reads window.apps[name] and toggles
 *     `app-cap-kb-save` on <body>.
 *   - The default is ON for apps that haven't declared the flag. Only an explicit `false`
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
    it('an app that keeps its chats sets the class', () => {
      window.apps = { Chat: { library_save: true, library_search: true } };
      applyAppCapabilityClasses('Chat');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(true);
    });

    it('an app that keeps no chats (library_save false) does not', () => {
      window.apps = { Image: { library_save: false, library_search: false } };
      applyAppCapabilityClasses('Image');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(false);
    });

    it('library_search does not matter to it', () => {
      window.apps = { WebInsightOpenAI: { library_save: true, library_search: false } };
      applyAppCapabilityClasses('WebInsightOpenAI');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(true);
    });

    it('an app that declares nothing keeps its chats', () => {
      window.apps = { CustomLegacy: {} };
      applyAppCapabilityClasses('CustomLegacy');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(true);
    });

    it('handles string "false" (legacy serialization) the same as boolean false', () => {
      window.apps = { Legacy: { library_save: 'false', library_search: 'false' } };
      applyAppCapabilityClasses('Legacy');
      const cl = document.body.classList;
      expect(cl.contains('app-cap-kb-save')).toBe(false);
    });

    it('clears stale classes when switching from a KB app to an artifact app', () => {
      window.apps = {
        Mail: { library_save: false, library_search: false },
        Image: { library_save: false, library_search: false }
      };
      applyAppCapabilityClasses('Mail');
      applyAppCapabilityClasses('Image');
      expect(document.body.classList.contains('app-cap-kb-save')).toBe(false);
    });

    it('hides the record of the chat for an app that keeps no chats', () => {
      const css = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/css/monadic.css'), 'utf8');
      expect(css).toContain('body:not(.app-cap-kb-save) #library-draft-conversation { display: none; }');
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
