/**
 * layout-controller.js
 *
 * The one owner of the page's column layout: how the conversation (#main)
 * and the side column (#menu) are shown, and the classes and visibility
 * that follow from it. Other code asks it (mode, isMenuHidden,
 * isMainHidden) and changes it (setMode, setMenuHidden, showConversation,
 * apply) instead of reading or setting the DOM itself; the classes it sets
 * (body.menu-visible, body.side-pane-only) are what other code may read.
 *
 * The layout is one of three modes, chosen with the buttons of #layout-mode
 * in the top bar: "both" (side by side), "left" (the conversation alone)
 * and "right" (the side column alone, at the full width). The choice is a
 * display preference kept in a cookie, like the theme, so resetting the Web
 * UI (which clears the page's storage) keeps it. Until the user chooses,
 * the mode is "both".
 *
 *   - Narrow (below Bootstrap's md breakpoint, 768 px): the menu and the
 *     conversation take turns; body.menu-visible is set while the menu is
 *     shown. "left" and "right" show one of them; in "both" the
 *     conversation is shown first, and pressing "both" again, or anything
 *     that shows the side column, gives the side column its turn.
 *   - Wide: in "both" the side column is beside the conversation, at the
 *     width the user set by dragging the border between them
 *     (#side-pane-splitter, the same for every pane, kept in localStorage);
 *     in "left" and "right" one column takes the full width and the kept
 *     width stays as it was. The width is the CSS variable --side-pane-width
 *     on the row, which the CSS uses only at 768 px and wider.
 *
 * Code that shows something in the side column for the user
 * (setMenuHidden(false)) changes "left" to "both".
 *
 * The side column holds four panes, Settings, the work screen, the shared
 * folder's files (shared-folder-panel.js) and the kept chats
 * (history-panel.js, shown while the server keeps them), behind tabs
 * (#side-pane-tabs). The page opens on Settings; the pane the user picks is
 * kept only until the page is loaded again. Which pane is shown is separate
 * from whether the column is shown. Each apply() dispatches "layoutchange"
 * on the document (the work screen follows whether it can be seen).
 */
(function() {
  'use strict';

  var COOKIE_NAME = 'layout-mode-preference';
  // Earlier versions kept whether the menu was hidden ("true" or "false").
  var OLD_COOKIE_NAME = 'menu-hidden-preference';
  var COOKIE_DAYS = 30;
  var MODES = ['both', 'left', 'right'];
  // In "both" on a narrow window: which column has its turn.
  var narrowTurn = 'main';
  var PANES = ['settings', 'work', 'files', 'history', 'library'];
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

  function readCookie(name) {
    return typeof window.getCookie === 'function' ? window.getCookie(name) : null;
  }

  function storeMode(value) {
    if (typeof window.setCookie === 'function') {
      window.setCookie(COOKIE_NAME, value, COOKIE_DAYS);
    }
  }

  // The mode the user chose, "both" until they choose; a choice kept by an
  // earlier version (whether the menu was hidden) is taken over once.
  function mode() {
    var value = readCookie(COOKIE_NAME);
    if (MODES.indexOf(value) !== -1) return value;
    var old = readCookie(OLD_COOKIE_NAME);
    if (old === 'true' || old === 'false') {
      value = old === 'true' ? 'left' : 'both';
      storeMode(value);
      if (typeof window.setCookie === 'function') window.setCookie(OLD_COOKIE_NAME, '', -1);
      return value;
    }
    return 'both';
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
    var m = mode();
    if (m === 'left') return true;
    if (m === 'right') return false;
    return isNarrow() && narrowTurn !== 'menu';
  }

  function isMainHidden() {
    var m = mode();
    if (m === 'right') return true;
    if (m === 'left') return false;
    return isNarrow() && narrowTurn === 'menu';
  }

  // Puts the DOM in the state the mode and the width call for.
  function apply() {
    var menu = $id('menu');
    var main = $id('main');
    if (!menu || !main) return;

    var m = mode();
    var menuHidden = isMenuHidden();
    applyPanes();
    applyButtons(m);

    var narrow = isNarrow();
    $toggle(menu, !menuHidden);
    $toggle(main, !isMainHidden());
    document.body.classList.toggle('menu-visible', narrow && !menuHidden);
    document.body.classList.toggle('side-pane-only', !narrow && m === 'right');
    applyWidth(narrow || m !== 'both');

    if (window.UIConfig && window.UIConfig.STATE) {
      window.UIConfig.STATE.isMenuVisible = !menuHidden;
    }
    $dispatch(document, 'layoutchange');
  }

  // The buttons of the top bar: the mode chosen is pressed.
  var buttonsBound = false;
  function applyButtons(m) {
    var group = $id('layout-mode');
    if (!group) return;
    group.querySelectorAll('[data-layout]').forEach(function(btn) {
      btn.setAttribute('aria-pressed', btn.getAttribute('data-layout') === m ? 'true' : 'false');
    });
    if (buttonsBound) return;
    buttonsBound = true;
    group.querySelectorAll('[data-layout]').forEach(function(btn) {
      if (window.MonadicTip) window.MonadicTip.attach(btn, { placement: 'bottom', delay: { show: 500, hide: 0 } });
    });
    // A button is a <button>: Enter and Space click it.
    group.addEventListener('click', function(e) {
      var btn = e.target.closest('[data-layout]');
      if (!btn || !group.contains(btn)) return;
      setMode(btn.getAttribute('data-layout'));
      $dispatch(group, 'layoutmodechosen');
    });
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
    if (!menu || !row || isNarrow() || mode() !== 'both') return null;
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
      var tabs = Array.prototype.slice.call(list.querySelectorAll('[role="tab"]:not([hidden])'));
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

  // On a narrow window, choosing "both" again gives the other column its
  // turn; choosing it from another mode starts with the conversation.
  function setMode(value) {
    if (MODES.indexOf(value) === -1) return;
    var was = mode();
    if (value === 'both' && was === 'both' && isNarrow()) {
      narrowTurn = narrowTurn === 'menu' ? 'main' : 'menu';
    } else {
      narrowTurn = 'main';
    }
    storeMode(value);
    apply();
  }

  // Shows the side column (hidden: false), as for something the user asked
  // to see there, or hides it.
  function setMenuHidden(hidden) {
    var m = mode();
    if (hidden) {
      if (isNarrow()) {
        showConversation();
        return;
      }
      if (m !== 'left') storeMode('left');
    } else {
      if (m === 'left') storeMode('both');
      if (isNarrow()) narrowTurn = 'menu';
    }
    apply();
  }

  // Shows the conversation, keeping the side column beside it where there
  // is room.
  function showConversation() {
    if (mode() === 'right') storeMode('both');
    narrowTurn = 'main';
    apply();
  }

  window.LayoutController = {
    apply: apply,
    mode: mode,
    setMode: setMode,
    isMenuHidden: isMenuHidden,
    isMainHidden: isMainHidden,
    setMenuHidden: setMenuHidden,
    showConversation: showConversation,
    selectedPane: selectedPane,
    setPane: setPane,
    sideWidth: sideWidth,
    setSideWidth: function(value) { setWidth(value, true); }
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.LayoutController;
  }
})();
