/**
 * The workbench in the work screen pane, and its trace in the conversation.
 *
 * The pane lists the items of the chat's workbench (the chat's browser,
 * each image the assistant made, each file of the shared folder opened
 * there) in the order they came, and shows the one selected; ← and → (and the
 * buttons beside the item) move along the row. An image shows with its
 * path in the shared folder (every image is kept in the chat's folder
 * there) and "Save as…" (in the desktop app; "Download" in a browser); a
 * file shows as an image, as text with its line numbers, or as audio or
 * video. Each item's tab has a × that takes it off the workbench; the file
 * stays in the shared folder. An item whose file changed or is gone is not
 * shown: the pane says which (a file can be opened again as it is now).
 *
 * The server keeps which item each tab has selected: the page tells it
 * (WORKBENCH_SELECT), and a view says what the server holds for this tab
 * (`selected`), which is how an item made for this tab is brought forward.
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

  const RETRY_VIEW_MS = 30000;

  let board = null;
  let approvals = {};
  let assets = {};
  // The item this tab shows, or null (nothing selected).
  let selected = null;
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
  // What the server last said this tab has selected.
  let serverSelected = null;
  // A file the user asked to open: the pane is shown when it comes.
  let opening = null;
  // An item the user opened, shown as soon as the board has it.
  let pendingOpen = null;
  // What the pane drew for the item shown, kept while it is the same item
  // at the same version (media keep playing, text keeps its scroll): its
  // key (item and version), node, the address it was drawn from, and
  // whether getting it failed (then a view with a new address draws it
  // again).
  let drawnBody = null;
  // The number of this tab's latest selection told to the server: an
  // answer to an older one is not taken.
  let selectSeq = 0;

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

  function statusText(status, item) {
    if (status === 'changed' && item && item.kind === 'file') {
      return t('ui.workbench.fileChanged', 'This file changed in the shared folder after it was opened here.');
    }
    if (status === 'changed') return t('ui.workbench.changed', 'This file changed in the shared folder after it was made.');
    if (status === 'missing') return t('ui.workbench.missing', 'This file is no longer in the shared folder.');
    return '';
  }

  // The items in the row, in the order they came.
  function rowItems() {
    return items().filter((item) => ['image', 'file', 'browser'].includes(item.kind));
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

  function label(item) {
    return item.kind === 'browser' ? t('ui.workbench.browser', 'Browser') : (item.name || '');
  }

  function tab(id, label) {
    const wrap = element('span', 'workbench-item-wrap');
    const el = element('button', 'workbench-item');
    el.type = 'button';
    el.setAttribute('role', 'tab');
    el.setAttribute('aria-selected', id === selected ? 'true' : 'false');
    el.dataset.item = id;
    el.title = label;
    const shownItem = itemById(id);
    el.appendChild(element('span', 'workbench-item-name', shownItem && shownItem.kind === 'browser' ? label : shortName(label)));
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
    const shown = rowItems();
    list.hidden = shown.length === 0;
    if (list.hidden) return;
    shown.forEach((item) => list.appendChild(tab(item.id, label(item))));
  }

  // The board as it is now, with new addresses (an address is
  // short-lived). now: the user asked.
  function askView(now) {
    const at = Date.now();
    if ((!now && at - askedViewAt < RETRY_VIEW_MS) || typeof window.safeWsSend !== 'function') return;
    askedViewAt = at;
    window.safeWsSend({ message: 'WORKBENCH_VIEW' }, { idempotent: true, silentDrop: true });
  }

  // Whether the item is the chat's browser, open (the relay shows it).
  function liveBrowser(item) {
    return !!item && item.kind === 'browser' && item.status === 'open';
  }

  // The pane's two parts: what the item holds (left in place while it is
  // the same, so media stay connected) and what is said about it.
  function viewParts(view) {
    let held = view.querySelector(':scope > .workbench-body');
    let info = view.querySelector(':scope > .workbench-info');
    if (!held || !info) {
      held = element('div', 'workbench-body');
      info = element('div', 'workbench-info');
      view.replaceChildren(held, info);
    }
    return { held, info };
  }

  function show(part, node) {
    if (node) {
      if (part.childNodes.length !== 1 || part.firstChild !== node) part.replaceChildren(node);
    } else {
      part.replaceChildren();
    }
  }

  // ‹ n / m › above what is shown, for any item.
  function stepperHost() {
    let host = $id('workbench-stepper');
    const area = $id('work-screen-browser');
    if (!host && area && area.parentNode) {
      host = element('div', 'workbench-stepper-host');
      host.id = 'workbench-stepper';
      area.parentNode.insertBefore(host, area);
    }
    return host;
  }

  function drawView() {
    const browserArea = $id('work-screen-browser');
    const view = $id('workbench-view');
    const item = selected ? itemById(selected) : null;
    const live = liveBrowser(item);
    // Nothing selected: the area says there is nothing to show.
    if (browserArea) browserArea.hidden = !!item && !live;
    const host = stepperHost();
    if (host) {
      host.replaceChildren();
      host.hidden = !item;
      if (item) host.appendChild(stepper(item));
    }
    if (!view) return;
    view.hidden = !item || live;
    if (!item || live) {
      view.replaceChildren();
      return;
    }
    view.dataset.item = item.id;
    const { held, info } = viewParts(view);
    info.replaceChildren();
    if (item.kind === 'browser') {
      show(held, element('div', 'alert alert-secondary small mb-2', t('ui.workbench.browserClosed', 'This browser was closed.')));
      return;
    }
    if (item.status === 'ok' && assets[item.id]) {
      show(held, drawnFor(item).node);
    } else if (item.status !== 'ok') {
      drawnBody = null;
      show(held, element('div', 'alert alert-warning small mb-2', statusText(item.status, item)));
    } else {
      show(held, null);
    }
    const line = element('div', 'small text-secondary mt-2');
    line.appendChild(element('code', null, item.path || item.name || ''));
    info.appendChild(line);
    if (item.status === 'ok' && item.artifact_id) {
      info.appendChild(saveButton(item.artifact_id, 'btn-primary mt-2'));
    }
    if (item.kind === 'file' && item.status === 'changed') {
      info.appendChild(button(t('ui.workbench.reopen', 'Open it as it is now'), 'btn-secondary mt-2',
        () => openFile(item.path)));
    }
  }

  // What is drawn for the item: kept while it is the same item at the same
  // version, drawn again from the new address once getting it failed (an
  // address that expired, a busy server, a reconnect). Media go on from
  // where they were.
  function drawnFor(item) {
    const key = `${item.id}|${item.version || item.sha256 || ''}`;
    const url = assets[item.id];
    const same = drawnBody && drawnBody.key === key;
    if (same && !(drawnBody.failed && drawnBody.url !== url)) return drawnBody;
    const resumeAt = same && drawnBody.node && typeof drawnBody.node.currentTime === 'number' ? drawnBody.node.currentTime : 0;
    const drawn = { key: key, url: url, failed: false, node: null };
    drawn.node = body(item, drawn, resumeAt);
    drawnBody = drawn;
    return drawn;
  }

  // ‹ n / m › for the row.
  function stepper(item) {
    const row = rowItems();
    const at = row.findIndex((i) => i.id === item.id);
    const bar = element('div', 'workbench-stepper d-flex align-items-center gap-2 mb-2');
    const prev = button('‹', 'btn-outline-secondary workbench-prev', () => step(-1));
    prev.setAttribute('aria-label', t('ui.workbench.prev', 'Previous item'));
    prev.disabled = at <= 0;
    const next = button('›', 'btn-outline-secondary workbench-next', () => step(1));
    next.setAttribute('aria-label', t('ui.workbench.next', 'Next item'));
    next.disabled = at < 0 || at >= row.length - 1;
    bar.appendChild(prev);
    bar.appendChild(element('span', 'small text-secondary', `${at + 1} / ${row.length}`));
    bar.appendChild(next);
    return bar;
  }

  // Getting what was drawn failed: a view gives a new address, and the
  // next draw uses it.
  function failed(drawn, now) {
    drawn.failed = true;
    askView(now);
  }

  // What the item's address holds, drawn for its kind (drawn: its record,
  // told when getting it fails; resumeAt: where media go on from).
  function body(item, drawn, resumeAt) {
    const url = drawn.url;
    const kind = item.kind === 'file' ? item.preview : 'image';
    if (kind === 'audio' || kind === 'video') {
      const media = element(kind, `workbench-${kind}`);
      media.controls = true;
      media.preload = 'metadata';
      media.addEventListener('error', () => failed(drawn, false));
      if (resumeAt > 0) media.addEventListener('loadedmetadata', () => { media.currentTime = resumeAt; }, { once: true });
      media.src = url;
      return media;
    }
    if (kind === 'text') return textBody(item, drawn);
    const img = element('img', 'workbench-image rounded');
    img.alt = item.name || '';
    img.addEventListener('error', () => failed(drawn, false));
    img.src = url;
    return img;
  }

  // A text file as numbered lines (one element per line, so what is in
  // view can be told by line).
  function textBody(item, drawn) {
    const box = element('div', 'workbench-text');
    box.setAttribute('tabindex', '0');
    fetch(drawn.url, { credentials: 'same-origin', cache: 'no-store' }).then(async (response) => {
      if (!response.ok) {
        drawn.failed = true;
        if (response.status === 503) {
          // Busy: the user asks again.
          box.replaceChildren(element('div', 'alert alert-warning small mb-2', t('ui.workbench.busy', 'The work screen is reading other files. Try again in a moment.')),
            button(t('ui.workbench.retry', 'Try again'), 'btn-secondary', () => askView(true)));
          return;
        }
        box.replaceChildren(element('div', 'alert alert-warning small mb-0',
          response.status === 409 ? statusText('changed', item) : response.status === 410 ? statusText('missing') :
            t('ui.workbench.expired', 'The link expired. Try again.')));
        askView(response.status === 409 || response.status === 410);
        return;
      }
      const text = await response.text();
      const list = element('ol', 'workbench-lines');
      text.split(/\r\n|\n|\r/).forEach((lineText) => list.appendChild(element('li', null, lineText)));
      box.replaceChildren(list);
      if (response.headers.get('x-workbench-truncated')) {
        box.appendChild(element('div', 'small text-secondary mt-1', t('ui.workbench.truncated', 'Only the beginning of the file is shown.')));
      }
    }).catch(() => {
      drawn.failed = true;
      box.replaceChildren(element('div', 'alert alert-warning small mb-0', t('ui.workbench.downloadFailed', 'Could not get the file.')));
    });
    return box;
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
        line.appendChild(document.createTextNode(` — ${statusText(item.status, item)}`));
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
    selected = id && itemById(id) ? id : null;
    tellSelected();
    draw();
    refreshRelay();
  }

  // The server keeps what this tab shows (it keeps that item on the board).
  function tellSelected() {
    if (typeof window.safeWsSend !== 'function' || !board) return;
    selectSeq += 1;
    window.safeWsSend({ message: 'WORKBENCH_SELECT', item_id: selected, seq: selectSeq },
      { idempotent: true, silentDrop: true });
  }

  // One step along the row (from the browser, to the first item).
  function step(delta) {
    const row = rowItems();
    if (row.length === 0) return;
    const at = row.findIndex((item) => item.id === selected);
    const next = at < 0 ? 0 : Math.min(Math.max(at + delta, 0), row.length - 1);
    if (row[next].id !== selected) select(row[next].id);
  }

  // A file of the shared folder the user opens here (path as the Shared
  // Folder panel names it).
  function openFile(path) {
    if (!path || typeof window.safeWsSend !== 'function') return;
    opening = path;
    window.safeWsSend({ message: 'WORKBENCH_OPEN', path: String(path) });
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
    // The user is typing, or turned this off: the pane stays (the
    // announcement says what came), and the server is told what this tab
    // still shows.
    if (typing() || !autoSwitch()) {
      tellSelected();
      return;
    }
    selected = item.id;
    const lc = window.LayoutController;
    if (lc && !lc.isMenuHidden() && lc.selectedPane() !== 'work') lc.setPane('work');
  }

  function reset() {
    board = null;
    approvals = {};
    assets = {};
    selected = null;
    serverSelected = null;
    opening = null;
    pendingOpen = null;
    drawnBody = null;
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

  // ---- the user's preference -----------------------------------------

  // Whether a new item brings the work screen forward. A display
  // preference kept in a cookie (like whether the side column is hidden),
  // so resetting the Web UI keeps it. On unless the user turned it off.
  const AUTO_SWITCH_COOKIE = 'work-screen-auto-switch';

  function autoSwitch() {
    const value = typeof window.getCookie === 'function' ? window.getCookie(AUTO_SWITCH_COOKIE) : null;
    return value !== 'false';
  }

  function attachAutoSwitch() {
    const box = $id('work-screen-auto-switch');
    if (!box) return;
    box.checked = autoSwitch();
    box.addEventListener('change', () => {
      if (typeof window.setCookie === 'function') window.setCookie(AUTO_SWITCH_COOKIE, box.checked ? 'true' : 'false', 365);
    });
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', attachAutoSwitch);
    else attachAutoSwitch();
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
    if (selected && !itemById(selected)) selected = null;
    const arrived = rowItems().filter((item) => !seen.has(item.id));
    arrived.forEach((item) => seen.add(item.id));
    const held = data.selected || null;
    const told = held !== serverSelected;
    serverSelected = held;
    // The board a connection is sent first (a reload, a reconnect) brings
    // nothing forward: none of it is new to the user.
    if (arrived.some((item) => item.actor === 'agent') && !data.initial) {
      news.push(t('ui.workbench.announceNew', 'Something new is in the work screen.'));
    }
    // What the server selected for this tab (an item made or opened for
    // it) is brought forward once.
    if (told && held && held !== selected && itemById(held) && !data.initial) bringForward(itemById(held));
    // What the user opened is shown, whatever the server's selection said.
    if (pendingOpen && itemById(pendingOpen)) {
      showOpened(pendingOpen);
      pendingOpen = null;
    }
    // A connection's first board: the server knows nothing of this tab yet.
    // What the page still shows is told again; otherwise the chat's open
    // browser is shown, as before.
    if (data.initial) {
      if (!selected) {
        const open = rowItems().find(liveBrowser);
        if (open) selected = open.id;
      }
      if (selected) tellSelected();
    }
    // Images the board put away to make room (not removed here).
    if (before.some((id) => !itemById(id) && !removed.has(id))) {
      news.push(t('ui.workbench.putAway', 'An older item was removed from the work screen.'));
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

  // A file the user asked to open: it is shown (the column too), or the
  // reason is given.
  function onOpened(data) {
    if (!data) return;
    const asked = opening;
    opening = null;
    if (data.status === 'refused') {
      const reason = data.reason === 'busy' ? t('ui.workbench.busy', 'The work screen is reading other files. Try again in a moment.') : (data.reason || '');
      warn(`${t('ui.workbench.notOpened', 'The file was not opened in the work screen')}: ${reason}`);
      return;
    }
    if (asked && data.item_id) {
      if (itemById(data.item_id)) showOpened(data.item_id);
      else pendingOpen = data.item_id;
    }
  }

  // The user asked for this item: it is selected and the column shown.
  function showOpened(id) {
    const lc = window.LayoutController;
    if (lc) {
      if (lc.isMenuHidden()) lc.setMenuHidden(false);
      if (lc.selectedPane() !== 'work') lc.setPane('work');
    }
    select(id);
  }

  // The server's answer to this tab's latest selection: what it holds now
  // (so that the next item it selects for this tab is told apart), and for
  // a refused selection, what is shown.
  function onSelected(data) {
    if (!data || (typeof data.seq === 'number' && data.seq !== selectSeq)) return;
    serverSelected = data.item_id || null;
    if (data.status !== 'refused') return;
    selected = data.item_id && itemById(data.item_id) ? data.item_id : null;
    draw();
    refreshRelay();
  }

  // ← and → in the pane (not while typing) move along the row.
  function onKey(e) {
    if (e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey || typing()) return;
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    const target = e.target;
    if (target && target.closest && target.closest('audio, video, .workbench-text')) return;
    e.preventDefault();
    step(e.key === 'ArrowLeft' ? -1 : 1);
  }

  if (typeof document !== 'undefined') {
    const attach = () => { const pane = $id('work-screen-pane'); if (pane) pane.addEventListener('keydown', onKey); };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', attach);
    else attach();
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
    onView, onResult, onDownload, onOpened, onSelected, drawRecord, select, openFile, step,
    // Something changed on the board elsewhere (a tool showed a file).
    onChanged: () => askView(true),
    // Whether the pane shows the browser (the relay runs only then).
    showsBrowser: () => liveBrowser(selected ? itemById(selected) : null),
    // The browser the pane shows (its instance, which the relay names), or
    // null.
    shownBrowser: () => {
      const item = selected ? itemById(selected) : null;
      return liveBrowser(item) && Number.isInteger(item.instance) ? item.instance : null;
    },
    // The chat's browser opened while the work screen was full.
    onBrowserFull: () => warn(t('ui.workbench.browserFull', 'The browser opened, but the work screen is full. Remove an item to show it there.'))
  };
})(window);
