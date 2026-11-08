// The Files tab of the side column: what the shared folder holds, one
// folder at a time, searched, sorted and filtered on the server. Each row
// says when the entry was last modified, its size, what it is, and whether
// it must be kept or is in use. A file the work screen shows opens there;
// a folder opens in the list. Entries can be selected (the box before each
// row, Shift and Cmd/Ctrl as in a file manager) to copy their paths for a
// chat or, in the desktop app, to move to the system's trash; the menu of
// a row (⋯) does the same for that row. Names come from the folder, so they
// are always set as text.
(function () {
  'use strict';

  const PER_PAGE = 50;          // entries asked for at a time ("Show more")
  const READ_AGAIN_PAGES = 10;  // pages read again at most (500 entries)
  const SIZE_POLLS = 15;        // times to ask again for one folder's size
  const SIZES_PER_ASK = 200;    // folders per request (the server's limit)
  const SIZE_POLL_MS = 2000;
  const SEARCH_DELAY = 300;
  const SORTS = ['name', 'modified', 'size'];
  const SORT_KEY = 'monadic-shared-files-sort';
  const FILES_ONLY_KEY = 'monadic-shared-folder-files-only';
  const TRASH_PER_REQUEST = 20000; // the desktop app's limit (MAX_TRASH)
  // The kinds the work screen shows (FileItem::KINDS on the server).
  const WORKBENCH_KINDS = ['image', 'text', 'audio', 'video', 'pdf'];

  // pages: how many PER_PAGE pages the list holds (the next is pages + 1).
  // shown: the search, filters and order the list holds was read with
  // (more of it is added only while they are the same).
  let state = { path: '', pages: 0, items: [], total: 0, matched: 0, truncated: false, rootId: null, rootIdProblem: null,
                chatRoot: null, shown: null };
  // The entries shown, by path.
  let shownByPath = new Map();
  // What the list is narrowed and ordered by (kept while moving between folders).
  let view = { q: '', sort: savedSort(), cls: '', age: '' };

  function savedSort() {
    try {
      const value = window.localStorage && window.localStorage.getItem(SORT_KEY);
      return SORTS.indexOf(value) >= 0 ? value : 'name';
    } catch (_) {
      return 'name';
    }
  }

  // What is known of selected entries that may not be shown (their kind
  // and size, for the total): from the rows seen and from "select all that
  // can be moved".
  let known = new Map();
  // Paths selected, in the folder shown now. movable: those the server said
  // may be moved to the trash ("select all that can be moved"), when they
  // are not shown.
  let selected = new Set();
  let movable = new Set();
  // Bumped whenever the selection is changed by hand, so a slow "select all
  // that can be moved" does not bring back what was cleared after it was asked.
  let choiceGeneration = 0;
  let matchingBusy = false;

  // Each load, refresh or hide starts a new generation; a response or a
  // timer of an older one is dropped, so the list never goes back to a
  // folder it has left, and nothing keeps running while the tab is hidden.
  let generation = 0;
  let controller = null;
  let timer = null;
  // path => times its size was asked for. A Map, so a folder named like an
  // object's own property (constructor, __proto__) counts from 0 too.
  let asked = new Map();
  let visible = false;
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
    public_copy: ['publicCopy', 'Old copy for playback'],
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

  // The kinds of entry the filter narrows to, as on the server.
  const FILTER_KINDS = [
    ['test_file', 'testFile', 'Made by a test run'],
    ['test_candidate', 'testCandidate', 'Possibly left by a test run'],
    ['intermediate_candidate', 'intermediate', 'Possibly a working file'],
    ['generated', 'generated', 'Generated file'],
    ['public_copy', 'publicCopy', 'Copy for playback'],
    ['other', 'other', 'Other']
  ];
  const FILTER_AGES = [['30', 'age30', 'Not modified in 30 days'], ['90', 'age90', 'Not modified in 90 days'],
    ['365', 'age365', 'Not modified in 365 days']];

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

  function trashAvailable() {
    return !!(state.rootId && window.electronAPI && typeof window.electronAPI.trashSharedEntries === 'function');
  }

  function canTrash(item) {
    return !!(item.capabilities && item.capabilities.trash && trashAvailable());
  }

  // Any file or folder can be selected (to copy its path); what may go to
  // the trash is decided per entry.
  function canSelect(item) {
    return !!item && (item.kind === 'file' || item.kind === 'folder');
  }

  // Whether the work screen can show a listed entry (and the page has one).
  function workScreenShows(item) {
    return !!(item && item.kind === 'file' && WORKBENCH_KINDS.indexOf(item.preview) >= 0 && window.Workbench);
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

  // When the entry was last modified, and its size.
  function metaText(item) {
    const parts = [];
    const at = item.modified_at ? new Date(item.modified_at) : null;
    if (at && !Number.isNaN(at.getTime())) {
      parts.push(at.toLocaleString(undefined, { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }));
    }
    const size = sizeText(item);
    if (size) parts.push(size);
    return parts.join(' · ');
  }

  // ---- selecting -------------------------------------------------------
  // The box before a row selects it (Shift: the rows from the last one
  // selected). On the name, a click opens the entry; with Cmd/Ctrl it
  // selects, with Shift it selects a range. The list's keys: ↑ ↓ move,
  // Shift+↑ ↓ extend, Enter opens, Space selects, Cmd/Ctrl+A selects all
  // shown, the Menu key (or Shift+F10) opens the row's menu, Esc clears (a
  // menu open is closed first, by the menu).
  let anchor = null;    // index of the row a range starts from
  let cursor = null;    // index of the row the keyboard is on

  function rowAt(index) {
    const list = $id('sfp-list');
    return list ? list.children[index] || null : null;
  }

  function paintRow(index) {
    const li = rowAt(index);
    const item = state.items[index];
    if (!li || !item) return;
    const on = selected.has(item.path);
    li.classList.toggle('sfp-selected', on);
    const box = li.querySelector('.sfp-check');
    if (box) {
      box.setAttribute('aria-checked', on ? 'true' : 'false');
      const glyph = box.querySelector('i');
      if (glyph) glyph.className = on ? 'fa-solid fa-square-check' : 'fa-regular fa-square';
    }
  }

  // The row the keyboard is on: its name is the one element of the list
  // the Tab key reaches (the first row's while none is), and the arrows
  // move the focus from name to name.
  function paintCursor() {
    const list = $id('sfp-list');
    if (!list) return;
    const at = cursor === null ? 0 : cursor;
    Array.prototype.forEach.call(list.children, function (li, n) {
      const on = n === cursor;
      li.classList.toggle('sfp-cursor', on);
      if (on) li.setAttribute('aria-current', 'true'); else li.removeAttribute('aria-current');
      const name = li.querySelector('.sfp-name');
      if (name) name.tabIndex = n === at ? 0 : -1;
    });
    list.tabIndex = list.children.length ? -1 : 0;
  }

  function focusRow(index) {
    const li = rowAt(index);
    const name = li && li.querySelector('.sfp-name');
    if (name && typeof name.focus === 'function') name.focus({ preventScroll: false });
  }

  // The focus back on the row of path (drawn anew), or on the list.
  function focusPath(p) {
    const n = state.items.findIndex(function (i) { return i.path === p; });
    if (n >= 0) { cursor = n; paintCursor(); focusRow(n); return; }
    const list = $id('sfp-list');
    if (list && typeof list.focus === 'function') list.focus({ preventScroll: true });
  }

  function setPicked(index, value) {
    const item = state.items[index];
    if (!canSelect(item)) return;
    choiceGeneration += 1;
    if (value) selected.add(item.path); else { selected.delete(item.path); movable.delete(item.path); }
    paintRow(index);
  }

  function setRange(from, to, value) {
    for (let i = Math.min(from, to); i <= Math.max(from, to); i += 1) setPicked(i, value);
  }

  function clearPicked() {
    choiceGeneration += 1;
    selected = new Set();
    movable = new Set();
    state.items.forEach(function (_i, n) { paintRow(n); });
  }

  // Click on the box (or Cmd/Ctrl on the name): one row in or out; Shift:
  // the rows from the start of the range.
  function pick(index, shift) {
    const item = state.items[index];
    if (!canSelect(item)) return;
    if (shift && anchor !== null && anchor < state.items.length) {
      setRange(anchor, index, true);
    } else {
      setPicked(index, !selected.has(item.path));
      anchor = index;
    }
    cursor = index;
    paintCursor();
    renderBands();
  }

  function clearSelection() {
    clearPicked();
    anchor = null;
    renderBands();
  }

  // The search, a filter or the order changed: what was selected may no
  // longer be shown, so nothing stays selected.
  function clearChoice() {
    choiceGeneration += 1;
    selected = new Set();
    movable = new Set();
    anchor = null;
    cursor = null;
  }

  // "Skip folders": selecting all (shown, all that can be moved, Cmd/Ctrl+A)
  // takes files only. A folder can still be selected by itself.
  function filesOnly() {
    try { return window.localStorage.getItem(FILES_ONLY_KEY) === 'true'; } catch (_) { return false; }
  }

  function setFilesOnly(on) {
    try { window.localStorage.setItem(FILES_ONLY_KEY, String(!!on)); } catch (_) { /* no storage here */ }
  }

  function selectAllShown() {
    choiceGeneration += 1;
    const files = filesOnly();
    const choosable = state.items.filter(function (i) { return canSelect(i) && !(files && i.kind === 'folder'); });
    const every = choosable.length > 0 && choosable.every(function (i) { return selected.has(i.path); });
    choosable.forEach(function (i) { if (every) selected.delete(i.path); else selected.add(i.path); });
    render();
  }

  function selectTests() {
    choiceGeneration += 1;
    state.items.forEach(function (i) { if (i.classification === 'test_file' && canTrash(i)) selected.add(i.path); });
    render();
  }

  // Every entry that matches the search and filters and may be moved to the
  // trash, shown or not (asked of the server; the desktop app asks again
  // before moving).
  async function selectMatching() {
    if (matchingBusy) return;
    const mine = generation;
    const choice = choiceGeneration;
    const params = new URLSearchParams(query(state.path, 1, PER_PAGE).split('?')[1]);
    params.delete('page');
    params.delete('per_page');
    params.delete('sort');
    try {
      matchingBusy = true;
      renderBands();
      const data = await getJson('/api/shared_folder/matching?' + params.toString());
      if (mine !== generation || choice !== choiceGeneration) return;
      const files = filesOnly();
      data.items.forEach(function (i) {
        if (files && i.kind === 'folder') return;
        known.set(i.path, i);
        selected.add(i.path);
        movable.add(i.path);
      });
      if (data.truncated) showError(t('truncated', 'Only the first items read are shown (the folder holds more).'));
      render();
    } catch (e) {
      if (mine !== generation || (e && e.name === 'AbortError')) return;
      showError(t('loadFailed', 'The shared folder could not be read') + ': ' + e.message);
    } finally {
      matchingBusy = false;
      renderBands();
    }
  }

  // The selected entries that may be moved to the trash: those shown that
  // the server allows, and those it said so of when they were selected all.
  function trashTargets() {
    if (!trashAvailable()) return [];
    return Array.from(selected).filter(function (p) {
      // What the list says now, else what it said when the entry was last
      // listed, else what "select all that can be moved" said.
      const item = shownByPath.get(p) || known.get(p);
      return item && item.capabilities ? canTrash(item) : movable.has(p);
    });
  }

  // ---- opening ---------------------------------------------------------

  function openItem(item, index) {
    if (!item) return;
    if (item.kind === 'folder') {
      load(item.path);
    } else if (workScreenShows(item)) {
      window.Workbench.openFile(item.path);
    } else if (index !== undefined) {
      pick(index, false);
    }
  }

  function goUp() {
    if (state.path) load(state.path.split('/').slice(0, -1).join('/'));
  }

  // The path a chat's tools use for the entry (the container's view of the
  // shared folder, given by the server), as it is: no quoting, no encoding.
  function chatPath(item) {
    return state.chatRoot ? state.chatRoot + '/' + item.path : null;
  }

  // Copies the paths (one per line); says so only once the clipboard has them.
  async function copyPaths(paths, button) {
    const text = paths.map(function (p) { return chatPath({ path: p }); }).filter(Boolean).join('\n');
    if (!text) return false;
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
      return false;
    }
    clearWarning();
    setStatus('info', [icon('fa-solid fa-check me-1'),
      (paths.length > 1 ? t('copiedCount', 'Copied {count} paths') : t('copied', 'Copied')).replace('{count}', String(paths.length))]);
    if (button && button.isConnected) {
      const glyph = button.querySelector('i');
      if (glyph) glyph.className = 'fa-solid fa-check';
      setTimeout(function () { if (glyph) glyph.className = 'fa-regular fa-copy'; }, 1500);
    }
    return true;
  }

  async function reveal(item) {
    try {
      const result = await window.electronAPI.revealSharedEntry(state.rootId, item.path);
      if (!result || !result.ok) showError(t('revealFailed', 'Could not show it') + ': ' + ((result && result.error) || ''));
    } catch (e) {
      showError(t('revealFailed', 'Could not show it') + ': ' + e.message);
    }
  }

  // The menu of a row.
  function rowMenu(item, button) {
    if (!window.RowMenu) return;
    const entries = [];
    if (item.kind === 'folder') {
      entries.push({ label: t('openFolder', 'Open the folder'), icon: 'fa-regular fa-folder-open', action: function () { load(item.path); } });
    } else if (workScreenShows(item)) {
      entries.push({ label: t('openInWorkScreen', 'Open in the work screen'), icon: 'fa-solid fa-display',
        action: function () { window.Workbench.openFile(item.path); } });
    }
    if (state.chatRoot) {
      entries.push({ label: t('copyPath', 'Copy the path for a chat'), icon: 'fa-regular fa-copy',
        action: function () { copyPaths([item.path]); } });
    }
    if (canReveal(item)) {
      entries.push({ label: t('reveal', 'Show in the file manager'), icon: 'fa-regular fa-folder-open', action: function () { reveal(item); } });
    }
    if (trashAvailable()) {
      const allowed = canTrash(item);
      entries.push('divider');
      entries.push({ label: t('trashOne', 'Move to Trash'), icon: 'fa-regular fa-trash-can', danger: true, disabled: !allowed || trashing,
        title: allowed ? '' : (item.protected_reason ? protectedText(item.protected_reason) : t('cannotTrash', 'This cannot be moved to the Trash')),
        action: function () { trashPaths([item.path]); } });
    }
    window.RowMenu.open(button, entries, { restore: function () { focusPath(item.path); } });
  }

  // The menu of selecting all.
  function selectMenu(button) {
    if (!window.RowMenu) return;
    const files = filesOnly();
    window.RowMenu.open(button, [
      { label: t('selectAll', 'Select all shown'), icon: 'fa-regular fa-square-check', action: selectAllShown,
        disabled: state.items.length === 0 },
      { label: t('selectMatching', 'Select all that can be moved to the Trash'), icon: 'fa-solid fa-list-check',
        action: selectMatching, disabled: !trashAvailable() || matchingBusy || trashing },
      { label: t('selectTests', 'Select test files'), icon: 'fa-solid fa-vial', action: selectTests,
        disabled: !state.items.some(function (i) { return i.classification === 'test_file' && canTrash(i); }) },
      'divider',
      { label: (files ? '✓ ' : '') + t('filesOnly', 'Skip folders when selecting all'), icon: 'fa-regular fa-folder',
        action: function () { setFilesOnly(!files); } }
    ]);
  }

  // The filters (what kind, how old), changed at once.
  function filterPanel(button) {
    if (!window.RowMenu) return;
    const form = el('form', { className: 'sfp-filter-form' });
    form.addEventListener('submit', function (e) { e.preventDefault(); });
    const kind = el('select', { className: 'form-select form-select-sm' });
    kind.id = 'sfp-filter-kind';
    kind.appendChild(el('option', { text: t('filterAll', 'All items') }));
    kind.lastChild.value = '';
    FILTER_KINDS.forEach(function (k) { const o = el('option', { text: t(k[1], k[2]) }); o.value = k[0]; kind.appendChild(o); });
    kind.value = view.cls;
    const age = el('select', { className: 'form-select form-select-sm' });
    age.id = 'sfp-filter-age';
    age.appendChild(el('option', { text: t('ageAll', 'Modified any time') }));
    age.lastChild.value = '';
    FILTER_AGES.forEach(function (a) { const o = el('option', { text: t(a[1], a[2]) }); o.value = a[0]; age.appendChild(o); });
    age.value = view.age;
    const kindLabel = el('label', { className: 'form-label small mb-1', text: t('kindLabel', 'Kind') });
    kindLabel.htmlFor = kind.id;
    const ageLabel = el('label', { className: 'form-label small mb-1 mt-2', text: t('ageLabel', 'Last modified') });
    ageLabel.htmlFor = age.id;
    form.append(kindLabel, kind, ageLabel, age);
    kind.addEventListener('change', function () { view.cls = kind.value; clearChoice(); load(state.path); });
    age.addEventListener('change', function () { view.age = age.value; clearChoice(); load(state.path); });
    window.RowMenu.openPanel(button, form);
  }

  // ---- drawing ---------------------------------------------------------

  function row(item, index) {
    const li = el('li', { className: 'sfp-row' });
    li.dataset.path = item.path;
    const label = item.name;
    if (canSelect(item)) {
      const box = el('button', { className: 'sfp-check', type: 'button' }, [icon('fa-regular fa-square')]);
      box.setAttribute('role', 'checkbox');
      box.setAttribute('aria-checked', 'false');
      box.setAttribute('aria-label', t('selectOne', 'Select {name}').replace('{name}', label));
      box.tabIndex = -1;
      box.addEventListener('click', function (e) { pick(index, e.shiftKey); });
      li.appendChild(box);
    } else {
      li.appendChild(el('span', { className: 'sfp-check sfp-check-none' }));
    }

    const name = el('button', { className: 'sfp-name', type: 'button' });
    name.tabIndex = -1;
    name.appendChild(icon(kindIcon(item) + ' sfp-icon'));
    const text = el('span', { className: 'sfp-text' });
    text.appendChild(el('span', { className: 'sfp-label', text: label }));
    const meta = metaText(item);
    if (meta) text.appendChild(el('span', { className: 'sfp-meta', text: meta }));
    const what = el('span', { className: 'sfp-meta sfp-what', text: whatItIs(item) });
    if (item.protected_reason) {
      what.appendChild(document.createTextNode(' · '));
      what.appendChild(icon('fa-solid fa-lock me-1'));
      what.appendChild(document.createTextNode(protectedText(item.protected_reason)));
    }
    if (item.busy_reason) what.appendChild(el('span', { className: 'badge bg-info text-dark ms-1', text: t('inUse', 'in use') }));
    if (item.kind === 'link') what.appendChild(document.createTextNode(' ' + t('linkNotFollowed', '(link, not followed)')));
    text.appendChild(what);
    name.appendChild(text);
    if (item.kind === 'folder') name.title = t('openFolder', 'Open the folder');
    else if (workScreenShows(item)) name.title = t('openInWorkScreen', 'Open in the work screen');
    name.addEventListener('click', function (e) {
      if (e.metaKey || e.ctrlKey || e.shiftKey) { pick(index, e.shiftKey); return; }
      cursor = index;
      openItem(item, index);
    });
    name.addEventListener('focus', function () { if (cursor !== index) { cursor = index; paintCursor(); } });
    li.appendChild(name);

    const more = el('button', { className: 'btn btn-sm sfp-row-menu', type: 'button' }, [icon('fa-solid fa-ellipsis')]);
    more.setAttribute('aria-label', t('actionsOf', 'Actions for {name}').replace('{name}', label));
    more.setAttribute('aria-haspopup', 'menu');
    more.setAttribute('aria-expanded', 'false');
    more.tabIndex = -1;
    more.addEventListener('click', function () { cursor = index; paintCursor(); rowMenu(item, more); });
    li.appendChild(more);
    return li;
  }

  function render() {
    const list = $id('sfp-list');
    if (!list) return;
    // The focus stays where it was when the list is drawn anew (sizes coming
    // in): on the same entry's name, or on the list.
    const focused = document.activeElement;
    const hadFocus = focused === list || list.contains(focused);
    const focusedLi = hadFocus && focused !== list && focused.closest ? focused.closest('.sfp-row') : null;
    const focusedPath = focusedLi ? focusedLi.dataset.path : null;
    list.replaceChildren.apply(list, state.items.map(row));
    state.items.forEach(function (_i, n) { paintRow(n); });
    paintCursor();
    if (hadFocus) focusPath(focusedPath);

    const up = $id('sfp-up');
    if (up) up.disabled = !state.path;
    renderCrumbs();

    const info = $id('sfp-info');
    if (info) {
      let text = t('count', 'Items') + ': ' + (state.matched !== state.total ? state.matched + ' / ' + state.total : state.total);
      if (state.truncated) text += ' — ' + t('truncated', 'Only the first items read are shown (the folder holds more).');
      if (!state.rootId && state.rootIdProblem) text += ' — ' + t('noFolderId', 'Items cannot be shown in the file manager: this shared folder could not be identified');
      info.textContent = text;
    }
    const more = $id('sfp-more');
    if (more) more.hidden = !hasMore();
    renderBands();
  }

  function renderCrumbs() {
    const crumbs = $id('sfp-where');
    if (!crumbs) return;
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
    crumbs.title = state.path || t('top', 'Shared folder');
  }

  function filterLabel() {
    const parts = [];
    if (view.q) parts.push('“' + view.q + '”');
    const kind = FILTER_KINDS.find(function (k) { return k[0] === view.cls; });
    if (kind) parts.push(t(kind[1], kind[2]));
    const age = FILTER_AGES.find(function (a) { return a[0] === view.age; });
    if (age) parts.push(t(age[1], age[2]));
    return parts.join(' · ');
  }

  // The bands above the list: what it is narrowed by, and what is selected.
  function renderBands() {
    paintCursor();
    const filtering = $id('sfp-filtering');
    const narrowed = !!(view.cls || view.age);
    if (filtering) {
      filtering.hidden = !(narrowed || view.q);
      const text = $id('sfp-filtering-text');
      if (text) text.textContent = t('filteringBy', 'Narrowed by: {what}').replace('{what}', filterLabel());
    }
    const filterBtn = $id('sfp-filter-toggle');
    if (filterBtn) filterBtn.classList.toggle('sfp-on', narrowed);

    const band = $id('sfp-selection');
    if (!band) return;
    const count = selected.size;
    band.hidden = count === 0;
    const summary = $id('sfp-selection-text');
    if (summary) {
      let bytes = 0;
      let partial = false;
      Array.from(selected).forEach(function (p) {
        const i = known.get(p) || { path: p };
        if (typeof i.bytes === 'number') bytes += i.bytes;
        if (typeof i.bytes !== 'number' || (i.kind === 'folder' && i.size_status !== 'complete')) partial = true;
      });
      summary.textContent = t('selectionSummary', 'Selected: {count}, {size} in all')
        .replace('{count}', String(count)).replace('{size}', (partial ? '≥ ' : '') + formatBytes(bytes));
    }
    const copy = $id('sfp-copy');
    if (copy) copy.disabled = count === 0 || !state.chatRoot;
    const trash = $id('sfp-trash');
    if (trash) {
      trash.hidden = !trashAvailable();
      const go = trashTargets().length;
      trash.disabled = go === 0 || trashing;
      const glyph = trash.querySelector('i');
      if (glyph) glyph.className = trashing ? 'fa-solid fa-spinner fa-spin' : 'fa-regular fa-trash-can';
      const label = $id('sfp-trash-label');
      if (label) label.textContent = String(go);
      const name = t('trashCount', 'Move {count} to Trash').replace('{count}', String(go));
      trash.title = name;
      trash.setAttribute('aria-label', name);
      const why = $id('sfp-trash-why');
      if (why) {
        why.hidden = !trashAvailable() || go === count || count === 0;
        why.textContent = t('trashSkippedWhy', '{count} of the selected cannot be moved to the Trash (kept by Monadic Chat or in use).')
          .replace('{count}', String(count - go));
      }
    }
  }

  // ---- the list's keys ---------------------------------------------------

  function editable(target) {
    return !!(target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName)));
  }

  function onListKey(e) {
    if (editable(e.target) || (window.RowMenu && window.RowMenu.isOpen())) return;
    const count = state.items.length;
    if (!count) return;
    // The box and the ⋯ of a row keep their own Enter and Space.
    const onOwnButton = !!(e.target && e.target.closest && e.target.closest('.sfp-check, .sfp-row-menu'));
    if (onOwnButton && (e.key === 'Enter' || e.key === ' ')) return;
    if ((e.metaKey || e.ctrlKey) && !e.altKey && !e.shiftKey && (e.key === 'a' || e.key === 'A')) {
      e.preventDefault();
      const files = filesOnly();
      state.items.forEach(function (i, n) { if (!(files && i.kind === 'folder')) setPicked(n, true); });
      renderBands();
    } else if (e.key === 'Escape') {
      if (!selected.size) return;
      e.preventDefault();
      clearSelection();
    } else if (e.key === 'Enter') {
      if (cursor === null) return;
      e.preventDefault();
      openItem(state.items[cursor], cursor);
    } else if (e.key === ' ') {
      if (cursor === null) return;
      e.preventDefault();
      pick(cursor, e.shiftKey);
    } else if (e.key === 'ContextMenu' || (e.shiftKey && e.key === 'F10')) {
      // The menu of the row the keyboard is on.
      if (cursor === null) return;
      e.preventDefault();
      const button = rowAt(cursor) && rowAt(cursor).querySelector('.sfp-row-menu');
      if (button) rowMenu(state.items[cursor], button);
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const next = cursor === null ? 0 : Math.max(0, Math.min(count - 1, cursor + (e.key === 'ArrowDown' ? 1 : -1)));
      if (e.shiftKey) {
        if (anchor === null) anchor = cursor === null ? next : cursor;
        setRange(anchor, next, true);
      } else {
        anchor = next;
      }
      cursor = next;
      renderBands();
      focusRow(next);
    }
  }

  // ---- status ----------------------------------------------------------

  // The one place for what is going on (loading, nothing to show, errors,
  // what copying or moving to the Trash did). kind: 'info' or 'warn'; no
  // content clears it. keep: it stays until closed (×) or the next one.
  function setStatus(kind, content, keep) {
    const box = $id('sfp-status');
    if (!box) return;
    const parts = (Array.isArray(content) ? content : [content]).filter(function (c) { return c !== null && c !== undefined && c !== ''; })
      .map(function (c) { return typeof c === 'string' ? document.createTextNode(c) : c; });
    box.replaceChildren.apply(box, parts);
    if (parts.length && keep) {
      const close = el('button', { className: 'btn-close sfp-status-close ms-auto', type: 'button' });
      close.setAttribute('aria-label', t('dismiss', 'Dismiss'));
      close.addEventListener('click', function () { setStatus('info', null); showListState(); });
      box.appendChild(close);
    }
    box.classList.toggle('sfp-status-warn', kind === 'warn');
    box.dataset.kept = parts.length && keep ? 'true' : '';
    box.hidden = parts.length === 0;
  }

  function showError(message) {
    setStatus('warn', message || null, true);
  }

  // An earlier error goes once the same kind of action works.
  function clearWarning() {
    const box = $id('sfp-status');
    if (box && box.classList.contains('sfp-status-warn')) setStatus('info', null);
  }

  // Nothing listed: an empty folder, or nothing matching the search and
  // filters (then they can be cleared from here). A kept result stays.
  function showListState() {
    const box = $id('sfp-status');
    if (box && box.dataset.kept === 'true') return;
    if (state.items.length) { setStatus('info', null); return; }
    if (state.total > 0) {
      const clear = el('button', { className: 'btn btn-sm btn-secondary ms-2 sf-clear-filters', type: 'button',
        text: t('clearFilters', 'Clear the search and filters') });
      clear.addEventListener('click', clearFilters);
      setStatus('info', [t('noMatch', 'No items match the search and filters'), (view.q || view.cls || view.age) ? clear : null]);
    } else {
      setStatus('info', t('emptyFolder', 'This folder is empty'));
    }
  }

  function clearFilters() {
    view.q = '';
    view.cls = '';
    view.age = '';
    const box = $id('sfp-search');
    if (box) box.value = '';
    clearChoice();
    load(state.path);
  }

  let loadingTimer = null;

  function loadingStarted() {
    clearTimeout(loadingTimer);
    const list = $id('sfp-list');
    if (list) list.setAttribute('aria-busy', 'true');
    loadingTimer = setTimeout(function () {
      const box = $id('sfp-status');
      if (box && box.dataset.kept === 'true') return;
      setStatus('info', [icon('fa-solid fa-spinner fa-spin me-1'), t('loading', 'Loading…')]);
    }, 250);
  }

  function loadingEnded() {
    clearTimeout(loadingTimer);
    loadingTimer = null;
    const list = $id('sfp-list');
    if (list) list.removeAttribute('aria-busy');
  }

  // ---- reading ---------------------------------------------------------

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

  async function getJson(url) {
    const resp = await fetch(url, controller ? { signal: controller.signal } : undefined);
    const data = await resp.json();
    if (!resp.ok || !data.success) throw new Error(data.error || ('HTTP ' + resp.status));
    return data;
  }

  function viewKey(path) {
    return JSON.stringify([path, view.q, view.sort, view.cls, view.age]);
  }

  function hasMore() {
    return state.pages * PER_PAGE < (state.matched || 0);
  }

  // The search as the box has it now (a pause not over yet included).
  function searchNow() {
    if (!searchTimer) return;
    clearTimeout(searchTimer);
    searchTimer = null;
    const box = $id('sfp-search');
    const q = box ? (box.value || '').trim() : view.q;
    if (q !== view.q) { view.q = q; clearChoice(); }
  }

  // The first page of path. opts.more: the next PER_PAGE entries added to
  // the list. opts.again: the same folder read again from its start, as far
  // as it was shown (at most READ_AGAIN_PAGES pages), keeping the size
  // counts asked so far; the next "Show more" goes on from there.
  async function load(path, opts) {
    opts = opts || {};
    searchNow();
    // More of a list read with other conditions (a search typed since, or
    // one that could not be read) is the new list from its start instead.
    if (opts.more && state.shown !== viewKey(path)) opts = {};
    if (opts.more && !hasMore()) return;
    const mine = nextGeneration();
    // A refresh asks again for the sizes not counted yet; reading again by
    // itself (sizes in, a move to the Trash) keeps what was asked.
    if ((!opts.again && !opts.more) || opts.retry) asked = new Map();
    resortDue = false;
    loadingStarted();
    const pagesNow = opts.again ? Math.max(1, Math.min(state.pages, READ_AGAIN_PAGES)) : 1;
    const page = opts.more ? state.pages + 1 : 1;
    const perPage = opts.more ? PER_PAGE : pagesNow * PER_PAGE;
    try {
      const data = await getJson(query(path, page, perPage));
      if (mine !== generation) return;
      if (data.path !== state.path) { clearChoice(); known = new Map(); }
      // The keyboard's place and the start of a range are rows; in another
      // order they are found again by path, or dropped.
      const anchorPath = anchor !== null && state.items[anchor] ? state.items[anchor].path : null;
      const cursorPath = cursor !== null && state.items[cursor] ? state.items[cursor].path : null;
      let items = data.items || [];
      if (opts.more) {
        const seen = new Set(state.items.map(function (i) { return i.path; }));
        items = state.items.concat(items.filter(function (i) { return !seen.has(i.path); }));
      }
      if (opts.again) {
        // A folder already asked about as often as it may be stays shown as
        // not counted yet, as before the list was asked for again.
        items = items.map(function (i) {
          return i.size_status === 'pending' && (asked.get(i.path) || 0) >= SIZE_POLLS
            ? Object.assign({}, i, { size_status: 'not_counted' }) : i;
        });
      }
      state = { path: data.path, pages: opts.more ? state.pages + 1 : pagesNow, items: items, total: data.total,
                matched: data.matched === undefined ? data.total : data.matched, truncated: !!data.truncated,
                rootId: data.root_id || null, rootIdProblem: data.root_id_problem || null, chatRoot: data.chat_root || null,
                shown: viewKey(data.path) };
      shownByPath = new Map(state.items.map(function (i) { return [i.path, i]; }));
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
  // for the sizes only, while some are still being counted and the tab is
  // shown. Each folder is asked about at most SIZE_POLLS times, and one
  // that is still counting after that is shown as not counted yet, to be
  // refreshed.
  function scheduleSizes(mine) {
    if (!visible || mine !== generation) return;
    const waiting = state.items
      .filter(function (i) { return i.size_status === 'pending' && (asked.get(i.path) || 0) < SIZE_POLLS; })
      .sort(function (a, b) { return (asked.get(a.path) || 0) - (asked.get(b.path) || 0); })
      .slice(0, SIZES_PER_ASK)
      .map(function (i) { return i.path; });
    if (waiting.length === 0) {
      // Every count is in: in size order, the list is read again from its
      // start so that the order shown is the order of the sizes.
      if (resortDue && view.sort === 'size') {
        resortDue = false;
        load(state.path, { again: true });
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
          shownByPath.set(updated.path, updated);
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

  // ---- moving to the Trash ---------------------------------------------
  // Through the desktop app, which asks first in a dialog of its own and
  // then asks the server again for each one. One run at a time; the run
  // keeps the folder it started in, and the list is read again only if that
  // folder is still shown. What did not move stays selected, to try again.
  // The result stays above the list until closed, also if the tab is left.
  let trashing = false;

  async function trashPaths(paths) {
    if (trashing || paths.length === 0 || !trashAvailable()) return;
    const rootId = state.rootId;
    const startPath = state.path;
    const startGeneration = generation;
    const moved = [];
    const failed = [];
    let notTried = 0;
    let cancelled = false;
    trashing = true;
    renderBands();
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
    }
    // Said no before anything was moved: the list and the selection stay as they are.
    if (cancelled && moved.length === 0 && failed.length === 0) { renderBands(); return; }
    const sameFolder = state.path === startPath && state.rootId === rootId;
    if (sameFolder) {
      choiceGeneration += 1;
      moved.forEach(function (p) { selected.delete(p); movable.delete(p); known.delete(p); });
    }
    showTrashResult(moved.length, failed, notTried);
    // The list again only while the tab is shown with the folder the run
    // started in and nothing else was asked for meanwhile (a folder opened,
    // a search); otherwise it is read when the tab is shown next.
    if (sameFolder && visible && generation === startGeneration) await load(state.path, { again: true });
    else renderBands();
  }

  function trashSelected() {
    return trashPaths(trashTargets());
  }

  // The count moved, and every entry that was not, in a list that opens.
  function showTrashResult(movedCount, failed, notTried) {
    if (!failed.length && !notTried) {
      setStatus('info', [icon('fa-solid fa-check me-1'), t('trashDone', 'Moved to the Trash') + ': ' + movedCount], true);
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
    setStatus('warn', [el('div', {}, parts)], true);
  }

  // ---- the tab ---------------------------------------------------------

  // The tab is read when it comes into view (not on every layout change:
  // dragging the border between the columns sends many); what is still on
  // its way stops while it is hidden.
  function onLayout() {
    const lc = window.LayoutController;
    const now = !!(lc && lc.selectedPane() === 'files' && !lc.isMenuHidden());
    if (now && !visible) {
      visible = true;
      // A search typed before the tab was left is taken as it is now.
      const box = $id('sfp-search');
      const q = box ? (box.value || '').trim() : view.q;
      if (q !== view.q) { view.q = q; clearChoice(); }
      load(state.path, { again: state.pages > 0 && state.shown === viewKey(state.path) });
    } else if (!now && visible) {
      visible = false;
      clearTimeout(searchTimer);
      searchTimer = null;
      if (window.RowMenu) window.RowMenu.close();
      nextGeneration();
      loadingEnded();
    }
  }

  let searchTimer = null;

  function init() {
    // The box is read when the pause is over, not when a key is typed: with
    // an input method the last event can carry text that is no longer there.
    const search = $id('sfp-search');
    const searchSoon = function (e) {
      clearTimeout(searchTimer);
      searchTimer = null;
      if (e && e.isComposing) return;
      searchTimer = setTimeout(function () {
        searchTimer = null;
        const q = (search.value || '').trim();
        if (q === view.q) return;
        view.q = q;
        clearChoice();
        load(state.path);
      }, SEARCH_DELAY);
    };
    $on(search, 'input', searchSoon);
    $on(search, 'compositionend', searchSoon);
    $on(search, 'search', searchSoon); // Esc in the box empties it without an input event
    const order = $id('sfp-sort');
    if (order) {
      order.value = view.sort;
      $on(order, 'change', function () {
        if (SORTS.indexOf(order.value) < 0) return;
        view.sort = order.value;
        try { window.localStorage.setItem(SORT_KEY, view.sort); } catch (_) { /* no storage here */ }
        load(state.path);
      });
    }
    $on($id('sfp-up'), 'click', goUp);
    $on($id('sfp-refresh'), 'click', function () { load(state.path, { again: state.pages > 0, retry: true }); });
    $on($id('sfp-more'), 'click', function () { load(state.path, { more: true }); });
    $on($id('sfp-filter-toggle'), 'click', function (e) { filterPanel(e.currentTarget); });
    $on($id('sfp-filtering-clear'), 'click', clearFilters);
    $on($id('sfp-select-menu'), 'click', function (e) { selectMenu(e.currentTarget); });
    $on($id('sfp-copy'), 'click', function (e) { copyPaths(Array.from(selected), e.currentTarget); });
    $on($id('sfp-trash'), 'click', trashSelected);
    $on($id('sfp-clear-selection'), 'click', clearSelection);
    $on($id('sfp-list'), 'keydown', onListKey);
    document.addEventListener('layoutchange', onLayout);
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
  }

  const api = { load: load, workScreenShows: workScreenShows, kindIcon: kindIcon, sizeText: sizeText };
  if (typeof window !== 'undefined') window.SharedFolderPanel = api;
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = Object.assign({}, api, {
      formatBytes: formatBytes, whatItIs: whatItIs, query: query, sizesQuery: sizesQuery, selectMatching: selectMatching,
      selectTests: selectTests, selectAllShown: selectAllShown, clearSelection: clearSelection, trashSelected: trashSelected,
      goUp: goUp, chatPath: chatPath, copyPaths: copyPaths, trashTargets: trashTargets,
      _state: function () { return state; }, _selected: function () { return selected; },
      _view: function (v) { if (v) view = Object.assign(view, v); return view; },
      _visible: function (v) { visible = v; }
    });
  }
})();
