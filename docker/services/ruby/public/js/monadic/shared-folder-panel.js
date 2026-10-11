// The shared folder page: what the shared folder holds, one folder at a
// time, with each entry's size, what it is, and whether it must be kept or
// is in use. Read only. In the desktop app an entry can be shown in the
// file manager. Names come from the folder, so they are always set as text.
(function () {
  'use strict';

  const SIZE_POLLS = 15;      // times to ask again for one folder's size
  const SIZES_PER_ASK = 200;  // folders per request (the server's limit)
  const SIZE_POLL_MS = 2000;

  let state = { path: '', page: 1, items: [], total: 0, truncated: false, rootId: null, rootIdProblem: null };

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
  let loadingMore = false;

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

  function row(item) {
    const tr = document.createElement('tr');

    const nameCell = el('td');
    const kindIcon = item.kind === 'folder' ? 'fa-regular fa-folder' :
      item.kind === 'link' ? 'fa-solid fa-link' : item.kind === 'file' ? 'fa-regular fa-file' : 'fa-solid fa-question';
    nameCell.appendChild(icon(kindIcon + ' me-2 text-secondary'));
    if (item.kind === 'folder') {
      const a = el('a', { text: item.name });
      a.href = '#';
      a.addEventListener('click', function (e) { e.preventDefault(); load(item.path); });
      nameCell.appendChild(a);
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

    const actions = el('td', { className: 'text-end' });
    if (canReveal(item)) {
      const btn = el('button', { className: 'btn btn-sm btn-outline-secondary', type: 'button', title: t('reveal', 'Show in the file manager') }, [icon('fa-regular fa-folder-open')]);
      btn.addEventListener('click', function () { reveal(item); });
      actions.appendChild(btn);
    }
    tr.appendChild(actions);
    return tr;
  }

  function render() {
    const body = $id('shared-folder-tbody');
    if (!body) return;
    body.replaceChildren();
    state.items.forEach(function (item) { body.appendChild(row(item)); });

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
      let text = t('count', 'Entries') + ': ' + state.total;
      if (state.truncated) text += ' — ' + t('truncated', 'Only the first entries read are shown (the folder holds more).');
      if (!state.rootId && state.rootIdProblem) text += ' — ' + t('noFolderId', 'Entries cannot be shown in the file manager: this shared folder could not be identified');
      info.textContent = text;
    }
    const more = $id('shared-folder-more');
    if (more) more.style.display = state.items.length < state.total ? '' : 'none';
  }

  function tabParam(params) {
    const id = (typeof window.getMonadicTabId === 'function') ? window.getMonadicTabId() : null;
    if (id) params.set('tab_id', id);
    return params;
  }

  function query(path, page) {
    return '/api/shared_folder?' + tabParam(new URLSearchParams({ path: path, page: String(page) })).toString();
  }

  function sizesQuery(paths) {
    const params = new URLSearchParams();
    paths.forEach(function (p) { params.append('paths[]', p); });
    return '/api/shared_folder/sizes?' + tabParam(params).toString();
  }

  function showError(message) {
    const err = $id('shared-folder-error');
    if (!err) return;
    err.textContent = message || '';
    err.style.display = message ? '' : 'none';
  }

  async function getJson(url) {
    const resp = await fetch(url, controller ? { signal: controller.signal } : undefined);
    const data = await resp.json();
    if (!resp.ok || !data.success) throw new Error(data.error || ('HTTP ' + resp.status));
    return data;
  }

  // A folder from its first page.
  async function load(path) {
    const mine = nextGeneration();
    asked = new Map();
    loadingMore = false;
    showError('');
    try {
      const data = await getJson(query(path, 1));
      if (mine !== generation) return;
      state = { path: data.path, page: data.page, items: data.items, total: data.total, truncated: !!data.truncated,
                rootId: data.root_id || null, rootIdProblem: data.root_id_problem || null };
      render();
      scheduleSizes(mine);
    } catch (e) {
      if (mine !== generation || (e && e.name === 'AbortError')) return;
      showError(t('loadFailed', 'The shared folder could not be read') + ': ' + e.message);
    }
  }

  // The next page of the folder shown now (one at a time).
  async function loadMore() {
    if (loadingMore) return;
    loadingMore = true;
    const mine = generation;
    const path = state.path;
    try {
      const data = await getJson(query(path, state.page + 1));
      if (mine !== generation || path !== state.path) return;
      state.items = state.items.concat(data.items);
      state.page = data.page;
      render();
      scheduleSizes(mine);
    } catch (e) {
      if (mine === generation && !(e && e.name === 'AbortError')) {
        showError(t('loadFailed', 'The shared folder could not be read') + ': ' + e.message);
      }
    } finally {
      if (mine === generation) loadingMore = false;
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
    if (waiting.length === 0) return;
    clearTimeout(timer);
    timer = setTimeout(async function () {
      waiting.forEach(function (p) { asked.set(p, (asked.get(p) || 0) + 1); });
      try {
        const data = await getJson(sizesQuery(waiting));
        if (mine !== generation) return;
        state.items = state.items.map(function (i) {
          const size = data.sizes[i.path];
          return size ? Object.assign({}, i, size) : i;
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

  function init() {
    $on($id('shared-folder-browse'), 'click', open);
    $on($id('shared-folder-refresh'), 'click', function () { load(state.path); });
    $on($id('shared-folder-more'), 'click', loadMore);
    $on($id('sharedFolderModal'), 'hidden.bs.modal', function () {
      isOpen = false;
      nextGeneration(); // drops what is still on its way
    });
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { formatBytes: formatBytes, sizeText: sizeText, whatItIs: whatItIs, query: query, sizesQuery: sizesQuery,
      open: open, load: load, loadMore: loadMore, _state: function () { return state; } };
  }
  if (typeof window !== 'undefined') window.SharedFolderPanel = { open: open, load: load };
})();
