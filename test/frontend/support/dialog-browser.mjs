// Drives MonadicDialog (dialog.js) in a headless browser: the view's delete
// confirmation as it is, the real stylesheets (vendor-layers.css with
// Bootstrap, tokens, buttons, tooltip, dialog, monadic) and the real scripts
// (dom-helpers, tooltip, dialog, ws-input-handler for Easy Submit). Run by
// dialog-browser.test.js as a child process (puppeteer is an ES module);
// prints what it measured as one JSON line.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const here = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(here, '../../../docker/services/ruby/public');
const VIEW = fs.readFileSync(path.join(here, '../../../docker/services/ruby/views/index.erb'), 'utf8');
const start = VIEW.indexOf('<dialog class="mdialog" id="deleteConfirmation"');
const DELETE = VIEW.slice(start, VIEW.indexOf('</dialog>', start) + '</dialog>'.length).replace(/<%[\s\S]*?%>/g, '');

const PAGE = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="/css/vendor-layers.css"><link rel="stylesheet" href="/css/tokens.css">
<link rel="stylesheet" href="/css/buttons.css"><link rel="stylesheet" href="/css/tooltip.css">
<link rel="stylesheet" href="/css/dialog.css"><link rel="stylesheet" href="/css/monadic.css">
</head><body>
<input type="checkbox" id="check-easy-submit" checked><input type="checkbox" id="check-auto-speech">
<textarea id="message">a draft</textarea>
<button id="send" type="button">Send</button>
<button id="opener" type="button">Delete</button>
${DELETE}
<dialog class="mdialog" id="still" data-dialog-static aria-labelledby="still-title"><div class="modal-dialog"><div class="modal-content">
  <div class="modal-header"><h5 id="still-title">Passphrase</h5></div>
  <div class="modal-body"><input id="phrase" type="password"></div>
  <div class="modal-footer"><button type="button" class="btn btn-sm btn-secondary" data-dialog-close id="still-cancel">Cancel</button></div>
</div></div></dialog>
<script src="/js/monadic/dom-helpers.js"></script>
<script src="/js/monadic/tooltip.js"></script>
<script src="/js/monadic/dialog.js"></script>
<script src="/js/monadic/ws-input-handler.js"></script>
<script>
  window.sent = 0;
  document.getElementById('send').addEventListener('click', () => { window.sent += 1; });
  window.log = [];
  ['deleteConfirmation', 'still'].forEach((id) => ['mdialog:shown', 'mdialog:hide', 'mdialog:hidden'].forEach((type) =>
    document.getElementById(id).addEventListener(type, (e) => window.log.push(id + ' ' + type + ' ' + (e.detail.reason || '')))));
</script>
</body></html>`;

function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (url === '/') { res.writeHead(200, { 'content-type': 'text/html' }); res.end(PAGE); return; }
    const file = path.join(PUBLIC, url);
    if (!file.startsWith(PUBLIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'content-type': url.endsWith('.css') ? 'text/css' : 'text/javascript' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const wait = (ms) => new Promise((r) => { setTimeout(r, ms); });

async function main() {
  const server = await serve();
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1000, height: 700 });
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const look = () => page.evaluate(() => {
      const d = document.getElementById('deleteConfirmation');
      const panel = d.querySelector('.modal-content').getBoundingClientRect();
      const title = document.getElementById(d.getAttribute('aria-labelledby'));
      return {
        open: d.open, marked: document.documentElement.hasAttribute('data-dialog-open'),
        focused: document.activeElement && (document.activeElement.id || document.activeElement.textContent.trim()),
        named: title ? title.textContent.trim() : null,
        panel: { left: panel.left, right: panel.right, top: panel.top, bottom: panel.bottom, width: panel.width },
        face: getComputedStyle(d.querySelector('.modal-content')).backgroundColor,
        backdrop: d.open ? getComputedStyle(d, '::backdrop').backgroundColor : null,
        view: { width: innerWidth, height: innerHeight },
        log: window.log.splice(0), sent: window.sent
      };
    });
    const openIt = () => page.evaluate(() => { document.getElementById('opener').focus(); MonadicDialog.of(document.getElementById('deleteConfirmation')).open(document.getElementById('opener')); });
    const out = {};

    out.closedAtStart = await look();
    await openIt();
    await wait(250);
    out.opened = await look();

    // Easy Submit leaves Enter to the dialog while it is open.
    await page.keyboard.press('Enter');
    await wait(50);
    out.enterInside = await look();
    if (out.enterInside.open) await page.keyboard.press('Escape');
    await wait(50);
    out.afterEnterOrEsc = await look();

    // Esc closes it, once; the focus goes back to what opened it; Enter is
    // the chat's again.
    await openIt();
    await wait(100);
    await page.keyboard.press('Escape');
    await wait(50);
    out.escaped = await look();
    await page.evaluate(() => document.getElementById('opener').blur());
    await page.keyboard.press('Enter');
    await wait(50);
    out.enterAfter = await look();

    // The backdrop: a press outside the panel closes it; a drag from inside
    // to outside does not.
    await openIt();
    await wait(250);
    const { panel } = await look();
    await page.mouse.move((panel.left + panel.right) / 2, panel.top + 20);
    await page.mouse.down();
    await page.mouse.move(5, 5, { steps: 5 });
    await page.mouse.up();
    await wait(50);
    out.dragged = await look();
    await page.mouse.click(5, 5);
    await wait(50);
    out.backdrop = await look();

    // Its Cancel button, and close() refused by mdialog:hide.
    await openIt();
    await wait(100);
    out.refused = await page.evaluate(async () => {
      const d = document.getElementById('deleteConfirmation');
      const stop = (e) => e.preventDefault();
      d.addEventListener('mdialog:hide', stop);
      const closed = await MonadicDialog.of(d).close('button');
      d.removeEventListener('mdialog:hide', stop);
      return { closed, open: d.open };
    });
    out.refusedLook = await look();
    await page.click('#deleteConfirmation .modal-footer [data-dialog-close]');
    await wait(50);
    out.cancelled = await look();

    // Opened again while it closes: it opens once it has closed.
    out.reopened = await page.evaluate(async () => {
      const d = MonadicDialog.of(document.getElementById('deleteConfirmation'));
      d.open();
      const closing = d.close('button');
      d.open();
      const closed = await closing;
      await new Promise((r) => setTimeout(r, 50));
      return { closed, open: document.getElementById('deleteConfirmation').open };
    });
    await page.keyboard.press('Escape');
    await wait(50);
    out.reopenedLog = (await look()).log;

    // A tooltip shown in the dialog: the first Esc closes the tooltip only.
    await page.waitForFunction(() => !document.getElementById('deleteConfirmation').open);
    await openIt();
    await page.waitForFunction(() => document.getElementById('deleteConfirmation').open
      && document.activeElement && document.getElementById('deleteConfirmation').contains(document.activeElement));
    out.tooltip = await page.evaluate(() => {
      const button = document.querySelector('#deleteConfirmation #deleteConfirmButton');
      const tip = MonadicTip.attach(button, { title: 'Deletes what is chosen' });
      tip.show();
      const bubble = document.getElementById('monadic-tip');
      return { inDialog: bubble.parentNode.id };
    });
    await page.keyboard.press('Escape');
    await page.waitForFunction(() => document.getElementById('monadic-tip').hidden);
    out.firstEsc = await page.evaluate(() => ({ tip: !document.getElementById('monadic-tip').hidden, open: document.getElementById('deleteConfirmation').open }));
    await page.keyboard.press('Escape');
    await page.waitForFunction(() => !document.getElementById('deleteConfirmation').open, { timeout: 3000 }).catch(() => {});
    out.secondEsc = await page.evaluate(() => ({ open: document.getElementById('deleteConfirmation').open }));
    await look();

    // A static dialog: Esc and the backdrop leave it open; its button closes it.
    await page.evaluate(() => MonadicDialog.of(document.getElementById('still')).open());
    await wait(100);
    await page.keyboard.press('Escape');
    await page.mouse.click(5, 5);
    await wait(50);
    out.staticKept = await page.evaluate(() => ({ open: document.getElementById('still').open, focused: document.activeElement.id }));
    await page.click('#still-cancel');
    await wait(50);
    out.staticClosed = await page.evaluate(() => ({ open: document.getElementById('still').open, marked: document.documentElement.hasAttribute('data-dialog-open') }));

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
