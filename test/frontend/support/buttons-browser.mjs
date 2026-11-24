// Measures the shared buttons (buttons.css) in a headless browser, on the
// pages that use them, with the stylesheets each page has in the app: the
// Web UI's message tools row (vendor-layers.css with Bootstrap, tokens.css,
// buttons.css, monadic.css) and the settings window's Save and Close
// (settings.html as it is, with tokens.css and buttons.css put in as the
// Electron window gets them). Run by buttons-browser.test.js as a child
// process (puppeteer is an ES module); prints what it measured as one JSON
// line.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(here, '../../..');
const PUBLIC = path.join(ROOT, 'docker/services/ruby/public');
const APP = path.join(ROOT, 'app');

const VIEW = fs.readFileSync(path.join(ROOT, 'docker/services/ruby/views/index.erb'), 'utf8');
const between = (from, to) => {
  const start = VIEW.indexOf(from);
  return VIEW.slice(start, VIEW.indexOf(to, start)).replace(/<%#[\s\S]*?%>/g, '');
};
// The row as the view has it, and the Send and Clear row (not moved yet)
// for the buttons next to it.
const TOOLS = `${between('<div class="d-flex align-items-center flex-wrap message-tools">', '</div>\n                </div>')}</div>`;
const SEND = between('<button id="send"', '<button id="clear"') + between('<button id="clear"', '</button>') + '</button>';

const WEB = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="/vendor/css/montserrat.css">
<link rel="stylesheet" href="/css/vendor-layers.css">
<link rel="stylesheet" href="/css/tokens.css">
<link rel="stylesheet" href="/css/buttons.css">
<link rel="stylesheet" href="/css/monadic.css">
<link rel="stylesheet" href="/vendor/css/all.min.css">
</head><body><div id="main"><div id="user-panel"><div id="tools-holder">${TOOLS}</div>
<div class="d-flex">${SEND}</div></div></div></body></html>`;

// The settings window as Electron loads it, with the shared sheets put in
// (or, for the window that cannot read them, left out).
const SETTINGS = fs.readFileSync(path.join(APP, 'settings.html'), 'utf8');
const settingsPage = (shared) => SETTINGS.replace('<head>', `<head><base href="/app/">${shared
  ? '<link rel="stylesheet" href="/css/tokens.css"><link rel="stylesheet" href="/css/buttons.css">'
  : ''}`);

const TYPES = { '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf' };

function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    const pages = { '/web': WEB, '/settings': settingsPage(true), '/settings-alone': settingsPage(false) };
    if (pages[url]) {
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(pages[url]);
      return;
    }
    const base = url.startsWith('/app/') ? APP : PUBLIC;
    const file = path.join(base, url.startsWith('/app/') ? url.slice(5) : url);
    if (!file.startsWith(base) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

// Each button's box and look; hidden ones are left out.
const measure = (ids) => {
  const out = {};
  ids.forEach((id) => {
    const el = document.getElementById(id);
    if (!el) { out[id] = null; return; }
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    out[id] = {
      width: r.width, height: r.height, top: r.top,
      bg: cs.backgroundColor, fg: cs.color, radius: cs.borderTopLeftRadius,
      minHeight: cs.minHeight, whiteSpace: cs.whiteSpace, opacity: cs.opacity, outline: cs.outlineStyle,
      cut: el.scrollWidth - el.clientWidth
    };
  });
  return out;
};

// Past the buttons' color transition.
const settled = () => new Promise((resolve) => { setTimeout(resolve, 300); });

const TOOL_IDS = ['image-file', 'doc', 'url', 'anonymize', 'voice'];
const SETTINGS_IDS = ['save-settings-btn', 'close-settings-btn'];

async function look(page, url, ids, { dark = false, width = 1280 } = {}) {
  await page.setViewport({ width, height: 800 });
  await page.goto(url);
  await page.evaluate(() => document.fonts.ready);
  if (dark) await page.evaluate(() => document.documentElement.classList.add('dark-theme'));
  await settled();
  return page.evaluate(measure, ids);
}

async function main() {
  const server = await serve();
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    page.on('pageerror', () => {}); // settings.html's script needs the window's preload; its look does not
    const out = {};
    out.web = await look(page, `${base}/web`, [...TOOL_IDS, 'send']);
    out.webDark = await look(page, `${base}/web`, TOOL_IDS, { dark: true });
    // Hover, then the keyboard's focus ring.
    await page.hover('#doc');
    await settled();
    out.webHover = await page.evaluate(() => getComputedStyle(document.getElementById('doc')).backgroundColor);
    await page.mouse.move(0, 0);
    await page.focus('#doc');
    await page.keyboard.press('Shift');
    out.webFocus = await page.evaluate(() => {
      const el = document.getElementById('doc');
      el.blur();
      el.focus({ focusVisible: true });
      return { outline: getComputedStyle(el).outlineStyle, matches: el.matches(':focus-visible') };
    });
    out.webDisabled = await page.evaluate(() => {
      const el = document.getElementById('doc');
      el.disabled = true;
      return getComputedStyle(el).opacity;
    });
    // A narrow row with long labels: the buttons wrap their text, nothing
    // is cut or sticks out of the row.
    await look(page, `${base}/web`, TOOL_IDS, { width: 320 });
    out.webNarrow = await page.evaluate((ids) => {
      ids.forEach((id) => { document.getElementById(id).lastChild.textContent = ' A label much longer than the button can hold on one line'; });
      const right = document.documentElement.clientWidth;
      return { out: ids.filter((id) => document.getElementById(id).getBoundingClientRect().right > right + 0.5) };
    }, TOOL_IDS);
    out.webNarrowButtons = await page.evaluate(measure, TOOL_IDS);
    out.settings = await look(page, `${base}/settings`, SETTINGS_IDS);
    out.settingsDark = await look(page, `${base}/settings`, SETTINGS_IDS, { dark: true });
    out.settingsAlone = await look(page, `${base}/settings-alone`, SETTINGS_IDS);
    process.stdout.write(`RESULT ${JSON.stringify(out)}\n`);
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((error) => {
  process.stderr.write(`${error && error.stack}\n`);
  process.exit(1);
});
