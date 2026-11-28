/**
 * @jest-environment jsdom
 */
// The work screen's present desk: Now and Latest in one panel, and a drawer
// of what was put away, folded by hand and narrowed by name.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

describe('WorkbenchPlaces', () => {
  let container;

  beforeEach(() => {
    jest.resetModules();
    window.localStorage.clear();
    document.body.innerHTML = '<div id="view"></div>';
    container = document.getElementById('view');
    require(js('monadic/workbench-places.js'));
  });

  const row = (name) => {
    const node = document.createElement('div');
    node.className = 'workbench-stash-row';
    const span = document.createElement('span');
    span.className = 'workbench-stash-name';
    span.textContent = name;
    node.appendChild(span);
    return node;
  };

  test('makes the desk and the drawer, each a panel with a head and a body of its own', () => {
    const places = window.WorkbenchPlaces.build(container);
    expect(Array.from(container.querySelectorAll('.workbench-place')).map((n) => n.dataset.place)).toEqual(['desk', 'stash']);
    expect(places.regions.desk.title.textContent.trim()).toBe('On the desk');
    expect(places.regions.stash.title.textContent.trim()).toBe('Put away');
    expect(places.regions.desk.root.classList.contains('shaded-panel')).toBe(true);
    expect(places.regions.desk.head.tagName).toBe('H5');
    // The desk does not fold; the drawer does.
    expect(places.regions.desk.head.querySelector('.sidebar-collapse-icon')).toBeNull();
    expect(places.regions.stash.head.querySelector('.sidebar-collapse-icon')).not.toBeNull();
    expect(places.regionOf(places.regions.stash.body.appendChild(document.createElement('p')))).toBe('stash');
  });

  test('shows Now and Latest on the desk, Put away in the drawer, and Before nowhere', () => {
    const regionOf = window.WorkbenchPlaces.regionOf;
    expect(['current', 'latest', 'previous', 'stash'].map(regionOf)).toEqual(['desk', 'desk', null, 'stash']);
  });

  test('counts Now against its limit, says when the desk holds nothing, and counts the drawer', () => {
    const places = window.WorkbenchPlaces.build(container);
    places.fill({ current: 0, latest: 0, stash: 0 }, { limit: 10 });
    expect(places.regions.desk.count.textContent).toBe('Now 0 / 10');
    expect(places.regions.desk.body.querySelector('.workbench-place-none').textContent).toBe('Nothing here');
    places.fill({ current: 2, latest: 1, stash: 4 }, { limit: 10 });
    expect(places.regions.desk.count.textContent).toBe('Now 2 / 10');
    expect(places.regions.desk.body.querySelector('.workbench-place-none')).toBeNull();
    expect(places.regions.stash.count.textContent).toBe('4');
  });

  test('keeps the drawer folded at first, opens and folds it from its head, with the keys too, and keeps that', () => {
    let places = window.WorkbenchPlaces.build(container);
    const drawer = places.regions.stash;
    expect(drawer.root.classList.contains('is-folded')).toBe(true);
    expect(drawer.head.getAttribute('aria-expanded')).toBe('false');
    drawer.head.click();
    expect(drawer.root.classList.contains('is-folded')).toBe(false);
    expect(drawer.head.getAttribute('aria-expanded')).toBe('true');
    // The next page opens it as it was left.
    places = window.WorkbenchPlaces.build(container);
    expect(places.regions.stash.root.classList.contains('is-folded')).toBe(false);
    places.regions.stash.head.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    expect(places.regions.stash.root.classList.contains('is-folded')).toBe(true);
  });

  test('narrows the drawer to the rows whose name holds what is typed, in any case, also after a fill', () => {
    const places = window.WorkbenchPlaces.build(container);
    const body = places.regions.stash.body;
    body.append(row('Plan.pdf'), row('notes.txt'), row('whiteboard-1.png'));
    places.regions.stash.filter.value = 'PL';
    places.regions.stash.filter.dispatchEvent(new Event('input'));
    expect(Array.from(body.children).map((n) => n.hidden)).toEqual([false, true, true]);
    body.appendChild(row('plain.md'));
    places.fill({ current: 0, latest: 0, stash: 4 }, {});
    expect(Array.from(body.children).map((n) => n.hidden)).toEqual([false, true, true, false]);
    places.regions.stash.filter.value = '';
    places.regions.stash.filter.dispatchEvent(new Event('input'));
    expect(Array.from(body.children).every((n) => !n.hidden)).toBe(true);
  });
});
