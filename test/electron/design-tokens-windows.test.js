// The app's own windows get the Web UI's design variables from the same
// tokens.css, never an empty sheet in its place.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { tokensPath, createTokenLoader, applyTokens, shareTokens, prepareWindow, showWindow } = require('../../app/design_tokens');

const ROOT = path.join(__dirname, '..', '..');
const TOKENS = 'docker/services/ruby/public/css/tokens.css';

function fakeContents({ destroyed = false, insert = jest.fn().mockResolvedValue('key') } = {}) {
  const handlers = {};
  return {
    insertCSS: insert,
    isDestroyed: () => destroyed,
    on: (event, fn) => { (handlers[event] = handlers[event] || []).push(fn); },
    emit: (event) => (handlers[event] || []).forEach((fn) => fn()),
    handlers
  };
}

describe('where the variables are read from', () => {
  test('from the source tree when run from it: the file the Web UI serves', () => {
    const file = tokensPath({ packaged: false, resourcesPath: '/unused', appDir: path.join(ROOT, 'app') });
    expect(path.relative(ROOT, file)).toBe(path.join(...TOKENS.split('/')));
    expect(fs.readFileSync(file, 'utf8')).toMatch(/--/);
  });

  test('from the docker payload in a package, which ships tracked files only', () => {
    const file = tokensPath({ packaged: true, resourcesPath: '/R', appDir: '/unused' });
    expect(file).toBe(path.join('/R', 'app', ...TOKENS.split('/')));
    expect(() => execFileSync('git', ['ls-files', '--error-unmatch', TOKENS], { cwd: ROOT, stdio: 'ignore' })).not.toThrow();
  });
});

describe('reading the variables', () => {
  test('reads the file once', () => {
    const readFile = jest.fn().mockReturnValue(':root { --x: 1px; }');
    const load = createTokenLoader('/t.css', { readFile, log: jest.fn() });
    expect(load()).toBe(':root { --x: 1px; }');
    expect(load()).toBe(':root { --x: 1px; }');
    expect(readFile).toHaveBeenCalledTimes(1);
  });

  test('gives nothing, and says so once, for a file that cannot be read or is empty', () => {
    const log = jest.fn();
    const missing = createTokenLoader('/t.css', { readFile: () => { throw Object.assign(new Error('x'), { code: 'ENOENT' }); }, log });
    expect(missing()).toBeNull();
    expect(missing()).toBeNull();
    expect(log).toHaveBeenCalledTimes(1);
    expect(log.mock.calls[0][0]).toContain('ENOENT');

    const empty = createTokenLoader('/t.css', { readFile: () => ' \n', log });
    expect(empty()).toBeNull();
  });
});

describe('putting them into a window', () => {
  test('inserts the sheet as an author sheet', async () => {
    const contents = fakeContents();
    expect(await applyTokens(contents, () => ':root{}')).toBe(true);
    expect(contents.insertCSS).toHaveBeenCalledWith(':root{}', { cssOrigin: 'author' });
  });

  test('inserts nothing when there is no sheet or the window is gone', async () => {
    const contents = fakeContents();
    expect(await applyTokens(contents, () => null)).toBe(false);
    const gone = fakeContents({ destroyed: true });
    expect(await applyTokens(gone, () => ':root{}')).toBe(false);
    expect(contents.insertCSS).not.toHaveBeenCalled();
    expect(gone.insertCSS).not.toHaveBeenCalled();
  });

  test('logs an error code or a fixed reason, never the message', async () => {
    const log = jest.fn();
    const load = createTokenLoader('/t.css', { readFile: () => { throw new Error('open /secret/path/tokens.css'); }, log });
    expect(load()).toBeNull();
    const contents = fakeContents({ insert: jest.fn().mockRejectedValue(new Error('failed for /secret/path')) });
    await applyTokens(contents, () => ':root{}', { log });
    expect(log).toHaveBeenCalledTimes(2);
    log.mock.calls.forEach(([line]) => {
      expect(line).not.toContain('/secret');
      expect(line).toContain('no error code');
    });
  });

  test('does not reject when reading the sheet or logging throws', async () => {
    const contents = fakeContents();
    await expect(applyTokens(contents, () => { throw new Error('x'); }, { log: () => { throw new Error('y'); } })).resolves.toBe(false);
  });

  test('a failed insert is logged and does not reject', async () => {
    const log = jest.fn();
    const contents = fakeContents({ insert: jest.fn().mockRejectedValue(new Error('no')) });
    await expect(applyTokens(contents, () => ':root{}', { log })).resolves.toBe(false);
    expect(log).toHaveBeenCalledTimes(1);
  });

  test('the first page is ready once its sheet is in, and at the latest after the wait', async () => {
    jest.useFakeTimers();
    try {
      let finish;
      const slow = fakeContents({ insert: jest.fn(() => new Promise((r) => { finish = r; })) });
      let done = false;
      shareTokens(slow, () => ':root{}', { timeoutMs: 1000 }).then(() => { done = true; });
      slow.emit('dom-ready');
      await Promise.resolve();
      expect(done).toBe(false);
      finish();
      await jest.advanceTimersByTimeAsync(0);
      expect(done).toBe(true);

      const never = fakeContents();
      let timedOut = false;
      shareTokens(never, () => ':root{}', { timeoutMs: 1000 }).then(() => { timedOut = true; });
      await jest.advanceTimersByTimeAsync(999);
      expect(timedOut).toBe(false);
      await jest.advanceTimersByTimeAsync(1);
      expect(timedOut).toBe(true);
    } finally {
      jest.useRealTimers();
    }
  });

  test('a window is shown only after its first page is ready, and never once it is closed', async () => {
    let finish;
    const contents = fakeContents({ insert: jest.fn(() => new Promise((r) => { finish = r; })) });
    let destroyed = false;
    const win = { webContents: contents, isDestroyed: () => destroyed, show: jest.fn(), focus: jest.fn(), on: jest.fn() };
    prepareWindow(win, () => ':root{}');
    contents.emit('dom-ready');
    const shown = showWindow(win, { focus: true });
    await Promise.resolve();
    expect(win.show).not.toHaveBeenCalled();
    finish();
    expect(await shown).toBe(true);
    expect(win.show).toHaveBeenCalledTimes(1);
    expect(win.focus).toHaveBeenCalledTimes(1);

    destroyed = true;
    expect(await showWindow(win)).toBe(false);
    expect(win.show).toHaveBeenCalledTimes(1);
  });

  test('a show asked for before the window was closed (only hidden) is dropped; a later one is not', async () => {
    let finish;
    const contents = fakeContents({ insert: jest.fn(() => new Promise((r) => { finish = r; })) });
    const handlers = {};
    const events = [];
    const win = {
      webContents: contents,
      isDestroyed: () => false,
      show: jest.fn(() => events.push('show')),
      focus: jest.fn(),
      hide: jest.fn(() => { events.push('hide'); (handlers.hide || []).forEach((fn) => fn()); }),
      on: (event, fn) => { (handlers[event] = handlers[event] || []).push(fn); }
    };
    prepareWindow(win, () => ':root{}');
    contents.emit('dom-ready');
    const first = showWindow(win);
    (handlers.close || []).forEach((fn) => fn());
    win.hide();
    finish();
    expect(await first).toBe(false);
    expect(events).toEqual(['hide']);

    expect(await showWindow(win)).toBe(true);
    expect(events).toEqual(['hide', 'show']);
  });

  test('every page the window loads gets them again', () => {
    const contents = fakeContents();
    shareTokens(contents, () => ':root{}');
    contents.emit('dom-ready');
    contents.emit('dom-ready');
    expect(contents.insertCSS).toHaveBeenCalledTimes(2);
  });
});

describe("the app's windows", () => {
  const main = fs.readFileSync(path.join(ROOT, 'app', 'main.js'), 'utf8');

  test.each([
    ['the console', 'mainWindow', "mainWindow.loadFile(path.join(__dirname, 'index.html'))"],
    ['settings', 'settingsWindow', "settingsWindow.loadFile(path.join(__dirname, 'settings.html'))"],
    ['the passphrase prompt', 'win', "win.loadFile(path.join(__dirname, 'passphrase-prompt.html'))"]
  ])('%s gets the variables before its page loads', (_name, variable, load) => {
    const share = main.indexOf(`designTokens.prepareWindow(${variable}, loadDesignTokens)`);
    const loads = main.indexOf(load);
    expect(share).toBeGreaterThan(-1);
    expect(loads).toBeGreaterThan(share);
  });
});
