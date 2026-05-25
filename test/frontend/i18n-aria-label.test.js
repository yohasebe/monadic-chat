/**
 * @jest-environment jsdom
 */

/**
 * Structural verification for the `data-i18n-aria-label` i18n pattern.
 *
 * Loading translations.js into jsdom is heavy (IIFE + class with
 * top-level DOM lookups), and most of the risk is *structural*
 * — silent typos that cause an aria-label key to fall through to the
 * default English at runtime. So this spec inspects the source files
 * directly:
 *
 *   1. translations.js HAS the loader loop for [data-i18n-aria-label]
 *      that mirrors the existing [data-i18n-placeholder] one.
 *   2. Every aria-label key referenced from index.erb exists in every
 *      supported locale's `ui:` section.
 *   3. Every locale has the *same set* of aria-label keys (parity).
 *
 * If any of these fail, runtime aria-label i18n is broken even though
 * the loader code itself compiles fine.
 */

const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '../..');
const TRANSLATIONS_PATH = path.join(
  REPO,
  'docker/services/ruby/public/js/i18n/translations.js'
);
const INDEX_ERB_PATH = path.join(
  REPO,
  'docker/services/ruby/views/index.erb'
);

const EXPECTED_LOCALES = ['en', 'ja', 'zh', 'ko', 'es', 'fr', 'de'];

let translationsSrc;
let indexSrc;

beforeAll(() => {
  translationsSrc = fs.readFileSync(TRANSLATIONS_PATH, 'utf8');
  indexSrc = fs.readFileSync(INDEX_ERB_PATH, 'utf8');
});

/**
 * Extract leaf-string keys under each locale's `ui:` section. We
 * don't parse the whole JS as JSON (it's not JSON), but the `ui:`
 * sections are flat objects of `key: "value",` lines which we can
 * tokenize line-by-line within each locale block.
 */
function extractKeysForLocale(src, locale) {
  // Locate the opening of this locale's block, then its `ui: {`.
  const localeOpen = new RegExp(`^\\s{2}${locale}:\\s*\\{`, 'm');
  const localeMatch = localeOpen.exec(src);
  if (!localeMatch) return null;
  const after = src.slice(localeMatch.index + localeMatch[0].length);
  const uiOpen = after.search(/^\s{4}ui:\s*\{/m);
  if (uiOpen < 0) return null;
  // Walk braces to find the matching close brace of `ui:`.
  let depth = 1;
  let i = uiOpen + after.slice(uiOpen).search(/\{/) + 1;
  while (i < after.length && depth > 0) {
    if (after[i] === '{') depth++;
    else if (after[i] === '}') depth--;
    i++;
  }
  const uiBody = after.slice(uiOpen, i);
  // Extract every `<identifier>: "..."` at line-start within ui.
  const keys = [];
  const keyRe = /^\s+([a-zA-Z_][a-zA-Z0-9_]*):\s*"/gm;
  let m;
  while ((m = keyRe.exec(uiBody)) !== null) keys.push(m[1]);
  return keys;
}

describe('i18n loader: data-i18n-aria-label', () => {
  it('translations.js contains the loader loop for data-i18n-aria-label', () => {
    // The fix in this session adds a third querySelectorAll loop
    // mirroring data-i18n-title and data-i18n-placeholder. Without
    // it, aria-labels never localize regardless of how many keys we
    // add to the translation table.
    expect(translationsSrc).toMatch(
      /querySelectorAll\(['"]\[data-i18n-aria-label\]['"]\)/
    );
    // Verify the loop actually sets the attribute, not just queries.
    expect(translationsSrc).toMatch(
      /setAttribute\(['"]aria-label['"]/
    );
  });

  it('every locale exposes the same aria-label key set (parity)', () => {
    const ariaKeysByLocale = {};
    for (const locale of EXPECTED_LOCALES) {
      const keys = extractKeysForLocale(translationsSrc, locale);
      expect(keys).not.toBeNull();
      // Filter to aria-label keys (consistent naming convention).
      ariaKeysByLocale[locale] = keys.filter((k) => k.endsWith('AriaLabel')).sort();
    }
    const enKeys = ariaKeysByLocale.en;
    expect(enKeys.length).toBeGreaterThan(0); // sanity: we added several

    // Each other locale must have *the same* set of aria-label keys.
    for (const locale of EXPECTED_LOCALES.filter((l) => l !== 'en')) {
      expect(ariaKeysByLocale[locale]).toEqual(enKeys);
    }
  });

  it('every aria-label key referenced from index.erb exists in en', () => {
    // Collect `ui.<key>` references used in data-i18n-aria-label
    // attributes. If any of these is mistyped (e.g. ui.messageArialabel
    // → no such key), the loader silently sets aria-label="" which is
    // an a11y regression worse than the hardcoded English fallback.
    const referenced = new Set();
    const re = /data-i18n-aria-label=["']ui\.([a-zA-Z_][a-zA-Z0-9_]*)["']/g;
    let m;
    while ((m = re.exec(indexSrc)) !== null) referenced.add(m[1]);
    expect(referenced.size).toBeGreaterThan(0); // sanity: we wired up several elements

    const enKeys = extractKeysForLocale(translationsSrc, 'en');
    const enKeySet = new Set(enKeys);
    const missing = [...referenced].filter((k) => !enKeySet.has(k));
    expect(missing).toEqual([]);
  });

  it('every aria-label key referenced from index.erb exists in all locales', () => {
    const referenced = new Set();
    const re = /data-i18n-aria-label=["']ui\.([a-zA-Z_][a-zA-Z0-9_]*)["']/g;
    let m;
    while ((m = re.exec(indexSrc)) !== null) referenced.add(m[1]);

    for (const locale of EXPECTED_LOCALES) {
      const keys = new Set(extractKeysForLocale(translationsSrc, locale));
      const missing = [...referenced].filter((k) => !keys.has(k));
      expect({ locale, missing }).toEqual({ locale, missing: [] });
    }
  });
});
