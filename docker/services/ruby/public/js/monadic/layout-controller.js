/**
 * layout-controller.js
 *
 * The one owner of the page's column layout: whether the settings column
 * (#menu) is shown next to the conversation (#main), and the classes and
 * visibility that follow from it. Other code asks it (isMenuHidden) and
 * changes it (setMenuHidden, toggleMenu, apply) instead of reading or setting
 * the DOM itself.
 *
 * What the user chose is a display preference kept in a cookie, like the
 * theme, so resetting the Web UI (which clears the page's storage) keeps it.
 * Until they choose, the menu is shown on wide screens and hidden on narrow
 * ones.
 *
 *   - Narrow (below the mobile breakpoint): the menu and the conversation take
 *     turns; body.menu-visible is set while the menu is shown.
 *   - Wide: the conversation is col-md-8 beside the menu, or col-md-12 alone.
 */
(function() {
  'use strict';

  var COOKIE_NAME = 'menu-hidden-preference';
  var COOKIE_DAYS = 30;

  function storedChoice() {
    var value = typeof window.getCookie === 'function' ? window.getCookie(COOKIE_NAME) : null;
    return value === 'true' ? true : (value === 'false' ? false : null);
  }

  function storeChoice(hidden) {
    if (typeof window.setCookie === 'function') {
      window.setCookie(COOKIE_NAME, hidden ? 'true' : 'false', COOKIE_DAYS);
    }
  }

  function isNarrow() {
    if (window.UIConfig && typeof window.UIConfig.isMobileView === 'function') {
      return window.UIConfig.isMobileView();
    }
    return window.innerWidth < 600;
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
      main.classList.toggle('col-md-8', !hidden);
      main.classList.toggle('col-md-12', hidden);
      $show(main);
      $toggle(menu, !hidden);
    }

    if (window.UIConfig && window.UIConfig.STATE) {
      window.UIConfig.STATE.isMenuVisible = !hidden;
    }
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
    toggleMenu: toggleMenu
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.LayoutController;
  }
})();
