/**
 * layout-controller.js
 *
 * The one owner of the page's column layout: whether the settings column
 * (#menu) is shown next to the conversation (#main), and the classes and
 * visibility that follow from it. Other code asks it (isMenuHidden) and
 * changes it (setMenuHidden, toggleMenu, apply) instead of reading or setting
 * the DOM itself; the classes it sets (menu-hidden on #toggle-menu,
 * body.menu-visible) are what other code may read.
 *
 * What the user chose is a display preference kept in a cookie, like the
 * theme, so resetting the Web UI (which clears the page's storage) keeps it.
 * Until they choose, the menu is shown on wide screens and hidden on narrow
 * ones.
 *
 *   - Narrow (below Bootstrap's md breakpoint, 768 px): the menu and the
 *     conversation take turns; body.menu-visible is set while the menu is
 *     shown.
 *   - Wide: the side column is beside the conversation, at the width the
 *     user set by dragging the border between them (#side-pane-splitter,
 *     the same for every pane, kept in localStorage), or the conversation
 *     is alone. The width is the CSS variable --side-pane-width on the row,
 *     which the CSS uses only at 768 px and wider.
 *
 * The side column holds three panes, Settings, the work screen and the
 * shared folder (shared-files-pane.js), behind tabs
 * (#side-pane-tabs). The page opens on Settings; the pane the user picks is
 * kept only until the page is loaded again. Which pane is shown is separate
 * from whether the column is shown. Each apply() dispatches "layoutchange"
 * on the document (the work screen follows whether it can be seen).
 */
(function() {
  'use strict';

  var COOKIE_NAME = 'menu-hidden-preference';
  var COOKIE_DAYS = 30;
  var PANES = ['settings', 'work', 'files'];
  var pane = 'settings';
  // The side column's width, in % of the row: the user's (by dragging or
  // with the keys on the border), kept per browser.
  var WIDTH_KEY = 'monadic-side-pane-width';
  var WIDTH_DEFAULT = 40;
  var WIDTH_MIN = 25;
  var WIDTH_MAX = 60;
  var WIDTH_STEP = 2;

  // Earlier versions kept the pane in this cookie; it is no longer read.
  if (typeof window.setCookie === 'function') {
    window.setCookie('side-pane-preference', '', -1);
  }

  function storedChoice() {
    var value = typeof window.getCookie === 'function' ? window.getCookie(COOKIE_NAME) : null;
    return value === 'true' ? true : (value === 'false' ? false : null);
  }

  function storeChoice(hidden) {
    if (typeof window.setCookie === 'function') {
      window.setCookie(COOKIE_NAME, hidden ? 'true' : 'false', COOKIE_DAYS);
    }
  }

  function clampWidth(value) {
    var n = Number(value);
    if (!isFinite(n)) return WIDTH_DEFAULT;
    return Math.min(WIDTH_MAX, Math.max(WIDTH_MIN, Math.round(n * 10) / 10));
  }

  function storedWidth() {
    try {
      var value = window.localStorage.getItem(WIDTH_KEY);
      return value === null ? WIDTH_DEFAULT : clampWidth(value);
    } catch (_) {
      return WIDTH_DEFAULT;
    }
  }

  function storeWidth(width) {
    try { window.localStorage.setItem(WIDTH_KEY, String(width)); } catch (_) { /* no storage here */ }
  }

  var width = storedWidth();

  function sideWidth() {
    return width;
  }

  function selectedPane() {
    return pane;
  }

  // Below Bootstrap's md breakpoint the CSS shows #menu only with
  // body.menu-visible, so the menu and the conversation take turns there.
  function isNarrow() {
    if (window.UIConfig && typeof window.UIConfig.isTabletView === 'function') {
      return window.UIConfig.isTabletView();
    }
    return window.innerWidth < 768;
  }

  function isMenuHidden() {
    var choice = storedChoice();
    return choice === null ? isNarrow() : choice;
  }

  // Puts the DOM in the state the choice and the width call for.
  function apply() {
    var toggleBtn = $id('toggle-menu');
    var menu = $id('menu');
    var main = $id('main');
    if (!toggleBtn || !menu || !main) return;

    var hidden = isMenuHidden();
    applyPanes();
    toggleBtn.classList.toggle('menu-hidden', hidden);
    toggleBtn.setAttribute('aria-expanded', hidden ? 'false' : 'true');

    var narrow = isNarrow();
    if (narrow) {
      $toggle(menu, !hidden);
      $toggle(main, hidden);
      document.body.classList.toggle('menu-visible', !hidden);
    } else {
      document.body.classList.remove('menu-visible');
      $show(main);
      $toggle(menu, !hidden);
    }
    applyWidth(narrow || hidden);

    if (window.UIConfig && window.UIConfig.STATE) {
      window.UIConfig.STATE.isMenuVisible = !hidden;
    }
    $dispatch(document, 'layoutchange');
  }

  // The side column's width on the row, and the border to drag: shown only
  // beside the conversation (off: narrow, or the column hidden).
  function applyWidth(off) {
    var row = menuRow();
    if (row) row.style.setProperty('--side-pane-width', width + '%');
    var handle = $id('side-pane-splitter');
    if (!handle) return;
    if (off) endDrag();
    handle.hidden = !!off;
    handle.tabIndex = off ? -1 : 0;
    announceSoon();
    bindSplitter();
  }

  function menuRow() {
    var menu = $id('menu');
    return menu ? menu.parentElement : null;
  }

  // A new width: set now; kept, and told to the page (layoutchange), when
  // the change is done (commit).
  function setWidth(value, commit) {
    width = clampWidth(value);
    var row = menuRow();
    if (row) row.style.setProperty('--side-pane-width', width + '%');
    announceSoon();
    if (commit) {
      storeWidth(width);
      $dispatch(document, 'layoutchange');
    }
  }

  // The side column's width as drawn, in % of the row: the CSS keeps it
  // within what its tabs and the conversation need, so it can differ from
  // the width asked for. null while it is not beside the conversation.
  function shownWidth() {
    var menu = $id('menu');
    var row = menuRow();
    if (!menu || !row || isNarrow() || isMenuHidden()) return null;
    var whole = row.getBoundingClientRect().width;
    var side = menu.getBoundingClientRect().width;
    return whole > 0 && side > 0 ? (side / whole) * 100 : null;
  }

  // The border says the width as drawn, once the new width is drawn (the
  // columns take it in the next frame).
  function announceSoon() {
    var handle = $id('side-pane-splitter');
    if (!handle) return;
    var announce = function() {
      var shown = shownWidth();
      handle.setAttribute('aria-valuenow', String(Math.round(shown === null ? width : shown)));
    };
    if (typeof window.requestAnimationFrame === 'function') {
      window.requestAnimationFrame(function() { window.requestAnimationFrame(announce); });
    } else {
      announce();
    }
  }

  // Dragging the border: the side column is what is right of the pointer.
  // Any way a drag can end (release, cancel, losing the pointer, the
  // column hidden or the window narrowed) ends it once.
  var dragging = null;
  function endDrag() {
    if (!dragging) return;
    var handle = $id('side-pane-splitter');
    if (handle && dragging.pointerId !== undefined && handle.hasPointerCapture &&
        handle.hasPointerCapture(dragging.pointerId)) {
      handle.releasePointerCapture(dragging.pointerId);
    }
    dragging = null;
    document.body.classList.remove('side-pane-resizing');
    setWidth(width, true);
  }

  var splitterBound = false;
  function bindSplitter() {
    var handle = $id('side-pane-splitter');
    if (splitterBound || !handle) return;
    splitterBound = true;
    handle.addEventListener('pointerdown', function(e) {
      if (e.button !== undefined && e.button !== 0) return;
      e.preventDefault();
      dragging = { pointerId: e.pointerId };
      if (handle.setPointerCapture && e.pointerId !== undefined) handle.setPointerCapture(e.pointerId);
      document.body.classList.add('side-pane-resizing');
    });
    handle.addEventListener('pointermove', function(e) {
      if (!dragging) return;
      var row = menuRow();
      var box = row ? row.getBoundingClientRect() : null;
      if (!box || box.width <= 0) return;
      setWidth(((box.right - e.clientX) / box.width) * 100, false);
    });
    ['pointerup', 'pointercancel', 'lostpointercapture'].forEach(function(type) {
      handle.addEventListener(type, endDrag);
    });
    // The arrow keys move the border by WIDTH_STEP; Home and End to the
    // narrowest and widest side column.
    handle.addEventListener('keydown', function(e) {
      // A step from the width as drawn, so each press moves the border.
      var shown = shownWidth();
      var from = shown === null ? width : shown;
      var next = null;
      if (e.key === 'ArrowLeft') next = from + WIDTH_STEP;
      else if (e.key === 'ArrowRight') next = from - WIDTH_STEP;
      else if (e.key === 'Home') next = WIDTH_MIN;
      else if (e.key === 'End') next = WIDTH_MAX;
      if (next === null) return;
      e.preventDefault();
      setWidth(next, true);
    });
  }

  // The tabs and panes of the side column, as selectedPane() says.
  function applyPanes() {
    PANES.forEach(function(name) {
      var tab = document.querySelector('#side-pane-tabs [data-pane="' + name + '"]');
      var panel = tab ? $id(tab.getAttribute('aria-controls')) : null;
      var on = name === pane;
      if (tab) {
        tab.setAttribute('aria-selected', on ? 'true' : 'false');
        tab.tabIndex = on ? 0 : -1;
      }
      if (panel) panel.hidden = !on;
    });
    bindTabs();
  }

  function setPane(name) {
    if (PANES.indexOf(name) === -1) return;
    pane = name;
    apply();
  }

  // Click selects a tab; the arrow keys, Home and End move between tabs and
  // Enter or Space selects (the tabs are buttons).
  var tabsBound = false;
  function bindTabs() {
    var list = $id('side-pane-tabs');
    if (tabsBound || !list) return;
    tabsBound = true;
    list.addEventListener('click', function(e) {
      var tab = e.target.closest('[role="tab"]');
      if (tab) setPane(tab.getAttribute('data-pane'));
    });
    list.addEventListener('keydown', function(e) {
      var tabs = Array.prototype.slice.call(list.querySelectorAll('[role="tab"]'));
      var at = tabs.indexOf(document.activeElement);
      if (at === -1) return;
      var next = null;
      if (e.key === 'ArrowRight') next = (at + 1) % tabs.length;
      else if (e.key === 'ArrowLeft') next = (at - 1 + tabs.length) % tabs.length;
      else if (e.key === 'Home') next = 0;
      else if (e.key === 'End') next = tabs.length - 1;
      if (next === null) return;
      e.preventDefault();
      tabs[next].focus();
    });
  }

  function setMenuHidden(hidden) {
    storeChoice(!!hidden);
    apply();
  }

  function toggleMenu() {
    setMenuHidden(!isMenuHidden());
    return isMenuHidden();
  }

  window.LayoutController = {
    apply: apply,
    isMenuHidden: isMenuHidden,
    setMenuHidden: setMenuHidden,
    toggleMenu: toggleMenu,
    selectedPane: selectedPane,
    setPane: setPane,
    sideWidth: sideWidth,
    setSideWidth: function(value) { setWidth(value, true); }
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.LayoutController;
  }
})();
