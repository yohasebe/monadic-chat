/**
 * The workbench in the work screen pane, and its trace in the conversation.
 *
 * The pane lists the items of the chat's workbench (the chat's browser,
 * each image the assistant made, each file of the shared folder opened
 * there) in the order they came, and shows the one selected; ← and → (and the
 * buttons beside the item) move along the row. An image shows with its
 * path in the shared folder (every image is kept in the chat's folder
 * there) and "Save as…" (in the desktop app; "Download" in a browser); a
 * file shows as an image, as text with its line numbers, as audio or
 * video, or as a PDF a page at a time (workbench-pdf.js). A text file of a
 * kind the work screen draws (Markdown, a table, SVG, a page, a diagram, a
 * chart: workbench-render.js) is drawn, with a switch to its lines. Each item's tab has a × that takes it off the workbench; the file
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
 * Under a reply that showed files in the work screen, one line per file
 * (`workbench_shown`), which shows that version again.
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
  // The address of the whole text of each item the work screen can draw.
  let renders = {};
  // How each drawable text item is shown, by item and version: 'drawn'
  // (the default) or 'source' (its numbered lines).
  const modes = new Map();
  // Where each drawing was scrolled to (by what drawKey names), so that a
  // switch between drawn and source, or back from another item, keeps it.
  const scrolls = new Map();
  const SCROLLS_KEPT = 50;
  // The item this tab shows, or null (nothing selected).
  let selected = null;
  // Images already seen (a new one is brought forward once).
  const seen = new Set();
  // Images removed from here (not put away by the board to make room).
  const removed = new Set();
  // What each message records as made, as last drawn.
  const records = new Map();
  // What each message records its reply looked at (mid → list).
  const looks = new Map();
  // What each message records its reply showed on the work screen.
  const shownRecords = new Map();
  // One operation id per removal, so the same removal sent again (a retry,
  // a reconnect) is the same operation on the server.
  const operations = new Map();
  let askedViewAt = 0;
  // What the server last said this tab has selected, and the number of
  // that selection (a capture names it).
  let serverSelected = null;
  let serverSerial = null;
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
  // A file the user attached, shown here from the page's own data (draft:
  // the message being written; message: one sent): { source, key, kind,
  // name, size, data, attachmentId, note }. Never a board item: while one is
  // shown nothing of the board is selected, so neither a message's range
  // nor a look names a board item.
  let local = null;
  let localPdf = null;
  // Each showing of an attachment, so that a new one is drawn anew.
  let localSerial = 0;
  // Numbers the requests to open an attachment. Only the answer to the
  // request the shown attachment waits for is taken; a reset puts the
  // attachment away, so an answer from before it is dropped.
  let attachmentRequest = 0;
  // The latest selection the server answered (selectSeq when none waits).
  let answeredSeq = 0;

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
    // The item shown already stays as it is (nothing is drawn again).
    el.addEventListener('click', () => { if (id !== selected) select(id); });
    wrap.appendChild(el);
    const item = itemById(id);
    if (item && approvals[item.id]) {
      const close = element('button', 'workbench-item-remove');
      close.appendChild(element('i', 'fa-solid fa-xmark'));
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

  // What the next message carries, above the board's items.
  function drawDrafts() {
    const strip = $id('workbench-drafts');
    if (!strip) return;
    const entries = window.AttachmentDrafts && typeof window.AttachmentDrafts.list === 'function'
      ? window.AttachmentDrafts.list() : [];
    strip.replaceChildren();
    strip.hidden = entries.length === 0;
    if (strip.hidden) return;
    strip.appendChild(element('span', 'workbench-drafts-label', t('ui.workbench.toSend', 'To send')));
    entries.forEach((entry) => {
      const chip = element('button', 'mc-badge mc-badge--grey workbench-draft');
      chip.type = 'button';
      chip.textContent = entry.name || '';
      chip.title = t('ui.workbench.showAttachment', 'Show on the work screen');
      chip.setAttribute('aria-pressed', local && local.key === entry.key ? 'true' : 'false');
      chip.addEventListener('click', () => showAttachment(Object.assign({ source: 'draft' }, entry)));
      strip.appendChild(chip);
    });
  }

  function drawList() {
    drawDrafts();
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
    if (local) {
      drawLocal();
      return;
    }
    const browserArea = $id('work-screen-browser');
    const view = $id('workbench-view');
    if (view && view.dataset.local) {
      dropLocalPdf();
      delete view.dataset.local;
      view.replaceChildren();
    }
    const item = selected ? itemById(selected) : null;
    const live = liveBrowser(item);
    // Nothing selected: the area says there is nothing to show.
    if (browserArea) browserArea.hidden = !!item && !live;
    const host = stepperHost();
    if (host) {
      host.replaceChildren();
      // Only when there is another item to step to.
      host.hidden = !item || rowItems().length < 2;
      if (!host.hidden) host.appendChild(stepper(item));
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
      letGo(drawnBody);
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
    // A file is read again where it is shown (the board takes it at the
    // version it has now): after it changed, or whenever the user asks.
    if (item.kind === 'file' && item.status === 'changed') {
      info.appendChild(button(t('ui.workbench.reopen', 'Open it as it is now'), 'btn-secondary mt-2',
        () => openFile(item.path)));
    } else if (item.kind === 'file' && item.status === 'ok') {
      info.appendChild(button(t('ui.workbench.reload', 'Reload'), 'btn-secondary mt-2', () => openFile(item.path)));
    }
  }

  // What is drawn for the item: kept while it is the same item at the same
  // version, drawn again from the new address once getting it failed (an
  // address that expired, a busy server, a reconnect). Media go on from
  // where they were.
  function drawnFor(item) {
    const key = drawKey(item);
    const url = assets[item.id];
    const same = drawnBody && drawnBody.key === key;
    if (same && !(drawnBody.failed && drawnBody.url !== url)) return drawnBody;
    const resumeAt = same && drawnBody.node && typeof drawnBody.node.currentTime === 'number' ? drawnBody.node.currentTime : 0;
    // A medium that failed again with a fresh address is not asked for again.
    const drawn = { key: key, url: url, failed: false, node: null, retried: !!(same && drawnBody.retried) };
    drawn.node = body(item, drawn, resumeAt);
    letGo(drawnBody);
    drawnBody = drawn;
    return drawn;
  }

  // Whether the item is a text file the work screen can draw.
  function drawable(item) {
    return !!(item && item.kind === 'file' && item.preview === 'text' && item.render && renders[item.id] &&
      window.WorkbenchRender);
  }

  function versionKey(item) {
    return `${item.id}|${item.version || item.sha256 || ''}`;
  }

  // How the item is shown now: 'drawn' or 'source' for a drawable text.
  function modeOf(item) {
    if (!drawable(item)) return null;
    return modes.get(versionKey(item)) || 'drawn';
  }

  // What is drawn is kept while the item, its version and how it is shown
  // stay the same.
  function drawKey(item) {
    const mode = modeOf(item);
    return mode ? `${versionKey(item)}|${mode}` : versionKey(item);
  }

  function setMode(item, mode) {
    if (modeOf(item) === mode) return;
    modes.set(versionKey(item), mode);
    drawView();
  }

  // ‹ n / m › for the row.
  function stepper(item) {
    const row = rowItems();
    const at = row.findIndex((i) => i.id === item.id);
    const bar = element('div', 'workbench-stepper d-flex align-items-center gap-2 mb-2');
    const prev = button('', 'btn-outline-secondary workbench-prev', () => step(-1));
    prev.appendChild(element('i', 'fa-solid fa-chevron-left'));
    prev.setAttribute('aria-label', t('ui.workbench.prev', 'Previous item'));
    prev.disabled = at <= 0;
    const next = button('', 'btn-outline-secondary workbench-next', () => step(1));
    next.appendChild(element('i', 'fa-solid fa-chevron-right'));
    next.setAttribute('aria-label', t('ui.workbench.next', 'Next item'));
    next.disabled = at < 0 || at >= row.length - 1;
    bar.appendChild(prev);
    bar.appendChild(element('span', 'small text-secondary workbench-item-where',
      t('ui.workbench.itemOf', 'Item {n} of {total}').replace('{n}', String(at + 1)).replace('{total}', String(row.length))));
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
      // The address may have run out: asked for once more. Failing again,
      // the browser cannot play it, and the name is shown instead.
      media.addEventListener('error', () => {
        if (drawn.retried) {
          media.replaceWith(element('div', 'alert alert-warning mb-2', t('ui.workbench.notPlayable', 'This kind of file is not played on the work screen.')));
          return;
        }
        drawn.retried = true;
        failed(drawn, false);
      });
      // Read once: a later failure (an address that ran out) is asked for again.
      media.addEventListener('loadedmetadata', () => { drawn.retried = false; });
      if (resumeAt > 0) media.addEventListener('loadedmetadata', () => { media.currentTime = resumeAt; }, { once: true });
      media.src = url;
      return media;
    }
    if (kind === 'text' && drawable(item)) return drawableBody(item, drawn);
    if (kind === 'text') return textBody(item, drawn);
    if (kind === 'pdf') return pdfBody(item, drawn);
    const img = element('img', 'workbench-image rounded');
    img.alt = item.name || '';
    img.addEventListener('error', () => failed(drawn, false));
    img.src = url;
    return img;
  }

  // Gets the item's address for box: onBody(response) draws what came. A
  // failure is said in box (busy, changed, gone, expired), and the drawing
  // is marked failed (a view with a new address draws it again).
  function fetchInto(box, item, drawn, onBody) {
    fetch(drawn.url, { credentials: 'same-origin', cache: 'no-store' }).then(async (response) => {
      if (drawn.onStatus && drawn.onStatus(response.status)) return;
      if (response.status === 415) {
        // The same version is not text where it is shown: asking again
        // gives the same.
        drawn.unshowable = true;
        box.replaceChildren(element('div', 'alert alert-warning small mb-0', t('ui.workbench.notText', 'This file cannot be shown as text.')));
        return;
      }
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
      await onBody(response);
    }).catch(() => {
      drawn.failed = true;
      box.replaceChildren(element('div', 'alert alert-warning small mb-0', t('ui.workbench.downloadFailed', 'Could not get the file.')));
    });
  }

  // The lines of a text the server served (already with "\n" line ends),
  // numbered from 1 by their place, as the server numbers them
  // (SharedFolderPreview.text_lines): none in empty text; a "\n" ends the
  // line before it, so a final "\n" adds no line.
  function textLines(text) {
    if (text === '') return [];
    return (text.endsWith('\n') ? text.slice(0, -1) : text).split('\n');
  }

  // A text file as numbered lines (one element per line, so what is in
  // view can be told by line).
  function textBody(item, drawn) {
    const box = element('div', 'workbench-text');
    box.setAttribute('tabindex', '0');
    fetchInto(box, item, drawn, async (response) => {
      const list = element('ol', 'workbench-lines');
      textLines(await response.text()).forEach((lineText) => list.appendChild(element('li', null, lineText)));
      box.replaceChildren(list);
      drawn.loaded = true;
      restoreScroll(drawn, box);
      if (response.headers.get('x-workbench-truncated')) {
        box.appendChild(element('div', 'small text-secondary mt-1', t('ui.workbench.truncated', 'Only the beginning of the file is shown.')));
      }
    });
    return box;
  }

  // A text the work screen can draw (WorkbenchRender): drawn, or as its
  // numbered lines, with a switch between the two above it. What is drawn
  // comes from the whole text (the render address); the lines from the
  // text view, as for any text. A drawing that fails says why and offers
  // the lines.
  function drawableBody(item, drawn) {
    const mode = modeOf(item);
    drawn.mode = mode;
    const wrap = element('div', 'workbench-drawable');
    const bar = element('div', 'btn-group btn-group-sm workbench-mode mb-2');
    bar.setAttribute('role', 'group');
    bar.setAttribute('aria-label', t('ui.workbench.viewAs', 'Show the file'));
    [['drawn', t('ui.workbench.viewDrawn', 'Drawn')], ['source', t('ui.workbench.viewSource', 'Source')]].forEach(([value, label]) => {
      const choice = button(label, value === mode ? 'btn-secondary' : 'btn-outline-secondary', () => setMode(item, value));
      choice.setAttribute('aria-pressed', value === mode ? 'true' : 'false');
      choice.dataset.mode = value;
      bar.appendChild(choice);
    });
    wrap.appendChild(bar);
    if (mode === 'source') {
      wrap.appendChild(textBody(item, drawn));
      return wrap;
    }
    const box = element('div', 'workbench-rendered');
    box.setAttribute('tabindex', '0');
    wrap.appendChild(box);
    // Getting the whole text: a failure marks the drawing (a view with new
    // addresses draws it again); a file too large to draw (413) offers its
    // lines instead.
    const source = {
      url: renders[item.id],
      get failed() { return drawn.failed; },
      set failed(value) { drawn.failed = value; },
      get unshowable() { return drawn.unshowable; },
      set unshowable(value) { drawn.unshowable = value; },
      onStatus: (status) => {
        if (status !== 413) return false;
        drawn.unshowable = true;
        box.replaceChildren(element('div', 'alert alert-secondary small mb-2', t('ui.workbench.renderTooLarge', 'This file is too large to draw.')),
          button(t('ui.workbench.viewSource', 'Source'), 'btn-secondary', () => setMode(item, 'source')));
        return true;
      }
    };
    fetchInto(box, item, source, async (response) => {
      const text = await response.text();
      if (drawn.gone) return;
      drawn.render = window.WorkbenchRender.draw(box, item.render, text, { name: item.name });
      try {
        await drawn.render.done;
        if (!drawn.gone) {
          drawn.loaded = true;
          restoreScroll(drawn, box);
          // A tune is played under its score (abc-player.js).
          if (item.render === 'abc' && window.AbcPlayer) {
            const controls = element('div', 'workbench-abc-player mt-2');
            wrap.appendChild(controls);
            drawn.player = await window.AbcPlayer.playerFor(controls, text);
            if (drawn.gone) drawn.player.stop();
          }
        }
      } catch (e) {
        if (drawn.gone) return;
        drawn.unshowable = true;
        box.replaceChildren(element('div', 'alert alert-warning small mb-2',
          `${t('ui.workbench.renderFailed', 'This file could not be drawn.')} ${e && e.message ? e.message : ''}`.trim()),
        button(t('ui.workbench.viewSource', 'Source'), 'btn-secondary', () => setMode(item, 'source')));
      }
    });
    return wrap;
  }

  // A PDF, drawn a page at a time (workbench-pdf.js) from its bytes.
  function pdfBody(item, drawn) {
    const box = element('div', 'workbench-pdf');
    fetchInto(box, item, drawn, async (response) => {
      const bytes = await response.arrayBuffer();
      if (drawn.gone) return;
      if (!window.WorkbenchPdf) throw new Error('pdf.js is not loaded');
      drawn.pdf = window.WorkbenchPdf.show(box, bytes);
    });
    return box;
  }

  // The part of a drawing that scrolls (a text's lines or a drawn file).
  function scroller(drawn) {
    const node = drawn && drawn.node;
    if (!node || !node.matches) return null;
    return node.matches('.workbench-text, .workbench-rendered') ? node : node.querySelector('.workbench-rendered, .workbench-text');
  }

  // Back where the drawing was left, once its content is in.
  function restoreScroll(drawn, box) {
    const top = scrolls.get(drawn.key);
    if (top && box) box.scrollTop = top;
  }

  // What was drawn is no longer shown: where it was scrolled to is kept; a
  // PDF lets its document go.
  function letGo(drawn) {
    if (!drawn) return;
    const box = !drawn.gone && drawn.loaded ? scroller(drawn) : null;
    if (box) {
      scrolls.delete(drawn.key);
      scrolls.set(drawn.key, box.scrollTop);
      while (scrolls.size > SCROLLS_KEPT) scrolls.delete(scrolls.keys().next().value);
    }
    drawn.gone = true;
    if (drawn.pdf) drawn.pdf.dispose();
    if (drawn.render) drawn.render.dispose();
    if (drawn.player) drawn.player.stop();
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

  const LOOK_STATES = {
    sent: ['lookSent', 'Sent to the AI provider from the work screen'],
    embedded: ['lookEmbedded', 'Put in a request to the assistant (not confirmed as sent)'],
    unknown: ['lookUnknown', 'Sent to the AI provider; whether it arrived is not known'],
    unsent: ['lookUnsent', 'Read from the work screen, not sent to the assistant'],
    refused: ['lookRefused', "Not taken by the assistant's provider"],
    acquired: ['lookAcquired', 'Read from the work screen, not sent yet']
  };

  // One line for each look of the reply: how far it went, what it was
  // (the name, the version, the lines), from the message's record.
  function drawLooks(mid, list) {
    const card = mid ? $id(mid) : null;
    const text = card ? card.querySelector('.card-text') : null;
    const entries = Array.isArray(list) ? list.filter((e) => e && LOOK_STATES[e.state] && e.name) : [];
    if (entries.length === 0) looks.delete(mid); else looks.set(mid, entries);
    if (!text) return;
    let el = text.querySelector(':scope > .workbench-look-note');
    if (entries.length === 0) {
      if (el) el.remove();
      return;
    }
    if (!el) {
      el = element('div', 'workbench-look-note small text-secondary mt-2');
      text.appendChild(el);
    }
    el.replaceChildren();
    entries.forEach((entry) => {
      const [key, fallback] = LOOK_STATES[entry.state];
      const line = element('div', 'workbench-look-line');
      line.appendChild(element('i', 'fa-solid fa-eye me-1'));
      line.appendChild(document.createTextNode(`${t(`ui.workbench.${key}`, fallback)}: `));
      line.appendChild(element('code', null, String(entry.name)));
      const details = [];
      if (entry.version) details.push(String(entry.version).slice(0, 12));
      const lines = entry.lines;
      if (lines && Number.isInteger(lines.first) && Number.isInteger(lines.last)) {
        details.push(t('ui.workbench.lookLines', 'lines {first}–{last}')
          .replace('{first}', String(lines.first)).replace('{last}', String(lines.last)));
      }
      const pages = entry.kind === 'pdf' ? entry.pages : null;
      if (pages && Number.isInteger(pages.first)) {
        details.push(pages.first === pages.last
          ? t('ui.workbench.lookPage', 'page {page}').replace('{page}', String(pages.first))
          : t('ui.workbench.lookPages', 'pages {first}–{last} of {total}').replace('{first}', String(pages.first))
            .replace('{last}', String(pages.last)).replace('{total}', Number.isInteger(pages.total) ? String(pages.total) : '?'));
      }
      const parts = entry.kind === 'pdf' && entry.parts ? entry.parts : {};
      [['image', 'lookImage', 'image of the part in view'], ['page_text', 'lookPageText', 'text of the page'],
        ['selection', 'lookSelection', 'selected text']].forEach(([part, key, fallback]) => {
        if (parts[part] === true) details.push(t(`ui.workbench.${key}`, fallback));
      });
      // A PDF's text that stops because the time ran out says so; any other
      // cut is "cut short".
      if (entry.kind === 'pdf' && entry.stopped === 'time') {
        details.push(t('ui.workbench.lookStoppedTime', 'stopped: out of time'));
      } else if (entry.truncated || (lines && lines.partial)) {
        details.push(t('ui.workbench.lookCut', 'cut short'));
      }
      if (entry.empty) {
        details.push(entry.kind === 'pdf' ? t('ui.workbench.lookNoText', 'no text extracted') : t('ui.workbench.lookEmpty', 'empty'));
      }
      const at = entry.at ? new Date(entry.at) : null;
      if (at && !Number.isNaN(at.getTime())) details.push(at.toLocaleTimeString());
      if (details.length) line.appendChild(document.createTextNode(` (${details.join(', ')})`));
      el.appendChild(line);
    });
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
    if (id) clearLocal();
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
  function openFile(path, sha256) {
    if (!path || typeof window.safeWsSend !== 'function') return;
    opening = path;
    const message = { message: 'WORKBENCH_OPEN', path: String(path) };
    // The version a message's record names: only that one opens.
    if (sha256) message.sha256 = String(sha256);
    window.safeWsSend(message);
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
    // What the page showed of an attachment gives way to the new item.
    clearLocal();
    selected = item.id;
    const lc = window.LayoutController;
    if (lc && !lc.isMenuHidden() && lc.selectedPane() !== 'work') lc.setPane('work');
  }

  function reset() {
    clearLocal();
    board = null;
    approvals = {};
    assets = {};
    renders = {};
    modes.clear();
    scrolls.clear();
    selected = null;
    serverSelected = null;
    serverSerial = null;
    opening = null;
    pendingOpen = null;
    letGo(drawnBody);
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
    looks.clear();
    document.querySelectorAll('.workbench-look-note').forEach((el) => el.remove());
    shownRecords.clear();
    document.querySelectorAll('.workbench-shown-note').forEach((el) => el.remove());
    (Array.isArray(messages) ? messages : []).forEach((m) => {
      if (m && m.mid && Array.isArray(m.artifacts)) records.set(m.mid, m.artifacts);
      if (m && m.mid && Array.isArray(m.workbench_shown)) drawShown(m.mid, m.workbench_shown);
      if (m && m.mid && Array.isArray(m.workbench_looks)) drawLooks(m.mid, m.workbench_looks);
    });
  }

  // ---- what is in view (sent with a message) -------------------------

  const SELECTION_LIMIT = 100000;

  function paneShown() {
    const lc = window.LayoutController;
    if (lc && (lc.isMenuHidden() || lc.selectedPane() !== 'work')) return false;
    return document.visibilityState !== 'hidden';
  }

  // The part of el the user can see now: its area inside its border, cut
  // by every ancestor that clips it (overflow other than visible, such as
  // the side column scrolled on a narrow screen) and by the window. null
  // when none of it is.
  function visibleRect(el) {
    const own = el.getBoundingClientRect();
    const inner = (node, rect) => (node.clientHeight > 0
      ? { top: rect.top + node.clientTop, bottom: rect.top + node.clientTop + node.clientHeight,
          left: rect.left + node.clientLeft, right: rect.left + node.clientLeft + node.clientWidth }
      : { top: rect.top, bottom: rect.bottom, left: rect.left, right: rect.right });
    const seen = inner(el, own);
    for (let up = el.parentElement; up && up !== document.body && up !== document.documentElement; up = up.parentElement) {
      const style = window.getComputedStyle(up);
      const clips = (value) => ['auto', 'scroll', 'hidden', 'clip'].includes(value);
      if (!clips(style.overflowX) && !clips(style.overflowY)) continue;
      const clip = inner(up, up.getBoundingClientRect());
      seen.top = Math.max(seen.top, clip.top);
      seen.bottom = Math.min(seen.bottom, clip.bottom);
      seen.left = Math.max(seen.left, clip.left);
      seen.right = Math.min(seen.right, clip.right);
    }
    seen.top = Math.max(seen.top, 0);
    seen.bottom = Math.min(seen.bottom, window.innerHeight);
    seen.left = Math.max(seen.left, 0);
    seen.right = Math.min(seen.right, window.innerWidth);
    return seen.bottom > seen.top && seen.right > seen.left ? seen : null;
  }

  // The lines of a text box in view (frame: what of the box can be seen),
  // as line numbers, measured now: the line elements are in order, so two
  // binary searches find the first line that ends below the frame's top and
  // the first that starts at or below its bottom. A line partly in view
  // counts.
  function linesInView(box, frame) {
    const lines = box.querySelectorAll('.workbench-lines > li');
    if (lines.length === 0) return null;
    const firstWhere = (test) => {
      let lo = 0;
      let hi = lines.length;
      while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (test(lines[mid].getBoundingClientRect())) hi = mid;
        else lo = mid + 1;
      }
      return lo;
    };
    const first = firstWhere((r) => r.bottom > frame.top);
    const after = firstWhere((r) => r.top >= frame.bottom);
    return first < after ? { first_line: first + 1, last_line: after } : null;
  }

  // Characters (not UTF-16 units) the user selected inside node, at most
  // SELECTION_LIMIT; none for a selection elsewhere (the message box, the
  // conversation).
  function selectedChars(node) {
    const selection = typeof window.getSelection === 'function' ? window.getSelection() : null;
    if (!node || !selection || selection.isCollapsed) return 0;
    if (!node.contains(selection.anchorNode) || !node.contains(selection.focusNode)) return 0;
    return Math.min(Array.from(selection.toString()).length, SELECTION_LIMIT);
  }

  // What the pane shows of the selected item now, sent with a message
  // (workbench_range): the item and its version, the range in view (or
  // null and why: not_shown, drawing, failed, unknown), and how many
  // characters are selected in it. The server takes it only for the item
  // this tab has selected, at that version. null with nothing selected.
  function rangeNow() {
    // An attachment shown from the page's data is no item of the board: the
    // model is told of none.
    if (local) return null;
    const item = selected ? itemById(selected) : null;
    if (!item) return null;
    const version = item.version || item.sha256 || '';
    const drawn = drawnBody && drawnBody.key === drawKey(item) ? drawnBody : null;
    const kind = item.kind === 'file' ? item.preview : item.kind;
    const report = (range, note) => ({
      item_id: item.id, version: version, range: range, note: note,
      selection_chars: drawn ? selectedChars(drawn.node) : 0
    });
    if (!paneShown()) return report(null, 'not_shown');
    if (kind === 'image' || kind === 'browser') return report({}, null);
    if (!drawn) return report(null, 'unknown');
    if (drawn.failed || drawn.unshowable) return report(null, 'failed');
    const frame = visibleRect(drawn.node);
    if (!frame) return report(null, 'not_shown');
    // Drawn, the text's lines are not what is in view.
    if (kind === 'text' && drawn.mode === 'drawn') return report(null, 'rendered');
    if (kind === 'text') {
      if (!drawn.loaded) return report(null, 'drawing');
      const lines = linesInView(drawn.node, frame);
      // A text with no line, or none of its lines in view.
      return lines ? report(lines, null) : report(null, 'empty');
    }
    if (kind === 'pdf') {
      const shown = drawn.pdf ? drawn.pdf.shown() : { status: 'loading' };
      if (shown.status !== 'ready') return report(null, shown.status === 'failed' ? 'failed' : 'drawing');
      // The page itself, not only the bar above it, must be in view.
      const sheet = drawn.node.querySelector('.workbench-pdf-page');
      if (!sheet || !visibleRect(sheet)) return report(null, 'not_shown');
      return report({ page: shown.page, pages: shown.pages, scale_percent: Math.round(shown.scale * 100) }, null);
    }
    if (kind === 'audio' || kind === 'video') {
      const media = drawn.node;
      const duration = Number.isFinite(media.duration) ? Math.round(media.duration) : null;
      return report({ position_seconds: Math.floor(media.currentTime || 0), duration_seconds: duration }, null);
    }
    return report(null, 'unknown');
  }

  // ---- what the server asks the work screen (a look) ------------------

  // What is cut from a PDF's page, at most (as the server takes it).
  const CUT_SIDE = 2048;
  const CUT_PIXELS = 4194304;
  const CUT_BASE64 = 5 * 1024 * 1024;
  const SELECTED_TEXT_LIMIT = 8000;

  // The text the user selected inside node (a PDF's text layer), at most
  // SELECTED_TEXT_LIMIT characters: [text, cut], or [null, false].
  function selectedText(node) {
    const selection = typeof window.getSelection === 'function' ? window.getSelection() : null;
    if (!node || !selection || selection.isCollapsed) return [null, false];
    if (!node.contains(selection.anchorNode) || !node.contains(selection.focusNode)) return [null, false];
    const chars = Array.from(selection.toString());
    if (chars.length === 0) return [null, false];
    return [chars.slice(0, SELECTED_TEXT_LIMIT).join(''), chars.length > SELECTED_TEXT_LIMIT];
  }

  // The part of a PDF page's canvas in view, cut and drawn at most
  // CUT_SIDE × CUT_PIXELS (into a canvas of that size, not a larger one
  // made smaller), as PNG base64 with the part of the canvas it is (in the
  // canvas's own pixels: the canvas may be drawn at another ratio than the
  // screen's), or why there is none. Taken from the drawing named; a newer
  // drawing meanwhile spoils it.
  function cutPage(handle, drawing) {
    const canvas = handle.canvas();
    const frame = canvas ? visibleRect(canvas) : null;
    if (!frame) return { image_note: 'not_in_view' };
    const rect = canvas.getBoundingClientRect();
    if (!(rect.width > 0 && rect.height > 0)) return { image_note: 'not_in_view' };
    const sx = canvas.width / rect.width;
    const sy = canvas.height / rect.height;
    const x = (frame.left - rect.left) * sx;
    const y = (frame.top - rect.top) * sy;
    const w = (frame.right - frame.left) * sx;
    const h = (frame.bottom - frame.top) * sy;
    if (![x, y, w, h].every(Number.isFinite) || w <= 0 || h <= 0) return { image_note: 'not_in_view' };
    const fit = Math.min(1, CUT_SIDE / Math.max(w, h), Math.sqrt(CUT_PIXELS / (w * h)));
    const width = Math.max(1, Math.floor(w * fit));
    const height = Math.max(1, Math.floor(h * fit));
    const cut = document.createElement('canvas');
    cut.width = width;
    cut.height = height;
    const context = cut.getContext('2d');
    if (!context) return { image_note: 'failed' };
    context.drawImage(canvas, x, y, w, h, 0, 0, width, height);
    const url = cut.toDataURL('image/png');
    if (handle.shown().drawing !== drawing) return { image_note: 'redrawn' };
    const comma = url.indexOf(',');
    if (!url.startsWith('data:image/png;base64,') || comma < 0) return { image_note: 'failed' };
    const image = url.slice(comma + 1);
    if (image.length > CUT_BASE64) return { image_note: 'too_large' };
    const round = (v) => Math.round(v * 100) / 100;
    return { image: image, crop: { x: round(x), y: round(y), width: round(w), height: round(h), sent_width: width, sent_height: height } };
  }

  // A capture of a PDF: the page in view and, as asked, the part of it in
  // view and the text selected in it, all from the drawing shown now.
  function pdfAnswer(data, drawn) {
    const handle = drawn.pdf;
    const shown = handle.shown();
    const wants = Array.isArray(data.wants) ? data.wants : [];
    const out = { range: { page: shown.page, pages: shown.pages }, note: null };
    if (wants.includes('selection')) {
      const [text, cut] = selectedText(handle.textLayer());
      if (text) {
        out.selection_text = text;
        out.selection_cut = cut;
      }
    }
    if (wants.includes('image')) {
      let part;
      try {
        part = cutPage(handle, shown.drawing);
      } catch (_) {
        part = { image_note: 'failed' };
      }
      Object.assign(out, part);
    }
    return out;
  }

  // The answer to a capture (workbench_capture): what the pane shows now of
  // the item asked for, only while it is the selection the server has for
  // this tab (by its number) and no selection of this page is waiting for
  // the server's answer. Only what was asked for (wants) is given.
  function captureAnswer(data) {
    if (answeredSeq !== selectSeq) return { range: null, note: 'changing' };
    const item = selected ? itemById(selected) : null;
    const version = item ? (item.version || item.sha256 || '') : '';
    if (!item || item.id !== data.item_id || version !== data.version || serverSelected !== selected ||
        serverSerial !== data.serial) {
      return { range: null, note: 'selection_changed' };
    }
    const now = rangeNow();
    if (!now || now.item_id !== data.item_id || now.version !== data.version) {
      return { range: null, note: 'selection_changed' };
    }
    const wants = Array.isArray(data.wants) ? data.wants : [];
    const drawn = drawnBody && drawnBody.key === `${data.item_id}|${data.version}` ? drawnBody : null;
    if (drawn && drawn.pdf && now.range && Number.isInteger(now.range.page)) return pdfAnswer(data, drawn);
    const lines = now.range && Number.isInteger(now.range.first_line) && Number.isInteger(now.range.last_line);
    if (wants.includes('range') && lines) {
      return { range: { first_line: now.range.first_line, last_line: now.range.last_line }, note: null };
    }
    return { range: null, note: now.note || 'unknown' };
  }

  // Answers a capture by HTTP, to the address only this connection was
  // given (its id), so that the answer does not wait behind the socket.
  function onCapture(data) {
    if (!data || typeof data.id !== 'string' || typeof fetch !== 'function') return;
    let answer;
    try {
      answer = captureAnswer(data);
    } catch (_) {
      answer = { range: null, note: 'failed' };
    }
    fetch(`/workbench/capture/${encodeURIComponent(data.id)}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(answer),
      credentials: 'same-origin', cache: 'no-store', redirect: 'error'
    }).catch(() => {});
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
    renders = data.renders || {};
    const news = [];
    if (selected && !itemById(selected)) selected = null;
    const arrived = rowItems().filter((item) => !seen.has(item.id));
    arrived.forEach((item) => seen.add(item.id));
    const held = data.selected || null;
    const told = held !== serverSelected;
    serverSelected = held;
    serverSerial = typeof data.selection_serial === 'number' ? data.selection_serial : null;
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

  // ---- attachments shown here (page only) ----------------------------

  const IMAGE_DATA = /^data:image\/(png|jpe?g|gif|webp);base64,[A-Za-z0-9+/=]+$/;
  const PDF_DATA = /^data:application\/pdf;base64,[A-Za-z0-9+/=]+$/;

  function dropLocalPdf() {
    if (localPdf && typeof localPdf.dispose === 'function') localPdf.dispose();
    localPdf = null;
  }

  function clearLocal() {
    if (!local) return;
    dropLocalPdf();
    local = null;
  }

  function bytesOf(dataUrl) {
    const text = atob(dataUrl.slice(dataUrl.indexOf(',') + 1));
    const bytes = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i += 1) bytes[i] = text.charCodeAt(i);
    return bytes;
  }

  function sizeText(size) {
    if (!Number.isFinite(size) || size <= 0) return '';
    return size >= 1048576 ? `${(size / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(size / 1024))} KB`;
  }

  const ATTACHMENT_NOTES = {
    no_data: ['ui.workbench.noDataToShow', 'No data to show.'],
    not_playable: ['ui.workbench.notPlayable', 'This kind of file is not played on the work screen.'],
    too_large: ['ui.workbench.attachmentTooLarge', 'This file is too large to play on the work screen.'],
    busy: ['ui.workbench.busy', 'The work screen is reading other files. Try again in a moment.']
  };

  function noteText(note) {
    const known = ATTACHMENT_NOTES[note];
    if (known) return t(known[0], known[1]);
    return t('ui.workbench.attachmentNotOpened', 'The attachment could not be shown on the work screen.');
  }

  // The file shown from the page's data: an image, a PDF, or what is known
  // of it (name and size).
  function drawLocal() {
    const browserArea = $id('work-screen-browser');
    const view = $id('workbench-view');
    if (browserArea) browserArea.hidden = true;
    const host = stepperHost();
    if (host) {
      host.replaceChildren();
      host.hidden = true;
    }
    if (!view) return;
    view.hidden = false;
    delete view.dataset.item;
    const key = `${local.key}|${local.serial}|${local.note || ''}`;
    if (view.dataset.local === key) return;
    dropLocalPdf();
    letGo(drawnBody);
    drawnBody = null;
    view.dataset.local = key;
    const body = element('div', 'workbench-body');
    const info = element('div', 'workbench-info');
    let note = local.note;
    if (!note && (local.kind === 'image' || local.kind === 'pdf') && !local.data) note = 'no_data';
    if (note) {
      body.appendChild(element('div', 'alert alert-warning mb-2', noteText(note)));
    } else if (local.kind === 'image' && IMAGE_DATA.test(local.data)) {
      const img = element('img', 'workbench-image');
      img.alt = local.name || '';
      img.src = local.data;
      body.appendChild(img);
    } else if (local.kind === 'pdf' && PDF_DATA.test(local.data) && window.WorkbenchPdf) {
      const box = element('div', 'workbench-pdf');
      body.appendChild(box);
      try {
        localPdf = window.WorkbenchPdf.show(box, bytesOf(local.data));
      } catch (_) {
        box.replaceChildren(element('div', 'alert alert-warning mb-2', t('ui.workbench.pdfFailed', 'The PDF could not be shown.')));
      }
    }
    const line = element('div', 'text-secondary mt-2');
    line.appendChild(element('code', null, local.name || ''));
    const size = sizeText(local.size);
    if (size) line.appendChild(document.createTextNode(` · ${size}`));
    info.appendChild(line);
    view.replaceChildren(body, info);
  }

  function bringPane() {
    const lc = window.LayoutController;
    if (!lc) return;
    if (lc.isMenuHidden()) lc.setMenuHidden(false);
    if (lc.selectedPane() !== 'work') lc.setPane('work');
  }

  // A file the user attached, shown on the work screen: audio and video
  // the server keeps open as board items; the rest is shown from the
  // page's data.
  function showAttachment(entry) {
    if (!entry) return;
    if (entry.attachmentId && (entry.kind === 'audio' || entry.kind === 'video')) {
      openAttachment(entry);
      return;
    }
    // The same file, still drawn: shown as it is.
    if (local && !local.note && local.key === entry.key && local.data === entry.data && (local.kind !== 'pdf' || localPdf)) {
      bringPane();
      return;
    }
    clearLocal();
    localSerial += 1;
    local = Object.assign({}, entry, { note: null, serial: localSerial });
    bringPane();
    if (selected) select(null);
    else draw();
  }

  function openAttachment(entry) {
    if (typeof window.safeWsSend !== 'function') return;
    attachmentRequest += 1;
    clearLocal();
    localSerial += 1;
    local = Object.assign({}, entry, { note: null, waiting: attachmentRequest, serial: localSerial });
    bringPane();
    if (selected) select(null);
    else draw();
    window.safeWsSend({ message: 'WORKBENCH_OPEN_ATTACHMENT', attachment_id: String(entry.attachmentId),
                        request: attachmentRequest });
  }

  // The server's answer to the latest request to open an attachment.
  function onAttachmentOpened(data) {
    if (!data || !local || local.waiting !== data.request) return;
    if (data.status !== 'accepted') {
      local = Object.assign({}, local, { note: data.reason || 'failed', waiting: null });
      draw();
      return;
    }
    clearLocal();
    if (data.item_id && itemById(data.item_id)) showOpened(data.item_id);
    else pendingOpen = data.item_id || null;
  }

  // A file of a sent message (its card): a PDF from the message's own data.
  function onCardClick(e) {
    const preview = e.target && e.target.closest ? e.target.closest('#discourse .pdf-preview') : null;
    const attachment = e.target && e.target.closest ? e.target.closest('#discourse .message-attachments [data-attachment-id]') : null;
    if (attachment) {
      showAttachment({ source: 'message', key: `message:${attachment.dataset.attachmentId}`,
                       kind: attachment.dataset.purpose === 'audio' ? 'audio' : 'video',
                       name: attachment.dataset.name || '', attachmentId: attachment.dataset.attachmentId });
      return;
    }
    if (!preview) return;
    const card = preview.closest('.card');
    const title = (preview.textContent || '').trim();
    const messages = window.SessionState && typeof window.SessionState.getMessages === 'function'
      ? window.SessionState.getMessages() : [];
    const message = (Array.isArray(messages) ? messages : []).find((m) => m && card && m.mid === card.id);
    const file = message && Array.isArray(message.images) ? message.images.find((i) => i && i.title === title) : null;
    showAttachment({ source: 'message', key: `message:${card ? card.id : ''}:${title}`, kind: 'pdf', name: title,
                     data: file && typeof file.data === 'string' ? file.data : null });
  }

  function onDraftsChanged() {
    const entries = window.AttachmentDrafts && typeof window.AttachmentDrafts.list === 'function'
      ? window.AttachmentDrafts.list() : [];
    if (local && local.source === 'draft' && !entries.some((entry) => entry.key === local.key)) {
      clearLocal();
      drawView();
    }
    drawDrafts();
  }

  if (typeof document !== 'undefined') {
    document.addEventListener('attachments:changed', onDraftsChanged);
    document.addEventListener('click', onCardClick);
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
      const reason = data.reason === 'busy' ? t('ui.workbench.busy', 'The work screen is reading other files. Try again in a moment.')
        : data.reason === 'changed' ? t('ui.workbench.changedSinceShown', 'The file changed after it was shown.') : (data.reason || '');
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
    if (typeof data.seq === 'number') answeredSeq = data.seq;
    serverSelected = data.item_id || null;
    serverSerial = typeof data.serial === 'number' ? data.serial : null;
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
    if (target && target.closest && target.closest('audio, video, .workbench-text, .workbench-pdf, .workbench-rendered')) return;
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

  // What a message records its reply showed on the work screen: one line
  // per file. The line selects the item when the board has that version;
  // otherwise it opens that version, which the server checks.
  function drawShown(mid, list) {
    if (!mid) return;
    const entries = (Array.isArray(list) ? list : []).filter((e) => e && typeof e.path === 'string' && typeof e.sha256 === 'string');
    if (entries.length === 0) shownRecords.delete(mid);
    else shownRecords.set(mid, entries);
    const card = $id(mid);
    const text = card ? card.querySelector('.card-text') : null;
    if (!text) return;
    let el = text.querySelector(':scope > .workbench-shown-note');
    if (entries.length === 0) {
      if (el) el.remove();
      return;
    }
    if (!el) {
      el = element('div', 'workbench-shown-note small text-secondary mt-2');
      text.appendChild(el);
    }
    el.replaceChildren();
    entries.forEach((entry) => {
      const line = element('div', 'workbench-note-line');
      line.appendChild(element('i', 'fa-solid fa-display me-1'));
      line.appendChild(document.createTextNode(`${t('ui.workbench.shownOn', 'Shown in the work screen')}: `));
      const open = element('button', 'btn btn-link btn-sm p-0 align-baseline workbench-shown-open');
      open.type = 'button';
      open.title = t('ui.workbench.open', 'Show in the work screen');
      open.appendChild(element('code', null, String(entry.name || entry.path)));
      open.addEventListener('click', () => {
        const item = items().find((i) => i.kind === 'file' && i.path === entry.path && i.sha256 === entry.sha256);
        if (item) openItem(item.id);
        else openFile(entry.path, entry.sha256);
      });
      line.appendChild(open);
      el.appendChild(line);
    });
  }

  // What a message records as made (with the message).
  function drawRecord(mid, artifacts) {
    if (!mid || !Array.isArray(artifacts)) return;
    if (artifacts.length === 0) records.delete(mid);
    else records.set(mid, artifacts);
    drawNote(mid);
  }

  window.Workbench = {
    onView, onResult, onDownload, onOpened, onSelected, onCapture, drawRecord, drawLooks, drawShown, select, openFile, step,
    showAttachment, onAttachmentOpened, shownAttachment: () => (local ? Object.assign({}, local) : null),
    textLines, rangeNow,
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
