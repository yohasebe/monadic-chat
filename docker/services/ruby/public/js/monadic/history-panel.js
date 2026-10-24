// The conversation history: the latest chats in the sidebar, and every kept
// chat in the window it shares with the shared folder, where a chat can be
// continued, named or removed. Everything goes over the tab's WebSocket; the
// server answers with headings only, never a conversation. Names and
// headings come from what people wrote, so they are always set as text.
(function () {
  'use strict';

  const RECENT = 5;
  const REFRESH_MS = 800;

  let enabled = false;
  // Whether the window is open (set when it is asked to open, before the
  // modal has finished showing, so a quick reply is not dropped).
  let windowOpen = false;
  let view = { q: '', items: [], hasMore: false };
  // The row being named or asked about, by chat id (one at a time).
  let editing = null;
  let confirmingRemove = null;
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

  function modalEl() { return $id('sharedFolderModal'); }

  function chatsShown() {
    const body = $id('history-chats-body');
    return !!(windowOpen && body && body.style.display !== 'none');
  }

  // The window shows chats or files; the shared folder reads its files when
  // their tab is first shown (it listens for this event).
  function showPane(name) {
    const pane = name === 'chats' && enabled ? 'chats' : 'files';
    $toggle($id('history-chats-body'), pane === 'chats');
    $toggle($id('shared-folder-files-body'), pane === 'files');
    document.querySelectorAll('#sharedFolderModalLabel .manage-title').forEach(function (n) {
      $toggle(n, n.getAttribute('data-pane') === pane);
    });
    document.querySelectorAll('#manage-tabs .nav-link').forEach(function (b) {
      const on = b.getAttribute('data-pane') === pane;
      b.classList.toggle('active', on);
      b.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    document.dispatchEvent(new CustomEvent('monadic:manage-pane', { detail: { pane: pane } }));
  }

  function openPanel() {
    const m = modalEl();
    if (!m || !window.bootstrap) return;
    windowOpen = true;
    showPane('chats');
    bootstrap.Modal.getOrCreateInstance(m).show();
    setStatus(t('loading', 'Loading…'));
    requestList(view.q, 0);
  }

  function setEnabled(on) {
    enabled = !!on;
    $toggle($id('history-panel'), enabled);
    $toggle($id('manage-tabs'), enabled);
    if (!enabled && chatsShown()) showPane('files');
  }

  function setStatus(text, kind, actions) {
    const box = $id('history-status');
    if (!box) return;
    box.textContent = '';
    if (!text) { $hide(box); return; }
    box.className = 'sf-status small mb-2' + (kind ? ' sf-status-' + kind : '');
    box.appendChild(el('span', null, text));
    (actions || []).forEach(function (a) { box.appendChild(document.createTextNode(' ')); box.appendChild(a); });
    $show(box);
  }

  function refreshSoon() {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(function () {
      refreshTimer = null;
      requestList('', 0);
      if (chatsShown() && view.q) requestList(view.q, 0);
    }, REFRESH_MS);
  }

  function resume(chatId, confirmed) {
    const payload = { message: 'HISTORY_RESUME', chat_id: chatId };
    if (confirmed) payload.confirm = true;
    send(payload);
  }

  function renderRecent(items) {
    const list = $id('history-recent');
    if (!list) return;
    list.textContent = '';
    const shown = items.slice(0, RECENT);
    if (shown.length === 0) {
      list.appendChild(el('li', 'small text-secondary', t('empty', 'No chats are kept yet.')));
      return;
    }
    shown.forEach(function (item) {
      const li = el('li', 'mb-1');
      const b = el('button', 'history-recent-item');
      b.type = 'button';
      b.title = item.open ? t('openHere', 'Open in a tab') : t('continueHint', 'Continue this chat in this tab');
      b.appendChild(el('span', 'history-recent-name', displayName(item)));
      if (item.heading_recent) b.appendChild(el('span', 'history-recent-topic', item.heading_recent));
      if (item.open) b.classList.add('is-open');
      b.addEventListener('click', function () { if (!item.open) resume(item.chat_id, false); });
      li.appendChild(b);
      list.appendChild(li);
    });
  }

  function nameCell(item) {
    const td = el('td', 'history-name-cell');
    if (editing === item.chat_id) {
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
          e.stopPropagation(); // the window stays open
          editing = null;
          renderTable();
        }
      });
      td.appendChild(input);
      setTimeout(function () { input.focus(); input.select(); }, 0);
      return td;
    }
    td.appendChild(el('div', 'history-name', displayName(item)));
    if (item.heading_recent) td.appendChild(el('div', 'history-topic small text-secondary', item.heading_recent));
    if (item.open) td.appendChild(el('span', 'badge history-open-badge', t('open', 'Open in a tab')));
    return td;
  }

  function actionsCell(item) {
    const td = el('td', 'text-end text-nowrap history-actions');
    if (confirmingRemove === item.chat_id) {
      td.appendChild(button('btn-danger', t('removeConfirm', 'Remove'), null, function () {
        confirmingRemove = null;
        send({ message: 'HISTORY_DELETE', chat_id: item.chat_id });
      }));
      td.appendChild(document.createTextNode(' '));
      td.appendChild(button('btn-secondary', t('cancel', 'Cancel'), null, function () { confirmingRemove = null; renderTable(); }));
      return td;
    }
    const go = button('btn-primary', t('continue', 'Continue'), t('continueHint', 'Continue this chat in this tab'),
      function () { resume(item.chat_id, false); });
    go.disabled = !!item.open;
    td.appendChild(go);
    td.appendChild(document.createTextNode(' '));
    const named = button('btn-secondary', null, t('rename', 'Name'), function () { editing = item.chat_id; confirmingRemove = null; renderTable(); });
    named.appendChild(icon('fa-solid fa-pen'));
    td.appendChild(named);
    td.appendChild(document.createTextNode(' '));
    // A chat open in a tab is not removed (the tab goes on with it); the
    // button stays, disabled, with the reason.
    const remove = button('btn-danger', null, item.open ? t('openCannotRemove', 'Open in a tab: start a new chat there to remove it') : t('remove', 'Remove from the history'),
      function () { confirmingRemove = item.chat_id; editing = null; renderTable(); });
    remove.appendChild(icon('fa-regular fa-trash-can'));
    remove.disabled = !!item.open;
    td.appendChild(remove);
    return td;
  }

  function renderTable() {
    const tbody = $id('history-tbody');
    if (!tbody) return;
    tbody.textContent = '';
    view.items.forEach(function (item) {
      const tr = el('tr');
      tr.appendChild(nameCell(item));
      tr.appendChild(el('td', 'small', appName(item.app_name)));
      tr.appendChild(el('td', 'text-end small', String(item.message_count || 0)));
      tr.appendChild(el('td', 'small text-nowrap', formatTime(item.last_activity_at)));
      tr.appendChild(actionsCell(item));
      tbody.appendChild(tr);
    });
    $toggle($id('history-more'), view.hasMore);
    const info = $id('history-info');
    if (info) info.textContent = view.items.length ? t('count', '{n} shown', { n: view.items.length + (view.hasMore ? '+' : '') }) : '';
    if (view.items.length === 0) setStatus(view.q ? t('noMatch', 'No chat matches.') : t('empty', 'No chats are kept yet.'));
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
    if (!enabled) return;
    const items = Array.isArray(data.items) ? data.items : [];
    if ((data.query || '') === '' && (data.offset || 0) === 0) renderRecent(items);
    if (!chatsShown() || (data.query || '') !== view.q) return;
    view.items = (data.offset || 0) === 0 ? items : view.items.concat(items);
    view.hasMore = !!data.has_more;
    setStatus('');
    renderTable();
  }

  function onResumed(data) {
    if (data.success || data.error === 'history_chat_here') {
      const m = modalEl();
      if (m && windowOpen && window.bootstrap) bootstrap.Modal.getOrCreateInstance(m).hide();
      refreshSoon();
      return;
    }
    if (data.error === 'history_private_here') {
      // The chat here is not kept, so continuing another one ends it.
      if (!chatsShown()) openPanel();
      setStatus(t('privateHere', 'This chat is Private and is not kept in the history. Continuing another chat ends it for good.'), 'warn', [
        button('btn-warning', t('continueAnyway', 'Continue the other chat'), null, function () { setStatus(''); resume(data.chat_id, true); }),
        button('btn-secondary', t('cancel', 'Cancel'), null, function () { setStatus(''); })
      ]);
      return;
    }
    if (chatsShown()) setStatus(errorText(data.error), 'warn');
    else if (typeof window.setAlert === 'function') window.setAlert(errorText(data.error), 'warning');
  }

  function onMessage(data) {
    if (!data || !data.type) return;
    switch (data.type) {
      case 'history_list': onList(data); break;
      case 'history_resumed': onResumed(data); break;
      case 'history_renamed':
      case 'history_deleted':
        if (!data.success && chatsShown()) setStatus(errorText(data.error), 'warn');
        requestList('', 0);
        if (chatsShown() && view.q) requestList(view.q, 0);
        break;
      default: break;
    }
  }

  function init() {
    $on($id('history-browse'), 'click', openPanel);
    document.querySelectorAll('#manage-tabs .nav-link').forEach(function (b) {
      $on(b, 'click', function () {
        const pane = b.getAttribute('data-pane');
        windowOpen = true; // the tabs are in the open window
        showPane(pane);
        if (pane === 'chats') requestList(view.q, 0);
      });
    });
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
      }, 300);
    };
    $on(search, 'input', searchSoon);
    $on(search, 'compositionend', searchSoon);
    $on(search, 'search', searchSoon);
    $on($id('history-refresh'), 'click', function () { requestList(view.q, 0); });
    $on($id('history-more'), 'click', function () { requestList(view.q, view.items.length); });
    $on(modalEl(), 'hidden.bs.modal', function () {
      windowOpen = false;
      editing = null;
      confirmingRemove = null;
      setStatus('');
      showPane('files');
    });
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { displayName: displayName, formatTime: formatTime, onMessage: onMessage, showPane: showPane };
  }
  if (typeof window !== 'undefined') {
    window.HistoryPanel = { onMessage: onMessage, refreshSoon: refreshSoon, showPane: showPane, open: openPanel };
  }
})();
