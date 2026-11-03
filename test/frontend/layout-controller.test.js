/**
 * @jest-environment jsdom
 */
// The page's column layout comes from one place: what the user chose, or the
// default for the window's width.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

function setWidth(width) {
  Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: width });
}

describe('LayoutController', () => {
  let LC;

  beforeEach(() => {
    jest.resetModules();
    localStorage.clear();
    document.cookie = 'menu-hidden-preference=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT';
    document.body.className = '';
    document.body.innerHTML =
      '<button id="toggle-menu" aria-expanded="true"></button>' +
      '<div id="menu" class="col-md-4"></div>' +
      '<div id="main" class="col-md-8"></div>';
    delete window.UIConfig;
    delete window.StorageHelper;
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/cookie-utils.js'));
    LC = require(js('monadic/layout-controller.js'));
  });

  const menu = () => document.getElementById('menu');
  const main = () => document.getElementById('main');
  const btn = () => document.getElementById('toggle-menu');
  const shown = (el) => el.style.display !== 'none';

  test('with no choice yet, a wide window shows the menu beside the conversation', () => {
    setWidth(1280);
    LC.apply();
    expect(LC.isMenuHidden()).toBe(false);
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(true);
    expect(main().classList.contains('col-md-8')).toBe(true);
    expect(btn().classList.contains('menu-hidden')).toBe(false);
    expect(btn().getAttribute('aria-expanded')).toBe('true');
  });

  test('with no choice yet, a narrow window shows the conversation alone', () => {
    setWidth(500);
    LC.apply();
    expect(LC.isMenuHidden()).toBe(true);
    expect(shown(menu())).toBe(false);
    expect(shown(main())).toBe(true);
    expect(document.body.classList.contains('menu-visible')).toBe(false);
  });

  test('hiding the menu in a wide window widens the conversation and keeps the choice', () => {
    setWidth(1280);
    LC.apply();
    expect(LC.toggleMenu()).toBe(true);
    expect(shown(menu())).toBe(false);
    expect(main().classList.contains('col-md-12')).toBe(true);
    expect(main().classList.contains('col-md-8')).toBe(false);
    expect(btn().classList.contains('menu-hidden')).toBe(true);
    expect(btn().getAttribute('aria-expanded')).toBe('false');
    expect(window.getCookie('menu-hidden-preference')).toBe('true');

    expect(LC.toggleMenu()).toBe(false);
    expect(shown(menu())).toBe(true);
    expect(main().classList.contains('col-md-8')).toBe(true);
    expect(window.getCookie('menu-hidden-preference')).toBe('false');
  });

  test('in a narrow window the menu and the conversation take turns', () => {
    setWidth(500);
    LC.apply();
    LC.toggleMenu();
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(false);
    expect(document.body.classList.contains('menu-visible')).toBe(true);
  });

  test('the choice holds when the window is resized', () => {
    setWidth(1280);
    LC.setMenuHidden(true);
    setWidth(500);
    LC.apply();
    expect(shown(menu())).toBe(false);
    setWidth(1280);
    LC.apply();
    expect(shown(menu())).toBe(false);
    expect(main().classList.contains('col-md-12')).toBe(true);
  });

  test('a menu shown on a narrow window is beside the conversation again when the window widens', () => {
    setWidth(500);
    LC.setMenuHidden(false);
    expect(shown(main())).toBe(false);
    setWidth(1280);
    LC.apply();
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(true);
    expect(document.body.classList.contains('menu-visible')).toBe(false);
  });

  test('resetting the Web UI, which clears the page storage, keeps the choice', () => {
    setWidth(1280);
    LC.setMenuHidden(true);
    localStorage.clear();
    sessionStorage.clear();
    LC.apply();
    expect(shown(menu())).toBe(false);
  });

  test('applying twice changes nothing', () => {
    setWidth(1280);
    LC.setMenuHidden(true);
    const before = document.body.innerHTML + document.body.className;
    LC.apply();
    expect(document.body.innerHTML + document.body.className).toBe(before);
  });
});

// Other page scripts read the layout from the controller and change it
// through it; they do not set it themselves.
describe('who sets the column layout', () => {
  const fs = require('fs');
  const dir = path.join(__dirname, '../../docker/services/ruby/public/js');
  const files = [path.join(dir, 'monadic.js')].concat(
    fs.readdirSync(path.join(dir, 'monadic'))
      .filter((f) => f.endsWith('.js') && f !== 'layout-controller.js')
      .map((f) => path.join(dir, 'monadic', f))
  );

  test('only layout-controller.js stores the choice or sets the column widths', () => {
    const offenders = files.filter((f) => {
      const src = fs.readFileSync(f, 'utf8');
      return /menu-hidden-preference|monadic-menu-hidden/.test(src) ||
        /\$id\(\s*["']main["']\s*\)[\s\S]{0,40}classList\.(add|remove)\(\s*["']col-md-(8|12)["']/.test(src) ||
        /\$main\.classList\.(add|remove)\(\s*["']col-md-(8|12)["']/.test(src) ||
        /mainPanel\.classList\.(add|remove)\(\s*["']col-md-(8|12)["']/.test(src);
    }).map((f) => path.basename(f));
    expect(offenders).toEqual([]);
  });
});
