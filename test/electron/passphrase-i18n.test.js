/**
 * @jest-environment jsdom
 */
// The passphrase window speaks the app's language: main sends the window's
// own words with the init message, and the page shows them, including the
// validation messages. Without them it stays in English.
const fs = require('fs');
const path = require('path');

const APP = path.join(__dirname, '..', '..', 'app');
const html = fs.readFileSync(path.join(APP, 'passphrase-prompt.html'), 'utf8');
const ja = JSON.parse(fs.readFileSync(path.join(APP, 'translations', 'ja.json'), 'utf8')).dialogs;
const en = JSON.parse(fs.readFileSync(path.join(APP, 'translations', 'en.json'), 'utf8')).dialogs;

function openWindow() {
  document.documentElement.innerHTML = html.slice(html.indexOf('<head>'), html.indexOf('<script src="passphrase-prompt.js"'));
  let init;
  window.passphraseAPI = { onInit: (cb) => { init = cb; }, submit: jest.fn(), fit: jest.fn() };
  Object.defineProperty(document, 'fonts', { value: { ready: Promise.resolve() }, configurable: true });
  jest.isolateModules(() => require(path.join(APP, 'passphrase-prompt.js')));
  return init;
}
const $ = (id) => document.getElementById(id);
const type = (id, v) => { $(id).value = v; $(id).dispatchEvent(new Event('input')); };

describe('passphrase window words', () => {
  test('shows the labels, buttons and messages main sends', () => {
    const init = openWindow();
    const p = ja.passphrase;
    init({ title: ja.exportDbPassphraseTitle, hint: ja.exportDbPassphraseHint, lang: 'ja',
      labels: { ...p, cancel: ja.cancel, ok: ja.ok } });
    expect([$('label-pp').textContent, $('label-pp2').textContent, $('cancel').textContent, $('ok').textContent])
      .toEqual([p.label, p.confirmLabel, ja.cancel, ja.ok]);
    expect(document.title).toBe(p.windowTitle);
    expect(document.documentElement.lang).toBe('ja');
    type('pp', 'short');
    expect($('err').textContent).toBe(p.tooShort);
    type('pp', 'long enough'); type('pp2', 'different!');
    expect($('err').textContent).toBe(p.mismatch);
  });

  test('stays in English when main sends no labels', () => {
    const init = openWindow();
    init({ confirmRequired: true });
    expect($('label-pp2').textContent).toBe('Confirm passphrase');
    type('pp', 'short');
    expect($('err').textContent).toBe(en.passphrase.tooShort);
  });

  test('main builds the labels from the translations, not English literals', () => {
    const main = fs.readFileSync(path.join(APP, 'main.js'), 'utf8');
    const fn = main.slice(main.indexOf('function promptPassphrase('), main.indexOf('return new Promise', main.indexOf('function promptPassphrase(')));
    for (const k of ['windowTitle', 'label', 'confirmLabel', 'tooShort', 'mismatch']) {
      expect(fn).toContain(`i18n.t('dialogs.passphrase.${k}')`);
    }
    expect(fn).not.toMatch(/'Enter Passphrase'|'Used to encrypt/);
    expect(main).toContain('title: options.labels.windowTitle');
  });
});
