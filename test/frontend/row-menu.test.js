/**
 * @jest-environment jsdom
 */
// The small menu of a row or a band: one at a time, moved through with the
// arrows; Esc and Tab close it and give the focus back to its button, as a
// scroll or a resize does when the focus was in it; a click outside keeps
// the focus where it went; a button that is gone gives the focus to where
// the menu was told to.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js/monadic', f);

describe('RowMenu', () => {
  let RowMenu;
  let button;
  let ran;

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = '<button id="more">⋯</button><input id="elsewhere">';
    button = document.getElementById('more');
    ran = [];
    RowMenu = require(js('row-menu.js'));
  });

  afterEach(() => RowMenu.close());

  const open = (opts) => RowMenu.open(button, [
    { label: 'First', action: () => ran.push('first') },
    { label: 'Off', disabled: true },
    'divider',
    { label: 'Last', action: () => ran.push('last') }
  ], opts);
  const box = () => document.querySelector('.row-menu');
  const press = (key) => document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true }));

  it('opens on the body as a menu, with the focus on its first item, and says so on its button', () => {
    open();
    expect(box().parentNode).toBe(document.body);
    expect(box().getAttribute('role')).toBe('menu');
    expect(document.activeElement.textContent).toBe('First');
    expect(button.getAttribute('aria-expanded')).toBe('true');
  });

  it('moves over the items it can run with the arrows, and runs one', () => {
    open();
    press('ArrowDown');
    expect(document.activeElement.textContent).toBe('Last');
    press('ArrowDown');
    expect(document.activeElement.textContent).toBe('First');
    document.activeElement.click();
    expect(ran).toEqual(['first']);
    expect(box()).toBeNull();
    expect(document.activeElement).toBe(button);
  });

  it.each(['Escape', 'Tab'])('closes on %s and gives the focus back to its button', (key) => {
    open();
    press(key);
    expect(box()).toBeNull();
    expect(document.activeElement).toBe(button);
    expect(button.getAttribute('aria-expanded')).toBe('false');
  });

  it('gives the focus back when a scroll closes it with the focus in it', () => {
    open();
    document.dispatchEvent(new Event('scroll'));
    expect(box()).toBeNull();
    expect(document.activeElement).toBe(button);
  });

  it('keeps the focus where a click outside put it', () => {
    open();
    const other = document.getElementById('elsewhere');
    other.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    other.focus();
    expect(box()).toBeNull();
    expect(document.activeElement).toBe(other);
  });

  it('gives the focus to where it was told when its button is gone', () => {
    const restore = jest.fn();
    open({ restore });
    button.remove();
    window.dispatchEvent(new Event('resize'));
    expect(restore).toHaveBeenCalled();
  });

  it('closes when its button is pressed again, and shows one menu at a time', () => {
    open();
    open();
    expect(box()).toBeNull();
    open();
    RowMenu.openPanel(document.getElementById('elsewhere'), document.createElement('form'));
    expect(document.querySelectorAll('.row-menu')).toHaveLength(1);
  });
});
