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
    document.cookie = 'side-pane-preference=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT';
    document.body.className = '';
    document.body.innerHTML =
      '<button id="toggle-menu" aria-expanded="true"></button>' +
      '<div class="row">' +
      '<div id="menu">' +
        '<div id="side-pane-tabs" role="tablist">' +
          '<button id="side-tab-settings" role="tab" aria-selected="true" aria-controls="settings-pane" data-pane="settings">Settings</button>' +
          '<button id="side-tab-work" role="tab" aria-selected="false" aria-controls="work-screen-pane" data-pane="work" tabindex="-1">Work screen</button>' +
        '</div>' +
        '<div id="settings-pane" role="tabpanel"></div>' +
        '<div id="work-screen-pane" role="tabpanel" hidden></div>' +
      '</div>' +
      '<div id="side-pane-splitter" role="separator" tabindex="0" hidden></div>' +
      '<div id="main"></div>' +
      '</div>';
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
  const handle = () => document.getElementById('side-pane-splitter');
  const sideWidth = () => menu().parentElement.style.getPropertyValue('--side-pane-width');
  // The border is there to drag (beside the conversation) or not.
  const draggable = (on) => {
    expect(handle().hidden).toBe(!on);
    expect(handle().tabIndex).toBe(on ? 0 : -1);
  };

  test('with no choice yet, a wide window shows the menu beside the conversation', () => {
    setWidth(1280);
    LC.apply();
    expect(LC.isMenuHidden()).toBe(false);
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(true);
    expect(sideWidth()).toBe('40%');
    draggable(true);
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
    draggable(false);
    expect(btn().classList.contains('menu-hidden')).toBe(true);
    expect(btn().getAttribute('aria-expanded')).toBe('false');
    expect(window.getCookie('menu-hidden-preference')).toBe('true');

    expect(LC.toggleMenu()).toBe(false);
    expect(shown(menu())).toBe(true);
    draggable(true);
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

  // Below 768 px the CSS shows #menu only with body.menu-visible.
  test.each([600, 700, 767])('at %i px the menu and the conversation take turns too', (width) => {
    setWidth(width);
    LC.apply();
    expect(LC.isMenuHidden()).toBe(true);
    LC.toggleMenu();
    expect(document.body.classList.contains('menu-visible')).toBe(true);
    expect(shown(main())).toBe(false);
  });

  test('at 768 px the menu is beside the conversation', () => {
    setWidth(768);
    LC.apply();
    expect(LC.isMenuHidden()).toBe(false);
    expect(document.body.classList.contains('menu-visible')).toBe(false);
    expect(shown(main())).toBe(true);
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
    draggable(false);
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

  const tab = (id) => document.getElementById(id);
  const pane = (id) => document.getElementById(id);

  test('the settings pane is shown until the user picks the work screen', () => {
    setWidth(1280);
    LC.apply();
    expect(LC.selectedPane()).toBe('settings');
    expect(tab('side-tab-settings').getAttribute('aria-selected')).toBe('true');
    expect(pane('settings-pane').hidden).toBe(false);
    expect(pane('work-screen-pane').hidden).toBe(true);
    expect(sideWidth()).toBe('40%');
  });

  test('the work screen pane is as wide as the menu', () => {
    setWidth(1280);
    LC.setPane('work');
    expect(pane('work-screen-pane').hidden).toBe(false);
    expect(pane('settings-pane').hidden).toBe(true);
    expect(tab('side-tab-work').getAttribute('aria-selected')).toBe('true');
    expect(tab('side-tab-work').tabIndex).toBe(0);
    expect(tab('side-tab-settings').tabIndex).toBe(-1);
    expect(sideWidth()).toBe('40%');
    expect(window.getCookie('side-pane-preference')).toBeNull();
  });

  test('the page opens on Settings again when it is loaded again, and the old pane cookie is removed', () => {
    setWidth(1280);
    LC.setPane('work');
    document.cookie = 'side-pane-preference=work; path=/';
    jest.resetModules();
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/cookie-utils.js'));
    LC = require(js('monadic/layout-controller.js'));
    LC.apply();
    expect(LC.selectedPane()).toBe('settings');
    expect(pane('settings-pane').hidden).toBe(false);
    expect(window.getCookie('side-pane-preference')).toBeNull();
  });

  test('hiding the column with the work screen selected gives the conversation the whole width', () => {
    setWidth(1280);
    LC.setPane('work');
    LC.setMenuHidden(true);
    expect(shown(menu())).toBe(false);
    draggable(false);
    LC.setMenuHidden(false);
    draggable(true);
  });

  test('clicking a tab selects it; an unknown pane changes nothing', () => {
    setWidth(1280);
    LC.apply();
    tab('side-tab-work').click();
    expect(LC.selectedPane()).toBe('work');
    LC.setPane('elsewhere');
    expect(LC.selectedPane()).toBe('work');
    tab('side-tab-settings').click();
    expect(LC.selectedPane()).toBe('settings');
  });

  test('the arrow keys move between tabs without selecting them', () => {
    setWidth(1280);
    LC.apply();
    tab('side-tab-settings').focus();
    tab('side-tab-settings').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
    expect(document.activeElement).toBe(tab('side-tab-work'));
    expect(LC.selectedPane()).toBe('settings');
    tab('side-tab-work').dispatchEvent(new KeyboardEvent('keydown', { key: 'Home', bubbles: true }));
    expect(document.activeElement).toBe(tab('side-tab-settings'));
    tab('side-tab-settings').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }));
    expect(document.activeElement).toBe(tab('side-tab-work'));
    tab('side-tab-work').dispatchEvent(new KeyboardEvent('keydown', { key: 'Home', bubbles: true }));
    tab('side-tab-settings').dispatchEvent(new KeyboardEvent('keydown', { key: 'End', bubbles: true }));
    expect(document.activeElement).toBe(tab('side-tab-work'));
    expect(LC.selectedPane()).toBe('settings');
  });

  describe('the border between the columns', () => {
    const row = () => menu().parentElement;
    const at = (clientX, type) => {
      const e = new MouseEvent(type, { clientX, bubbles: true, button: 0 });
      Object.defineProperty(e, 'pointerId', { value: 1 });
      handle().dispatchEvent(e);
    };
    beforeEach(() => {
      row().getBoundingClientRect = () => ({ left: 0, right: 1000, width: 1000, top: 0, bottom: 500, height: 500 });
    });
    const key = (k) => handle().dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true }));

    test('dragging sets the side column to what is right of the pointer, kept when the drag ends', async () => {
      setWidth(1280);
      LC.apply();
      const changes = jest.fn();
      document.addEventListener('layoutchange', changes);
      at(600, 'pointerdown');
      expect(document.body.classList.contains('side-pane-resizing')).toBe(true);
      at(550, 'pointermove');
      expect(sideWidth()).toBe('45%');
      expect(localStorage.getItem('monadic-side-pane-width')).toBeNull();
      expect(changes).not.toHaveBeenCalled();
      at(550, 'pointerup');
      expect(document.body.classList.contains('side-pane-resizing')).toBe(false);
      expect(localStorage.getItem('monadic-side-pane-width')).toBe('45');
      expect(changes).toHaveBeenCalledTimes(1);
      // Said once drawn (in jsdom nothing is drawn: the width asked for).
      await new Promise((r) => (typeof requestAnimationFrame === 'function'
        ? requestAnimationFrame(() => requestAnimationFrame(r)) : r()));
      expect(handle().getAttribute('aria-valuenow')).toBe('45');
      document.removeEventListener('layoutchange', changes);
    });

    test.each(['pointercancel', 'lostpointercapture'])('a drag ended by %s is ended as by a release', (type) => {
      setWidth(1280);
      LC.apply();
      at(600, 'pointerdown');
      at(700, 'pointermove');
      at(700, type);
      expect(document.body.classList.contains('side-pane-resizing')).toBe(false);
      expect(localStorage.getItem('monadic-side-pane-width')).toBe('30');
      at(500, 'pointermove');
      expect(sideWidth()).toBe('30%');
    });

    test('a drag ends when the column is hidden or the window narrows', () => {
      setWidth(1280);
      LC.apply();
      at(600, 'pointerdown');
      LC.setMenuHidden(true);
      expect(document.body.classList.contains('side-pane-resizing')).toBe(false);
      LC.setMenuHidden(false);
      at(600, 'pointerdown');
      setWidth(700);
      LC.apply();
      expect(document.body.classList.contains('side-pane-resizing')).toBe(false);
      draggable(false);
    });

    test('keeps the width between 25 % and 60 %', () => {
      setWidth(1280);
      LC.apply();
      at(600, 'pointerdown');
      at(100, 'pointermove');
      expect(sideWidth()).toBe('60%');
      at(990, 'pointermove');
      expect(sideWidth()).toBe('25%');
      at(990, 'pointerup');
    });

    test('the arrow keys move the border, Home and End to the narrowest and widest', () => {
      setWidth(1280);
      LC.apply();
      key('ArrowLeft');
      expect(sideWidth()).toBe('42%');
      key('ArrowRight');
      key('ArrowRight');
      expect(sideWidth()).toBe('38%');
      key('End');
      expect(sideWidth()).toBe('60%');
      key('Home');
      expect(sideWidth()).toBe('25%');
      expect(localStorage.getItem('monadic-side-pane-width')).toBe('25');
    });

    test('a kept width is used when the page loads again; a broken one gives the default', () => {
      localStorage.setItem('monadic-side-pane-width', '52');
      jest.resetModules();
      require(js('monadic/dom-helpers.js'));
      require(js('monadic/cookie-utils.js'));
      LC = require(js('monadic/layout-controller.js'));
      setWidth(1280);
      LC.apply();
      expect(sideWidth()).toBe('52%');
      localStorage.setItem('monadic-side-pane-width', 'wide');
      jest.resetModules();
      require(js('monadic/dom-helpers.js'));
      require(js('monadic/cookie-utils.js'));
      LC = require(js('monadic/layout-controller.js'));
      LC.apply();
      expect(sideWidth()).toBe('40%');
      localStorage.setItem('monadic-side-pane-width', '95');
      jest.resetModules();
      require(js('monadic/dom-helpers.js'));
      require(js('monadic/cookie-utils.js'));
      LC = require(js('monadic/layout-controller.js'));
      LC.apply();
      expect(sideWidth()).toBe('60%');
    });

    test('the width stays as it was while the window is narrow', () => {
      localStorage.setItem('monadic-side-pane-width', '50');
      jest.resetModules();
      require(js('monadic/dom-helpers.js'));
      require(js('monadic/cookie-utils.js'));
      LC = require(js('monadic/layout-controller.js'));
      setWidth(700);
      LC.apply();
      draggable(false);
      setWidth(1280);
      LC.apply();
      expect(sideWidth()).toBe('50%');
      expect(localStorage.getItem('monadic-side-pane-width')).toBe('50');
    });
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
      return /menu-hidden-preference|monadic-menu-hidden|monadic-side-pane-width|--side-pane-width/.test(src) ||
        /\$id\(\s*["']main["']\s*\)[\s\S]{0,40}classList\.(add|remove)\(\s*["']col-md-(8|12)["']/.test(src) ||
        /\$main\.classList\.(add|remove)\(\s*["']col-md-(8|12)["']/.test(src) ||
        /mainPanel\.classList\.(add|remove)\(\s*["']col-md-(8|12)["']/.test(src);
    }).map((f) => path.basename(f));
    expect(offenders).toEqual([]);
  });
});
