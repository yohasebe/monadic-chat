/**
 * The pointer of the work screen: the user marks a part of what an item
 * shows (a rectangle or an ellipse, drawn translucent over it) to point at
 * it in the message they send. The item's view gives a surface to draw on
 * and where it is (for a PDF, the page); the pointer gives its buttons, the
 * mark, and what is marked.
 *
 * WorkbenchPointer.attach({ surface, where, changed }) puts a layer over
 * surface (a positioned element) and returns a handle; changed(pointer), when
 * given, is called each time the mark is made, moved or taken away:
 * - controls: the pointer's buttons (point, the look, take it away), to be
 *   put in the view's bar
 * - pointer(): what is marked ({ at, by, shape, color, x, y, w, h }: at is
 *   where() when it was marked, by is 'user', the four are fractions of the
 *   surface's width and height) or null; pointerSeq() counts its changes
 * - refresh(): shows the mark only where it was made (call it when where()
 *   changes)
 * - setPointable(flag): shows or hides the buttons (they are shown only
 *   where the chat's model takes images)
 * - escape(): stops drawing and closes the look's menu; true when there was
 *   either to stop
 * - clear(): stops drawing and takes the mark away
 * - dispose()
 *
 * WorkbenchPointer.control(...) and group(...) make the buttons and groups
 * of a view's bar, as the pointer's own are made.
 */
(function (window) {
  'use strict';

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
  const EDGES = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw'];
  // A drag shorter than this (a fraction) is a click: a small part around it.
  const SMALLEST = 0.01;
  const CLICK_W = 0.2;
  const CLICK_H = 0.05;
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

  // A button of a view's bar: an icon, its name as a tooltip (tips collects
  // the tooltips, to be let go with the view).
  // A tool on its group's panel (buttons.css), square.
  function control(className, label, icon, { tip, tips } = {}) {
    const b = element('button', `btn btn-sm btn-tool btn-icon workbench-icon-btn ${className}`);
    b.type = 'button';
    b.innerHTML = `<i class="${icon}" aria-hidden="true"></i>`;
    b.setAttribute('aria-label', label);
    b.title = tip || label;
    // Its text kept here too: the tooltip takes the title.
    b.help = b.title;
    if (window.MonadicTip) {
      const tooltip = window.MonadicTip.attach(b, { delay: { show: 500, hide: 0 } });
      if (tips) tips.push(tooltip);
      b.tip = tooltip;
    }
    return b;
  }

  function group(label, ...children) {
    const g = element('div', 'btn-panel workbench-bar-group');
    g.setAttribute('role', 'group');
    g.setAttribute('aria-label', label);
    g.append(...children);
    return g;
  }

  function attach({ surface, where, changed }) {
    const tips = [];
    // The buttons: draw a mark (the next drag over the surface, in the
    // color of the mark), choose its look (shape and color), take it away.
    const point = control('workbench-pointer-point', t('ui.workbench.pointAt', 'Point at a part of it'), 'fa-solid fa-crosshairs', {
      tip: t('ui.workbench.pointHelp',
        'Drag over it to mark the part you mean. Your next message takes a picture of what is in view, mark included. Hidden words are not hidden in the picture.'),
      tips
    });
    point.setAttribute('aria-pressed', 'false');
    const lookButton = control('workbench-pointer-look', t('ui.workbench.pointLook', 'The look of the mark'), 'fa-regular fa-square', { tips });
    lookButton.setAttribute('aria-haspopup', 'true');
    lookButton.setAttribute('aria-expanded', 'false');
    const unpoint = control('workbench-pointer-unpoint', t('ui.workbench.pointClear', 'Take the mark away'), 'fa-solid fa-xmark', { tips });
    // The look's menu: the two shapes, then the colors.
    const lookMenu = element('div', 'workbench-pointer-look-menu');
    lookMenu.hidden = true;
    lookMenu.setAttribute('role', 'group');
    lookMenu.setAttribute('aria-label', t('ui.workbench.pointLook', 'The look of the mark'));
    function choice(kind, value, label) {
      const b = element('button', `btn btn-sm btn-tool btn-icon workbench-icon-btn workbench-pointer-look-${kind}`);
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
      const swatch = element('span', 'workbench-pointer-swatch');
      swatch.style.background = COLORS[value].line;
      swatch.style.color = COLORS[value].ink;
      swatch.innerHTML = '<i class="fa-solid fa-check" aria-hidden="true"></i>';
      b.append(swatch);
      return b;
    });
    const lookRow = (label, buttons) => {
      const row = element('div', 'workbench-pointer-look-row');
      row.append(element('span', 'workbench-pointer-look-label', label), ...buttons);
      return row;
    };
    lookMenu.append(lookRow(t('ui.workbench.pointShape', 'Shape'), shapeChoices),
      lookRow(t('ui.workbench.pointColor', 'Color'), colorChoices));
    const controls = group(t('ui.workbench.pointAt', 'Point at a part of it'), point, lookButton, unpoint, lookMenu);
    controls.classList.add('workbench-pointer-controls');
    controls.classList.add('workbench-pointer-controls');
    controls.hidden = true;

    // Over the surface (above what it shows while a mark is being drawn).
    const layer = element('div', 'workbench-pointer-layer');
    const mark = element('div', 'workbench-pointer');
    mark.hidden = true;
    // Its sides and corners, held to change its size (the mark itself, to
    // move it).
    EDGES.forEach((edge) => {
      const handle = element('span', `workbench-pointer-handle workbench-pointer-${edge}`);
      handle.dataset.edge = edge;
      mark.append(handle);
    });
    layer.append(mark);
    surface.append(layer);

    // Where the mark is (fractions of the surface), whether the next drag
    // draws it, and how many times it changed.
    let pointer = null;
    let pointerSeq = 0;
    let drawing = false;
    let pointable = false;
    let look = savedLook();

    function showPointer() {
      const here = pointer && pointer.at === where();
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
      // The face's colors (monadic.css: .workbench-pointer-point), darker
      // while drawing.
      point.style.setProperty('--mark-face', colors.line);
      point.style.setProperty('--mark-ink', colors.ink);
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
      if (!lookMenu.hidden && !controls.contains(e.target)) openLook(false);
    }
    document.addEventListener('pointerdown', closeLookOutside, true);

    // Drawing: the button is pressed (darker, its icon a pen), and its name
    // says how to stop.
    const POINT_HELP = point.help;
    const DRAWING_HELP = t('ui.workbench.pointDrawing', 'Drag over it to draw the mark. Press this again or Esc to stop.');
    function drawMode(on) {
      drawing = !!on && pointable;
      layer.classList.toggle('workbench-pointer-drawing', drawing);
      point.classList.toggle('active', drawing);
      point.setAttribute('aria-pressed', drawing ? 'true' : 'false');
      point.firstChild.className = drawing ? 'fa-solid fa-pen' : 'fa-solid fa-crosshairs';
      const help = drawing ? DRAWING_HELP : POINT_HELP;
      point.setAttribute('aria-label', drawing ? DRAWING_HELP : t('ui.workbench.pointAt', 'Point at a part of it'));
      if (point.tip) point.tip.setText(help);
      else point.title = help;
    }

    function setPointer(next) {
      pointer = next;
      pointerSeq += 1;
      showPointer();
      if (typeof changed === 'function') changed(pointer);
    }

    // The point on the surface under an event, as fractions (within 0..1).
    function fractionAt(e) {
      const r = layer.getBoundingClientRect();
      if (!(r.width > 0 && r.height > 0)) return null;
      const clip = (v) => Math.min(1, Math.max(0, v));
      return { x: clip((e.clientX - r.left) / r.width), y: clip((e.clientY - r.top) / r.height) };
    }
    const marked = (fields) => Object.assign({ at: where(), by: 'user', shape: look.shape, color: look.color }, fields);

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
      pointer = marked({ x: Math.min(start.x, now.x), y: Math.min(start.y, now.y),
                         w: Math.abs(now.x - start.x), h: Math.abs(now.y - start.y) });
      showPointer();
    });
    layer.addEventListener('pointerup', (e) => {
      if (!drawing || !start) return;
      const end = fractionAt(e) || start;
      let next = marked({ x: Math.min(start.x, end.x), y: Math.min(start.y, end.y),
                          w: Math.abs(end.x - start.x), h: Math.abs(end.y - start.y) });
      // A click marks a small part around it.
      if (next.w < SMALLEST || next.h < SMALLEST) {
        next = marked({ x: Math.min(1 - CLICK_W, Math.max(0, end.x - CLICK_W / 2)),
                        y: Math.min(1 - CLICK_H, Math.max(0, end.y - CLICK_H / 2)), w: CLICK_W, h: CLICK_H });
      }
      start = null;
      setPointer(next);
      drawMode(false);
    });
    // Holding the mark moves it; holding a side or a corner moves that side
    // or those sides. The change counts once, when the mark is let go.
    let held = null;
    mark.addEventListener('pointerdown', (e) => {
      // A mark that can no longer be changed (setPointable(false)) stays as it is.
      if (!pointable || drawing || !pointer || e.button !== 0) return;
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
    showPointer();

    return {
      controls: controls,
      pointer: () => (pointer ? Object.assign({}, pointer) : null),
      pointerSeq: () => pointerSeq,
      refresh: showPointer,
      setPointable: (flag) => {
        pointable = !!flag;
        controls.hidden = !pointable;
        if (!pointable) drawMode(false);
      },
      clear: () => {
        drawMode(false);
        openLook(false);
        if (pointer) setPointer(null);
      },
      escape: () => {
        if (!drawing && lookMenu.hidden) return false;
        drawMode(false);
        openLook(false);
        return true;
      },
      dispose: () => {
        tips.forEach((tip) => { try { tip.dispose(); } catch (_) { /* gone with the page */ } });
        document.removeEventListener('pointerdown', closeLookOutside, true);
      }
    };
  }

  window.WorkbenchPointer = { attach: attach, control: control, group: group, COLORS: COLORS };
})(window);
