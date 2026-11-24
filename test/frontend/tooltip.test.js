/**
 * @jest-environment jsdom
 */

/**
 * MonadicTip (tooltip.js): one bubble, moved to the control it describes;
 * delays for the pointer and the focus, show() and hide() at once; the title
 * taken and given back; hidden by Esc, a press, or the control leaving.
 */
const fs = require('fs');
const path = require('path');

const SOURCE = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/js/monadic/tooltip.js'), 'utf8');

describe('MonadicTip', () => {
  beforeAll(() => { (0, eval)(SOURCE); });

  let controls;
  beforeEach(() => {
    jest.useFakeTimers();
    document.body.innerHTML = '<div id="box"><button id="a" title="First">A</button><button id="b" title="Second" aria-describedby="note">B</button></div><p id="note">n</p>';
    controls = { a: document.getElementById('a'), b: document.getElementById('b') };
  });
  afterEach(() => {
    window.MonadicTip.disposeWithin(document.body);
    window.MonadicTip.hideAll();
    jest.useRealTimers();
  });

  const bubble = () => document.getElementById('monadic-tip');
  const shown = () => !!bubble() && !bubble().hidden;
  const enter = (el) => el.dispatchEvent(new Event('pointerenter'));
  const leave = (el) => el.dispatchEvent(new Event('pointerleave'));

  test('one handle for a control, its title taken (the browser\'s own does not show too) and given back', () => {
    const tip = window.MonadicTip.attach(controls.a);
    expect(window.MonadicTip.attach(controls.a)).toBe(tip);
    expect(window.MonadicTip.get(controls.a)).toBe(tip);
    expect(controls.a.hasAttribute('title')).toBe(false);
    tip.dispose();
    expect(controls.a.getAttribute('title')).toBe('First');
    expect(window.MonadicTip.get(controls.a)).toBeNull();
  });

  test('a text given as an option makes no title on the control', () => {
    const status = document.createElement('div');
    document.body.appendChild(status);
    const tip = window.MonadicTip.attach(status, { title: 'Ready' });
    tip.show();
    expect(bubble().textContent).toBe('Ready');
    tip.dispose();
    expect(status.hasAttribute('title')).toBe(false);
  });

  test('the pointer shows it after the delay, leaving hides it; show() is at once', () => {
    const tip = window.MonadicTip.attach(controls.a, { delay: { show: 500, hide: 0 } });
    enter(controls.a);
    jest.advanceTimersByTime(499);
    expect(shown()).toBe(false);
    jest.advanceTimersByTime(1);
    expect(shown()).toBe(true);
    expect(bubble().textContent).toBe('First');
    leave(controls.a);
    jest.advanceTimersByTime(200);
    expect(shown()).toBe(false);
    tip.show();
    expect(shown()).toBe(true);
  });

  test('a delay that ran out for one control does not show it over another', () => {
    window.MonadicTip.attach(controls.a, { delay: { show: 300 } });
    window.MonadicTip.attach(controls.b, { delay: { show: 0 } });
    enter(controls.a);
    leave(controls.a);
    enter(controls.b);
    jest.advanceTimersByTime(1000);
    expect(bubble().textContent).toBe('Second');
  });

  test('the bubble describes only the control shown, keeping its own descriptions', () => {
    const tipA = window.MonadicTip.attach(controls.a);
    const tipB = window.MonadicTip.attach(controls.b);
    tipB.show();
    expect(controls.b.getAttribute('aria-describedby')).toBe('note monadic-tip');
    tipA.show();
    expect(controls.b.getAttribute('aria-describedby')).toBe('note');
    expect(controls.a.getAttribute('aria-describedby')).toBe('monadic-tip');
    tipA.hide();
    expect(controls.a.hasAttribute('aria-describedby')).toBe(false);
  });

  test('a text set while shown changes the bubble; an empty one hides it', () => {
    const tip = window.MonadicTip.attach(controls.a);
    tip.show();
    tip.setText('Changed');
    expect(bubble().textContent).toBe('Changed');
    tip.setText('');
    expect(shown()).toBe(false);
  });

  test('a title written again later (a translation) becomes the text', () => {
    const tip = window.MonadicTip.attach(controls.a);
    controls.a.setAttribute('title', 'Erster');
    tip.show();
    expect(bubble().textContent).toBe('Erster');
    expect(controls.a.hasAttribute('title')).toBe(false);
  });

  test('Esc hides it and goes no further; with nothing shown, Esc is left alone', () => {
    const tip = window.MonadicTip.attach(controls.a);
    const after = jest.fn();
    document.body.addEventListener('keydown', after);
    tip.show();
    controls.a.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    expect(shown()).toBe(false);
    expect(after).not.toHaveBeenCalled();
    controls.a.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    expect(after).toHaveBeenCalledTimes(1);
    document.body.removeEventListener('keydown', after);
  });

  test('a press hides it, and it stays hidden until the pointer comes again', () => {
    window.MonadicTip.attach(controls.a, { delay: { show: 0 } });
    enter(controls.a);
    expect(shown()).toBe(true);
    controls.a.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(shown()).toBe(false);
    enter(controls.a);
    expect(shown()).toBe(false);
    leave(controls.a);
    enter(controls.a);
    expect(shown()).toBe(true);
  });

  test('the control leaving the page hides it, with nothing else happening', async () => {
    const tip = window.MonadicTip.attach(controls.a);
    tip.show();
    document.getElementById('box').replaceChildren();
    await Promise.resolve();
    expect(shown()).toBe(false);
  });

  test('a delay that runs out after the control left shows nothing', () => {
    window.MonadicTip.attach(controls.a, { delay: { show: 300 } });
    enter(controls.a);
    controls.a.remove();
    jest.advanceTimersByTime(400);
    expect(shown()).toBe(false);
  });

  test('a control not yet on the page can be given its tooltip', () => {
    const later = document.createElement('button');
    later.title = 'Later';
    const tip = window.MonadicTip.attach(later);
    tip.show();
    expect(shown()).toBe(false);
    document.body.appendChild(later);
    tip.show();
    expect(bubble().textContent).toBe('Later');
  });

  test('hideAll keeps the tooltips; disposeWithin lets go of those in a part, itself included, and no others', () => {
    const tipA = window.MonadicTip.attach(controls.a);
    const box = document.getElementById('box');
    const tipBox = window.MonadicTip.attach(box, { title: 'Box' });
    const outside = document.getElementById('note');
    outside.title = 'Note';
    const tipOut = window.MonadicTip.attach(outside);
    tipA.show();
    window.MonadicTip.hideAll();
    expect(shown()).toBe(false);
    expect(window.MonadicTip.get(controls.a)).toBe(tipA);
    window.MonadicTip.disposeWithin(box);
    expect(window.MonadicTip.get(controls.a)).toBeNull();
    expect(window.MonadicTip.get(box)).toBeNull();
    expect(window.MonadicTip.get(outside)).toBe(tipOut);
    expect(tipBox).toBeTruthy();
  });

  test('the bubble goes into an open dialog the control is in', () => {
    const dialog = document.createElement('dialog');
    dialog.setAttribute('open', '');
    const inside = document.createElement('button');
    inside.title = 'Inside';
    dialog.appendChild(inside);
    document.body.appendChild(dialog);
    window.MonadicTip.attach(inside).show();
    expect(bubble().parentNode).toBe(dialog);
    window.MonadicTip.attach(controls.a).show();
    expect(bubble().parentNode).toBe(document.body);
  });

  test('a text is text, never HTML', () => {
    const tip = window.MonadicTip.attach(controls.a, { title: '<img src=x onerror="window.__tip=1">' });
    tip.show();
    expect(bubble().querySelector('img')).toBeNull();
    expect(bubble().textContent).toContain('<img');
  });
});

describe('the scripts use MonadicTip only', () => {
  const DIR = path.join(__dirname, '../../docker/services/ruby/public/js');
  const files = ['monadic.js'].concat(fs.readdirSync(path.join(DIR, 'monadic')).filter((f) => f.endsWith('.js')).map((f) => `monadic/${f}`));

  test.each([
    ['Bootstrap\'s tooltip', /bootstrap\.Tooltip/],
    ['its moved titles', /data-bs-original-title/],
    ['its bubbles removed by hand', /querySelectorAll\(['"]\.tooltip['"]\)/],
    ['its content set', /setContent\(/]
  ])('no script uses %s', (_name, pattern) => {
    const found = files.filter((f) => pattern.test(fs.readFileSync(path.join(DIR, f), 'utf8')));
    expect(found).toEqual([]);
  });
});
