// Drives MonadicTip (tooltip.js) in a headless browser with the real
// stylesheets (tokens.css, tooltip.css): where the bubble goes, moving onto
// it, the keyboard's focus, scrolling in a box, and the control taken off
// the page while shown. Run by tooltip-browser.test.js as a child process
// (puppeteer is an ES module); prints what it measured as one JSON line.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const here = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(here, '../../../docker/services/ruby/public');

const LONG = 'A long explanation that wraps over several lines, so that reading it takes a moment and the pointer may move onto it.';
const PAGE = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="/css/tokens.css"><link rel="stylesheet" href="/css/tooltip.css">
<style>body{margin:0;font:14px sans-serif} button{position:absolute} #box{position:absolute;top:200px;left:300px;width:200px;height:120px;overflow:auto;border:1px solid #ccc} #inner{height:600px;position:relative}</style>
</head><body>
<button id="top" style="top:2px;left:200px" title="At the top">Top</button>
<button id="right" style="top:300px;right:2px" title="${LONG}">Right</button>
<button id="first" style="top:400px;left:20px" title="First">First</button>
<button id="second" style="top:400px;left:120px" title="Second">Second</button>
<div id="box"><div id="inner"><button id="boxed" style="top:20px;left:20px" title="In a box">Boxed</button></div></div>
<div id="holder"><button id="gone" style="top:500px;left:20px" title="Goes away">Gone</button></div>
<script src="/js/monadic/tooltip.js"></script>
<script>
  ['top', 'right', 'first', 'second', 'boxed', 'gone'].forEach((id) => MonadicTip.attach(document.getElementById(id), { delay: { show: 0, hide: 0 } }));
</script>
</body></html>`;

function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (url === '/') { res.writeHead(200, { 'content-type': 'text/html' }); res.end(PAGE); return; }
    const file = path.join(PUBLIC, url);
    if (!file.startsWith(PUBLIC) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'content-type': url.endsWith('.css') ? 'text/css' : 'text/javascript' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const wait = (ms) => new Promise((r) => { setTimeout(r, ms); });
const state = (id) => {
  const b = document.getElementById('monadic-tip');
  const t = document.getElementById(id);
  const br = b ? b.getBoundingClientRect() : null;
  const tr = t ? t.getBoundingClientRect() : null;
  return {
    shown: !!b && !b.hidden,
    text: b ? b.textContent : '',
    bubble: br && { top: br.top, bottom: br.bottom, left: br.left, right: br.right },
    target: tr && { top: tr.top, bottom: tr.bottom },
    view: { width: document.documentElement.clientWidth, height: document.documentElement.clientHeight },
    describedBy: t ? t.getAttribute('aria-describedby') : null,
    bg: b ? getComputedStyle(b).backgroundColor : null,
    fg: b ? getComputedStyle(b).color : null
  };
};

async function main() {
  const server = await serve();
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 800, height: 600 });
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const out = {};

    // At the top edge it goes below; at the right edge it stays inside.
    await page.hover('#top');
    await wait(50);
    out.top = await page.evaluate(state, 'top');
    await page.hover('#right');
    await wait(50);
    out.right = await page.evaluate(state, 'right');

    // The pointer moving onto the bubble keeps it; leaving both hides it.
    const box = out.right.bubble;
    await page.mouse.move((box.left + box.right) / 2, (box.top + box.bottom) / 2, { steps: 4 });
    await wait(300);
    out.onBubble = await page.evaluate(state, 'right');
    await page.mouse.move(5, 590);
    await wait(300);
    out.afterLeaving = await page.evaluate(state, 'right');

    // The keyboard's focus shows it; a click's focus does not.
    await page.focus('#first');
    await page.keyboard.press('Tab');
    await wait(50);
    out.tabbed = await page.evaluate(state, 'second');
    await page.click('#first');
    await page.mouse.move(5, 590);
    await wait(300);
    out.clicked = await page.evaluate(state, 'first');

    // In a box that scrolls: it follows; scrolled out of view, it hides.
    await page.hover('#boxed');
    await wait(50);
    const before = await page.evaluate(state, 'boxed');
    await page.evaluate(() => { document.getElementById('box').scrollTop = 10; });
    await wait(50);
    const moved = await page.evaluate(state, 'boxed');
    out.scrolled = { followed: Math.abs((before.bubble.top - moved.bubble.top) - 10) <= 1, shown: moved.shown };
    await page.evaluate(() => { document.getElementById('box').scrollTop = 400; window.dispatchEvent(new Event('scroll')); });
    await wait(50);
    out.scrolledAway = await page.evaluate(state, 'boxed');

    // Taken off the page while shown, nothing else happening: it hides.
    await page.hover('#gone');
    await wait(50);
    out.goneBefore = await page.evaluate(state, 'gone');
    await page.evaluate(() => { document.getElementById('holder').innerHTML = ''; });
    await wait(50);
    out.goneAfter = await page.evaluate(state, 'gone');

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
