/**
 * shared-files-pane.js
 *
 * The Shared folder pane of the side column (layout-controller.js): a light
 * list of one folder of the shared folder at a time, with a search of the
 * names in it. A folder opens on a click; a file the work screen shows
 * opens there (Workbench.openFile, as from the Shared Folder window); any
 * other file opens the Shared Folder window on it (its folder, searched by
 * its name). Managing the folder (filters, sizes, moving to the Trash) is
 * in that window, which "Show all" opens on the same folder and search.
 *
 * The list is read when the pane comes into view and on Refresh, PER_PAGE
 * entries at a time ("Show more"); an answer to an older request (another
 * folder or search) is dropped. What is shown (state) changes only when an
 * answer comes: a folder that cannot be read leaves the one shown, and
 * what acts on "this folder" acts on the one shown.
 */
(function () {
  'use strict';

  const PER_PAGE = 50;
  const SEARCH_DELAY = 300;

  let state = { path: '', q: '', items: [], page: 0, matched: 0, truncated: false };
  let generation = 0;
  let controller = null;
  let searchTimer = null;
  let visible = false;

  function t(key, fallback) {
    try {
      if (typeof webUIi18n !== 'undefined') {
        const v = webUIi18n.t('ui.sharedFilesPane.' + key);
        if (v && v !== 'ui.sharedFilesPane.' + key) return v;
      }
    } catch (_) { /* fall back */ }
    return fallback;
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function icon(className) {
    const i = element('i', className);
    i.setAttribute('aria-hidden', 'true');
    return i;
  }

  function panel() {
    return window.SharedFolderPanel || null;
  }

  function opensInWorkScreen(item) {
    const p = panel();
    return !!(p && typeof p.workScreenShows === 'function' && p.workScreenShows(item));
  }

  function kindIcon(item) {
    const p = panel();
    return p && typeof p.kindIcon === 'function' ? p.kindIcon(item) : (item.kind === 'folder' ? 'fa-solid fa-folder' : 'fa-regular fa-file');
  }

  function query(path, q, page) {
    const params = new URLSearchParams({ path: path, page: String(page), per_page: String(PER_PAGE) });
    if (q) params.set('q', q);
    const id = typeof window.getMonadicTabId === 'function' ? window.getMonadicTabId() : null;
    if (id) params.set('tab_id', id);
    return '/api/shared_folder?' + params.toString();
  }

  // A new request: what is still on its way is dropped.
  function nextGeneration() {
    generation += 1;
    if (controller) controller.abort();
    controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
    return generation;
  }

  // The first page of path searching for q (the search box's), replacing
  // the list; or, with more, the next page of the folder shown added to it.
  async function load(path, more) {
    if (more && !hasMore()) return;
    const mine = nextGeneration();
    const q = more ? state.q : searchNow();
    const at = more ? state.path : path;
    const page = more ? state.page + 1 : 1;
    if (!more) setStatus(t('loading', 'Loading…'));
    setMoreBusy(true);
    try {
      const resp = await fetch(query(at, q, page), controller ? { signal: controller.signal } : undefined);
      const data = await resp.json();
      if (mine !== generation) return;
      if (!resp.ok || !data.success) throw new Error(data.error || ('HTTP ' + resp.status));
      const kept = more ? state.items : [];
      const seen = new Set(kept.map(function (i) { return i.path; }));
      const added = (data.items || []).filter(function (i) { return !seen.has(i.path); });
      state = { path: typeof data.path === 'string' ? data.path : at, q: q, items: kept.concat(added),
        page: data.page || page, matched: data.matched || 0, truncated: !!data.truncated };
      render();
    } catch (e) {
      if (mine !== generation || (e && e.name === 'AbortError')) return;
      setStatus(t('failed', 'The shared folder could not be read.'), true);
    } finally {
      if (mine === generation) setMoreBusy(false);
    }
  }

  // The search as the box has it now (a pause not over yet included).
  function searchNow() {
    clearTimeout(searchTimer);
    searchTimer = null;
    const box = $id('sfp-search');
    return box ? (box.value || '').trim() : state.q;
  }

  function hasMore() {
    return state.page > 0 && state.page * PER_PAGE < state.matched;
  }

  function setStatus(text, warn) {
    const box = $id('sfp-status');
    if (!box) return;
    box.replaceChildren();
    if (text) box.appendChild(document.createTextNode(text));
    box.classList.toggle('sfp-status-warn', !!warn);
    box.hidden = !text;
  }

  function setMoreBusy(busy) {
    const more = $id('sfp-more');
    if (more) more.disabled = !!busy;
  }

  function where() {
    return state.path ? state.path : t('top', 'Shared folder');
  }

  function render() {
    const list = $id('sfp-list');
    if (!list) return;
    list.replaceChildren.apply(list, state.items.map(row));
    const up = $id('sfp-up');
    if (up) up.disabled = !state.path;
    const at = $id('sfp-where');
    if (at) {
      at.textContent = where();
      at.title = where();
    }
    const more = $id('sfp-more');
    if (more) more.hidden = !hasMore();
    if (state.items.length) {
      setStatus(state.truncated ? t('truncated', 'Only the first items read are shown.') : '');
    } else if (state.q) {
      const box = $id('sfp-status');
      setStatus(t('noMatch', 'No names match the search.'));
      if (box) {
        const clear = element('button', 'btn btn-sm btn-secondary ms-2 sfp-clear', t('clearSearch', 'Clear the search'));
        clear.type = 'button';
        clear.addEventListener('click', clearSearch);
        box.appendChild(clear);
      }
    } else {
      setStatus(t('empty', 'This folder is empty.'));
    }
  }

  function row(item) {
    const li = element('li', 'sfp-row');
    li.dataset.path = item.path;
    const name = element('button', 'sfp-name');
    name.type = 'button';
    name.appendChild(icon(kindIcon(item) + ' sfp-icon'));
    name.appendChild(element('span', 'sfp-label', item.name));
    if (item.kind === 'folder') {
      name.title = t('openFolder', 'Open the folder');
      name.addEventListener('click', function () { enter(item.path); });
    } else if (opensInWorkScreen(item)) {
      name.title = t('openInWorkScreen', 'Open in the work screen');
      name.addEventListener('click', function () { openInWorkScreen(item); });
    } else {
      // The window shows it, in its folder (the window manages it).
      name.title = t('openInWindow', 'Show in the Shared Folder window');
      name.addEventListener('click', function () { openInWindow(item); });
    }
    li.appendChild(name);
    if (opensInWorkScreen(item)) {
      const label = t('openInWorkScreenOf', 'Open {name} in the work screen').replace('{name}', item.name);
      const open = element('button', 'btn btn-sm btn-secondary sfp-open');
      open.type = 'button';
      open.title = label;
      open.setAttribute('aria-label', label);
      open.appendChild(icon('fa-solid fa-display'));
      open.addEventListener('click', function () { openInWorkScreen(item); });
      li.appendChild(open);
    }
    return li;
  }

  function openInWindow(item) {
    const p = panel();
    if (p && typeof p.open === 'function') p.open({ path: state.path, q: item.name });
  }

  function openInWorkScreen(item) {
    if (window.Workbench && typeof window.Workbench.openFile === 'function') window.Workbench.openFile(item.path);
  }

  function enter(path) {
    load(path, false);
  }

  function goUp() {
    if (!state.path) return;
    const parts = state.path.split('/');
    parts.pop();
    load(parts.join('/'), false);
  }

  function clearSearch() {
    const box = $id('sfp-search');
    if (box) box.value = '';
    load(state.path, false);
  }

  // The window, on the folder shown and the search as typed.
  function showAll() {
    const p = panel();
    if (p && typeof p.open === 'function') p.open({ path: state.path, q: searchNow() });
  }

  // The pane is read when it comes into view (not on every layout change:
  // dragging the border between the columns sends many).
  function onLayout() {
    const lc = window.LayoutController;
    const now = !!(lc && lc.selectedPane() === 'files' && !lc.isMenuHidden());
    if (now && !visible) load(state.path, false);
    visible = now;
  }

  function init() {
    const search = $id('sfp-search');
    const searchSoon = function (e) {
      clearTimeout(searchTimer);
      searchTimer = null;
      if (e && e.isComposing) return;
      searchTimer = setTimeout(function () {
        searchTimer = null;
        if ((search.value || '').trim() === state.q) return;
        load(state.path, false);
      }, SEARCH_DELAY);
    };
    $on(search, 'input', searchSoon);
    $on(search, 'compositionend', searchSoon);
    $on(search, 'search', searchSoon);
    $on($id('sfp-up'), 'click', goUp);
    $on($id('sfp-refresh'), 'click', function () { load(state.path, false); });
    $on($id('sfp-all'), 'click', showAll);
    $on($id('sfp-more'), 'click', function () { load(state.path, true); });
    document.addEventListener('layoutchange', onLayout);
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
  }

  const api = { load: load, _state: function () { return state; } };
  window.SharedFilesPane = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
