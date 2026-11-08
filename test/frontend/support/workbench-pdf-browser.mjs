// Drives WorkbenchPdf with the pinned pdf.js in a headless browser (run by
// workbench-pdf-browser.test.js as a child process: puppeteer is an ES
// module). Each case shows PDFs in turn, letting the one before go (once it
// is drawn, or at once while it loads), and prints what the last one drew,
// with the page's errors and unhandled rejections, as one JSON line.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const here = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(here, '../../../docker/services/ruby/public');
const VENDOR = path.join(PUBLIC, 'vendor/pdfjs');

// A PDF of the given pages, each saying "Page n of total" in Helvetica.
function makePdf(total) {
  const objects = ['<< /Type /Catalog /Pages 2 0 R >>', null, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
  const kids = [];
  for (let n = 1; n <= total; n += 1) {
    const content = `BT /F1 24 Tf 72 720 Td (Page ${n} of ${total}) Tj ET`;
    kids.push(`${objects.length + 1} 0 R`);
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${objects.length + 2} 0 R >>`);
    objects.push(`<< /Length ${content.length} >>\nstream\n${content}\nendstream`);
  }
  objects[1] = `<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${total} >>`;
  let out = '%PDF-1.4\n';
  const offsets = [];
  objects.forEach((body, i) => {
    offsets.push(out.length);
    out += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = out.length;
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  offsets.forEach((o) => { out += `${String(o).padStart(10, '0')} 00000 n \n`; });
  out += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, 'latin1').toString('base64');
}

const TYPES = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm' };
const PAGE = '<!doctype html><meta charset="utf-8"><div id="box" style="width:600px"></div>'
  + '<script src="/js/monadic/workbench-pdf.js"></script>';

// The page, the work screen's script and the pinned pdf.js only.
function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (url === '/') {
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(PAGE);
      return;
    }
    let file = null;
    if (url === '/js/monadic/workbench-pdf.js') file = path.join(PUBLIC, url);
    else if (url.startsWith('/vendor/pdfjs/')) file = path.join(VENDOR, url.slice('/vendor/pdfjs/'.length));
    if (!file || !file.startsWith(PUBLIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

async function runCase(browser, base, pdfs, atOnce) {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.evaluateOnNewDocument(() => {
    window.__rejections = [];
    window.addEventListener('unhandledrejection', (e) => {
      window.__rejections.push(String((e.reason && e.reason.message) || e.reason));
    });
  });
  try {
    await page.goto(base);
    const result = await page.evaluate(async (list, letGoAtOnce) => {
      const box = document.getElementById('box');
      const bytes = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)).buffer;
      // pdf.js as the page loads it, telling when a document is asked for
      // (to let one go while it loads, not before its loading task exists).
      const asked = [];
      const load = window.WorkbenchPdf.loader;
      window.WorkbenchPdf.loader = () => Promise.resolve(load()).then((lib) => {
        if (lib.__watched) return lib;
        const getDocument = lib.getDocument.bind(lib);
        const watched = Object.create(lib);
        watched.__watched = true;
        watched.getDocument = (options) => { const task = getDocument(options); asked.push(task); return task; };
        return watched;
      });
      const show = (b64, last) => new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('not drawn in time')), 20000);
        const before = asked.length;
        const handle = window.WorkbenchPdf.show(box, bytes(b64), (shown) => {
          if (shown.status === 'ready') { clearTimeout(timer); resolve({ handle, shown }); }
          if (shown.status === 'failed') { clearTimeout(timer); reject(new Error('the PDF failed')); }
        });
        if (letGoAtOnce && !last) {
          // Let go once its document is asked for and still loading.
          const waitAsked = () => {
            if (asked.length > before) { clearTimeout(timer); resolve({ handle, shown: null }); } else setTimeout(waitAsked, 1);
          };
          waitAsked();
        }
      });
      let before = null;
      for (let i = 0; i < list.length; i += 1) {
        if (before) before.handle.dispose();
        before = await show(list[i], i === list.length - 1);
      }
      // A moment for anything late from the documents let go.
      await new Promise((r) => setTimeout(r, 500));
      const canvas = box.querySelector('canvas');
      return {
        shown: before.shown,
        canvas: canvas ? [canvas.width, canvas.height] : null,
        text: (box.querySelector('.textLayer') || {}).textContent || '',
        rejections: window.__rejections
      };
    }, pdfs, atOnce);
    return { ...result, errors };
  } catch (e) {
    return { failed: e.message, errors };
  } finally {
    await page.close();
  }
}

// The browser and the server are closed whatever happens, each on its own:
// a failure to close one still closes the other, and fails the run.
const server = await serve();
let browser = null;
let failed = false;
try {
  browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  const base = `http://127.0.0.1:${server.address().port}/`;
  const out = {
    afterDrawn: await runCase(browser, base, [makePdf(1), makePdf(3)], false),
    whileLoading: await runCase(browser, base, [makePdf(2), makePdf(4)], true)
  };
  process.stdout.write(`RESULT ${JSON.stringify(out)}\n`);
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
