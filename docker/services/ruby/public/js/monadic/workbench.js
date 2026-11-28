/**
 * The workbench in the work screen pane, and its trace in the conversation.
 *
 * The pane lists the items of the chat's workbench (the chat's browser,
 * each image the assistant made, each file of the shared folder opened
 * there) in the order they came, and shows the one selected; ← and → (and the
 * buttons beside the item) move along the row. An item shows with its
 * path in the shared folder (every image is kept in the chat's folder
 * there) and "Save as…" (in the desktop app; "Download" in a browser),
 * which saves the file under its own name; a file shows as an image, as text with its line numbers, as audio or
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
  // The address of the picture under each whiteboard (served for one drawn
  // on a picture).
  let backgrounds = {};
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
  // Items that came to a work screen with nothing on it, until the work
  // screen is shown or one of them is offered (the chat's first).
  const firsts = new Set();
  // Images removed from here (not put away by the board to make room).
  const removed = new Set();
  // What each message records as made, as last drawn.
  const records = new Map();
  // What each message records its reply looked at (mid → list).
  const looks = new Map();
  // What each message records its reply showed on the work screen.
  const shownRecords = new Map();
  let askedViewAt = 0;
  // What the server last said this tab has selected, and the number of
  // that selection (a capture names it).
  let serverSelected = null;
  let serverSerial = null;
  // A file the user asked to open: the pane is shown when it comes.
  let opening = null;
  // An item the user opened, shown as soon as the board has it.
  let pendingOpen = null;
  // A section of a document (Workbench::Document) a line under a reply
  // opens at: { path, section }, scrolled to once the document is drawn.
  let pendingSection = null;
  // What the pane drew for the item shown, kept while it is the same item
  // at the same version (media keep playing, text keeps its scroll): its
  // key (item and version), node, the address it was drawn from, and
  // whether getting it failed (then a view with a new address draws it
  // again).
  let drawnBody = null;
  // What is drawn of the other items of the row, shown under and above the
  // one chosen, by item id (each as drawnBody is).
  const others = new Map();
  // The number of this tab's latest selection told to the server: an
  // answer to an older one is not taken.
  let selectSeq = 0;
  // A file the user attached, shown here from the page's own data (draft:
  // the message being written; message: one sent): { source, key, kind,
  // name, size, data, attachmentId, note }. Never a board item: while one is
  // shown nothing of the board is selected, so neither a message's range
  // nor a look names a board item.
  let local = null;
  // The pointer change last sent with a message: the drawing's handle and
  // the number of its change (a picture goes with a message only after the
  // user placed or moved the pointer).
  let sentPointer = { handle: null, seq: 0 };
  // The text the user selected in the PDF shown, held from when they
  // selected it (putting the cursor in the message box takes the page's
  // selection away) until it is sent, set aside with ×, or replaced by
  // another selection: { key, item_id, version, page, pages, text, cut }.
  // set aside and sent: the key of the selection set aside or sent last (it
  // is not offered again until another is selected).
  let heldSelection = null;
  // Where the AI pointed last, in the file at path and version ({ path,
  // version, point: { lines } | { page, quote }, label }), and whether it
  // is still to be brought into view.
  let aiPoint = null;
  let aiPointToShow = false;
  let selectionSetAside = null;
  let selectionSent = null;
  // Characters of a selection sent with a message, at most.
  const SELECTION_SEND_LIMIT = 2000;
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

  // The user is writing something: a field in focus that has text. The
  // message box takes the focus after each reply, so focus alone is not
  // writing.
  const TEXT_INPUTS = ['', 'text', 'search', 'email', 'url', 'tel', 'password'];

  function writing() {
    const el = document.activeElement;
    if (!el) return false;
    let text = null;
    if (el.isContentEditable) text = el.textContent;
    else if (el.tagName === 'TEXTAREA') text = el.value;
    else if (el.tagName === 'INPUT' && TEXT_INPUTS.includes(el.getAttribute('type') || '')) text = el.value;
    return typeof text === 'string' && text !== '';
  }

  // A path in a line under an item is shown by its file name (short-paths.js).
  function shortenPaths(el) {
    if (window.ShortPaths) window.ShortPaths.apply(el);
  }

  // "Save as…" in the desktop app (it asks where to save); "Download" in a
  // browser.
  function saveLabel() {
    return window.electronAPI ? t('ui.workbench.saveAs', 'Save as…') : t('ui.workbench.download', 'Download');
  }

  function statusText(status, item) {
    if (item && item.kind === 'library') {
      if (status === 'changed') return t('ui.workbench.libraryChanged', 'This entry changed in the Library after it was opened here: open it again.');
      if (status === 'missing') return t('ui.workbench.libraryMissing', 'This entry is no longer in the Library.');
    }
    if (status === 'changed' && item && item.kind === 'file') {
      return t('ui.workbench.fileChanged', 'This file changed in the shared folder after it was opened here.');
    }
    if (status === 'changed') return t('ui.workbench.changed', 'This file changed in the shared folder after it was made.');
    if (status === 'missing') return t('ui.workbench.missing', 'This file is no longer in the shared folder.');
    return '';
  }

  // The items in the row, in the order they came.
  function rowItems() {
    return items().filter((item) => ['image', 'file', 'library', 'browser'].includes(item.kind));
  }

  // An item drawn by what its content is (a file, or an entry of the
  // Library shown as its text), not by what made it.
  function previewed(item) {
    return item.kind === 'file' || item.kind === 'library';
  }

  // ---- the pane ------------------------------------------------------

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  // A shared button (buttons.css): className gives its meaning or form.
  function button(label, className, onClick) {
    const el = element('button', `btn btn-sm ${className}`, label);
    el.type = 'button';
    el.addEventListener('click', onClick);
    return el;
  }

  // The user's operation on an item (remove, stash: put away, bring: into
  // Now), with a new id: the same id is sent again only when the same
  // message is resent. Nothing is asked while a reply runs.
  function act(item, action) {
    const token = item && approvals[item.id];
    if (!token || typeof window.safeWsSend !== 'function') return;
    if (locked()) {
      warn(lockText());
      return;
    }
    // A board leaving Now is kept as saved: what was drawn goes first.
    if (action !== 'bring' && afterWhiteboardSaves(() => act(itemById(item.id) || item, action))) return;
    window.safeWsSend({
      message: 'WORKBENCH_ACTION', item_id: item.id, action: action, token: token, operation_id: newOperationId()
    }, { idempotent: true });
  }

  // While a reply runs, the user does not change the work screen.
  function locked() {
    return !!(board && board.replying);
  }

  function lockText() {
    return t('ui.workbench.replyingLock', 'The work screen can be changed when the reply ends.');
  }

  // Where an item is: a place of the desk, or put away (an item the board
  // names no place for is in Now).
  function placeOf(item) {
    if (!item) return 'stash';
    return item.place === 'stash' ? 'stash' : (['current', 'latest', 'previous'].includes(item.place) ? item.place : 'current');
  }

  // Whether marks can be made on the item now (Now or Latest, no reply).
  function markable(item) {
    return !locked() && ['current', 'latest'].includes(placeOf(item));
  }

  // Asks the server for an address to save an image (artifact_id) or a
  // file item at the version shown (item_id and sha256) from; the file is
  // fetched when it comes (onDownload), so a failure never leaves the page.
  function download(ids) {
    if (!ids || typeof window.safeWsSend !== 'function') return;
    window.safeWsSend(Object.assign({ message: 'WORKBENCH_DOWNLOAD' }, ids));
  }

  function saveButton(artifactId, className) {
    return button(saveLabel(), className, () => download({ artifact_id: artifactId }));
  }

  // A document is named by its title; every other file by its name.
  function label(item) {
    return item.kind === 'browser' ? t('ui.workbench.browser', 'Browser') : (item.title || item.name || '');
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

  // An item's two parts: what it holds (left in place while it is
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
    // The browser in use takes the place of the desk; a button goes back.
    if (browserArea) browserArea.hidden = !live;
    drawBack(live);
    if (!view) return;
    // A past turn's desk, while shown, stands in for the present one.
    view.hidden = live || !!past;
    if (live) return;
    if (item) view.dataset.item = item.id;
    else delete view.dataset.item;
    drawSections(view, item);
  }

  // While a reply runs: a line says so, and what changes the work screen
  // is not offered (each of those checks again when used).
  function drawLock() {
    const pane = $id('work-screen-pane');
    const on = locked();
    if (pane) pane.classList.toggle('workbench-replying', on);
    ['workbench-put', 'workbench-new-whiteboard', 'workbench-open-url'].forEach((id) => {
      const el = $id(id);
      if (el) el.disabled = on;
    });
    let line = $id('workbench-lock');
    const head = document.querySelector('#work-screen-pane .workbench-head');
    if (!line && head && on) {
      line = element('div', 'workbench-lock text-secondary mb-2', lockText());
      line.id = 'workbench-lock';
      line.setAttribute('role', 'status');
      head.appendChild(line);
    }
    if (line) line.hidden = !on;
  }

  // Back from the browser to the desk.
  function drawBack(shown) {
    const area = $id('work-screen-browser');
    if (!area) return;
    let back = area.querySelector(':scope > .workbench-back');
    if (!shown) {
      if (back) back.hidden = true;
      return;
    }
    if (!back) {
      back = button(t('ui.workbench.backToDesk', 'Back to the work screen'), 'btn-secondary btn-outline workbench-back mb-2',
        () => select(null));
      area.insertBefore(back, area.firstChild);
    }
    back.hidden = false;
  }

  // ---- an earlier turn's desk -----------------------------------------

  // The turn shown from a card ({ mid, turn, request }), or null: the
  // present desk is hidden meanwhile, so nothing of it is said to be in
  // view and nothing of the past one goes with a message.
  let past = null;
  let turnRequest = 0;

  // Shows the work screen as the turn of the card mid left it (its number
  // turn, when known); the same card again goes back to now.
  function showTurn(mid, turn) {
    if (!mid || typeof window.safeWsSend !== 'function') return;
    if (past && past.mid === mid) {
      backToNow();
      return;
    }
    turnRequest += 1;
    past = { mid: mid, turn: turn || null, request: turnRequest };
    window.safeWsSend({ message: 'WORKBENCH_TURN_VIEW', mid: mid, request: turnRequest });
    const lc = window.LayoutController;
    if (lc && typeof lc.setPane === 'function') lc.setPane('work');
  }

  // The server's answer: drawn when it is for the turn asked last (a late
  // answer for one asked before is let go).
  function onTurnView(data) {
    if (!past || !data || data.request !== past.request || data.mid !== past.mid) return;
    const box = turnBox();
    if (!box || !window.WorkbenchTurn) return;
    window.WorkbenchTurn.show(box, data, {
      turn: past.turn, t: t, back: backToNow,
      canBring: (id) => !locked() && !!approvals[id] && !!itemById(id) && placeOf(itemById(id)) !== 'current',
      bring: (id) => {
        const item = itemById(id);
        if (item) act(item, 'bring');
        backToNow();
      }
    });
    box.hidden = false;
    markShownCard(past.mid);
    const view = $id('workbench-view');
    if (view) view.hidden = true;
  }

  function backToNow() {
    past = null;
    const box = turnBox();
    if (box) {
      box.hidden = true;
      box.replaceChildren();
    }
    markShownCard(null);
    draw();
  }

  function turnBox() {
    return $id('workbench-turn');
  }

  // The card whose turn is shown is outlined.
  function markShownCard(mid) {
    document.querySelectorAll('.card.is-turn-shown').forEach((card) => card.classList.remove('is-turn-shown'));
    const card = mid ? $id(mid) : null;
    if (card) card.classList.add('is-turn-shown');
  }

  // The desk and the drawer in view (WorkbenchPlaces), made once for it.
  let places = null;
  function placesIn(view) {
    if (!places || !view.contains(places.regions.desk.root)) {
      places = window.WorkbenchPlaces.build(view, t);
      nearObservers.clear();
      wirePlaces(places);
    }
    return places;
  }

  function sectionOf(id) {
    const view = $id('workbench-view');
    if (!view) return null;
    return Array.from(view.querySelectorAll('.workbench-section')).find((node) => node.dataset.item === id) || null;
  }

  // The present desk: Now, then Latest, one under another, each tagged with
  // who placed it and when; the one chosen (the tab's focus) with its
  // buttons and its pointer, the others as they are, drawn once they come
  // near the view. Put away, in the drawer, newest first, a row each (the
  // one chosen opened in its place, to read). Before is not shown: an
  // earlier turn's desk is shown from its card in the conversation.
  function drawSections(view, focus) {
    const at = placesIn(view);
    const row = rowItems();
    const regionOf = (item) => window.WorkbenchPlaces.regionOf(placeOf(item));
    const opened = (item) => regionOf(item) === 'desk' || (regionOf(item) === 'stash' && !!focus && item.id === focus.id);
    const shownIds = new Set(row.filter(opened).map((item) => item.id));
    const kept = new Map();
    window.WorkbenchPlaces.PLACES.forEach((region) => {
      Array.from(at.regions[region].body.children).forEach((node) => {
        if (node.classList.contains('workbench-section') && shownIds.has(node.dataset.item)) kept.set(node.dataset.item, node);
        else node.remove();
      });
    });
    others.forEach((drawn, id) => {
      if (shownIds.has(id)) return;
      letGo(drawn);
      others.delete(id);
    });
    const of = (place) => row.filter((item) => placeOf(item) === place);
    const lists = { desk: of('current').concat(of('latest')), stash: of('stash').reverse() };
    window.WorkbenchPlaces.PLACES.forEach((region) => {
      const body = at.regions[region].body;
      lists[region].forEach((item, index) => {
        const node = opened(item) ? (kept.get(item.id) || section(item)) : stashRow(item);
        if (body.children[index] !== node) body.insertBefore(node, body.children[index] || null);
        if (opened(item)) nearby(node, body);
      });
    });
    at.fill({ current: of('current').length, latest: of('latest').length, stash: lists.stash.length },
      { limit: board && board.now_limit });
    // The one chosen first: what was drawn for the one before is kept for
    // it among the others.
    if (focus && shownIds.has(focus.id)) drawFocus(focus, kept.get(focus.id) || sectionOf(focus.id));
    row.forEach((item) => {
      if ((focus && item.id === focus.id) || !opened(item)) return;
      drawOther(item, sectionOf(item.id));
    });
  }

  // A put-away item: its kind, its name (opening it here, to read) and
  // a button that brings it into Now.
  function stashRow(item) {
    const node = element('div', 'workbench-stash-row');
    node.dataset.item = item.id;
    const grip = gripOf(item);
    if (grip) node.appendChild(grip);
    const open = element('button', 'workbench-stash-open');
    open.type = 'button';
    open.appendChild(element('i', `fa-solid ${kindIcon(item)} me-1`));
    open.appendChild(element('span', 'workbench-stash-name', label(item)));
    open.title = t('ui.workbench.stashOpen', 'Open it here to read (the AI does not read it)');
    open.addEventListener('click', () => select(item.id));
    node.appendChild(open);
    node.appendChild(movesOf(item));
    return node;
  }

  function kindIcon(item) {
    if (item.kind === 'image' || item.preview === 'image') return 'fa-image';
    if (item.kind === 'browser') return 'fa-globe';
    if (item.kind === 'library') return 'fa-book';
    if (item.preview === 'pdf') return 'fa-file-pdf';
    if (item.preview === 'audio') return 'fa-file-audio';
    if (item.preview === 'video') return 'fa-file-video';
    return 'fa-file-lines';
  }

  // Everything done with an item, in one menu beside its name (as the
  // side column's lists have it): moving it, its marks, saving it, keeping
  // it in the Library, drawing on it, reading it again, and taking it off.
  function itemActions(item) {
    const place = placeOf(item);
    const movable = !!approvals[item.id];
    const busy = locked();
    const entries = [];
    const add = (text, icon, action, extra) => entries.push(Object.assign({ label: text, icon: `fa-solid ${icon}`, action: action }, extra || {}));
    if (movable && place !== 'current') {
      add(t('ui.workbench.bring', 'Into Now'), 'fa-arrow-up-from-bracket', () => act(item, 'bring'), { disabled: busy });
    }
    if (movable && place !== 'stash') {
      add(t('ui.workbench.stash', 'Put away'), 'fa-box-archive', () => act(item, 'stash'), { disabled: busy });
    }
    const kept = earlierMarksOf(item).length + (earlierDrawingOf(item).length > 0 ? item.drawing.digests.length : 0);
    if (movable && kept > 0 && ['current', 'latest'].includes(place)) {
      add(t('ui.workbench.eraseMarks', 'Erase marks ({n})').replace('{n}', String(kept)), 'fa-eraser', () => eraseMarks(item),
        { disabled: busy });
    }
    const ok = item.status === 'ok';
    if (ok && item.artifact_id) {
      add(saveLabel(), 'fa-floppy-disk', () => download({ artifact_id: item.artifact_id }));
    } else if (ok && item.kind === 'file' && item.sha256 && !(Number(item.size) > WHOLE_LIMIT)) {
      add(saveLabel(), 'fa-floppy-disk', () => download({ item_id: item.id, sha256: item.sha256 }));
    }
    // A document the Library takes is kept there as this version.
    if (ok && item.kind === 'file' && item.library && item.sha256) {
      add(t('ui.workbench.toLibrary', 'Keep in the Library'), 'fa-book', () => keepInLibrary(item));
    }
    // An image can be drawn on: a whiteboard with it laid under.
    if (ok && item.sha256 && (item.artifact_id || (item.kind === 'file' && item.preview === 'image'))) {
      add(t('ui.workbench.wb_drawOn', 'Draw on it'), 'fa-pen', () => drawOn(item), { disabled: busy });
    }
    // A whiteboard shown here is also written out as a picture.
    if (ok && isWhiteboard(item) && drawnBody && drawnBody.key === drawKey(item) && drawnBody.whiteboard) {
      ['svg', 'png', 'pdf'].forEach((kind) => {
        add(`${t('ui.workbench.wb_export', 'Export')} ${kind.toUpperCase()}`, 'fa-file-export',
          () => { if (drawnBody && drawnBody.key === drawKey(item) && drawnBody.whiteboard) drawnBody.whiteboard.exportAs(kind); });
      });
    }
    // A file is read again where it is shown (the board takes it at the
    // version it has now).
    if (item.kind === 'file' && item.status === 'changed') {
      add(t('ui.workbench.reopen', 'Open it as it is now'), 'fa-rotate-right', () => openFile(item.path));
    } else if (item.kind === 'file' && ok) {
      add(t('ui.workbench.reload', 'Reload'), 'fa-rotate-right', () => openFile(item.path));
    }
    if (item.kind === 'file' && ok && /\.ipynb$/i.test(item.path || '')) {
      add(t('ui.workbench.jupyterOpen', 'Open in JupyterLab'), 'fa-book-open', () => openInJupyter(item.path));
    }
    // A document put together from sections: its earlier versions.
    if (item.kind === 'file' && ok && DOCUMENT_PATH.test(item.path || '')) {
      add(t('ui.workbench.versions', 'Versions'), 'fa-clock-rotate-left', () => { if (selected !== item.id) select(item.id); askVersions(item.path); });
    }
    // Taken off the work screen: only what was placed in this turn and not
    // sent (anything else is put away above).
    if (movable && place !== 'stash' && (item.fresh || item.kind === 'browser')) {
      if (entries.length > 0) entries.push('divider');
      add(t('ui.workbench.remove', 'Remove from the work screen'), 'fa-xmark', () => act(item, 'remove'), { danger: true, disabled: busy });
    }
    return entries;
  }

  // The button that opens an item's menu.
  function movesOf(item) {
    const group = element('span', 'workbench-section-moves');
    const more = element('button', 'btn btn-sm btn-icon sfp-row-menu workbench-item-menu');
    more.type = 'button';
    more.setAttribute('aria-haspopup', 'menu');
    more.setAttribute('aria-expanded', 'false');
    more.setAttribute('aria-label', t('ui.workbench.actionsOf', 'Actions for {name}').replace('{name}', label(item)));
    more.appendChild(element('i', 'fa-solid fa-ellipsis'));
    more.addEventListener('click', (e) => {
      e.stopPropagation();
      if (window.RowMenu) window.RowMenu.open(more, itemActions(itemById(item.id) || item));
    });
    group.appendChild(more);
    return group;
  }

  // What an item is dragged by: into Now or to Put away.
  const DRAG_TYPE = 'application/x-monadic-workbench-item';
  function gripOf(item) {
    if (!approvals[item.id]) return null;
    const grip = element('span', 'workbench-grip');
    grip.draggable = true;
    grip.title = t('ui.workbench.dragToMove', 'Drag into Now or Put away');
    grip.appendChild(element('i', 'fa-solid fa-grip-vertical'));
    grip.addEventListener('dragstart', (e) => {
      if (!e.dataTransfer || locked()) {
        e.preventDefault();
        return;
      }
      e.dataTransfer.setData(DRAG_TYPE, item.id);
      e.dataTransfer.effectAllowed = 'move';
    });
    return grip;
  }

  // The desk (into Now) and the drawer (put away) take a dragged item; a
  // file from the computer is the pane's (wirePut).
  function wirePlaces(at) {
    [['desk', 'current', 'bring'], ['stash', 'stash', 'stash']].forEach(([region, place, action]) => {
      const root = at.regions[region].root;
      const carries = (e) => e.dataTransfer && Array.from(e.dataTransfer.types || []).includes(DRAG_TYPE);
      root.addEventListener('dragover', (e) => {
        if (!carries(e)) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
      });
      root.addEventListener('drop', (e) => {
        if (!carries(e)) return;
        e.preventDefault();
        e.stopPropagation();
        const item = itemById(e.dataTransfer.getData(DRAG_TYPE));
        if (item && placeOf(item) !== place) act(item, action);
      });
    });
    window.WorkbenchPlaces.PLACES.forEach((region) => {
      $on(at.regions[region].body, 'scroll', () => {
        unpin();
        placeJump();
      }, { passive: true });
    });
  }

  // An item's part of the view: its name (choosing it; the one chosen is
  // named by its tab), what it holds, and what is said about it.
  function section(item) {
    const node = element('section', 'workbench-section');
    node.dataset.item = item.id;
    const bar = element('div', 'workbench-section-bar');
    const head = element('button', 'workbench-section-head');
    head.type = 'button';
    head.addEventListener('click', () => choose(node));
    bar.appendChild(head);
    node.append(bar, element('div', 'workbench-body'), element('div', 'workbench-info'));
    // Touching another item, or moving to it with the keyboard, makes it
    // the one chosen (where the pointer and the buttons are). Its move
    // buttons and grip act at once.
    node.addEventListener('pointerdown', (e) => {
      if (e.target.closest && e.target.closest('.workbench-section-moves, .workbench-grip')) return;
      if (choose(node)) node.dataset.chosenBy = 'touch';
    }, true);
    node.addEventListener('click', (e) => {
      if (node.dataset.chosenBy !== 'touch') return;
      delete node.dataset.chosenBy;
      e.preventDefault();
      e.stopPropagation();
    }, true);
    node.addEventListener('focusin', () => choose(node));
    nearby(node);
    return node;
  }

  // Choosing another item by touching it: that touch only chooses (a click
  // that follows does not also act, such as showing an image larger).
  function choose(node) {
    const id = node.dataset.item;
    if (id === selected || !itemById(id)) return false;
    select(id, false);
    return true;
  }

  function headOf(node, item, focused) {
    const bar = node.querySelector(':scope > .workbench-section-bar');
    const head = bar && bar.querySelector(':scope > .workbench-section-head');
    if (!head) return;
    head.textContent = label(item);
    head.setAttribute('aria-current', focused ? 'true' : 'false');
    Array.from(bar.querySelectorAll(':scope > .workbench-grip, :scope > .workbench-item-tag, :scope > .workbench-section-moves'))
      .forEach((el) => el.remove());
    const grip = gripOf(item);
    if (grip) bar.insertBefore(grip, head);
    const tag = tagOf(item);
    if (tag) bar.appendChild(tag);
    bar.appendChild(movesOf(item));
  }

  // Who placed a desk item and when: in Now (this turn), or in Latest (the
  // turn before, the other side's or the user's own).
  function tagOf(item) {
    const place = placeOf(item);
    if (place !== 'current' && place !== 'latest') return null;
    const by = place === 'latest' ? ((board && board.layers && board.layers.latest) || item.by) : item.by;
    const who = by === 'agent' ? t('ui.workbench.placeByAgent', 'AI') : t('ui.workbench.placeByUser', 'You');
    const when = place === 'current' ? t('ui.workbench.placeNow', 'Now') : t('ui.workbench.placeLatest', 'Latest');
    const tag = element('span', `workbench-item-tag is-${place} is-by-${by === 'agent' ? 'agent' : 'user'}`, `${who} · ${when}`);
    return tag;
  }

  // The others are drawn once near the view of their place (an image, a
  // PDF, a text read only when it may be seen): one watcher for each place,
  // whose body scrolls on its own; an item moved to another place is
  // watched there.
  const nearObservers = new Map();
  function nearby(node, body) {
    if (typeof IntersectionObserver !== 'function' || node.dataset.near === 'true') return;
    if (node.nearIn === body) return;
    if (node.nearIn && nearObservers.has(node.nearIn)) nearObservers.get(node.nearIn).unobserve(node);
    let observer = nearObservers.get(body);
    if (!observer) {
      observer = new IntersectionObserver((entries) => {
        let came = false;
        entries.forEach((entry) => {
          if (!entry.isIntersecting || entry.target.nearIn !== body) return;
          entry.target.dataset.near = 'true';
          observer.unobserve(entry.target);
          came = true;
        });
        if (came) drawView();
      }, { root: body, rootMargin: '400px 0px' });
      nearObservers.set(body, observer);
    }
    node.nearIn = body;
    observer.observe(node);
  }

  function drawOther(item, node) {
    node.classList.remove('is-focus');
    headOf(node, item, false);
    const { held, info } = viewParts(node);
    if (window.MonadicTip) window.MonadicTip.disposeWithin(info);
    info.replaceChildren();
    show(held, otherBody(item, node));
  }

  function otherBody(item, node) {
    if (item.kind === 'browser') {
      return element('div', 'alert alert-secondary small mb-2', item.status === 'open'
        ? t('ui.workbench.browserChoose', 'Choose it to show the browser.')
        : t('ui.workbench.browserClosed', 'This browser was closed.'));
    }
    if (item.status !== 'ok') return element('div', 'alert alert-warning small mb-2', statusText(item.status, item));
    if (item.preview === 'file') return heldFileBody(item);
    // One whiteboard is shown at a time: the one chosen.
    if (isWhiteboard(item)) {
      return element('div', 'alert alert-secondary small mb-2',
        t('ui.workbench.wbChoose', 'Choose it to show the whiteboard. One whiteboard is shown at a time.'));
    }
    if (!assets[item.id]) return null;
    if (node.dataset.near !== 'true' && !others.has(item.id)) return element('div', 'workbench-later');
    return otherFor(item).node;
  }

  // What is drawn for another item, kept as drawnFor keeps the chosen one's.
  function otherFor(item) {
    const key = drawKey(item);
    const url = assets[item.id];
    const had = others.get(item.id);
    const same = had && had.key === key;
    if (same && !(had.failed && had.url !== url)) return had;
    const drawn = { key: key, url: url, failed: false, node: null, retried: !!(same && had.retried), itemId: item.id };
    drawn.node = body(item, drawn, 0);
    letGo(had);
    others.set(item.id, drawn);
    return drawn;
  }

  // What was drawn for the one chosen before goes among the others (its
  // mark kept, only the chosen one's goes with a message), a whiteboard let
  // go (one is shown at a time).
  function park(drawn) {
    if (!drawn) return;
    if (drawn.whiteboard || !drawn.itemId || !itemById(drawn.itemId)) {
      letGo(drawn);
      return;
    }
    // Its mark stays shown; it can no longer be changed there.
    setMarkable(drawn, false);
    if (others.get(drawn.itemId) !== drawn) letGo(others.get(drawn.itemId));
    others.set(drawn.itemId, drawn);
  }

  // Whether the drawing's marks can be made or changed (its mark, if any,
  // stays shown either way).
  function setMarkable(drawn, flag) {
    if (!drawn) return;
    if (drawn.image && typeof drawn.image.setPointable === 'function') drawn.image.setPointable(flag);
    if (drawn.pdf && typeof drawn.pdf.setPointable === 'function') drawn.pdf.setPointable(flag);
    drawn.markable = flag;
  }

  // The chosen item shows no drawing (a file only held, a file changed or
  // gone): its own is let go, another's kept.
  function dropFocusBody(item) {
    if (drawnBody && drawnBody.itemId === item.id) letGo(drawnBody);
    else park(drawnBody);
    drawnBody = null;
  }

  function letGoOthers() {
    others.forEach((drawn) => letGo(drawn));
    others.clear();
  }

  function drawFocus(item, node) {
    const { held, info } = viewParts(node);
    node.classList.add('is-focus');
    headOf(node, item, true);
    if (window.MonadicTip) window.MonadicTip.disposeWithin(info);
    info.replaceChildren();
    const place = placeOf(item);
    if (place === 'stash') {
      info.appendChild(element('div', 'text-secondary mt-1',
        t('ui.workbench.stashReading', 'Put away: you can read it here; the AI does not read it. Bring it into Now to use it.')));
    } else if (place === 'previous') {
      info.appendChild(element('div', 'text-secondary mt-1',
        t('ui.workbench.beforeNoMarks', 'Bring it into Now to mark it.')));
    }
    if (item.kind === 'browser') {
      show(held, element('div', 'alert alert-secondary small mb-2', t('ui.workbench.browserClosed', 'This browser was closed.')));
      return;
    }
    if (item.status === 'ok' && item.preview === 'file') {
      // A file the work screen only holds: what it is, not what it shows.
      dropFocusBody(item);
      show(held, heldFileBody(item));
    } else if (item.status === 'ok' && assets[item.id]) {
      const drawn = drawnFor(item);
      setMarkable(drawn, markable(item));
      show(held, drawn.node);
    } else if (item.status !== 'ok') {
      dropFocusBody(item);
      show(held, element('div', 'alert alert-warning small mb-2', statusText(item.status, item)));
    } else {
      show(held, null);
    }
    const line = element('div', 'small text-secondary mt-2');
    if (item.kind === 'library') {
      line.appendChild(element('i', 'fa-solid fa-book me-1'));
      line.appendChild(document.createTextNode(t('ui.workbench.fromLibrary', 'From the Library (its text)')));
    } else {
      line.appendChild(element('code', null, item.path || item.name || ''));
      shortenPaths(line);
    }
    info.appendChild(line);
    // A document put together from sections lists its versions here.
    if (item.kind === 'file' && item.status === 'ok' && DOCUMENT_PATH.test(item.path || '')) {
      info.appendChild(element('div', 'workbench-versions mt-2'));
    }
  }

  // The path of a document of a chat's folder.
  const DOCUMENT_PATH = /^conversations\/[^/]+\/documents\/[a-z0-9-]+\.md$/;

  // The document whose versions are listed now (asked again when the
  // board changes, so a new version shows up in the list).
  let versionsOf = null;

  function askVersions(path) {
    versionsOf = String(path);
    if (typeof window.safeWsSend === 'function') window.safeWsSend({ message: 'WORKBENCH_VERSIONS', path: versionsOf });
  }

  // The versions the server listed, under the document they are of when it
  // is still the one shown: newest first, each opening its file.
  function onVersions(data) {
    const item = selected ? itemById(selected) : null;
    const box = item && data && item.path === data.path && document.querySelector('.workbench-versions');
    if (!box) return;
    const versions = Array.isArray(data.versions) ? data.versions.slice().reverse() : [];
    if (versions.length === 0) {
      box.replaceChildren(element('div', 'small text-secondary', t('ui.workbench.noVersions', 'No versions are kept in this chat.')));
      return;
    }
    const list = element('div', 'list-group list-group-flush small');
    versions.forEach((version) => {
      const label = t('ui.workbench.versionOf', '§ {section} — version {version}')
        .replace('{section}', String(version.section)).replace('{version}', String(version.version));
      const entry = element('button', 'list-group-item list-group-item-action py-1', label);
      entry.type = 'button';
      entry.addEventListener('click', () => openFile(version.path));
      list.appendChild(entry);
    });
    box.replaceChildren(list);
  }

  // What is drawn for the item: kept while it is the same item at the same
  // version, drawn again from the new address once getting it failed (an
  // address that expired, a busy server, a reconnect). Media go on from
  // where they were.
  function drawnFor(item) {
    if (drawnBody && drawnBody.itemId !== item.id) {
      park(drawnBody);
      drawnBody = null;
    }
    if (!drawnBody && others.has(item.id)) {
      drawnBody = others.get(item.id);
      others.delete(item.id);
    }
    const key = drawKey(item);
    const url = assets[item.id];
    const same = drawnBody && drawnBody.key === key;
    if (same && drawnBody.whiteboard) syncWhiteboard(drawnBody, item);
    if (same && !(drawnBody.failed && drawnBody.url !== url)) return drawnBody;
    const resumeAt = same && drawnBody.node && typeof drawnBody.node.currentTime === 'number' ? drawnBody.node.currentTime : 0;
    // A medium that failed again with a fresh address is not asked for again.
    const drawn = { key: key, url: url, failed: false, node: null, retried: !!(same && drawnBody.retried), itemId: item.id };
    drawn.node = body(item, drawn, resumeAt);
    letGo(drawnBody);
    drawnBody = drawn;
    return drawn;
  }

  // The most a file is read whole to be saved (FileItem::LIMIT); a larger
  // one (a long video) is not saved from the work screen.
  const WHOLE_LIMIT = 64 * 1024 * 1024;
  // The icon of a file the work screen only holds, by its type.
  const HELD_ICONS = [[/wordprocessingml/, 'fa-file-word'], [/spreadsheetml/, 'fa-file-excel'],
    [/presentationml/, 'fa-file-powerpoint'], [/^video\//, 'fa-file-video'], [/^audio\//, 'fa-file-audio']];

  // What is shown of a file the work screen only holds (an Office
  // document, a MIDI file, audio or video it does not play): its name,
  // type and size, and that the tools that take it can use it.
  function heldFileBody(item) {
    const box = element('div', 'workbench-held-file');
    const type = String(item.content_type || '');
    const icon = (HELD_ICONS.find(([re]) => re.test(type)) || [null, 'fa-file'])[1];
    box.appendChild(element('i', `fa-solid ${icon} workbench-held-file-icon`));
    const about = element('div', 'workbench-held-file-about');
    about.appendChild(element('div', 'workbench-held-file-name', item.name || ''));
    const mb = (Number(item.size) || 0) / (1024 * 1024);
    about.appendChild(element('div', 'text-secondary', `${type || '?'} · ${mb >= 1 ? mb.toFixed(1) : '<1'} MB`));
    about.appendChild(element('div', 'text-secondary',
      t('ui.workbench.heldFile', 'This file is not shown here. The AI can use it with the tools that take it.')));
    box.appendChild(about);
    return box;
  }

  // ---- the whiteboard -------------------------------------------------

  // How long the user stops drawing before the board is saved.
  const WHITEBOARD_SAVE_DELAY = 1000;
  let whiteboardRequest = 0;
  // The whiteboard drawings waiting for the server's answer to a save, by
  // its request number.
  const whiteboardSaves = new Map();
  // The new whiteboards this tab asked for, by request number: the one
  // made is selected here.
  const whiteboardNews = new Set();

  // A whiteboard only looked at: one kept as it was (it left Now), and any
  // while a reply runs (the user does not change the work screen then; a
  // stroke would not be saved).
  function whiteboardStill(item) {
    return !!item.frozen || locked();
  }

  function isWhiteboard(item) {
    return !!(item && item.kind === 'file' && item.preview === 'text' && item.render === 'whiteboard');
  }

  // A whiteboard: its board, drawn from the file and saved as the user
  // draws (WORKBENCH_WHITEBOARD_SAVE).
  function whiteboardBody(item, drawn) {
    const box = element('div', 'workbench-whiteboard');
    drawn.whiteboardItem = item.id;
    drawn.whiteboardVersion = item.version || item.sha256 || '';
    // Drawn, not lines: what is in view is not told by line.
    drawn.mode = 'drawn';
    const source = { url: renders[item.id] || drawn.url,
      get failed() { return drawn.failed; }, set failed(value) { drawn.failed = value; } };
    fetchInto(box, item, source, async (response) => {
      const text = await response.text();
      if (drawn.gone) return;
      let data;
      try {
        data = JSON.parse(text);
      } catch (_) {
        data = null;
      }
      // A board that left Now is kept as it was, and none is drawn on while
      // a reply runs: shown, with why.
      const still = whiteboardStill(item);
      drawn.whiteboard = window.WorkbenchWhiteboard.show(box, data, { onChange: (next) => whiteboardChanged(drawn, next),
        name: item.name, save: saveBlob, loadPicture: () => whiteboardPicture(drawn, item.id), frozen: still,
        frozenNote: still && !item.frozen ? lockText() : undefined });
      // The version what is drawn is (the board read at it).
      drawn.loadedVersion = drawn.whiteboardVersion;
      drawn.loaded = true;
    });
    return box;
  }

  // The picture under a whiteboard drawn on one, from the address this
  // connection has for it now (a view gives a new one when it expired).
  function whiteboardPicture(drawn, id) {
    const url = backgrounds[id];
    drawn.pictureUrl = url;
    if (!url || typeof fetch !== 'function') return Promise.reject(new Error('no address'));
    return fetch(url, { credentials: 'same-origin', cache: 'no-store' }).then((response) => {
      if (!response.ok) throw new Error(String(response.status));
      return response.blob();
    });
  }

  function whiteboardChanged(drawn, data) {
    drawn.whiteboardPending = data;
    clearTimeout(drawn.whiteboardTimer);
    drawn.whiteboardTimer = setTimeout(() => saveWhiteboardNow(drawn), WHITEBOARD_SAVE_DELAY);
  }

  // Every board drawn on and not saved yet is sent now: before a message,
  // which ends the turn (its boards leave Now and are kept as saved).
  function flushWhiteboards() {
    drawnBoards().forEach((drawn) => {
      if (drawn.whiteboardPending) saveWhiteboardNow(drawn);
    });
  }

  function drawnBoards() {
    return [drawnBody].concat(Array.from(others.values())).filter((drawn) => drawn && drawn.whiteboardItem);
  }

  // How long a held step waits for the boards' saves.
  const SAVES_WAIT = 15000;
  let savesWait = null;

  // When a board has strokes not saved yet, or a save on its way: sends
  // them, and runs next once every save is answered, taken (a refusal, or
  // no answer in time, runs nothing and says so: the message stays to be
  // sent again). Returns whether it holds next (false: nothing to wait for).
  function afterWhiteboardSaves(next) {
    if (!drawnBoards().some((drawn) => drawn.whiteboardPending || drawn.whiteboardSaving)) return false;
    if (savesWait) clearTimeout(savesWait.timer);
    savesWait = { next: next, failed: false,
      timer: setTimeout(() => savesSettled(true), SAVES_WAIT) };
    flushWhiteboards();
    return true;
  }

  function savesSettled(failed) {
    if (!savesWait) return;
    if (failed) savesWait.failed = true;
    if (!savesWait.failed && drawnBoards().some((drawn) => drawn.whiteboardPending || drawn.whiteboardSaving)) return;
    const done = savesWait;
    savesWait = null;
    clearTimeout(done.timer);
    if (done.failed) warn(t('ui.workbench.wbNotSavedHeld', 'The whiteboard could not be saved, so nothing was sent. Try again.'));
    else done.next();
  }

  // Sends the board waiting to be saved, unless a save of it is still on
  // its way (it is sent when that one is answered, from the new version).
  function saveWhiteboardNow(drawn) {
    clearTimeout(drawn.whiteboardTimer);
    drawn.whiteboardTimer = null;
    if (!drawn.whiteboardPending || drawn.whiteboardSaving || typeof window.safeWsSend !== 'function') return;
    const data = drawn.whiteboardPending;
    drawn.whiteboardPending = null;
    drawn.whiteboardSaving = true;
    whiteboardRequest += 1;
    whiteboardSaves.set(whiteboardRequest, drawn);
    window.safeWsSend({ message: 'WORKBENCH_WHITEBOARD_SAVE', request: whiteboardRequest, item_id: drawn.whiteboardItem,
                        version: drawn.whiteboardVersion, data: data });
  }

  // The server's answer to a new whiteboard or a save.
  function onWhiteboard(data) {
    const drawn = data && whiteboardSaves.get(data.request);
    if (!drawn) {
      const made = !!data && whiteboardNews.delete(data.request);
      if (made && data.status === 'saved' && data.item_id) showOwn(data.item_id);
      if (data && data.status === 'refused') whiteboardRefused(data.reason);
      return;
    }
    whiteboardSaves.delete(data.request);
    drawn.whiteboardSaving = false;
    if (data.status === 'saved' && typeof data.version === 'string') {
      drawn.whiteboardVersion = data.version;
      // What is drawn is that version (and what was drawn since, waiting).
      drawn.loadedVersion = data.version;
      if (drawn.whiteboardPending && !drawn.gone) saveWhiteboardNow(drawn);
      savesSettled(false);
      return;
    }
    savesSettled(true);
    whiteboardRefused(data.reason);
    // Saved meanwhile from elsewhere, or no longer drawn on: the board as it
    // is now is drawn again.
    if ((data.reason === 'changed' || data.reason === 'whiteboard_frozen') && !drawn.gone) {
      drawn.whiteboardPending = null;
      drawn.whiteboardVersion = '';
      askView(true);
    }
  }

  // ---- a whiteboard made an image ------------------------------------

  // A board that left Now waits for its image (the view's image_pending:
  // the version to paint): this tab paints it, shown or not, from its whole
  // file (renders) off screen at its sheet's size, and sends it; the first
  // image the server takes is the board's. One at a time; each item and
  // version once while it is on its way (a failure is tried again with a
  // later view).
  const painting = new Set();
  let paintChain = Promise.resolve();

  function paintBoardImages() {
    items().forEach((item) => {
      const version = item.image_pending;
      const key = `${item.id}:${version}`;
      if (!version || !renders[item.id] || painting.has(key) || !window.WorkbenchWhiteboard) return;
      painting.add(key);
      paintChain = paintChain.then(() => paintBoardImage(item, version, renders[item.id]))
        .catch(() => painting.delete(key));
    });
  }

  async function paintBoardImage(item, version, url) {
    const response = await fetch(url, { credentials: 'same-origin', cache: 'no-store' });
    if (!response.ok) throw new Error(String(response.status));
    // A file that is not a board is not painted as an empty one.
    const data = JSON.parse(await response.text());
    const box = element('div', 'workbench-board-painting');
    box.setAttribute('aria-hidden', 'true');
    document.body.appendChild(box);
    let image = null;
    try {
      const handle = window.WorkbenchWhiteboard.show(box, data, { frozen: true });
      try {
        const size = handle.size();
        const canvas = document.createElement('canvas');
        canvas.width = size.width;
        canvas.height = size.height;
        const context = canvas.getContext('2d');
        if (context && handle.paint(context, size.width, size.height)) {
          const png = canvas.toDataURL('image/png');
          const comma = png.indexOf(',');
          if (png.startsWith('data:image/png;base64,') && comma > 0) image = png.slice(comma + 1);
        }
      } finally {
        handle.dispose();
      }
    } finally {
      box.remove();
    }
    if (!image || typeof window.safeWsSend !== 'function') throw new Error('not painted');
    // png, not image: a message's top-level image is taken as an app's
    // setting (BooleanParser) on the server.
    window.safeWsSend({ message: 'WORKBENCH_WHITEBOARD_IMAGE', item_id: item.id, version: version, png: image });
  }

  // The server's answer: made (the view that follows shows the image), done
  // (another tab's came first), or refused (tried again with a later view
  // while the board still waits).
  function onWhiteboardImage(data) {
    if (!data || data.status === 'made' || data.status === 'done') return;
    painting.delete(`${data.item_id}:${data.version}`);
  }

  function whiteboardRefused(reason) {
    if (typeof window.setAlert !== 'function') return;
    let text = t('ui.workbench.wbNotSaved', 'The whiteboard could not be saved.');
    if (reason === 'changed') text = t('ui.workbench.wbChanged', 'The whiteboard was changed elsewhere; it is shown as it is now.');
    else if (['replying', 'now_full', 'whiteboard_used', 'whiteboard_frozen'].includes(reason)) text = refusalText(reason);
    window.setAlert(text, 'warning');
  }

  // The view says the whiteboard has a version this page did not save (in
  // another tab): it is read and drawn again, unless the user is drawing.
  function syncWhiteboard(drawn, item) {
    // A picture that could not be had is asked for again with a new address.
    if (drawn.whiteboard && backgrounds[item.id] && backgrounds[item.id] !== drawn.pictureUrl) {
      drawn.whiteboard.retryPicture();
    }
    const version = item.version || item.sha256 || '';
    if (!drawn.whiteboard || version === drawn.whiteboardVersion || drawn.whiteboardSaving || drawn.whiteboardPending) return;
    drawn.whiteboardVersion = version;
    const url = renders[item.id] || assets[item.id];
    if (!url || typeof fetch !== 'function') return;
    fetch(url, { credentials: 'same-origin', cache: 'no-store' })
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => {
        if (!data || drawn.gone || drawn.whiteboardVersion !== version) return;
        drawn.whiteboard.load(data);
        drawn.loadedVersion = version;
      })
      .catch(() => {});
  }

  // A capture of a whiteboard: the whole board painted at its sheet's
  // size, when an image is asked for, only as the version asked for with
  // nothing left unsaved (lines waiting are saved now and the answer says
  // so: the server asks again for the new version), and for a board drawn
  // on a picture, once the picture is had (never on a blank sheet).
  function whiteboardAnswer(data, drawn) {
    const handle = drawn.whiteboard;
    const out = { range: {}, note: null };
    const wants = Array.isArray(data.wants) ? data.wants : [];
    if (!wants.includes('image')) return out;
    if (drawn.whiteboardPending || drawn.whiteboardSaving) {
      saveWhiteboardNow(drawn);
      return Object.assign(out, { image_note: 'saving' });
    }
    if (drawn.loadedVersion !== data.version) return Object.assign(out, { image_note: 'drawing' });
    if (!handle.pictureReady()) return Object.assign(out, { image_note: 'failed' });
    const { width, height } = handle.size();
    const board = document.createElement('canvas');
    board.width = width;
    board.height = height;
    const context = board.getContext('2d');
    if (!context || !handle.paint(context, width, height)) return Object.assign(out, { image_note: 'failed' });
    return Object.assign(out, drawnPng(board, 0, 0, width, height));
  }

  // An entry of the Library opened on the work screen (its text, as it is
  // now in the Library).
  function openLibrary(libraryId) {
    if (!libraryId || typeof window.safeWsSend !== 'function') return;
    opening = `library:${libraryId}`;
    window.safeWsSend({ message: 'WORKBENCH_OPEN_LIBRARY', library_id: String(libraryId) });
  }

  // A document of the work screen kept in the Library (as the version the
  // tab shows); the Library says how the import goes (followImport). A
  // record of a conversation is named first (keepDialog). One keep of an
  // item at a time, until its answer comes.
  const keeping = new Set();
  function keepInLibrary(item) {
    // A blank title is the record's first heading, else its file name (the server's rule).
    if (item.draft) keepDialog(item, null, '');
    else sendKeep(item, {});
  }

  function sendKeep(item, extra) {
    if (typeof window.safeWsSend !== 'function' || keeping.has(item.id)) return;
    keeping.add(item.id);
    window.safeWsSend(Object.assign({ message: 'LIBRARY_FROM_WORKBENCH', item_id: item.id, sha256: item.sha256 }, extra));
    announce(t('ui.workbench.toLibraryWorking', 'Keeping the document in the Library…'));
  }

  // The dialog for a record of a conversation: its title, and, when records
  // of the chat are kept already (records), which to update, or keep this
  // one besides.
  function keepDialog(item, records, title) {
    const dialog = $id('libraryKeepChoice');
    const titleInput = $id('library-keep-title');
    const select = $id('library-keep-target');
    if (!dialog || !titleInput || !select || !window.MonadicDialog) return;
    titleInput.value = title || '';
    const choosing = Array.isArray(records) && records.length > 0;
    $id('library-keep-records').hidden = !choosing;
    $id('library-keep-update').hidden = !choosing;
    $id('library-keep-new').textContent = choosing
      ? t('ui.libKeepChoiceNew', 'Keep as another document') : t('ui.libKeepButton', 'Keep');
    select.replaceChildren(...(choosing ? records : []).map((r) => {
      const option = document.createElement('option');
      option.value = r.id;
      option.dataset.seen = r.revision || '';
      option.textContent = `${r.title || r.id} (${String(r.created_at || '').slice(0, 16).replace('T', ' ')})`;
      return option;
    }));
    const box = window.MonadicDialog.of(dialog);
    const answer = (choice) => box.close('button').then((closed) => {
      if (!closed) return;
      const extra = { title: titleInput.value.trim() };
      if (choice) extra.choice = choice;
      sendKeep(item, extra);
    });
    $id('library-keep-update').onclick = () => {
      const chosen = select.selectedOptions[0];
      if (chosen) answer({ update: chosen.value, seen: chosen.dataset.seen });
    };
    $id('library-keep-new').onclick = () => answer(choosing ? 'new' : null);
    box.open();
  }

  const TO_LIBRARY_REASONS = {
    hides_words: ['ui.workbench.toLibraryHidesWords', 'A chat that hides words cannot keep documents in the Library.'],
    changed: ['ui.workbench.toLibraryChanged', 'The document changed; open it again to keep it in the Library.'],
    not_importable: ['ui.workbench.toLibraryNotImportable', 'The Library does not take this kind of file.'],
    too_large: ['ui.workbench.toLibraryTooLarge', 'The document is too large for the Library.'],
    not_saved_by_app: ['ui.workbench.toLibraryNotByApp', 'This app does not keep its conversations in the Library.'],
    record_changed: ['ui.workbench.toLibraryRecordChanged', 'That record changed in the Library meanwhile; keep the document again to choose.'],
    record_missing: ['ui.workbench.toLibraryRecordMissing', 'That record is no longer in the Library; keep the document again to choose.'],
    in_progress: ['ui.workbench.toLibraryInProgress', 'This conversation is being kept in the Library; try again once that is done.']
  };
  function onToLibrary(data) {
    if (!data) return;
    keeping.delete(data.item_id);
    if (data.import_id && window.libraryPanel && typeof window.libraryPanel.followImport === 'function') {
      const item = items().find((i) => i.id === data.item_id);
      window.libraryPanel.followImport(data.import_id, item ? item.name : '').catch(() => {});
      return;
    }
    if (data.error === 'choose' && Array.isArray(data.records) && data.records.length) {
      const item = items().find((i) => i.id === data.item_id);
      const titleInput = $id('library-keep-title');
      if (item) keepDialog(item, data.records, titleInput ? titleInput.value : '');
      return;
    }
    const reason = TO_LIBRARY_REASONS[data.error];
    warn(reason ? t(reason[0], reason[1]) : t('ui.workbench.toLibraryFailed', 'The document could not be kept in the Library.'));
  }

  // A new whiteboard for this chat (the server makes it and shows it in
  // this tab): plain, or on image (an item of the work screen, as the
  // version shown).
  // Draw on an image: it is chosen and its Draw is turned on (only in Now
  // or Latest, where it can be marked).
  function drawOn(item) {
    if (!['current', 'latest'].includes(placeOf(item))) {
      warn(t('ui.workbench.beforeNoMarks', 'Bring it into Now to mark it.'));
      return;
    }
    select(item.id);
    const drawn = drawnBody && drawnBody.itemId === item.id ? drawnBody : others.get(item.id);
    if (drawn && drawn.image && typeof drawn.image.startDrawing === 'function') drawn.image.startDrawing();
  }

  function newWhiteboard() {
    if (typeof window.safeWsSend !== 'function') return;
    if (locked()) {
      warn(lockText());
      return;
    }
    whiteboardRequest += 1;
    const message = { message: 'WORKBENCH_WHITEBOARD_NEW', request: whiteboardRequest };
    whiteboardNews.add(whiteboardRequest);
    window.safeWsSend(message);
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
    // A whiteboard stays drawn across its versions (each save makes one):
    // the board takes a new version in place (syncWhiteboard).
    if (isWhiteboard(item)) return `${item.id}|whiteboard${whiteboardStill(item) ? '|still' : ''}`;
    const mode = modeOf(item);
    return mode ? `${versionKey(item)}|${mode}` : versionKey(item);
  }

  function setMode(item, mode) {
    if (modeOf(item) === mode) return;
    modes.set(versionKey(item), mode);
    drawView();
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
    const kind = previewed(item) ? item.preview : 'image';
    if (kind === 'audio' || kind === 'video') {
      const media = element(kind, `workbench-${kind}`);
      media.controls = true;
      media.preload = 'metadata';
      // The address may have run out: asked for once more. Failing again,
      // the browser cannot play it, and the name is shown instead.
      media.addEventListener('error', () => {
        if (drawn.retried) {
          // Asked for again and still failing: a kind the browser does not
          // play (MEDIA_ERR_SRC_NOT_SUPPORTED), or else a failure to get or
          // decode it, which may pass when tried again.
          const unsupported = media.error && media.error.code === 4;
          media.replaceWith(element('div', 'alert alert-warning mb-2', unsupported
            ? t('ui.workbench.notPlayable', 'This kind of file is not played on the work screen.')
            : t('ui.workbench.playbackFailed', 'This file could not be played. Try again.')));
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
    if (isWhiteboard(item) && window.WorkbenchWhiteboard) return whiteboardBody(item, drawn);
    if (kind === 'text' && drawable(item)) return drawableBody(item, drawn);
    if (kind === 'text') return textBody(item, drawn);
    if (kind === 'pdf') return pdfBody(item, drawn);
    const img = enlargeable(element('img', 'workbench-image rounded'));
    img.alt = item.name || '';
    img.addEventListener('error', () => failed(drawn, false));
    img.src = url;
    return kind === 'image' && window.WorkbenchPointer ? imageBody(img, drawn) : img;
  }

  // An image with the pointer over it: the pointer's buttons in a bar above
  // it, the mark drawn over the image. drawn.image: { img, pointer(),
  // marks(), pointerSeq(), dropMarks(ids), dispose() }.
  function imageBody(img, drawn) {
    const box = element('div', 'workbench-image-view');
    const frame = element('div', 'workbench-image-frame');
    frame.append(img);
    // Dragging over the image draws a mark, not the browser's drag of it.
    img.draggable = false;
    const pointing = window.WorkbenchPointer.attach({ surface: frame, where: () => 1, changed: () => markChanged(drawn) });
    const bar = element('div', 'workbench-image-bar');
    bar.append(pointing.controls);
    const sketching = sketchOn(frame, bar, img, drawn, pointing);
    pointing.setPointable(drawn.markable !== false);
    sketching.setDrawable(drawn.markable !== false);
    box.tabIndex = 0;
    box.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && (pointing.escape() || sketching.escape())) e.preventDefault();
    });
    box.append(bar, frame);
    drawn.image = {
      img: img,
      pointer: () => pointing.pointer(),
      marks: () => pointing.marks().map(({ at, ...rest }) => Object.assign({ page: at }, rest)),
      pointerSeq: () => pointing.pointerSeq(),
      clear: () => { pointing.clear(); sketching.clear(); },
      dropMarks: (ids) => pointing.drop(ids),
      setPointable: (flag) => { pointing.setPointable(flag); sketching.setDrawable(flag); },
      startDrawing: () => sketching.start(),
      refreshDrawing: () => sketching.refresh(),
      dispose: () => { pointing.dispose(); sketching.dispose(); }
    };
    return box;
  }

  // Drawing on an image (this turn's shapes, over the earlier turns' drawn
  // lighter): a clear layer over the image with the whiteboard's tools
  // (WorkbenchWhiteboard's overlay), shown while there is anything drawn;
  // its tools in the image's bar while Draw is on. Pointing and drawing are
  // not on at once. What is drawn is kept on drawn (drawn.drawing, by the
  // item), and makes the item's picture as a mark does.
  function sketchOn(frame, bar, img, drawn, pointing) {
    const parts = window.WorkbenchPointer;
    if (!parts || typeof parts.control !== 'function' || typeof parts.group !== 'function' || !window.WorkbenchWhiteboard) {
      const none = () => false;
      return { start: none, refresh: none, escape: none, setDrawable: none, clear: none, dispose: none };
    }
    const button = window.WorkbenchPointer.control('workbench-draw-toggle', t('ui.workbench.wb_drawOn', 'Draw on it'), 'fa-solid fa-pen');
    button.setAttribute('aria-pressed', 'false');
    const controls = window.WorkbenchPointer.group(t('ui.workbench.wb_drawOn', 'Draw on it'), button);
    controls.classList.add('workbench-draw-controls');
    bar.appendChild(controls);
    const layer = element('div', 'workbench-image-draw');
    frame.appendChild(layer);
    let sketch = null;
    let tools = null;
    let drawing = false;
    let drawable = false;

    const earlier = () => earlierDrawingOf(itemById(drawn.itemId));
    const draft = () => (drawn.drawing && Array.isArray(drawn.drawing.shapes) ? drawn.drawing.shapes : []);

    // Drawn again (the image is had, its earlier drawing as the view has
    // it); none while there is nothing to show and Draw is off.
    function refresh() {
      if (sketch) {
        sketch.dispose();
        sketch = null;
      }
      if (tools) tools.remove();
      tools = null;
      layer.replaceChildren();
      if (!window.WorkbenchWhiteboard || !(img.naturalWidth > 0 && img.naturalHeight > 0)) return;
      if (!drawing && earlier().length === 0 && draft().length === 0) return;
      const size = window.WorkbenchWhiteboard.overlayFrame(img.naturalWidth, img.naturalHeight);
      sketch = window.WorkbenchWhiteboard.show(layer, { shapes: draft() }, {
        overlay: Object.assign({ earlier: earlier() }, size),
        onChange: (data) => {
          // Each change a number of its own, never given again on this item
          // (what was sent is known by it).
          drawn.drawingSeq = (drawn.drawingSeq || 0) + 1;
          drawn.drawing = { shapes: data.shapes, rev: drawn.drawingSeq };
          markChanged(drawn);
        }
      });
      tools = layer.querySelector('.workbench-whiteboard-bar');
      if (tools) {
        tools.classList.add('workbench-image-draw-tools');
        tools.hidden = !drawing;
        bar.appendChild(tools);
      }
      layer.classList.toggle('is-drawing', drawing);
    }

    function setDrawing(on) {
      drawing = !!on && drawable;
      button.setAttribute('aria-pressed', drawing ? 'true' : 'false');
      button.classList.toggle('active', drawing);
      if (drawing && typeof pointing.escape === 'function') pointing.escape();
      if (pointing.controls) pointing.controls.classList.toggle('is-off', drawing);
      refresh();
    }

    button.addEventListener('click', () => setDrawing(!drawing));
    if (img.complete && img.naturalWidth > 0) refresh();
    else img.addEventListener('load', refresh, { once: true });

    return {
      start: () => setDrawing(true),
      refresh: refresh,
      escape: () => {
        if (!drawing) return false;
        setDrawing(false);
        return true;
      },
      setDrawable: (flag) => {
        drawable = !!flag;
        controls.hidden = !drawable;
        if (!drawable && drawing) setDrawing(false);
      },
      clear: () => {
        drawn.drawing = null;
        setDrawing(false);
      },
      dispose: () => {
        if (sketch) sketch.dispose();
        sketch = null;
        if (tools) tools.remove();
      }
    };
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
      const lines = textLines(await response.text());
      // Code is highlighted by its language; each line keeps its own text.
      const render = window.WorkbenchRender;
      const html = render && typeof render.highlightedLines === 'function'
        ? render.highlightedLines(lines.join('\n'), render.codeLanguage(item.name || item.path)) : null;
      lines.forEach((lineText, i) => {
        const li = element('li', null);
        if (html && html.length === lines.length) li.innerHTML = html[i];
        else li.textContent = lineText;
        list.appendChild(li);
      });
      // The bar the selected lines' chip goes in (empty, it shows nothing).
      box.replaceChildren(element('div', 'workbench-text-bar'), list);
      drawn.lines = list;
      drawn.loaded = true;
      showHeldLines();
      showAiPoint();
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
    const bar = element('div', 'btn-panel workbench-mode mb-2');
    bar.setAttribute('role', 'group');
    bar.setAttribute('aria-label', t('ui.workbench.viewAs', 'Show the file'));
    [['drawn', t('ui.workbench.viewDrawn', 'Drawn')], ['source', t('ui.workbench.viewSource', 'Source')]].forEach(([value, label]) => {
      const choice = button(label, 'btn-tool', () => setMode(item, value));
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
          scrollToSection(box, item.path);
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
        box.replaceChildren(window.WorkbenchRender.failureNotice(e, 'alert alert-warning mb-2'),
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
      drawn.pdf = window.WorkbenchPdf.show(box, bytes, (now) => {
        if (now && now.status === 'ready') {
          showAiPoint();
          drawEarlierMarks(drawn);
        }
      }, () => markChanged(drawn));
      if (drawn.pdf && typeof drawn.pdf.setPointable === 'function') drawn.pdf.setPointable(drawn.markable !== false);
      showSelectionChip();
    });
    return box;
  }

  // The part of a drawing that scrolls (a text's lines or a drawn file).
  function scroller(drawn) {
    const node = drawn && drawn.node;
    if (!node || !node.matches) return null;
    return node.matches('.workbench-text, .workbench-rendered') ? node : node.querySelector('.workbench-rendered, .workbench-text');
  }

  // The mark a document's section begins with (a heading "§ <section>").
  function sectionMark(root, section) {
    return Array.from(root.querySelectorAll('h6')).find((h) => h.textContent.trim() === `§ ${section}`) || null;
  }

  // The drawn document at path, in box, scrolled to the section asked for
  // (pendingSection), once.
  function scrollToSection(box, path) {
    if (!box || !pendingSection || pendingSection.path !== path) return false;
    const mark = sectionMark(box, pendingSection.section);
    pendingSection = null;
    if (!mark) return false;
    box.scrollTop += mark.getBoundingClientRect().top - box.getBoundingClientRect().top;
    return true;
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
    if (drawn.image) drawn.image.dispose();
    if (drawn.whiteboard) {
      saveWhiteboardNow(drawn);
      drawn.whiteboard.dispose();
    }
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
      shortenPaths(line);
      if (item && item.status !== 'ok') {
        line.appendChild(document.createTextNode(` — ${statusText(item.status, item)}`));
      } else {
        line.appendChild(document.createTextNode(' '));
        line.appendChild(saveButton(entry.id, 'btn-link p-0 align-baseline workbench-save'));
      }
      el.appendChild(line);
    });
    localizeOfferLine(text, entries);
  }

  // The reply's line naming the image it made, which the server writes in
  // English (Offer.reply_text) and the model reads as it is: shown in the
  // page's language. It is the reply's paragraph whose one code is the
  // path of an image the message made.
  function localizeOfferLine(text, entries) {
    const paths = new Set(entries.map((entry) => String(entry.path)));
    text.querySelectorAll('p').forEach((p) => {
      if (p.closest('.workbench-note')) return;
      const codes = p.querySelectorAll('code');
      // A path the page shortened keeps the whole one (ShortPaths).
      if (codes.length !== 1 || !paths.has(codes[0].dataset.fullPath || codes[0].textContent)) return;
      p.replaceChildren(document.createTextNode(`${t('ui.workbench.offerLine', 'The image is in the work screen and in the shared folder:')} `), codes[0]);
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
      // The image it sent, as kept in the chat's folder.
      if (typeof entry.image_sha256 === 'string' && SENT_STATES.includes(entry.state)) {
        line.appendChild(document.createTextNode(' '));
        line.appendChild(sentImageButton(mid, entry.image_sha256, t('ui.workbench.lookShowImage', 'Show the image sent')));
      }
      el.appendChild(line);
    });
  }

  // The states of a look whose image left for the provider.
  const SENT_STATES = ['sent', 'refused', 'unknown'];

  // A button that shows an image the message mid sent (sha256), as the
  // chat's folder keeps it (WORKBENCH_SENT_IMAGE).
  function sentImageButton(mid, sha256, label) {
    const button = element('button', 'btn btn-link btn-sm p-0 align-baseline workbench-sent-open', label);
    button.type = 'button';
    button.dataset.sha256 = sha256;
    button.addEventListener('click', () => {
      if (typeof window.safeWsSend === 'function') window.safeWsSend({ message: 'WORKBENCH_SENT_IMAGE', mid: mid, sha256: sha256 });
    });
    return button;
  }

  // The images of the work screen the reply's image edits sent (their
  // records): a line on the message's card, each image shown when
  // clicked.
  function drawEdits(mid, list) {
    if (!mid) return;
    const card = $id(mid);
    const text = card ? card.querySelector('.card-text') : null;
    if (!text) return;
    const entries = (Array.isArray(list) ? list : []).filter((e) => e && typeof e.sha256 === 'string' &&
      (e.role === 'original' || e.role === 'reference'));
    let el = text.querySelector(':scope > .workbench-edit-note');
    if (entries.length === 0) {
      if (el) el.remove();
      return;
    }
    if (!el) {
      el = element('div', 'workbench-edit-note small text-secondary mt-2');
      text.appendChild(el);
    }
    el.replaceChildren();
    const line = element('div', 'workbench-note-line');
    line.appendChild(element('i', 'fa-solid fa-wand-magic-sparkles me-1'));
    line.appendChild(document.createTextNode(`${t('ui.workbench.editSent', 'Sent for an image edit')}: `));
    entries.forEach((entry, i) => {
      if (i > 0) line.appendChild(document.createTextNode(', '));
      const label = entry.role === 'reference'
        ? t('ui.workbench.editReference', 'the drawing on it')
        : t('ui.workbench.editOriginal', 'the image');
      line.appendChild(sentImageButton(mid, entry.sha256, label));
    });
    el.appendChild(line);
  }

  function draw() {
    drawLock();
    drawView();
    drawNotes();
    [drawnBody].concat(Array.from(others.values())).forEach(drawEarlierMarks);
    drawMarksLine();
    placeJump();
  }

  // ---- to the top and the end ----------------------------------------

  // The two buttons, while the place of the item chosen (Now when none is)
  // is longer than its view: each kept from where it would not move.
  const AT_END = 4;
  function jumpPlace() {
    const item = selected ? itemById(selected) : null;
    const region = (item && window.WorkbenchPlaces.regionOf(placeOf(item))) || 'desk';
    return places ? { place: region, scroller: places.regions[region].body } : null;
  }

  function placeJump() {
    const group = document.querySelector('#work-screen-pane .workbench-jump');
    const at = jumpPlace();
    if (!group) return;
    const scroller = at && at.scroller;
    const room = scroller ? scroller.scrollHeight - scroller.clientHeight : 0;
    group.hidden = !(room > AT_END);
    if (group.hidden) return;
    const top = $id('workbench-top');
    const bottom = $id('workbench-bottom');
    const name = places.regions[at.place].name;
    if (top) {
      top.disabled = scroller.scrollTop <= AT_END;
      top.setAttribute('aria-label', `${t('ui.workbench.toTop', 'To the top of the work screen')}: ${name}`);
    }
    if (bottom) {
      bottom.disabled = room - scroller.scrollTop <= AT_END;
      bottom.setAttribute('aria-label', `${t('ui.workbench.toBottom', 'To the end of the work screen')}: ${name}`);
    }
  }

  function jump(toEnd) {
    const at = jumpPlace();
    if (!at) return;
    at.scroller.scrollTo({ top: toEnd ? at.scroller.scrollHeight : 0, behavior: 'smooth' });
  }

  function wireJump() {
    $on($id('workbench-top'), 'click', () => jump(false));
    $on($id('workbench-bottom'), 'click', () => jump(true));
    window.addEventListener('resize', placeJump);
    // What is drawn grows after it is placed (an image, a PDF's pages).
    const pane = $id('work-screen-pane');
    if (pane && typeof ResizeObserver === 'function') {
      new ResizeObserver(() => {
        keepPinned();
        placeJump();
      }).observe(pane);
    }
    ['wheel', 'touchstart', 'keydown'].forEach((type) => $on(pane, type, unpin, { passive: true }));
    placeJump();
  }

  // ---- selection -----------------------------------------------------

  function refreshRelay() {
    if (window.WorkScreen && typeof window.WorkScreen.refresh === 'function') window.WorkScreen.refresh();
  }

  // into: brings the item's part to the top of the view (not when the
  // user chose it where it is).
  function select(id, into) {
    if (id) clearLocal();
    selected = id && itemById(id) ? id : null;
    tellSelected();
    draw();
    refreshRelay();
    if (selected && into !== false) bringIntoView(selected);
  }

  // The item's part at the top of its place's view.
  function bringIntoView(id) {
    const node = sectionOf(id) || (places && Array.from(places.regions.stash.body.children).find((n) => n.dataset.item === id));
    const scroller = node && node.parentElement;
    if (!node || !scroller || typeof scroller.scrollBy !== 'function') return;
    const by = node.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 4;
    if (Math.abs(by) > 1) scroller.scrollBy({ top: by, behavior: pinned ? 'auto' : 'smooth' });
    // Items above it may still grow (an image, a PDF drawn): it is kept
    // there a moment, until the user moves the view.
    if (!pinned) pinned = { id: id, until: Date.now() + PIN_MS };
  }

  const PIN_MS = 3000;
  let pinned = null;
  function keepPinned() {
    if (!pinned) return;
    if (Date.now() > pinned.until || pinned.id !== selected) {
      pinned = null;
      return;
    }
    bringIntoView(pinned.id);
  }
  function unpin() { pinned = null; }

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
    // The user is writing, or turned this off: the pane stays (the
    // announcement says what came), and the server is told what this tab
    // still shows.
    if (writing() || !autoSwitch()) {
      tellSelected();
      return;
    }
    // What the page showed of an attachment gives way to the new item.
    clearLocal();
    selected = item.id;
    showWorkPane();
    setTimeout(() => bringIntoView(item.id), 0);
  }

  // Whether the work screen is the pane shown (with no side column to
  // read, it is).
  function workPaneShown() {
    const lc = window.LayoutController;
    return !lc || (!lc.isMenuHidden() && lc.selectedPane() === 'work');
  }

  // What came to the work screen while another pane was shown: the tab
  // keeps a mark until the work screen is shown.
  function markUnseen(on) {
    const mark = $id('side-tab-work-new');
    if (mark) mark.hidden = !on;
  }

  if (typeof document !== 'undefined') {
    document.addEventListener('layoutchange', () => {
      if (!workPaneShown()) return;
      markUnseen(false);
      firsts.clear();
    });
  }

  // The side column, when shown, turns to the work screen.
  function showWorkPane() {
    const lc = window.LayoutController;
    if (lc && !lc.isMenuHidden() && lc.selectedPane() !== 'work') lc.setPane('work');
  }

  function reset() {
    // The work screen of the chat before is gone: the side column shows
    // the menu rather than an empty work screen (a new item brings it back).
    const lc = window.LayoutController;
    if (lc && typeof lc.setPane === 'function' && lc.selectedPane() === 'work') lc.setPane('settings');
    markUnseen(false);
    clearLocal();
    versionsOf = null;
    board = null;
    approvals = {};
    assets = {};
    renders = {};
    backgrounds = {};
    modes.clear();
    scrolls.clear();
    selected = null;
    serverSelected = null;
    serverSerial = null;
    opening = null;
    pendingOpen = null;
    pendingSection = null;
    letGo(drawnBody);
    drawnBody = null;
    letGoOthers();
    seen.clear();
    firsts.clear();
    removed.clear();
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
    document.querySelectorAll('.workbench-picture-note').forEach((el) => el.remove());
    document.querySelectorAll('.workbench-edit-note').forEach((el) => el.remove());
    readingRecords.clear();
    document.querySelectorAll('.workbench-reading-note').forEach((el) => el.remove());
    (Array.isArray(messages) ? messages : []).forEach((m) => {
      if (m && m.mid && Array.isArray(m.artifacts)) records.set(m.mid, m.artifacts);
      if (m && m.mid && m.workbench_picture) drawPicture(m.mid, m.workbench_picture);
      if (m && m.mid && m.workbench_selection) drawSelection(m.mid, m.workbench_selection);
      if (m && m.mid && Array.isArray(m.workbench_shown)) drawShown(m.mid, m.workbench_shown);
      if (m && m.mid && Array.isArray(m.workbench_looks)) drawLooks(m.mid, m.workbench_looks);
      if (m && m.mid && Array.isArray(m.workbench_edit_inputs)) drawEdits(m.mid, m.workbench_edit_inputs);
      if (m && m.mid && Array.isArray(m.library_readings)) drawReadings(m.mid, m.library_readings);
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
  // null and why: not_shown, drawing, failed, unknown), how many
  // characters are selected in it, and the items in view (in_view, while
  // the pane is shown). The server takes the range only for the item this
  // tab has selected, at that version, and the items in view only as the
  // board's, at their versions. null with nothing selected.
  function rangeNow() {
    // An attachment shown from the page's data is no item of the board: the
    // model is told of none.
    if (local) return null;
    const item = selected ? itemById(selected) : null;
    if (!item || placeOf(item) === 'stash') return null;
    const version = item.version || item.sha256 || '';
    const drawn = drawnBody && drawnBody.key === drawKey(item) ? drawnBody : null;
    const kind = previewed(item) ? item.preview : item.kind;
    const shownNow = paneShown();
    const report = (range, note) => Object.assign({
      item_id: item.id, version: version, range: range, note: note,
      selection_chars: drawn ? selectedChars(drawn.node) : 0
    }, shownNow ? { in_view: inViewNow() } : {});
    if (!shownNow) return report(null, 'not_shown');
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

  // The items in view now, in their order (all or part of each): an open
  // browser chosen is shown alone.
  function inViewNow() {
    const item = selected ? itemById(selected) : null;
    const of = (i) => ({ item_id: i.id, version: i.version || i.sha256 || '' });
    if (liveBrowser(item)) return [of(item)];
    const view = $id('workbench-view');
    if (!view || view.hidden || !places) return [];
    // What is in view now on the desk, place by place (never put away).
    return Array.from(places.regions.desk.body.children)
      .filter((node) => node.classList.contains('workbench-section') && visibleRect(node))
      .map((node) => itemById(node.dataset.item)).filter((item) => item && placeOf(item) !== 'stash').map(of);
  }

  // Whether the chat's model takes images (the page's model spec; a model it
  // does not know is taken to).
  // In a Live Conversation, the providers whose session takes the image of
  // a look (with the mark the user drew on it).
  const LIVE_IMAGE_PROVIDERS = ['openai', 'gemini'];

  // The provider of the Live Conversation going on in this page, or null.
  function liveProvider() {
    if (!document.body.classList.contains('lc-app')) return null;
    const el = $id('model');
    const spec = el && window.modelSpec ? window.modelSpec[el.value] : null;
    return spec && spec.sts_provider ? spec.sts_provider : 'unknown';
  }

  function takesImages() {
    const live = liveProvider();
    if (live) return LIVE_IMAGE_PROVIDERS.includes(live);
    const el = $id('model');
    const name = el ? el.value : null;
    const spec = name && window.modelSpec ? window.modelSpec[name] : null;
    return !spec || spec.vision_capability !== false;
  }

  // The part of the PDF in view, with the pointer drawn on it, to go with the
  // message being sent: { data, sent } (data is what is sent, sent() is
  // called once it went), or null. Only after the user placed or moved the
  // pointer on the page shown, while some of it is in view, for a model that
  // takes images. Taken at once, when the user sends.
  // The user's marks (one, or a list) drawn on a part cut from the PDF's
  // canvas (cutPage's decorate), in their colors and shapes, numbered when
  // there are several: { decorate, mark(), marks() }, marks() being each as
  // fractions of the part cut (rounded), or null for one not in that part;
  // mark() the first.
  function drawingMark(handle, pointers) {
    const list = Array.isArray(pointers) ? pointers : [pointers];
    let painted = list.map(() => null);
    const canvas = handle.canvas();
    const decorate = (context, frame) => {
      const clip = (v) => Math.min(1, Math.max(0, v));
      painted = list.map((pointer, i) => {
        // The pointer in the canvas's pixels, then in the cut part's.
        const left = pointer.x * canvas.width;
        const top = pointer.y * canvas.height;
        const right = left + pointer.w * canvas.width;
        const bottom = top + pointer.h * canvas.height;
        const x0 = clip((left - frame.x) / frame.w);
        const y0 = clip((top - frame.y) / frame.h);
        const x1 = clip((right - frame.x) / frame.w);
        const y1 = clip((bottom - frame.y) / frame.h);
        if (!(x1 > x0 && y1 > y0)) return null;
        return paintMark(context, Object.assign({}, pointer, { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }), frame.width, frame.height,
          list.length > 1 ? i + 1 : 0);
      });
    };
    return { decorate: decorate, mark: () => painted[0], marks: () => painted };
  }

  // Paints the user's mark (x, y, w, h: fractions of what it is on) on a
  // context of width × height pixels, translucent in its color, and returns
  // it as it is said ({ shape, color, x, y, w, h }, rounded).
  function paintMark(context, pointer, width, height, number = 0) {
    const palette = (window.WorkbenchPointer && window.WorkbenchPointer.COLORS) || {};
    const color = palette[pointer.color] ? pointer.color : 'orange';
    const round = (v) => Math.round(v * 10000) / 10000;
    const mark = { shape: pointer.shape === 'ellipse' ? 'ellipse' : 'rect', color: color,
                   x: round(pointer.x), y: round(pointer.y), w: round(pointer.w), h: round(pointer.h) };
    const px = pointer.x * width;
    const py = pointer.y * height;
    const pw = pointer.w * width;
    const ph = pointer.h * height;
    context.save();
    const colors = palette[color] || { fill: 'rgba(240, 160, 80, 0.28)', line: '#d98a3d' };
    context.fillStyle = colors.fill;
    context.strokeStyle = colors.line;
    context.lineWidth = Math.max(2, Math.round(width / 400));
    context.beginPath();
    if (mark.shape === 'ellipse') context.ellipse(px + pw / 2, py + ph / 2, pw / 2, ph / 2, 0, 0, Math.PI * 2);
    else context.rect(px, py, pw, ph);
    context.fill();
    context.stroke();
    // Its number, inside its top left corner (as the pane shows it).
    if (number > 0) {
      const radius = Math.max(9, Math.round(width / 70));
      const cx = Math.min(width - radius, Math.max(radius, px + radius + 3));
      const cy = Math.min(height - radius, Math.max(radius, py + radius + 3));
      context.beginPath();
      context.arc(cx, cy, radius, 0, Math.PI * 2);
      context.fillStyle = colors.line;
      context.fill();
      context.fillStyle = colors.ink || '#fff';
      context.font = `600 ${Math.round(radius * 1.3)}px sans-serif`;
      context.textAlign = 'center';
      context.textBaseline = 'middle';
      context.fillText(String(number), cx, cy + 1);
    }
    context.restore();
    return mark;
  }

  // ---- marks kept on the items --------------------------------------

  // The marks earlier messages sent on an item (the board keeps them, per
  // original and version), drawn lighter and fixed on its image or the PDF's
  // page shown; erased ones (erasures: item id → { version, targets }) go
  // at once here and are recorded with the next message.
  const erasures = new Map();

  function earlierMarksOf(item) {
    if (!item || !Array.isArray(item.marks) || erasedNow(item)) return [];
    return item.marks.filter((m) => m && m.rect);
  }

  // What earlier messages drew on the item, as the view has it (none once
  // erased here, before it is sent).
  function earlierDrawingOf(item) {
    if (!item || !item.drawing || !Array.isArray(item.drawing.shapes) || erasedNow(item)) return [];
    return item.drawing.shapes;
  }

  function erasedNow(item) {
    const erased = erasures.get(item.id);
    return !!erased && erased.version === (item.version || item.sha256 || '');
  }

  // What was drawn that the view now shows as sent (its shapes among the
  // earlier ones) leaves this turn's drawing; the drawing over the image is
  // drawn again when what was sent before changes.
  function keepDrawingAsSent(drawn, item) {
    const earlier = earlierDrawingOf(item);
    const kept = new Set(earlier.map((shape) => shape && shape.id));
    const draft = draftOf(drawn);
    const left = draft.filter((shape) => !kept.has(shape.id));
    const shown = JSON.stringify(item && item.drawing ? item.drawing.digests || [] : []) + (erasedNow(item || {}) ? '|erased' : '');
    if (left.length === draft.length && drawn.drawingShown === shown) return;
    drawn.drawingShown = shown;
    drawn.drawing = left.length > 0 ? { shapes: left, rev: (drawn.drawing && drawn.drawing.rev) || 0 } : null;
    if (typeof drawn.image.refreshDrawing === 'function') drawn.image.refreshDrawing();
  }

  function drawEarlierMarks(drawn) {
    if (!drawn || !drawn.node || typeof drawn.node.querySelector !== 'function') return;
    const item = itemById(drawn.itemId);
    let surface = null;
    let page = 1;
    if (drawn.image) {
      surface = drawn.node.querySelector('.workbench-image-frame');
    } else if (drawn.pdf) {
      surface = drawn.node.querySelector('.workbench-pdf-page');
      const shown = typeof drawn.pdf.shown === 'function' ? drawn.pdf.shown() : null;
      page = shown && shown.page ? shown.page : 1;
    }
    if (!surface) return;
    // Marks that went with a message are drawn here now, fixed.
    const handle = drawn.image || drawn.pdf;
    const sent = item && Array.isArray(item.marks) ? item.marks.map((m) => m && m.id).filter(Boolean) : [];
    if (sent.length > 0 && handle && typeof handle.dropMarks === 'function') handle.dropMarks(sent);
    if (drawn.image) keepDrawingAsSent(drawn, item);
    let layer = surface.querySelector(':scope > .workbench-marks-earlier');
    // Nothing to draw and nothing drawn: nothing is made.
    if (!layer && earlierMarksOf(item).length === 0) return;
    if (!layer) {
      layer = element('div', 'workbench-marks-earlier');
      layer.setAttribute('aria-hidden', 'true');
      surface.appendChild(layer);
    }
    const marks = earlierMarksOf(item).filter((m) => (m.page || 1) === page);
    layer.replaceChildren(...marks.map((m) => {
      const box = element('div', `workbench-mark-earlier ${m.shape === 'ellipse' ? 'is-ellipse' : 'is-rect'}`);
      box.style.left = `${m.rect.x * 100}%`;
      box.style.top = `${m.rect.y * 100}%`;
      box.style.width = `${m.rect.w * 100}%`;
      box.style.height = `${m.rect.h * 100}%`;
      return box;
    }));
  }

  // Erases every mark of the item (earlier ones, and this turn's unsent one).
  function eraseMarks(item) {
    if (locked()) {
      warn(lockText());
      return;
    }
    const version = item.version || item.sha256 || '';
    const targets = (Array.isArray(item.marks) ? item.marks : []).map((m) => [m.id, m.rev]);
    // What was drawn on it, by the drawings shown here.
    const drawings = item.drawing && Array.isArray(item.drawing.digests) ? item.drawing.digests.slice() : [];
    if (targets.length > 0 || drawings.length > 0) erasures.set(item.id, { version: version, targets: targets, drawings: drawings });
    const drawn = drawnBody && drawnBody.itemId === item.id ? drawnBody : others.get(item.id);
    const handle = drawn && (drawn.image || drawn.pdf);
    if (handle && typeof handle.clear === 'function') handle.clear();
    if (handle && typeof handle.clearPointer === 'function') handle.clearPointer();
    if (drawn) drawn.pictures = new Map();
    draw();
  }

  // The erasures that go with the message the user sends now, or null.
  function erasuresNow() {
    const data = [];
    erasures.forEach((erase, itemId) => {
      const item = itemById(itemId);
      if (item && (item.version || item.sha256 || '') === erase.version && ['current', 'latest'].includes(placeOf(item))) {
        data.push({ item_id: itemId, version: erase.version, targets: erase.targets, drawings: erase.drawings || [] });
      }
    });
    if (data.length === 0) return null;
    return { data: data, sent: () => erasures.clear() };
  }

  // A message the user deleted had erased marks that could not come back
  // (more than an item shows): they stay erased.
  function onMarksKeptErased(data) {
    announce(t('ui.workbench.marksKeptErased',
      'The message was deleted. {n} marks it had erased stay erased: bringing them back would show more than an item takes.')
      .replace('{n}', String(data && data.count ? data.count : '')));
  }

  // ---- marks sent with a message -------------------------------------

  // Each drawn item's marks, with a picture of each page marked (an image:
  // its one) taken when a mark on it was made or changed (the item, its
  // version, the page, and each mark: its own id, how many times it
  // changed, its place on the picture and on the whole image or page): the
  // pictures of the marked items on the desk (Now and Latest) go with the
  // next message, in their order there, at most MARKS_PER_MESSAGE
  // (Picture::PER_MESSAGE); a picture sent once is not sent again until a
  // mark on it changes.
  const MARKS_PER_MESSAGE = 4;
  const sentMarks = new Set();

  function marksOf(handle) {
    return handle && typeof handle.marks === 'function' ? handle.marks() : [];
  }

  function markChanged(drawn) {
    if (!drawn) return;
    const item = itemById(drawn.itemId);
    const handle = drawn.image || drawn.pdf;
    const marks = item ? marksOf(handle) : [];
    // What this turn drew on an image (it goes as that image's picture).
    const shapes = item && drawn.image ? draftOf(drawn) : [];
    const pages = drawn.pictures || new Map();
    const marked = new Set(marks.map((m) => m.page || 1));
    if (shapes.length > 0) marked.add(1);
    Array.from(pages.keys()).forEach((page) => { if (!marked.has(page)) pages.delete(page); });
    // The page shown is the one a mark changed on.
    const page = drawn.image ? 1 : (handle && typeof handle.shown === 'function' ? handle.shown().page : null);
    const onPage = marks.filter((m) => (m.page || 1) === page);
    if (onPage.length > 0 || (drawn.image && shapes.length > 0)) {
      let data = null;
      try {
        data = drawn.image ? imageMarkPicture(item, drawn.image, onPage, shapes) : pdfMarkPicture(item, drawn.pdf, onPage);
      } catch (_) {
        data = null;
      }
      pages.set(page, { marks: onPage.map((m) => ({ id: m.id, rev: m.rev })), data: data,
                        drawing: drawn.image && shapes.length > 0 ? `${drawn.itemId}:drawing:${drawn.drawing.rev}` : null });
    }
    drawn.pictures = pages;
    drawMarksLine();
  }

  // Each mark as the picture says it ({ id, rev, mark: its place on the
  // picture, rect: on the whole image or page }), in the order made.
  function picturedMarks(list, painted) {
    return list.map((m, i) => (painted[i] ? { id: m.id, rev: m.rev, mark: painted[i], rect: rectOf(m) } : null))
      .filter(Boolean);
  }

  // The shapes this turn drew on an image (not those earlier turns sent).
  function draftOf(drawn) {
    return drawn && drawn.drawing && Array.isArray(drawn.drawing.shapes) ? drawn.drawing.shapes : [];
  }

  function imageMarkPicture(item, handle, list, shapes = []) {
    const part = markedImage(handle, list, { earlier: earlierDrawingOf(item), shapes: shapes });
    const painted = part.marks || [];
    if (!part.image || (shapes.length === 0 && painted.every((m) => !m))) return null;
    const data = { item_id: item.id, version: item.version || item.sha256 || '', image: part.image,
                   marks: picturedMarks(list, painted) };
    if (shapes.length > 0) data.drawing = { shapes: shapes };
    return data;
  }

  // Where a mark is on the whole image or page (fractions), as the board keeps it.
  function rectOf(pointer) {
    return { x: pointer.x, y: pointer.y, w: pointer.w, h: pointer.h };
  }

  // The part of the PDF's page in view, widened to every mark on it, with
  // the marks, as a mark is made there (the page they are on is the page
  // shown).
  function pdfMarkPicture(item, handle, list) {
    const shown = handle.shown();
    if (shown.status !== 'ready' || list.some((m) => m.page !== shown.page)) return null;
    const marked = drawingMark(handle, list);
    const part = cutPage(handle, shown.drawing, marked.decorate, list);
    const painted = marked.marks();
    if (!part || !part.image || painted.every((m) => !m)) return null;
    return { item_id: item.id, version: item.version || item.sha256 || '', page: shown.page, pages: shown.pages,
             image: part.image, marks: picturedMarks(list, painted) };
  }

  const pictureKey = (itemId, page) => (mark) => `${itemId}:${page}:${mark.id}:${mark.rev}`;

  // The pictures of the marked items on the desk that have not gone with a
  // message, in their order there (a PDF's by page), each { itemId, page,
  // marks, data }.
  function waitingMarks() {
    if (!takesImages()) return [];
    const order = rowItems().filter((item) => ['current', 'latest'].includes(placeOf(item))).map((item) => item.id);
    const waiting = [];
    [drawnBody].concat(Array.from(others.values())).forEach((drawn) => {
      if (!drawn || !drawn.pictures || !order.includes(drawn.itemId)) return;
      const item = itemById(drawn.itemId);
      const version = item ? (item.version || item.sha256 || '') : null;
      drawn.pictures.forEach((picture, page) => {
        if (!picture.data || picture.data.version !== version) return;
        const drawingSent = !picture.drawing || sentMarks.has(picture.drawing);
        if (drawingSent && picture.marks.every((m) => sentMarks.has(pictureKey(drawn.itemId, page)(m)))) return;
        waiting.push({ itemId: drawn.itemId, page: page, marks: picture.marks, drawing: picture.drawing, data: picture.data });
      });
    });
    return waiting.sort((a, b) => (order.indexOf(a.itemId) - order.indexOf(b.itemId)) || (a.page - b.page));
  }

  // The pictures of the marked items that go with the message the user
  // sends now, or null.
  function picturesNow() {
    if (local) return null;
    const waiting = waitingMarks();
    if (waiting.length === 0) return null;
    const going = waiting.slice(0, MARKS_PER_MESSAGE);
    return {
      data: going.map((picture) => picture.data),
      left: waiting.length - going.length,
      sent: () => {
        going.forEach((picture) => {
          picture.marks.forEach((m) => sentMarks.add(pictureKey(picture.itemId, picture.page)(m)));
          if (picture.drawing) sentMarks.add(picture.drawing);
        });
        drawMarksLine();
      }
    };
  }

  // Before sending: when more items are marked than a message takes, which
  // go (the first in the desk's order).
  function drawMarksLine() {
    const head = document.querySelector('#work-screen-pane .workbench-head');
    let line = $id('workbench-marks');
    const waiting = waitingMarks();
    const over = waiting.length > MARKS_PER_MESSAGE;
    if (!line && head && over) {
      line = element('div', 'workbench-marks text-secondary mb-2');
      line.id = 'workbench-marks';
      line.setAttribute('role', 'status');
      head.appendChild(line);
    }
    if (!line) return;
    line.hidden = !over;
    if (over) {
      line.textContent = t('ui.workbench.marksOver',
        '{n} marked pictures wait. The next message takes the first {max} in the order of the work screen (a PDF: by page); the others are not sent.')
        .replace('{n}', String(waiting.length)).replace('{max}', String(MARKS_PER_MESSAGE));
    }
  }

  // The picture of the item chosen without a mark, for a model that cannot
  // look at the work screen itself (marked items go by picturesNow).
  function pictureNow() {
    if (waitingMarks().length > 0) return null;
    const picture = singlePictureNow();
    return picture && picture.data && picture.data.unmarked ? picture : null;
  }

  function singlePictureNow() {
    if (local || !paneShown() || !takesImages()) return null;
    const item = selected ? itemById(selected) : null;
    if (!item || item.kind !== 'file' || placeOf(item) === 'stash') return null;
    const drawn = drawnBody && drawnBody.key === drawKey(item) ? drawnBody : null;
    if (item.preview === 'image') return drawn && drawn.image ? imagePictureNow(item, drawn.image) : null;
    if (item.preview !== 'pdf') return null;
    const handle = drawn && drawn.pdf;
    if (!handle || typeof handle.pointer !== 'function') return null;
    const shown = handle.shown();
    const pointer = handle.pointer();
    if (shown.status !== 'ready') return null;
    if (!pointer || pointer.page !== shown.page) return unmarkedPageNow(item, handle, shown);
    const seq = handle.pointerSeq();
    if (sentPointer.handle === handle && sentPointer.seq === seq) return null;
    const marked = drawingMark(handle, pointer);
    let part;
    try {
      part = cutPage(handle, shown.drawing, marked.decorate);
    } catch (_) {
      return null;
    }
    const mark = marked.mark();
    if (!part || !part.image || !mark) return null;
    return {
      data: {
        item_id: item.id, version: item.version || item.sha256 || '', page: shown.page, pages: shown.pages,
        mark: mark, crop: part.crop, image: part.image
      },
      sent: () => { sentPointer = { handle: handle, seq: seq }; }
    };
  }

  // A model that cannot call tools cannot look at the work screen itself:
  // the item the user chose goes with each message they send, unmarked
  // when nothing is marked on it (the server takes that only for such a
  // model), while some of it is in view.
  function looksByMessage() {
    if (liveProvider()) return false;
    const el = $id('model');
    const spec = el && window.modelSpec ? window.modelSpec[el.value] : null;
    return !!spec && spec.tool_capability === false && spec.vision_capability === true;
  }

  function unmarkedFor(item) {
    return looksByMessage() && inViewNow().some((entry) => entry.item_id === item.id);
  }

  function unmarkedPageNow(item, handle, shown) {
    if (!unmarkedFor(item)) return null;
    let part;
    try {
      part = cutPage(handle, shown.drawing, null);
    } catch (_) {
      return null;
    }
    if (!part || !part.image) return null;
    return {
      data: { item_id: item.id, version: item.version || item.sha256 || '', page: shown.page, pages: shown.pages,
        unmarked: true, crop: part.crop, image: part.image },
      sent: () => {}
    };
  }

  // The same for an image the tab shows: the whole image with the mark
  // drawn on it, after the user placed or moved the mark (unmarked for a
  // model that cannot look at the work screen itself).
  function imagePictureNow(item, handle) {
    const pointer = handle.pointer();
    if (!pointer) {
      if (!unmarkedFor(item) || !handle.img.complete || !(handle.img.naturalWidth > 0)) return null;
      let part;
      try {
        part = drawnPng(handle.img, 0, 0, handle.img.naturalWidth, handle.img.naturalHeight, null);
      } catch (_) {
        return null;
      }
      if (!part.image) return null;
      return {
        data: { item_id: item.id, version: item.version || item.sha256 || '', unmarked: true, crop: part.crop, image: part.image },
        sent: () => {}
      };
    }
    const seq = handle.pointerSeq();
    if (sentPointer.handle === handle && sentPointer.seq === seq) return null;
    const part = markedImage(handle, pointer);
    if (!part.image || !part.mark) return null;
    return {
      data: { item_id: item.id, version: item.version || item.sha256 || '', mark: part.mark, crop: part.crop, image: part.image },
      sent: () => { sentPointer = { handle: handle, seq: seq }; }
    };
  }

  // The PDF the tab shows now, drawn, or null.
  function shownPdf() {
    const item = selected ? itemById(selected) : null;
    const drawn = item && drawnBody && drawnBody.key === drawKey(item) ? drawnBody : null;
    return drawn && drawn.pdf ? { item: item, drawn: drawn } : null;
  }

  // The text file the tab shows now as its numbered lines, or null.
  function shownLines() {
    const item = selected ? itemById(selected) : null;
    const drawn = item && drawnBody && drawnBody.key === drawKey(item) ? drawnBody : null;
    return drawn && drawn.lines && drawn.lines.isConnected ? { item: item, drawn: drawn } : null;
  }

  // The lines of the text drawn (item at version) the user selected: as the
  // page's selection has them now, or else as held (unless set aside):
  // { first, last }, or null.
  function linesChosen(drawn, item, version) {
    const selection = typeof window.getSelection === 'function' ? window.getSelection() : null;
    const range = drawn.lines && selection && !selection.isCollapsed ? selectedLines(drawn.lines, selection) : null;
    if (range) return { first: range[0], last: range[1] };
    const held = heldSelection;
    if (held && held.kind === 'text' && held.item_id === item.id && held.version === version && held.key !== selectionSetAside) {
      return { first: held.first, last: held.last };
    }
    return null;
  }

  // The held lines of the text shown, marked as such: they stay marked when
  // the page's selection goes (the user clicks elsewhere), and after they
  // are sent, until other lines are selected or they are set aside.
  function showHeldLines() {
    const shown = shownLines();
    if (!shown) return;
    const held = heldLinesOf(shown);
    Array.from(shown.drawn.lines.children).forEach((li, i) => {
      li.classList.toggle('workbench-line-held', !!held && i + 1 >= held.first && i + 1 <= held.last);
    });
  }

  // The held lines of the text shown (shownLines()), unless set aside, or
  // null.
  function heldLinesOf(shown) {
    const held = heldSelection;
    const version = shown.item.version || shown.item.sha256 || '';
    return held && held.kind === 'text' && held.item_id === shown.item.id && held.version === version &&
      held.key !== selectionSetAside ? held : null;
  }

  // ---- where the AI points ----------------------------------------------

  // The server says the AI pointed at a part of an item this tab shows: it
  // is marked, and brought into view, while the tab shows that item.
  function onPoint(data) {
    const item = data && typeof data.item_id === 'string' ? itemById(data.item_id) : null;
    const point = data && data.point;
    if (!item || item.kind !== 'file' || !point || typeof point !== 'object') return;
    pointAt(item.path, data.version, point);
  }

  function pointAt(path, version, point) {
    const lines = Array.isArray(point.lines) && point.lines.length === 2 && point.lines.every(Number.isInteger) ? point.lines : null;
    const page = Number.isInteger(point.page) && typeof point.quote === 'string' ? point.page : null;
    if (!lines && !page) return;
    aiPoint = { path: path, version: version, lines: lines, page: page, quote: page ? point.quote : null,
                label: typeof point.label === 'string' ? point.label : '' };
    aiPointToShow = true;
    showAiPoint();
  }

  // The AI's mark taken away (the user sent the next message, or clicked
  // its ×).
  function clearAiPoint() {
    aiPoint = null;
    aiPointToShow = false;
    showAiPoint();
  }

  // Draws the AI's mark where the tab shows its item (and nothing where it
  // does not): the lines of a text, the quote on a PDF's page (turning to
  // that page first), with a chip that says where and takes it away.
  function showAiPoint() {
    const item = selected ? itemById(selected) : null;
    const drawn = item && drawnBody && drawnBody.key === drawKey(item) ? drawnBody : null;
    const node = drawn ? drawn.node : null;
    if (node) {
      node.querySelectorAll('.workbench-line-ai').forEach((el) => el.classList.remove('workbench-line-ai'));
      node.querySelectorAll('.workbench-ai-hit').forEach((el) => el.classList.remove('workbench-ai-hit'));
      node.querySelectorAll('.workbench-ai-chip').forEach((el) => el.remove());
    }
    const version = item ? (item.version || item.sha256 || '') : '';
    if (!aiPoint || !drawn || item.path !== aiPoint.path || version !== aiPoint.version) return;
    let first = null;
    let bar = null;
    if (aiPoint.lines && drawn.lines && drawn.lines.isConnected) {
      const [from, to] = aiPoint.lines;
      Array.from(drawn.lines.children).forEach((li, i) => {
        if (i + 1 < from || i + 1 > to) return;
        li.classList.add('workbench-line-ai');
        if (!first) first = li;
      });
      bar = node.querySelector('.workbench-text-bar');
    } else if (aiPoint.page && drawn.pdf) {
      const shown = drawn.pdf.shown();
      if (shown.status !== 'ready' || shown.page !== aiPoint.page) {
        if (aiPointToShow && typeof drawn.pdf.goTo === 'function') drawn.pdf.goTo(aiPoint.page);
        return;
      }
      first = markQuote(drawn.pdf.textLayer(), aiPoint.quote);
      bar = node.querySelector('.workbench-pdf-bar');
    } else {
      return;
    }
    if (bar) bar.appendChild(aiChip());
    if (aiPointToShow) {
      aiPointToShow = false;
      if (first && typeof first.scrollIntoView === 'function') first.scrollIntoView({ block: 'center' });
    }
  }

  // The pieces of a PDF page's text layer the quote is in (spaces are not
  // compared: the layer's pieces may or may not have them), marked; the
  // first of them, or null.
  function markQuote(layer, quote) {
    if (!layer || !quote) return null;
    const pieces = Array.from(layer.querySelectorAll('span')).filter((span) => !span.querySelector('span'));
    const chars = [];
    pieces.forEach((span, n) => {
      Array.from(span.textContent || '').forEach((ch) => { if (!/\s/.test(ch)) chars.push([ch, n]); });
    });
    const wanted = Array.from(quote).filter((ch) => !/\s/.test(ch)).join('');
    const at = wanted ? chars.map((c) => c[0]).join('').indexOf(wanted) : -1;
    if (at < 0) return null;
    const from = chars[at][1];
    const to = chars[at + Array.from(wanted).length - 1][1];
    for (let n = from; n <= to; n++) pieces[n].classList.add('workbench-ai-hit');
    return pieces[from];
  }

  // The chip of the AI's mark: where it is, its label, and × to take it away.
  function aiChip() {
    const chip = element('span', 'workbench-selection-chip workbench-ai-chip');
    chip.appendChild(element('i', 'fa-solid fa-location-crosshairs'));
    const where = aiPoint.lines
      ? t('ui.workbench.aiPointLines', 'AI: lines {first}–{last}').replace('{first}', String(aiPoint.lines[0]))
        .replace('{last}', String(aiPoint.lines[1]))
      : t('ui.workbench.aiPointPage', 'AI: page {n}').replace('{n}', String(aiPoint.page));
    chip.appendChild(element('span', 'workbench-selection-text', aiPoint.label ? `${where} · ${aiPoint.label}` : where));
    const clear = element('button', 'btn btn-sm btn-icon workbench-selection-aside');
    clear.type = 'button';
    clear.innerHTML = '<i class="fa-solid fa-xmark" aria-hidden="true"></i>';
    const label = t('ui.workbench.aiPointClear', "Clear the AI's mark");
    clear.setAttribute('aria-label', label);
    clear.title = label;
    clear.addEventListener('click', clearAiPoint);
    chip.appendChild(clear);
    return chip;
  }

  // The numbers of the lines of list (a text's numbered lines) a selection
  // runs from and to: [first, last], or null when it is not within them.
  function selectedLines(list, selection) {
    const lineOf = (node) => {
      const el = node && (node.nodeType === 1 ? node : node.parentElement);
      const li = el && el.closest ? el.closest('li') : null;
      return li && li.parentElement === list ? Array.prototype.indexOf.call(list.children, li) + 1 : 0;
    };
    const a = lineOf(selection.anchorNode);
    const b = lineOf(selection.focusNode);
    return a && b ? [Math.min(a, b), Math.max(a, b)] : null;
  }

  // The held selection, when it is of the PDF shown and neither sent nor
  // set aside: the one offered to send.
  function offeredSelection() {
    const shown = shownPdf() || shownLines();
    if (!heldSelection || !shown || placeOf(shown.item) === 'stash') return null;
    if (heldSelection.key === selectionSetAside || heldSelection.key === selectionSent) return null;
    const version = shown.item.version || shown.item.sha256 || '';
    return heldSelection.item_id === shown.item.id && heldSelection.version === version ? heldSelection : null;
  }

  // The chip in the PDF's bar (or above a text's lines) that says the
  // selected text (or lines) goes with the next message, with × to set it
  // aside.
  function showSelectionChip() {
    showHeldLines();
    const pdf = shownPdf();
    const lines = pdf ? null : shownLines();
    const bar = pdf ? pdf.drawn.node.querySelector('.workbench-pdf-bar')
      : lines ? lines.drawn.node.querySelector('.workbench-text-bar') : null;
    if (!bar) return;
    let chip = bar.querySelector('.workbench-selection-chip');
    // A Live Conversation sends no message with it: the AI gets the text
    // selected when it looks at the work screen.
    const offered = liveProvider() ? null : offeredSelection();
    // Lines still marked but not offered (sent, or in a Live Conversation)
    // keep the chip, to take the mark away.
    const marked = !offered && lines ? heldLinesOf(lines) : null;
    if (!offered && !marked) {
      if (chip) chip.remove();
      return;
    }
    if (!chip) {
      chip = element('span', 'workbench-selection-chip');
      chip.appendChild(element('i', 'fa-solid fa-i-cursor'));
      chip.appendChild(element('span', 'workbench-selection-text'));
      const aside = element('button', 'btn btn-sm btn-icon workbench-selection-aside');
      aside.type = 'button';
      aside.innerHTML = '<i class="fa-solid fa-xmark" aria-hidden="true"></i>';
      aside.addEventListener('click', () => {
        if (heldSelection) selectionSetAside = heldSelection.key;
        showSelectionChip();
      });
      chip.appendChild(aside);
      bar.appendChild(chip);
    }
    const range = (text, held) => text.replace('{first}', String(held.first)).replace('{last}', String(held.last));
    let text;
    let label;
    if (marked) {
      text = range(t('ui.workbench.selectionMarkedLines', 'Lines {first}–{last}'), marked);
      label = t('ui.workbench.selectionClearLines', 'Clear the selected lines');
    } else if (offered.kind === 'text') {
      text = range(t('ui.workbench.selectionSendLines', 'Send lines {first}–{last}'), offered);
      label = t('ui.workbench.selectionAside', 'Do not send the selected text');
    } else {
      text = t('ui.workbench.selectionSend', 'Send the selected text ({n} characters)').replace('{n}', String(Array.from(offered.text).length));
      label = t('ui.workbench.selectionAside', 'Do not send the selected text');
    }
    chip.querySelector('.workbench-selection-text').textContent = text;
    const aside = chip.querySelector('.workbench-selection-aside');
    aside.setAttribute('aria-label', label);
    aside.title = label;
  }

  // A selection made in the text of the PDF shown is held (and offered).
  document.addEventListener('selectionchange', () => {
    const selection = typeof window.getSelection === 'function' ? window.getSelection() : null;
    if (!selection || selection.isCollapsed) return;
    // Lines of a text file are held by their numbers.
    const shownText = shownLines();
    if (shownText) {
      const range = selectedLines(shownText.drawn.lines, selection);
      if (!range) return;
      const id = shownText.item.id;
      const version = shownText.item.version || shownText.item.sha256 || '';
      heldSelection = { key: `${id}|${version}|lines|${range[0]}|${range[1]}`, kind: 'text',
                        item_id: id, version: version, first: range[0], last: range[1] };
      showSelectionChip();
      return;
    }
    const pdf = shownPdf();
    const layer = pdf && typeof pdf.drawn.pdf.textLayer === 'function' ? pdf.drawn.pdf.textLayer() : null;
    if (!layer || !layer.contains(selection.anchorNode) || !layer.contains(selection.focusNode)) return;
    const shown = pdf.drawn.pdf.shown();
    if (shown.status !== 'ready') return;
    const chars = Array.from(selection.toString().trim());
    if (chars.length === 0) return;
    const version = pdf.item.version || pdf.item.sha256 || '';
    const text = chars.slice(0, SELECTION_SEND_LIMIT).join('');
    heldSelection = { key: `${pdf.item.id}|${version}|${shown.page}|${text}`, item_id: pdf.item.id, version: version,
                      page: shown.page, pages: shown.pages, text: text, cut: chars.length > SELECTION_SEND_LIMIT };
    showSelectionChip();
  });

  // The selected text offered, to go with the message being sent: { data,
  // sent } (data is what is sent, sent() is called once it went), or null.
  function selectionNow() {
    if (local || !paneShown() || liveProvider()) return null;
    const offered = offeredSelection();
    if (!offered) return null;
    const { key, kind: _kind, ...data } = offered;
    return {
      data: data,
      sent: () => {
        selectionSent = key;
        showSelectionChip();
      }
    };
  }

  // A Live Conversation began or ended: the chip follows what its session
  // takes.
  function liveChanged() {
    showSelectionChip();
  }
  if (typeof MutationObserver === 'function' && document.body) {
    new MutationObserver(liveChanged).observe(document.body, { attributes: true, attributeFilter: ['class'] });
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
  // decorate(context, frame), when given, draws over the cut part (frame:
  // the part of the canvas cut, x, y, w, h in its pixels, and the size it is
  // drawn at, width and height).
  function cutPage(handle, drawing, decorate, widenTo) {
    const canvas = handle.canvas();
    const frame = canvas ? visibleRect(canvas) : null;
    if (!frame) return { image_note: 'not_in_view' };
    const rect = canvas.getBoundingClientRect();
    if (!(rect.width > 0 && rect.height > 0)) return { image_note: 'not_in_view' };
    // Widened to the marks given (fractions of the page), within the page:
    // each mark on the page is in the part cut.
    (widenTo || []).forEach((m) => {
      frame.left = Math.max(rect.left, Math.min(frame.left, rect.left + m.x * rect.width));
      frame.top = Math.max(rect.top, Math.min(frame.top, rect.top + m.y * rect.height));
      frame.right = Math.min(rect.right, Math.max(frame.right, rect.left + (m.x + m.w) * rect.width));
      frame.bottom = Math.min(rect.bottom, Math.max(frame.bottom, rect.top + (m.y + m.h) * rect.height));
    });
    const sx = canvas.width / rect.width;
    const sy = canvas.height / rect.height;
    const x = (frame.left - rect.left) * sx;
    const y = (frame.top - rect.top) * sy;
    const w = (frame.right - frame.left) * sx;
    const h = (frame.bottom - frame.top) * sy;
    if (![x, y, w, h].every(Number.isFinite) || w <= 0 || h <= 0) return { image_note: 'not_in_view' };
    const part = drawnPng(canvas, x, y, w, h, decorate);
    if (handle.shown().drawing !== drawing) return { image_note: 'redrawn' };
    return part;
  }

  // The part x, y, w, h (in source's own pixels) of source (a canvas or an
  // image), drawn at most CUT_SIDE × CUT_PIXELS (into a canvas of that size),
  // as PNG base64 with the part it is, or why there is none. decorate(context,
  // frame), when given, draws over it (frame: the part, and the size it is
  // drawn at, width and height).
  function drawnPng(source, x, y, w, h, decorate) {
    const fit = Math.min(1, CUT_SIDE / Math.max(w, h), Math.sqrt(CUT_PIXELS / (w * h)));
    const width = Math.max(1, Math.floor(w * fit));
    const height = Math.max(1, Math.floor(h * fit));
    const cut = document.createElement('canvas');
    cut.width = width;
    cut.height = height;
    const context = cut.getContext('2d');
    if (!context) return { image_note: 'failed' };
    context.drawImage(source, x, y, w, h, 0, 0, width, height);
    if (decorate) decorate(context, { x: x, y: y, w: w, h: h, width: width, height: height });
    const url = cut.toDataURL('image/png');
    const comma = url.indexOf(',');
    if (!url.startsWith('data:image/png;base64,') || comma < 0) return { image_note: 'failed' };
    const image = url.slice(comma + 1);
    if (image.length > CUT_BASE64) return { image_note: 'too_large' };
    const round = (v) => Math.round(v * 100) / 100;
    return { image: image, crop: { x: round(x), y: round(y), width: round(w), height: round(h), sent_width: width, sent_height: height } };
  }

  // The text of a PDF page's text layer inside the user's mark: each piece
  // whose middle is in it, in the layer's order, as [text, cut] (at most
  // SELECTED_TEXT_LIMIT characters), or [null, false].
  function markedText(handle, pointer) {
    const canvas = handle.canvas();
    const layer = typeof handle.textLayer === 'function' ? handle.textLayer() : null;
    if (!canvas || !layer) return [null, false];
    const box = canvas.getBoundingClientRect();
    if (!(box.width > 0 && box.height > 0)) return [null, false];
    const cx = pointer.x + pointer.w / 2;
    const cy = pointer.y + pointer.h / 2;
    const inside = (x, y) => {
      if (pointer.shape === 'ellipse') {
        const dx = (x - cx) / (pointer.w / 2);
        const dy = (y - cy) / (pointer.h / 2);
        return dx * dx + dy * dy <= 1;
      }
      return x >= pointer.x && x <= pointer.x + pointer.w && y >= pointer.y && y <= pointer.y + pointer.h;
    };
    const pieces = [];
    layer.querySelectorAll('span, br').forEach((node) => {
      if (node.tagName === 'BR') {
        pieces.push(' ');
        return;
      }
      // A span holding others (marked content) is read through them.
      if (node.querySelector('span')) return;
      const r = node.getBoundingClientRect();
      if (!(r.width > 0 && r.height > 0)) return;
      if (inside((r.left + r.width / 2 - box.left) / box.width, (r.top + r.height / 2 - box.top) / box.height)) {
        pieces.push(node.textContent);
      }
    });
    const chars = Array.from(pieces.join('').replace(/\s+/g, ' ').trim());
    if (chars.length === 0) return [null, false];
    return [chars.slice(0, SELECTED_TEXT_LIMIT).join(''), chars.length > SELECTED_TEXT_LIMIT];
  }

  // A capture of an image: when an image is asked for and the user marked
  // a part of it or earlier messages drew on it, the whole image as the tab
  // has it, with what was sent drawn on it (as sent: not lighter, not this
  // turn's draft, whose texts the server has not checked) and the mark,
  // where the mark is, and which drawings were painted (drawing); 'drawn'
  // (an edit's reference) asks for the drawing alone. Else nothing more
  // (the server has the image itself).
  function imageAnswer(data, handle, item) {
    const out = { range: {}, note: null };
    const wants = Array.isArray(data.wants) ? data.wants : [];
    const earlier = earlierDrawingOf(item);
    const drawing = earlier.length > 0 ? { earlier: earlier, earlierAlpha: 1, shapes: [] } : null;
    if (wants.includes('drawn')) {
      if (!drawing) return out;
      const painted = markedImage(handle, [], drawing);
      Object.assign(out, painted);
      delete out.marks;
      if (painted.image) out.drawing = item.drawing.digests;
      return out;
    }
    const pointer = handle.pointer();
    if (!wants.includes('image') || (!pointer && !drawing)) return out;
    const part = markedImage(handle, pointer ? [pointer] : [], drawing);
    Object.assign(out, part);
    delete out.marks;
    if (!part.image) delete out.mark;
    if (drawing && part.image) out.drawing = item.drawing.digests;
    return out;
  }

  // The whole image the tab shows, with what was drawn on it (drawing:
  // { earlier, shapes }: earlier turns' shapes lighter, then this turn's)
  // and the user's marks (one, or a list) over them, in that order, each
  // once: what drawnPng gives, with the first mark ({ shape, color, x, y, w,
  // h }) as mark and, for a list, each as marks.
  function markedImage(handle, pointers, drawing) {
    const img = handle.img;
    if (!img.complete || !(img.naturalWidth > 0 && img.naturalHeight > 0)) return { image_note: 'drawing' };
    const list = (Array.isArray(pointers) ? pointers : [pointers]).filter(Boolean);
    let marks = [];
    let part;
    try {
      part = drawnPng(img, 0, 0, img.naturalWidth, img.naturalHeight, (context, frame) => {
        paintDrawing(context, frame, img, drawing);
        marks = list.map((pointer, i) => paintMark(context, pointer, frame.width, frame.height, list.length > 1 ? i + 1 : 0));
      });
    } catch (_) {
      return { image_note: 'failed' };
    }
    if (!marks[0]) return Array.isArray(pointers) ? Object.assign(part, { marks: marks }) : part;
    return Array.isArray(pointers) ? Object.assign(part, { mark: marks[0], marks: marks }) : Object.assign(part, { mark: marks[0] });
  }

  // What was drawn on an image, painted over it on a picture of frame's
  // size: earlier turns' shapes lighter, then this turn's (the board's
  // painter, WorkbenchWhiteboard, as the pane shows them).
  function paintDrawing(context, frame, img, drawing) {
    const board = window.WorkbenchWhiteboard;
    if (!drawing || !board || typeof board.paintShapes !== 'function') return;
    const size = board.overlayFrame(img.naturalWidth, img.naturalHeight);
    if (!size) return;
    const of = (shapes) => Object.assign({ shapes: shapes }, size);
    if (Array.isArray(drawing.earlier) && drawing.earlier.length > 0) {
      const alpha = typeof drawing.earlierAlpha === 'number' ? drawing.earlierAlpha : board.EARLIER_ALPHA;
      board.paintShapes(of(drawing.earlier), context, frame.width, frame.height, alpha);
    }
    if (Array.isArray(drawing.shapes) && drawing.shapes.length > 0) {
      board.paintShapes(of(drawing.shapes), context, frame.width, frame.height);
    }
  }

  // A capture of a PDF: the page in view and, as asked, the part of it in
  // view and the text selected in it, all from the drawing shown now.
  function pdfAnswer(data, drawn) {
    const handle = drawn.pdf;
    const shown = handle.shown();
    const wants = Array.isArray(data.wants) ? data.wants : [];
    const out = { range: { page: shown.page, pages: shown.pages }, note: null };
    // The mark the user put on this page.
    const pointer = typeof handle.pointer === 'function' ? handle.pointer() : null;
    const onPage = pointer && pointer.page === shown.page ? pointer : null;
    if (wants.includes('selection')) {
      if (onPage) {
        const [marked, markCut] = markedText(handle, onPage);
        if (marked) {
          out.mark_text = marked;
          out.mark_cut = markCut;
        }
      }
      let [text, cut] = selectedText(handle.textLayer());
      // The page's selection gone (the user clicked elsewhere): the text
      // they selected on this page, as held.
      const held = !text && offeredSelection();
      if (held && held.page === shown.page) [text, cut] = [held.text, held.cut];
      if (text) {
        out.selection_text = text;
        out.selection_cut = cut;
      }
    }
    if (wants.includes('image')) {
      // The mark is drawn on what is cut, and said where it is.
      const marked = onPage ? drawingMark(handle, onPage) : null;
      let part;
      try {
        part = cutPage(handle, shown.drawing, marked ? marked.decorate : undefined);
      } catch (_) {
        part = { image_note: 'failed' };
      }
      Object.assign(out, part);
      if (marked && part.image && marked.mark()) out.mark = marked.mark();
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
    const drawn = drawnBody && drawnBody.key === drawKey(item) ? drawnBody : null;
    if (drawn && drawn.pdf && now.range && Number.isInteger(now.range.page)) return pdfAnswer(data, drawn);
    if (drawn && drawn.image) return imageAnswer(data, drawn.image, item);
    if (drawn && drawn.whiteboard) return whiteboardAnswer(data, drawn);
    const lines = now.range && Number.isInteger(now.range.first_line) && Number.isInteger(now.range.last_line);
    if (wants.includes('range') && lines) {
      const out = { range: { first_line: now.range.first_line, last_line: now.range.last_line }, note: null };
      const chosen = wants.includes('selection') && drawn ? linesChosen(drawn, item, version) : null;
      if (chosen) out.selected_lines = chosen;
      return out;
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

  // The notes the app adds after a reply (data.notes): 'updating' while
  // they are made. Shown on the work screen's tab and above its items
  // only: the reply's own status (the top of the page, the spinner, Ready)
  // is not touched.
  function showNotesStatus(state) {
    const mark = $id('side-tab-work-mark');
    const line = $id('workbench-notes-status');
    const text = state === 'updating' ? t('ui.workbench.notesUpdating', 'Updating the notes…') : '';
    if (mark) {
      mark.hidden = state !== 'updating';
      if (text) mark.setAttribute('title', text); else mark.removeAttribute('title');
    }
    if (line) {
      line.textContent = text;
      line.hidden = !text;
    }
  }

  function onView(data) {
    const next = data && data.board;
    if (!next || !Array.isArray(next.items)) return;
    if (board && next.chat_id === board.chat_id && next.board_id && next.board_id === board.board_id &&
        next.revision < board.revision) return;
    const switched = !!board && next.chat_id !== board.chat_id;
    if (switched) reset();
    showNotesStatus(data.notes || null);
    const before = items().map((item) => item.id);
    const versions = new Map(rowItems().map((item) => [item.id, item.version]));
    board = next;
    approvals = data.approvals || {};
    assets = data.assets || {};
    renders = data.renders || {};
    backgrounds = data.backgrounds || {};
    const news = [];
    // A document whose versions are listed, while it is the one shown.
    const listed = selected ? itemById(selected) : null;
    if (versionsOf && listed && listed.path === versionsOf) askVersions(versionsOf);
    else versionsOf = null;
    if (selected && !itemById(selected)) selected = null;
    const arrived = rowItems().filter((item) => !seen.has(item.id));
    arrived.forEach((item) => seen.add(item.id));
    if (before.length === 0 && !data.initial && !workPaneShown()) arrived.forEach((item) => firsts.add(item.id));
    // A selection whose item has not arrived yet is taken when it does.
    const held = data.selected && itemById(data.selected) ? data.selected : null;
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
    if (told && held && held !== selected && itemById(held) && !data.initial) {
      // An item offered quietly (the notes after a reply) is shown only on
      // a work screen that shows nothing; otherwise the server is told what
      // this tab still shows. The pane turns to it only when it is the
      // first item of the chat's work screen.
      if (data.selection_quiet) {
        const first = firsts.has(held);
        firsts.clear();
        if (!selected && !local) {
          selected = held;
          if (first && !writing() && autoSwitch()) showWorkPane();
        } else {
          tellSelected();
        }
      } else {
        bringForward(itemById(held));
      }
    }
    // A new item, or a new version of one (the notes made again), while
    // another pane is shown.
    if (!switched && !data.initial && !workPaneShown() &&
        rowItems().some((item) => !versions.has(item.id) || versions.get(item.id) !== item.version)) {
      markUnseen(true);
    }
    // What the user opened is shown, whatever the server's selection said.
    if (pendingOpen && itemById(pendingOpen)) {
      showOpened(pendingOpen);
      pendingOpen = null;
    }
    // A connection's first board: the server knows nothing of this tab yet.
    // What the page still shows is told again; otherwise the chat's open
    // browser is shown, as before.
    if (data.initial) {
      // The chat's open browser first; an item offered quietly fills a
      // screen that would show nothing. A shown attachment stays, and the
      // server is told so.
      if (!selected && !local) {
        const open = rowItems().find(liveBrowser);
        if (open) selected = open.id;
        else if (held && data.selection_quiet) selected = held;
      }
      if (selected || held) tellSelected();
    }
    // Images the board put away to make room (not removed here).
    if (before.some((id) => !itemById(id) && !removed.has(id))) {
      news.push(t('ui.workbench.putAway', 'An older item was removed from the work screen.'));
    }
    if (news.length > 0) announce(news.join(' '));
    draw();
    paintBoardImages();
    refreshRelay();
    if (resumedChat && next.chat_id === resumedChat) {
      resumedChat = null;
      const lc = window.LayoutController;
      if (lc && rowItems().length > 0 && lc.selectedPane() !== 'work') lc.setPane('work');
    }
  }

  // A chat continued from the history shows its work screen when its board
  // has something on it; the board comes after the history's answer.
  let resumedChat = null;
  function expectResumed(chatId) {
    resumedChat = chatId ? String(chatId) : null;
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
    if (!view) return;
    view.hidden = false;
    delete view.dataset.item;
    const key = `${local.key}|${local.serial}|${local.note || ''}`;
    if (view.dataset.local === key) return;
    dropLocalPdf();
    letGo(drawnBody);
    drawnBody = null;
    letGoOthers();
    view.dataset.local = key;
    const body = element('div', 'workbench-body');
    const info = element('div', 'workbench-info');
    let note = local.note;
    if (!note && (local.kind === 'image' || local.kind === 'pdf') && !local.data) note = 'no_data';
    if (note) {
      body.appendChild(element('div', 'alert alert-warning mb-2', noteText(note)));
    } else if (local.kind === 'image' && IMAGE_DATA.test(local.data)) {
      const img = enlargeable(element('img', 'workbench-image'));
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
    // Shown from the message, not put on the work screen: the AI cannot look
    // at it here, nor the user point at it.
    if (!local.attachmentId && !note) {
      info.appendChild(element('div', 'workbench-local-note mt-2',
        t('ui.workbench.localNotShared', 'The AI does not see this view. To look at it together, put the file on the work screen.')));
    }
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
    pendingOpen = null;
    showOwn(data.item_id);
  }

  // ---- A file from the computer -----------------------------------------

  // A file the user puts on the work screen (the button, or dropped on the
  // pane) is saved in the chat's folder (inputs/) and opened as an item of
  // the board, which the AI can look at and the user point at. A few at a
  // time, one after another; the last one put is shown.
  const PUT_AT_ONCE = 5;
  const PUT_REASONS = {
    extension: ['ui.workbench.putKind', 'The work screen does not show this kind of file.'],
    content: ['ui.workbench.putContent', "The file's contents do not match its name."],
    too_large: ['ui.workbench.putTooLarge', 'This file is too large for the work screen.'],
    workspace_missing: ['ui.workbench.putNoFolder', "The chat's folder is not available. Start a new chat and try again."],
    unavailable: ['ui.workbench.putNoFolder', "The chat's folder is not available. Start a new chat and try again."],
    no_chat: ['ui.workbench.putReload', 'This page is no longer connected. Reload it and try again.']
  };

  async function putFile(file) {
    if (!window.monadicFetch || typeof window.monadicFetch.postJson !== 'function') return;
    if (locked()) {
      warn(lockText());
      return;
    }
    const form = new FormData();
    form.append('file', file);
    form.append('purpose', 'workbench');
    try {
      const record = await window.monadicFetch.postJson('/attachments', form);
      openAttachment({ key: `put:${record.attachment_id}`, kind: 'file', attachmentId: record.attachment_id,
                       name: record.name || file.name, size: record.size || file.size });
    } catch (e) {
      const reason = e && e.body && PUT_REASONS[e.body.reason];
      const why = reason ? t(reason[0], reason[1]) : (e && e.message) || '';
      warn(t('ui.workbench.putFailed', 'Could not put {name} on the work screen: {why}')
        .replace('{name}', file.name).replace('{why}', why));
    }
  }

  async function putFiles(files) {
    const list = Array.from(files || []).filter((f) => f && typeof f.name === 'string');
    if (list.length > PUT_AT_ONCE) {
      warn(t('ui.workbench.putAtOnce', 'Up to {n} files are put at once.').replace('{n}', String(PUT_AT_ONCE)));
    }
    for (const file of list.slice(0, PUT_AT_ONCE)) await putFile(file);
  }

  // Files kept with a message as data ({ title, type, data: a data URL }),
  // put on the work screen as files from the computer are.
  function putDataFiles(entries) {
    const files = (Array.isArray(entries) ? entries : []).filter((entry) => entry && typeof entry.data === 'string' &&
      entry.data.startsWith('data:')).map((entry) => {
      const comma = entry.data.indexOf(',');
      const binary = atob(entry.data.slice(comma + 1));
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
      return new File([bytes], String(entry.title || 'file'), { type: String(entry.type || '') });
    });
    if (files.length) putFiles(files);
  }

  // Whether a drag carries files from the computer.
  const carriesFiles = (e) => !!(e.dataTransfer && Array.from(e.dataTransfer.types || []).includes('Files'));

  function wirePut() {
    // The short buttons above the work screen say what each does (their
    // titles) on hover and on focus.
    if (window.MonadicTip) {
      ['workbench-put', 'workbench-new-whiteboard', 'workbench-open-url'].forEach((id) => {
        const el = $id(id);
        if (el) window.MonadicTip.attach(el, { delay: { show: 500, hide: 0 } });
      });
    }
    $on($id('workbench-new-whiteboard'), 'click', () => newWhiteboard());
    const button = $id('workbench-put');
    const input = $id('workbench-put-input');
    const pane = $id('work-screen-pane');
    if (button && input) {
      $on(button, 'click', () => input.click());
      $on(input, 'change', () => {
        const files = Array.from(input.files || []);
        input.value = '';
        putFiles(files);
      });
    }
    if (pane) {
      let depth = 0;
      const dropping = (on) => pane.classList.toggle('workbench-dropping', on);
      $on(pane, 'dragenter', (e) => {
        if (!carriesFiles(e)) return;
        depth += 1;
        dropping(true);
      });
      $on(pane, 'dragleave', (e) => {
        if (!carriesFiles(e)) return;
        depth = Math.max(0, depth - 1);
        if (depth === 0) dropping(false);
      });
      $on(pane, 'dragover', (e) => {
        if (!carriesFiles(e)) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'copy';
      });
      $on(pane, 'drop', (e) => {
        if (!carriesFiles(e)) return;
        e.preventDefault();
        depth = 0;
        dropping(false);
        putFiles(e.dataTransfer.files);
      });
    }
    // A file dropped anywhere else on the page does not replace the page.
    window.addEventListener('dragover', (e) => { if (carriesFiles(e)) e.preventDefault(); });
    window.addEventListener('drop', (e) => { if (carriesFiles(e)) e.preventDefault(); });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', wirePut);
    document.addEventListener('DOMContentLoaded', wireJump);
  } else {
    wirePut();
    wireJump();
  }

  // ---- JupyterLab ------------------------------------------------------

  // A notebook opens in JupyterLab only when the user asks (a link to it in
  // the conversation, or the button on the work screen): the server starts
  // JupyterLab when it does not answer, and answers with the notebook's
  // address. A link counts when it is JupyterLab's on this machine
  // (127.0.0.1 or localhost, /lab/tree/, a .ipynb); the server takes only
  // the notebook's path from it. The click is taken on the window before
  // anything on the document sees it: the desktop app opens every web link
  // it gets in the system browser.
  const JUPYTER_HOSTS = ['127.0.0.1', 'localhost'];
  let jupyterAsked = null;

  function jupyterPath(href) {
    let url;
    try {
      url = new URL(href, window.location.href);
    } catch (_) {
      return null;
    }
    if (url.protocol !== 'http:' || !JUPYTER_HOSTS.includes(url.hostname) || url.username || url.password) return null;
    if (!url.pathname.startsWith('/lab/tree/')) return null;
    let path;
    try {
      path = url.pathname.slice('/lab/tree/'.length).split('/').map(decodeURIComponent).join('/');
    } catch (_) {
      return null;
    }
    return /\.ipynb$/i.test(path) ? path : null;
  }

  function jupyterSay(key, fallback, kind) {
    if (typeof window.setAlert === 'function') window.setAlert(t(`ui.workbench.${key}`, fallback), kind);
  }

  function openInJupyter(path) {
    if (typeof window.safeWsSend !== 'function') return;
    const request = newOperationId();
    // In a web browser the tab is opened now, while the click lets it be,
    // and given the address once JupyterLab answers. The desktop app opens
    // the address in the system's browser instead.
    const pending = window.electronAPI ? null : window.open('about:blank', '_blank');
    if (jupyterAsked && jupyterAsked.tab && !jupyterAsked.tab.closed) jupyterAsked.tab.close();
    jupyterAsked = { request, tab: pending };
    jupyterSay('jupyterStarting', 'Starting JupyterLab…', 'info');
    window.safeWsSend({ message: 'JUPYTER_OPEN', path: String(path), request });
  }

  function onJupyterOpened(data) {
    if (!data || !jupyterAsked || data.request !== jupyterAsked.request) return;
    const { tab } = jupyterAsked;
    jupyterAsked = null;
    if (!data.success || typeof data.url !== 'string') {
      if (tab && !tab.closed) tab.close();
      const keys = { not_a_notebook: ['jupyterNotNotebook', 'This is not a notebook in the shared folder.'],
                     python_starting: ['jupyterPythonStarting', 'The Python container is starting. Try again in a moment.'] };
      const [key, fallback] = keys[data.error] || ['jupyterNotStarted', 'JupyterLab could not be started.'];
      jupyterSay(key, fallback, data.error === 'python_starting' ? 'warning' : 'error');
      return;
    }
    jupyterSay('jupyterOpened', 'Opened in JupyterLab.', 'success');
    if (tab && !tab.closed) tab.location.href = data.url;
    else window.open(data.url, '_blank');
  }

  function onJupyterLinkClick(e) {
    if (e.defaultPrevented || e.button !== 0) return;
    const link = e.target && e.target.closest ? e.target.closest('#discourse a[href]') : null;
    const path = link ? jupyterPath(link.getAttribute('href')) : null;
    if (!path) return;
    e.preventDefault();
    e.stopPropagation();
    openInJupyter(path);
  }

  // An image the conversation shows from the shared folder (/data/…):
  // opened on the work screen as the Files tab opens it.
  function sharedPathOf(img) {
    const src = img.getAttribute('src') || '';
    if (!src.startsWith('/data/')) return null;
    try {
      return decodeURIComponent(src.slice('/data/'.length).split(/[?#]/)[0]) || null;
    } catch (_) {
      return null;
    }
  }

  // A file of a sent message (its card): an image or a PDF from the
  // message's own data, an audio or video by its attachment; an image the
  // reply shows from the shared folder.
  function onCardClick(e) {
    const at = (selector) => (e.target && e.target.closest ? e.target.closest(selector) : null);
    const generated = at('#discourse .generated_image img:not([data-action])');
    if (generated) {
      const path = sharedPathOf(generated);
      if (!path) return;
      e.preventDefault();
      bringPane();
      openFile(path);
      return;
    }
    const image = at('#discourse .card .base64-image, #discourse .card .mask-overlay-container');
    if (image) {
      const img = image.matches('img') ? image : image.querySelector('img.base-image');
      if (!img) return;
      const card = image.closest('.card');
      const name = img.getAttribute('alt') || '';
      showAttachment({ source: 'message', key: `message:${card ? card.id : ''}:${name}`, kind: 'image', name,
                       data: img.getAttribute('src') || null });
      return;
    }
    const preview = at('#discourse .pdf-preview');
    const attachment = at('#discourse .message-attachments [data-attachment-id]');
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

  // An image of the work screen is shown larger, over the whole window, on a
  // click (or Enter or Space); a click on the larger image, outside it, or
  // Esc closes it.
  function enlargeable(img) {
    img.classList.add('workbench-zoomable');
    img.tabIndex = 0;
    img.setAttribute('role', 'button');
    img.title = t('ui.workbench.enlarge', 'Show it larger');
    return img;
  }

  function enlarge(img) {
    const modal = $id('workbenchZoom');
    const big = $id('workbench-zoom-image');
    if (!modal || !big || !window.MonadicDialog) return;
    big.src = img.currentSrc || img.src;
    big.alt = img.alt || '';
    window.MonadicDialog.of(modal).open(img);
  }

  function onZoomClick(e) {
    const target = e.target && e.target.closest ? e.target : null;
    if (!target) return;
    if (target.id === 'workbench-zoom-image') {
      window.MonadicDialog.of($id('workbenchZoom')).close('button');
      return;
    }
    const img = target.closest('#workbench-view .workbench-zoomable');
    if (img) enlarge(img);
  }

  function onZoomKey(e) {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    const img = e.target && e.target.closest ? e.target.closest('#workbench-view .workbench-zoomable') : null;
    if (!img) return;
    e.preventDefault();
    enlarge(img);
  }

  if (typeof document !== 'undefined') {
    document.addEventListener('click', onCardClick);
    document.addEventListener('click', onZoomClick);
    document.addEventListener('keydown', onZoomKey);
  }
  if (typeof window !== 'undefined') window.addEventListener('click', onJupyterLinkClick, true);

  function onResult(data) {
    if (!data) return;
    if (['accepted', 'same'].includes(data.status)) {
      if (data.state === 'removed') {
        removed.add(data.item_id);
        announce(t('ui.workbench.removed', 'Removed from the work screen'));
      } else if (data.state === 'stashed') {
        announce(t('ui.workbench.stashed', 'Put away'));
      } else if (data.state === 'brought') {
        announce(t('ui.workbench.brought', 'Brought into Now'));
      }
      return;
    }
    if (data.status === 'refused') warn(refusalText(data.reason));
  }

  // Why an operation was not taken (Channel::REFUSALS).
  function refusalText(reason) {
    if (reason === 'replying') return lockText();
    if (reason === 'now_full') return t('ui.workbench.nowFull', 'Now is full: take an item off or put one away first.');
    if (reason === 'whiteboard_used') {
      return t('ui.workbench.wbUsed', 'A whiteboard was placed in this turn already: draw on it, or place another after your next message.');
    }
    if (reason === 'whiteboard_frozen') {
      return t('ui.workbench.wbFrozen', 'This whiteboard left Now and is kept as it was. Place a new whiteboard to draw.');
    }
    if (reason === 'this item changed') return t('ui.workbench.changedSinceShown', 'The file changed after it was shown.');
    return t('ui.workbench.refused', 'This was not accepted.');
  }

  // A file the user asked to open: it is shown (the column too), or the
  // reason is given.
  function onOpened(data) {
    if (!data) return;
    const asked = opening;
    opening = null;
    const fallback = typeof data.path === 'string' ? excerptFallbacks.get(data.path) : null;
    if (typeof data.path === 'string') excerptFallbacks.delete(data.path);
    if (data.status === 'refused' && fallback) {
      showExcerpt(fallback);
      return;
    }
    if (data.status === 'refused') {
      const reason = data.reason === 'busy' ? t('ui.workbench.busy', 'The work screen is reading other files. Try again in a moment.')
        : data.reason === 'changed' ? t('ui.workbench.changedSinceShown', 'The file changed after it was shown.')
          : data.reason === 'missing' && data.library_id ? t('ui.workbench.libraryMissing', 'This entry is no longer in the Library.')
            : data.reason === 'incomplete' ? t('ui.workbench.libraryIncomplete', 'The Library did not keep the whole text of this entry.')
              : (data.reason || '');
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

  // An item this tab's user put, made or opened (a whiteboard, an address):
  // it is selected here once it is on the board, as a click on its tab
  // selects it, whatever was selected before.
  function showOwn(id) {
    if (!id) return;
    if (itemById(id)) showOpened(id);
    else pendingOpen = id;
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

  // The address to save an image or a file from: it is fetched here and handed
  // to the browser as a download, so whatever the answer the page stays.
  async function onDownload(data) {
    if (!data) return;
    if (data.status === 'refused' && data.reason === 'changed') {
      warn(statusText('changed'));
      askView(true);
      return;
    }
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
    saveBlob(blob, data.name);
  }

  // Hands blob to the browser as a download named name (Electron asks
  // where to save it).
  function saveBlob(blob, name) {
    const href = URL.createObjectURL(blob);
    const a = element('a');
    try {
      a.href = href;
      a.download = String(name || 'file');
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
  // The picture of the work screen a user's message was sent with (its
  // reference): a line on the message's card that shows it in the work
  // screen, asked of the server when clicked.
  // pictures: the message's references (a list; a message from before has
  // one): a line each on the message's card, opening the picture as sent.
  function drawPicture(mid, pictures) {
    if (!mid) return;
    const card = $id(mid);
    const text = card ? card.querySelector('.card-text') : null;
    if (!text) return;
    let el = text.querySelector(':scope > .workbench-picture-note');
    const list = (Array.isArray(pictures) ? pictures : [pictures]).filter((p) => p && typeof p.id === 'string');
    if (list.length === 0) {
      if (el) el.remove();
      return;
    }
    if (!el) {
      el = element('div', 'workbench-picture-note text-secondary mt-2');
      text.appendChild(el);
    }
    el.replaceChildren();
    list.forEach((picture) => {
      const line = element('div', 'workbench-note-line');
      line.appendChild(element('i', 'fa-solid fa-crosshairs me-1'));
      const open = element('button', 'btn btn-link btn-sm p-0 align-baseline workbench-picture-open');
      open.type = 'button';
      open.textContent = picture.kind === 'image'
        ? t('ui.workbench.pictureSentImage', 'The work screen as sent (image)')
        : t('ui.workbench.pictureSent', 'The work screen as sent (page {n})').replace('{n}', String(picture.page));
      open.addEventListener('click', () => {
        if (typeof window.safeWsSend === 'function') window.safeWsSend({ message: 'WORKBENCH_PICTURE', picture_id: picture.id });
      });
      line.appendChild(open);
      el.appendChild(line);
    });
  }

  // The text a user's message was sent with, selected in the work screen
  // (its reference): a line on the message's card that shows the text when
  // clicked.
  function drawSelection(mid, selection) {
    if (!mid) return;
    const card = $id(mid);
    const text = card ? card.querySelector('.card-text') : null;
    if (!text) return;
    let el = text.querySelector(':scope > .workbench-selection-note');
    if (!selection || typeof selection.text !== 'string') {
      if (el) el.remove();
      return;
    }
    if (!el) {
      el = element('div', 'workbench-selection-note small text-secondary mt-2');
      text.appendChild(el);
    }
    el.replaceChildren();
    const line = element('div', 'workbench-note-line');
    line.appendChild(element('i', 'fa-solid fa-i-cursor me-1'));
    const open = element('button', 'btn btn-link btn-sm p-0 align-baseline workbench-selection-open');
    open.type = 'button';
    open.setAttribute('aria-expanded', 'false');
    open.textContent = selection.kind === 'text'
      ? t('ui.workbench.selectionSentLines', 'Selected lines ({first}–{last})').replace('{first}', String(selection.first))
        .replace('{last}', String(selection.last))
      : t('ui.workbench.selectionSent', 'Selected text (page {n})').replace('{n}', String(selection.page));
    const quote = selection.kind === 'text'
      ? element('pre', 'workbench-selection-quote workbench-selection-lines', selection.text)
      : element('blockquote', 'workbench-selection-quote', selection.text);
    quote.hidden = true;
    open.addEventListener('click', () => {
      quote.hidden = !quote.hidden;
      open.setAttribute('aria-expanded', quote.hidden ? 'false' : 'true');
    });
    line.appendChild(open);
    el.append(line, quote);
  }

  // The server's answer to WORKBENCH_PICTURE: the picture, shown in the work
  // screen as an attachment is (from the page's data), or a note that it is
  // gone.
  function onPicture(data) {
    if (!data || typeof data.picture_id !== 'string') return;
    if (!data.found || typeof data.data !== 'string' || !IMAGE_DATA.test(data.data)) {
      warn(t('ui.workbench.pictureGone', 'The picture sent with this message is no longer kept.'));
      return;
    }
    showAttachment({ kind: 'image', key: `picture:${data.picture_id}`, data: data.data,
                     title: t('ui.workbench.pictureTitle', 'The work screen as sent') });
  }

  // The server's answer to WORKBENCH_SENT_IMAGE: the image, shown in the
  // work screen as an attachment is, or a note that it is no longer kept.
  function onSentImage(data) {
    if (!data || typeof data.sha256 !== 'string') return;
    if (!data.found || typeof data.data !== 'string' || !IMAGE_DATA.test(data.data)) {
      warn(t('ui.workbench.sentImageGone', 'The image sent is no longer kept in the chat\'s folder.'));
      return;
    }
    showAttachment({ kind: 'image', key: `sent:${data.sha256}`, data: data.data,
                     title: t('ui.workbench.sentImageTitle', 'The image sent') });
  }

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
      const pointed = entry.point && typeof entry.point === 'object' ? entry.point : null;
      line.appendChild(element('i', pointed ? 'fa-solid fa-location-crosshairs me-1' : 'fa-solid fa-display me-1'));
      line.appendChild(document.createTextNode(pointed
        ? `${t('ui.workbench.pointedOn', 'Pointed at in the work screen')}: `
        : `${t('ui.workbench.shownOn', 'Shown in the work screen')}: `));
      const open = element('button', 'btn btn-link btn-sm p-0 align-baseline workbench-shown-open');
      open.type = 'button';
      open.title = t('ui.workbench.open', 'Show in the work screen');
      open.appendChild(element('code', null, String(entry.name || entry.path)));
      shortenPaths(open);
      // The section beside the path, so the path alone is shown by its name.
      if (typeof entry.section === 'string') open.appendChild(element('span', null, ` § ${entry.section}`));
      if (pointed) {
        const where = Array.isArray(pointed.lines)
          ? t('ui.workbench.pointedLines', 'lines {first}–{last}').replace('{first}', String(pointed.lines[0]))
            .replace('{last}', String(pointed.lines[1]))
          : t('ui.workbench.pointedPage', 'page {n}').replace('{n}', String(pointed.page));
        open.appendChild(element('span', null, ` · ${where}`));
      }
      open.addEventListener('click', () => {
        // Where the AI pointed: the file at that version, marked there again.
        if (pointed) pointAt(entry.path, entry.sha256, pointed);
        // A section of a document: the document as it is now, at the section.
        if (typeof entry.section === 'string') {
          pendingSection = { path: entry.path, section: entry.section };
          const doc = items().find((i) => i.kind === 'file' && i.path === entry.path);
          if (!doc) {
            openFile(entry.path);
            return;
          }
          openItem(doc.id);
          if (drawnBody && drawnBody.loaded && selected === doc.id) scrollToSection(scroller(drawnBody), entry.path);
          return;
        }
        const item = items().find((i) => i.kind === 'file' && i.path === entry.path && i.sha256 === entry.sha256);
        if (item) openItem(item.id);
        else openFile(entry.path, entry.sha256);
      });
      line.appendChild(open);
      el.appendChild(line);
    });
  }

  // What a reply read from the Library (library_readings), by its message:
  // one line per search, with its copy on the work screen to open.
  const readingRecords = new Map();

  function drawReadings(mid, list) {
    if (!mid) return;
    const entries = (Array.isArray(list) ? list : []).filter((r) => r && typeof r.id === 'string' && Array.isArray(r.excerpts));
    if (entries.length === 0) readingRecords.delete(mid);
    else readingRecords.set(mid, entries);
    const card = $id(mid);
    const text = card ? card.querySelector('.card-text') : null;
    if (!text) return;
    let el = text.querySelector(':scope > .workbench-reading-note');
    if (entries.length === 0) {
      if (el) el.remove();
      return;
    }
    if (!el) {
      el = element('div', 'workbench-reading-note small text-secondary mt-2');
      text.appendChild(el);
    }
    el.replaceChildren();
    entries.forEach((reading) => {
      const line = element('div', 'workbench-note-line');
      line.appendChild(element('i', 'fa-solid fa-book-open me-1'));
      const cited = Array.isArray(reading.cited) ? reading.cited.length : 0;
      const count = reading.excerpts.length === 0
        ? t('ui.workbench.libraryNone', 'nothing found')
        : t('ui.workbench.libraryCount', '{n} passages, {cited} cited')
          .replace('{n}', String(reading.excerpts.length)).replace('{cited}', String(cited));
      line.appendChild(document.createTextNode(`${t('ui.workbench.libraryRead', 'Read from the Library')}: `));
      line.appendChild(element('q', null, String(reading.query || '')));
      line.appendChild(document.createTextNode(` (${count})`));
      if (typeof reading.path === 'string') {
        line.appendChild(document.createTextNode(' '));
        const open = element('button', 'btn btn-link btn-sm p-0 align-baseline workbench-reading-open');
        open.type = 'button';
        open.textContent = t('ui.workbench.open', 'Show in the work screen');
        open.addEventListener('click', () => openReading(reading));
        line.appendChild(open);
      }
      el.appendChild(line);
    });
  }

  // A reading's copy on the work screen: the item, or the file opened again.
  function openReading(reading) {
    const item = items().find((i) => i.kind === 'file' && i.path === reading.path);
    if (item) openItem(item.id);
    else openFile(reading.path);
  }

  // The excerpts shown as they were recorded when their copy, being
  // opened, is found gone (by the copy's path).
  const excerptFallbacks = new Map();

  function showExcerpt(excerpt) {
    if (window.libraryPanel && typeof window.libraryPanel.showExcerpt === 'function') window.libraryPanel.showExcerpt(excerpt);
  }

  // An excerpt a reply cites by its link (mc:read:<id>): its reading's copy
  // on the work screen, or, when the copy is gone or changed (or there was
  // none), the excerpt as it was recorded for the reply; without a record,
  // that it is no longer there.
  function openExcerpt(excerptId) {
    for (const list of readingRecords.values()) {
      for (const reading of list) {
        const excerpt = reading.excerpts.find((e) => e && e.id === excerptId);
        if (!excerpt) continue;
        const item = typeof reading.path === 'string'
          ? items().find((i) => i.kind === 'file' && i.path === reading.path) : null;
        if (item && item.status === 'ok') openItem(item.id);
        else if (typeof reading.path === 'string' && !item) {
          excerptFallbacks.set(reading.path, excerpt);
          openFile(reading.path);
        } else showExcerpt(excerpt);
        return true;
      }
    }
    showExcerpt(null);
    return false;
  }

  if (typeof document !== 'undefined') {
    document.addEventListener('click', (ev) => {
      const link = ev.target && typeof ev.target.closest === 'function' ? ev.target.closest('a[href^="mc:read:"]') : null;
      if (!link) return;
      ev.preventDefault();
      openExcerpt(link.getAttribute('href').slice('mc:read:'.length));
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
    onView, expectResumed, onResult, locked, picturesNow, erasuresNow, onMarksKeptErased, onDownload, onOpened, onVersions, onSelected, onCapture, drawRecord, drawLooks, drawShown, drawEdits, drawReadings, openExcerpt, onToLibrary, openLibrary, onSentImage, select, openFile, step,
    showAttachment, onAttachmentOpened, showOwn, putDataFiles, openInJupyter, onJupyterOpened, jupyterPath, shownAttachment: () => (local ? Object.assign({}, local) : null),
    textLines, rangeNow, pictureNow, drawPicture, onPicture, selectionNow, drawSelection, onPoint, clearAiPoint, onWhiteboard, flushWhiteboards, afterWhiteboardSaves, onWhiteboardImage,
    showTurn, onTurnView, backToNow, turnShown: () => (past ? past.mid : null),
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
