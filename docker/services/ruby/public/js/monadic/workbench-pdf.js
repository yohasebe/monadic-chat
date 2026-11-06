/**
 * A PDF in the work screen, drawn with pdf.js (kept under /vendor/pdfjs at
 * a pinned version, loaded the first time a PDF is shown): one page at a
 * time, with pdf.js's text layer over it so the user can select its text.
 * ‹ and › (or ← and → while the PDF has the focus) move between pages; −
 * and + zoom. The first page fits the pane's width.
 *
 * The bytes are the item's, taken whole from its address (the version the
 * item was opened at). Nothing in the PDF acts: no scripts, no forms, no
 * links (annotations are not drawn). A canvas is never larger than
 * MAX_PIXELS; on a high-density screen the page is drawn sharper within
 * that.
 *
 * WorkbenchPdf.show(box, bytes, onChange) draws into box and returns a
 * handle: state() (the page and scale asked for), shown() (what is drawn
 * now: { status: 'ready', page, pages, scale } once a page and its text
 * layer are drawn, otherwise { status: 'loading' | 'drawing' | 'failed' }),
 * and dispose() (stops drawing and lets the document go). onChange is
 * called whenever shown() changes.
 */
(function (window) {
  'use strict';

  const BASE = '/vendor/pdfjs/';
  const MAX_PIXELS = 4096 * 4096;
  const MIN_SCALE = 0.25;
  const MAX_SCALE = 4;
  const ZOOM_STEP = 1.25;

  let loading = null;

  function t(key, fallback) {
    return typeof webUIi18n !== 'undefined' ? webUIi18n.t(key) : fallback;
  }

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  function clamp(scale) {
    return Math.min(Math.max(scale, MIN_SCALE), MAX_SCALE);
  }

  // pdf.js, loaded once (again after a failure).
  function library() {
    if (!loading) {
      loading = Promise.resolve(WorkbenchPdf.loader()).then((lib) => {
        lib.GlobalWorkerOptions.workerSrc = `${BASE}pdf.worker.min.mjs`;
        return lib;
      });
      loading.catch(() => { loading = null; });
    }
    return loading;
  }

  function show(box, bytes, onChange) {
    const state = { page: 1, pages: 0, scale: null, lib: null, doc: null, task: null, text: null, disposed: false };
    // What is drawn: the drawing it comes from (gen) and its status.
    let gen = 0;
    let drawnNow = { status: 'loading' };
    function settle(next) {
      drawnNow = next;
      if (typeof onChange === 'function' && !state.disposed) onChange(drawnNow);
    }
    const bar = element('div', 'workbench-pdf-bar d-flex align-items-center gap-2 mb-2');
    const prev = element('button', 'btn btn-sm btn-outline-secondary workbench-pdf-prev', '‹');
    const next = element('button', 'btn btn-sm btn-outline-secondary workbench-pdf-next', '›');
    const where = element('span', 'small text-secondary workbench-pdf-where', '');
    const smaller = element('button', 'btn btn-sm btn-outline-secondary workbench-pdf-out', '−');
    const larger = element('button', 'btn btn-sm btn-outline-secondary workbench-pdf-in', '+');
    const zoom = element('span', 'small text-secondary workbench-pdf-zoom', '');
    prev.setAttribute('aria-label', t('ui.workbench.pdfPrev', 'Previous page'));
    next.setAttribute('aria-label', t('ui.workbench.pdfNext', 'Next page'));
    smaller.setAttribute('aria-label', t('ui.workbench.zoomOut', 'Zoom out'));
    larger.setAttribute('aria-label', t('ui.workbench.zoomIn', 'Zoom in'));
    [prev, next, smaller, larger].forEach((b) => { b.type = 'button'; b.disabled = true; });
    bar.append(prev, where, next, smaller, zoom, larger);
    const sheet = element('div', 'workbench-pdf-page');
    const canvas = element('canvas');
    sheet.append(canvas);
    box.classList.add('workbench-pdf');
    box.setAttribute('tabindex', '0');
    box.replaceChildren(bar, sheet);

    function fail() {
      if (state.disposed) return;
      settle({ status: 'failed' });
      box.replaceChildren(element('div', 'alert alert-warning small mb-0', t('ui.workbench.pdfFailed', 'The PDF could not be shown.')));
    }

    function label() {
      where.textContent = `${state.page} / ${state.pages}`;
      zoom.textContent = `${Math.round(state.scale * 100)}%`;
      prev.disabled = state.page <= 1;
      next.disabled = state.page >= state.pages;
      smaller.disabled = state.scale <= MIN_SCALE;
      larger.disabled = state.scale >= MAX_SCALE;
    }

    async function draw() {
      const n = state.page;
      const mine = ++gen;
      settle({ status: 'drawing' });
      const page = await state.doc.getPage(n);
      if (state.disposed || mine !== gen) return;
      // The text of the page drawn before goes now (and stops being drawn):
      // each drawing has a text layer of its own.
      stopText();
      if (!state.scale) {
        const width = page.getViewport({ scale: 1 }).width;
        state.scale = box.clientWidth > 0 && width > 0 ? clamp(box.clientWidth / width) : 1;
      }
      const viewport = page.getViewport({ scale: state.scale });
      const ratio = Math.min(window.devicePixelRatio || 1, Math.sqrt(MAX_PIXELS / (viewport.width * viewport.height)));
      if (state.task) state.task.cancel();
      canvas.width = Math.max(1, Math.floor(viewport.width * ratio));
      canvas.height = Math.max(1, Math.floor(viewport.height * ratio));
      canvas.style.width = `${Math.floor(viewport.width)}px`;
      canvas.style.height = `${Math.floor(viewport.height)}px`;
      sheet.style.setProperty('--total-scale-factor', String(state.scale));
      sheet.style.setProperty('--scale-round-x', '1px');
      sheet.style.setProperty('--scale-round-y', '1px');
      label();
      const task = page.render({
        canvas: canvas, canvasContext: canvas.getContext('2d'), viewport: viewport,
        transform: ratio !== 1 ? [ratio, 0, 0, ratio, 0, 0] : null,
        annotationMode: state.lib.AnnotationMode.DISABLE
      });
      state.task = task;
      try {
        await task.promise;
      } catch (e) {
        if (e && e.name === 'RenderingCancelledException') return;
        throw e;
      }
      if (state.disposed || mine !== gen) return;
      // This drawing's text, in a layer of its own, hidden until it is
      // whole and still the latest; a newer drawing takes it out first.
      const layer = element('div', 'textLayer');
      layer.style.visibility = 'hidden';
      sheet.appendChild(layer);
      const text = new state.lib.TextLayer({ textContentSource: page.streamTextContent(), container: layer, viewport: viewport });
      state.text = text;
      try {
        await text.render();
      } catch (e) {
        if (state.disposed || mine !== gen) return;
        throw e;
      }
      if (state.disposed || mine !== gen) return;
      layer.style.visibility = '';
      settle({ status: 'ready', page: n, pages: state.pages, scale: state.scale });
    }

    // The text layer drawn last stops and leaves the page.
    function stopText() {
      if (state.text && typeof state.text.cancel === 'function') state.text.cancel();
      state.text = null;
      sheet.querySelectorAll('.textLayer').forEach((old) => old.remove());
    }

    // A drawing that fails is said only while it is the latest.
    function redraw() {
      const drawing = draw();
      const mine = gen;
      drawing.catch(() => { if (mine === gen) fail(); });
    }

    function turn(delta) {
      const page = Math.min(Math.max(state.page + delta, 1), state.pages);
      if (page === state.page) return;
      state.page = page;
      redraw();
    }

    function scaleBy(factor) {
      const scale = clamp(state.scale * factor);
      if (scale === state.scale) return;
      state.scale = scale;
      redraw();
    }

    prev.addEventListener('click', () => turn(-1));
    next.addEventListener('click', () => turn(1));
    smaller.addEventListener('click', () => scaleBy(1 / ZOOM_STEP));
    larger.addEventListener('click', () => scaleBy(ZOOM_STEP));
    box.addEventListener('keydown', (e) => {
      if (!state.doc || e.altKey || e.ctrlKey || e.metaKey) return;
      if (e.key === 'ArrowLeft' || e.key === 'PageUp') turn(-1);
      else if (e.key === 'ArrowRight' || e.key === 'PageDown') turn(1);
      else return;
      e.preventDefault();
    });

    library().then((lib) => {
      state.lib = lib;
      return lib.getDocument({
        data: new Uint8Array(bytes), cMapUrl: `${BASE}cmaps/`, cMapPacked: true,
        standardFontDataUrl: `${BASE}standard_fonts/`, wasmUrl: `${BASE}wasm/`, iccUrl: `${BASE}iccs/`,
        // Named so that nothing in the PDF runs, whatever a later version
        // makes of them (the pinned one has no eval and draws no
        // annotations here).
        enableXfa: false, enableScripting: false, isEvalSupported: false
      }).promise;
    }).then((doc) => {
      if (state.disposed) {
        doc.destroy();
        return null;
      }
      state.doc = doc;
      state.pages = doc.numPages;
      redraw();
      return null;
    }).catch(fail);

    return {
      state: () => ({ page: state.page, pages: state.pages, scale: state.scale }),
      shown: () => Object.assign({}, drawnNow),
      dispose: () => {
        state.disposed = true;
        if (state.task) state.task.cancel();
        if (state.text && typeof state.text.cancel === 'function') state.text.cancel();
        if (state.doc) state.doc.destroy();
      }
    };
  }

  const WorkbenchPdf = {
    show: show,
    // How pdf.js is loaded (a module beside the page's scripts).
    loader: () => import(`${BASE}pdf.min.mjs`)
  };
  window.WorkbenchPdf = WorkbenchPdf;
})(window);
