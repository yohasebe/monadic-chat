/**
 * @jest-environment jsdom
 */
// The work screen's four places: their heads, an empty one folded, and the
// separators between open places, moved with the keys and kept per layout
// mode.
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

  const open = (places) => Array.from(places.separators).filter((s) => !s.hidden);
  const grow = (places, name) => Number(places.regions[name].root.style.flexGrow);

  test('makes the four places in order, each with a head and a body of its own', () => {
    const places = window.WorkbenchPlaces.build(container);
    expect(Array.from(container.querySelectorAll('.workbench-place')).map((n) => n.dataset.place))
      .toEqual(['current', 'latest', 'previous', 'stash']);
    expect(places.regions.current.title.textContent.trim()).toBe('Now');
    expect(places.regions.stash.title.textContent.trim()).toBe('Put away');
    // Each a panel as the side column's others, its head with an icon and the arrow that folds it.
    expect(places.regions.current.root.classList.contains('shaded-panel')).toBe(true);
    expect(places.regions.current.head.tagName).toBe('H5');
    expect(places.regions.current.head.querySelector('.fa-pencil')).not.toBeNull();
    expect(places.regions.current.head.querySelector('.sidebar-collapse-icon')).not.toBeNull();
    expect(places.regionOf(places.regions.latest.body.appendChild(document.createElement('p')))).toBe('latest');
  });

  test('says who placed a layer and how many items it holds, Now against its limit', () => {
    const places = window.WorkbenchPlaces.build(container);
    places.fill({ current: 2, latest: 1, previous: 3, stash: 0 }, { layers: { latest: 'agent', previous: 'user' }, limit: 10 });
    expect(places.regions.current.count.textContent).toBe('2 / 10');
    expect(places.regions.latest.count.textContent).toBe('AI · 1');
    expect(places.regions.previous.count.textContent).toBe('You · 3');
    expect(places.regions.stash.count.textContent).toBe('0');
  });

  test('folds an empty place to its head and gives its height to the others, with one separator per open pair', () => {
    const places = window.WorkbenchPlaces.build(container);
    places.fill({ current: 1, latest: 0, previous: 2, stash: 0 }, {});
    expect(places.regions.latest.root.classList.contains('is-empty')).toBe(true);
    expect(grow(places, 'latest')).toBe(0);
    // An empty Latest or Before is not shown; an empty Now or Put away is its head.
    expect(places.regions.latest.root.hidden).toBe(true);
    expect(places.regions.stash.root.hidden).toBe(false);
    places.fill({ current: 0, latest: 0, previous: 0, stash: 0 }, {});
    expect(places.regions.current.root.hidden).toBe(false);
    expect(places.regions.previous.root.hidden).toBe(true);
    places.fill({ current: 1, latest: 0, previous: 2, stash: 0 }, {});
    expect(places.regions.previous.root.hidden).toBe(false);
    expect(grow(places, 'current') + grow(places, 'previous')).toBeCloseTo(1);
    const shown = open(places);
    expect(shown).toHaveLength(1);
    expect(shown[0].getAttribute('aria-label')).toBe('Now / Before');
    expect(shown[0].tabIndex).toBe(0);
  });

  test('moves a separator with the arrow keys between its two places only, and keeps it for the layout mode', () => {
    const places = window.WorkbenchPlaces.build(container);
    places.fill({ current: 1, latest: 1, previous: 1, stash: 1 }, { mode: 'side' });
    const first = open(places)[0];
    const before = { current: grow(places, 'current'), latest: grow(places, 'latest'), previous: grow(places, 'previous') };
    first.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
    expect(grow(places, 'current')).toBeGreaterThan(before.current);
    expect(grow(places, 'latest')).toBeLessThan(before.latest);
    expect(grow(places, 'previous')).toBeCloseTo(before.previous);
    const kept = JSON.parse(window.localStorage.getItem('monadic.workbench.places.side'));
    expect(kept.current).toBeGreaterThan(0.4);
    // Another mode has its own; coming back takes the kept one.
    places.fill({ current: 1, latest: 1, previous: 1, stash: 1 }, { mode: 'right' });
    expect(grow(places, 'current')).toBeCloseTo(before.current);
    places.fill({ current: 1, latest: 1, previous: 1, stash: 1 }, { mode: 'side' });
    expect(grow(places, 'current')).toBeGreaterThan(before.current);
  });

  test('folds a place by hand from its head, with the keys too, and keeps that for the next page', () => {
    const places = window.WorkbenchPlaces.build(container);
    places.fill({ current: 1, latest: 1, previous: 0, stash: 0 }, {});
    const head = places.regions.latest.head;
    expect(head.getAttribute('aria-expanded')).toBe('true');
    head.click();
    expect(places.regions.latest.root.classList.contains('is-folded')).toBe(true);
    expect(head.getAttribute('aria-expanded')).toBe('false');
    expect(grow(places, 'latest')).toBe(0);
    expect(grow(places, 'current')).toBeCloseTo(1);
    expect(open(places)).toHaveLength(0);
    head.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    expect(places.regions.latest.root.classList.contains('is-folded')).toBe(false);
    head.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }));
    const again = window.WorkbenchPlaces.build(container);
    again.fill({ current: 1, latest: 1, previous: 0, stash: 0 }, {});
    expect(again.regions.latest.root.classList.contains('is-folded')).toBe(true);
  });

  test('folds an empty place by hand too, its arrow saying whether it is folded, and says when an open one holds nothing', () => {
    const places = window.WorkbenchPlaces.build(container);
    places.fill({ current: 0, latest: 0, previous: 0, stash: 0 }, {});
    const now = places.regions.current;
    expect(now.head.getAttribute('aria-expanded')).toBe('true');
    expect(now.body.querySelector('.workbench-place-none').textContent).toBe('Nothing here');
    now.head.click();
    expect(now.head.getAttribute('aria-expanded')).toBe('false');
    expect(now.root.classList.contains('is-folded')).toBe(true);
    now.head.click();
    expect(now.head.getAttribute('aria-expanded')).toBe('true');
    places.fill({ current: 1, latest: 0, previous: 0, stash: 0 }, {});
    expect(now.body.querySelector('.workbench-place-none')).toBeNull();
  });

  test('keeps each place a least share, and starts from the defaults when what was kept is broken', () => {
    window.localStorage.setItem('monadic.workbench.places.side', '{not json');
    const places = window.WorkbenchPlaces.build(container);
    places.fill({ current: 1, latest: 1, previous: 0, stash: 0 }, { mode: 'side' });
    expect(grow(places, 'current')).toBeGreaterThan(0);
    const separator = open(places)[0];
    for (let i = 0; i < 40; i += 1) separator.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
    expect(grow(places, 'current')).toBeGreaterThan(0.05);
    expect(grow(places, 'latest')).toBeLessThan(0.95);
  });
});
