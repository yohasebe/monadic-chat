/**
 * @jest-environment jsdom
 */
// A whiteboard on the work screen: shapes drawn with the tools, kept as the
// file keeps them, undone and redone, and painted for the AI's look.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

beforeAll(() => {
  require(js('monadic/workbench-pointer.js'));
  require(js('monadic/workbench-whiteboard.js'));
});

describe('WorkbenchWhiteboard', () => {
  let box;
  let changes;
  let board;

  // The board on screen: 800 × 500 from the top left of the window.
  function show(data) {
    box = document.createElement('div');
    document.body.appendChild(box);
    changes = [];
    board = window.WorkbenchWhiteboard.show(box, data, { onChange: (d) => changes.push(d) });
    box.querySelector('svg').getBoundingClientRect = () => ({ left: 0, top: 0, width: 800, height: 500 });
    return board;
  }

  afterEach(() => {
    if (box) box.remove();
    box = null;
    window.localStorage.clear();
  });

  const svgEl = () => box.querySelector('svg');
  function pointer(type, x, y) {
    const e = new MouseEvent(type, { clientX: x, clientY: y, button: 0, bubbles: true });
    svgEl().dispatchEvent(e);
  }
  function tool(name) { box.querySelector(`[data-tool="${name}"]`).click(); }

  test('draws the shapes it is given, and gives them back as they are kept', () => {
    show({ shapes: [{ id: 'a', type: 'rect', x: 10, y: 20, w: 100, h: 50, color: 'red', stroke: 4 },
      { id: 'b', type: 'text', x: 5, y: 5, text: 'Plan\nB', size: 32, color: 'blue' }] });
    expect(box.querySelectorAll('.workbench-whiteboard-shape')).toHaveLength(2);
    expect(box.querySelector('text').textContent).toBe('PlanB');
    expect(board.data().shapes.map((s) => s.id)).toEqual(['a', 'b']);
    expect(board.data()).toMatchObject({ version: 1, width: 1600, height: 1000 });
  });

  test('draws a pen stroke on the board in its own units, and tells the change', () => {
    show(null);
    pointer('pointerdown', 100, 50);
    pointer('pointermove', 110, 50);
    pointer('pointermove', 120, 60);
    pointer('pointerup', 120, 60);
    expect(changes).toHaveLength(1);
    const [stroke] = changes[0].shapes;
    expect(stroke).toMatchObject({ type: 'pen', by: 'user', color: 'black', stroke: 6, fill: 'none' });
    // 800 px on screen is 1600 on the board.
    expect(stroke.points).toEqual([[200, 100], [220, 100], [240, 120]]);
  });

  test('draws an arrow and a rectangle by dragging, and nothing for a click', () => {
    show(null);
    tool('arrow');
    pointer('pointerdown', 0, 0);
    pointer('pointermove', 50, 25);
    pointer('pointerup', 50, 25);
    tool('rect');
    pointer('pointerdown', 100, 100);
    pointer('pointermove', 50, 50);
    pointer('pointerup', 50, 50);
    pointer('pointerdown', 300, 300);
    pointer('pointerup', 300, 300);
    const shapes = board.data().shapes;
    expect(shapes.map((s) => s.type)).toEqual(['arrow', 'rect']);
    expect(shapes[0]).toMatchObject({ x1: 0, y1: 0, x2: 100, y2: 50 });
    expect(shapes[1]).toMatchObject({ x: 100, y: 100, w: 100, h: 100 });
  });

  test('takes a text typed where the user clicked, Enter keeping it and Esc letting it go', async () => {
    show(null);
    tool('text');
    pointer('pointerdown', 200, 100);
    let input = box.querySelector('.workbench-whiteboard-input');
    input.value = 'Idea';
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    expect(board.data().shapes[0]).toMatchObject({ type: 'text', text: 'Idea', x: 400, y: 200 });
    pointer('pointerdown', 10, 10);
    input = box.querySelector('.workbench-whiteboard-input');
    input.value = 'gone';
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    expect(board.data().shapes).toHaveLength(1);
    expect(box.querySelector('.workbench-whiteboard-input')).toBeNull();
  });

  test('draws a marker and a filled pen stroke in the color chosen, smoothed', () => {
    show(null);
    box.querySelector('.workbench-whiteboard-color[data-color="peach"]').click();
    box.querySelector('.workbench-whiteboard-stroke[data-stroke="24"]').click();
    box.querySelector('.workbench-whiteboard-fill[data-fill="solid"]').click();
    pointer('pointerdown', 100, 100);
    pointer('pointermove', 150, 100);
    pointer('pointermove', 150, 150);
    pointer('pointerup', 150, 150);
    tool('marker');
    pointer('pointerdown', 10, 10);
    pointer('pointermove', 60, 10);
    pointer('pointerup', 60, 10);
    const [pen, marker] = board.data().shapes;
    expect(pen).toMatchObject({ type: 'pen', color: 'peach', stroke: 24, fill: 'solid' });
    expect(marker).toMatchObject({ type: 'marker', color: 'peach', stroke: 24 });
    expect(marker).not.toHaveProperty('fill');
    const [penEl, markerEl] = box.querySelectorAll('.workbench-whiteboard-shape');
    expect(penEl.getAttribute('d')).toMatch(/^M200 200 Q300 200 300 250 L300 300 Z$/);
    expect(penEl.getAttribute('fill')).toBe('#f2c29b');
    expect(penEl.getAttribute('fill-opacity')).toBe('1');
    expect(markerEl.getAttribute('stroke-width')).toBe('72');
    expect(markerEl.getAttribute('opacity')).toBe('0.35');
  });

  test('opens the colors, sizes and fills from buttons showing what is chosen, one at a time', () => {
    show(null);
    const button = (name) => box.querySelector(`.workbench-whiteboard-${name}`);
    const menu = (name) => box.querySelector(`.workbench-whiteboard-${name}-menu`);
    expect(menu('colors').hidden).toBe(true);
    button('colors').click();
    expect(menu('colors').hidden).toBe(false);
    expect(button('colors').getAttribute('aria-expanded')).toBe('true');
    button('strokes').click();
    expect(menu('colors').hidden).toBe(true);
    expect(menu('strokes').hidden).toBe(false);
    menu('strokes').querySelector('[data-stroke="12"]').click();
    expect(menu('strokes').hidden).toBe(true);
    expect(button('strokes').querySelector('.workbench-whiteboard-stroke-dot').style.width).toBe('10px');
    button('colors').click();
    menu('colors').querySelector('[data-color="teal"]').click();
    expect(menu('colors').hidden).toBe(true);
    expect(button('colors').querySelector('.workbench-whiteboard-color-face').getAttribute('style')).toContain('#2a9d8f');
    button('fills').click();
    menu('fills').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    expect(menu('fills').hidden).toBe(true);
    button('fills').click();
    document.body.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
    expect(menu('fills').hidden).toBe(true);
  });

  test('shows a grid the ends of shapes and texts keep to, and remembers it', () => {
    show(null);
    const grid = box.querySelector('.workbench-whiteboard-grid');
    const lines = box.querySelector('.workbench-whiteboard-gridlines');
    expect(lines.style.display).toBe('none');
    grid.click();
    expect(lines.style.display).toBe('');
    expect(grid.getAttribute('aria-pressed')).toBe('true');
    tool('rect');
    pointer('pointerdown', 21, 19);
    pointer('pointermove', 50, 49);
    pointer('pointerup', 50, 49);
    // Near is 8 px on screen, 16 on this board. 42, 38 is near the line at
    // 40 and taken to it; 100, 98 is not near one (18 from 80 and 120) and
    // stays.
    expect(board.data().shapes[0]).toMatchObject({ x: 40, y: 40, w: 60, h: 58 });
    tool('line');
    svgEl().dispatchEvent(new MouseEvent('pointerdown', { clientX: 21, clientY: 19, button: 0, altKey: true, bubbles: true }));
    svgEl().dispatchEvent(new MouseEvent('pointermove', { clientX: 60, clientY: 60, button: 0, altKey: true, bubbles: true }));
    svgEl().dispatchEvent(new MouseEvent('pointerup', { clientX: 60, clientY: 60, button: 0, altKey: true, bubbles: true }));
    // With Alt held, nothing is drawn to the grid.
    expect(board.data().shapes[1]).toMatchObject({ x1: 42, y1: 38, x2: 120, y2: 120 });
    board.data().shapes.pop();
    tool('pen');
    pointer('pointerdown', 11, 9);
    pointer('pointermove', 52, 48);
    pointer('pointerup', 52, 48);
    expect(board.data().shapes[2].points[0]).toEqual([22, 18]);
    box.remove();
    show(null);
    expect(box.querySelector('.workbench-whiteboard-gridlines').style.display).toBe('');
  });

  describe('the select tool', () => {
    // A press, a drag and a let-go at the places given (on the element
    // pressed, else on the board).
    function drag(from, to, target) {
      (target || svgEl()).dispatchEvent(new MouseEvent('pointerdown', { clientX: from[0], clientY: from[1], button: 0, bubbles: true }));
      pointer('pointermove', to[0], to[1]);
      pointer('pointerup', to[0], to[1]);
    }
    const rect = { id: 'r', type: 'rect', x: 100, y: 100, w: 200, h: 100, color: 'black', stroke: 6, fill: 'none' };

    test('chooses a shape by its stroke or by its box, and moves it as one change', () => {
      show({ shapes: [rect, { id: 'l', type: 'line', x1: 1000, y1: 500, x2: 1200, y2: 500, stroke: 6 }] });
      tool('select');
      // Inside the rectangle (not on its stroke): chosen by its box.
      drag([100, 75], [125, 100]);
      expect(board.data().shapes[0]).toMatchObject({ x: 150, y: 150, w: 200, h: 100 });
      expect(box.querySelectorAll('.workbench-whiteboard-handle')).toHaveLength(8);
      expect(changes).toHaveLength(1);
      box.querySelector('.workbench-whiteboard-undo').click();
      expect(board.data().shapes[0]).toMatchObject({ x: 100, y: 100 });
      drag([550, 250], [550, 300], box.querySelector('[data-id="l"]'));
      expect(board.data().shapes[1]).toMatchObject({ x1: 1000, y1: 600, x2: 1200, y2: 600 });
    });

    test('resizes the chosen shape by a handle, its stroke and points scaled with it', () => {
      show({ shapes: [rect, { id: 'p', type: 'pen', points: [[400, 400], [600, 500]], stroke: 6 }] });
      tool('select');
      drag([100, 75], [100, 75]);
      // The right handle: the right side 100 further (50 on screen).
      drag([0, 0], [50, 0], box.querySelector('.workbench-whiteboard-handle[data-handle="e"]'));
      expect(board.data().shapes[0]).toMatchObject({ x: 100, y: 100, w: 300, h: 100 });
      drag([250, 225], [250, 225]);
      drag([0, 0], [-50, -25], box.querySelector('.workbench-whiteboard-handle[data-handle="nw"]'));
      expect(board.data().shapes[1].points).toEqual([[300, 350], [600, 500]]);
    });

    test('keeps a moved shape on the board, and draws its edges to the grid when near', () => {
      show({ shapes: [rect] });
      box.querySelector('.workbench-whiteboard-grid').click();
      tool('select');
      drag([100, 75], [-500, 82.5]);
      expect(board.data().shapes[0]).toMatchObject({ x: 0, y: 120 });
      // Moved down by 18: the top (138) is near no line, the bottom (238) is
      // 2 from 240, so the shape goes where its bottom is on that line.
      tool('select');
      drag([100, 85], [100, 94]);
      expect(board.data().shapes[0].y).toBe(140);
    });

    test('restyles, nudges and deletes the chosen shape, and lets it go with Esc', () => {
      show({ shapes: [rect, { id: 't', type: 'text', x: 600, y: 600, text: 'Hi', size: 20 }] });
      tool('select');
      drag([100, 75], [100, 75]);
      box.querySelector('.workbench-whiteboard-color[data-color="navy"]').click();
      box.querySelector('.workbench-whiteboard-fill[data-fill="light"]').click();
      expect(board.data().shapes[0]).toMatchObject({ color: 'navy', fill: 'light' });
      const key = (k, extra) => svgEl().dispatchEvent(new KeyboardEvent('keydown', Object.assign({ key: k, bubbles: true }, extra)));
      key('ArrowRight', { shiftKey: true });
      expect(board.data().shapes[0].x).toBe(110);
      key('Delete');
      expect(board.data().shapes.map((s) => s.id)).toEqual(['t']);
      drag([305, 305], [305, 305]);
      // A text is moved and restyled, not resized.
      expect(box.querySelectorAll('.workbench-whiteboard-handle')).toHaveLength(0);
      box.querySelector('.workbench-whiteboard-stroke[data-stroke="24"]').click();
      expect(board.data().shapes[0]).toMatchObject({ size: 72 });
      key('Escape');
      expect(box.querySelector('.workbench-whiteboard-selection')).toBeNull();
      tool('pen');
      expect(box.querySelector('.workbench-whiteboard-selection')).toBeNull();
    });
  });

  describe('boxes with a text, and arrows joining them', () => {
    const boxes = [
      { id: 'a', type: 'rect', x: 100, y: 100, w: 200, h: 100, text: 'Order', size: 20, color: 'blue', stroke: 6 },
      { id: 'b', type: 'ellipse', x: 600, y: 100, w: 200, h: 100, text: 'Ship\nit', size: 20, color: 'red', stroke: 6,
        fill: 'solid' },
      { id: 'j', type: 'arrow', x1: 200, y1: 150, x2: 700, y2: 150, from: 'a', to: 'b', stroke: 6 }
    ];

    test('writes a shape\'s text in its middle, light on a dark solid fill', () => {
      show({ shapes: boxes });
      const [a, b] = box.querySelectorAll('.workbench-whiteboard-shape');
      const text = a.querySelector('text');
      expect(text.getAttribute('text-anchor')).toBe('middle');
      expect(text.querySelector('tspan').getAttribute('x')).toBe('200');
      expect(text.querySelector('tspan').getAttribute('y')).toBe('150');
      expect(text.getAttribute('fill')).toBe('#2f6fd0');
      expect([...b.querySelectorAll('tspan')].map((t) => t.getAttribute('y'))).toEqual(['137.5', '162.5']);
      expect(b.querySelector('text').getAttribute('fill')).toBe('#ffffff');
    });

    test('draws a joining arrow between the edges of its shapes, and keeps it there as they move', () => {
      show({ shapes: boxes });
      const line = () => box.querySelector('[data-id="j"] line');
      // From the rectangle's right edge (300) and the ellipse's left (600),
      // each 3 + 6 away.
      expect([line().getAttribute('x1'), line().getAttribute('x2')]).toEqual(['309', '591']);
      tool('select');
      const rect = box.querySelector('[data-id="a"]');
      rect.dispatchEvent(new MouseEvent('pointerdown', { clientX: 100, clientY: 75, button: 0, bubbles: true }));
      pointer('pointermove', 100, 175);
      pointer('pointerup', 100, 175);
      expect(board.data().shapes[0]).toMatchObject({ y: 300 });
      expect(Number(line().getAttribute('y1'))).toBeGreaterThan(150);
      expect(board.data().shapes[2]).toMatchObject({ from: 'a', to: 'b' });
    });

    test('lets an arrow moved by itself go of the shapes it joined', () => {
      show({ shapes: boxes });
      tool('select');
      const arrow = box.querySelector('[data-id="j"] line');
      arrow.dispatchEvent(new MouseEvent('pointerdown', { clientX: 225, clientY: 75, button: 0, bubbles: true }));
      pointer('pointermove', 225, 100);
      pointer('pointerup', 225, 100);
      const moved = board.data().shapes[2];
      expect(moved).not.toHaveProperty('from');
      expect(moved).toMatchObject({ x1: 309, y1: 200, x2: 591, y2: 200 });
    });

    test('writes a box\'s text again on a double click, and takes it off when left empty', () => {
      show({ shapes: boxes });
      tool('select');
      const twice = () => box.querySelector('[data-id="a"]')
        .dispatchEvent(new MouseEvent('dblclick', { clientX: 100, clientY: 75, bubbles: true }));
      twice();
      let input = box.querySelector('.workbench-whiteboard-input');
      expect(input.value).toBe('Order');
      input.value = 'Order\nreceived';
      input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
      expect(board.data().shapes[0]).toMatchObject({ text: 'Order\nreceived', size: 20 });
      twice();
      input = box.querySelector('.workbench-whiteboard-input');
      input.value = '';
      input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
      expect(board.data().shapes[0]).not.toHaveProperty('text');
    });

    test('paints the boxes\' texts in their middles, and the arrow at the edges', () => {
      show({ shapes: boxes });
      const calls = [];
      const context = new Proxy({}, {
        get: (_, name) => (typeof name === 'string' && !['fillStyle', 'strokeStyle', 'lineWidth', 'font', 'textBaseline',
          'textAlign', 'lineCap', 'lineJoin', 'globalAlpha'].includes(name) ? (...args) => calls.push([name, ...args]) : undefined),
        set: () => true
      });
      board.paint(context, 1600, 1000);
      expect(calls).toContainEqual(['fillText', 'Order', 200, 150]);
      expect(calls).toContainEqual(['fillText', 'it', 700, 162.5]);
      expect(calls).toContainEqual(['moveTo', 309, 150]);
    });
  });

  test('zooms the view only: the board, its shapes and where a press lands on them stay', () => {
    show({ shapes: [{ id: 'a', type: 'rect', x: 100, y: 100, w: 200, h: 100 }] });
    const sheet = box.querySelector('.workbench-whiteboard-sheet');
    const level = box.querySelector('.workbench-whiteboard-zoom-level');
    const zoomIn = box.querySelector('.workbench-whiteboard-zoom-in');
    expect(level.textContent).toBe('100%');
    expect(box.querySelector('.workbench-whiteboard-zoom-out').disabled).toBe(true);
    zoomIn.click();
    zoomIn.click();
    expect(level.textContent).toBe('150%');
    expect(svgEl().style.width).toBe('150%');
    expect(sheet.dataset.zoomed).toBe('true');
    // Shown 1.5 times as large: a press at 300, 150 on screen is at 400, 200
    // on the board.
    svgEl().getBoundingClientRect = () => ({ left: 0, top: 0, width: 1200, height: 750 });
    pointer('pointerdown', 300, 150);
    pointer('pointermove', 330, 150);
    pointer('pointerup', 330, 150);
    expect(board.data().shapes[1].points[0]).toEqual([400, 200]);
    sheet.dispatchEvent(new WheelEvent('wheel', { deltaY: -500, ctrlKey: true, bubbles: true, cancelable: true }));
    expect(level.textContent).toBe('300%');
    expect(zoomIn.disabled).toBe(true);
    level.click();
    expect(level.textContent).toBe('100%');
    expect(sheet.dataset.zoomed).toBe('false');
    expect(board.data().shapes[0]).toMatchObject({ x: 100, y: 100, w: 200, h: 100 });
  });

  // The shared setup's Blob is a stand-in and jsdom has no TextEncoder:
  // Node's own are used where a file is made.
  function withNodeBlob(run) {
    const blob = global.Blob;
    const encoder = global.TextEncoder;
    global.Blob = require('buffer').Blob;
    global.TextEncoder = require('util').TextEncoder;
    return Promise.resolve().then(run).finally(() => {
      global.Blob = blob;
      global.TextEncoder = encoder;
    });
  }

  test('writes the board out as an SVG named after it', () => withNodeBlob(async () => {
    const stand = global.XMLSerializer;
    global.XMLSerializer = function Serializer() { this.serializeToString = (node) => node.outerHTML; };
    const saved = [];
    try {
      box = document.createElement('div');
      document.body.appendChild(box);
      window.WorkbenchWhiteboard.show(box, { shapes: [{ id: 'a', type: 'text', x: 5, y: 5, text: 'Plan', size: 20 }] },
        { name: 'whiteboard-2.wb.json', save: (blob, name) => saved.push([blob, name]) }).exportAs('svg');
    } finally {
      global.XMLSerializer = stand;
    }
    expect(saved).toHaveLength(1);
    const [blob, name] = saved[0];
    expect(name).toBe('whiteboard-2.svg');
    expect(blob.type).toBe('image/svg+xml');
    const text = await blob.text();
    expect(text.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true);
    expect(text).toContain('Plan');
  }));

  test('makes a PDF of one page holding the picture, every offset where it says', () => withNodeBlob(async () => {
    // The shared setup's Uint8Array is a stand-in: Node's Buffer is one.
    const jpeg = require('buffer').Buffer.from([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]);
    // Read with Node's Buffer: the Blob's bytes are Node's, not the page's.
    const bytes = require('buffer').Buffer.from(await window.WorkbenchWhiteboard.pdfOf(jpeg, 3200, 2000).arrayBuffer());
    const text = bytes.toString('latin1');
    expect(text.startsWith('%PDF-1.4')).toBe(true);
    expect(text).toContain('/MediaBox [0 0 800 500]');
    expect(text).toContain('/Width 3200 /Height 2000');
    expect(text).toContain(`/Length ${jpeg.length}`);
    const xref = Number(text.match(/startxref\n(\d+)/)[1]);
    expect(text.slice(xref, xref + 4)).toBe('xref');
    const offsets = [...text.slice(xref).matchAll(/^(\d{10}) 00000 n $/gm)].map((m) => Number(m[1]));
    expect(offsets).toHaveLength(5);
    offsets.forEach((offset, i) => expect(text.slice(offset, offset + 8)).toBe(`${i + 1} 0 obj\n`));
    const start = text.indexOf('stream\n') + 7;
    expect([...bytes.subarray(start, start + jpeg.length)]).toEqual([...jpeg]);
  }));

  test('undoes and redoes, and clears the board as one change', () => {
    show({ shapes: [{ id: 'a', type: 'line', x1: 0, y1: 0, x2: 10, y2: 10 }] });
    box.querySelector('.workbench-whiteboard-clear').click();
    expect(board.data().shapes).toHaveLength(0);
    box.querySelector('.workbench-whiteboard-undo').click();
    expect(board.data().shapes).toHaveLength(1);
    box.querySelector('.workbench-whiteboard-redo').click();
    expect(board.data().shapes).toHaveLength(0);
    expect(changes).toHaveLength(3);
  });

  test('erases the shape under the pointer', () => {
    show({ shapes: [{ id: 'a', type: 'rect', x: 0, y: 0, w: 100, h: 100 }, { id: 'b', type: 'rect', x: 500, y: 500, w: 10, h: 10 }] });
    tool('eraser');
    const target = box.querySelector('[data-id="a"]');
    document.elementFromPoint = () => target;
    pointer('pointerdown', 5, 5);
    pointer('pointerup', 5, 5);
    expect(board.data().shapes.map((s) => s.id)).toEqual(['b']);
    delete document.elementFromPoint;
  });

  test('paints the board on a canvas, white under its shapes', () => {
    show({ shapes: [{ id: 'a', type: 'text', x: 5, y: 5, text: 'Hi\nthere', size: 20 },
      { id: 'b', type: 'arrow', x1: 0, y1: 0, x2: 100, y2: 0 }] });
    const calls = [];
    const context = new Proxy({}, {
      get: (_, name) => (typeof name === 'string' && !['fillStyle', 'strokeStyle', 'lineWidth', 'font', 'textBaseline',
        'lineCap', 'lineJoin', 'globalAlpha'].includes(name) ? (...args) => calls.push([name, ...args]) : undefined),
      set: () => true
    });
    board.paint(context, 800, 500);
    expect(calls[0]).toEqual(['save']);
    expect(calls).toContainEqual(['fillRect', 0, 0, 800, 500]);
    expect(calls).toContainEqual(['scale', 0.5, 0.5]);
    expect(calls.filter((c) => c[0] === 'fillText').map((c) => c[1])).toEqual(['Hi', 'there']);
    expect(calls.filter((c) => c[0] === 'closePath')).toHaveLength(1);
  });

  test('gives the board as an SVG to show, its texts as text and nothing that runs', () => {
    // The shared setup's stand-in serializes nothing: the element's markup
    // stands in for it here.
    const stand = global.XMLSerializer;
    global.XMLSerializer = function Serializer() { this.serializeToString = (node) => node.outerHTML; };
    let text;
    try {
      text = window.WorkbenchWhiteboard.svgText({ shapes: [{ id: 'a', type: 'text', x: 5, y: 5, text: '<script>x</script>' },
        { id: 'b', type: 'ellipse', x: 0, y: 0, w: 10, h: 10 }] });
    } finally {
      global.XMLSerializer = stand;
    }
    const doc = new DOMParser().parseFromString(text, 'image/svg+xml');
    expect(doc.documentElement.getAttribute('viewBox')).toBe('0 0 1600 1000');
    expect(doc.querySelector('script')).toBeNull();
    expect(doc.querySelector('text').textContent).toBe('<script>x</script>');
    expect(doc.querySelectorAll('ellipse')).toHaveLength(1);
  });

  test('loads another board in place, letting go of what could be undone', () => {
    show({ shapes: [] });
    tool('rect');
    pointer('pointerdown', 0, 0);
    pointer('pointermove', 50, 50);
    pointer('pointerup', 50, 50);
    board.load({ shapes: [{ id: 'z', type: 'line', x1: 0, y1: 0, x2: 1, y2: 1 }] });
    expect(board.data().shapes.map((s) => s.id)).toEqual(['z']);
    expect(box.querySelector('.workbench-whiteboard-undo').disabled).toBe(true);
  });
});
