/**
 * @jest-environment jsdom
 */
// An earlier turn's work screen, shown from its card: a banner saying which
// turn it is and that the AI sees the present one, the items of that desk
// tagged, a line for those that changed or are gone, an image still the same
// shown with the marks it had then, and Into Now for what can be brought.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

describe('WorkbenchTurn', () => {
  let box;

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = '<div id="box"></div>';
    box = document.getElementById('box');
    require(js('monadic/workbench-turn.js'));
  });

  const data = {
    status: 'ok', by: 'agent', put_away: 2,
    items: [
      { id: 'i_a', kind: 'file', preview: 'image', name: 'plan.png', place: 'current', by: 'agent', now: 'same',
        marks: [{ id: 'm_aaaaaa', rev: 1, shape: 'ellipse', rect: { x: 0.1, y: 0.2, w: 0.3, h: 0.4 } }] },
      { id: 'i_b', kind: 'file', preview: 'text', name: 'notes.txt', place: 'latest', by: 'user', now: 'changed' },
      { id: 'i_c', kind: 'file', preview: 'pdf', name: 'gone.pdf', place: 'previous', by: 'user', now: 'gone' }
    ],
    assets: { i_a: '/workbench/asset/a' }
  };

  test('says which turn it is and that the AI sees the present work screen, and goes back', () => {
    const back = jest.fn();
    window.WorkbenchTurn.show(box, data, { turn: '3', back });
    expect(box.querySelector('.workbench-turn-title').textContent.trim()).toBe("The work screen at T3 (the AI's reply)");
    expect(box.querySelector('.workbench-turn-note').textContent).toContain('The AI sees the present work screen');
    box.querySelector('.workbench-turn-back').click();
    expect(back).toHaveBeenCalled();
  });

  test('lists the items in their order, tagged, with a line for one changed or gone, and how many were put away', () => {
    window.WorkbenchTurn.show(box, data, { turn: '3' });
    const items = Array.from(box.querySelectorAll('.workbench-turn-item'));
    expect(items.map((n) => n.dataset.item)).toEqual(['i_a', 'i_b', 'i_c']);
    expect(items.map((n) => n.querySelector('.workbench-item-tag').textContent)).toEqual(['AI · Now', 'You · Latest', 'You · Before']);
    expect(items[1].querySelector('.workbench-turn-state').textContent).toContain('Changed since this turn');
    expect(items[2].querySelector('.workbench-turn-state').textContent).toBe('No longer on the work screen.');
    expect(box.querySelector('.workbench-turn-away').textContent).toBe('2 put away then');
  });

  test('shows an image still the same with the marks it had then, lighter, and nothing for others', () => {
    window.WorkbenchTurn.show(box, data, {});
    const img = box.querySelector('.workbench-turn-item[data-item="i_a"] img');
    expect(img.getAttribute('src')).toBe('/workbench/asset/a');
    const mark = box.querySelector('.workbench-turn-item[data-item="i_a"] .workbench-mark-earlier');
    expect(mark.classList.contains('is-ellipse')).toBe(true);
    expect([mark.style.left, mark.style.top, mark.style.width, mark.style.height]).toEqual(['10%', '20%', '30%', '40%']);
    expect(box.querySelector('.workbench-turn-item[data-item="i_b"] img')).toBeNull();
  });

  test('paints what an image had drawn on it then over the image', () => {
    require(js('monadic/workbench-whiteboard.js'));
    const painted = [];
    const getContext = jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => new Proxy({}, {
      get: (_t, name) => (...args) => { painted.push(String(name)); return { width: 10 }; }, set: () => true
    }));
    try {
      const drawnData = Object.assign({}, data, { items: [Object.assign({}, data.items[0],
        { drawing: { digests: ['d'.repeat(64)], shapes: [{ id: 's1', type: 'rect', x: 10, y: 10, w: 100, h: 50 }] } })] });
      window.WorkbenchTurn.show(box, drawnData, {});
      const img = box.querySelector('.workbench-turn-item img');
      Object.defineProperty(img, 'naturalWidth', { value: 300 });
      Object.defineProperty(img, 'naturalHeight', { value: 400 });
      img.dispatchEvent(new Event('load'));
      const canvas = box.querySelector('.workbench-turn-drawing');
      expect([canvas.width, canvas.height]).toEqual([300, 400]);
      expect(painted).toContain('rect');
    } finally {
      getContext.mockRestore();
      delete window.WorkbenchWhiteboard;
    }
  });

  test('brings into Now only what can be, never what is gone', () => {
    const bring = jest.fn();
    window.WorkbenchTurn.show(box, data, { bring, canBring: (id) => id !== 'i_b' });
    const button = (id) => box.querySelector(`.workbench-turn-item[data-item="${id}"] .workbench-turn-bring`);
    expect([button('i_a').disabled, button('i_b').disabled, button('i_c').disabled]).toEqual([false, true, true]);
    button('i_a').click();
    button('i_c').click();
    expect(bring.mock.calls).toEqual([['i_a']]);
  });

  test('says when the turn was not recorded, or held nothing', () => {
    window.WorkbenchTurn.show(box, { status: 'none', by: 'user' }, {});
    expect(box.querySelector('.workbench-turn-none').textContent).toBe('The work screen of this turn was not recorded.');
    window.WorkbenchTurn.show(box, { status: 'ok', by: 'user', items: [] }, {});
    expect(box.querySelector('.workbench-turn-none').textContent).toBe('Nothing was on the desk.');
  });
});
