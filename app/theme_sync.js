// One theme setting for the whole app: the Web UI's choice (the
// theme-preference cookie it saves, light, dark or system) becomes
// nativeTheme.themeSource, which Electron applies to the window frames and to
// prefers-color-scheme in every window. Each window then reads light or dark
// from Electron (window-theme.js), so nothing here works out whether the
// system is dark. The cookie is only read, never written back.
//
// Only the internal Web UI's origin is read (http://localhost:4567, where
// every entry to it goes). A missing or unknown value is system. While the Web
// UI is open it keeps its own choice until it loads again, so a cookie that
// expires or is removed under an open page is followed by the windows first.
const THEME_URL = 'http://localhost:4567/';
const COOKIE = 'theme-preference';
const CHOICES = ['light', 'dark', 'system'];

function normalizeChoice(value) {
  return CHOICES.includes(value) ? value : 'system';
}

function isThemeCookie(cookie) {
  return Boolean(cookie) && cookie.name === COOKIE && cookie.domain === 'localhost' && cookie.path === '/';
}

function createThemeSync({ cookies, nativeTheme, log = console.error, timeoutMs = 1000 }) {
  let generation = 0;
  let applied = null;

  function apply(choice) {
    if (choice === applied) return;
    applied = choice;
    nativeTheme.themeSource = choice;
  }

  // Each read is numbered; only the newest one is applied, so a slow read
  // never undoes a newer change. A read that fails keeps the choice in use
  // (system when there is none yet).
  function refresh() {
    const mine = ++generation;
    let reading;
    try {
      reading = Promise.resolve(cookies.get({ url: THEME_URL, name: COOKIE }));
    } catch (error) {
      reading = Promise.reject(error);
    }
    return reading.then((found) => {
      if (mine !== generation) return;
      const cookie = (found || []).find((c) => c.path === '/');
      apply(normalizeChoice(cookie && cookie.value));
    }, (error) => {
      try { log(`[theme] the theme setting could not be read (${reason(error)})`); } catch (_) { /* nothing more to do */ }
      if (mine === generation && applied === null) apply('system');
    });
  }

  // A change of any kind (set, overwritten, removed, expired) is a reason to
  // read the cookie again; the value in the notice is not used (a removal
  // carries the old one).
  cookies.on('changed', (_event, cookie) => {
    if (isThemeCookie(cookie)) refresh();
  });

  // Before the first window: the first read, or system after timeoutMs. A read
  // that ends later is still applied if nothing newer came.
  async function start() {
    let timer;
    const late = new Promise((resolve) => { timer = setTimeout(resolve, timeoutMs); });
    await Promise.race([refresh(), late]);
    clearTimeout(timer);
    if (applied === null) apply('system');
  }

  return { start, refresh, current: () => applied };
}

function reason(error) {
  const code = error && error.code;
  return typeof code === 'string' && /^[A-Z0-9_]+$/.test(code) ? code : 'no error code';
}

module.exports = { createThemeSync, normalizeChoice, isThemeCookie, THEME_URL };
