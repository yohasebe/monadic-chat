// The desktop app's dialogs take their words from the translations: every
// key they ask for exists (i18n.t returns the key itself when it does not),
// no dialog is given English text directly, and the update dialogs show the
// app's language.
const fs = require('fs');
const path = require('path');

const autoUpdaterEvents = {};
jest.mock('electron-updater', () => ({
  autoUpdater: { on: (event, handler) => { autoUpdaterEvents[event] = handler; } }
}));
const showMessageBox = jest.fn(() => Promise.resolve({ response: 1 }));
jest.mock('electron', () => ({ app: {}, dialog: { showMessageBox }, shell: { openExternal: jest.fn() } }));

const APP = path.join(__dirname, '..', '..', 'app');
const SOURCES = ['main.js', 'updater.js'].map((f) => [f, fs.readFileSync(path.join(APP, f), 'utf8')]);
const i18n = require('../../app/i18n');
const ja = JSON.parse(fs.readFileSync(path.join(APP, 'translations', 'ja.json'), 'utf8'));

describe('desktop app dialogs', () => {
  afterEach(() => i18n.setLanguage('en'));

  test.each(SOURCES)('every key %s asks for is translated', (file, src) => {
    const keys = [...src.matchAll(/i18n\.t\('([\w.]+)'/g)].map((m) => m[1]);
    expect(keys.length).toBeGreaterThan(5);
    expect(keys.filter((k) => typeof i18n.t(k) !== 'string' || i18n.t(k) === k)).toEqual([]);
  });

  test.each(SOURCES)('no dialog in %s is given English text directly', (file, src) => {
    const calls = [...src.matchAll(/dialog\.show(?:ErrorBox|MessageBox|OpenDialog)\(/g)];
    expect(calls.length).toBeGreaterThan(0);
    // A string that starts with words; one that starts with a value (the
    // raw error, a path) is fine.
    const words = String.raw`(?:['"]|\x60(?!\$\{))`;
    const literal = new RegExp(String.raw`showErrorBox\(\s*${words}|\b(?:title|message|detail|name):\s*${words}|buttons:\s*\[\s*${words}`);
    const found = calls.map((m) => {
      let depth = 0; let i = src.indexOf('(', m.index);
      do { depth += { '(': 1, ')': -1 }[src[i]] || 0; i += 1; } while (depth > 0);
      return src.slice(m.index, i);
    }).filter((call) => literal.test(call));
    expect(found).toEqual([]);
  });

  test.each(SOURCES)('no message %s writes to the main window is in English', (file, src) => {
    const calls = [...src.matchAll(/(?:writeToScreen|noticeInMainWindow|send\('command-output',|runCommand)\(?/g)].map((m) => {
      let depth = 0; let i = src.indexOf('(', m.index);
      do { depth += { '(': 1, ')': -1 }[src[i]] || 0; i += 1; } while (depth > 0);
      return src.slice(m.index, i);
    });
    expect(calls.length).toBeGreaterThan(0);
    // Words left once markup, interpolations, keys and [MARKERS] are taken out.
    const english = (call) => [...call.matchAll(/'([^'\n]*)'|"([^"\n]*)"|`([^`]*)`/g)]
      .map((m) => m.slice(1).join(''))
      .map((s) => s.replace(/<[^>]*>|\$\{[^}]*\}|\[[A-Z_ ]+\]:?/g, ' '))
      .some((s) => /[A-Za-z]{2,}[,.]?\s+[A-Za-z]{2,}/.test(s));
    expect(calls.filter(english)).toEqual([]);
  });

  describe('update dialogs', () => {
    const updater = require('../../app/updater');
    const mainWindow = { isDestroyed: () => false, webContents: { send: jest.fn() } };

    beforeEach(() => {
      updater._resetForTests();
      showMessageBox.mockClear();
      updater.init({ dockerManager: {}, getMainWindow: () => mainWindow, log: { warn: jest.fn() } });
      i18n.setLanguage('ja');
    });

    test('the ready dialog speaks the app language', async () => {
      await autoUpdaterEvents['update-downloaded']({ version: '9.9.9' });
      const opts = showMessageBox.mock.calls[0][1];
      const r = ja.dialogs.updateReady;
      expect(opts).toMatchObject({ title: r.title, detail: r.detail, buttons: [r.restartNow, r.later] });
      expect(opts.message).toBe(r.message.replace('{{version}}', '9.9.9'));
    });

    test('the error dialog keeps the raw error and adds the translated advice', () => {
      autoUpdaterEvents.error(new Error('net::ERR_X'));
      const opts = showMessageBox.mock.calls[0][1];
      const e = ja.dialogs.updateError;
      expect(opts).toMatchObject({ title: e.title, message: e.message, buttons: [e.openReleases, e.close] });
      expect(opts.detail).toBe(`net::ERR_X\n\n${e.detail}`);
    });
  });
});
