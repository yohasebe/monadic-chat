/**
 * A whiteboard on the work screen: shapes on a board of WIDTH × HEIGHT (a
 * pen's and a marker's strokes, lines, arrows, rectangles, ellipses and
 * texts), drawn as SVG and edited with the tools in its bar. A shape
 * chosen with the select tool can be moved, resized (but a text), restyled
 * and deleted. A grid can be shown on it; the ends of lines and shapes, the
 * place of a text and the edges of a shape moved or resized are then drawn
 * to its lines when near them (not while Alt is held). What it holds is the same as
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
    black: '#222222', red: '#d04848', orange: '#e08a2e', yellow: '#f2c230', lime: '#9ccc3c',
    green: '#3c9a5f', sky: '#5bb8e8', blue: '#2f6fd0', violet: '#8c6ed2', pink: '#f08cb4',
    white: '#ffffff', silver: '#c8c8c8', gray: '#808080', brown: '#8b5a2b', peach: '#f2c29b',
    olive: '#7a7f2a', teal: '#2a9d8f', navy: '#1f3a7a', purple: '#6a3d9a', magenta: '#c2409a'
  };
  // A width or size is taken as the nearest of these.
  const STROKES = [3, 6, 12, 24];
  const SIZES = [20, 32, 48, 72];
  const FILLS = ['none', 'light', 'solid'];
  // How light a light fill is; a marker's width (times its stroke's) and
  // how light it is.
  const LIGHT = 0.2;
  const MARKER_WIDTH = 3;
  const MARKER_ALPHA = 0.35;
  const GRID = 40;
  // How near a grid line (on screen, in pixels) a point is drawn to it.
  const SNAP_PX = 8;
  // The margin around a chosen shape, and the size of its handles.
  const PAD = 8;
  const HANDLE = 14;
  const HANDLES = [['nw', 0, 0], ['n', 0.5, 0], ['ne', 1, 0], ['e', 1, 0.5], ['se', 1, 1], ['s', 0.5, 1], ['sw', 0, 1],
    ['w', 0, 0.5]];
  const GRID_KEY = 'monadic-whiteboard-grid';
  const TOOLS = [
    ['select', 'fa-solid fa-arrow-pointer', 'Select'],
    ['pen', 'fa-solid fa-pen', 'Pen'],
    ['marker', 'fa-solid fa-highlighter', 'Marker'],
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
  const nearest = (value, choices, fallback) => (typeof value === 'number' && Number.isFinite(value)
    ? choices.reduce((best, c) => (Math.abs(c - value) < Math.abs(best - value) ? c : best)) : fallback);
  const widthOf = (shape) => nearest(shape.stroke, STROKES, STROKES[1]) * (shape.type === 'marker' ? MARKER_WIDTH : 1);
  const sizeOf = (shape) => nearest(shape.size, SIZES, SIZES[0]);
  const fillOf = (shape) => (shape.fill === true ? 'light' : FILLS.includes(shape.fill) ? shape.fill : 'none');
  const fillAlpha = (shape) => (fillOf(shape) === 'solid' ? 1 : LIGHT);
  const textLines = (shape) => String(shape.text || '').split('\n');

  function emptyBoard() {
    return { version: 1, width: WIDTH, height: HEIGHT, shapes: [] };
  }

  // The board taken from data as far as it is one (the server keeps it so).
  function boardOf(data) {
    const shapes = data && Array.isArray(data.shapes) ? data.shapes.filter((s) => s && typeof s === 'object' && s.id) : [];
    return { version: 1, width: WIDTH, height: HEIGHT, shapes: shapes.map((s) => Object.assign({}, s)) };
  }

  // ---- where a shape is -----------------------------------------------

  // The box a shape takes on the board, { x, y, w, h } (a text's by the
  // number of its characters and lines, roughly).
  function bounds(shape) {
    const box = (xs, ys) => {
      if (xs.length === 0) return { x: 0, y: 0, w: 0, h: 0 };
      const x = Math.min(...xs);
      const y = Math.min(...ys);
      return { x: x, y: y, w: Math.max(...xs) - x, h: Math.max(...ys) - y };
    };
    switch (shape.type) {
      case 'pen':
      case 'marker': {
        const points = shape.points || [];
        return box(points.map((p) => p[0]), points.map((p) => p[1]));
      }
      case 'line':
      case 'arrow':
        return box([shape.x1, shape.x2], [shape.y1, shape.y2]);
      case 'text': {
        const size = sizeOf(shape);
        const lines = textLines(shape);
        return { x: shape.x, y: shape.y, w: Math.max(...lines.map((l) => l.length)) * size * 0.6, h: lines.length * size * 1.25 };
      }
      default:
        return { x: shape.x, y: shape.y, w: shape.w, h: shape.h };
    }
  }

  // The shape taken from the box from to the box to (moved, and scaled on
  // each side that has a size; a text only moved).
  function fitted(shape, from, to) {
    const sx = from.w > 0 ? to.w / from.w : 1;
    const sy = from.h > 0 ? to.h / from.h : 1;
    const mx = (v) => round(to.x + (v - from.x) * sx);
    const my = (v) => round(to.y + (v - from.y) * sy);
    const out = Object.assign({}, shape);
    switch (shape.type) {
      case 'pen':
      case 'marker':
        out.points = (shape.points || []).map((p) => [mx(p[0]), my(p[1])]);
        break;
      case 'line':
      case 'arrow':
        Object.assign(out, { x1: mx(shape.x1), y1: my(shape.y1), x2: mx(shape.x2), y2: my(shape.y2) });
        break;
      case 'text':
        Object.assign(out, { x: mx(shape.x), y: my(shape.y) });
        break;
      default:
        Object.assign(out, { x: mx(shape.x), y: my(shape.y), w: round(shape.w * sx), h: round(shape.h * sy) });
    }
    return out;
  }

  // ---- drawing a shape ------------------------------------------------

  // A stroke through points, smoothed: a curve through the middles of its
  // steps, as [command, ...numbers] (M, Q, L), the same for SVG and canvas.
  function curve(points) {
    if (points.length < 3) return points.map((p, i) => [i === 0 ? 'M' : 'L', p[0], p[1]]);
    const out = [['M', points[0][0], points[0][1]]];
    for (let i = 1; i < points.length - 1; i += 1) {
      const [p, n] = [points[i], points[i + 1]];
      out.push(['Q', p[0], p[1], round((p[0] + n[0]) / 2), round((p[1] + n[1]) / 2)]);
    }
    const last = points[points.length - 1];
    out.push(['L', last[0], last[1]]);
    return out;
  }

  function trace(context, steps) {
    steps.forEach(([command, ...n]) => {
      if (command === 'M') context.moveTo(n[0], n[1]);
      else if (command === 'L') context.lineTo(n[0], n[1]);
      else context.quadraticCurveTo(n[0], n[1], n[2], n[3]);
    });
  }

  // The SVG element of a shape (its id in data-id).
  function shapeElement(shape) {
    const stroke = color(shape);
    const width = widthOf(shape);
    let el;
    switch (shape.type) {
      case 'pen':
      case 'marker': {
        const points = shape.points || [];
        const filled = shape.type === 'pen' && fillOf(shape) !== 'none' && points.length > 2;
        if (points.length === 1) {
          el = svg('circle', { cx: points[0][0], cy: points[0][1], r: width / 2, fill: stroke });
        } else {
          const d = curve(points).map(([command, ...n]) => command + n.join(' ')).join(' ') + (filled ? ' Z' : '');
          el = svg('path', { d: d, fill: filled ? stroke : 'none', stroke: stroke, 'stroke-width': width,
            'stroke-linecap': 'round', 'stroke-linejoin': 'round' });
          if (filled) el.setAttribute('fill-opacity', String(fillAlpha(shape)));
        }
        if (shape.type === 'marker') el.setAttribute('opacity', String(MARKER_ALPHA));
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
        el.setAttribute('fill', fillOf(shape) !== 'none' ? stroke : 'none');
        if (fillOf(shape) !== 'none') el.setAttribute('fill-opacity', String(fillAlpha(shape)));
        break;
      case 'text': {
        const size = sizeOf(shape);
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
      const lineWidth = widthOf(shape);
      context.strokeStyle = stroke;
      context.fillStyle = stroke;
      context.lineWidth = lineWidth;
      context.globalAlpha = shape.type === 'marker' ? MARKER_ALPHA : 1;
      context.beginPath();
      switch (shape.type) {
        case 'pen':
        case 'marker': {
          const points = shape.points || [];
          if (points.length === 1) {
            context.arc(points[0][0], points[0][1], lineWidth / 2, 0, Math.PI * 2);
            context.fill();
            break;
          }
          trace(context, curve(points));
          if (shape.type === 'pen' && fillOf(shape) !== 'none' && points.length > 2) {
            context.closePath();
            context.globalAlpha = fillAlpha(shape);
            context.fill();
            context.globalAlpha = 1;
          }
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
          if (fillOf(shape) !== 'none') {
            context.globalAlpha = fillAlpha(shape);
            context.fill();
            context.globalAlpha = 1;
          }
          context.stroke();
          break;
        case 'text': {
          const size = sizeOf(shape);
          context.font = `${size}px sans-serif`;
          context.textBaseline = 'top';
          textLines(shape).forEach((line, i) => context.fillText(line, shape.x, shape.y + i * size * 1.25));
          break;
        }
        default:
          break;
      }
    });
    context.globalAlpha = 1;
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

  // What a size and a fill look like on their buttons.
  const strokeDot = (i) => {
    const px = [3, 6, 10, 15][i] || 6;
    return `<span class="workbench-whiteboard-stroke-dot" style="width:${px}px;height:${px}px"></span>`;
  };
  const fillSwatch = (fill) => `<span class="workbench-whiteboard-fill-swatch" data-fill="${FILLS.includes(fill) ? fill : 'none'}"></span>`;

  // Whether the grid was last shown (this browser's choice).
  function gridKept() {
    try { return window.localStorage.getItem(GRID_KEY) === '1'; } catch (_) { return false; }
  }

  function show(box, data, { onChange } = {}) {
    let board = data ? boardOf(data) : emptyBoard();
    const past = [];
    const future = [];
    const state = { tool: 'pen', color: 'black', stroke: STROKES[1], size: SIZES[1], fill: 'none', grid: gridKept(),
      disposed: false };
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
    // A choice that opens from a button showing what is chosen (the color,
    // the size, the fill): one open at a time, closed by a pick, Esc or a
    // press outside it.
    const pickers = [];
    function picker(className, label, options) {
      const wrap = element('div', 'workbench-whiteboard-picker');
      const button = element('button', `btn btn-sm btn-secondary workbench-icon-btn workbench-whiteboard-picker-button ${className}`);
      button.type = 'button';
      button.setAttribute('aria-label', label);
      button.setAttribute('aria-haspopup', 'true');
      button.setAttribute('aria-expanded', 'false');
      button.title = label;
      const face = element('span', 'workbench-whiteboard-face');
      button.append(face, element('i', 'fa-solid fa-caret-down workbench-whiteboard-caret'));
      const menu = element('div', `workbench-whiteboard-menu ${className}-menu`);
      menu.setAttribute('role', 'group');
      menu.setAttribute('aria-label', label);
      menu.hidden = true;
      menu.append(...options);
      wrap.append(button, menu);
      const self = {
        wrap: wrap,
        face: face,
        open: () => {
          pickers.forEach((p) => p !== self && p.close());
          menu.hidden = false;
          button.setAttribute('aria-expanded', 'true');
          document.addEventListener('pointerdown', outside, true);
        },
        close: () => {
          menu.hidden = true;
          button.setAttribute('aria-expanded', 'false');
          document.removeEventListener('pointerdown', outside, true);
        }
      };
      function outside(e) { if (!wrap.contains(e.target)) self.close(); }
      button.addEventListener('click', () => (menu.hidden ? self.open() : self.close()));
      wrap.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape' || menu.hidden) return;
        e.preventDefault();
        self.close();
        button.focus();
      });
      options.forEach((b) => b.addEventListener('click', () => self.close()));
      pickers.push(self);
      return self;
    }

    const swatches = Object.keys(COLORS).map((name) => {
      const b = element('button', 'workbench-whiteboard-color');
      b.type = 'button';
      b.dataset.color = name;
      b.style.setProperty('--wb-color', COLORS[name]);
      const label = t(`ui.workbench.wb_color_${name}`, name);
      b.setAttribute('aria-label', label);
      b.title = label;
      b.addEventListener('click', () => {
        choose({ color: name });
        restyle({ color: name });
      });
      return b;
    });
    const strokes = STROKES.map((width, i) => {
      const b = element('button', 'btn btn-sm btn-secondary workbench-icon-btn workbench-whiteboard-stroke');
      b.type = 'button';
      b.dataset.stroke = String(width);
      b.innerHTML = strokeDot(i);
      const label = t(`ui.workbench.wb_stroke_${i + 1}`, ['Thin', 'Medium', 'Thick', 'Very thick'][i]);
      b.setAttribute('aria-label', label);
      b.title = label;
      b.addEventListener('click', () => {
        choose({ stroke: width, size: SIZES[i] });
        restyle({ stroke: width, size: SIZES[i] });
      });
      return b;
    });
    const fills = FILLS.map((fill) => {
      const b = element('button', 'btn btn-sm btn-secondary workbench-icon-btn workbench-whiteboard-fill');
      b.type = 'button';
      b.dataset.fill = fill;
      b.innerHTML = fillSwatch(fill);
      const label = t(`ui.workbench.wb_fill_${fill}`, { none: 'No fill', light: 'Light fill', solid: 'Solid fill' }[fill]);
      b.setAttribute('aria-label', label);
      b.title = label;
      b.addEventListener('click', () => {
        choose({ fill: fill });
        restyle({ fill: fill });
      });
      return b;
    });
    const colorPicker = picker('workbench-whiteboard-colors', t('ui.workbench.wb_colors', 'Color'), swatches);
    const strokePicker = picker('workbench-whiteboard-strokes', t('ui.workbench.wb_strokes', 'Size'), strokes);
    const fillPicker = picker('workbench-whiteboard-fills', t('ui.workbench.wb_fills', 'Fill'), fills);
    const grid = control('workbench-whiteboard-grid', t('ui.workbench.wb_grid', 'Grid'), 'fa-solid fa-border-all');
    grid.addEventListener('click', () => {
      choose({ grid: !state.grid });
      try { window.localStorage.setItem(GRID_KEY, state.grid ? '1' : '0'); } catch (_) { /* kept for this board only */ }
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
      group(t('ui.workbench.wb_style', 'Color, size and fill'), colorPicker.wrap, strokePicker.wrap, fillPicker.wrap),
      group(t('ui.workbench.wb_grid', 'Grid'), grid),
      group(t('ui.workbench.wb_history', 'Undo and redo'), undo, redo, clear));

    const sheet = element('div', 'workbench-whiteboard-sheet');
    const canvas = svg('svg', { viewBox: `0 0 ${WIDTH} ${HEIGHT}`, class: 'workbench-whiteboard-canvas', role: 'img' });
    canvas.setAttribute('aria-label', t('ui.workbench.wb_board', 'Whiteboard'));
    // The grid: its lines over the whole board, each on the very place a
    // point is drawn to, shown when on.
    const lines = [];
    for (let x = GRID; x < WIDTH; x += GRID) lines.push(`M${x} 0V${HEIGHT}`);
    for (let y = GRID; y < HEIGHT; y += GRID) lines.push(`M0 ${y}H${WIDTH}`);
    const gridLayer = svg('path', { d: lines.join(''), fill: 'none', stroke: '#d6dce3', 'stroke-width': 1,
      'vector-effect': 'non-scaling-stroke', class: 'workbench-whiteboard-gridlines', 'pointer-events': 'none' });
    const layer = svg('g');
    const preview = svg('g', { class: 'workbench-whiteboard-preview' });
    const chrome = svg('g', { class: 'workbench-whiteboard-chrome' });
    canvas.setAttribute('tabindex', '0');
    canvas.append(gridLayer, layer, preview, chrome);
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
      fills.forEach((b) => b.classList.toggle('active', b.dataset.fill === state.fill));
      colorPicker.face.innerHTML = `<span class="workbench-whiteboard-color-face" style="--wb-color:${COLORS[state.color]}"></span>`;
      strokePicker.face.innerHTML = strokeDot(STROKES.indexOf(state.stroke));
      fillPicker.face.innerHTML = fillSwatch(state.fill);
      grid.classList.toggle('active', state.grid);
      grid.setAttribute('aria-pressed', state.grid ? 'true' : 'false');
      gridLayer.style.display = state.grid ? '' : 'none';
      sheet.dataset.tool = state.tool;
      if (state.tool !== 'select' && selected) {
        selected = null;
        drawChrome();
      }
    }

    // The shape chosen with the select tool (its id), drawn with a box and
    // its handles over the board.
    let selected = null;
    const chosen = () => board.shapes.find((s) => s.id === selected) || null;

    function drawChrome() {
      const shape = chosen();
      if (!shape) {
        selected = null;
        chrome.replaceChildren();
        return;
      }
      const b = bounds(shape);
      const box = { x: b.x - PAD, y: b.y - PAD, w: b.w + PAD * 2, h: b.h + PAD * 2 };
      const parts = [svg('rect', { x: box.x, y: box.y, width: box.w, height: box.h, class: 'workbench-whiteboard-selection',
        'data-handle': 'move' })];
      if (shape.type !== 'text') {
        HANDLES.forEach(([name, fx, fy]) => parts.push(svg('rect', { x: box.x + box.w * fx - HANDLE / 2,
          y: box.y + box.h * fy - HANDLE / 2, width: HANDLE, height: HANDLE, class: 'workbench-whiteboard-handle',
          'data-handle': name })));
      }
      chrome.replaceChildren(...parts);
    }

    // The chosen shape restyled as the user picked (its color, its width or
    // a text's size, its fill), as one change.
    function restyle(next) {
      const shape = chosen();
      if (!shape) return;
      change(() => {
        if (next.color) shape.color = next.color;
        if (next.stroke) {
          if (shape.type === 'text') shape.size = next.size;
          else shape.stroke = next.stroke;
        }
        if (next.fill && ['pen', 'rect', 'ellipse'].includes(shape.type)) shape.fill = next.fill;
      });
    }

    function redraw() {
      layer.replaceChildren(...board.shapes.map(shapeElement).filter(Boolean));
      drawChrome();
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

    // A change made already (a drag), kept for undo as from before and told.
    function keep(before) {
      past.push(before);
      if (past.length > HISTORY) past.shift();
      future.length = 0;
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

    // A place drawn to the nearest grid line when the grid is shown and it
    // is near one (not while Alt is held); elsewhere it stays as it is.
    const near = (v, e) => {
      if (!state.grid || (e && e.altKey)) return v;
      const rect = canvas.getBoundingClientRect();
      const reach = SNAP_PX * (rect.width > 0 ? WIDTH / rect.width : 1);
      const line = Math.round(v / GRID) * GRID;
      return Math.abs(line - v) <= reach ? line : v;
    };
    const snap = (p, e) => [near(p[0], e), near(p[1], e)];
    // Where a side of size moved to start goes: shifted so that the one of
    // its edges nearer a grid line is on it (as near takes it).
    const align = (start, size, e) => {
      const shifts = [near(start, e) - start, near(start + size, e) - (start + size)].filter((d) => d !== 0);
      return shifts.length === 0 ? start : start + shifts.reduce((a, b) => (Math.abs(b) < Math.abs(a) ? b : a));
    };
    const within = (v, low, high) => Math.min(Math.max(v, low), high);
    const freehand = () => state.tool === 'pen' || state.tool === 'marker';

    let drawing = null;

    function shapeFrom(start, end) {
      const base = { id: newId(), type: state.tool, by: 'user', color: state.color, stroke: state.stroke };
      if (state.tool === 'line' || state.tool === 'arrow') {
        return Object.assign(base, { x1: start[0], y1: start[1], x2: end[0], y2: end[1] });
      }
      return Object.assign(base, { x: Math.min(start[0], end[0]), y: Math.min(start[1], end[1]),
        w: round(Math.abs(end[0] - start[0])), h: round(Math.abs(end[1] - start[1])), fill: state.fill });
    }

    function strokeShape(points, id) {
      const shape = { id: id, type: state.tool, by: 'user', color: state.color, stroke: state.stroke, points: points };
      if (state.tool === 'pen') shape.fill = state.fill;
      return shape;
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
        writeText(snap(at(e), e));
        return;
      }
      if (state.tool === 'select') {
        startSelect(e);
      } else if (state.tool === 'eraser') {
        drawing = { erasing: true };
        eraseAt(e);
      } else {
        const start = freehand() ? at(e) : snap(at(e), e);
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
      if (drawing.select) {
        dragSelect(e);
        return;
      }
      const now = freehand() ? at(e) : snap(at(e), e);
      if (freehand()) {
        const last = drawing.points[drawing.points.length - 1];
        if (Math.hypot(now[0] - last[0], now[1] - last[1]) < STEP) return;
        drawing.points.push(now);
        preview.replaceChildren(shapeElement(strokeShape(drawing.points, 'preview')));
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
      if (done.select) {
        if (done.moved && done.before !== snapshot()) keep(done.before);
        return;
      }
      if (freehand()) {
        const shape = strokeShape(done.points.slice(0, 5000), newId());
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
    // The select tool: a press on a handle resizes the chosen shape, on its
    // box or on a shape moves it (choosing it first), elsewhere lets it go.
    function shapeAt(e, point) {
      const target = e.target && e.target.closest ? e.target.closest('[data-id]') : null;
      if (target && layer.contains(target)) return target.getAttribute('data-id');
      // Else the smallest shape whose box (with a margin) holds the point.
      let best = null;
      board.shapes.forEach((s) => {
        const b = bounds(s);
        const pad = PAD + widthOf(s) / 2;
        if (point[0] < b.x - pad || point[0] > b.x + b.w + pad || point[1] < b.y - pad || point[1] > b.y + b.h + pad) return;
        const area = (b.w + pad * 2) * (b.h + pad * 2);
        if (!best || area <= best.area) best = { id: s.id, area: area };
      });
      return best ? best.id : null;
    }

    function startSelect(e) {
      const point = at(e);
      const grip = e.target && e.target.closest ? e.target.closest('[data-handle]') : null;
      let mode = grip && chrome.contains(grip) ? grip.getAttribute('data-handle') : null;
      if (!mode) {
        selected = shapeAt(e, point);
        mode = 'move';
        drawChrome();
      }
      const shape = chosen();
      if (canvas.focus) canvas.focus({ preventScroll: true });
      if (!shape) return;
      drawing = { select: true, mode: mode, start: point, from: bounds(shape), original: Object.assign({}, shape),
        before: snapshot(), moved: false };
    }

    function dragSelect(e) {
      const d = drawing;
      const now = at(e);
      const dx = now[0] - d.start[0];
      const dy = now[1] - d.start[1];
      const b = d.from;
      let to;
      if (d.mode === 'move') {
        to = { x: within(align(b.x + dx, b.w, e), 0, Math.max(0, WIDTH - b.w)),
          y: within(align(b.y + dy, b.h, e), 0, Math.max(0, HEIGHT - b.h)), w: b.w, h: b.h };
      } else {
        const m = d.mode;
        let left = b.x;
        let right = b.x + b.w;
        let top = b.y;
        let bottom = b.y + b.h;
        if (m.includes('w') && b.w > 0) left = within(near(b.x + dx, e), 0, WIDTH);
        if (m.includes('e') && b.w > 0) right = within(near(b.x + b.w + dx, e), 0, WIDTH);
        if (m.includes('n') && b.h > 0) top = within(near(b.y + dy, e), 0, HEIGHT);
        if (m.includes('s') && b.h > 0) bottom = within(near(b.y + b.h + dy, e), 0, HEIGHT);
        to = { x: Math.min(left, right), y: Math.min(top, bottom), w: Math.abs(right - left), h: Math.abs(bottom - top) };
        if ((b.w > 0 && to.w < 4) || (b.h > 0 && to.h < 4)) return;
      }
      const index = board.shapes.findIndex((s) => s.id === d.original.id);
      if (index < 0) return;
      board.shapes[index] = fitted(d.original, b, to);
      d.moved = d.moved || dx !== 0 || dy !== 0;
      redraw();
    }

    // With a shape chosen: Delete or Backspace removes it, the arrows move
    // it (by 10 with Shift), Esc lets it go.
    canvas.addEventListener('keydown', (e) => {
      const shape = chosen();
      if (!shape || drawing) return;
      const arrows = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
      if (e.key === 'Delete' || e.key === 'Backspace') {
        e.preventDefault();
        change(() => { board.shapes = board.shapes.filter((s) => s.id !== shape.id); });
      } else if (e.key === 'Escape') {
        e.preventDefault();
        selected = null;
        drawChrome();
      } else if (arrows[e.key]) {
        e.preventDefault();
        const by = e.shiftKey ? 10 : 1;
        const b = bounds(shape);
        const to = { x: within(b.x + arrows[e.key][0] * by, 0, Math.max(0, WIDTH - b.w)),
          y: within(b.y + arrows[e.key][1] * by, 0, Math.max(0, HEIGHT - b.h)), w: b.w, h: b.h };
        change(() => {
          const index = board.shapes.findIndex((s) => s.id === shape.id);
          board.shapes[index] = fitted(shape, b, to);
        });
      }
    });

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
      input.style.fontSize = `${(state.size / HEIGHT) * rect.height}px`;
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
        selected = null;
        past.length = 0;
        future.length = 0;
        redraw();
      },
      paint: (context, width, height) => paint(board, context, width, height),
      dispose: () => {
        state.disposed = true;
        pickers.forEach((p) => p.close());
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
