// The History tab of the side column: every kept chat, the latest first,
// searched by name and words and narrowed by app and by when it was last
// used. A click continues a chat in this tab; the menu of a row (⋯) names it
// or removes it from the history; chats selected by their boxes are removed
// together. The tab is
// there only while the server keeps a history. Everything goes over the
// tab's WebSocket; the server answers with headings only, never a
// conversation. Names and headings come from what people wrote, so they are
// always set as text.
(function () {
  'use strict';

  const REFRESH_MS = 800;
  const SEARCH_DELAY = 300;

  let enabled = false;
  let visible = false;
  // How long a chat was not used, in days, that the list can be narrowed by
  // (the server takes these only).
  const UNUSED = [[30, 'unused30', 'Not used in 30 days'], [90, 'unused90', 'Not used in 90 days'],
    [365, 'unused365', 'Not used in 365 days']];

  function unusedText(days) {
    const entry = UNUSED.find(function (u) { return u[0] === days; });
    return entry ? t(entry[1], entry[2]) : '';
  }
  let view = { q: '', app: '', unused: null, items: [], hasMore: false, apps: [] };
  // The chats selected by their boxes, by chat id, and whether removing
  // them is being asked about.
  let selected = new Set();
  let confirmingSelected = false;
  // The row being named or asked about, by chat id (one at a time).
  let editing = null;
  let confirmingRemove = null;
  // Whether a request to continue is on its way (one at a time). Only its
  // answer, or a new connection (answers go to the connection that asked),
  // lets the next request go.
  let resuming = null;
  let refreshTimer = null;
  let searchTimer = null;

  function t(key, fallback, vars) {
    let text = fallback;
    try {
      if (typeof webUIi18n !== 'undefined') {
        const v = webUIi18n.t('ui.historyPanel.' + key);
        if (v && v !== 'ui.historyPanel.' + key) text = v;
      }
    } catch (_) { /* fall back */ }
    if (vars) Object.keys(vars).forEach(function (k) { text = text.split('{' + k + '}').join(String(vars[k])); });
    return text;
  }

  function displayName(item) {
    return (item && (item.title_user || item.heading_first)) || t('untitled', 'Untitled chat');
  }

  // Apps of different providers share display names ("Chat"), so the
  // provider is added.
  function appName(id) {
    const app = window.apps && window.apps[id];
    if (!app) return id || '';
    const name = app.display_name || app.app_name || id;
    return app.group ? name + ' (' + app.group + ')' : name;
  }

  function formatTime(iso) {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    const lang = (typeof webUIi18n !== 'undefined' && webUIi18n.currentLanguage) || undefined;
    try { return d.toLocaleString(lang, { dateStyle: 'medium', timeStyle: 'short' }); } catch (_) { return d.toLocaleString(); }
  }

  function el(tag, cls, text) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  function button(cls, label, title, onClick) {
    const b = el('button', 'btn btn-sm ' + cls);
    b.type = 'button';
    if (label) b.textContent = label;
    if (title) { b.title = title; b.setAttribute('aria-label', title); }
    if (onClick) b.addEventListener('click', onClick);
    return b;
  }

  function icon(cls) {
    const i = el('i', cls);
    i.setAttribute('aria-hidden', 'true');
    return i;
  }

  function send(payload, opts) {
    if (typeof window.safeWsSend !== 'function') return false;
    const r = window.safeWsSend(payload, opts);
    return !!(r && (r.sent || r.queued));
  }

  // A request for another chat (window.sendChatSwitch).
  function sendSwitch(payload) {
    if (typeof window.sendChatSwitch !== 'function') return send(payload);
    const r = window.sendChatSwitch(payload);
    return !!(r && (r.sent || r.queued));
  }

  function requestList(offset) {
    send({ message: 'HISTORY_LIST', query: view.q, app: view.app, unused_days: view.unused, offset: offset || 0 },
      { silentDrop: true });
  }

  // The search or a filter changed: what was selected may no longer be shown.
  function listChanged() {
    selected = new Set();
    confirmingSelected = false;
    requestList(0);
  }

  // The tab is there only while the server keeps a history; a tab hidden
  // while it is shown gives way to the menu.
  function setEnabled(on) {
    enabled = !!on;
    const tab = $id('side-tab-history');
    if (tab) tab.hidden = !enabled;
    const lc = window.LayoutController;
    if (!enabled && lc && lc.selectedPane() === 'history') lc.setPane('settings');
  }

  function setStatus(text, kind, actions) {
    const box = $id('history-status');
    if (!box) return;
    box.textContent = '';
    if (!text) { box.hidden = true; return; }
    box.className = 'sfp-status history-status mb-2' + (kind === 'warn' ? ' sfp-status-warn' : '');
    if (kind === 'busy') box.appendChild(el('i', 'fas fa-spinner fa-spin'));
    box.appendChild(el('span', null, text));
    (actions || []).forEach(function (a) { box.appendChild(document.createTextNode(' ')); box.appendChild(a); });
    box.hidden = false;
  }

  function refreshSoon() {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(function () {
      refreshTimer = null;
      requestList(0);
    }, REFRESH_MS);
  }

  // A chat is continued once the request before has been answered.
  function resume(chatId) {
    if (resuming) return;
    const payload = { message: 'HISTORY_RESUME', chat_id: chatId };
    resuming = true;
    if (sendSwitch(payload)) setStatus(t('opening', 'Opening the chat…'), 'busy');
    else resuming = null;
  }

  // The menu of a row.
  // The focus back on the chat's row (drawn anew), or on the list.
  function focusChat(chatId) {
    const li = Array.prototype.find.call(document.querySelectorAll('#history-list .history-row'),
      function (r) { return r.dataset.chat === chatId; });
    const target = li ? li.querySelector('.history-name:not(:disabled), .sfp-row-menu') : $id('history-search');
    if (target && typeof target.focus === 'function') target.focus({ preventScroll: true });
  }

  function rowMenu(item, more) {
    if (!window.RowMenu) return;
    window.RowMenu.open(more, [
      { label: t('continue', 'Continue'), icon: 'fa-solid fa-arrow-right', disabled: !!item.open,
        title: item.open && !item.here ? t('openElsewhere', 'This chat is open in another window. Start a new chat there first.') : '',
        action: function () { resume(item.chat_id); } },
      { label: t('rename', 'Name'), icon: 'fa-solid fa-pen',
        action: function () { editing = item.chat_id; confirmingRemove = null; render(); } },
      'divider',
      { label: t('remove', 'Remove from the history'), icon: 'fa-regular fa-trash-can', danger: true, disabled: !!item.open,
        title: item.open ? t('openCannotRemove', 'Open in a window: start a new chat there to remove it') : '',
        action: function () { confirmingRemove = item.chat_id; editing = null; render(); } }
    ], { restore: function () { focusChat(item.chat_id); } });
  }

  function nameEditor(item) {
    const input = el('input', 'form-control form-control-sm');
    input.type = 'text';
    input.maxLength = 120;
    input.value = item.title_user || '';
    input.placeholder = item.heading_first || '';
    input.setAttribute('aria-label', t('rename', 'Name'));
    input.addEventListener('keydown', function (e) {
      if (e.isComposing) return;
      if (e.key === 'Enter') {
        e.preventDefault();
        editing = null;
        send({ message: 'HISTORY_RENAME', chat_id: item.chat_id, title: input.value });
      } else if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        editing = null;
        render();
      }
    });
    setTimeout(function () { input.focus(); input.select(); }, 0);
    return input;
  }

  function selectable(item) {
    return !item.open;
  }

  function checkBox(item) {
    if (!selectable(item)) return el('span', 'sfp-check sfp-check-none');
    const on = selected.has(item.chat_id);
    const box = el('button', 'sfp-check');
    box.type = 'button';
    box.setAttribute('role', 'checkbox');
    box.setAttribute('aria-checked', String(on));
    box.setAttribute('aria-label', t('selectOne', 'Select {name}', { name: displayName(item) }));
    box.appendChild(icon(on ? 'fa-solid fa-square-check' : 'fa-regular fa-square'));
    box.addEventListener('click', function () {
      if (selected.has(item.chat_id)) selected.delete(item.chat_id); else selected.add(item.chat_id);
      confirmingSelected = false;
      render();
    });
    return box;
  }

  function row(item) {
    const li = el('li', 'sfp-row history-row');
    li.dataset.chat = item.chat_id;
    if (selected.has(item.chat_id)) li.classList.add('sfp-selected');
    if (item.here) li.classList.add('history-here');
    if (editing === item.chat_id) {
      li.appendChild(nameEditor(item));
      return li;
    }
    if (confirmingRemove === item.chat_id) {
      li.appendChild(el('span', 'history-confirm-text small', t('removeAsk', 'Remove “{name}” from the history?', { name: displayName(item) })));
      li.appendChild(button('btn-danger ms-auto', t('removeConfirm', 'Remove'), null, function () {
        confirmingRemove = null;
        send({ message: 'HISTORY_DELETE', chat_id: item.chat_id });
      }));
      li.appendChild(button('btn-secondary ms-1', t('cancel', 'Cancel'), null, function () { confirmingRemove = null; render(); }));
      return li;
    }
    li.appendChild(checkBox(item));
    const name = el('button', 'sfp-name history-name');
    name.type = 'button';
    if (item.here) name.title = t('hereHint', 'This is the chat shown now');
    else name.title = item.open ? t('openElsewhere', 'This chat is open in another window. Start a new chat there first.')
      : t('continueHint', 'Continue this chat in this tab');
    name.disabled = !!item.open;
    const text = el('span', 'sfp-text');
    text.appendChild(el('span', 'sfp-label', displayName(item)));
    if (item.heading_recent) text.appendChild(el('span', 'sfp-meta history-topic', item.heading_recent));
    const meta = [appName(item.app_name), t('messages', '{n} messages', { n: item.message_count || 0 }), formatTime(item.last_activity_at)]
      .filter(Boolean).join(' · ');
    text.appendChild(el('span', 'sfp-meta', meta));
    name.appendChild(text);
    if (item.open) {
      name.appendChild(el('span', 'mc-badge ' + (item.here ? 'mc-badge--blue' : 'mc-badge--grey') + ' history-open-badge ms-auto',
        item.here ? t('here', 'Shown now') : t('open', 'Open in another window')));
    }
    name.addEventListener('click', function () { if (!item.open) resume(item.chat_id); });
    li.appendChild(name);
    const more = el('button', 'btn btn-sm sfp-row-menu');
    more.type = 'button';
    more.appendChild(icon('fa-solid fa-ellipsis'));
    more.setAttribute('aria-label', t('actionsOf', 'Actions for {name}', { name: displayName(item) }));
    more.setAttribute('aria-haspopup', 'menu');
    more.setAttribute('aria-expanded', 'false');
    more.addEventListener('click', function () { rowMenu(item, more); });
    li.appendChild(more);
    return li;
  }

  function filterLabel() {
    const parts = [];
    if (view.app) parts.push(appName(view.app));
    if (view.unused) parts.push(unusedText(view.unused));
    return parts.join(' · ');
  }

  // The bands above the list: what it is narrowed by, and what is selected.
  function renderBands() {
    const narrowed = !!(view.app || view.unused);
    const filtering = $id('history-filtering');
    if (filtering) filtering.hidden = !narrowed;
    const what = $id('history-filtering-text');
    if (what) what.textContent = t('filteringBy', 'Narrowed by: {what}', { what: filterLabel() });
    const filterBtn = $id('history-filter-toggle');
    if (filterBtn) filterBtn.classList.toggle('sfp-on', narrowed);
    const band = $id('history-selection');
    if (!band) return;
    const count = selected.size;
    band.hidden = count === 0;
    const text = $id('history-selection-text');
    if (text) {
      text.textContent = confirmingSelected
        ? t('removeSelectedAsk', 'Remove {n} chats from the history?', { n: count })
        : t('selected', 'Selected: {n}', { n: count });
    }
    const label = $id('history-remove-label');
    if (label) {
      label.textContent = confirmingSelected ? t('removeConfirm', 'Remove')
        : t('removeSelected', 'Remove {n} from the history', { n: count });
    }
  }

  function selectAllShown() {
    view.items.forEach(function (item) { if (selectable(item)) selected.add(item.chat_id); });
    confirmingSelected = false;
    render();
  }

  function clearSelection() {
    selected = new Set();
    confirmingSelected = false;
    render();
  }

  function removeSelected() {
    if (selected.size === 0) return;
    if (!confirmingSelected) {
      confirmingSelected = true;
      renderBands();
      return;
    }
    const ids = Array.from(selected);
    confirmingSelected = false;
    if (send({ message: 'HISTORY_DELETE', chat_ids: ids })) setStatus(t('loading', 'Loading…'), 'busy');
  }

  function selectMenu(button) {
    if (!window.RowMenu) return;
    window.RowMenu.open(button, [
      { label: t('selectAll', 'Select all shown'), icon: 'fa-regular fa-square-check', action: selectAllShown,
        disabled: !view.items.some(selectable) },
      { label: t('clearSelection', 'Clear selection'), icon: 'fa-solid fa-xmark', action: clearSelection,
        disabled: selected.size === 0 }
    ]);
  }

  // The filters (which app, how long unused), changed at once.
  function filterPanel(button) {
    if (!window.RowMenu) return;
    const form = el('form', 'sfp-filter-form');
    form.addEventListener('submit', function (e) { e.preventDefault(); });
    const app = el('select', 'form-select form-select-sm');
    app.id = 'history-filter-app';
    const all = el('option', null, t('appAll', 'All apps'));
    all.value = '';
    app.appendChild(all);
    view.apps.forEach(function (name) {
      const o = el('option', null, appName(name));
      o.value = name;
      app.appendChild(o);
    });
    app.value = view.app;
    const unused = el('select', 'form-select form-select-sm');
    unused.id = 'history-filter-unused';
    const any = el('option', null, t('unusedAll', 'Any time'));
    any.value = '';
    unused.appendChild(any);
    UNUSED.forEach(function (entry) {
      const o = el('option', null, t(entry[1], entry[2]));
      o.value = String(entry[0]);
      unused.appendChild(o);
    });
    unused.value = view.unused ? String(view.unused) : '';
    const appLabel = el('label', 'form-label mb-1', t('appLabel', 'App'));
    appLabel.htmlFor = app.id;
    const unusedLabel = el('label', 'form-label mb-1 mt-2', t('unusedLabel', 'Last used'));
    unusedLabel.htmlFor = unused.id;
    form.append(appLabel, app, unusedLabel, unused);
    app.addEventListener('change', function () { view.app = app.value; renderBands(); listChanged(); });
    unused.addEventListener('change', function () {
      view.unused = unused.value ? Number(unused.value) : null;
      renderBands();
      listChanged();
    });
    window.RowMenu.openPanel(button, form);
  }

  function clearFilters() {
    view.app = '';
    view.unused = null;
    renderBands();
    listChanged();
  }

  function render() {
    const list = $id('history-list');
    if (!list) return;
    // What is selected stays selected only while it is shown and can be.
    const shown = new Set(view.items.filter(selectable).map(function (item) { return item.chat_id; }));
    selected.forEach(function (id) { if (!shown.has(id)) selected.delete(id); });
    if (selected.size === 0) confirmingSelected = false;
    renderBands();
    list.replaceChildren.apply(list, view.items.map(row));
    const more = $id('history-more');
    if (more) more.hidden = !view.hasMore;
    const info = $id('history-info');
    if (info) info.textContent = view.items.length ? t('count', '{n} shown', { n: view.items.length + (view.hasMore ? '+' : '') }) : '';
    if (view.items.length === 0) {
      setStatus(view.q ? t('noMatch', 'No chat matches.') : t('empty', 'No chats are kept yet.'));
    }
  }

  function errorText(code) {
    switch (code) {
      case 'history_chat_open': return t('openElsewhere', 'This chat is open in another window. Start a new chat there first.');
      case 'history_not_found': return t('notFound', 'This chat is no longer in the history.');
      case 'history_off': return t('off', 'The history is not kept.');
      default: return t('failed', 'That did not work. Please try again.');
    }
  }

  function onList(data) {
    setEnabled(data.enabled !== false);
    if (!enabled || !visible || (data.query || '') !== view.q) return;
    if ((data.app || '') !== view.app || (data.unused_days || null) !== view.unused) return;
    view.apps = Array.isArray(data.apps) ? data.apps : [];
    const items = Array.isArray(data.items) ? data.items : [];
    view.items = (data.offset || 0) === 0 ? items : view.items.concat(items);
    view.hasMore = !!data.has_more;
    setStatus('');
    render();
  }

  // Continued: on a narrow screen the conversation is shown (the side
  // column and the conversation take turns there).
  function onResumed(data) {
    // One request is on its way at a time on this connection, so this is
    // its answer, whatever chat it names (a failure may name none).
    resuming = null;
    setStatus('');
    if (data.success || data.error === 'history_chat_here') {
      const lc = window.LayoutController;
      const narrow = window.UIConfig && typeof window.UIConfig.isTabletView === 'function' ? window.UIConfig.isTabletView() : window.innerWidth < 768;
      if (data.success && lc && narrow) lc.setMenuHidden(true);
      if (data.success && window.Workbench && typeof window.Workbench.expectResumed === 'function') {
        window.Workbench.expectResumed(data.chat_id);
      }
      refreshSoon();
      return;
    }
    if (visible) setStatus(errorText(data.error), 'warn');
    else if (typeof window.setAlert === 'function') window.setAlert(errorText(data.error), 'warning');
  }

  function onMessage(data) {
    if (!data || !data.type) return;
    switch (data.type) {
      case 'history_list': onList(data); break;
      case 'history_resumed': onResumed(data); break;
      case 'history_deleted':
        if (Array.isArray(data.chat_ids)) {
          setStatus('');
          selected = new Set();
          confirmingSelected = false;
          renderBands();
          const failed = Object.keys(data.failed || {}).length;
          if (failed && visible) setStatus(t('removedSome', '{n} could not be removed.', { n: failed }), 'warn');
          if (visible) requestList(0);
          break;
        }
        if (!data.success && visible) setStatus(errorText(data.error), 'warn');
        if (visible) requestList(0);
        break;
      case 'history_renamed':
        if (!data.success && visible) setStatus(errorText(data.error), 'warn');
        if (visible) requestList(0);
        break;
      default: break;
    }
  }

  // The tab is read when it comes into view; what was being asked or
  // edited there goes when it is left.
  function onLayout() {
    const lc = window.LayoutController;
    const now = !!(lc && lc.selectedPane() === 'history' && !lc.isMenuHidden());
    if (now && !visible) {
      visible = true;
      requestList(0);
    } else if (!now && visible) {
      visible = false;
      editing = null;
      confirmingRemove = null;
      confirmingSelected = false;
      setStatus('');
      if (window.RowMenu) window.RowMenu.close();
    }
  }

  function init() {
    // The box is read when the pause is over, not when a key is typed: with
    // an input method the last event can carry text that is no longer there.
    const search = $id('history-search');
    const searchSoon = function (e) {
      clearTimeout(searchTimer);
      if (e && e.isComposing) return;
      searchTimer = setTimeout(function () {
        searchTimer = null;
        view.q = (search.value || '').trim();
        listChanged();
      }, SEARCH_DELAY);
    };
    $on(search, 'input', searchSoon);
    $on(search, 'compositionend', searchSoon);
    $on(search, 'search', searchSoon);
    $on($id('history-refresh'), 'click', function () { requestList(0); });
    $on($id('history-filter-toggle'), 'click', function (e) { filterPanel(e.currentTarget); });
    $on($id('history-select-menu'), 'click', function (e) { selectMenu(e.currentTarget); });
    $on($id('history-filtering-clear'), 'click', clearFilters);
    $on($id('history-clear-selection'), 'click', clearSelection);
    $on($id('history-remove-selected'), 'click', removeSelected);
    $on($id('history-more'), 'click', function () { requestList(view.items.length); });
    document.addEventListener('layoutchange', onLayout);
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
  }

  // A new connection: no answer can come to what the one before asked.
  function connectionOpened() {
    resuming = null;
  }

  const api = { onMessage: onMessage, refreshSoon: refreshSoon, connectionOpened: connectionOpened };
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = Object.assign({ displayName: displayName, formatTime: formatTime }, api);
  }
  if (typeof window !== 'undefined') window.HistoryPanel = api;
})();
