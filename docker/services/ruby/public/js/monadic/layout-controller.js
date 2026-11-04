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
 *   - Wide: the conversation is col-md-8 beside the menu, or col-md-12 alone;
 *     col-md-6 beside it while the work screen pane is shown.
 *
 * The side column holds two panes, Settings and the work screen, behind tabs
 * (#side-pane-tabs). The page opens on Settings; the pane the user picks is
 * kept only until the page is loaded again. Which pane is shown is separate
 * from whether the column is shown.
 */
(function() {
  'use strict';

  var COOKIE_NAME = 'menu-hidden-preference';
  var COOKIE_DAYS = 30;
  var PANES = ['settings', 'work'];
  var pane = 'settings';

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
    var wide = selectedPane() === 'work';
    applyPanes();
    toggleBtn.classList.toggle('menu-hidden', hidden);
    toggleBtn.setAttribute('aria-expanded', hidden ? 'false' : 'true');

    if (isNarrow()) {
      $toggle(menu, !hidden);
      $toggle(main, hidden);
      document.body.classList.toggle('menu-visible', !hidden);
      if (hidden) {
        main.classList.remove('col-md-8');
        main.classList.add('col-md-12');
      }
    } else {
      document.body.classList.remove('menu-visible');
      main.classList.toggle('col-md-12', hidden);
      main.classList.toggle('col-md-8', !hidden && !wide);
      main.classList.toggle('col-md-6', !hidden && wide);
      menu.classList.toggle('col-md-4', !wide);
      menu.classList.toggle('col-md-6', wide);
      $show(main);
      $toggle(menu, !hidden);
    }

    if (window.UIConfig && window.UIConfig.STATE) {
      window.UIConfig.STATE.isMenuVisible = !hidden;
    }
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
    setPane: setPane
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.LayoutController;
  }
})();
