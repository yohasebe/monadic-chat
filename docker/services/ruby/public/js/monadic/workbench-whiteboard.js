/**
 * A whiteboard on the work screen: shapes on a board of WIDTH × HEIGHT (a
 * pen's strokes, lines, arrows, rectangles, ellipses and texts), drawn as
 * SVG and edited with the tools in its bar. What it holds is the same as
 * the file keeps ({ version, width, height, shapes }); the server checks it
 * when it is saved (Workbench::Whiteboard).
 *
 * WorkbenchWhiteboard.show(box, data, { onChange }) draws data in box and
 * returns a handle:
 * - data(): the board as it is now
 * - load(data): the board drawn again as data has it (the undo history is
 *   let go)
 * - paint(context, width, height): the board painted on a canvas context of
 *   that size (as it is shown, without the tools)
 * - dispose()
 * onChange(data) is called after each change the user makes.
 */
(function (window) {
  'use strict';

  const WIDTH = 1600;
  const HEIGHT = 1000;
  const SVG = 'http://www.w3.org/2000/svg';
  // The colors and sizes a shape can take (by name / by number), the same
  // as the server takes.
  const COLORS = {
    black: '#222222', blue: '#2f6fd0', red: '#d04848', green: '#3c9a5f', orange: '#e08a2e', violet: '#8c6ed2'
  };
  const STROKES = [2, 4, 8];
  const SIZES = [20, 32, 48];
  const TOOLS = [
    ['pen', 'fa-solid fa-pen', 'Pen'],
    ['line', 'fa-solid fa-minus', 'Line'],
    ['arrow', 'fa-solid fa-arrow-right-long', 'Arrow'],
    ['rect', 'fa-regular fa-square', 'Rectangle'],
    ['ellipse', 'fa-regular fa-circle', 'Ellipse'],
    ['text', 'fa-solid fa-font', 'Text'],
    ['eraser', 'fa-solid fa-eraser', 'Eraser']
  ];
  const HISTORY = 100;
  // A pen's points closer than this (on the board) are one.
  const STEP = 2;

  function t(key, fallback) {
    return typeof webUIi18n !== 'undefined' ? webUIi18n.t(key) : fallback;
  }

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  function svg(tag, attrs) {
    const el = document.createElementNS(SVG, tag);
    Object.entries(attrs || {}).forEach(([k, v]) => el.setAttribute(k, String(v)));
    return el;
  }

  let counter = 0;
  function newId() {
    counter += 1;
    return `s${Date.now().toString(36)}${counter.toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;
  }

  const round = (v) => Math.round(v * 10) / 10;
  const color = (shape) => COLORS[shape.color] || COLORS.black;
  const textLines = (shape) => String(shape.text || '').split('\n');

  function emptyBoard() {
    return { version: 1, width: WIDTH, height: HEIGHT, shapes: [] };
  }

  // The board taken from data as far as it is one (the server keeps it so).
  function boardOf(data) {
    const shapes = data && Array.isArray(data.shapes) ? data.shapes.filter((s) => s && typeof s === 'object' && s.id) : [];
    return { version: 1, width: WIDTH, height: HEIGHT, shapes: shapes.map((s) => Object.assign({}, s)) };
  }

  // ---- drawing a shape ------------------------------------------------

  // The SVG element of a shape (its id in data-id).
  function shapeElement(shape) {
    const stroke = color(shape);
    const width = STROKES.includes(shape.stroke) ? shape.stroke : STROKES[1];
    let el;
    switch (shape.type) {
      case 'pen': {
        const points = shape.points || [];
        if (points.length === 1) {
          el = svg('circle', { cx: points[0][0], cy: points[0][1], r: width / 2, fill: stroke });
        } else {
          el = svg('polyline', { points: points.map((p) => p.join(',')).join(' '), fill: 'none', stroke: stroke,
            'stroke-width': width, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });
        }
        break;
      }
      case 'line':
      case 'arrow':
        el = svg('line', { x1: shape.x1, y1: shape.y1, x2: shape.x2, y2: shape.y2, stroke: stroke, 'stroke-width': width,
          'stroke-linecap': 'round' });
        if (shape.type === 'arrow') {
          const group = svg('g');
          group.append(el, svg('polygon', { points: arrowHead(shape, width).map((p) => p.join(',')).join(' '), fill: stroke }));
          el = group;
        }
        break;
      case 'rect':
      case 'ellipse':
        el = shape.type === 'rect'
          ? svg('rect', { x: shape.x, y: shape.y, width: shape.w, height: shape.h, rx: 6 })
          : svg('ellipse', { cx: shape.x + shape.w / 2, cy: shape.y + shape.h / 2, rx: shape.w / 2, ry: shape.h / 2 });
        el.setAttribute('stroke', stroke);
        el.setAttribute('stroke-width', String(width));
        el.setAttribute('fill', shape.fill ? stroke : 'none');
        if (shape.fill) el.setAttribute('fill-opacity', '0.15');
        break;
      case 'text': {
        const size = SIZES.includes(shape.size) ? shape.size : SIZES[0];
        el = svg('text', { x: shape.x, y: shape.y, fill: stroke, 'font-size': size, 'font-family': 'sans-serif' });
        textLines(shape).forEach((line, i) => {
          const span = svg('tspan', { x: shape.x, dy: i === 0 ? size : size * 1.25 });
          span.textContent = line || ' ';
          el.appendChild(span);
        });
        break;
      }
      default:
        return null;
    }
    el.setAttribute('data-id', shape.id);
    el.classList.add('workbench-whiteboard-shape');
    return el;
  }

  // The three corners of an arrow's head, at its end.
  function arrowHead(shape, width) {
    const angle = Math.atan2(shape.y2 - shape.y1, shape.x2 - shape.x1);
    const length = 10 + width * 3;
    const spread = Math.PI / 7;
    return [
      [shape.x2, shape.y2],
      [shape.x2 - length * Math.cos(angle - spread), shape.y2 - length * Math.sin(angle - spread)],
      [shape.x2 - length * Math.cos(angle + spread), shape.y2 - length * Math.sin(angle + spread)]
    ];
  }

  // Paints the board on a canvas context of width × height (white, as it is
  // shown).
  function paint(board, context, width, height) {
    const scale = Math.min(width / WIDTH, height / HEIGHT);
    context.save();
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, width, height);
    context.scale(scale, scale);
    context.lineCap = 'round';
    context.lineJoin = 'round';
    board.shapes.forEach((shape) => {
      const stroke = color(shape);
      const lineWidth = STROKES.includes(shape.stroke) ? shape.stroke : STROKES[1];
      context.strokeStyle = stroke;
      context.fillStyle = stroke;
      context.lineWidth = lineWidth;
      context.beginPath();
      switch (shape.type) {
        case 'pen': {
          const points = shape.points || [];
          if (points.length === 1) {
            context.arc(points[0][0], points[0][1], lineWidth / 2, 0, Math.PI * 2);
            context.fill();
            break;
          }
          points.forEach((p, i) => (i === 0 ? context.moveTo(p[0], p[1]) : context.lineTo(p[0], p[1])));
          context.stroke();
          break;
        }
        case 'line':
        case 'arrow':
          context.moveTo(shape.x1, shape.y1);
          context.lineTo(shape.x2, shape.y2);
          context.stroke();
          if (shape.type === 'arrow') {
            const head = arrowHead(shape, lineWidth);
            context.beginPath();
            context.moveTo(head[0][0], head[0][1]);
            context.lineTo(head[1][0], head[1][1]);
            context.lineTo(head[2][0], head[2][1]);
            context.closePath();
            context.fill();
          }
          break;
        case 'rect':
        case 'ellipse':
          if (shape.type === 'rect') context.rect(shape.x, shape.y, shape.w, shape.h);
          else context.ellipse(shape.x + shape.w / 2, shape.y + shape.h / 2, shape.w / 2, shape.h / 2, 0, 0, Math.PI * 2);
          if (shape.fill) {
            context.globalAlpha = 0.15;
            context.fill();
            context.globalAlpha = 1;
          }
          context.stroke();
          break;
        case 'text': {
          const size = SIZES.includes(shape.size) ? shape.size : SIZES[0];
          context.font = `${size}px sans-serif`;
          context.textBaseline = 'top';
          textLines(shape).forEach((line, i) => context.fillText(line, shape.x, shape.y + i * size * 1.25));
          break;
        }
        default:
          break;
      }
    });
    context.restore();
  }

  // The board as the text of an SVG (white, its shapes as the editor draws
  // them), for a view that only shows it.
  function svgText(data) {
    const board = boardOf(data);
    const root = svg('svg', { viewBox: `0 0 ${WIDTH} ${HEIGHT}`, width: WIDTH, height: HEIGHT });
    root.appendChild(svg('rect', { x: 0, y: 0, width: WIDTH, height: HEIGHT, fill: '#ffffff' }));
    board.shapes.map(shapeElement).filter(Boolean).forEach((el) => root.appendChild(el));
    return new XMLSerializer().serializeToString(root);
  }

  // ---- the editor -----------------------------------------------------

  function show(box, data, { onChange } = {}) {
    let board = data ? boardOf(data) : emptyBoard();
    const past = [];
    const future = [];
    const state = { tool: 'pen', color: 'black', stroke: STROKES[1], size: SIZES[1], disposed: false };
    const tips = [];

    const control = (className, label, icon) => window.WorkbenchPointer.control(className, label, icon, { tips });
    const group = window.WorkbenchPointer.group;
    const bar = element('div', 'workbench-whiteboard-bar d-flex flex-wrap align-items-center gap-3');
    const toolButtons = TOOLS.map(([tool, icon, name]) => {
      const b = control(`workbench-whiteboard-tool workbench-whiteboard-${tool}`, t(`ui.workbench.wb_${tool}`, name), icon);
      b.dataset.tool = tool;
      b.addEventListener('click', () => choose({ tool: tool }));
      return b;
    });
    const swatches = Object.keys(COLORS).map((name) => {
      const b = element('button', 'btn btn-sm workbench-whiteboard-color');
      b.type = 'button';
      b.dataset.color = name;
      b.style.setProperty('--wb-color', COLORS[name]);
      const label = t(`ui.workbench.wb_color_${name}`, name);
      b.setAttribute('aria-label', label);
      b.title = label;
      b.addEventListener('click', () => choose({ color: name }));
      return b;
    });
    const strokes = STROKES.map((width, i) => {
      const b = element('button', 'btn btn-sm btn-secondary workbench-icon-btn workbench-whiteboard-stroke');
      b.type = 'button';
      b.dataset.stroke = String(width);
      b.innerHTML = `<span class="workbench-whiteboard-stroke-dot" style="width:${4 + i * 4}px;height:${4 + i * 4}px"></span>`;
      const label = t(`ui.workbench.wb_stroke_${i + 1}`, ['Thin', 'Medium', 'Thick'][i]);
      b.setAttribute('aria-label', label);
      b.title = label;
      b.addEventListener('click', () => choose({ stroke: width, size: SIZES[i] }));
      return b;
    });
    const undo = control('workbench-whiteboard-undo', t('ui.workbench.wb_undo', 'Undo'), 'fa-solid fa-rotate-left');
    const redo = control('workbench-whiteboard-redo', t('ui.workbench.wb_redo', 'Redo'), 'fa-solid fa-rotate-right');
    const clear = control('workbench-whiteboard-clear', t('ui.workbench.wb_clear', 'Clear the whiteboard'), 'fa-solid fa-trash-can');
    undo.addEventListener('click', () => step(past, future));
    redo.addEventListener('click', () => step(future, past));
    clear.addEventListener('click', () => {
      if (board.shapes.length === 0) return;
      change(() => { board.shapes = []; });
    });
    bar.append(group(t('ui.workbench.wb_tools', 'Tools'), ...toolButtons),
      group(t('ui.workbench.wb_colors', 'Color'), ...swatches),
      group(t('ui.workbench.wb_strokes', 'Size'), ...strokes),
      group(t('ui.workbench.wb_history', 'Undo and redo'), undo, redo, clear));

    const sheet = element('div', 'workbench-whiteboard-sheet');
    const canvas = svg('svg', { viewBox: `0 0 ${WIDTH} ${HEIGHT}`, class: 'workbench-whiteboard-canvas', role: 'img' });
    canvas.setAttribute('aria-label', t('ui.workbench.wb_board', 'Whiteboard'));
    const defs = svg('g');
    const layer = svg('g');
    const preview = svg('g', { class: 'workbench-whiteboard-preview' });
    canvas.append(defs, layer, preview);
    sheet.appendChild(canvas);
    box.classList.add('workbench-whiteboard');
    box.replaceChildren(bar, sheet);

    function choose(next) {
      Object.assign(state, next);
      toolButtons.forEach((b) => {
        const on = b.dataset.tool === state.tool;
        b.classList.toggle('active', on);
        b.setAttribute('aria-pressed', on ? 'true' : 'false');
      });
      swatches.forEach((b) => b.classList.toggle('active', b.dataset.color === state.color));
      strokes.forEach((b) => b.classList.toggle('active', Number(b.dataset.stroke) === state.stroke));
      sheet.dataset.tool = state.tool;
    }

    function redraw() {
      layer.replaceChildren(...board.shapes.map(shapeElement).filter(Boolean));
      undo.disabled = past.length === 0;
      redo.disabled = future.length === 0;
      clear.disabled = board.shapes.length === 0;
    }

    const snapshot = () => JSON.stringify(board.shapes);

    // A change the user makes: kept for undo, drawn, and told.
    function change(apply) {
      past.push(snapshot());
      if (past.length > HISTORY) past.shift();
      future.length = 0;
      apply();
      redraw();
      if (typeof onChange === 'function') onChange(handle.data());
    }

    function step(from, to) {
      if (from.length === 0) return;
      to.push(snapshot());
      board.shapes = JSON.parse(from.pop());
      redraw();
      if (typeof onChange === 'function') onChange(handle.data());
    }

    // Where a pointer event is on the board.
    function at(e) {
      const rect = canvas.getBoundingClientRect();
      if (!(rect.width > 0 && rect.height > 0)) return [0, 0];
      return [round((e.clientX - rect.left) * WIDTH / rect.width), round((e.clientY - rect.top) * HEIGHT / rect.height)];
    }

    let drawing = null;

    function shapeFrom(start, end) {
      const base = { id: newId(), type: state.tool, by: 'user', color: state.color, stroke: state.stroke };
      if (state.tool === 'line' || state.tool === 'arrow') {
        return Object.assign(base, { x1: start[0], y1: start[1], x2: end[0], y2: end[1] });
      }
      return Object.assign(base, { x: Math.min(start[0], end[0]), y: Math.min(start[1], end[1]),
        w: round(Math.abs(end[0] - start[0])), h: round(Math.abs(end[1] - start[1])), fill: false });
    }

    function eraseAt(e) {
      const hit = document.elementFromPoint ? document.elementFromPoint(e.clientX, e.clientY) : null;
      const shapeEl = hit && hit.closest ? hit.closest('[data-id]') : null;
      if (!shapeEl || !layer.contains(shapeEl)) return;
      const id = shapeEl.getAttribute('data-id');
      change(() => { board.shapes = board.shapes.filter((s) => s.id !== id); });
    }

    canvas.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || state.disposed) return;
      e.preventDefault();
      if (state.tool === 'text') {
        writeText(at(e));
        return;
      }
      if (state.tool === 'eraser') {
        drawing = { erasing: true };
        eraseAt(e);
      } else {
        const start = at(e);
        drawing = { start: start, points: [start] };
      }
      if (canvas.setPointerCapture) {
        try { canvas.setPointerCapture(e.pointerId); } catch (_) { /* not captured */ }
      }
    });

    canvas.addEventListener('pointermove', (e) => {
      if (!drawing) return;
      if (drawing.erasing) {
        eraseAt(e);
        return;
      }
      const now = at(e);
      if (state.tool === 'pen') {
        const last = drawing.points[drawing.points.length - 1];
        if (Math.hypot(now[0] - last[0], now[1] - last[1]) < STEP) return;
        drawing.points.push(now);
        preview.replaceChildren(shapeElement({ id: 'preview', type: 'pen', color: state.color, stroke: state.stroke,
          points: drawing.points }));
      } else {
        drawing.end = now;
        preview.replaceChildren(shapeElement(Object.assign(shapeFrom(drawing.start, now), { id: 'preview' })));
      }
    });

    function finish() {
      const done = drawing;
      drawing = null;
      preview.replaceChildren();
      if (!done || done.erasing) return;
      if (state.tool === 'pen') {
        const shape = { id: newId(), type: 'pen', by: 'user', color: state.color, stroke: state.stroke,
          points: done.points.slice(0, 5000) };
        change(() => { board.shapes.push(shape); });
        return;
      }
      if (!done.end) return;
      const shape = shapeFrom(done.start, done.end);
      const tiny = shape.type === 'line' || shape.type === 'arrow'
        ? Math.hypot(shape.x2 - shape.x1, shape.y2 - shape.y1) < 4 : shape.w < 4 || shape.h < 4;
      if (tiny) return;
      change(() => { board.shapes.push(shape); });
    }
    canvas.addEventListener('pointerup', finish);
    canvas.addEventListener('pointercancel', finish);

    // A text typed at where the user clicked: Enter keeps it (Shift+Enter
    // starts a new line), Esc lets it go, and so does leaving it empty.
    function writeText(point) {
      const rect = canvas.getBoundingClientRect();
      const input = element('textarea', 'form-control workbench-whiteboard-input');
      input.rows = 1;
      input.style.left = `${(point[0] / WIDTH) * rect.width}px`;
      input.style.top = `${(point[1] / HEIGHT) * rect.height}px`;
      input.style.color = COLORS[state.color];
      input.setAttribute('aria-label', t('ui.workbench.wb_text', 'Text'));
      sheet.appendChild(input);
      let done = false;
      const keep = (save) => {
        if (done) return;
        done = true;
        const text = input.value.replace(/\s+$/, '');
        input.remove();
        if (!save || !text.trim()) return;
        const shape = { id: newId(), type: 'text', by: 'user', color: state.color, size: state.size, x: point[0], y: point[1],
          text: text.slice(0, 1000) };
        change(() => { board.shapes.push(shape); });
      };
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
          e.preventDefault();
          keep(true);
        } else if (e.key === 'Escape') {
          e.preventDefault();
          keep(false);
        }
      });
      input.addEventListener('blur', () => keep(true));
      setTimeout(() => input.focus(), 0);
    }

    const handle = {
      data: () => ({ version: 1, width: WIDTH, height: HEIGHT, shapes: board.shapes.map((s) => Object.assign({}, s)) }),
      load: (next) => {
        board = boardOf(next);
        past.length = 0;
        future.length = 0;
        redraw();
      },
      paint: (context, width, height) => paint(board, context, width, height),
      dispose: () => {
        state.disposed = true;
        tips.forEach((tip) => { try { tip.dispose(); } catch (_) { /* gone with the board */ } });
      }
    };
    choose({});
    redraw();
    return handle;
  }

  window.WorkbenchWhiteboard = { show: show, svgText: svgText, WIDTH: WIDTH, HEIGHT: HEIGHT, COLORS: COLORS };
  if (typeof module !== 'undefined' && module.exports) module.exports = window.WorkbenchWhiteboard;
})(typeof window !== 'undefined' ? window : globalThis);
