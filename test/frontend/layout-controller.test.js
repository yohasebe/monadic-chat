/**
 * @jest-environment jsdom
 */
// The page's column layout comes from one place: the mode the user chose
// with the top bar's layout buttons, or the default for the window's width.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

function setWidth(width) {
  Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: width });
}

const clearCookie = (name) => { document.cookie = `${name}=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT`; };

describe('LayoutController', () => {
  let LC;

  const load = () => {
    jest.resetModules();
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/cookie-utils.js'));
    LC = require(js('monadic/layout-controller.js'));
  };

  beforeEach(() => {
    localStorage.clear();
    ['layout-mode-preference', 'menu-hidden-preference', 'side-pane-preference'].forEach(clearCookie);
    document.body.className = '';
    document.body.innerHTML =
      '<div id="layout-mode" role="group">' +
        '<button type="button" data-layout="both" aria-pressed="true" title="Side by side"></button>' +
        '<button type="button" data-layout="left" aria-pressed="false" title="Left only"></button>' +
        '<button type="button" data-layout="right" aria-pressed="false" title="Right only"></button>' +
      '</div>' +
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
    delete window.MonadicTip;
    load();
  });

  const menu = () => document.getElementById('menu');
  const main = () => document.getElementById('main');
  const modeButton = (m) => document.querySelector(`#layout-mode [data-layout="${m}"]`);
  const pressed = () => ['both', 'left', 'right'].filter((m) => modeButton(m).getAttribute('aria-pressed') === 'true');
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
    expect(LC.mode()).toBe('both');
    expect(LC.isMenuHidden()).toBe(false);
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(true);
    expect(sideWidth()).toBe('40%');
    draggable(true);
    expect(pressed()).toEqual(['both']);
  });

  test('with no choice yet, a narrow window shows the conversation alone', () => {
    setWidth(500);
    LC.apply();
    expect(LC.isMenuHidden()).toBe(true);
    expect(shown(menu())).toBe(false);
    expect(shown(main())).toBe(true);
    expect(document.body.classList.contains('menu-visible')).toBe(false);
  });

  test('the three buttons switch the mode, press the one chosen and keep the choice', () => {
    setWidth(1280);
    LC.apply();
    modeButton('left').click();
    expect(pressed()).toEqual(['left']);
    expect(shown(menu())).toBe(false);
    expect(shown(main())).toBe(true);
    draggable(false);
    expect(window.getCookie('layout-mode-preference')).toBe('left');

    modeButton('right').click();
    expect(pressed()).toEqual(['right']);
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(false);
    expect(LC.isMainHidden()).toBe(true);
    expect(document.body.classList.contains('side-pane-only')).toBe(true);
    draggable(false);
    expect(window.getCookie('layout-mode-preference')).toBe('right');

    modeButton('both').click();
    expect(pressed()).toEqual(['both']);
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(true);
    expect(document.body.classList.contains('side-pane-only')).toBe(false);
    draggable(true);
    expect(window.getCookie('layout-mode-preference')).toBe('both');
  });

  test('the buttons are buttons: the keyboard reaches them, and Enter and Space click them', () => {
    setWidth(1280);
    LC.apply();
    ['both', 'left', 'right'].forEach((m) => {
      expect(modeButton(m).tagName).toBe('BUTTON');
      expect(modeButton(m).tabIndex).toBe(0);
    });
  });

  test('a chosen button tells the page (the scroll buttons follow)', () => {
    setWidth(1280);
    LC.apply();
    const chosen = jest.fn();
    document.getElementById('layout-mode').addEventListener('layoutmodechosen', chosen);
    modeButton('left').click();
    expect(chosen).toHaveBeenCalledTimes(1);
  });

  test('the buttons have their tooltips when the page has them', () => {
    window.MonadicTip = { attach: jest.fn() };
    load();
    setWidth(1280);
    LC.apply();
    expect(window.MonadicTip.attach).toHaveBeenCalledTimes(3);
    expect(window.MonadicTip.attach.mock.calls.map((c) => c[0])).toEqual(['both', 'left', 'right'].map(modeButton));
    LC.apply();
    expect(window.MonadicTip.attach).toHaveBeenCalledTimes(3);
  });

  test('side by side again has the width the user kept; one column alone leaves it as it was', () => {
    setWidth(1280);
    LC.apply();
    LC.setSideWidth(52);
    modeButton('right').click();
    expect(sideWidth()).toBe('52%');
    modeButton('left').click();
    expect(sideWidth()).toBe('52%');
    expect(localStorage.getItem('monadic-side-pane-width')).toBe('52');
    modeButton('both').click();
    expect(sideWidth()).toBe('52%');
    expect(LC.sideWidth()).toBe(52);
  });

  test('the page works when its storage throws', () => {
    const denied = () => { throw new Error('denied'); };
    const spies = ['getItem', 'setItem'].map((name) => jest.spyOn(Storage.prototype, name).mockImplementation(denied));
    try {
      load();
      setWidth(1280);
      LC.apply();
      expect(sideWidth()).toBe('40%');
      modeButton('right').click();
      expect(shown(main())).toBe(false);
      LC.setSideWidth(50);
      modeButton('both').click();
      expect(sideWidth()).toBe('50%');
      expect(shown(main())).toBe(true);
    } finally {
      spies.forEach((spy) => spy.mockRestore());
    }
  });

  test('the mode is remembered when the page loads again', () => {
    setWidth(1280);
    LC.apply();
    modeButton('right').click();
    load();
    LC.apply();
    expect(LC.mode()).toBe('right');
    expect(pressed()).toEqual(['right']);
    expect(shown(main())).toBe(false);
  });

  test('a choice kept by the menu switch is taken over once', () => {
    document.cookie = 'menu-hidden-preference=true; path=/';
    load();
    setWidth(1280);
    LC.apply();
    expect(LC.mode()).toBe('left');
    expect(window.getCookie('layout-mode-preference')).toBe('left');
    expect(window.getCookie('menu-hidden-preference')).toBeNull();
  });

  test('showing the work screen from "left only" shows it side by side', () => {
    setWidth(1280);
    LC.apply();
    modeButton('left').click();
    // As workbench.js does for what the user opens
    if (LC.isMenuHidden()) LC.setMenuHidden(false);
    LC.setPane('work');
    expect(LC.mode()).toBe('both');
    expect(pressed()).toEqual(['both']);
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(true);
    expect(document.getElementById('work-screen-pane').hidden).toBe(false);
  });

  test('showing the side column on a narrow window gives it its turn, in any mode', () => {
    setWidth(500);
    LC.apply();
    modeButton('left').click();
    LC.setMenuHidden(false);
    expect(LC.mode()).toBe('both');
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(false);
    expect(document.body.classList.contains('menu-visible')).toBe(true);
  });

  test('showing the conversation leaves "right only" for side by side', () => {
    setWidth(1280);
    LC.apply();
    modeButton('right').click();
    LC.showConversation();
    expect(LC.mode()).toBe('both');
    expect(shown(main())).toBe(true);
    expect(shown(menu())).toBe(true);
  });

  test('in a narrow window the menu and the conversation take turns', () => {
    setWidth(500);
    LC.apply();
    modeButton('right').click();
    expect(shown(menu())).toBe(true);
    expect(shown(main())).toBe(false);
    expect(document.body.classList.contains('menu-visible')).toBe(true);
    modeButton('left').click();
    expect(shown(menu())).toBe(false);
    expect(shown(main())).toBe(true);
    expect(document.body.classList.contains('menu-visible')).toBe(false);
  });

  test('in a narrow window side by side shows the conversation, and pressing it again switches the turn', () => {
    setWidth(500);
    LC.apply();
    modeButton('right').click();
    modeButton('both').click();
    expect(shown(main())).toBe(true);
    expect(shown(menu())).toBe(false);
    modeButton('both').click();
    expect(shown(main())).toBe(false);
    expect(shown(menu())).toBe(true);
    expect(pressed()).toEqual(['both']);
    modeButton('both').click();
    expect(shown(main())).toBe(true);
  });

  // Below 768 px the CSS shows #menu only with body.menu-visible.
  test.each([600, 700, 767])('at %i px the menu and the conversation take turns too', (width) => {
    setWidth(width);
    LC.apply();
    expect(LC.isMenuHidden()).toBe(true);
    LC.setMenuHidden(false);
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
    expect(LC.mode()).toBe('left');
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
      return /layout-mode-preference|menu-hidden-preference|monadic-menu-hidden|monadic-side-pane-width|--side-pane-width/.test(src) ||
        /\$id\(\s*["']main["']\s*\)[\s\S]{0,40}classList\.(add|remove)\(\s*["']col-md-(8|12)["']/.test(src) ||
        /\$main\.classList\.(add|remove)\(\s*["']col-md-(8|12)["']/.test(src) ||
        /mainPanel\.classList\.(add|remove)\(\s*["']col-md-(8|12)["']/.test(src);
    }).map((f) => path.basename(f));
    expect(offenders).toEqual([]);
  });
});
