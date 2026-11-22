// The tabs over the main column: "Current settings" and "Session". The
// column shows one of the two, in one of three states:
//   'none'   before a session: the settings are the whole column, and
//            "Current settings" is only its name.
//   'ready'  a chat was opened and can be continued: "Session" continues it,
//            as the button under the settings does.
//   'active' in a session: the tabs switch the column, and the conversation
//            comes back where it was scrolled to. The button under the
//            settings goes back to the conversation too.
(function () {
  'use strict';

  const VIEWS = ['settings', 'session'];
  let mode = 'none';
  let conversationScroll = 0;

  function bar() { return $id('config-summary'); }
  function tab(view) { return $id('summary-tab-' + view); }
  function locked() { return mode === 'none'; }

  function current() {
    const settings = tab('settings');
    return settings && settings.getAttribute('aria-selected') === 'true' ? 'settings' : 'session';
  }

  function mark(view) {
    VIEWS.forEach((name) => {
      const el = tab(name);
      if (!el) return;
      const selected = name === view;
      el.setAttribute('aria-selected', selected ? 'true' : 'false');
      el.tabIndex = !locked() && (selected || mode === 'ready') ? 0 : -1;
    });
  }

  function show(view) {
    const settings = view === 'settings';
    const column = $id('main');
    const configBody = $id('config-body');
    const wasSettings = current() === 'settings';
    if (settings && !wasSettings && column) conversationScroll = column.scrollTop;
    // Shown at once, with no animation, so the tab chosen last is what shows.
    $toggle(configBody, settings);
    $toggle($id('main-panel'), !settings);
    if (mode === 'active') $toggle($id('config-actions'), settings);
    mark(view);
    if (!column) return;
    if (settings) column.scrollTop = 0;
    else if (wasSettings) column.scrollTop = conversationScroll;
  }

  function setMode(next) {
    mode = next;
    const el = bar();
    if (el) el.classList.toggle('config-summary-locked', next === 'none');
    const session = tab('session');
    if (session) session.hidden = next === 'none';
    if (next !== 'active') conversationScroll = 0;
    mark(current());
  }

  // "Session" while a chat waits to be continued is the button under the
  // settings; otherwise each tab shows its view.
  function choose(name) {
    if (locked()) return;
    if (name === 'session' && mode === 'ready') {
      const start = $id('start');
      if (start) start.click();
      return;
    }
    show(name);
  }

  VIEWS.forEach((name) => {
    $on(tab(name), 'click', () => choose(name));
  });
  $on(bar(), 'keydown', (e) => {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    if (locked() || !e.target.closest('.summary-tab')) return;
    // The keys are the tabs': the page's shortcuts (→ starts voice input)
    // do not see them.
    e.preventDefault();
    e.stopPropagation();
    const next = e.target === tab('settings') ? 'session' : 'settings';
    tab(next).focus();
    if (mode === 'active') show(next);
  });

  window.MainTabs = { show, setMode, current, locked, mode: () => mode };
  if (typeof module !== 'undefined' && module.exports) module.exports = window.MainTabs;
})();
