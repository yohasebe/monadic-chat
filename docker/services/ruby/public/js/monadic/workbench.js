/**
 * The workbench in the work screen pane, and its trace in the conversation.
 *
 * The pane lists the items of the chat's workbench (the browser, and each
 * image the assistant made) and shows the one selected: for an image, the
 * image, its name and whether it was saved, with "Save to the shared
 * folder" while it is not. Each image's tab has a × that removes it from
 * the workbench. Nothing waits for an answer: an image is worked on (an
 * edit starts from the last one) and saved when the user wants to keep it.
 * The conversation shows only text: under the message that made an image,
 * one line with its name and state (the name opens the image in the pane),
 * and the names of what was saved.
 *
 * The server sends the board (`workbench`: the items, a token per image
 * for this connection, and an address for each image), the result of an
 * operation (`workbench_result`), and a message's record of what was saved
 * (`message_artifacts`). A board replaces the one before (an older
 * revision of the same board is ignored). Everything is drawn with
 * textContent from these fields; nothing in a message's text is read as a
 * record.
 *
 * A new image is selected when it arrives, and the side column switches to
 * the work screen when it is shown and the user is not typing; a column the
 * user hid is not opened. One status line outside the pane announces new
 * images and results.
 */
(function (window) {
  'use strict';

  const BROWSER = 'browser';
  const RETRY_VIEW_MS = 30000;

  let board = null;
  let approvals = {};
  let assets = {};
  let selected = BROWSER;
  // Images already seen (a new one is brought forward once).
  const seen = new Set();
  // Images removed from here: the board no longer has them; their lines say
  // so until the page is loaded again.
  const removed = new Map();
  // What each message records as saved, as last drawn.
  const records = new Map();
  // Messages that have a line, drawn again when the board changes.
  const noted = new Set();
  // One operation id per operation on an image, so the same operation sent
  // again (a retry, a reconnect) is the same operation on the server.
  const operations = new Map();
  let askedViewAt = 0;

  function t(key, fallback) {
    return typeof webUIi18n !== 'undefined' ? webUIi18n.t(key) : fallback;
  }

  function newOperationId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') return window.crypto.randomUUID();
    return `op-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }

  function items() {
    return board && Array.isArray(board.items) ? board.items : [];
  }

  function itemById(id) {
    return items().find((item) => item.id === id) || null;
  }

  function saveState(item) {
    return item && item.save ? item.save.state : null;
  }

  // Not saved, and this connection may save it.
  function savable(item) {
    return !!(item && approvals[item.id] && !item.save);
  }

  // This connection may remove it, and no save of it is under way.
  function removable(item) {
    const state = saveState(item);
    return !!(item && approvals[item.id] && (!state || state === 'recorded'));
  }

  function stateText(item) {
    const state = saveState(item);
    if (state === 'recorded') return t('ui.workbench.saved', 'Saved to the shared folder');
    if (state) return t('ui.workbench.saving', 'Saving…');
    return t('ui.workbench.notSaved', 'Not saved');
  }

  function announce(text) {
    const el = $id('workbench-status');
    if (el) el.textContent = text;
  }

  function typing() {
    const el = document.activeElement;
    if (!el) return false;
    if (el.isContentEditable || el.tagName === 'TEXTAREA') return true;
    return el.tagName === 'INPUT' && !['button', 'checkbox', 'radio', 'submit'].includes(el.type);
  }

  // ---- the pane ------------------------------------------------------

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  function button(label, className, onClick) {
    const el = element('button', `btn btn-sm ${className}`, label);
    el.type = 'button';
    el.addEventListener('click', onClick);
    return el;
  }

  // A long name with its start and its end kept (names often differ only
  // near the end).
  function shortName(name) {
    const text = String(name || '');
    return text.length <= 24 ? text : `${text.slice(0, 9)}…${text.slice(-13)}`;
  }

  function operate(item, action) {
    const token = approvals[item.id];
    if (!token || typeof window.safeWsSend !== 'function') return;
    const key = `${item.id}:${item.sha256}:${action}`;
    if (!operations.has(key)) operations.set(key, newOperationId());
    window.safeWsSend({
      message: 'WORKBENCH_ACTION', item_id: item.id, action: action, token: token,
      operation_id: operations.get(key)
    }, { idempotent: true });
  }

  function tab(id, label) {
    const wrap = element('span', 'workbench-item-wrap');
    const el = element('button', 'workbench-item');
    el.type = 'button';
    el.setAttribute('role', 'tab');
    el.setAttribute('aria-selected', id === selected ? 'true' : 'false');
    el.dataset.item = id;
    el.title = label;
    el.appendChild(element('span', 'workbench-item-name', id === BROWSER ? label : shortName(label)));
    el.addEventListener('click', () => select(id));
    wrap.appendChild(el);
    const item = itemById(id);
    if (removable(item)) {
      const close = element('button', 'workbench-item-remove', '×');
      close.type = 'button';
      close.title = t('ui.workbench.remove', 'Remove from the work screen');
      close.setAttribute('aria-label', `${close.title}: ${label}`);
      close.addEventListener('click', (e) => {
        e.currentTarget.disabled = true;
        operate(item, 'remove');
      });
      wrap.appendChild(close);
    }
    return wrap;
  }

  function drawList() {
    const list = $id('workbench-items');
    if (!list) return;
    list.replaceChildren();
    const shown = items().filter((item) => item.kind === 'image');
    list.hidden = shown.length === 0;
    if (list.hidden) return;
    list.appendChild(tab(BROWSER, t('ui.workbench.browser', 'Browser')));
    shown.forEach((item) => list.appendChild(tab(item.id, item.name || '')));
  }

  // The board as it is now, with new addresses (an address is short-lived);
  // asking also takes up a save that stopped. now: the user asked.
  function askView(now) {
    const at = Date.now();
    if ((!now && at - askedViewAt < RETRY_VIEW_MS) || typeof window.safeWsSend !== 'function') return;
    askedViewAt = at;
    window.safeWsSend({ message: 'WORKBENCH_VIEW' }, { idempotent: true, silentDrop: true });
  }

  function drawView() {
    const browserArea = $id('work-screen-browser');
    const view = $id('workbench-view');
    const item = selected === BROWSER ? null : itemById(selected);
    if (browserArea) browserArea.hidden = !!item;
    if (!view) return;
    view.hidden = !item;
    view.replaceChildren();
    if (!item) return;
    view.dataset.item = item.id;
    if (assets[item.id]) {
      const img = element('img', 'workbench-image rounded');
      img.alt = item.name || '';
      img.addEventListener('error', () => askView(false));
      img.src = assets[item.id];
      view.appendChild(img);
    }
    const line = element('div', 'small text-secondary mt-2');
    line.appendChild(element('code', null, (item.save && item.save.name) || item.name || ''));
    line.appendChild(document.createTextNode(` — ${stateText(item)}`));
    view.appendChild(line);
    const state = saveState(item);
    if (state && state !== 'recorded') {
      // A save that stopped part way: asking for the board takes it up again.
      view.appendChild(button(t('ui.workbench.retry', 'Try again'), 'btn-outline-secondary mt-2', () => askView(true)));
    }
    if (savable(item)) {
      view.appendChild(button(t('ui.workbench.save', 'Save to the shared folder'), 'btn-primary mt-2', (e) => {
        e.currentTarget.disabled = true;
        operate(item, 'save');
      }));
    }
  }

  // ---- the conversation ----------------------------------------------

  function drawNote(mid) {
    const card = mid ? $id(mid) : null;
    const text = card ? card.querySelector('.card-text') : null;
    if (!text) return;
    let el = text.querySelector(':scope > .workbench-note');
    const lines = [];
    const savedNames = new Set();
    items().filter((item) => item.mid === mid).forEach((item) => {
      if (item.save && item.save.name) savedNames.add(item.save.name);
      lines.push({ name: (item.save && item.save.name) || item.name || '', state: stateText(item), id: item.id });
    });
    removed.forEach((entry, id) => {
      if (entry.mid === mid && !itemById(id)) {
        lines.push({ name: entry.name, state: t('ui.workbench.removed', 'Removed from the work screen') });
      }
    });
    (records.get(mid) || []).forEach((entry) => {
      const name = entry && entry.name ? String(entry.name) : '';
      if (name && !savedNames.has(name)) lines.push({ name: name, state: t('ui.workbench.record', 'Saved'), saved: true });
    });
    if (lines.length === 0) {
      if (el) el.remove();
      noted.delete(mid);
      return;
    }
    if (!el) {
      el = element('div', 'workbench-note small text-secondary mt-2');
      text.appendChild(el);
    }
    noted.add(mid);
    el.replaceChildren();
    lines.forEach((entry) => {
      const line = element('div', 'workbench-note-line');
      line.appendChild(element('i', `fa-solid ${entry.saved ? 'fa-floppy-disk' : 'fa-image'} me-1`));
      if (entry.id) {
        const open = element('button', 'btn btn-link btn-sm p-0 align-baseline workbench-open');
        open.type = 'button';
        open.title = t('ui.workbench.open', 'Show in the work screen');
        open.appendChild(element('code', null, entry.name));
        open.addEventListener('click', () => openItem(entry.id));
        line.appendChild(open);
      } else {
        line.appendChild(element('code', null, entry.name));
      }
      line.appendChild(document.createTextNode(` — ${entry.state}`));
      el.appendChild(line);
    });
  }

  function drawNotes() {
    const mids = new Set([...noted, ...records.keys()]);
    items().forEach((item) => { if (item.mid) mids.add(item.mid); });
    removed.forEach((entry) => mids.add(entry.mid));
    mids.forEach(drawNote);
  }

  function draw() {
    drawList();
    drawView();
    drawNotes();
  }

  // ---- selection -----------------------------------------------------

  function refreshRelay() {
    if (window.WorkScreen && typeof window.WorkScreen.refresh === 'function') window.WorkScreen.refresh();
  }

  function select(id) {
    selected = id === BROWSER || itemById(id) ? id : BROWSER;
    draw();
    refreshRelay();
  }

  // From a line in the conversation: the user asked for it, so the side
  // column is shown.
  function openItem(id) {
    const lc = window.LayoutController;
    if (lc) {
      if (lc.isMenuHidden()) lc.setMenuHidden(false);
      if (lc.selectedPane() !== 'work') lc.setPane('work');
    }
    select(id);
  }

  // A new image: it is selected and the work screen is shown when the
  // column is, unless the user is typing (then only the announcement says
  // so).
  function bringForward(item) {
    if (typing()) return;
    selected = item.id;
    const lc = window.LayoutController;
    if (lc && !lc.isMenuHidden() && lc.selectedPane() !== 'work') lc.setPane('work');
  }

  function reset() {
    board = null;
    approvals = {};
    assets = {};
    selected = BROWSER;
    seen.clear();
    removed.clear();
    operations.clear();
    records.clear();
    noted.clear();
    // What was drawn for the chat before goes; what the chat now shown
    // records as saved is drawn again from its messages.
    document.querySelectorAll('.workbench-note').forEach((el) => el.remove());
    const messages = window.SessionState && typeof window.SessionState.getMessages === 'function'
      ? window.SessionState.getMessages() : [];
    (Array.isArray(messages) ? messages : []).forEach((m) => {
      if (m && m.mid && Array.isArray(m.artifacts)) records.set(m.mid, m.artifacts);
    });
  }

  // ---- messages from the server --------------------------------------

  function onView(data) {
    const next = data && data.board;
    if (!next || !Array.isArray(next.items)) return;
    if (board && next.chat_id === board.chat_id && next.board_id && next.board_id === board.board_id &&
        next.revision < board.revision) return;
    if (board && next.chat_id !== board.chat_id) reset();
    const before = items().map((item) => item.id);
    board = next;
    approvals = data.approvals || {};
    assets = data.assets || {};
    const news = [];
    if (selected !== BROWSER && !itemById(selected)) selected = BROWSER;
    const arrived = items().filter((item) => item.kind === 'image' && !seen.has(item.id));
    arrived.forEach((item) => seen.add(item.id));
    // The board a connection is sent first (a reload, a reconnect) brings
    // nothing forward: none of it is new to the user.
    if (arrived.length > 0 && !data.initial) {
      news.push(t('ui.workbench.announceNew', 'A new image is in the work screen.'));
      bringForward(arrived[arrived.length - 1]);
    }
    // Images the board put away to make room (not removed here).
    if (before.some((id) => !itemById(id) && !removed.has(id))) {
      news.push(t('ui.workbench.putAway', 'An older image was removed from the work screen.'));
    }
    if (news.length > 0) announce(news.join(' '));
    draw();
    refreshRelay();
  }

  function onResult(data) {
    if (!data) return;
    const done = ['accepted', 'same', 'taken'].includes(data.status);
    if (data.action === 'remove' && done) {
      const item = itemById(data.item_id);
      if (item) removed.set(item.id, { mid: item.mid, name: item.name || '' });
      announce(t('ui.workbench.removed', 'Removed from the work screen'));
      return;
    }
    if (data.action === 'save' && done && data.state === 'recorded') {
      announce(`${t('ui.workbench.saved', 'Saved to the shared folder')}: ${data.name || ''}`);
      return;
    }
    if (data.status !== 'refused' && data.status !== 'incomplete') return;
    const message = data.status === 'incomplete'
      ? t('ui.workbench.failed', 'Could not save. Try again.')
      : t('ui.workbench.refused', 'This was not accepted.');
    announce(message);
    if (typeof window.setAlert === 'function') window.setAlert(message, 'warning');
  }

  // What a message records as saved (from the server, or with the message).
  function drawRecord(mid, artifacts) {
    if (!mid || !Array.isArray(artifacts)) return;
    records.set(mid, artifacts);
    drawNote(mid);
  }

  function onArtifacts(data) {
    if (!data || !data.mid) return;
    if (board && data.chat_id && data.chat_id !== board.chat_id) return;
    const messages = window.SessionState && typeof window.SessionState.getMessages === 'function'
      ? window.SessionState.getMessages() : null;
    const message = Array.isArray(messages) ? messages.find((m) => m && m.mid === data.mid) : null;
    if (message) message.artifacts = data.artifacts;
    drawRecord(data.mid, data.artifacts);
  }

  window.Workbench = {
    onView, onResult, onArtifacts, drawRecord, select,
    // Whether the pane shows the browser (the relay runs only then).
    showsBrowser: () => selected === BROWSER
  };
})(window);
