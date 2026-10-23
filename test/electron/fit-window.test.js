// The passphrase prompt takes the height its page reports (translated titles
// and hints wrap) before it is shown, and only from its own page.
const fs = require('fs');
const path = require('path');
const { createFitHandler } = require('../../app/fit_window');

const ROOT = path.join(__dirname, '..', '..');

function fakeWindow() {
  const webContents = {};
  return { webContents, destroyed: false, isDestroyed() { return this.destroyed; }, setContentSize: jest.fn() };
}

describe('fitting a window to its content', () => {
  test('takes the reported height and then shows the window', () => {
    const win = fakeWindow();
    const onFitted = jest.fn();
    createFitHandler(win, { width: 400, onFitted })({ sender: win.webContents }, 313.4);
    expect(win.setContentSize).toHaveBeenCalledWith(400, 313);
    expect(onFitted).toHaveBeenCalledTimes(1);
  });

  test('keeps the height within bounds', () => {
    const win = fakeWindow();
    const fit = createFitHandler(win, { width: 400, onFitted: () => {} });
    fit({ sender: win.webContents }, 20);
    fit({ sender: win.webContents }, 5000);
    expect(win.setContentSize.mock.calls).toEqual([[400, 160], [400, 640]]);
  });

  test('ignores reports from any other page', () => {
    const win = fakeWindow();
    const onFitted = jest.fn();
    createFitHandler(win, { width: 400, onFitted })({ sender: {} }, 300);
    expect(win.setContentSize).not.toHaveBeenCalled();
    expect(onFitted).not.toHaveBeenCalled();
  });

  test('does nothing once the window is gone', () => {
    const win = fakeWindow();
    win.destroyed = true;
    const onFitted = jest.fn();
    createFitHandler(win, { width: 400, onFitted })({ sender: win.webContents }, 300);
    expect(win.setContentSize).not.toHaveBeenCalled();
    expect(onFitted).not.toHaveBeenCalled();
  });

  test('a height that is not a number keeps the size but still shows the window', () => {
    const win = fakeWindow();
    const onFitted = jest.fn();
    createFitHandler(win, { width: 400, onFitted })({ sender: win.webContents }, 'tall');
    expect(win.setContentSize).not.toHaveBeenCalled();
    expect(onFitted).toHaveBeenCalledTimes(1);
  });
});

describe('the passphrase prompt', () => {
  const main = fs.readFileSync(path.join(ROOT, 'app', 'main.js'), 'utf8');
  const start = main.indexOf('function promptPassphrase(');
  const body = main.slice(start, main.indexOf('\n}\n', start));

  test('is shown when its page reports its height, or after a second without a report', () => {
    expect(body).toContain("createFitHandler(win, { width: 400, onFitted: show })");
    expect(body).toContain("ipcMain.on('passphrase-prompt:fit', onFit)");
    expect(body).toContain('showTimer = setTimeout(show, 1000)');
    expect(body).not.toMatch(/once\('did-finish-load'[\s\S]*?designTokens\.showWindow\(win\)[\s\S]*?\}\);/);
  });

  test('stops listening when it is settled', () => {
    const settle = body.slice(body.indexOf('function settle('), body.indexOf('function onResult('));
    expect(settle).toContain("ipcMain.removeListener('passphrase-prompt:fit', onFit)");
    expect(settle).toContain('clearTimeout(showTimer)');
  });

  test('takes a result only from its own page', () => {
    const onResult = body.slice(body.indexOf('function onResult('), body.indexOf("ipcMain.on('passphrase-prompt:result'"));
    expect(onResult).toMatch(/^function onResult\(event, payload\) \{\s*if \(win\.isDestroyed\(\) \|\| event\.sender !== win\.webContents\) return;/);
  });

  test('its page reports the height once the font is in', () => {
    const page = fs.readFileSync(path.join(ROOT, 'app', 'passphrase-prompt.js'), 'utf8');
    expect(page).toMatch(/document\.fonts\.ready\.then\(\(\) => \{\s*window\.passphraseAPI\.fit\(/);
    const preload = fs.readFileSync(path.join(ROOT, 'app', 'preload-passphrase.js'), 'utf8');
    expect(preload).toContain("fit: (height) => ipcRenderer.send('passphrase-prompt:fit', height)");
  });
});
