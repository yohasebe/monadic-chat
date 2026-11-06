/**
 * The workbench in the work screen pane, and its trace in the conversation.
 *
 * The pane lists the items of the chat's workbench (the browser, and each
 * image the assistant made) and shows the one selected: for an image, the
 * image, its path in the shared folder (every image is kept in the chat's
 * folder there), and "Save as…" (in the desktop app; "Download" in a
 * browser) to save a copy elsewhere. Each image's tab has a × that takes
 * it off the workbench; the file stays in the shared folder. An image
 * whose file changed or is gone since it was made is not shown: the pane
 * says which.
 *
 * The conversation shows only text: under the message that made an image,
 * one line with its path (which shows the image in the pane while it is on
 * the workbench) and its "Save as…". The line comes from the message's
 * record (`artifacts`), so it stays after the image leaves the workbench.
 *
 * The server sends the board (`workbench`: the items, a token per image
 * for this connection, and an address for each image), the result of a
 * removal (`workbench_result`), and an address to save an image from
 * (`workbench_download`). A board replaces the one before (an older
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
  // Images removed from here (not put away by the board to make room).
  const removed = new Set();
  // What each message records as made, as last drawn.
  const records = new Map();
  // One operation id per removal, so the same removal sent again (a retry,
  // a reconnect) is the same operation on the server.
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

  function itemOfArtifact(artifactId) {
    return items().find((item) => item.artifact_id === artifactId) || null;
  }

  function announce(text) {
    const el = $id('workbench-status');
    if (el) el.textContent = text;
  }

  function warn(text) {
    announce(text);
    if (typeof window.setAlert === 'function') window.setAlert(text, 'warning');
  }

  function typing() {
    const el = document.activeElement;
    if (!el) return false;
    if (el.isContentEditable || el.tagName === 'TEXTAREA') return true;
    return el.tagName === 'INPUT' && !['button', 'checkbox', 'radio', 'submit'].includes(el.type);
  }

  // "Save as…" in the desktop app (it asks where to save); "Download" in a
  // browser.
  function saveLabel() {
    return window.electronAPI ? t('ui.workbench.saveAs', 'Save as…') : t('ui.workbench.download', 'Download');
  }

  function statusText(status) {
    if (status === 'changed') return t('ui.workbench.changed', 'This file changed in the shared folder after it was made.');
    if (status === 'missing') return t('ui.workbench.missing', 'This file is no longer in the shared folder.');
    return '';
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

  // A name without the time it starts with (the tab's title has it), and
  // when long, with its start and its end kept (names often differ only
  // near the end).
  function shortName(name) {
    const text = String(name || '').replace(/^\d{8}-\d{6}_/, '');
    return text.length <= 24 ? text : `${text.slice(0, 9)}…${text.slice(-13)}`;
  }

  function remove(item) {
    const token = approvals[item.id];
    if (!token || typeof window.safeWsSend !== 'function') return;
    const key = `${item.id}:${item.sha256}`;
    if (!operations.has(key)) operations.set(key, newOperationId());
    window.safeWsSend({
      message: 'WORKBENCH_ACTION', item_id: item.id, action: 'remove', token: token,
      operation_id: operations.get(key)
    }, { idempotent: true });
  }

  // Asks the server for an address to save the image from; the file is
  // fetched when it comes (onDownload), so a failure never leaves the page.
  function download(artifactId) {
    if (!artifactId || typeof window.safeWsSend !== 'function') return;
    window.safeWsSend({ message: 'WORKBENCH_DOWNLOAD', artifact_id: artifactId });
  }

  function saveButton(artifactId, className) {
    return button(saveLabel(), className, () => download(artifactId));
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
    if (item && approvals[item.id]) {
      const close = element('button', 'workbench-item-remove', '×');
      close.type = 'button';
      close.title = t('ui.workbench.remove', 'Remove from the work screen');
      close.setAttribute('aria-label', `${close.title}: ${label}`);
      close.addEventListener('click', (e) => {
        e.currentTarget.disabled = true;
        remove(item);
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

  // The board as it is now, with new addresses (an address is
  // short-lived). now: the user asked.
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
    if (item.status === 'ok' && assets[item.id]) {
      const img = element('img', 'workbench-image rounded');
      img.alt = item.name || '';
      img.addEventListener('error', () => askView(false));
      img.src = assets[item.id];
      view.appendChild(img);
    } else if (item.status !== 'ok') {
      view.appendChild(element('div', 'alert alert-warning small mb-2', statusText(item.status)));
    }
    const line = element('div', 'small text-secondary mt-2');
    line.appendChild(element('code', null, item.path || item.name || ''));
    view.appendChild(line);
    if (item.status === 'ok' && item.artifact_id) {
      view.appendChild(saveButton(item.artifact_id, 'btn-primary mt-2'));
    }
  }

  // ---- the conversation ----------------------------------------------

  function drawNote(mid) {
    const card = mid ? $id(mid) : null;
    const text = card ? card.querySelector('.card-text') : null;
    if (!text) return;
    let el = text.querySelector(':scope > .workbench-note');
    const entries = (records.get(mid) || []).filter((entry) => entry && entry.id && entry.path);
    if (entries.length === 0) {
      if (el) el.remove();
      return;
    }
    if (!el) {
      el = element('div', 'workbench-note small text-secondary mt-2');
      text.appendChild(el);
    }
    el.replaceChildren();
    entries.forEach((entry) => {
      const line = element('div', 'workbench-note-line');
      line.appendChild(element('i', 'fa-solid fa-image me-1'));
      const item = itemOfArtifact(entry.id);
      if (item) {
        const open = element('button', 'btn btn-link btn-sm p-0 align-baseline workbench-open');
        open.type = 'button';
        open.title = t('ui.workbench.open', 'Show in the work screen');
        open.appendChild(element('code', null, String(entry.path)));
        open.addEventListener('click', () => openItem(item.id));
        line.appendChild(open);
      } else {
        line.appendChild(element('code', null, String(entry.path)));
      }
      if (item && item.status !== 'ok') {
        line.appendChild(document.createTextNode(` — ${statusText(item.status)}`));
      } else {
        line.appendChild(document.createTextNode(' '));
        line.appendChild(saveButton(entry.id, 'btn-link p-0 align-baseline workbench-save'));
      }
      el.appendChild(line);
    });
  }

  function drawNotes() {
    records.forEach((_entries, mid) => drawNote(mid));
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
    // What was drawn for the chat before goes; what the chat now shown
    // records as made is drawn again from its messages.
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
    if (data.action === 'remove' && ['accepted', 'same'].includes(data.status)) {
      removed.add(data.item_id);
      announce(t('ui.workbench.removed', 'Removed from the work screen'));
      return;
    }
    if (data.status === 'refused') warn(t('ui.workbench.refused', 'This was not accepted.'));
  }

  // The address to save an image from: the file is fetched here and handed
  // to the browser as a download, so whatever the answer the page stays.
  async function onDownload(data) {
    if (!data) return;
    if (data.status === 'refused' || !data.url) {
      warn(t('ui.workbench.refused', 'This was not accepted.'));
      return;
    }
    let response;
    try {
      response = await fetch(data.url, { credentials: 'same-origin', cache: 'no-store' });
    } catch (_e) {
      warn(t('ui.workbench.downloadFailed', 'Could not get the file.'));
      return;
    }
    if (!response.ok) {
      if (response.status === 409) warn(statusText('changed'));
      else if (response.status === 410) warn(statusText('missing'));
      else warn(t('ui.workbench.expired', 'The link expired. Try again.'));
      if (response.status === 409 || response.status === 410) askView(true);
      return;
    }
    let blob;
    try {
      blob = await response.blob();
    } catch (_e) {
      warn(t('ui.workbench.downloadFailed', 'Could not get the file.'));
      return;
    }
    const href = URL.createObjectURL(blob);
    const a = element('a');
    try {
      a.href = href;
      a.download = String(data.name || 'image');
      a.hidden = true;
      document.body.appendChild(a);
      a.click();
    } finally {
      a.remove();
      setTimeout(() => URL.revokeObjectURL(href), 60000);
    }
  }

  // What a message records as made (with the message).
  function drawRecord(mid, artifacts) {
    if (!mid || !Array.isArray(artifacts)) return;
    if (artifacts.length === 0) records.delete(mid);
    else records.set(mid, artifacts);
    drawNote(mid);
  }

  window.Workbench = {
    onView, onResult, onDownload, drawRecord, select,
    // Whether the pane shows the browser (the relay runs only then).
    showsBrowser: () => selected === BROWSER
  };
})(window);
