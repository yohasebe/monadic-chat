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

  afterEach(() => { if (box) box.remove(); box = null; });

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
    expect(stroke).toMatchObject({ type: 'pen', by: 'user', color: 'black', stroke: 4 });
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
