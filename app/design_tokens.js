// The Web UI's design variables (tokens.css: colours, radii, spacing and type,
// for the light theme and for .dark-theme) and its buttons (buttons.css, made
// from those variables) are given to the app's own windows too, so that all
// draw from one table. Only these are shared, not the Web UI's reset,
// Bootstrap or layout. The files are the ones the Web UI serves: in the source
// tree when run from it, under resources/app/docker in a package (the docker
// payload is made of tracked files).
const fs = require('fs');
const path = require('path');

const CSS = ['docker', 'services', 'ruby', 'public', 'css'];

function sheetPath(name, { packaged, resourcesPath, appDir }) {
  return packaged
    ? path.join(resourcesPath, 'app', ...CSS, name)
    : path.join(appDir, '..', ...CSS, name);
}

const tokensPath = (where) => sheetPath('tokens.css', where);
const buttonsPath = (where) => sheetPath('buttons.css', where);

// Read once. A file that cannot be read, or is empty, gives null and one log
// line, so a window is never given an empty sheet in its place. Logs carry an
// error code or a fixed reason, never an error's message (it can hold a path).
function createTokenLoader(file, { readFile = fs.readFileSync, log = console.error } = {}) {
  let css;
  return function load() {
    if (css !== undefined) return css;
    try {
      const text = readFile(file, 'utf8');
      css = text.trim() ? text : null;
      if (!css) log(`[design-tokens] ${path.basename(file)} is empty`);
    } catch (error) {
      css = null;
      log(`[design-tokens] ${path.basename(file)} cannot be read (${reason(error)})`);
    }
    return css;
  };
}

// The variables, then the buttons, as one sheet (put in at once, so their
// order holds). The buttons are left out without the variables: made of them,
// they would be drawn without colors or sizes, and the windows' own buttons
// are still usable as they are.
function createSheetsLoader({ tokens, buttons }, options) {
  const loadTokens = createTokenLoader(tokens, options);
  const loadButtons = createTokenLoader(buttons, options);
  return function load() {
    const variables = loadTokens();
    if (!variables) return null;
    const shapes = loadButtons();
    return shapes ? `${variables}\n${shapes}` : variables;
  };
}

// Puts the variables into a window's page; true when they are in. Never
// rejects: a window without them is shown as it is.
async function applyTokens(webContents, load, { log = console.error } = {}) {
  try {
    const css = load();
    if (!css || !webContents || webContents.isDestroyed()) return false;
    await webContents.insertCSS(css, { cssOrigin: 'author' });
    return true;
  } catch (error) {
    try { log(`[design-tokens] the variables could not be put into a window (${reason(error)})`); } catch (_) { /* nothing more to do */ }
    return false;
  }
}

function reason(error) {
  const code = error && error.code;
  return typeof code === 'string' && /^[A-Z0-9_]+$/.test(code) ? code : 'no error code';
}

// Every page a window loads gets them again (an inserted sheet lasts only for
// the page it was put into). Returns a promise for the first page: settled
// when its sheet is in, could not be put in, or timeoutMs has passed.
function shareTokens(webContents, load, { timeoutMs = 1000, ...options } = {}) {
  let first = true;
  let settle;
  const ready = new Promise((resolve) => { settle = resolve; });
  const timer = setTimeout(() => settle(), timeoutMs);
  webContents.on('dom-ready', () => {
    const applied = applyTokens(webContents, load, options);
    if (!first) return;
    first = false;
    applied.then(() => { clearTimeout(timer); settle(); });
  });
  return ready;
}

// A window made with show: false is shown once its first page has the
// variables (or the wait has run out), so it does not appear unstyled; later
// calls do not wait for that again. A show asked for before the window was
// closed or hidden (a closed console is only hidden) is dropped, and nothing
// is shown for a window destroyed meanwhile.
const windows = new WeakMap();

function prepareWindow(win, load, options) {
  const state = { ready: shareTokens(win.webContents, load, options), asked: 0 };
  windows.set(win, state);
  const drop = () => { state.asked += 1; };
  win.on('close', drop);
  win.on('hide', drop);
}

function showWindow(win, { focus = false } = {}) {
  const state = windows.get(win);
  const ask = state ? ++state.asked : 0;
  const ready = state ? state.ready : Promise.resolve();
  return ready.then(() => {
    if (!win || win.isDestroyed()) return false;
    if (state && state.asked !== ask) return false;
    win.show();
    if (focus) win.focus();
    return true;
  });
}

module.exports = { tokensPath, buttonsPath, createTokenLoader, createSheetsLoader, applyTokens, shareTokens, prepareWindow, showWindow };
