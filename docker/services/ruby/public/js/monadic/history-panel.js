// The History tab of the side column: every kept chat, the latest first,
// searched by name and words. A click continues a chat in this tab; the
// menu of a row (⋯) names it or removes it from the history. The tab is
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
  let view = { q: '', items: [], hasMore: false };
  // The row being named or asked about, by chat id (one at a time).
  let editing = null;
  let confirmingRemove = null;
  // The chat to continue once the user confirms that the Private chat here
  // ends; the question stays while lists arrive, and goes when the tab is
  // left (it is never used for another chat).
  let confirmingResume = null;
  // The request to continue that is on its way, one at a time: { chatId,
  // live }. Leaving the tab gives it up (live false) but keeps it until its
  // answer comes, so that answer is known for what it is and asks nothing.
  // Only its answer, or a new connection (answers go to the connection that
  // asked), lets the next request go.
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

  function requestList(query, offset) {
    send({ message: 'HISTORY_LIST', query: query || '', offset: offset || 0 }, { silentDrop: true });
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
    box.appendChild(el('span', null, text));
    (actions || []).forEach(function (a) { box.appendChild(document.createTextNode(' ')); box.appendChild(a); });
    box.hidden = false;
  }

  function refreshSoon() {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(function () {
      refreshTimer = null;
      requestList(visible ? view.q : '', 0);
    }, REFRESH_MS);
  }

  // A chat is continued once the request before has been answered.
  function resume(chatId, confirmed) {
    if (resuming) return;
    const payload = { message: 'HISTORY_RESUME', chat_id: chatId };
    if (confirmed) payload.confirm = true;
    resuming = { chatId: chatId, live: true };
    if (!send(payload)) resuming = null;
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
        title: item.open ? t('openElsewhere', 'This chat is open in a tab. Start a new chat there first.') : '',
        action: function () { resume(item.chat_id, false); } },
      { label: t('rename', 'Name'), icon: 'fa-solid fa-pen',
        action: function () { editing = item.chat_id; confirmingRemove = null; render(); } },
      'divider',
      { label: t('remove', 'Remove from the history'), icon: 'fa-regular fa-trash-can', danger: true, disabled: !!item.open,
        title: item.open ? t('openCannotRemove', 'Open in a tab: start a new chat there to remove it') : '',
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

  function row(item) {
    const li = el('li', 'sfp-row history-row');
    li.dataset.chat = item.chat_id;
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
    const name = el('button', 'sfp-name history-name');
    name.type = 'button';
    name.title = item.open ? t('openHere', 'Open in a tab') : t('continueHint', 'Continue this chat in this tab');
    name.disabled = !!item.open;
    const text = el('span', 'sfp-text');
    text.appendChild(el('span', 'sfp-label', displayName(item)));
    if (item.heading_recent) text.appendChild(el('span', 'sfp-meta history-topic', item.heading_recent));
    const meta = [appName(item.app_name), t('messages', '{n} messages', { n: item.message_count || 0 }), formatTime(item.last_activity_at)]
      .filter(Boolean).join(' · ');
    text.appendChild(el('span', 'sfp-meta', meta));
    name.appendChild(text);
    if (item.open) name.appendChild(el('span', 'badge history-open-badge ms-auto', t('open', 'Open in a tab')));
    name.addEventListener('click', function () { if (!item.open) resume(item.chat_id, false); });
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

  function render() {
    const list = $id('history-list');
    if (!list) return;
    list.replaceChildren.apply(list, view.items.map(row));
    const more = $id('history-more');
    if (more) more.hidden = !view.hasMore;
    const info = $id('history-info');
    if (info) info.textContent = view.items.length ? t('count', '{n} shown', { n: view.items.length + (view.hasMore ? '+' : '') }) : '';
    if (view.items.length === 0 && !confirmingResume) {
      setStatus(view.q ? t('noMatch', 'No chat matches.') : t('empty', 'No chats are kept yet.'));
    }
  }

  function errorText(code) {
    switch (code) {
      case 'history_chat_open': return t('openElsewhere', 'This chat is open in a tab. Start a new chat there first.');
      case 'history_not_found': return t('notFound', 'This chat is no longer in the history.');
      case 'history_off': return t('off', 'The history is not kept.');
      default: return t('failed', 'That did not work. Please try again.');
    }
  }

  function onList(data) {
    setEnabled(data.enabled !== false);
    if (!enabled || !visible || (data.query || '') !== view.q) return;
    const items = Array.isArray(data.items) ? data.items : [];
    view.items = (data.offset || 0) === 0 ? items : view.items.concat(items);
    view.hasMore = !!data.has_more;
    if (!confirmingResume) setStatus('');
    render();
    if (confirmingResume) askResume(confirmingResume);
  }

  function askResume(chatId) {
    confirmingResume = chatId;
    const done = function () { confirmingResume = null; setStatus(''); render(); };
    setStatus(t('privateHere', 'This chat is Private and is not kept in the history. Continuing another chat ends it for good.'), 'warn', [
      button('btn-warning', t('continueAnyway', 'Continue the other chat'), null, function () {
        const target = confirmingResume;
        done();
        if (target === chatId) resume(chatId, true);
      }),
      button('btn-secondary', t('cancel', 'Cancel'), null, done)
    ]);
  }

  // Continued: on a narrow screen the conversation is shown (the side
  // column and the conversation take turns there).
  function onResumed(data) {
    // One request is on its way at a time on this connection, so this is
    // its answer, whatever chat it names (a failure may name none); asked:
    // that request still stands and is the one the answer is about.
    const asked = !!(resuming && resuming.live && data.chat_id === resuming.chatId);
    resuming = null;
    if (data.success || data.error === 'history_chat_here') {
      const lc = window.LayoutController;
      const narrow = window.UIConfig && typeof window.UIConfig.isTabletView === 'function' ? window.UIConfig.isTabletView() : window.innerWidth < 768;
      if (data.success && lc && narrow) lc.setMenuHidden(true);
      refreshSoon();
      return;
    }
    if (data.error === 'history_private_here') {
      // The chat here is not kept, so continuing another one ends it. Asked
      // only for the request that stands (not one given up on by leaving).
      if (!visible || !asked) return;
      askResume(data.chat_id);
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
      case 'history_renamed':
      case 'history_deleted':
        if (!data.success && visible) setStatus(errorText(data.error), 'warn');
        if (visible) requestList(view.q, 0);
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
      requestList(view.q, 0);
    } else if (!now && visible) {
      visible = false;
      editing = null;
      confirmingRemove = null;
      confirmingResume = null;
      if (resuming) resuming.live = false;
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
        requestList(view.q, 0);
      }, SEARCH_DELAY);
    };
    $on(search, 'input', searchSoon);
    $on(search, 'compositionend', searchSoon);
    $on(search, 'search', searchSoon);
    $on($id('history-refresh'), 'click', function () { requestList(view.q, 0); });
    $on($id('history-more'), 'click', function () { requestList(view.q, view.items.length); });
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
