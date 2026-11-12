// Drives AbcPlayer in a headless browser (run by abc-player-browser.test.js
// as a child process: puppeteer is an ES module): a tune is made ready to
// play, and every request the page makes is recorded. Prints one JSON line.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const here = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(here, '../../../docker/services/ruby/public');
const PAGE = '<!doctype html><meta charset="utf-8"><div id="controls"></div>'
  + '<script src="/vendor/js/abcjs-basic-min.min.js"></script><script src="/js/monadic/abc-player.js"></script>';

function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (url === '/') {
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(PAGE);
      return;
    }
    const allowed = url === '/vendor/js/abcjs-basic-min.min.js' || url === '/js/monadic/abc-player.js' ||
      (url.startsWith('/vendor/soundfont/') && !url.includes('..'));
    const file = path.join(PUBLIC, url);
    if (!allowed || !fs.existsSync(file)) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { 'content-type': url.endsWith('.mp3') ? 'audio/mpeg' : 'text/javascript' });
    res.end(fs.readFileSync(file));
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const server = await serve();
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--autoplay-policy=no-user-gesture-required'] });
const out = { requests: [], outside: [], failed: [] };
try {
  const page = await browser.newPage();
  await page.setRequestInterception(true);
  page.on('request', (req) => {
    const url = req.url();
    if (url.startsWith(base)) {
      out.requests.push(url.slice(base.length));
      req.continue();
    } else {
      if (!url.startsWith('data:')) out.outside.push(url);
      req.abort();
    }
  });
  page.on('requestfailed', (req) => { if (req.url().startsWith(base)) out.failed.push(req.url().slice(base.length)); });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(base);
  Object.assign(out, await page.evaluate(async () => {
    const holder = document.getElementById('controls');
    // A violin (40) is played as strings; the second voice is a piano.
    const tune = 'X:1\nT:Two\nM:4/4\nL:1/4\nK:C\nV:1\n%%MIDI program 40\nCDEF|\nV:2\n%%MIDI program 0\nC,E,G,C|';
    const player = await window.AbcPlayer.playerFor(holder, tune);
    const control = holder.querySelector('.abcjs-inline-audio');
    // The controls start loading the sounds when asked to play.
    holder.querySelector('.abcjs-midi-start').click();
    await new Promise((r) => setTimeout(r, 4000));
    player.stop();
    return { controls: !!control };
  }));
  out.errors = errors;
} finally {
  await browser.close();
  server.close();
}
console.log(`RESULT ${JSON.stringify(out)}`);
