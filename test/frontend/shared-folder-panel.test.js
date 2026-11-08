/**
 * @jest-environment jsdom
 */
// The Files tab of the side column, on the page's own markup: its words are
// in every UI language; it is read when it comes into view and an older
// answer never replaces a newer one; a click opens (a folder in the list, a
// file in the work screen) and the box or a modifier selects; any entry can
// be selected to copy its path, while only what the server allows goes to
// the trash; "Show more" goes on from where reading again left off; folder
// sizes are asked for only while the tab is shown; the result of moving to
// the trash stays; names are set as text.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../../docker/services/ruby');
const PAGE = fs.readFileSync(path.join(ROOT, 'views/index.erb'), 'utf8');
const TRANSLATIONS = fs.readFileSync(path.join(ROOT, 'public/js/i18n/translations.js'), 'utf8');
const js = (f) => path.join(ROOT, 'public/js', f);

function cut(from, to) {
  const start = PAGE.indexOf(from);
  const end = PAGE.indexOf(to, start);
  if (start < 0 || end < 0) throw new Error('markup not found: ' + from);
  return PAGE.slice(start, end);
}

describe('Files tab words', () => {
  it('are in every language with the same keys, and every key used is there', () => {
    const blocks = TRANSLATIONS.split(/\n {2}(?=\w\w: \{\n {4}ui: \{)/).slice(1);
    expect(blocks.map((b) => b.slice(0, 2))).toEqual(['en', 'ja', 'zh', 'ko', 'es', 'fr', 'de']);
    const keysOf = (block) => {
      const body = block.match(/\n {6}sharedFolderPanel: \{\n([\s\S]*?)\n {6}\},/);
      expect(body).not.toBeNull();
      return body[1].split('\n').map((l) => l.trim().split(':')[0]);
    };
    const english = keysOf(blocks[0]);
    blocks.forEach((b) => expect(keysOf(b)).toEqual(english));
    const used = new Set();
    (PAGE.match(/ui\.sharedFolderPanel\.(\w+)/g) || []).forEach((k) => used.add(k.split('.').pop()));
    const script = fs.readFileSync(js('monadic/shared-folder-panel.js'), 'utf8');
    (script.match(/\bt\('(\w+)'/g) || []).forEach((k) => used.add(k.slice(3, -1)));
    used.forEach((k) => expect(english).toContain(k));
  });
});

describe('Files tab', () => {
  let panel;
  let pending;
  let shown;
  const ROOT_ID = 'a'.repeat(32);

  const file = (name, extra) => Object.assign({ name, path: name, kind: 'file', preview: 'text', size_status: 'complete',
    bytes: 100, classification: 'other', capabilities: { reveal: true, trash: true } }, extra);
  const folder = (name, extra) => Object.assign({ name, path: name, kind: 'folder', size_status: 'complete', bytes: 1000,
    classification: 'other', capabilities: { reveal: true, trash: true } }, extra);
  function listing(at, items, extra) {
    return Object.assign({ success: true, path: at, page: 1, per_page: 50, total: items.length, matched: items.length,
      root_id: ROOT_ID, chat_root: '/monadic/data', items }, extra);
  }
  const respond = (i, body, ok = true) => pending[i].resolve({ ok, status: ok ? 200 : 500, json: async () => body });
  const last = () => pending[pending.length - 1];
  async function flush() { for (let i = 0; i < 12; i += 1) await Promise.resolve(); }
  const rows = () => Array.from(document.querySelectorAll('#sfp-list .sfp-row'));
  const names = () => rows().map((r) => r.querySelector('.sfp-label').textContent);
  const checked = () => rows().map((r) => r.querySelector('.sfp-check').getAttribute('aria-checked') === 'true');
  const $ = (id) => document.getElementById(id);
  const show = () => { shown = true; document.dispatchEvent(new Event('layoutchange')); };
  const hide = () => { shown = false; document.dispatchEvent(new Event('layoutchange')); };
  const key = (k, extra) => $('sfp-list').dispatchEvent(new KeyboardEvent('keydown', Object.assign({ key: k, bubbles: true }, extra)));
  const menuItems = () => Array.from(document.querySelectorAll('.row-menu .dropdown-item'));
  const menuItem = (label) => menuItems().find((b) => b.textContent.includes(label));

  async function opened(items, extra) {
    show();
    respond(pending.length - 1, listing('', items, extra));
    await flush();
  }

  beforeEach(() => {
    jest.useFakeTimers();
    jest.resetModules();
    document.body.innerHTML = cut('<%# The shared folder, one folder at a time', '<%# The kept chats');
    localStorage.clear();
    shown = false;
    pending = [];
    global.fetch = jest.fn((url) => new Promise((resolve) => { pending.push({ url, resolve }); }));
    window.LayoutController = { selectedPane: () => (shown ? 'files' : 'settings'), isMenuHidden: () => false };
    window.Workbench = { openFile: jest.fn() };
    window.electronAPI = { trashSharedEntries: jest.fn(), revealSharedEntry: jest.fn(), writeClipboard: jest.fn(async () => true) };
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/row-menu.js'));
    panel = require(js('monadic/shared-folder-panel.js'));
  });

  afterEach(() => {
    if (window.RowMenu) window.RowMenu.close();
    jest.useRealTimers();
    delete global.fetch;
    delete window.electronAPI;
  });

  describe('reading', () => {
    it('reads the folder when the tab comes into view, not on every layout change', async () => {
      document.dispatchEvent(new Event('layoutchange'));
      expect(pending).toHaveLength(0);
      show();
      expect(pending).toHaveLength(1);
      expect(pending[0].url).toContain('/api/shared_folder?path=&page=1&per_page=50');
      document.dispatchEvent(new Event('layoutchange'));
      expect(pending).toHaveLength(1);
    });

    it('keeps the folder it moved to when an older answer comes last', async () => {
      await opened([folder('box')]);
      panel.load('box');
      panel.load('other');
      respond(2, listing('other', [file('o.txt', { path: 'other/o.txt' })]));
      await flush();
      respond(1, listing('box', [file('b.txt', { path: 'box/b.txt' })]));
      await flush();
      expect(panel._state().path).toBe('other');
      expect(names()).toEqual(['o.txt']);
    });

    it('sets names as text', async () => {
      await opened([file('<img src=x onerror=alert(1)>.txt')]);
      expect(names()).toEqual(['<img src=x onerror=alert(1)>.txt']);
      expect(document.querySelector('#sfp-list img')).toBeNull();
    });

    it('says when the entry was modified, its size and what it is', async () => {
      await opened([file('a.txt', { modified_at: '2026-11-08T11:45:00Z', bytes: 2048, classification: 'generated' })]);
      const metas = rows()[0].querySelectorAll('.sfp-meta');
      expect(metas[0].textContent).toContain('2.0 KB');
      expect(metas[0].textContent).toMatch(/2026/);
      expect(metas[1].textContent).toContain('Generated file');
    });

    it('says an empty folder is empty, and offers to clear a search and filters that leave nothing', async () => {
      await opened([]);
      expect($('sfp-status').textContent).toContain('empty');
      panel._view({ cls: 'generated' });
      panel.load('');
      respond(1, listing('', [], { total: 5 }));
      await flush();
      expect($('sfp-status').textContent).toContain('No items match');
      $('sfp-status').querySelector('.sf-clear-filters').click();
      expect(last().url).not.toContain('classes');
    });
  });

  describe('opening and selecting', () => {
    it('opens a folder in the list and a file in the work screen; selects a file the work screen does not show', async () => {
      await opened([folder('box'), file('a.txt'), file('b.zip', { preview: null })]);
      rows()[1].querySelector('.sfp-name').click();
      expect(window.Workbench.openFile).toHaveBeenCalledWith('a.txt');
      rows()[2].querySelector('.sfp-name').click();
      expect(checked()).toEqual([false, false, true]);
      rows()[0].querySelector('.sfp-name').click();
      expect(last().url).toContain('path=box');
    });

    it('selects without opening with Cmd/Ctrl, a range with Shift, and with the box', async () => {
      await opened([file('a.txt'), file('b.txt'), file('c.txt'), file('d.txt')]);
      rows()[0].querySelector('.sfp-name').dispatchEvent(new MouseEvent('click', { bubbles: true, metaKey: true }));
      expect(window.Workbench.openFile).not.toHaveBeenCalled();
      rows()[2].querySelector('.sfp-check').dispatchEvent(new MouseEvent('click', { bubbles: true, shiftKey: true }));
      expect(checked()).toEqual([true, true, true, false]);
      rows()[1].querySelector('.sfp-check').click();
      expect(checked()).toEqual([true, false, true, false]);
      expect($('sfp-selection').hidden).toBe(false);
      $('sfp-clear-selection').click();
      expect(checked()).toEqual([false, false, false, false]);
      expect($('sfp-selection').hidden).toBe(true);
    });

    it('moves with the arrows, selects with Space (Shift for a range), opens with Enter, clears with Esc, selects all with Cmd+A', async () => {
      await opened([file('a.txt'), file('b.txt'), file('c.txt')]);
      key('ArrowDown');
      key(' ');
      expect(checked()).toEqual([true, false, false]);
      key('ArrowDown', { shiftKey: true });
      key('ArrowDown', { shiftKey: true });
      expect(checked()).toEqual([true, true, true]);
      key('Escape');
      expect(checked()).toEqual([false, false, false]);
      key('Enter');
      expect(window.Workbench.openFile).toHaveBeenCalledWith('c.txt');
      key('a', { metaKey: true });
      expect(checked()).toEqual([true, true, true]);
    });

    it('opens the menu of the row the keyboard is on with Shift+F10', async () => {
      await opened([file('a.txt')]);
      key('ArrowDown');
      key('F10', { shiftKey: true });
      expect(menuItem('Open in the work screen')).toBeTruthy();
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      expect(document.querySelector('.row-menu')).toBeNull();
    });

    it('leaves the list keys alone while the search is typed in', async () => {
      await opened([file('a.txt')]);
      $('sfp-search').dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }));
      expect(checked()).toEqual([false]);
    });
  });

  describe('copying and moving to the Trash', () => {
    it('copies the paths of any entries selected, and says so only when the clipboard has them', async () => {
      await opened([file('a.txt'), file('kept.txt', { capabilities: { reveal: true, trash: false }, protected_reason: 'user_scripts' })]);
      rows()[0].querySelector('.sfp-check').click();
      rows()[1].querySelector('.sfp-check').click();
      $('sfp-copy').click();
      await flush();
      expect(window.electronAPI.writeClipboard).toHaveBeenCalledWith('/monadic/data/a.txt\n/monadic/data/kept.txt');
      expect($('sfp-status').textContent).toContain('Copied 2 paths');
      window.electronAPI.writeClipboard = jest.fn(async () => false);
      $('sfp-copy').click();
      await flush();
      expect($('sfp-status').textContent).toContain('could not be copied');
    });

    it('moves only what may go, and says how many of the selected cannot', async () => {
      await opened([file('a.txt'), file('kept.txt', { capabilities: { reveal: true, trash: false } })]);
      rows()[1].querySelector('.sfp-check').click();
      expect($('sfp-trash').disabled).toBe(true);
      expect($('sfp-trash-why').hidden).toBe(false);
      rows()[0].querySelector('.sfp-check').click();
      expect($('sfp-trash').disabled).toBe(false);
      expect($('sfp-trash-label').textContent).toBe('1');
      window.electronAPI.trashSharedEntries.mockResolvedValue({ results: [{ path: 'a.txt', ok: true }] });
      $('sfp-trash').click();
      await flush();
      expect(window.electronAPI.trashSharedEntries).toHaveBeenCalledWith(ROOT_ID, ['a.txt']);
    });

    it('offers no Trash where entries cannot be moved (outside the desktop app)', async () => {
      delete window.electronAPI;
      await opened([file('a.txt')]);
      rows()[0].querySelector('.sfp-check').click();
      expect($('sfp-trash').hidden).toBe(true);
      expect($('sfp-copy').disabled).toBe(false);
    });

    it('selects all that can be moved from the menu, also entries not shown, and moves them', async () => {
      await opened([file('a.txt')], { matched: 120, total: 120 });
      $('sfp-select-menu').click();
      menuItem('Select all that can be moved').click();
      const ask = last();
      expect(ask.url).toContain('/api/shared_folder/matching?');
      ask.resolve({ ok: true, status: 200, json: async () => ({ success: true, items: [{ path: 'a.txt', kind: 'file' }, { path: 'z.txt', kind: 'file' }] }) });
      await flush();
      expect(panel.trashTargets().sort()).toEqual(['a.txt', 'z.txt']);
      expect($('sfp-trash-label').textContent).toBe('2');
    });

    it('does not bring back a selection cleared while all that can be moved was asked for', async () => {
      await opened([file('a.txt')]);
      $('sfp-select-menu').click();
      menuItem('Select all that can be moved').click();
      const ask = last();
      $('sfp-search').value = 'x';
      $('sfp-search').dispatchEvent(new Event('input'));
      jest.advanceTimersByTime(300);
      ask.resolve({ ok: true, status: 200, json: async () => ({ success: true, items: [{ path: 'z.txt', kind: 'file' }] }) });
      await flush();
      expect(panel._selected().size).toBe(0);
    });

    it('keeps the result of moving to the Trash after the list is read again, until it is closed', async () => {
      await opened([file('a.txt'), file('b.txt')]);
      rows()[0].querySelector('.sfp-check').click();
      rows()[1].querySelector('.sfp-check').click();
      window.electronAPI.trashSharedEntries.mockResolvedValue({ results: [{ path: 'a.txt', ok: true }, { path: 'b.txt', ok: false, error: 'busy' }] });
      $('sfp-trash').click();
      await flush();
      respond(pending.length - 1, listing('', [file('b.txt')]));
      await flush();
      expect($('sfp-status').textContent).toContain('Moved: 1, not moved: 1');
      expect(panel._selected().has('b.txt')).toBe(true);
      expect(panel._selected().has('a.txt')).toBe(false);
      $('sfp-status').querySelector('.sfp-status-close').click();
      expect($('sfp-status').textContent).not.toContain('Moved');
    });

    it('changes nothing when the person says no in the dialog', async () => {
      await opened([file('a.txt')]);
      rows()[0].querySelector('.sfp-check').click();
      window.electronAPI.trashSharedEntries.mockResolvedValue({ cancelled: true });
      const asked = pending.length;
      $('sfp-trash').click();
      await flush();
      expect(pending).toHaveLength(asked);
      expect(panel._selected().has('a.txt')).toBe(true);
    });

    it('leaves the folder shown now as it is when a run started in another one ends', async () => {
      await opened([folder('box'), file('a.txt')]);
      rows()[1].querySelector('.sfp-check').click();
      let finish;
      window.electronAPI.trashSharedEntries.mockReturnValue(new Promise((r) => { finish = r; }));
      $('sfp-trash').click();
      panel.load('box');
      respond(pending.length - 1, listing('box', [file('in.txt', { path: 'box/in.txt' })]));
      await flush();
      const asked = pending.length;
      finish({ results: [{ path: 'a.txt', ok: true }] });
      await flush();
      expect(pending).toHaveLength(asked);
      expect(names()).toEqual(['in.txt']);
      expect($('sfp-status').textContent).toContain('Moved to the Trash');
    });
  });

  describe('operations that overlap (a search pause, a hidden tab, a list drawn anew)', () => {
    it('reads a search typed just before Show more from its start, never adding it to the list shown', async () => {
      await opened([file('old.txt')], { matched: 120, total: 120 });
      $('sfp-search').value = 'new';
      $('sfp-search').dispatchEvent(new Event('input'));
      $('sfp-more').click();
      expect(last().url).toContain('page=1&per_page=50');
      expect(last().url).toContain('q=new');
      respond(pending.length - 1, listing('', [file('new1.txt')], { matched: 120, total: 120 }));
      await flush();
      expect(names()).toEqual(['new1.txt']);
    });

    it('does not add to the list shown after a new search could not be read', async () => {
      await opened([file('old.txt')], { matched: 120, total: 120 });
      $('sfp-search').value = 'new';
      $('sfp-search').dispatchEvent(new Event('input'));
      jest.advanceTimersByTime(300);
      respond(pending.length - 1, { success: false, error: 'x' }, false);
      await flush();
      $('sfp-more').click();
      expect(last().url).toContain('page=1&per_page=50');
    });

    it('keeps a selected entry that may go among what goes to the Trash when it is no longer shown', async () => {
      await opened([file('a.txt'), file('b.txt')]);
      rows()[0].querySelector('.sfp-check').click();
      $('sfp-refresh').click();
      respond(pending.length - 1, listing('', [file('b.txt')]));
      await flush();
      expect(panel._selected().has('a.txt')).toBe(true);
      expect(panel.trashTargets()).toEqual(['a.txt']);
    });

    it('leaves Enter on a row\'s box to the box, and moves the focus from name to name with the arrows', async () => {
      await opened([file('a.txt'), file('b.txt')]);
      // The keyboard is on a row (its name had the focus) before the box gets it.
      rows()[1].querySelector('.sfp-name').focus();
      const box = rows()[0].querySelector('.sfp-check');
      box.focus();
      box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
      expect(window.Workbench.openFile).not.toHaveBeenCalled();
      const first = rows()[0].querySelector('.sfp-name');
      first.focus();
      first.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
      expect(document.activeElement).toBe(rows()[1].querySelector('.sfp-name'));
      expect(rows()[1].querySelector('.sfp-name').tabIndex).toBe(0);
      expect(rows()[0].querySelector('.sfp-name').tabIndex).toBe(-1);
    });

    it('keeps the focus on the same entry when the list is drawn anew', async () => {
      await opened([folder('big', { size_status: 'pending', bytes: undefined }), file('a.txt')]);
      rows()[1].querySelector('.sfp-name').focus();
      jest.advanceTimersByTime(2000);
      await flush();
      last().resolve({ ok: true, status: 200, json: async () => ({ success: true, sizes: { big: { size_status: 'pending' } } }) });
      await flush();
      expect(document.activeElement).toBe(rows()[1].querySelector('.sfp-name'));
    });

    it('starts nothing when the tab is left during a search pause', async () => {
      await opened([file('a.txt')]);
      $('sfp-search').value = 'x';
      $('sfp-search').dispatchEvent(new Event('input'));
      hide();
      const asked = pending.length;
      jest.advanceTimersByTime(1000);
      expect(pending).toHaveLength(asked);
      show();
      expect(last().url).toContain('q=x');
    });

    it('does not read the folder again after a move to the Trash when the tab was left', async () => {
      await opened([file('a.txt')]);
      rows()[0].querySelector('.sfp-check').click();
      let finish;
      window.electronAPI.trashSharedEntries.mockReturnValue(new Promise((r) => { finish = r; }));
      $('sfp-trash').click();
      hide();
      const asked = pending.length;
      finish({ results: [{ path: 'a.txt', ok: true }] });
      await flush();
      expect(pending).toHaveLength(asked);
      expect($('sfp-status').textContent).toContain('Moved to the Trash');
    });

    it('asks again for sizes not counted after Refresh', async () => {
      await opened([folder('big', { size_status: 'pending', bytes: undefined })]);
      for (let n = 0; n < 15; n += 1) {
        jest.advanceTimersByTime(2000);
        await flush();
        last().resolve({ ok: true, status: 200, json: async () => ({ success: true, sizes: { big: { size_status: 'pending' } } }) });
        await flush();
      }
      expect(rows()[0].textContent).toContain('not counted yet');
      $('sfp-refresh').click();
      respond(pending.length - 1, listing('', [folder('big', { size_status: 'pending', bytes: undefined })]));
      await flush();
      jest.advanceTimersByTime(2000);
      await flush();
      expect(last().url).toContain('/api/shared_folder/sizes?');
    });
  });

  describe('more entries, and reading again', () => {
    const many = (from, n) => Array.from({ length: n }, (_, i) => file(`f${String(from + i).padStart(4, '0')}.txt`));

    it('adds the next 50 with Show more', async () => {
      await opened(many(0, 50), { matched: 120, total: 120 });
      $('sfp-more').click();
      expect(last().url).toContain('page=2&per_page=50');
      respond(pending.length - 1, listing('', many(50, 50), { page: 2, matched: 120, total: 120 }));
      await flush();
      expect(rows()).toHaveLength(100);
      expect($('sfp-more').hidden).toBe(false);
    });

    it('goes on from where reading again left off (150 read again, then page 4)', async () => {
      await opened(many(0, 50), { matched: 400, total: 400 });
      for (let p = 2; p <= 3; p += 1) {
        $('sfp-more').click();
        respond(pending.length - 1, listing('', many((p - 1) * 50, 50), { page: p, matched: 400, total: 400 }));
        await flush();
      }
      $('sfp-refresh').click();
      expect(last().url).toContain('page=1&per_page=150');
      respond(pending.length - 1, listing('', many(0, 150), { per_page: 150, matched: 400, total: 400 }));
      await flush();
      $('sfp-more').click();
      expect(last().url).toContain('page=4&per_page=50');
    });

    it('reads again at most 500, and goes on from page 11', async () => {
      await opened(many(0, 50), { matched: 1000, total: 1000 });
      for (let p = 2; p <= 13; p += 1) {
        $('sfp-more').click();
        respond(pending.length - 1, listing('', many((p - 1) * 50, 50), { page: p, matched: 1000, total: 1000 }));
        await flush();
      }
      expect(rows()).toHaveLength(650);
      $('sfp-refresh').click();
      expect(last().url).toContain('page=1&per_page=500');
      respond(pending.length - 1, listing('', many(0, 500), { per_page: 500, matched: 1000, total: 1000 }));
      await flush();
      expect(rows()).toHaveLength(500);
      $('sfp-more').click();
      expect(last().url).toContain('page=11&per_page=50');
    });

    it('keeps the selection by path when the list is read again', async () => {
      await opened([file('a.txt'), file('b.txt')]);
      rows()[1].querySelector('.sfp-check').click();
      $('sfp-refresh').click();
      respond(pending.length - 1, listing('', [file('new.txt'), file('a.txt'), file('b.txt')]));
      await flush();
      expect(checked()).toEqual([false, false, true]);
    });
  });

  describe('folder sizes', () => {
    it('asks for sizes while the tab is shown, and reads the list again in size order once they are in', async () => {
      panel._view({ sort: 'size' });
      await opened([folder('big', { size_status: 'pending', bytes: undefined }), file('a.txt')]);
      jest.advanceTimersByTime(2000);
      await flush();
      expect(last().url).toContain('/api/shared_folder/sizes?');
      last().resolve({ ok: true, status: 200, json: async () => ({ success: true, sizes: { big: { size_status: 'complete', bytes: 5000 } } }) });
      await flush();
      expect(last().url).toContain('sort=size');
      expect(last().url).toContain('page=1&per_page=50');
    });

    it('asks nothing while the tab is hidden', async () => {
      await opened([folder('big', { size_status: 'pending', bytes: undefined })]);
      hide();
      const asked = pending.length;
      jest.advanceTimersByTime(10000);
      await flush();
      expect(pending).toHaveLength(asked);
    });
  });

  describe('filters', () => {
    it('narrows by kind from the filter panel, says so above the list, and clears it from there', async () => {
      await opened([file('a.txt')]);
      $('sfp-filter-toggle').click();
      const kind = document.getElementById('sfp-filter-kind');
      kind.value = 'generated';
      kind.dispatchEvent(new Event('change'));
      expect(last().url).toContain('classes%5B%5D=generated');
      respond(pending.length - 1, listing('', [file('g.png', { classification: 'generated' })]));
      await flush();
      expect($('sfp-filtering').hidden).toBe(false);
      expect($('sfp-filtering-text').textContent).toContain('Generated file');
      expect($('sfp-filter-toggle').classList.contains('sfp-on')).toBe(true);
      $('sfp-filtering-clear').click();
      expect(last().url).not.toContain('classes');
    });

    it('orders as chosen and keeps the order for the next load', async () => {
      await opened([]);
      $('sfp-sort').value = 'modified';
      $('sfp-sort').dispatchEvent(new Event('change'));
      expect(last().url).toContain('sort=modified');
      expect(localStorage.getItem('monadic-shared-files-sort')).toBe('modified');
    });
  });
});
