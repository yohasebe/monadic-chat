// Drives WorkbenchRender in a headless browser (run by
// workbench-render-browser.test.js as a child process: puppeteer is an ES
// module), with the pinned Mermaid and the built Vega worker. Every address
// a drawn file names points at this server's /probe, which counts what
// reaches it: nothing should. Prints one JSON line.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const here = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(here, '../../../docker/services/ruby/public');
const FORMATS = fs.readFileSync(path.join(here, '../../../docker/services/ruby/lib/monadic/render_formats.json'), 'utf8');
const PAGE = '<!doctype html><meta charset="utf-8"><div id="box" style="width:700px;height:500px"></div>'
  + `<script type="application/json" id="render-formats">${FORMATS}</script>`
  + '<script src="/vendor/js/purify.min.js"></script><script src="/vendor/js/markdown-it.min.js"></script>'
  + '<script src="/js/monadic/text-utils.js"></script><script src="/js/monadic/workbench-render.js"></script>'
  + '<script src="/js/monadic/render-registry.js"></script>';
const FILES = ['/js/monadic/render-registry.js', '/vendor/js/purify.min.js', '/vendor/js/markdown-it.min.js', '/vendor/js/mermaid.min.js', '/js/monadic/text-utils.js',
  '/js/monadic/workbench-render.js', '/vendor/vega/vega-worker.mjs'];

const probes = [];

function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (url.startsWith('/probe')) {
      probes.push(url);
      res.writeHead(200, { 'content-type': 'image/png' });
      res.end();
      return;
    }
    if (url === '/') {
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(PAGE);
      return;
    }
    if (!FILES.includes(url)) {
      res.writeHead(404);
      res.end();
      return;
    }
    const headers = { 'content-type': 'text/javascript' };
    // As the server sends it (Monadic::Workbench::WorkerPolicy).
    if (url === '/vendor/vega/vega-worker.mjs') headers['content-security-policy'] = "default-src 'none'";
    res.writeHead(200, headers);
    res.end(fs.readFileSync(path.join(PUBLIC, url)));
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const server = await serve();
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
const out = {};
try {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(base);
  Object.assign(out, await page.evaluate(async (base) => {
    const box = document.getElementById('box');
    const P = (name) => `${base}/probe-${name}`;
    const result = { drawn: {}, refused: {}, frames: {} };
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    async function run(name, kind, text, opts) {
      const handle = WorkbenchRender.draw(box, kind, text, opts);
      try {
        await handle.done;
        const img = box.querySelector('img.workbench-svg');
        if (img) await (img.complete ? Promise.resolve() : new Promise((r) => img.addEventListener('load', r, { once: true })));
        result.drawn[name] = img ? { width: img.naturalWidth, height: img.naturalHeight } : box.firstElementChild && box.firstElementChild.tagName;
      } catch (e) {
        result.refused[name] = e instanceof WorkbenchRender.Refused ? `refused: ${e.message}` : `failed: ${e.message}`;
      }
      return handle;
    }

    // A page with every way to load or move the sanitizer is to remove.
    await run('page', 'html', `<html><head><base href="${P('base')}/"><meta http-equiv="refresh" content="0;url=${P('refresh')}">` +
      `<link rel="stylesheet" href="${P('link')}"><style>body{background:\\75rl(${P('css-escape')})}</style>` +
      `<style>@import "${P('import')}";</style></head><body><p style="background:url(${P('style')})">hi</p>` +
      `<img src="${P('img')}" alt="x"><img src="data:image/png;base64,iVBORw0KGgo=" srcset="${P('srcset')} 2x">` +
      `<a href="${P('a')}" id="go">link</a><map name="m"><area href="${P('area')}"></map>` +
      `<svg><a xlink:href="${P('svg-a')}"><text>t</text></a><image href="${P('svg-image')}"/></svg>` +
      `<form action="${P('form')}"><button>go</button></form><iframe src="${P('iframe')}"></iframe>` +
      `<video poster="${P('poster')}"></video><script>fetch("${P('script')}");parent.document.title="touched"</script>` +
      `</body></html>`);
    const frame = box.querySelector('iframe');
    result.frames.page = { sandbox: frame.getAttribute('sandbox'), hasHref: /probe/.test(frame.srcdoc) };
    await wait(300);
    // A click on what was a link moves nothing.
    try {
      const doc = frame.contentDocument;
      result.frames.pageReadable = !!doc;
    } catch (e) {
      result.frames.pageReadable = false;
    }

    // Each layer alone. The policy alone: a page given as it is, with the
    // policy first, loads nothing.
    const bare = document.createElement('iframe');
    bare.setAttribute('sandbox', '');
    bare.srcdoc = `<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; base-uri 'none'; form-action 'none'">` +
      `<link rel="stylesheet" href="${P('layer-link')}"><style>@import "${P('layer-import')}"; p{background:url(${P('layer-css')})}</style></head>` +
      `<body><p>x</p><img src="${P('layer-img')}"><video poster="${P('layer-poster')}"></video></body></html>`;
    document.body.appendChild(bare);
    // The frame alone: its script does not run.
    const scripted = document.createElement('iframe');
    scripted.setAttribute('sandbox', '');
    scripted.srcdoc = `<script>parent.document.title = "ran"; fetch("${P('layer-script')}")</script>`;
    document.body.appendChild(scripted);
    await wait(500);

    await run('markdown', 'markdown', `# T\n\n![x](${P('md-img')}) [l](${P('md-link')})\n\n\`\`\`mermaid\nflowchart LR\nA-->B\n\`\`\`\n`);
    await run('svg', 'svg', `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20">` +
      `<style>@import url(${P('svg-import')});</style><image href="${P('svg-img')}" width="10" height="10"/>` +
      `<use xlink:href="${P('svg-use')}#a"/><rect width="20" height="20" fill="red"/>` +
      `<script>fetch("${P('svg-script')}")</script></svg>`);
    // The input that made strict Mermaid 11.4.1 load an image while drawing.
    await run('diagramProbe', 'diagram', `flowchart LR\nA["<image src='${P('mermaid-image')}'>"]\nB["<img src='${P('mermaid-img')}'>"]`);
    await run('diagramFlow', 'diagram', 'flowchart LR\n  A[開始] --> B{判定}\n  B -->|はい| C[終わり<br>二行目]');
    await run('diagramSequence', 'diagram', 'sequenceDiagram\n  Alice->>Bob: Hello\n  Bob-->>Alice: Hi');
    await run('diagramClass', 'diagram', 'classDiagram\n  Animal <|-- Duck');
    await run('diagramSankey', 'diagram', 'sankey-beta\nA,B,10\nA,C,5');
    await run('diagramGit', 'diagram', 'gitGraph\n  commit\n  branch dev\n  commit');
    await run('diagramUnknown', 'diagram', 'notADiagram\nA-->B');
    await run('diagramSettings', 'diagram', '%%{init: {"securityLevel": "loose"}}%%\nflowchart LR\nA-->B');

    const bar = { data: { values: [{ a: 'A', b: 28 }, { a: 'B', b: 55 }] }, mark: 'bar',
      encoding: { x: { field: 'a', type: 'nominal' }, y: { field: 'b', type: 'quantitative' } } };
    await run('chartBar', 'vega_lite', JSON.stringify(bar));
    await run('chartLine', 'vega_lite', JSON.stringify({ data: { values: Array.from({ length: 30 }, (_, i) => ({ x: i, y: i * i })) },
      transform: [{ calculate: 'datum.y / 2', as: 'z' }], mark: 'line',
      encoding: { x: { field: 'x', type: 'quantitative' }, y: { field: 'z', type: 'quantitative' } } }));
    await run('chartUrl', 'vega_lite', JSON.stringify({ data: { url: P('chart-url') }, mark: 'bar' }));
    await run('chartImage', 'vega_lite', JSON.stringify({ data: { values: [{ u: P('chart-image') }] },
      mark: { type: 'image' }, encoding: { url: { field: 'u' } } }));
    await run('chartFold', 'vega_lite', JSON.stringify({ data: { values: [{ a: 1, b: 2 }] },
      transform: [{ fold: ['a', 'b'] }, { fold: ['key', 'value'] }], mark: 'point' }));
    await run('chartFacet13', 'vega_lite', JSON.stringify({ data: { values: Array.from({ length: 13 }, (_, i) => ({ group: 'one', id: i })) },
      transform: [{ calculate: 'datum.id', as: 'group' }], mark: 'point', encoding: { row: { field: 'group' } } }));
    await run('chartRowColumn', 'vega_lite', JSON.stringify({ data: { values: Array.from({ length: 16 }, (_, i) => ({ r: i % 4, c: Math.floor(i / 4) })) },
      mark: 'point', encoding: { row: { field: 'r' }, column: { field: 'c' } } }));
    await run('chartRepeatLayer', 'vega_lite', JSON.stringify({ data: { values: [{ a: 1 }] },
      repeat: { layer: ['a', 'b', 'c', 'd', 'e'], column: ['x', 'y', 'z'] }, spec: { mark: 'line' } }));
    await run('chartFunction', 'vega_lite', JSON.stringify({ data: { values: [{ a: 1 }] },
      transform: [{ calculate: 'sequence(0, 100000000)', as: 's' }], mark: 'point' }));
    await run('chartJson', 'vega_lite', '{ not json');
    // An expression of Vega's own inside a transform, and a facet field read
    // through brackets: both refused.
    await run('chartSignal', 'vega_lite', JSON.stringify({ data: { values: [{ x: 1 }, { x: 2 }] },
      transform: [{ bin: { extent: { signal: 'length(sequence(20))' } }, field: 'x', as: 'b' }], mark: 'point',
      encoding: { x: { field: 'b', type: 'quantitative' } } }));
    await run('chartNestedExpr', 'vega_lite', JSON.stringify({ data: { values: [{ x: 1 }] },
      mark: { type: 'point', size: { expr: 'length(sequence(9))' } } }));
    // Values a filter compares with: an expression or a signal, at any depth.
    const point = { data: { values: [{ x: 20 }] }, mark: 'point', encoding: { x: { field: 'x', type: 'quantitative' } } };
    const filtered = (filter) => JSON.stringify(Object.assign({ transform: [{ filter }] }, point));
    await run('filterEqualExpr', 'vega_lite', filtered({ field: 'x', equal: { expr: 'length(sequence(20))' } }));
    await run('filterEqualSignal', 'vega_lite', filtered({ field: 'x', equal: { signal: 'length(sequence(20))' } }));
    await run('filterRange', 'vega_lite', filtered({ field: 'x', range: [0, { expr: 'length(sequence(20))' }] }));
    await run('filterOneOf', 'vega_lite', filtered({ field: 'x', oneOf: [1, { signal: 'length(sequence(20))' }] }));
    await run('filterNested', 'vega_lite', filtered({ and: [{ not: { or: [{ field: 'x', equal: { expr: 'length(sequence(20))' } }] } }] }));
    await run('filterPlain', 'vega_lite', filtered({ and: [{ field: 'x', range: [0, 30] }, { not: { field: 'x', oneOf: [1, 2] } }] }));
    await run('chartBracketFacet', 'vega_lite', JSON.stringify({ data: { values: Array.from({ length: 13 }, (_, i) => ({ a: { b: i }, x: i })) },
      mark: 'point', encoding: { row: { field: "a['b']", type: 'nominal' }, x: { field: 'x', type: 'quantitative' } } }));

    // A diagram in a chat card, the way the chat draws it (render-registry.js),
    // with the input that made strict Mermaid load an image while drawing.
    const chat = document.createElement('div');
    chat.className = 'card-text';
    chat.innerHTML = '<div class="mermaid-code"><pre></pre></div><div class="mermaid-code"><pre></pre></div>';
    chat.querySelectorAll('pre')[0].textContent = 'flowchart LR\n  A[\u201Cstart\u201D] --> B[\u7D42\u308F\u308A]';
    chat.querySelectorAll('pre')[1].textContent = `flowchart LR\nA["<image src='${P('chat-image')}'>"]`;
    document.body.appendChild(chat);
    Renderers.apply(chat);
    Renderers.apply(chat);
    const chatImages = async () => {
      for (let i = 0; i < 100; i += 1) {
        const imgs = Array.from(chat.querySelectorAll('.render-wrap img.workbench-svg'));
        if (imgs.length === 2 && imgs.every((img) => img.complete && img.naturalWidth > 0)) return imgs;
        await wait(100);
      }
      return Array.from(chat.querySelectorAll('.render-wrap img.workbench-svg'));
    };
    const imgs = await chatImages();
    result.chat = {
      images: imgs.map((img) => img.naturalWidth),
      wraps: chat.querySelectorAll('.render-wrap').length,
      downloads: chat.querySelectorAll('.render-actions button').length
    };
    const chatUrl = imgs[0] && imgs[0].src;
    // What a copy of the card (the PDF export) prints, taken before the card goes.
    const own = Renderers.selfContainedSrc(chat.querySelector('.mermaid-code'));
    chat.remove();
    await wait(200);
    result.chat.releasedWithCard = chatUrl ? await fetch(chatUrl).then(() => false, () => true) : null;
    result.chat.ownImageWidth = own ? await new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve(img.naturalWidth);
      img.onerror = () => resolve(0);
      img.src = own;
    }) : null;

    await wait(1500);
    result.title = document.title;
    // Images made for drawings are let go with them.
    const last = WorkbenchRender.draw(box, 'svg', '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"/>');
    await last.done;
    const url = box.querySelector('img').src;
    last.dispose();
    result.releasedAfterDispose = await fetch(url).then(() => false, () => true);
    return result;
  }, base));
  out.errors = errors;
} finally {
  await browser.close();
  server.close();
}
out.probes = probes;
console.log(`RESULT ${JSON.stringify(out)}`);
