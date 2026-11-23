/**
 * A PDF in the work screen, drawn with pdf.js (kept under /vendor/pdfjs at
 * a pinned version, loaded the first time a PDF is shown): one page at a
 * time, with pdf.js's text layer over it so the user can select its text.
 * ‹ and › (or ← and → while the PDF has the focus) move between pages; −
 * and + zoom. The page fits the pane's width, also when the pane's width
 * changes (a moment after it stops changing), until the user zooms; from
 * then on the scale they chose stays. The page shown stays.
 *
 * The bytes are the item's, taken whole from its address (the version the
 * item was opened at). Nothing in the PDF acts: no scripts, no forms, no
 * links (annotations are not drawn). A canvas is never larger than
 * MAX_PIXELS; on a high-density screen the page is drawn sharper within
 * that.
 *
 * WorkbenchPdf.show(box, bytes, onChange) draws into box and returns a
 * handle: state() (the page and scale asked for), shown() (what is drawn
 * now: { status: 'ready', page, pages, scale, drawing } once a page and its
 * text layer are drawn, drawing being the number of that drawing,
 * otherwise { status: 'loading' | 'drawing' | 'failed' }), canvas() and
 * textLayer() (the page's canvas and its text layer, as drawn now), and
 * dispose() (stops drawing and lets the document go). onChange is called
 * whenever shown() changes.
 *
 * The pointer: the user can mark a part of a page (a rectangle or an
 * ellipse, drawn translucent over it) to point at it in the message they
 * send. pointer() is that part ({ page, shape, color, x, y, w, h }, the four as
 * fractions of the page's width and height) or null; pointerSeq() counts
 * its changes; setPointable(flag) shows or hides its buttons (they are
 * shown only where the chat's model takes images).
 *
 * The document is let go through the task that loads it (getDocument's
 * return): pdf.js's document has no destroy of its own. Disposed before
 * pdf.js is loaded, the document is never asked for; disposed while it
 * loads or a page draws, what finishes later changes nothing here.
 */
(function (window) {
  'use strict';

  const BASE = '/vendor/pdfjs/';
  const MAX_PIXELS = 4096 * 4096;
  const MIN_SCALE = 0.25;
  const MAX_SCALE = 4;
  const ZOOM_STEP = 1.25;
  // Milliseconds the pane's width must stay still before the page is fitted
  // to it again.
  const REFIT_DELAY = 150;

  let loading = null;

  // The colors a mark can take (named: the model is told the name): its
  // fill, its line, and the icon's color on a button of its line.
  const COLORS = {
    orange: { fill: 'rgba(240, 160, 80, 0.28)', line: '#d98a3d', ink: '#fff' },
    magenta: { fill: 'rgba(214, 112, 176, 0.25)', line: '#c25a9a', ink: '#fff' },
    cyan: { fill: 'rgba(90, 180, 215, 0.28)', line: '#3d9fbf', ink: '#fff' },
    green: { fill: 'rgba(110, 185, 120, 0.28)', line: '#4f9e5c', ink: '#fff' },
    yellow: { fill: 'rgba(235, 210, 90, 0.33)', line: '#c9a93a', ink: '#2b2b2b' }
  };
  const SHAPES = ['rect', 'ellipse'];
  // The look the next mark takes, as this browser last chose it.
  const LOOK_KEY = 'monadic-pointer-look';
  function savedLook() {
    try {
      const look = JSON.parse(window.localStorage.getItem(LOOK_KEY) || '{}');
      return { shape: SHAPES.includes(look.shape) ? look.shape : 'rect', color: COLORS[look.color] ? look.color : 'orange' };
    } catch (_) {
      return { shape: 'rect', color: 'orange' };
    }
  }
  function saveLook(look) {
    try { window.localStorage.setItem(LOOK_KEY, JSON.stringify(look)); } catch (_) { /* kept for this page only */ }
  }
  const capital = (name) => name.charAt(0).toUpperCase() + name.slice(1);

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
    // rendering: the page being drawn; loading: the task that loads the
    // document (and lets it go).
    // fit: the scale follows the pane's width (until the user zooms).
    const state = { page: 1, pages: 0, scale: null, fit: true, lib: null, doc: null, rendering: null, loading: null, text: null,
                    disposed: false };
    // What is drawn: the drawing it comes from (gen) and its status.
    let gen = 0;
    let drawnNow = { status: 'loading' };
    function settle(next) {
      drawnNow = next;
      if (typeof onChange === 'function' && !state.disposed) onChange(drawnNow);
    }
    // The bar: three groups (pages, zoom, the pointer), each button with its
    // name as a tooltip.
    const bar = element('div', 'workbench-pdf-bar d-flex flex-wrap align-items-center gap-3');
    const tips = [];
    function control(className, label, icon, tip, kind = 'btn-secondary') {
      const b = element('button', `btn btn-sm ${kind} workbench-pdf-icon ${className}`);
      b.type = 'button';
      b.innerHTML = `<i class="${icon}" aria-hidden="true"></i>`;
      b.setAttribute('aria-label', label);
      b.title = tip || label;
      if (typeof bootstrap !== 'undefined' && bootstrap.Tooltip) {
        try {
          const tip = new bootstrap.Tooltip(b, { trigger: 'hover', delay: { show: 500, hide: 0 }, container: 'body', html: false });
          tips.push(tip);
          b.tip = tip;
        } catch (_) { /* the title stays */ }
      }
      return b;
    }
    function group(label, ...children) {
      const g = element('div', 'd-inline-flex align-items-center gap-1 workbench-pdf-group');
      g.setAttribute('role', 'group');
      g.setAttribute('aria-label', label);
      g.append(...children);
      return g;
    }
    const prev = control('workbench-pdf-prev', t('ui.workbench.pdfPrev', 'Previous page'), 'fa-solid fa-chevron-left');
    const next = control('workbench-pdf-next', t('ui.workbench.pdfNext', 'Next page'), 'fa-solid fa-chevron-right');
    const where = element('span', 'workbench-pdf-label workbench-pdf-where', '');
    const smaller = control('workbench-pdf-out', t('ui.workbench.zoomOut', 'Zoom out'), 'fa-solid fa-minus');
    const larger = control('workbench-pdf-in', t('ui.workbench.zoomIn', 'Zoom in'), 'fa-solid fa-plus');
    const zoom = element('span', 'workbench-pdf-label workbench-pdf-zoom', '');
    [prev, next, smaller, larger].forEach((b) => { b.disabled = true; });
    // The pointer's buttons: draw one (the next drag on the page, in the
    // color of the mark), choose its look (shape and color), take it away.
    const point = control('workbench-pdf-point', t('ui.workbench.pointAt', 'Point at a part of the page'), 'fa-solid fa-crosshairs',
      t('ui.workbench.pointHelp',
        'Drag over the page to mark the part you mean. Your next message takes a picture of the part in view, mark included. Hidden words are not hidden in the picture.'),
      'btn-info');
    point.setAttribute('aria-pressed', 'false');
    const lookButton = control('workbench-pdf-look', t('ui.workbench.pointLook', 'The look of the mark'), 'fa-regular fa-square');
    lookButton.setAttribute('aria-haspopup', 'true');
    lookButton.setAttribute('aria-expanded', 'false');
    const unpoint = control('workbench-pdf-unpoint', t('ui.workbench.pointClear', 'Take the mark away'), 'fa-solid fa-xmark');
    // The look's menu: the two shapes, then the colors.
    const lookMenu = element('div', 'workbench-pdf-look-menu');
    lookMenu.hidden = true;
    lookMenu.setAttribute('role', 'group');
    lookMenu.setAttribute('aria-label', t('ui.workbench.pointLook', 'The look of the mark'));
    function choice(kind, value, label) {
      const b = element('button', `btn btn-sm btn-secondary workbench-pdf-icon workbench-pdf-look-${kind}`);
      b.type = 'button';
      b.dataset[kind] = value;
      b.setAttribute('aria-label', label);
      b.title = label;
      return b;
    }
    const shapeChoices = SHAPES.map((value) => {
      const b = choice('shape', value, value === 'ellipse' ? t('ui.workbench.pointEllipse', 'Ellipse') : t('ui.workbench.pointRect', 'Rectangle'));
      b.innerHTML = `<i class="fa-regular ${value === 'ellipse' ? 'fa-circle' : 'fa-square'}" aria-hidden="true"></i>`;
      return b;
    });
    const colorChoices = Object.keys(COLORS).map((value) => {
      const b = choice('color', value, t(`ui.workbench.color${capital(value)}`, capital(value)));
      const swatch = element('span', 'workbench-pdf-swatch');
      swatch.style.background = COLORS[value].line;
      swatch.style.color = COLORS[value].ink;
      swatch.innerHTML = '<i class="fa-solid fa-check" aria-hidden="true"></i>';
      b.append(swatch);
      return b;
    });
    const lookRow = (label, buttons) => {
      const row = element('div', 'workbench-pdf-look-row');
      row.append(element('span', 'workbench-pdf-look-label', label), ...buttons);
      return row;
    };
    lookMenu.append(lookRow(t('ui.workbench.pointShape', 'Shape'), shapeChoices),
      lookRow(t('ui.workbench.pointColor', 'Color'), colorChoices));
    const pointing = group(t('ui.workbench.pointAt', 'Point at a part of the page'), point, lookButton, unpoint, lookMenu);
    pointing.classList.add('workbench-pdf-pointing');
    pointing.hidden = true;
    bar.append(group(t('ui.workbench.page', 'Page'), prev, where, next),
      group(t('ui.workbench.zoomIn', 'Zoom in'), smaller, zoom, larger), pointing);
    const sheet = element('div', 'workbench-pdf-page');
    const canvas = element('canvas');
    // Over the page (above its text layer while a mark is being drawn).
    const layer = element('div', 'workbench-pointer-layer');
    const mark = element('div', 'workbench-pointer');
    mark.hidden = true;
    // Its sides and corners, held to change its size (the mark itself, to
    // move it).
    ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw'].forEach((edge) => {
      const handle = element('span', `workbench-pointer-handle workbench-pointer-${edge}`);
      handle.dataset.edge = edge;
      mark.append(handle);
    });
    layer.append(mark);
    sheet.append(canvas, layer);
    box.classList.add('workbench-pdf');
    box.setAttribute('tabindex', '0');
    box.replaceChildren(bar, sheet);

    function fail() {
      if (state.disposed) return;
      settle({ status: 'failed' });
      box.replaceChildren(element('div', 'alert alert-warning mb-0', t('ui.workbench.pdfFailed', 'The PDF could not be shown.')));
    }

    // The pointer: where it is (fractions of the page), whether the next drag
    // draws it, and how many times it changed.
    let pointer = null;
    let pointerSeq = 0;
    let drawing = false;
    let pointable = false;
    let look = savedLook();
    const SMALLEST = 0.01;

    function showPointer() {
      const here = pointer && pointer.page === state.page;
      mark.hidden = !here;
      if (here) {
        mark.style.left = `${pointer.x * 100}%`;
        mark.style.top = `${pointer.y * 100}%`;
        mark.style.width = `${pointer.w * 100}%`;
        mark.style.height = `${pointer.h * 100}%`;
        mark.classList.toggle('workbench-pointer-ellipse', pointer.shape === 'ellipse');
        const colors = COLORS[pointer.color] || COLORS.orange;
        mark.style.setProperty('--mark-fill', colors.fill);
        mark.style.setProperty('--mark-line', colors.line);
      }
      showLook();
      unpoint.disabled = !pointer;
    }

    // The look in the buttons: pointing in the mark's color, the look's
    // button with its shape, the chosen shape and color pressed.
    function showLook() {
      const colors = COLORS[look.color];
      point.style.setProperty('--bs-btn-bg', colors.line);
      point.style.setProperty('--bs-btn-border-color', colors.line);
      point.style.setProperty('--bs-btn-hover-bg', colors.line);
      point.style.setProperty('--bs-btn-hover-border-color', colors.line);
      // Pressed (drawing): darker.
      point.style.setProperty('--bs-btn-active-bg', `color-mix(in srgb, ${colors.line} 65%, #000)`);
      point.style.setProperty('--bs-btn-active-border-color', `color-mix(in srgb, ${colors.line} 65%, #000)`);
      ['color', 'hover-color', 'active-color', 'disabled-color'].forEach((k) => point.style.setProperty(`--bs-btn-${k}`, colors.ink));
      lookButton.firstChild.className = `fa-regular ${look.shape === 'ellipse' ? 'fa-circle' : 'fa-square'}`;
      shapeChoices.forEach((b) => b.setAttribute('aria-pressed', b.dataset.shape === look.shape ? 'true' : 'false'));
      colorChoices.forEach((b) => b.setAttribute('aria-pressed', b.dataset.color === look.color ? 'true' : 'false'));
    }
    function openLook(on) {
      lookMenu.hidden = !on;
      lookButton.setAttribute('aria-expanded', on ? 'true' : 'false');
      lookButton.classList.toggle('active', !!on);
    }
    // A look chosen is kept for the next mark, and changes the mark there is.
    function choose(change) {
      look = Object.assign({}, look, change);
      saveLook(look);
      if (pointer) setPointer(Object.assign({}, pointer, change));
      else showLook();
    }
    lookButton.addEventListener('click', () => openLook(lookMenu.hidden));
    shapeChoices.forEach((b) => b.addEventListener('click', () => choose({ shape: b.dataset.shape })));
    colorChoices.forEach((b) => b.addEventListener('click', () => choose({ color: b.dataset.color })));
    function closeLookOutside(e) {
      if (!lookMenu.hidden && !pointing.contains(e.target)) openLook(false);
    }
    document.addEventListener('pointerdown', closeLookOutside, true);

    // Drawing: the button is pressed (darker, its icon a pen), and its name
    // says how to stop.
    const POINT_HELP = point.title;
    const DRAWING_HELP = t('ui.workbench.pointDrawing', 'Drag over the page to draw the mark. Press this again or Esc to stop.');
    function drawMode(on) {
      drawing = !!on && pointable;
      layer.classList.toggle('workbench-pointer-drawing', drawing);
      point.classList.toggle('active', drawing);
      point.setAttribute('aria-pressed', drawing ? 'true' : 'false');
      point.firstChild.className = drawing ? 'fa-solid fa-pen' : 'fa-solid fa-crosshairs';
      const help = drawing ? DRAWING_HELP : POINT_HELP;
      point.setAttribute('aria-label', drawing ? DRAWING_HELP : t('ui.workbench.pointAt', 'Point at a part of the page'));
      if (point.tip && typeof point.tip.setContent === 'function') point.tip.setContent({ '.tooltip-inner': help });
      else point.title = help;
    }

    function setPointer(next) {
      pointer = next;
      pointerSeq += 1;
      showPointer();
    }

    // The point in the page under an event, as fractions (within 0..1).
    function fractionAt(e) {
      const r = layer.getBoundingClientRect();
      if (!(r.width > 0 && r.height > 0)) return null;
      const clip = (v) => Math.min(1, Math.max(0, v));
      return { x: clip((e.clientX - r.left) / r.width), y: clip((e.clientY - r.top) / r.height) };
    }

    let start = null;
    layer.addEventListener('pointerdown', (e) => {
      if (!drawing || e.button !== 0) return;
      start = fractionAt(e);
      if (!start) return;
      layer.setPointerCapture(e.pointerId);
      e.preventDefault();
    });
    layer.addEventListener('pointermove', (e) => {
      if (!drawing || !start) return;
      const now = fractionAt(e);
      if (!now) return;
      pointer = { page: state.page, shape: look.shape, color: look.color,
                  x: Math.min(start.x, now.x), y: Math.min(start.y, now.y),
                  w: Math.abs(now.x - start.x), h: Math.abs(now.y - start.y) };
      showPointer();
    });
    layer.addEventListener('pointerup', (e) => {
      if (!drawing || !start) return;
      const end = fractionAt(e) || start;
      let next = { page: state.page, shape: look.shape, color: look.color, x: Math.min(start.x, end.x), y: Math.min(start.y, end.y),
                   w: Math.abs(end.x - start.x), h: Math.abs(end.y - start.y) };
      // A click marks a small part around it.
      if (next.w < SMALLEST || next.h < SMALLEST) {
        const w = 0.2;
        const h = 0.05;
        next = { page: state.page, shape: look.shape, color: look.color, x: Math.min(1 - w, Math.max(0, end.x - w / 2)),
                 y: Math.min(1 - h, Math.max(0, end.y - h / 2)), w: w, h: h };
      }
      start = null;
      setPointer(next);
      drawMode(false);
    });
    // Holding the mark moves it; holding a side or a corner moves that side
    // or those sides. The change counts once, when the mark is let go.
    let held = null;
    mark.addEventListener('pointerdown', (e) => {
      if (drawing || !pointer || e.button !== 0) return;
      const from = fractionAt(e);
      if (!from) return;
      const handle = e.target.closest && e.target.closest('.workbench-pointer-handle');
      // The margin around the mark (where its sides and corners show) holds
      // nothing.
      const inside = from.x >= pointer.x && from.x <= pointer.x + pointer.w && from.y >= pointer.y && from.y <= pointer.y + pointer.h;
      if (!handle && !inside) return;
      held = { edge: handle ? handle.dataset.edge : 'move', from: from, was: pointer };
      mark.classList.add('workbench-pointer-held');
      if (typeof mark.setPointerCapture === 'function') mark.setPointerCapture(e.pointerId);
      e.preventDefault();
      e.stopPropagation();
    });
    function heldTo(e) {
      const now = fractionAt(e);
      if (!now) return null;
      const was = held.was;
      const dx = now.x - held.from.x;
      const dy = now.y - held.from.y;
      const clip = (v) => Math.min(1, Math.max(0, v));
      if (held.edge === 'move') {
        return Object.assign({}, was, { x: clip(Math.min(1 - was.w, was.x + dx)), y: clip(Math.min(1 - was.h, was.y + dy)) });
      }
      let left = was.x;
      let right = was.x + was.w;
      let top = was.y;
      let bottom = was.y + was.h;
      if (held.edge.includes('w')) left = clip(left + dx);
      if (held.edge.includes('e')) right = clip(right + dx);
      if (held.edge.includes('n')) top = clip(top + dy);
      if (held.edge.includes('s')) bottom = clip(bottom + dy);
      const x = Math.min(left, right);
      const y = Math.min(top, bottom);
      return Object.assign({}, was, { x: x, y: y, w: Math.max(SMALLEST, Math.min(1 - x, Math.abs(right - left))),
                                       h: Math.max(SMALLEST, Math.min(1 - y, Math.abs(bottom - top))) });
    }
    mark.addEventListener('pointermove', (e) => {
      if (!held) return;
      const next = heldTo(e);
      if (!next) return;
      pointer = next;
      showPointer();
    });
    function letGo(e) {
      if (!held) return;
      const next = heldTo(e) || pointer;
      const was = held.was;
      held = null;
      mark.classList.remove('workbench-pointer-held');
      if (['x', 'y', 'w', 'h'].some((k) => next[k] !== was[k])) setPointer(next);
      else showPointer();
    }
    mark.addEventListener('pointerup', letGo);
    mark.addEventListener('pointercancel', () => {
      if (!held) return;
      pointer = held.was;
      held = null;
      mark.classList.remove('workbench-pointer-held');
      showPointer();
    });
    point.addEventListener('click', () => drawMode(!drawing));
    unpoint.addEventListener('click', () => {
      drawMode(false);
      if (pointer) setPointer(null);
    });

    function label() {
      showPointer();
      where.textContent = t('ui.workbench.pageOf', 'Page {n} of {total}')
        .replace('{n}', String(state.page)).replace('{total}', String(state.pages));
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
        fittedWidth = box.clientWidth;
        state.scale = box.clientWidth > 0 && width > 0 ? clamp(box.clientWidth / width) : 1;
      }
      const viewport = page.getViewport({ scale: state.scale });
      const ratio = Math.min(window.devicePixelRatio || 1, Math.sqrt(MAX_PIXELS / (viewport.width * viewport.height)));
      stopRendering();
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
      state.rendering = task;
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
      settle({ status: 'ready', page: n, pages: state.pages, scale: state.scale, drawing: mine });
    }

    function stopRendering() {
      const task = state.rendering;
      state.rendering = null;
      try {
        if (task) task.cancel();
      } catch (_) { /* already done */ }
    }

    // The document goes with the task that loaded it; a failure to let it
    // go stops nothing that comes after.
    function release() {
      const task = state.loading;
      state.loading = null;
      state.doc = null;
      if (!task) return;
      try {
        Promise.resolve(task.destroy()).catch(() => {});
      } catch (_) { /* already gone */ }
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
      state.fit = false;
      state.scale = scale;
      redraw();
    }

    // The pane's width changed (the border between the columns moved, the
    // window was resized): once it stays, the page is fitted to it again,
    // while it follows the width. A hidden pane (no width) changes nothing.
    let fittedWidth = 0;
    let refitTimer = null;
    const watcher = typeof ResizeObserver === 'function' ? new ResizeObserver(() => {
      const width = box.clientWidth;
      // Hidden (no width) before the wait was over: nothing is fitted.
      clearTimeout(refitTimer);
      refitTimer = null;
      if (!width || width === fittedWidth) return;
      refitTimer = setTimeout(() => {
        refitTimer = null;
        const now = box.clientWidth;
        if (state.disposed || !state.fit || !state.doc || !now || now === fittedWidth) return;
        state.scale = null;
        redraw();
      }, REFIT_DELAY);
    }) : null;
    if (watcher) watcher.observe(box);

    prev.addEventListener('click', () => turn(-1));
    next.addEventListener('click', () => turn(1));
    smaller.addEventListener('click', () => scaleBy(1 / ZOOM_STEP));
    larger.addEventListener('click', () => scaleBy(ZOOM_STEP));
    box.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && (drawing || !lookMenu.hidden)) {
        drawMode(false);
        openLook(false);
        e.preventDefault();
        return;
      }
      if (!state.doc || e.altKey || e.ctrlKey || e.metaKey) return;
      if (e.key === 'ArrowLeft' || e.key === 'PageUp') turn(-1);
      else if (e.key === 'ArrowRight' || e.key === 'PageDown') turn(1);
      else return;
      e.preventDefault();
    });

    library().then((lib) => {
      if (state.disposed) return null;
      state.lib = lib;
      state.loading = lib.getDocument({
        data: new Uint8Array(bytes), cMapUrl: `${BASE}cmaps/`, cMapPacked: true,
        standardFontDataUrl: `${BASE}standard_fonts/`, wasmUrl: `${BASE}wasm/`, iccUrl: `${BASE}iccs/`,
        // Named so that nothing in the PDF runs, whatever a later version
        // makes of them (the pinned one has no eval and draws no
        // annotations here).
        enableXfa: false, enableScripting: false, isEvalSupported: false
      });
      return state.loading.promise;
    }).then((doc) => {
      if (!doc || state.disposed) return null;
      state.doc = doc;
      state.pages = doc.numPages;
      redraw();
      return null;
    }).catch(fail);

    return {
      state: () => ({ page: state.page, pages: state.pages, scale: state.scale }),
      shown: () => Object.assign({}, drawnNow),
      canvas: () => canvas,
      textLayer: () => sheet.querySelector('.textLayer'),
      pointer: () => (pointer ? Object.assign({}, pointer) : null),
      pointerSeq: () => pointerSeq,
      setPointable: (flag) => {
        pointable = !!flag;
        pointing.hidden = !pointable;
        if (!pointable) drawMode(false);
      },
      dispose: () => {
        if (state.disposed) return;
        state.disposed = true;
        tips.forEach((tip) => { try { tip.dispose(); } catch (_) { /* gone with the page */ } });
        document.removeEventListener('pointerdown', closeLookOutside, true);
        if (watcher) watcher.disconnect();
        clearTimeout(refitTimer);
        stopRendering();
        try {
          if (state.text && typeof state.text.cancel === 'function') state.text.cancel();
        } catch (_) { /* already done */ }
        state.text = null;
        release();
      }
    };
  }

  const WorkbenchPdf = {
    show: show,
    // The colors of a mark (the picture sent draws it in the same).
    COLORS: COLORS,
    // How pdf.js is loaded (a module beside the page's scripts).
    loader: () => import(`${BASE}pdf.min.mjs`)
  };
  window.WorkbenchPdf = WorkbenchPdf;
})(window);
