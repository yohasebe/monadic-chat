// Drives the page's two columns in a headless browser with the real
// stylesheets (vendor-layers.css with Bootstrap, tokens.css, monadic.css)
// and layout-controller.js (run by layout-browser.test.js as a child
// process: puppeteer is an ES module). The page has the columns' structure
// of views/index.erb with long content; each case prints what it measured
// as one JSON line.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const here = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(here, '../../../docker/services/ruby/public');

const filler = (n, word) => Array.from({ length: n }, (_, i) => `<p>${word} ${i}</p>`).join('');
const PAGE = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="/vendor/css/montserrat.css">
<link rel="stylesheet" href="/css/vendor-layers.css">
<link rel="stylesheet" href="/css/tokens.css">
<link rel="stylesheet" href="/css/monadic.css">
</head><body>
<nav class="navbar fixed-top" style="height:65px"></nav>
<button id="toggle-menu"></button>
<div class="container-fluid pt-0 p-3" id="contents">
  <div class="row g-3 mt-0 mb-0 row-no-bottom-margin">
    <div id="menu" class="order-md-2 scrollable">
      <div id="side-pane-tabs" class="side-pane-tabs rounded mb-2" role="tablist">
        <button type="button" id="side-tab-settings" class="side-pane-tab" role="tab" aria-selected="true" aria-controls="settings-pane" data-pane="settings">Menu</button>
        <button type="button" id="side-tab-work" class="side-pane-tab" role="tab" aria-selected="false" aria-controls="work-screen-pane" data-pane="work" tabindex="-1">Work screen</button>
        <button type="button" id="side-tab-files" class="side-pane-tab" role="tab" aria-selected="false" aria-controls="shared-files-pane" data-pane="files" tabindex="-1">Shared folder</button>
      </div>
      <div id="settings-pane" role="tabpanel">${filler(80, 'setting')}</div>
      <div id="work-screen-pane" role="tabpanel" hidden></div>
      <div id="shared-files-pane" role="tabpanel" hidden></div>
    </div>
    <div id="side-pane-splitter" role="separator" aria-orientation="vertical" tabindex="0" hidden></div>
    <div id="main" class="order-md-1 scrollable">
      <div id="config-summary" class="rounded shaded-panel mb-2 config-summary-locked"><span class="summary-label">Current settings</span></div>
      <div id="config-wrapper"><div id="config-body">${filler(40, 'config')}</div></div>
      <div id="main-panel"><pre id="wide">${'x'.repeat(3000)}</pre>${filler(80, 'message')}</div>
    </div>
  </div>
</div>
<script src="/js/monadic/dom-helpers.js"></script>
<script src="/js/monadic/cookie-utils.js"></script>
<script src="/js/monadic/layout-controller.js"></script>
<script>window.LayoutController.apply();</script>
</body></html>`;

const TYPES = { '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf' };

function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (url === '/') {
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(PAGE);
      return;
    }
    const file = path.join(PUBLIC, url);
    if (!file.startsWith(PUBLIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

// What the page shows of the columns, once drawn: a width set on the row
// reaches the columns' computed flex in the next frame, so two frames are
// waited for first.
const measure = async () => {
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  const box = (id) => {
    const el = document.getElementById(id);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { left: r.left, right: r.right, top: r.top, width: r.width, shown: getComputedStyle(el).display !== 'none' && !el.hidden };
  };
  return {
    menu: box('menu'), main: box('main'), handle: box('side-pane-splitter'),
    summary: box('config-summary'), tabs: box('side-pane-tabs'),
    width: window.LayoutController.sideWidth(),
    rem: parseFloat(getComputedStyle(document.documentElement).fontSize),
    said: Number(document.getElementById('side-pane-splitter').getAttribute('aria-valuenow')),
    drawnPct: (() => {
      const m = document.getElementById('menu').getBoundingClientRect().width;
      const row = document.getElementById('menu').parentElement.getBoundingClientRect().width;
      return row ? Math.round((m / row) * 100) : null;
    })(),
    // How far the border's middle is from the gap between the columns, and
    // how much of each tab's label does not fit.
    handleOff: (() => {
      const h = document.getElementById('side-pane-splitter').getBoundingClientRect();
      const m = document.getElementById('menu').getBoundingClientRect();
      const c = document.getElementById('main').getBoundingClientRect();
      return h.width ? Math.round(Math.abs((h.left + h.width / 2) - (c.right + m.left) / 2)) : null;
    })(),
    tabsCut: Array.from(document.querySelectorAll('.side-pane-tab')).map((b) => b.scrollWidth - b.clientWidth),
    stored: (() => { try { return localStorage.getItem('monadic-side-pane-width'); } catch (_) { return null; } })()
  };
};

async function wide(browser, base) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });
  await page.goto(base);
  await page.evaluate(() => document.fonts.ready);
  const out = { before: await page.evaluate(measure) };
  // Both columns scrolled: the bars stay at the top of their columns.
  await page.evaluate(() => { document.getElementById('main').scrollTop = 1500; document.getElementById('menu').scrollTop = 1500; });
  out.scrolled = await page.evaluate(measure);
  out.scrolledBy = await page.evaluate(() => [document.getElementById('main').scrollTop, document.getElementById('menu').scrollTop]);
  // Dragging the border 128 px to the left (10 % of the row).
  const h = out.scrolled.handle;
  const x = h.left + h.width / 2;
  await page.mouse.move(x, 400);
  await page.mouse.down();
  await page.mouse.move(x - 64, 400, { steps: 4 });
  out.dragging = await page.evaluate(() => document.body.classList.contains('side-pane-resizing'));
  await page.mouse.move(x - 128, 400, { steps: 4 });
  await page.mouse.up();
  out.dragged = await page.evaluate(measure);
  // The same width for every pane.
  await page.evaluate(() => window.LayoutController.setPane('work'));
  out.work = await page.evaluate(measure);
  await page.evaluate(() => window.LayoutController.setPane('files'));
  out.files = await page.evaluate(measure);
  // Hidden column, and back.
  await page.evaluate(() => window.LayoutController.setMenuHidden(true));
  out.hidden = await page.evaluate(measure);
  await page.evaluate(() => window.LayoutController.setMenuHidden(false));
  out.back = await page.evaluate(measure);
  // Narrow (767): the columns take turns at full width; no border.
  await page.setViewport({ width: 767, height: 800 });
  await page.evaluate(() => window.LayoutController.apply());
  out.narrow = await page.evaluate(measure);
  await page.setViewport({ width: 768, height: 800 });
  await page.evaluate(() => window.LayoutController.apply());
  out.at768 = await page.evaluate(measure);
  // At 768 px the side column narrowest: its tabs still fit, and the
  // conversation keeps its room.
  await page.evaluate(() => window.LayoutController.setSideWidth(25));
  out.narrowest = await page.evaluate(measure);
  // One press of ← widens it from the width as drawn.
  await page.focus('#side-pane-splitter');
  await page.keyboard.press('ArrowLeft');
  out.afterKey = await page.evaluate(measure);
  await page.evaluate(() => window.LayoutController.setSideWidth(60));
  out.widest = await page.evaluate(measure);
  await page.evaluate(() => window.LayoutController.setSideWidth(50.1));
  // A new page load keeps the width.
  await page.setViewport({ width: 1280, height: 800 });
  await page.reload();
  out.reloaded = await page.evaluate(measure);
  await page.close();
  return out;
}

const server = await serve();
let browser = null;
let failed = false;
try {
  browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  const base = `http://127.0.0.1:${server.address().port}/`;
  process.stdout.write(`RESULT ${JSON.stringify(await wide(browser, base))}\n`);
} catch (e) {
  failed = true;
  process.stderr.write(`${e.stack || e}\n`);
} finally {
  if (browser) {
    try { await browser.close(); } catch (e) { failed = true; process.stderr.write(`browser close: ${e}\n`); }
  }
  try { await new Promise((resolve, reject) => server.close((e) => (e ? reject(e) : resolve()))); } catch (e) {
    failed = true;
    process.stderr.write(`server close: ${e}\n`);
  }
}
process.exit(failed ? 1 : 0);
