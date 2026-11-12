/**
 * What the work screen draws of a text file (workbench.js asks, by the kind
 * the server named from the file's extension): Markdown, a table (CSV,
 * TSV), an SVG image, a static HTML page, a Mermaid diagram and a Vega-Lite
 * chart. The file is the model's or the user's, so nothing drawn here may
 * reach the network or run as script:
 *
 * - Markdown and HTML pass a sanitizer of their own (a DOMPurify instance
 *   apart from the chat's), which keeps listed tags and attributes only.
 *   Images stay only as data: URLs of image types; Markdown links open
 *   outside, without a referrer; links in a page become plain text.
 * - A page is shown in an iframe with no permission at all (no script, no
 *   form, no popup) and a policy, set first in its head, that loads only
 *   data: images.
 * - SVG, and the SVG a diagram or a chart becomes, is shown as an image
 *   (an image loads nothing and runs nothing).
 * - A diagram is made by Mermaid inside a hidden iframe that may run its
 *   scripts and nothing else (its policy loads nothing); the text goes in
 *   by message only.
 * - A chart is made inside a worker whose own policy loads nothing and
 *   runs no text as code (vendor/vega, built by `npm run build:vega`); a
 *   chart that takes too long ends with the worker.
 *
 * draw(box, kind, text) shows the drawing in box and returns a handle:
 * { done: Promise, svg(), dispose() }. done settles once the drawing is shown or
 * failed (then box says why); after dispose nothing more is put in box.
 */
(function (window) {
  'use strict';

  const SVG_TYPE = 'image/svg+xml';
  const DATA_IMAGE = /^data:image\/(?:png|jpeg|gif|webp);base64,[A-Za-z0-9+/=\s]+$/i;
  const DATA_IMAGE_BYTES = 2 * 1024 * 1024;
  const TABLE_ROWS = 2000;
  const TABLE_COLUMNS = 50;
  const DIAGRAM_CHARS = 50000;
  const SVG_CHARS = 5 * 1024 * 1024;
  const DIAGRAM_WAIT_MS = 15000;
  const CHART_WAIT_MS = 10000;
  const MERMAID_PATH = '/vendor/js/mermaid.min.js';
  const VEGA_WORKER_PATH = '/vendor/vega/vega-worker.mjs';
  const PAGE_POLICY = "default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; " +
    "base-uri 'none'; form-action 'none'";
  const FRAME_POLICY = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'none'; " +
    "font-src 'none'; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'";

  function t(key, fallback) {
    return (typeof webUIi18n !== 'undefined' && webUIi18n.t) ? webUIi18n.t(`ui.workbench.${key}`) || fallback : fallback;
  }

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined && text !== null) el.textContent = String(text);
    return el;
  }

  class Refused extends Error {}

  // ---- images: data: URLs of image types only --------------------------

  function dataImageOk(src) {
    if (typeof src !== 'string' || !DATA_IMAGE.test(src)) return false;
    const base64 = src.slice(src.indexOf(',') + 1).replace(/\s/g, '');
    return Math.floor(base64.length * 3 / 4) <= DATA_IMAGE_BYTES;
  }

  // Each img of root: kept for a data: image, else replaced by its alt text.
  function keepDataImages(root) {
    root.querySelectorAll('img').forEach((img) => {
      img.removeAttribute('srcset');
      if (dataImageOk(img.getAttribute('src'))) return;
      const alt = img.getAttribute('alt') || '';
      img.replaceWith(document.createTextNode(alt ? `[${t('imageNotShown', 'image')}: ${alt}]` : ''));
    });
  }

  // CSS that could load something (or hide a way to): left out. The page's
  // policy stops a load this misses.
  function cssLoads(text) {
    return /url\s*\(|@import|image-set\s*\(|expression\s*\(|\\/i.test(String(text));
  }

  // ---- the sanitizers (instances apart from the chat's) ------------------

  let markdownPurifier = null;
  let pagePurifier = null;

  const MARKDOWN_TAGS = ['p', 'br', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'blockquote',
    'pre', 'code', 'em', 'strong', 's', 'del', 'a', 'img', 'table', 'thead', 'tbody', 'tr', 'th', 'td', 'span',
    'sup', 'sub'];
  const PAGE_TAGS = ['html', 'head', 'body', 'title', 'style', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'div',
    'span', 'section', 'article', 'header', 'footer', 'main', 'nav', 'aside', 'ul', 'ol', 'li', 'dl', 'dt', 'dd',
    'table', 'caption', 'colgroup', 'col', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'pre', 'code',
    'blockquote', 'figure', 'figcaption', 'img', 'br', 'hr', 'strong', 'em', 'b', 'i', 'u', 's', 'small', 'sub',
    'sup', 'mark', 'abbr', 'cite', 'q', 'time', 'kbd', 'samp', 'var', 'details', 'summary'];
  const PAGE_ATTRS = ['class', 'title', 'alt', 'lang', 'dir', 'colspan', 'rowspan', 'scope', 'width', 'height',
    'style', 'src', 'open'];

  function purifier(kind) {
    if (typeof window.DOMPurify !== 'function') throw new Error('the sanitizer is not loaded');
    if (kind === 'markdown') {
      if (!markdownPurifier) {
        markdownPurifier = window.DOMPurify(window);
        markdownPurifier.addHook('uponSanitizeAttribute', (node, data) => {
          if (data.attrName === 'href' && !/^(?:https?:|mailto:)/i.test(data.attrValue)) data.keepAttr = false;
          if (data.attrName === 'src' && !dataImageOk(data.attrValue)) data.keepAttr = false;
        });
        markdownPurifier.addHook('afterSanitizeAttributes', (node) => {
          if (node.nodeName === 'A') {
            node.setAttribute('target', '_blank');
            node.setAttribute('rel', 'noopener noreferrer');
            node.setAttribute('referrerpolicy', 'no-referrer');
          }
        });
      }
      return markdownPurifier;
    }
    if (!pagePurifier) {
      pagePurifier = window.DOMPurify(window);
      pagePurifier.addHook('uponSanitizeAttribute', (node, data) => {
        if (data.attrName === 'style' && cssLoads(data.attrValue)) data.keepAttr = false;
        if (data.attrName === 'src' && (node.nodeName !== 'IMG' || !dataImageOk(data.attrValue))) data.keepAttr = false;
      });
      pagePurifier.addHook('uponSanitizeElement', (node, data) => {
        if (data.tagName === 'style' && cssLoads(node.textContent)) node.textContent = '';
      });
    }
    return pagePurifier;
  }

  // ---- Markdown ----------------------------------------------------------

  let markdown = null;

  // text-utils.js's, loaded before this file.
  const escapeHtml = (text) => window.escapeHtml(text);

  function markdownParser() {
    if (markdown) return markdown;
    if (typeof window.markdownit !== 'function') throw new Error('markdown-it is not loaded');
    markdown = window.markdownit({
      html: false,
      linkify: true,
      typographer: true,
      highlight: (code, lang) => {
        const language = String(lang || '').trim().toLowerCase();
        if (window.hljs && language && window.hljs.getLanguage && window.hljs.getLanguage(language)) {
          try {
            return `<pre><code class="hljs language-${escapeHtml(language)}">${window.hljs.highlight(code, { language: language }).value}</code></pre>`;
          } catch (_) { /* drawn plain below */ }
        }
        return `<pre><code${language ? ` class="language-${escapeHtml(language)}"` : ''}>${escapeHtml(code)}</code></pre>`;
      }
    });
    return markdown;
  }

  // HTML made safe as Markdown's is: what it may hold, with data: images
  // only and no link that goes nowhere outside.
  function cleanFragment(html) {
    const clean = purifier('markdown').sanitize(html, {
      ALLOWED_TAGS: MARKDOWN_TAGS,
      ALLOWED_ATTR: ['href', 'title', 'alt', 'src', 'class', 'colspan', 'rowspan', 'align', 'start'],
      ALLOW_DATA_ATTR: false,
      RETURN_DOM_FRAGMENT: true
    });
    keepDataImages(clean);
    // A link to no outside address (a relative one) is its text.
    clean.querySelectorAll('a:not([href])').forEach((a) => a.replaceWith(...a.childNodes));
    return clean;
  }

  function markdownFragment(text) {
    return cleanFragment(markdownParser().render(text));
  }

  function drawMarkdown(box, text, live) {
    const doc = element('div', 'workbench-markdown');
    doc.appendChild(markdownFragment(text));
    box.replaceChildren(doc);
    // Mermaid blocks are drawn as diagrams, each in turn.
    const blocks = Array.from(doc.querySelectorAll('pre > code.language-mermaid'));
    return blocks.reduce((chain, code) => chain.then(() => {
      if (!live()) return null;
      const holder = element('div', 'workbench-diagram');
      const pre = code.parentNode;
      const letGo = () => holder.querySelectorAll('img.workbench-svg').forEach((img) => release(img.src));
      // The block becomes the diagram once its image is drawn; until then,
      // and when it cannot be drawn, it stays as code.
      return diagramSvg(code.textContent)
        .then((svg) => (live() && pre.parentNode ? showSvg(holder, svg, live) : null))
        .then(() => {
          if (live() && pre.parentNode && holder.firstChild) pre.replaceWith(holder);
          else letGo();
        })
        .catch(letGo);
    }), Promise.resolve());
  }

  // ---- code, highlighted --------------------------------------------------

  // A text is highlighted as code by its extension (highlight.js knows it as
  // a language) up to HIGHLIGHT_CHARS; plain text and data are not.
  const HIGHLIGHT_CHARS = 200000;
  const NOT_CODE = ['txt', 'log', 'csv', 'tsv', 'srt', 'vtt', 'jsonl', 'mmd', 'mermaid'];

  function codeLanguage(name) {
    const ext = String(name || '').toLowerCase().split('.').pop();
    if (!ext || NOT_CODE.includes(ext) || !window.hljs || !window.hljs.getLanguage) return null;
    return window.hljs.getLanguage(ext) ? ext : null;
  }

  // The HTML of each line of text highlighted as language, or null. A token
  // that runs over lines (a long string, a comment) is closed at each line's
  // end and opened again on the next, so each line stands alone. The text
  // is highlight.js's own escaping of it; the markup is its spans.
  function highlightedLines(text, language) {
    if (!language || !window.hljs || String(text).length > HIGHLIGHT_CHARS || !window.hljs.getLanguage(language)) return null;
    let html;
    try {
      html = window.hljs.highlight(String(text), { language, ignoreIllegals: true }).value;
    } catch (_) {
      return null;
    }
    const lines = [];
    const open = [];
    let line = '';
    html.split(/(<span[^>]*>|<\/span>|\n)/).forEach((token) => {
      if (!token) return;
      if (token === '\n') {
        lines.push(line + '</span>'.repeat(open.length));
        line = open.join('');
      } else if (token.startsWith('<span')) {
        open.push(token);
        line += token;
      } else if (token === '</span>') {
        open.pop();
        line += token;
      } else {
        line += token;
      }
    });
    lines.push(line);
    return lines;
  }

  // ---- Jupyter notebooks (read only) --------------------------------------

  // A notebook as it was saved: its cells in order, the text of each and
  // what each run showed. Nothing in it runs. Of an output's forms the
  // first found is shown: an image, HTML (made safe as Markdown's is; one
  // that is only a script, such as an interactive chart, is said to be
  // so), Markdown, then text.
  const NOTEBOOK_CELLS = 1000;
  const NOTEBOOK_TEXT = 20000;
  const NOTEBOOK_IMAGES = ['image/png', 'image/jpeg', 'image/gif', 'image/webp'];
  const ANSI = /\u001b\[[0-9;]*[A-Za-z]/g;

  function joined(value) {
    return Array.isArray(value) ? value.join('') : (typeof value === 'string' ? value : '');
  }

  function cutText(text) {
    const plain = String(text).replace(ANSI, '');
    return plain.length > NOTEBOOK_TEXT ? `${plain.slice(0, NOTEBOOK_TEXT)}\n…` : plain;
  }

  function preOf(text, className) {
    const pre = element('pre', className);
    pre.textContent = cutText(text);
    return pre;
  }

  function notebookOutput(output) {
    if (!output || typeof output !== 'object') return null;
    if (output.output_type === 'stream') {
      return preOf(joined(output.text), `workbench-nb-stream${output.name === 'stderr' ? ' workbench-nb-stderr' : ''}`);
    }
    if (output.output_type === 'error') {
      const trace = Array.isArray(output.traceback) ? output.traceback.join('\n') : `${output.ename}: ${output.evalue}`;
      return preOf(trace, 'workbench-nb-stream workbench-nb-stderr');
    }
    const data = output.data && typeof output.data === 'object' ? output.data : null;
    if (!data) return null;
    const image = NOTEBOOK_IMAGES.find((type) => typeof joined(data[type]) === 'string' && joined(data[type]));
    if (image) {
      const src = `data:${image};base64,${joined(data[image]).replace(/\s/g, '')}`;
      if (dataImageOk(src)) {
        const img = element('img', 'workbench-nb-image');
        img.alt = '';
        img.src = src;
        return img;
      }
    }
    if (data['text/html']) {
      const holder = element('div', 'workbench-nb-html');
      holder.appendChild(cleanFragment(joined(data['text/html'])));
      if (holder.textContent.trim() || holder.querySelector('img, table')) return holder;
      return element('div', 'workbench-nb-note', t('notebookInteractive', 'An interactive output (not shown here).'));
    }
    if (data['text/markdown']) {
      const holder = element('div', 'workbench-markdown');
      holder.appendChild(markdownFragment(joined(data['text/markdown'])));
      return holder;
    }
    if (data['text/plain']) return preOf(joined(data['text/plain']), 'workbench-nb-stream');
    return element('div', 'workbench-nb-note', t('notebookInteractive', 'An interactive output (not shown here).'));
  }

  function drawNotebook(box, text) {
    let notebook;
    try {
      notebook = JSON.parse(text);
    } catch (_) {
      throw new Refused(t('notebookUnreadable', 'This notebook could not be read.'));
    }
    const cells = notebook && Array.isArray(notebook.cells) ? notebook.cells : null;
    if (!cells) throw new Refused(t('notebookUnreadable', 'This notebook could not be read.'));
    const doc = element('div', 'workbench-notebook');
    const meta = notebook.metadata || {};
    const language = String((meta.language_info && meta.language_info.name) ||
      (meta.kernelspec && meta.kernelspec.language) || 'python').toLowerCase();
    cells.slice(0, NOTEBOOK_CELLS).forEach((cell) => {
      if (!cell || typeof cell !== 'object') return;
      const source = joined(cell.source);
      const holder = element('div', `workbench-nb-cell workbench-nb-${cell.cell_type === 'code' ? 'code' : 'text'}`);
      if (cell.cell_type === 'markdown') {
        holder.classList.add('workbench-markdown');
        holder.appendChild(markdownFragment(source));
      } else if (cell.cell_type === 'code') {
        const count = Number.isInteger(cell.execution_count) ? String(cell.execution_count) : ' ';
        holder.appendChild(element('div', 'workbench-nb-prompt', `[${count}]`));
        const pre = element('pre', 'workbench-nb-source');
        const code = element('code', null);
        const text = cutText(source);
        const lines = highlightedLines(text, language);
        if (lines) code.innerHTML = lines.join('\n');
        else code.textContent = text;
        pre.appendChild(code);
        holder.appendChild(pre);
        (Array.isArray(cell.outputs) ? cell.outputs : []).forEach((output) => {
          const shown = notebookOutput(output);
          if (shown) holder.appendChild(shown);
        });
      } else {
        holder.appendChild(preOf(source, 'workbench-nb-source'));
      }
      doc.appendChild(holder);
    });
    if (cells.length > NOTEBOOK_CELLS) {
      doc.appendChild(element('div', 'workbench-nb-note', t('notebookCut', 'Only the first {cells} cells are shown.')
        .replace('{cells}', String(NOTEBOOK_CELLS))));
    }
    box.replaceChildren(doc);
  }

  // ---- tables ------------------------------------------------------------

  // Records of a CSV or TSV text (quotes, quoted line ends and "" taken),
  // up to TABLE_ROWS records and TABLE_COLUMNS fields: { rows, cut }.
  function parseTable(text, delimiter) {
    const rows = [];
    let row = [];
    let field = '';
    let quoted = false;
    let cut = false;
    let i = 0;
    const endField = () => {
      if (row.length < TABLE_COLUMNS) row.push(field);
      else cut = true;
      field = '';
    };
    const endRow = () => {
      endField();
      rows.push(row);
      row = [];
    };
    while (i < text.length) {
      const c = text[i];
      if (quoted) {
        if (c === '"') {
          if (text[i + 1] === '"') {
            field += '"';
            i += 1;
          } else {
            quoted = false;
          }
        } else {
          field += c;
        }
      } else if (c === '"' && field === '') {
        quoted = true;
      } else if (c === delimiter) {
        endField();
      } else if (c === '\n') {
        endRow();
        if (rows.length >= TABLE_ROWS) {
          cut = i + 1 < text.length;
          return { rows, cut };
        }
      } else if (c !== '\r') {
        field += c;
      }
      i += 1;
    }
    if (field !== '' || row.length > 0) endRow();
    return { rows, cut };
  }

  function drawTable(box, text, delimiter) {
    const { rows, cut } = parseTable(text, delimiter);
    const wrap = element('div', 'workbench-table-wrap');
    const table = element('table', 'table table-sm table-bordered workbench-table');
    if (rows.length > 0) {
      const head = element('thead');
      const tr = element('tr');
      rows[0].forEach((cell) => tr.appendChild(element('th', null, cell)));
      head.appendChild(tr);
      table.appendChild(head);
    }
    const body = element('tbody');
    rows.slice(1).forEach((cells) => {
      const tr = element('tr');
      cells.forEach((cell) => tr.appendChild(element('td', null, cell)));
      body.appendChild(tr);
    });
    table.appendChild(body);
    wrap.appendChild(table);
    box.replaceChildren(wrap);
    if (cut) {
      box.appendChild(element('div', 'small text-secondary mt-1',
        t('tableCut', 'Only the first {rows} rows and {columns} columns are shown.')
          .replace('{rows}', String(TABLE_ROWS)).replace('{columns}', String(TABLE_COLUMNS))));
    }
  }

  // ---- SVG as an image -----------------------------------------------------

  const urls = new Set();

  function showSvg(box, svg, live) {
    if (typeof svg !== 'string' || svg.length > SVG_CHARS) throw new Refused(t('tooLarge', 'The drawing is too large to show.'));
    const url = URL.createObjectURL(new Blob([svg], { type: SVG_TYPE }));
    urls.add(url);
    // Shown larger on a click, as the work screen's images are (workbench.js).
    const img = element('img', 'workbench-svg workbench-zoomable');
    img.tabIndex = 0;
    img.setAttribute('role', 'button');
    img.title = t('enlarge', 'Show it larger');
    img.alt = '';
    img.decoding = 'async';
    img.src = url;
    box.replaceChildren(img);
    return new Promise((resolve, reject) => {
      img.addEventListener('load', () => resolve(), { once: true });
      img.addEventListener('error', () => reject(new Error(t('svgFailed', 'The image could not be drawn.'))), { once: true });
    }).finally(() => {
      if (!live()) release(url);
    }).then(() => url);
  }

  function release(url) {
    if (url && urls.delete(url)) URL.revokeObjectURL(url);
  }

  // ---- a static HTML page -------------------------------------------------

  // The page as it is shown: sanitized apart from the document it will be,
  // then put in a document this script makes, the policy first in its head.
  function pageDocument(text) {
    const dom = purifier('page').sanitize(text, {
      WHOLE_DOCUMENT: true,
      ALLOWED_TAGS: PAGE_TAGS,
      ALLOWED_ATTR: PAGE_ATTRS,
      ALLOW_DATA_ATTR: false,
      ALLOW_ARIA_ATTR: false,
      FORCE_BODY: false,
      RETURN_DOM: true
    });
    keepDataImages(dom);
    const styles = Array.from(dom.querySelectorAll('style'))
      .map((style) => style.textContent).filter((css) => css && !cssLoads(css));
    dom.querySelectorAll('style, title').forEach((node) => node.remove());
    const body = dom.querySelector('body') || dom;
    const meta = `<meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${PAGE_POLICY}">`;
    const css = styles.map((s) => `<style>${s.replace(/<\/style/gi, '<\\/style')}</style>`).join('');
    return `<!doctype html><html><head>${meta}${css}</head><body>${body.innerHTML}</body></html>`;
  }

  function drawPage(box, text) {
    const frame = element('iframe', 'workbench-page');
    frame.setAttribute('sandbox', '');
    frame.setAttribute('referrerpolicy', 'no-referrer');
    frame.title = t('page', 'Page');
    frame.srcdoc = pageDocument(text);
    box.replaceChildren(frame);
  }

  // ---- Mermaid, in a frame that loads nothing ---------------------------

  let mermaidSource = null;
  let diagramFrame = null;

  function diagramChecked(text) {
    const source = String(text);
    if (source.length > DIAGRAM_CHARS) throw new Refused(t('diagramTooLong', 'The diagram is too long to draw.'));
    if (/^\s*---/.test(source) || source.includes('%%{')) {
      throw new Refused(t('diagramSettings', 'Settings inside a diagram are not taken.'));
    }
    // Which kinds of diagram there are is Mermaid's to say (it tells when it
    // knows none), in the frame.
    return source;
  }

  // Mermaid's text, read once. A read that fails, or that a drawing gave
  // up on (abort), is forgotten, so the next drawing reads it again.
  function loadMermaid() {
    if (!mermaidSource) {
      const controller = new AbortController();
      const loading = fetch(MERMAID_PATH, { credentials: 'same-origin', signal: controller.signal }).then((response) => {
        if (!response.ok) throw new Error('Mermaid is not here');
        return response.text();
      });
      loading.abort = () => controller.abort();
      loading.catch(() => { if (mermaidSource === loading) mermaidSource = null; });
      mermaidSource = loading;
    }
    return mermaidSource;
  }

  // The frame's script: takes { type: 'render', id, text } from the page
  // that made it, answers { type: 'rendered', id, svg | error } to it.
  function frameScript(origin) {
    return `(function () {
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'default',
        maxTextSize: ${DIAGRAM_CHARS}, maxEdges: 500 });
      var n = 0;
      var to = ${JSON.stringify(origin)};
      window.addEventListener('message', function (e) {
        if (e.source !== window.parent) return;
        var d = e.data;
        if (!d || d.type !== 'render' || typeof d.id !== 'number' || typeof d.text !== 'string' ||
            d.text.length > ${DIAGRAM_CHARS}) return;
        n += 1;
        mermaid.render('d' + n, d.text).then(function (out) {
          // Labels hold HTML (<br>): read as HTML, written as XML, so that
          // it can be shown as an image.
          var svg = new DOMParser().parseFromString(String(out.svg), 'text/html').querySelector('svg');
          // An image takes its size from width and height: those of the
          // drawing (its viewBox), not "100%".
          var box = svg && (svg.getAttribute('viewBox') || '').split(/[\\s,]+/).map(Number);
          if (box && box.length === 4 && box[2] > 0 && box[3] > 0) {
            svg.setAttribute('width', String(Math.ceil(box[2])));
            svg.setAttribute('height', String(Math.ceil(box[3])));
            svg.style.removeProperty('max-width');
          }
          var xml = svg ? new XMLSerializer().serializeToString(svg) : '';
          window.parent.postMessage({ type: 'rendered', id: d.id, svg: xml }, to);
        }, function (err) {
          window.parent.postMessage({ type: 'rendered', id: d.id, error: String((err && err.message) || err) }, to);
        });
      });
      window.parent.postMessage({ type: 'ready' }, to);
    })();`;
  }

  function makeDiagramFrame(source) {
    const frame = document.createElement('iframe');
    frame.setAttribute('sandbox', 'allow-scripts');
    frame.setAttribute('aria-hidden', 'true');
    frame.tabIndex = -1;
    frame.className = 'workbench-diagram-frame';
    // Mermaid measures text, so the frame has a size; it is out of view.
    frame.style.cssText = 'position:fixed;left:-10000px;top:0;width:1200px;height:800px;border:0;visibility:hidden';
    const script = (code) => `<script>${code.replace(/<\/script/gi, '<\\/script')}</script>`;
    frame.srcdoc = `<!doctype html><html><head><meta charset="utf-8">` +
      `<meta http-equiv="Content-Security-Policy" content="${FRAME_POLICY}"></head><body>` +
      `${script(source)}${script(frameScript(window.location.origin))}</body></html>`;
    const state = { frame: frame, ready: null, waiting: null, nextId: 1 };
    state.ready = new Promise((resolve) => { state.readied = resolve; });
    state.listener = (e) => {
      if (e.source !== frame.contentWindow || !e.data || typeof e.data !== 'object') return;
      if (e.data.type === 'ready') {
        state.readied();
        return;
      }
      const waiting = state.waiting;
      if (e.data.type !== 'rendered' || !waiting || e.data.id !== waiting.id) return;
      state.waiting = null;
      if (typeof e.data.svg === 'string' && e.data.svg.length <= SVG_CHARS) waiting.resolve(e.data.svg);
      else waiting.reject(new Refused(typeof e.data.error === 'string' ? e.data.error.slice(0, 300) : t('renderFailed', 'This could not be drawn.')));
    };
    window.addEventListener('message', state.listener);
    document.body.appendChild(frame);
    return state;
  }

  function dropDiagramFrame() {
    if (!diagramFrame) return;
    const state = diagramFrame;
    diagramFrame = null;
    window.removeEventListener('message', state.listener);
    if (state.waiting) state.waiting.reject(new Error(t('renderFailed', 'This could not be drawn.')));
    state.frame.remove();
  }

  // One diagram at a time: each waits for the one before.
  let diagramQueue = Promise.resolve();

  // The SVG of a diagram. One limit covers reading Mermaid, making the
  // frame and drawing: a frame that does not answer (not even that it is
  // ready) is dropped, and the next diagram makes a new one.
  function diagramSvg(text) {
    let source;
    try {
      source = diagramChecked(text);
    } catch (e) {
      return Promise.reject(e);
    }
    const run = diagramQueue.then(() => new Promise((resolve, reject) => {
      let settled = false;
      let state = null;
      const finish = (fn, value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (state && state.waiting && state.waiting.finish === finish) state.waiting = null;
        fn(value);
      };
      const loading = loadMermaid();
      const timer = setTimeout(() => {
        finish(reject, new Error(t('renderTimeout', 'Drawing took too long.')));
        if (state && diagramFrame === state) dropDiagramFrame();
        // Still reading Mermaid: that read ends, and the next drawing reads
        // it again.
        if (!state) {
          if (mermaidSource === loading) mermaidSource = null;
          loading.abort();
        }
      }, DIAGRAM_WAIT_MS);
      loading.then((code) => {
        if (settled) return null;
        if (!diagramFrame) diagramFrame = makeDiagramFrame(code);
        state = diagramFrame;
        return state.ready.then(() => {
          if (settled || diagramFrame !== state) return;
          const id = state.nextId++;
          state.waiting = { id, finish, resolve: (svg) => finish(resolve, svg), reject: (e) => finish(reject, e) };
          state.frame.contentWindow.postMessage({ type: 'render', id: id, text: source }, '*');
        });
      }).catch((e) => finish(reject, e));
    }));
    diagramQueue = run.catch(() => null);
    return run;
  }

  // ---- Vega-Lite, in a worker that loads nothing ------------------------

  let chartWorker = null;
  let chartQueue = Promise.resolve();
  let chartId = 0;

  function chartSvg(text) {
    const run = chartQueue.then(() => new Promise((resolve, reject) => {
      if (!chartWorker) chartWorker = new Worker(VEGA_WORKER_PATH, { type: 'module' });
      const worker = chartWorker;
      const id = ++chartId;
      const done = () => {
        clearTimeout(timer);
        worker.removeEventListener('message', onMessage);
        worker.removeEventListener('error', onError);
      };
      const end = () => {
        worker.terminate();
        if (chartWorker === worker) chartWorker = null;
      };
      const onMessage = (e) => {
        if (!e.data || e.data.id !== id) return;
        done();
        if (typeof e.data.svg === 'string') resolve(e.data.svg);
        else reject(e.data.refused ? new Refused(String(e.data.error).slice(0, 300)) : new Error(String(e.data.error).slice(0, 300)));
      };
      const onError = () => {
        done();
        end();
        reject(new Error(t('renderFailed', 'This could not be drawn.')));
      };
      const timer = setTimeout(() => {
        done();
        end();
        reject(new Error(t('renderTimeout', 'Drawing took too long.')));
      }, CHART_WAIT_MS);
      worker.addEventListener('message', onMessage);
      worker.addEventListener('error', onError);
      worker.postMessage({ id: id, text: String(text) });
    }));
    chartQueue = run.catch(() => null);
    return run;
  }

  // ---- drawing -------------------------------------------------------------

  const KINDS = ['markdown', 'diagram', 'table', 'svg', 'html', 'vega_lite', 'notebook'];

  function draw(box, kind, text, options) {
    const ext = (options && options.name ? String(options.name).toLowerCase() : '');
    let disposed = false;
    let lastSvg = null;
    const shown = [];
    const live = () => !disposed;
    const showing = (svg) => {
      if (disposed) return null;
      return showSvg(box, svg, live).then((url) => {
        shown.push(url);
        lastSvg = svg;
      });
    };
    let work;
    try {
      if (!KINDS.includes(kind)) throw new Refused(t('renderKind', 'This kind of file is not drawn here.'));
      if (kind === 'markdown') work = drawMarkdown(box, text, live);
      else if (kind === 'table') work = drawTable(box, text, ext.endsWith('.tsv') ? '\t' : ',');
      else if (kind === 'svg') work = showing(text);
      else if (kind === 'html') work = drawPage(box, text);
      else if (kind === 'notebook') work = drawNotebook(box, text);
      else if (kind === 'diagram') work = diagramSvg(text).then(showing);
      else work = chartSvg(text).then(showing);
    } catch (e) {
      work = Promise.reject(e);
    }
    const done = Promise.resolve(work).then(() => {
      // An image made after the box was given up is let go.
      if (disposed) shown.forEach(release);
    });
    return {
      done: done,
      // The SVG text shown, once drawn (an SVG, a diagram or a chart).
      svg: () => (disposed ? null : lastSvg),
      dispose() {
        disposed = true;
        shown.forEach(release);
        box.querySelectorAll('img.workbench-svg').forEach((img) => release(img.src));
      }
    };
  }

  const api = {
    draw, KINDS, Refused,
    // For tests: what is taken apart from drawing.
    codeLanguage, highlightedLines,
    parseTable, pageDocument, diagramChecked, dataImageOk, cssLoads,
    _dropFrames() {
      dropDiagramFrame();
      if (chartWorker) chartWorker.terminate();
      chartWorker = null;
    }
  };
  window.WorkbenchRender = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
