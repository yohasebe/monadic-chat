// The shared folder page: what the shared folder holds, one folder at a
// time, with each entry's size, what it is, and whether it must be kept or
// is in use; searched, sorted and filtered on the server. In the desktop
// app an entry can be shown in the file manager, and entries the server
// allows can be moved to the system's trash. Names come from the folder, so
// they are always set as text.
(function () {
  'use strict';

  const SIZE_POLLS = 15;      // times to ask again for one folder's size
  const SIZES_PER_ASK = 200;  // folders per request (the server's limit)
  const PAGE_SIZES = [100, 200, 500];
  const PAGE_SIZE_KEY = 'monadic-shared-folder-page-size';
  const FILES_ONLY_KEY = 'monadic-shared-folder-files-only';
  const SIZE_POLL_MS = 2000;

  let state = { path: '', page: 1, items: [], total: 0, matched: 0, truncated: false, rootId: null, rootIdProblem: null };
  // What the list is narrowed and ordered by (kept while moving between folders).
  let view = { q: '', sort: 'name', cls: '', age: '', perPage: savedPageSize() };

  function savedPageSize() {
    try {
      const n = Number(window.localStorage && window.localStorage.getItem(PAGE_SIZE_KEY));
      if (PAGE_SIZES.indexOf(n) >= 0) return n;
    } catch (_) { /* no storage here */ }
    return 200;
  }

  // What is known of chosen entries that may not be on the page shown
  // (their kind and size, for the total): from the pages seen and from
  // "choose all".
  let known = new Map();
  // Paths chosen for the trash, in the folder shown now.
  let selected = new Set();
  // Bumped whenever the choice is changed by hand, so a slow "choose all"
  // does not bring back what was cleared or changed after it was asked.
  let choiceGeneration = 0;
  let matchingBusy = false;
  const TRASH_PER_REQUEST = 20000; // the desktop app's limit (MAX_TRASH)

  // Each load, refresh or close starts a new generation; a response or a
  // timer of an older one is dropped, so the page never goes back to a
  // folder it has left, and nothing keeps running once it is closed.
  let generation = 0;
  let controller = null;
  let timer = null;
  // path => times its size was asked for. A Map, so a folder named like an
  // object's own property (constructor, __proto__) counts from 0 too.
  let asked = new Map();
  let isOpen = false;
  let resortDue = false;      // a size came in while the list is in size order

  function nextGeneration() {
    generation += 1;
    clearTimeout(timer);
    timer = null;
    if (controller) controller.abort();
    controller = (typeof AbortController !== 'undefined') ? new AbortController() : null;
    return generation;
  }

  function t(key, fallback) {
    try {
      if (typeof webUIi18n !== 'undefined') {
        const v = webUIi18n.t('ui.sharedFolderPanel.' + key);
        if (v && v !== 'ui.sharedFolderPanel.' + key) return v;
      }
    } catch (_) { /* fall back */ }
    return fallback;
  }

  function el(tag, opts, children) {
    const node = document.createElement(tag);
    if (opts) {
      if (opts.className) node.className = opts.className;
      if (opts.text !== undefined) node.textContent = opts.text;
      if (opts.title) node.title = opts.title;
      if (opts.type) node.type = opts.type;
    }
    (children || []).forEach(function (c) { if (c) node.appendChild(c); });
    return node;
  }

  function icon(cls) {
    const i = document.createElement('i');
    i.className = cls;
    i.setAttribute('aria-hidden', 'true');
    return i;
  }

  function formatBytes(bytes) {
    if (typeof bytes !== 'number') return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let value = bytes;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit += 1; }
    return (unit === 0 ? String(value) : value.toFixed(1)) + ' ' + units[unit];
  }

  function sizeText(item) {
    switch (item.size_status) {
      case 'complete': return formatBytes(item.bytes);
      case 'partial': return '≥ ' + formatBytes(item.bytes);
      case 'permission_denied': return '≥ ' + formatBytes(item.bytes) + ' (' + t('noPermission', 'partly unreadable') + ')';
      case 'vanished': return t('gone', 'gone');
      case 'pending': return t('counting', 'counting…');
      case 'not_counted': return t('notCounted', 'not counted yet (refresh)');
      case 'changed': return t('changed', 'changed while counting');
      case 'failed': return t('countFailed', 'could not be counted');
      default: return '';
    }
  }

  const CLASS_LABELS = {
    chat_folders: ['chatFolders', 'Chat folders'],
    chat_folder: ['chatFolder', 'Chat folder'],
    public_copy: ['publicCopy', 'Copy for playback'],
    generated: ['generated', 'Generated file'],
    intermediate_candidate: ['intermediate', 'Possibly a working file'],
    test_file: ['testFile', 'Made by a test run'],
    test_candidate: ['testCandidate', 'Possibly left by a test run'],
    projects: ['projects', 'AutoForge projects'],
    transcriptions: ['transcriptions', 'Transcriptions'],
    documents: ['documents', 'Documents'],
    library_sources: ['librarySources', 'Knowledge Base imports'],
    protected: ['protected', 'Kept by Monadic Chat'],
    other: ['other', 'Other']
  };

  const PROTECTED_LABELS = {
    user_scripts: ['keptUserScripts', 'Your scripts, run by the apps'],
    user_apps: ['keptUserApps', 'Your apps and helpers, loaded at start'],
    user_services: ['keptUserServices', 'Your Docker services'],
    help_install: ['keptHelpInstall', 'Used while the help data installs'],
    browser_session: ['keptBrowserSession', 'The browser session of the web tools'],
    database_backup: ['keptDatabaseBackup', 'A backup of the document database'],
    folder_id: ['keptFolderId', 'Identifies this shared folder to the desktop app']
  };

  function protectedText(code) {
    const label = PROTECTED_LABELS[code];
    return label ? t(label[0], label[1]) : t('kept', 'Kept by Monadic Chat');
  }

  function whatItIs(item) {
    const label = CLASS_LABELS[item.classification] || CLASS_LABELS.other;
    let text = t(label[0], label[1]);
    if (item.app_name) text += ' · ' + item.app_name;
    if (item.classification_source === 'name' && item.classification !== 'protected') {
      text += ' ' + t('byName', '(by its name)');
    } else if (item.classification === 'chat_folder' && item.classification_source === 'none') {
      text += ' ' + t('notInLedger', '(not in the record)');
    }
    return text;
  }

  function canReveal(item) {
    return !!(item.capabilities && item.capabilities.reveal && state.rootId &&
              window.electronAPI && typeof window.electronAPI.revealSharedEntry === 'function');
  }

  function canTrash(item) {
    return !!(item.capabilities && item.capabilities.trash && state.rootId &&
              window.electronAPI && typeof window.electronAPI.trashSharedEntries === 'function');
  }

  // Choosing rows as in a file manager: a click chooses the row alone,
  // Cmd/Ctrl+click adds or removes it, Shift+click adds the rows from the
  // last one clicked, and pressing on a row and moving the mouse over
  // others chooses the rows passed (with Cmd/Ctrl, added to the choice).
  // Double-click or Enter opens: a folder is entered, a file previewed.
  // Rows that may not go are never chosen. Arrow keys move the choice
  // (Shift extends it), Cmd/Ctrl+A chooses all shown, Esc clears it.
  let drag = null;      // { from, last, base, x, y } while the button is held
  let anchor = null;    // index of the row last clicked
  let cursor = null;    // index of the row the keyboard is on

  function rowAt(index) {
    const body = $id('shared-folder-tbody');
    return body ? body.children[index] || null : null;
  }

  function paintRow(index) {
    const tr = rowAt(index);
    const item = state.items[index];
    if (!tr || !item) return;
    const on = selected.has(item.path);
    tr.classList.toggle('sf-selected', on);
    tr.setAttribute('aria-selected', on ? 'true' : 'false');
  }

  // The row the keyboard is on, shown apart from what is selected (a row
  // that cannot be selected can still be the current one).
  function paintCursor() {
    const body = $id('shared-folder-tbody');
    if (!body) return;
    Array.prototype.forEach.call(body.children, function (tr, n) {
      const on = n === cursor;
      tr.classList.toggle('sf-cursor', on);
      if (on) tr.setAttribute('aria-current', 'true'); else tr.removeAttribute('aria-current');
    });
  }

  function setPicked(index, value) {
    const item = state.items[index];
    if (!item || !canTrash(item)) return;
    choiceGeneration += 1;
    if (value) selected.add(item.path); else selected.delete(item.path);
    paintRow(index);
  }

  function setRange(from, to, value) {
    for (let i = Math.min(from, to); i <= Math.max(from, to); i += 1) setPicked(i, value);
  }

  function clearPicked() {
    choiceGeneration += 1;
    const before = Array.from(selected);
    selected = new Set();
    before.forEach(function (p) { paintRow(state.items.findIndex(function (i) { return i.path === p; })); });
  }

  // The choice as it was, then the rows from..to added (a drag shows the
  // rows passed now, not every row it went over on the way).
  function chooseSpan(base, from, to) {
    clearPicked();
    base.forEach(function (p) { selected.add(p); });
    state.items.forEach(function (_i, n) { paintRow(n); });
    setRange(from, to, true);
  }

  function rowIndexOf(target) {
    const body = $id('shared-folder-tbody');
    const tr = target && target.closest ? target.closest('tr') : null;
    return body && tr && tr.parentNode === body ? Array.prototype.indexOf.call(body.children, tr) : -1;
  }

  // Buttons in a row (copy, show in file manager) keep their own clicks.
  function onControl(target) {
    return !!(target && target.closest && target.closest('button, a, input, select, textarea'));
  }

  function onRowDown(e) {
    if (e.button !== 0 || onControl(e.target)) return;
    const index = rowIndexOf(e.target);
    if (index < 0) return;
    e.preventDefault(); // no text selection while dragging
    const body = $id('shared-folder-tbody');
    if (body && typeof body.focus === 'function') body.focus({ preventScroll: true });
    const add = e.metaKey || e.ctrlKey;
    const item = state.items[index];
    if (e.shiftKey && anchor !== null && anchor < state.items.length) {
      setRange(anchor, index, true);
    } else if (add) {
      setPicked(index, !selected.has(item.path));
      anchor = index;
    } else {
      clearPicked();
      setPicked(index, true);
      anchor = index;
    }
    cursor = index;
    drag = { from: index, last: index, base: add ? Array.from(selected) : [], x: e.clientX, y: e.clientY };
    renderTrashControls();
  }

  // Only a move of the mouse itself extends the drag: when the page moves
  // under a still pointer (a line of the toolbar appears), the browser
  // reports a move too, at the same place, and no row is passed over.
  function onRowMove(e) {
    if (!drag) return;
    if (typeof e.buttons === 'number' && !(e.buttons & 1)) { drag = null; return; } // released outside
    if (e.clientX === drag.x && e.clientY === drag.y) return;
    drag.x = e.clientX;
    drag.y = e.clientY;
    const index = rowIndexOf(e.target);
    if (index < 0 || index === drag.last) return;
    chooseSpan(drag.base, drag.from, index);
    drag.last = index;
    cursor = index;
    renderTrashControls();
  }

  function goUp() {
    if (state.path) load(state.path.split('/').slice(0, -1).join('/'));
  }

  // Nothing stays chosen, on this page or any other.
  function clearSelection() {
    clearPicked();
    anchor = null;
    cursor = null;
    renderTrashControls();
  }

  function openItem(item) {
    if (!item) return;
    if (item.kind === 'folder') load(item.path);
    else if (item.preview) openPreview(item);
  }

  function onRowDouble(e) {
    if (onControl(e.target)) return;
    openItem(state.items[rowIndexOf(e.target)]);
  }

  function onRowKey(e) {
    // A button or link in a row keeps its own keys; the preview has its own.
    if (previewing || (e.target !== e.currentTarget && onControl(e.target))) return;
    const count = state.items.length;
    if (!count) return;
    if (e.key === 'Escape' && selected.size) {
      e.preventDefault();
      e.stopPropagation(); // the dialog stays open
      clearPicked();
      renderTrashControls();
    } else if (e.key === 'Enter') {
      if (cursor !== null) { e.preventDefault(); openItem(state.items[cursor]); }
    } else if (e.key === ' ') {
      const item = cursor !== null ? state.items[cursor] : null;
      if (item && item.preview) { e.preventDefault(); openPreview(item); }
    } else if ((e.metaKey || e.ctrlKey) && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
      // As in a file manager: Cmd/Ctrl+Down opens, Cmd/Ctrl+Up goes up.
      e.preventDefault();
      if (e.key === 'ArrowUp') goUp();
      else openItem(cursor !== null ? state.items[cursor] : null);
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const next = cursor === null ? 0 : Math.max(0, Math.min(count - 1, cursor + (e.key === 'ArrowDown' ? 1 : -1)));
      if (e.shiftKey) {
        // The range from the row it started on, kept with what is chosen on
        // other pages; with no start on this page, the row reached starts one.
        const shownPaths = new Set(state.items.map(function (i) { return i.path; }));
        const elsewhere = Array.from(selected).filter(function (p) { return !shownPaths.has(p); });
        if (anchor === null) anchor = next;
        chooseSpan(elsewhere, anchor, next);
      } else {
        clearPicked();
        setPicked(next, true);
        anchor = next;
      }
      cursor = next;
      const tr = rowAt(next);
      if (tr && typeof tr.scrollIntoView === 'function') tr.scrollIntoView({ block: 'nearest' });
      renderTrashControls();
    }
  }

  // The icon for an entry's kind, coloured by what it holds.
  function kindIcon(item) {
    if (item.kind === 'folder') return 'fa-solid fa-folder sf-kind-folder';
    if (item.kind === 'link') return 'fa-solid fa-link sf-kind-other';
    if (item.kind !== 'file') return 'fa-solid fa-question sf-kind-other';
    switch (item.preview) {
      case 'image': return 'fa-regular fa-file-image sf-kind-media';
      case 'audio': return 'fa-regular fa-file-audio sf-kind-media';
      case 'video': return 'fa-regular fa-file-video sf-kind-media';
      case 'pdf': return 'fa-regular fa-file-pdf sf-kind-pdf';
      case 'text': return 'fa-regular fa-file-lines sf-kind-other';
      default: return 'fa-regular fa-file sf-kind-other';
    }
  }

  function row(item) {
    const tr = document.createElement('tr');
    tr.dataset.path = item.path;

    if (canTrash(item)) tr.style.cursor = 'pointer';
    tr.title = item.kind === 'folder' || item.preview ? t('openHint', 'Double-click to open') : '';
    if (selected.has(item.path)) tr.classList.add('sf-selected');
    tr.setAttribute('aria-selected', selected.has(item.path) ? 'true' : 'false');

    const nameCell = el('td');
    nameCell.appendChild(icon(kindIcon(item) + ' me-2'));
    if (item.kind === 'folder') {
      // The name opens the folder; the rest of the row chooses it.
      const link = el('a', { className: 'sf-folder-link', text: item.name, title: t('openFolder', 'Open the folder') });
      link.href = '#';
      link.addEventListener('click', function (e) { e.preventDefault(); load(item.path); });
      nameCell.appendChild(link);
    } else {
      nameCell.appendChild(el('span', { text: item.name }));
    }
    if (item.kind === 'link') nameCell.appendChild(el('span', { className: 'ms-2 small text-secondary', text: t('linkNotFollowed', '(link, not followed)') }));
    tr.appendChild(nameCell);

    const what = el('td', { className: 'small' }, [el('span', { text: whatItIs(item) })]);
    if (item.protected_reason) {
      what.appendChild(el('div', { className: 'small text-secondary' }, [icon('fa-solid fa-lock me-1'), el('span', { text: protectedText(item.protected_reason) })]));
    }
    if (item.busy_reason) {
      what.appendChild(el('span', { className: 'badge bg-info text-dark ms-1', text: t('inUse', 'in use') }));
    }
    tr.appendChild(what);

    tr.appendChild(el('td', { className: 'small text-nowrap text-end', text: sizeText(item) }));
    tr.appendChild(el('td', { className: 'small text-nowrap', text: item.modified_at ? new Date(item.modified_at).toLocaleString() : '' }));

    const actions = el('td', { className: 'text-end text-nowrap' });
    if ((item.kind === 'file' || item.kind === 'folder') && state.chatRoot) {
      const copyName = t('copyPathOf', 'Copy the path of {name} to use in a chat').replace('{name}', item.name);
      const copy = el('button', { className: 'btn btn-sm btn-secondary me-1', type: 'button', title: copyName }, [icon('fa-regular fa-copy')]);
      copy.setAttribute('aria-label', copyName);
      copy.dataset.action = 'copy';
      copy.addEventListener('click', function () { copyPath(item, copy); });
      actions.appendChild(copy);
    }
    if (canReveal(item)) {
      const revealName = t('revealOf', 'Show {name} in the file manager').replace('{name}', item.name);
      const btn = el('button', { className: 'btn btn-sm btn-secondary', type: 'button', title: revealName }, [icon('fa-regular fa-folder-open')]);
      btn.setAttribute('aria-label', revealName);
      btn.dataset.action = 'reveal';
      btn.addEventListener('click', function () { reveal(item); });
      actions.appendChild(btn);
    }
    tr.appendChild(actions);
    return tr;
  }

  function render() {
    const body = $id('shared-folder-tbody');
    if (!body) return;
    // A button in a row that had the focus gets it back in the new rows
    // (the list is drawn anew when sizes come in).
    const focused = document.activeElement;
    const keep = focused && body.contains(focused) && focused.dataset && focused.dataset.action && focused.closest('tr')
      ? { path: focused.closest('tr').dataset.path, action: focused.dataset.action } : null;
    body.replaceChildren();
    state.items.forEach(function (item) { body.appendChild(row(item)); });
    if (keep) {
      const again = Array.prototype.find.call(body.children, function (tr) { return tr.dataset.path === keep.path; });
      const target = again && again.querySelector('[data-action="' + keep.action + '"]');
      if (target) target.focus({ preventScroll: true });
      else body.focus({ preventScroll: true });
    }

    const up = $id('shared-folder-up');
    if (up) up.style.display = state.path ? '' : 'none';

    const crumbs = $id('shared-folder-path');
    if (crumbs) {
      crumbs.replaceChildren();
      const top = el('a', { text: t('top', 'Shared folder') });
      top.href = '#';
      top.addEventListener('click', function (e) { e.preventDefault(); load(''); });
      crumbs.appendChild(top);
      let soFar = [];
      state.path.split('/').filter(Boolean).forEach(function (part) {
        soFar = soFar.concat(part);
        const target = soFar.join('/');
        crumbs.appendChild(el('span', { className: 'mx-1 text-secondary', text: '/' }));
        const link = el('a', { text: part });
        link.href = '#';
        link.addEventListener('click', function (e) { e.preventDefault(); load(target); });
        crumbs.appendChild(link);
      });
    }

    const info = $id('shared-folder-info');
    if (info) {
      let text = t('count', 'Items') + ': ' + (state.matched !== state.total ? state.matched + ' / ' + state.total : state.total);
      if (state.truncated) text += ' — ' + t('truncated', 'Only the first items read are shown (the folder holds more).');
      if (!state.rootId && state.rootIdProblem) text += ' — ' + t('noFolderId', 'Items cannot be shown in the file manager: this shared folder could not be identified');
      info.textContent = text;
    }
    renderPager();
    renderTrashControls();
  }

  function pageCount() {
    return Math.max(1, Math.ceil((state.matched || 0) / (state.perPage || view.perPage)));
  }

  // The pagers above and below the list show the same page.
  function renderPager() {
    const pages = pageCount();
    const page = Math.min(state.page || 1, pages);
    const per = state.perPage || view.perPage;
    const first = state.matched ? (page - 1) * per + 1 : 0;
    const last = Math.min(page * per, state.matched || 0);
    const text = t('pageOf', 'Page {page} of {pages} ({first}–{last} of {count})')
      .replace('{page}', String(page)).replace('{pages}', String(pages))
      .replace('{first}', String(first)).replace('{last}', String(last)).replace('{count}', String(state.matched || 0));
    const shown = state.matched > PAGE_SIZES[0] || pages > 1;
    document.querySelectorAll('.sf-pager').forEach(function (pager) {
      pager.style.display = shown ? '' : 'none';
      const label = pager.querySelector('.sf-page-label');
      if (label) label.textContent = text;
      const prev = pager.querySelector('.sf-prev');
      if (prev) prev.disabled = page <= 1;
      const next = pager.querySelector('.sf-next');
      if (next) next.disabled = page >= pages;
      const size = pager.querySelector('.sf-per-page');
      if (size) size.value = String(view.perPage);
    });
  }

  function goToPage(page) {
    const target = Math.max(1, Math.min(page, pageCount()));
    if (target !== state.page) load(state.path, { page: target });
  }

  function trashAvailable() {
    return !!(state.rootId && window.electronAPI && typeof window.electronAPI.trashSharedEntries === 'function');
  }

  function renderTrashControls() {
    const available = trashAvailable();
    // The band of actions is there only where entries can be moved to the
    // Trash (the desktop app). Its buttons are disabled, never hidden, when
    // they have nothing to act on, so none of them moves.
    paintCursor();
    const band = $id('shared-folder-actions');
    if (band) band.style.display = available ? '' : 'none';
    const busy = trashing || matchingBusy;
    const choosable = choosableShown();
    const tests = $id('shared-folder-select-tests');
    if (tests) tests.disabled = busy || !state.items.some(function (i) { return i.classification === 'test_file' && canTrash(i); });
    const all = $id('shared-folder-select-all');
    if (all) {
      const every = choosable.length > 0 && choosable.every(function (i) { return selected.has(i.path); });
      all.disabled = busy || choosable.length === 0;
      all.setAttribute('aria-pressed', every ? 'true' : 'false');
      all.classList.toggle('active', every);
    }
    const matching = $id('shared-folder-select-matching');
    if (matching) {
      matching.disabled = busy || !(state.matched > state.items.length);
      matching.title = t('selectMatchingTitle', 'Every item matching the search and filters, on every page ({count})').replace('{count}', String(state.matched || 0));
    }
    const btn = $id('shared-folder-trash');
    if (btn) {
      btn.disabled = selected.size === 0 || trashing;
      const glyph = btn.querySelector('i');
      if (glyph) glyph.className = trashing ? 'fa-solid fa-spinner fa-spin' : 'fa-regular fa-trash-can';
      const name = t('trashSelected', 'Move to Trash') + (selected.size ? ' (' + selected.size + ')' : '');
      btn.title = name;
      btn.setAttribute('aria-label', name);
    }

    const summary = $id('shared-folder-selection');
    if (summary) {
      const chosen = Array.from(selected).map(function (p) { return known.get(p) || { path: p }; });
      let bytes = 0;
      let partial = false;
      chosen.forEach(function (i) {
        if (typeof i.bytes === 'number') bytes += i.bytes;
        if (typeof i.bytes !== 'number' || (i.kind === 'folder' && i.size_status !== 'complete')) partial = true;
      });
      summary.style.visibility = chosen.length ? 'visible' : 'hidden';
      const clear = $id('shared-folder-clear-selection');
      if (clear) clear.style.visibility = chosen.length ? 'visible' : 'hidden';
      summary.textContent = t('selectionSummary', 'Selected: {count}, {size} in all')
        .replace('{count}', String(chosen.length)).replace('{size}', (partial ? '≥ ' : '') + formatBytes(bytes));
    }
  }

  // Every entry that matches the search and filters and may go, on every
  // page (asked of the server; the desktop app asks again before moving).
  async function selectMatching() {
    if (matchingBusy) return;
    const mine = generation;
    const choice = choiceGeneration;
    const params = new URLSearchParams(query(state.path, 1).split('?')[1]);
    params.delete('page');
    params.delete('sort');
    try {
      matchingBusy = true;
      renderTrashControls();
      const data = await getJson('/api/shared_folder/matching?' + params.toString());
      if (mine !== generation || choice !== choiceGeneration) return;
      const files = filesOnly();
      data.items.forEach(function (i) {
        if (files && i.kind === 'folder') return;
        known.set(i.path, i);
        selected.add(i.path);
      });
      if (data.truncated) showError(t('truncated', 'Only the first items read are shown (the folder holds more).'));
      render();
    } catch (e) {
      if (mine !== generation || (e && e.name === 'AbortError')) return;
      showError(t('loadFailed', 'The shared folder could not be read') + ': ' + e.message);
    } finally {
      matchingBusy = false;
      renderTrashControls();
    }
  }

  // The search, a filter or the age changed: what was chosen may no longer
  // be shown, so nothing stays chosen.
  function clearChoice() {
    choiceGeneration += 1;
    selected = new Set();
    anchor = null;
    cursor = null;
  }

  // Every entry shown that may go is chosen, or none when all already are.
  // "Leave out folders": choosing all (shown, every page, Cmd/Ctrl+A)
  // takes files only. A folder can still be chosen by itself.
  function filesOnly() {
    const box = $id('shared-folder-files-only');
    return !!(box && box.checked);
  }

  function choosableShown() {
    const files = filesOnly();
    return state.items.filter(function (i) { return canTrash(i) && !(files && i.kind === 'folder'); });
  }

  // Cmd/Ctrl+A anywhere in the panel chooses every entry shown (files only
  // with "Leave out folders"), as in a file manager, instead of selecting
  // the text of the page; in a field it selects the field's text as usual.
  // In the desktop app the Edit menu's "Select All" has the same keys and
  // runs as well, selecting the text of the page just after; that text
  // selection is taken back for a moment after the keys were handled here.
  let dropTextSelectionUntil = 0;

  function dropTextSelection() {
    const sel = typeof window.getSelection === 'function' ? window.getSelection() : null;
    if (sel && sel.rangeCount) sel.removeAllRanges();
  }

  function onPanelKey(e) {
    if (!(e.metaKey || e.ctrlKey) || e.altKey || e.shiftKey || (e.key !== 'a' && e.key !== 'A')) return;
    if (previewing || trashing || editable(e.target)) return;
    e.preventDefault();
    const files = filesOnly();
    state.items.forEach(function (i, n) { if (!(files && i.kind === 'folder')) setPicked(n, true); });
    renderTrashControls();
    dropTextSelectionUntil = Date.now() + 500;
    dropTextSelection();
    setTimeout(dropTextSelection, 0);
  }

  function onSelectionChange() {
    if (Date.now() > dropTextSelectionUntil || editable(document.activeElement)) return;
    dropTextSelection();
  }

  function selectAllShown() {
    choiceGeneration += 1;
    const choosable = choosableShown();
    const every = choosable.length > 0 && choosable.every(function (i) { return selected.has(i.path); });
    choosable.forEach(function (i) { if (every) selected.delete(i.path); else selected.add(i.path); });
    render();
  }

  // The path a chat's tools use for the entry (the container's view of the
  // shared folder, given by the server), as it is: no quoting, no encoding.
  function chatPath(item) {
    return state.chatRoot ? state.chatRoot + '/' + item.path : null;
  }

  async function copyPath(item, button) {
    const text = chatPath(item);
    if (!text) return;
    let ok = false;
    try {
      if (window.electronAPI && typeof window.electronAPI.writeClipboard === 'function') {
        ok = (await window.electronAPI.writeClipboard(text)) === true;
      } else if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        await navigator.clipboard.writeText(text);
        ok = true;
      }
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      showError(t('copyFailed', 'The path could not be copied') + ': ' + text);
      return;
    }
    clearWarning();
    if (button) {
      // A brief check mark, in the button's own colour (no green flash).
      const before = button.title;
      const glyph = button.querySelector('i');
      button.title = t('copied', 'Copied') + ': ' + text;
      if (glyph) glyph.className = 'fa-solid fa-check';
      setTimeout(function () { if (glyph) glyph.className = 'fa-regular fa-copy'; button.title = before; }, 1500);
    }
  }

  // The preview shown above the list. Each one opened (or a close) starts a
  // new generation, so a slow answer for an earlier file is not shown.
  let previewGeneration = 0;
  let previewController = null;

  function fileUrl(item) {
    return '/api/shared_folder/file?' + new URLSearchParams({ path: item.path }).toString();
  }

  // While the preview is shown the rest of the panel takes no focus and no
  // keys (inert); the focus goes back where it was when it closes.
  let previewReturnFocus = null;

  function setBackgroundInert(on, boxId) {
    const box = $id(boxId || 'shared-folder-preview');
    const content = box && box.parentNode;
    if (!content) return;
    Array.prototype.forEach.call(content.children, function (child) {
      if (child === box) return;
      if (on) child.setAttribute('inert', ''); else child.removeAttribute('inert');
    });
  }

  // opts.stepping: another file follows at once, so the overlay, the keys
  // and the focus stay as they are.
  function closePreview(opts) {
    const stepping = !!(opts && opts.stepping);
    previewGeneration += 1;
    if (previewController) previewController.abort();
    previewController = null;
    const box = $id('shared-folder-preview');
    const body = $id('shared-folder-preview-body');
    if (body) {
      body.querySelectorAll('audio, video').forEach(function (m) {
        try { m.pause(); } catch (_) { /* not playing */ }
        m.removeAttribute('src');
        try { m.load(); } catch (_) { /* nothing loaded */ }
      });
      body.replaceChildren();
    }
    if (stepping) return;
    if (box) box.style.display = 'none';
    if (previewing) {
      previewing = null;
      document.removeEventListener('keydown', onPreviewKey, true);
      setBackgroundInert(false);
      const back = previewReturnFocus && previewReturnFocus.isConnected ? previewReturnFocus : $id('shared-folder-tbody');
      previewReturnFocus = null;
      if (back && typeof back.focus === 'function') back.focus({ preventScroll: true });
    }
  }

  // The preview is laid over the panel, so it is in view wherever the file
  // is in the list. The arrows go to the files before and after it on the
  // page that can be previewed; Esc (or Space, as in Quick Look) closes it
  // without closing the panel.
  let previewing = null;

  function previewable() {
    return state.items.filter(function (i) { return !!i.preview; });
  }

  function stepPreview(by) {
    if (!previewing) return;
    const list = previewable();
    const at = list.findIndex(function (i) { return i.path === previewing.path; });
    const next = list[at + by];
    if (!next) return;
    const index = state.items.indexOf(next);
    // The row follows, as when the arrow keys move in the list.
    clearPicked();
    setPicked(index, true);
    anchor = index;
    cursor = index;
    const tr = rowAt(index);
    if (tr && typeof tr.scrollIntoView === 'function') tr.scrollIntoView({ block: 'nearest' });
    renderTrashControls();
    openPreview(next);
  }

  function editable(target) {
    return !!(target && (/^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName) || target.isContentEditable));
  }

  function onPreviewKey(e) {
    if (!previewing) return;
    if (e.key === 'Escape' || e.key === ' ') {
      if (e.key === ' ' && (editable(e.target) || (e.target && e.target.closest && e.target.closest('button, audio, video')))) return;
      e.preventDefault();
      e.stopPropagation(); // the panel stays open
      closePreview();
    } else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
      if (editable(e.target) || (e.target && e.target.closest && e.target.closest('audio, video'))) return; // their own keys
      e.preventDefault();
      e.stopPropagation();
      stepPreview(e.key === 'ArrowLeft' ? -1 : 1);
    }
  }

  function renderPreviewNav() {
    const list = previewable();
    const at = previewing ? list.findIndex(function (i) { return i.path === previewing.path; }) : -1;
    const prev = $id('shared-folder-preview-prev');
    if (prev) prev.disabled = at <= 0;
    const next = $id('shared-folder-preview-next');
    if (next) next.disabled = at < 0 || at >= list.length - 1;
    const count = $id('shared-folder-preview-count');
    if (count) count.textContent = at >= 0 ? (at + 1) + ' / ' + list.length : '';
  }

  async function openPreview(item) {
    const stepping = !!previewing;
    closePreview({ stepping: stepping });
    const mine = previewGeneration;
    const box = $id('shared-folder-preview');
    const body = $id('shared-folder-preview-body');
    const title = $id('shared-folder-preview-name');
    if (!box || !body) return;
    if (title) title.textContent = item.path;
    box.style.display = '';
    previewing = item;
    if (!stepping) {
      previewReturnFocus = document.activeElement;
      document.addEventListener('keydown', onPreviewKey, true);
      setBackgroundInert(true);
      const close = $id('shared-folder-preview-close');
      if (close && typeof close.focus === 'function') close.focus({ preventScroll: true });
    }
    renderPreviewNav();
    const fail = function (message) {
      if (mine !== previewGeneration) return;
      body.replaceChildren(el('div', { className: 'small text-secondary', text: t('previewFailed', 'The file cannot be shown') + (message ? ': ' + message : '') }));
    };
    if (item.preview === 'text') {
      previewController = (typeof AbortController !== 'undefined') ? new AbortController() : null;
      try {
        const res = await fetch('/api/shared_folder/text?' + new URLSearchParams({ path: item.path }).toString(),
          { signal: previewController ? previewController.signal : undefined });
        const data = await res.json();
        if (mine !== previewGeneration) return;
        if (!res.ok || !data.success) { fail(data && data.error); return; }
        const pre = el('pre', { className: 'small mb-0 p-2 border rounded', text: data.text });
        pre.style.maxHeight = '68vh';
        pre.style.overflow = 'auto';
        pre.style.whiteSpace = 'pre-wrap';
        pre.style.wordBreak = 'break-word';
        body.replaceChildren(pre);
        if (data.truncated) {
          body.appendChild(el('div', { className: 'small text-secondary mt-1', text: t('previewTruncated', 'Only the beginning is shown') + ' (' + formatBytes(data.shown_bytes) + ' / ' + formatBytes(data.file_bytes) + ')' }));
        }
      } catch (e) {
        if (e && e.name === 'AbortError') return;
        fail(e && e.message);
      }
      return;
    }
    let node;
    if (item.preview === 'image') {
      node = el('img', { className: 'img-fluid border rounded' });
      node.style.maxHeight = '68vh';
      node.alt = item.name;
    } else if (item.preview === 'audio' || item.preview === 'video') {
      node = el(item.preview);
      node.controls = true;
      node.preload = 'metadata';
      if (item.preview === 'video') { node.style.maxWidth = '100%'; node.style.maxHeight = '68vh'; }
      else node.style.width = '100%';
    } else if (item.preview === 'pdf') {
      node = el('iframe', { className: 'border rounded w-100' });
      node.style.height = '70vh';
      node.title = item.name;
    } else {
      fail('');
      return;
    }
    node.addEventListener('error', function () { fail(''); });
    node.src = fileUrl(item);
    body.replaceChildren(node);
  }

  function tabParam(params) {
    const id = (typeof window.getMonadicTabId === 'function') ? window.getMonadicTabId() : null;
    if (id) params.set('tab_id', id);
    return params;
  }

  function query(path, page, perPage) {
    const params = new URLSearchParams({ path: path, page: String(page) });
    if (perPage) params.set('per_page', String(perPage));
    if (view.q) params.set('q', view.q);
    if (view.sort && view.sort !== 'name') params.set('sort', view.sort);
    if (view.cls) params.append('classes[]', view.cls);
    if (view.age) params.set('older_than_days', view.age);
    return '/api/shared_folder?' + tabParam(params).toString();
  }

  function sizesQuery(paths) {
    const params = new URLSearchParams();
    paths.forEach(function (p) { params.append('paths[]', p); });
    return '/api/shared_folder/sizes?' + tabParam(params).toString();
  }

  // The one place for what is going on (loading, nothing to show, errors,
  // what moving to the Trash did). kind: 'info' or 'warn'; no content clears it.
  function setStatus(kind, content) {
    const box = $id('shared-folder-status');
    if (!box) return;
    const parts = (Array.isArray(content) ? content : [content]).filter(function (c) { return c !== null && c !== undefined && c !== ''; })
      .map(function (c) { return typeof c === 'string' ? document.createTextNode(c) : c; });
    box.replaceChildren.apply(box, parts);
    box.classList.toggle('sf-status-warn', kind === 'warn');
    box.style.display = parts.length ? '' : 'none';
  }

  function showError(message) {
    setStatus('warn', message || null);
  }

  // An earlier error goes once the same kind of action works.
  function clearWarning() {
    const box = $id('shared-folder-status');
    if (box && box.classList.contains('sf-status-warn')) setStatus('info', null);
  }

  // Shown only when loading takes a moment, so a quick answer does not flash.
  let loadingTimer = null;

  function loadingStarted() {
    clearTimeout(loadingTimer);
    const table = $id('shared-folder-tbody');
    if (table) table.setAttribute('aria-busy', 'true');
    loadingTimer = setTimeout(function () {
      setStatus('info', [icon('fa-solid fa-spinner fa-spin me-1'), t('loading', 'Loading…')]);
    }, 250);
  }

  function loadingEnded() {
    clearTimeout(loadingTimer);
    loadingTimer = null;
    const table = $id('shared-folder-tbody');
    if (table) table.removeAttribute('aria-busy');
  }

  // Nothing listed: an empty folder, or nothing matching the search and filters.
  function showListState() {
    if (state.items.length) { setStatus('info', null); return; }
    if (state.total > 0) setStatus('info', t('noMatch', 'No items match the search and filters'));
    else setStatus('info', t('emptyFolder', 'This folder is empty'));
  }

  async function getJson(url) {
    const resp = await fetch(url, controller ? { signal: controller.signal } : undefined);
    const data = await resp.json();
    if (!resp.ok || !data.success) throw new Error(data.error || ('HTTP ' + resp.status));
    return data;
  }

  // Only name order is the same from one request to the next; in another
  // order (or with a kind chosen) a size or a date can move an entry across
  // pages, so the list is asked for again from the top instead.
  // One page of a folder (the first unless opts.page). opts.keep: the same
  // folder again, keeping the size counts asked so far.
  async function load(path, opts) {
    opts = opts || {};
    // A search still waiting for the pause goes with this request.
    if (searchTimer) {
      clearTimeout(searchTimer);
      searchTimer = null;
      const box = $id('shared-folder-search');
      const q = box ? (box.value || '').trim() : view.q;
      if (q !== view.q) { view.q = q; clearChoice(); }
    }
    const mine = nextGeneration();
    if (path !== state.path) closePreview(); // leaving the folder: stop what plays now
    if (!opts.keep) asked = new Map();
    resortDue = false;
    loadingStarted();
    try {
      const data = await getJson(query(path, opts.page || 1, view.perPage));
      if (mine !== generation) return;
      if (data.path !== state.path) { clearChoice(); known = new Map(); closePreview(); }
      // The keyboard's place and the start of a Shift range are rows; on
      // another page or order they are found again by path, or dropped.
      const anchorPath = anchor !== null && state.items[anchor] ? state.items[anchor].path : null;
      const cursorPath = cursor !== null && state.items[cursor] ? state.items[cursor].path : null;
      drag = null;
      // A page that is gone now (entries removed elsewhere): the last one.
      if (data.items.length === 0 && data.matched > 0 && data.page > 1) {
        const last = Math.max(1, Math.ceil(data.matched / (data.per_page || view.perPage)));
        if (last < data.page) { load(path, { page: last, keep: opts.keep }); return; }
      }
      state = { path: data.path, page: data.page, perPage: data.per_page, items: data.items, total: data.total,
                matched: data.matched === undefined ? data.total : data.matched, truncated: !!data.truncated,
                rootId: data.root_id || null, rootIdProblem: data.root_id_problem || null,
                chatRoot: data.chat_root || null };
      if (opts.keep) {
        // A folder already asked about as often as it may be stays shown as
        // not counted yet, as before the list was asked for again.
        state.items = state.items.map(function (i) {
          return i.size_status === 'pending' && (asked.get(i.path) || 0) >= SIZE_POLLS
            ? Object.assign({}, i, { size_status: 'not_counted' }) : i;
        });
      }
      state.items.forEach(function (i) { known.set(i.path, i); });
      const at = function (p) { const n = p === null ? -1 : state.items.findIndex(function (i) { return i.path === p; }); return n < 0 ? null : n; };
      anchor = at(anchorPath);
      cursor = at(cursorPath);
      loadingEnded();
      render();
      showListState();
      scheduleSizes(mine);
    } catch (e) {
      if (mine !== generation || (e && e.name === 'AbortError')) return;
      loadingEnded();
      showError(t('loadFailed', 'The shared folder could not be read') + ': ' + e.message);
    }
  }

  // Folder sizes are counted on the server in the background; ask again,
  // for the sizes only, while some are still being counted. Each folder is
  // asked about at most SIZE_POLLS times (a page added later gets its own
  // turns), and one that is still counting after that is shown as not
  // counted yet, to be refreshed.
  function scheduleSizes(mine) {
    if (!isOpen || mine !== generation) return;
    const waiting = state.items
      .filter(function (i) { return i.size_status === 'pending' && (asked.get(i.path) || 0) < SIZE_POLLS; })
      .sort(function (a, b) { return (asked.get(a.path) || 0) - (asked.get(b.path) || 0); })
      .slice(0, SIZES_PER_ASK)
      .map(function (i) { return i.path; });
    if (waiting.length === 0) {
      // Every count is in: in size order, the list is asked for again once
      // so that the order shown is the order of the sizes.
      if (resortDue && view.sort === 'size') {
        resortDue = false;
        load(state.path, { page: state.page, keep: true });
      }
      return;
    }
    clearTimeout(timer);
    timer = setTimeout(async function () {
      waiting.forEach(function (p) { asked.set(p, (asked.get(p) || 0) + 1); });
      try {
        const data = await getJson(sizesQuery(waiting));
        if (mine !== generation) return;
        state.items = state.items.map(function (i) {
          const size = data.sizes[i.path];
          if (size && size.size_status !== i.size_status) resortDue = true;
          const updated = size ? Object.assign({}, i, size) : i;
          known.set(updated.path, updated);
          return updated;
        });
      } catch (_) {
        if (mine !== generation) return;
      }
      state.items = state.items.map(function (i) {
        return i.size_status === 'pending' && (asked.get(i.path) || 0) >= SIZE_POLLS
          ? Object.assign({}, i, { size_status: 'not_counted' }) : i;
      });
      render();
      scheduleSizes(mine);
    }, SIZE_POLL_MS);
  }

  function selectTests() {
    choiceGeneration += 1;
    state.items.forEach(function (i) { if (i.classification === 'test_file' && canTrash(i)) selected.add(i.path); });
    render();
  }

  // Moves the chosen entries to the system's trash, through the desktop app,
  // which asks first in a dialog of its own and then asks the server again
  // for each one. One run at a time; the run keeps the folder it started
  // in, and the list is asked for again only if that folder is still shown.
  // What did not move stays chosen, to try again.
  let trashing = false;

  async function trashSelected() {
    if (trashing) return;
    closePreview(); // what it shows may be moved
    const paths = Array.from(selected);
    if (paths.length === 0 || !trashAvailable()) return;
    const rootId = state.rootId;
    const startPath = state.path;
    const wasOpen = isOpen;
    const moved = [];
    const failed = [];
    let notTried = 0;
    let cancelled = false;
    trashing = true;
    renderTrashControls();
    showBusy(true);
    try {
      for (let i = 0; i < paths.length; i += TRASH_PER_REQUEST) {
        const chunk = paths.slice(i, i + TRASH_PER_REQUEST);
        try {
          const result = await window.electronAPI.trashSharedEntries(rootId, chunk);
          if (result && result.cancelled) { cancelled = true; break; } // the person said no in the dialog
          if (result && Array.isArray(result.results)) {
            result.results.forEach(function (r) {
              if (r.ok) moved.push(r.path);
              else if (r.not_tried) notTried += 1;
              else failed.push(r.path + ' (' + (r.error || '') + ')');
            });
          } else {
            chunk.forEach(function (p) { failed.push(p + ' (' + ((result && result.error) || '') + ')'); });
          }
        } catch (e) {
          chunk.forEach(function (p) { failed.push(p + ' (' + e.message + ')'); });
        }
      }
    } finally {
      trashing = false;
      showBusy(false);
    }
    // Said no before anything was moved: the list and the choice stay as they are.
    if (cancelled && moved.length === 0 && failed.length === 0) { renderTrashControls(); return; }
    choiceGeneration += 1;
    moved.forEach(function (p) { selected.delete(p); known.delete(p); });
    // The list again only while the panel shows the folder the run started in.
    if (isOpen === wasOpen && state.path === startPath && state.rootId === rootId) {
      await load(state.path, { page: state.page });
    } else {
      renderTrashControls();
    }
    showTrashResult(moved.length, failed, notTried);
  }

  // While entries are moved (the desktop app's dialog included) the panel
  // shows a spinner over everything and takes no other action, and it
  // cannot be closed; the focus goes back to the list afterwards.
  function showBusy(on) {
    const box = $id('shared-folder-busy');
    if (!box) return;
    box.style.display = on ? '' : 'none';
    setBackgroundInert(on, 'shared-folder-busy');
    if (on) {
      if (document.activeElement && typeof document.activeElement.blur === 'function') document.activeElement.blur();
    } else {
      const list = $id('shared-folder-tbody');
      if (list && typeof list.focus === 'function') list.focus({ preventScroll: true });
    }
  }

  // The count moved, and every entry that was not, in a list that opens.
  function showTrashResult(movedCount, failed, notTried) {
    if (!failed.length && !notTried) {
      setStatus('info', [icon('fa-solid fa-check me-1'), t('trashDone', 'Moved to the Trash') + ': ' + movedCount]);
      return;
    }
    const summary = t('trashSummary', 'Moved: {moved}, not moved: {failed}, not tried: {notTried}')
      .replace('{moved}', String(movedCount)).replace('{failed}', String(failed.length)).replace('{notTried}', String(notTried));
    const parts = [el('div', { text: summary })];
    if (notTried) parts.push(el('div', { text: t('trashStopped', 'The rest was not tried: the server did not answer. What was not moved stays selected.') }));
    if (failed.length) {
      const list = el('ul', { className: 'mb-0 small' }, failed.map(function (f) { return el('li', { text: f }); }));
      list.style.maxHeight = '12rem';
      list.style.overflow = 'auto';
      parts.push(el('details', {}, [el('summary', { text: t('trashFailed', 'Not moved to the Trash') + ' (' + failed.length + ')' }), list]));
    }
    setStatus('warn', parts);
  }

  async function reveal(item) {
    try {
      const result = await window.electronAPI.revealSharedEntry(state.rootId, item.path);
      if (!result || !result.ok) showError(t('revealFailed', 'Could not show it') + ': ' + ((result && result.error) || ''));
    } catch (e) {
      showError(t('revealFailed', 'Could not show it') + ': ' + e.message);
    }
  }

  function open() {
    const modalEl = $id('sharedFolderModal');
    if (!modalEl || !window.bootstrap) return;
    isOpen = true;
    bootstrap.Modal.getOrCreateInstance(modalEl).show();
    load('');
  }

  let searchTimer = null;

  function init() {
    $on($id('shared-folder-browse'), 'click', open);
    // The box is read when the pause is over, not when a key is typed: with
    // an input method the last event can carry text that is no longer there.
    const search = $id('shared-folder-search');
    const searchSoon = function (e) {
      clearTimeout(searchTimer);
      searchTimer = null;
      if (e && e.isComposing) return;
      searchTimer = setTimeout(function () {
        searchTimer = null;
        view.q = (search.value || '').trim();
        clearChoice();
        load(state.path);
      }, 300);
    };
    $on(search, 'input', searchSoon);
    $on(search, 'compositionend', searchSoon);
    $on(search, 'search', searchSoon); // Esc in the box empties it without an input event
    $on($id('shared-folder-sort'), 'change', function (e) { view.sort = e.target.value; load(state.path); });
    $on($id('shared-folder-filter'), 'change', function (e) { view.cls = e.target.value; clearChoice(); load(state.path); });
    $on($id('shared-folder-age'), 'change', function (e) { view.age = e.target.value; clearChoice(); load(state.path); });
    $on($id('shared-folder-select-matching'), 'click', selectMatching);
    $on($id('shared-folder-clear-selection'), 'click', clearSelection);
    $on($id('shared-folder-up'), 'click', goUp);
    document.querySelectorAll('.sf-pager').forEach(function (pager) {
      $on(pager.querySelector('.sf-prev'), 'click', function () { goToPage((state.page || 1) - 1); });
      $on(pager.querySelector('.sf-next'), 'click', function () { goToPage((state.page || 1) + 1); });
    });
    $on(document.querySelector('.sf-per-page'), 'change', function (e) {
      const n = Number(e.target.value);
      if (PAGE_SIZES.indexOf(n) < 0) return;
      view.perPage = n;
      try { window.localStorage.setItem(PAGE_SIZE_KEY, String(n)); } catch (_) { /* no storage here */ }
      load(state.path);
    });
    $on($id('shared-folder-select-all'), 'click', selectAllShown);
    const filesBox = $id('shared-folder-files-only');
    if (filesBox) {
      try { filesBox.checked = window.localStorage.getItem(FILES_ONLY_KEY) === 'true'; } catch (_) { /* no storage here */ }
      $on(filesBox, 'change', function () {
        try { window.localStorage.setItem(FILES_ONLY_KEY, String(filesBox.checked)); } catch (_) { /* no storage here */ }
        renderTrashControls();
      });
    }
    $on($id('sharedFolderModal'), 'keydown', onPanelKey);
    document.addEventListener('selectionchange', onSelectionChange);
    // Not closed while entries are being moved.
    $on($id('sharedFolderModal'), 'hide.bs.modal', function (e) { if (trashing) e.preventDefault(); });
    $on($id('shared-folder-preview-close'), 'click', closePreview);
    $on($id('shared-folder-preview-prev'), 'click', function () { stepPreview(-1); });
    $on($id('shared-folder-preview-next'), 'click', function () { stepPreview(1); });
    // A click on the dimmed panel around the preview closes it.
    $on($id('shared-folder-preview'), 'mousedown', function (e) { if (e.target === e.currentTarget) closePreview(); });
    $on($id('shared-folder-select-tests'), 'click', selectTests);
    $on($id('shared-folder-trash'), 'click', function () { if (selected.size) trashSelected(); });
    $on($id('shared-folder-refresh'), 'click', function () { load(state.path, { page: state.page, keep: true }); });
    $on($id('shared-folder-tbody'), 'mousedown', onRowDown);
    $on($id('shared-folder-tbody'), 'mousemove', onRowMove);
    $on($id('shared-folder-tbody'), 'dblclick', onRowDouble);
    $on($id('shared-folder-tbody'), 'keydown', onRowKey);
    document.addEventListener('mouseup', function () { drag = null; });
    $on($id('sharedFolderModal'), 'hidden.bs.modal', function () {
      isOpen = false;
      clearTimeout(searchTimer);
      searchTimer = null;
      nextGeneration(); // drops what is still on its way
      closePreview();
    });
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { formatBytes: formatBytes, sizeText: sizeText, whatItIs: whatItIs, query: query, sizesQuery: sizesQuery,
      open: open, load: load, goToPage: goToPage, selectMatching: selectMatching, selectTests: selectTests, trashSelected: trashSelected,
      openPreview: openPreview, closePreview: closePreview, selectAllShown: selectAllShown, clearSelection: clearSelection, goUp: goUp, chatPath: chatPath, copyPath: copyPath,
      _state: function () { return state; }, _selected: function () { return selected; },
      _view: function (v) { if (v) view = Object.assign(view, v); return view; } };
  }
  if (typeof window !== 'undefined') window.SharedFolderPanel = { open: open, load: load };
})();
