// The settings carry the API keys. Only the Settings window's own page may
// read or save them: the main window shares the preload but shows content
// from outside the app. main.js starts the whole app at load, so the check
// is taken from the real file and evaluated here.
const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname, '../../app/main.js'), 'utf8');

function loadSenderCheck(settingsWindow) {
  const m = source.match(/function isSettingsSender\([^)]*\) \{[\s\S]*?\n\}\n/);
  if (!m) throw new Error('isSettingsSender not found in main.js');
  // eslint-disable-next-line no-new-func
  return new Function('settingsWindow', `${m[0]}\nreturn isSettingsSender;`)(settingsWindow);
}

function fakeWindow() {
  const mainFrame = {};
  const webContents = { mainFrame };
  return { webContents, isDestroyed: () => false };
}

describe('settings IPC', () => {
  test('answers the Settings window top frame only', () => {
    const settings = fakeWindow();
    const other = fakeWindow();
    const check = loadSenderCheck(settings);
    expect(check({ sender: settings.webContents, senderFrame: settings.webContents.mainFrame })).toBe(true);
    expect(check({ sender: other.webContents, senderFrame: other.webContents.mainFrame })).toBe(false);
    expect(check({ sender: settings.webContents, senderFrame: {} })).toBe(false);
  });

  test('answers nobody when the Settings window is closed', () => {
    expect(loadSenderCheck(null)({ sender: {}, senderFrame: {} })).toBe(false);
    const destroyed = { ...fakeWindow(), isDestroyed: () => true };
    const check = loadSenderCheck(destroyed);
    expect(check({ sender: destroyed.webContents, senderFrame: destroyed.webContents.mainFrame })).toBe(false);
  });

  test.each(['request-settings', 'save-settings'])('%s checks the sender before anything else', (channel) => {
    const m = source.match(new RegExp(`ipcMain\\.(?:on|handle)\\('${channel}', \\(event[^)]*\\) => \\{\\n\\s*(.*)`));
    expect(m).not.toBeNull();
    expect(m[1]).toMatch(/^if \(!isSettingsSender\(event\)\) return/);
  });
});
