// The Web UI's theme choice is the one theme setting: it becomes the native
// theme, read again on every change, with a slow read never undoing a newer one.
const fs = require('fs');
const path = require('path');
const { createThemeSync, normalizeChoice, isThemeCookie, THEME_URL } = require('../../app/theme_sync');

function fakeCookies() {
  const listeners = [];
  const reads = [];
  return {
    get: jest.fn((filter) => new Promise((resolve, reject) => { reads.push({ filter, resolve, reject }); })),
    on: (event, fn) => { if (event === 'changed') listeners.push(fn); },
    change: (cookie) => listeners.forEach((fn) => fn({}, cookie, 'explicit', false)),
    reads
  };
}

const cookie = (value, extra = {}) => ({ name: 'theme-preference', value, domain: 'localhost', path: '/', ...extra });
const flush = () => new Promise((r) => setTimeout(r, 0));

describe('the theme choice', () => {
  test('is light, dark or system; anything else is system', () => {
    expect(['light', 'dark', 'system', undefined, '', 'Dark', 'blue'].map(normalizeChoice))
      .toEqual(['light', 'dark', 'system', 'system', 'system', 'system', 'system']);
  });

  test('is read from the internal Web UI only, at its root path', () => {
    expect(THEME_URL).toBe('http://localhost:4567/');
    expect(isThemeCookie(cookie('dark'))).toBe(true);
    expect(isThemeCookie(cookie('dark', { domain: '127.0.0.1' }))).toBe(false);
    expect(isThemeCookie(cookie('dark', { path: '/x' }))).toBe(false);
    expect(isThemeCookie({ ...cookie('dark'), name: 'other' })).toBe(false);
  });
});

describe('following the choice', () => {
  test('applies the first read before the first window', async () => {
    const cookies = fakeCookies();
    const nativeTheme = { themeSource: 'system' };
    const sync = createThemeSync({ cookies, nativeTheme });
    const started = sync.start();
    expect(cookies.reads[0].filter).toEqual({ url: THEME_URL, name: 'theme-preference' });
    cookies.reads[0].resolve([cookie('dark')]);
    await started;
    expect(nativeTheme.themeSource).toBe('dark');
  });

  test('starts with system when the read is slow, and takes the read when it comes', async () => {
    jest.useFakeTimers();
    try {
      const cookies = fakeCookies();
      const nativeTheme = { themeSource: 'x' };
      const sync = createThemeSync({ cookies, nativeTheme, timeoutMs: 1000 });
      const started = sync.start();
      await jest.advanceTimersByTimeAsync(1000);
      await started;
      expect(nativeTheme.themeSource).toBe('system');
      cookies.reads[0].resolve([cookie('light')]);
      await jest.advanceTimersByTimeAsync(0);
      expect(nativeTheme.themeSource).toBe('light');
    } finally {
      jest.useRealTimers();
    }
  });

  test('reads again on a change, and a slow older read never undoes a newer one', async () => {
    const cookies = fakeCookies();
    const nativeTheme = { themeSource: 'system' };
    const sync = createThemeSync({ cookies, nativeTheme });
    const started = sync.start();
    cookies.reads[0].resolve([cookie('light')]);
    await started;

    cookies.change(cookie('dark'));
    cookies.change(cookie('system'));
    expect(cookies.reads).toHaveLength(3);
    cookies.reads[2].resolve([cookie('system')]);
    await flush();
    cookies.reads[1].resolve([cookie('dark')]);
    await flush();
    expect(nativeTheme.themeSource).toBe('system');
  });

  test('a removed cookie is read again (the notice carries the old value) and gives system', async () => {
    const cookies = fakeCookies();
    const nativeTheme = { themeSource: 'system' };
    const sync = createThemeSync({ cookies, nativeTheme });
    const started = sync.start();
    cookies.reads[0].resolve([cookie('dark')]);
    await started;
    cookies.change(cookie('dark'));
    cookies.reads[1].resolve([]);
    await flush();
    expect(nativeTheme.themeSource).toBe('system');
  });

  test('ignores other cookies, and keeps the choice in use when a read fails', async () => {
    const cookies = fakeCookies();
    const nativeTheme = { themeSource: 'system' };
    const log = jest.fn();
    const sync = createThemeSync({ cookies, nativeTheme, log });
    const started = sync.start();
    cookies.reads[0].resolve([cookie('dark')]);
    await started;
    cookies.change(cookie('light', { domain: '127.0.0.1' }));
    expect(cookies.reads).toHaveLength(1);
    cookies.change(cookie('light'));
    cookies.reads[1].reject(Object.assign(new Error('/some/path'), { code: 'EIO' }));
    await flush();
    expect(nativeTheme.themeSource).toBe('dark');
    expect(log.mock.calls[0][0]).toContain('EIO');
    expect(log.mock.calls[0][0]).not.toContain('/some');
  });

  test('sets the native theme only when the choice changes', async () => {
    const cookies = fakeCookies();
    const writes = [];
    const nativeTheme = { set themeSource(v) { writes.push(v); }, get themeSource() { return writes[writes.length - 1]; } };
    const sync = createThemeSync({ cookies, nativeTheme });
    const started = sync.start();
    cookies.reads[0].resolve([cookie('dark')]);
    await started;
    cookies.change(cookie('dark'));
    cookies.reads[1].resolve([cookie('dark')]);
    await flush();
    expect(writes).toEqual(['dark']);
  });
});

describe('the windows', () => {
  const app = path.join(__dirname, '..', '..', 'app');

  test.each(['index.html', 'settings.html', 'passphrase-prompt.html'])('%s marks its theme in <head>, before it is drawn', (page) => {
    const html = fs.readFileSync(path.join(app, page), 'utf8');
    const head = html.slice(0, html.indexOf('</head>'));
    expect(head).toMatch(/<script src="(\.\/)?window-theme\.js"><\/script>/);
  });

  test('the theme setting is read before the app makes its first window', () => {
    const main = fs.readFileSync(path.join(app, 'main.js'), 'utf8');
    const start = main.indexOf('await themeSync.start();');
    expect(start).toBeGreaterThan(-1);
    expect(main.indexOf('initializeApp();', start)).toBeGreaterThan(start);
    expect(main.slice(main.indexOf('app.whenReady().then('), start)).not.toContain('initializeApp();');
  });
});
