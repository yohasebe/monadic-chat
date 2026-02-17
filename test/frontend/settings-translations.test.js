// Test for settingsTranslations.js
// Verifies all languages have identical key structures and expected categories.
// Run with: npm test test/frontend/settings-translations.test.js

const fs = require('fs');
const path = require('path');

const translationsPath = path.join(__dirname, '../../app/settingsTranslations.js');
const translationsCode = fs.readFileSync(translationsPath, 'utf8');

// Extract settingsTranslations object by evaluating in isolated scope
// Note: const declarations in eval() don't leak, so we replace with var
const settingsTranslations = (() => {
  const mockDocument = {
    cookie: '',
    addEventListener: () => {},
    querySelectorAll: () => [],
    getElementById: () => null
  };
  const modifiedCode = translationsCode
    .replace(/^const settingsTranslations/m, 'var settingsTranslations')
    .replace(/^const settingsI18n/m, 'var settingsI18n')
    .replace(/^class SettingsI18n/m, 'var SettingsI18n; SettingsI18n = class SettingsI18n');
  let result;
  (function () {
    const document = mockDocument;  // eslint-disable-line no-unused-vars
    const window = {};  // eslint-disable-line no-unused-vars
    eval(modifiedCode);
    result = settingsTranslations;
  })();
  return result;
})();

// Recursively collect all leaf key paths from an object
function collectKeys(obj, prefix = '') {
  const keys = [];
  for (const [key, value] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (typeof value === 'object' && value !== null) {
      keys.push(...collectKeys(value, path));
    } else {
      keys.push(path);
    }
  }
  return keys.sort();
}

const EXPECTED_LANGUAGES = ['en', 'ja', 'zh', 'ko', 'es', 'fr', 'de'];
const EXPECTED_CATEGORIES = ['general', 'system', 'apiKeys', 'voice', 'services', 'installOptions', 'actions', 'about'];

describe('Settings Translations', () => {
  test('all expected languages are present', () => {
    const availableLanguages = Object.keys(settingsTranslations).sort();
    expect(availableLanguages).toEqual(EXPECTED_LANGUAGES.sort());
  });

  test('all languages have the same key structure as English', () => {
    const enKeys = collectKeys(settingsTranslations.en);
    expect(enKeys.length).toBeGreaterThan(0);

    for (const lang of EXPECTED_LANGUAGES) {
      if (lang === 'en') continue;
      const langKeys = collectKeys(settingsTranslations[lang]);
      const missingInLang = enKeys.filter(k => !langKeys.includes(k));
      const extraInLang = langKeys.filter(k => !enKeys.includes(k));

      expect(missingInLang).toEqual([]);
      expect(extraInLang).toEqual([]);
    }
  });

  test('all expected category keys exist in every language', () => {
    for (const lang of EXPECTED_LANGUAGES) {
      const categories = settingsTranslations[lang]?.settings?.categories;
      expect(categories).toBeDefined();
      const categoryKeys = Object.keys(categories).sort();
      expect(categoryKeys).toEqual(EXPECTED_CATEGORIES.sort());
    }
  });

  test('no translation value is empty string', () => {
    for (const lang of EXPECTED_LANGUAGES) {
      const keys = collectKeys(settingsTranslations[lang]);
      for (const keyPath of keys) {
        const parts = keyPath.split('.');
        let value = settingsTranslations[lang];
        for (const p of parts) value = value[p];
        expect(value).not.toBe('');
      }
    }
  });

  test('all translation values are strings', () => {
    for (const lang of EXPECTED_LANGUAGES) {
      const keys = collectKeys(settingsTranslations[lang]);
      for (const keyPath of keys) {
        const parts = keyPath.split('.');
        let value = settingsTranslations[lang];
        for (const p of parts) value = value[p];
        expect(typeof value).toBe('string');
      }
    }
  });

  test('English category labels are non-empty and meaningful', () => {
    const categories = settingsTranslations.en.settings.categories;
    for (const [key, value] of Object.entries(categories)) {
      expect(value.length).toBeGreaterThan(0);
      expect(value.trim()).toBe(value); // no leading/trailing whitespace
    }
  });
});
