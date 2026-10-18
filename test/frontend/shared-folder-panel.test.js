/**
 * @jest-environment jsdom
 */
// The shared folder page: its words are found in every UI language, a
// response for a folder it has left never replaces the one shown, and
// nothing keeps running once it is closed.
const fs = require('fs');
const path = require('path');

const TRANSLATIONS = path.join(__dirname, '../../docker/services/ruby/public/js/i18n/translations.js');

describe('shared folder page words', () => {
  // Each language's ui block holds sharedFolderPanel once, as an object
  // (an older string key named sharedFolder must not be reused for it).
  it('are an object of their own in all seven languages', () => {
    const source = fs.readFileSync(TRANSLATIONS, 'utf8');
    const blocks = source.split(/\n {2}(?=\w\w: \{\n {4}ui: \{)/).slice(1);
    expect(blocks.map((b) => b.slice(0, 2))).toEqual(['en', 'ja', 'zh', 'ko', 'es', 'fr', 'de']);
    blocks.forEach((block) => {
      expect(block.match(/\n {6}sharedFolderPanel: /g)).toHaveLength(1);
      expect(block).toMatch(/\n {6}sharedFolderPanel: \{\n/);
      ['panelTitle', 'browse', 'colName', 'truncated', 'noFolderId', 'keptUserScripts'].forEach((key) => {
        expect(block).toMatch(new RegExp('\\n {8}' + key + ': "'));
      });
    });
  });
});

describe('shared folder page', () => {
  let panel;
  let pending;

  function listing(pathName, items) {
    return { success: true, path: pathName, page: 1, total: items.length, root_id: 'a'.repeat(32), items };
  }

  async function flush() {
    for (let i = 0; i < 10; i += 1) await Promise.resolve();
  }

  function respond(index, body) {
    pending[index].resolve({ ok: true, status: 200, json: async () => body });
  }

  beforeEach(() => {
    jest.useFakeTimers();
    jest.resetModules();
    document.body.innerHTML = `
      <div id="sharedFolderModal"></div>
      <div id="shared-folder-path"></div><span id="shared-folder-info"></span>
      <div id="shared-folder-status" style="display:none"></div>
      <table><tbody id="shared-folder-tbody"></tbody></table>
      <div id="shared-folder-pager-top" class="sf-pager"><button class="sf-prev"></button><span class="sf-page-label"></span>
        <button class="sf-next"></button><select class="sf-per-page"><option>100</option><option>200</option><option>500</option></select></div>
      <div id="shared-folder-pager" class="sf-pager"><button class="sf-prev"></button><span class="sf-page-label"></span>
        <button class="sf-next"></button></div>`;
    global.$id = (id) => document.getElementById(id);
    global.$on = (node, ev, fn) => node && node.addEventListener(ev, fn);
    window.bootstrap = { Modal: { getOrCreateInstance: () => ({ show() {} }) } };
    global.bootstrap = window.bootstrap;
    pending = [];
    global.fetch = jest.fn((url) => new Promise((resolve) => { pending.push({ url, resolve }); }));
    panel = require('../../docker/services/ruby/public/js/monadic/shared-folder-panel.js');
  });

  afterEach(() => {
    jest.useRealTimers();
    delete global.fetch;
  });

  it('keeps the folder it moved to when an older answer comes last', async () => {
    panel.open();                      // asks for the top
    panel.load('conversations');       // then moves on
    respond(1, listing('conversations', [{ name: 'c', path: 'conversations/c', kind: 'folder', size_status: 'complete', bytes: 1 }]));
    await flush();
    respond(0, listing('', [{ name: 'old', path: 'old', kind: 'file', size_status: 'complete', bytes: 1 }]));
    await flush();
    expect(panel._state().path).toBe('conversations');
    expect(document.getElementById('shared-folder-tbody').textContent).toContain('c');
    expect(document.getElementById('shared-folder-tbody').textContent).not.toContain('old');
  });

  it('lists everything again when the search box is emptied, by typing or by Esc', async () => {
    document.body.insertAdjacentHTML('beforeend', '<input id="shared-folder-search">');
    jest.resetModules();
    panel = require('../../docker/services/ruby/public/js/monadic/shared-folder-panel.js');
    const box = document.getElementById('shared-folder-search');
    panel.load('');
    box.value = 'zzz';
    box.dispatchEvent(new Event('input'));
    jest.advanceTimersByTime(300);
    expect(pending[pending.length - 1].url).toContain('q=zzz');
    box.value = '';
    box.dispatchEvent(new Event('search')); // Esc empties a search box with no input event
    jest.advanceTimersByTime(300);
    expect(pending[pending.length - 1].url).not.toContain('q=');
    box.value = 'abc';
    box.dispatchEvent(new Event('input'));
    box.value = '';                         // emptied again before the pause is over
    jest.advanceTimersByTime(300);
    expect(pending[pending.length - 1].url).not.toContain('q=');
  });

  it('opens a folder from its name and goes up with the up button', async () => {
    document.body.insertAdjacentHTML('beforeend', '<button id="shared-folder-up"></button>');
    jest.resetModules();
    panel = require('../../docker/services/ruby/public/js/monadic/shared-folder-panel.js');
    panel.load('');
    respond(0, listing('', [{ name: 'box', path: 'box', kind: 'folder', size_status: 'complete', bytes: 1 }]));
    await flush();
    expect(document.getElementById('shared-folder-up').style.display).toBe('none');
    document.querySelector('#shared-folder-tbody .sf-folder-link').click();
    expect(pending[1].url).toContain('path=box');
    respond(1, listing('box', []));
    await flush();
    expect(document.getElementById('shared-folder-up').style.display).toBe('');
    document.getElementById('shared-folder-up').click();
    expect(pending[2].url).toContain('path=&');
  });

  it('hides the pagers when one short page holds everything', async () => {
    panel.load('');
    respond(0, listing('', [{ name: 'a', path: 'a', kind: 'file', size_status: 'complete', bytes: 1 }]));
    await flush();
    document.querySelectorAll('.sf-pager').forEach((p) => expect(p.style.display).toBe('none'));
  });

  it('asks for nothing more once it is closed', async () => {
    panel.open();
    document.getElementById('sharedFolderModal').dispatchEvent(new Event('hidden.bs.modal'));
    respond(0, listing('', [{ name: 'big', path: 'big', kind: 'folder', size_status: 'pending' }]));
    await flush();
    jest.advanceTimersByTime(60000);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('asks for the sizes only while folders are being counted', async () => {
    panel.open();
    respond(0, listing('', [{ name: 'big', path: 'big', kind: 'folder', size_status: 'pending' }]));
    await flush();
    jest.advanceTimersByTime(2000);
    expect(pending[1].url).toMatch(/^\/api\/shared_folder\/sizes\?paths%5B%5D=big/);
    respond(1, { success: true, sizes: { big: { size_status: 'complete', bytes: 2048 } } });
    await flush();
    expect(document.getElementById('shared-folder-tbody').textContent).toContain('2.0 KB');
    jest.advanceTimersByTime(60000);
    expect(global.fetch).toHaveBeenCalledTimes(2);
  });

  it('gives the next page its own turns to ask for sizes', async () => {
    panel.open();
    respond(0, Object.assign(listing('', [{ name: 'a', path: 'a', kind: 'folder', size_status: 'pending' }]), { matched: 400, total: 400, per_page: 200 }));
    await flush();
    for (let i = 1; i <= 15; i += 1) {
      jest.advanceTimersByTime(2000);
      respond(i, { success: true, sizes: { a: { size_status: 'pending' } } });
      await flush();
    }
    expect(document.getElementById('shared-folder-tbody').textContent).toContain('not counted yet');
    panel.goToPage(2);
    expect(pending[16].url).toContain('page=2');
    respond(16, Object.assign(listing('', [{ name: 'b', path: 'b', kind: 'folder', size_status: 'pending' }]), { page: 2, matched: 400, total: 400, per_page: 200 }));
    await flush();
    jest.advanceTimersByTime(2000);
    expect(pending[17].url).toMatch(/paths%5B%5D=b/);
    expect(pending[17].url).not.toMatch(/paths%5B%5D=a/);
  });

  it('asks for the page asked for, in any order, with the page size chosen', async () => {
    panel._view({ sort: 'size', perPage: 100 });
    panel.open();
    expect(pending[0].url).toContain('per_page=100');
    respond(0, Object.assign(listing('', [{ name: 'a', path: 'a', kind: 'file', size_status: 'complete', bytes: 1 }]), { matched: 250, total: 250, per_page: 100 }));
    await flush();
    const labels = Array.from(document.querySelectorAll('.sf-page-label')).map((l) => l.textContent);
    expect(labels).toHaveLength(2);
    expect(labels[0]).toBe(labels[1]); // above and below show the same page
    expect(labels[0]).toContain('250');
    document.querySelectorAll('.sf-prev').forEach((b) => expect(b.disabled).toBe(true));
    document.querySelector('#shared-folder-pager .sf-next').click(); // the one below works too
    expect(pending[1].url).toContain('page=2');
    expect(pending[1].url).toContain('sort=size');
    respond(1, Object.assign(listing('', [{ name: 'b', path: 'b', kind: 'file', size_status: 'complete', bytes: 9 }]), { page: 2, matched: 250, total: 250, per_page: 100 }));
    await flush();
    expect(panel._state().items.map((i) => i.path)).toEqual(['b']);
    panel.goToPage(9); // past the last page: the last one
    expect(pending[2].url).toContain('page=3');
  });

  it('in size order, asks for the list again once every count is in', async () => {
    panel._view({ sort: 'size' });
    panel.open();
    respond(0, listing('', [
      { name: 'a', path: 'a', kind: 'folder', size_status: 'pending' },
      { name: 'b', path: 'b', kind: 'folder', size_status: 'pending' }
    ]));
    await flush();
    jest.advanceTimersByTime(2000);
    respond(1, { success: true, sizes: { a: { size_status: 'complete', bytes: 1 }, b: { size_status: 'complete', bytes: 100 } } });
    await flush();
    expect(pending[2].url).toMatch(/^\/api\/shared_folder\?/);
    expect(pending[2].url).toContain('sort=size');
    respond(2, listing('', [
      { name: 'b', path: 'b', kind: 'folder', size_status: 'complete', bytes: 100 },
      { name: 'a', path: 'a', kind: 'folder', size_status: 'complete', bytes: 1 }
    ]));
    await flush();
    jest.advanceTimersByTime(60000);
    expect(global.fetch).toHaveBeenCalledTimes(3);
    expect(panel._state().items.map((i) => i.path)).toEqual(['b', 'a']);
  });

  it('asks for at most 200 folders at once', async () => {
    const many = Array.from({ length: 250 }, (_, i) => ({ name: 'f' + i, path: 'f' + i, kind: 'folder', size_status: 'pending' }));
    panel.open();
    respond(0, Object.assign(listing('', many), { total: 250 }));
    await flush();
    jest.advanceTimersByTime(2000);
    expect((pending[1].url.match(/paths%5B%5D=/g) || []).length).toBe(200);
  });

  it('asks for folders named like object properties', async () => {
    const names = ['constructor', 'toString', '__proto__', 'plain'];
    panel.open();
    respond(0, listing('', names.map((n) => ({ name: n, path: n, kind: 'folder', size_status: 'pending' }))));
    await flush();
    jest.advanceTimersByTime(2000);
    names.forEach((n) => expect(pending[1].url).toContain('paths%5B%5D=' + n));
  });

  it('shows names as text', async () => {
    panel.open();
    respond(0, listing('', [{ name: '<img src=x onerror=alert(1)>', path: 'x', kind: 'file', size_status: 'complete', bytes: 1 }]));
    await flush();
    expect(document.querySelector('#shared-folder-tbody img')).toBeNull();
  });
});

describe('shared folder page: search, selection and trash', () => {
  let panel;
  let pending;

  const ROOT = 'a'.repeat(32);
  const testFile = { name: 'monadic-test-1-a.txt', path: 'monadic-test-1-a.txt', kind: 'file', size_status: 'complete', bytes: 1,
    classification: 'test_file', capabilities: { reveal: true, trash: true } };
  const kept = { name: 'scripts', path: 'scripts', kind: 'folder', size_status: 'complete', bytes: 1,
    classification: 'protected', protected_reason: 'user_scripts', capabilities: { reveal: true, trash: false } };
  const plain = { name: 'notes.txt', path: 'notes.txt', kind: 'file', size_status: 'complete', bytes: 1,
    classification: 'other', capabilities: { reveal: true, trash: true } };

  function listing(items) {
    return { success: true, path: '', page: 1, total: items.length, matched: items.length, root_id: ROOT, items };
  }

  async function flush() {
    for (let i = 0; i < 10; i += 1) await Promise.resolve();
  }

  function respond(index, body) {
    pending[index].resolve({ ok: true, status: 200, json: async () => body });
  }

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = `
      <div id="sharedFolderModal"></div>
      <div id="shared-folder-path"></div><span id="shared-folder-info"></span>
      <input id="shared-folder-search"><select id="shared-folder-sort"><option value="name"></option><option value="size"></option></select>
      <select id="shared-folder-filter"><option value=""></option><option value="test_file"></option></select>
      <span id="shared-folder-selection"></span>
      <button id="shared-folder-select-matching"></button>
      <button id="shared-folder-select-tests"></button>
      <button id="shared-folder-trash"></button>
      <div id="shared-folder-status" style="display:none"></div>
      <table><tbody id="shared-folder-tbody"></tbody></table>`;
    global.$id = (id) => document.getElementById(id);
    global.$on = (node, ev, fn) => node && node.addEventListener(ev, fn);
    window.bootstrap = { Modal: { getOrCreateInstance: () => ({ show() {} }) } };
    global.bootstrap = window.bootstrap;
    window.electronAPI = { trashSharedEntries: jest.fn(async (_root, paths) => ({ ok: true, results: paths.map((p) => ({ path: p, ok: true })) })) };
    pending = [];
    global.fetch = jest.fn((url) => new Promise((resolve) => { pending.push({ url, resolve }); }));
    panel = require('../../docker/services/ruby/public/js/monadic/shared-folder-panel.js');
  });

  afterEach(() => {
    delete global.fetch;
    delete window.electronAPI;
  });

  it('asks the server for the search, the order and the kind', async () => {
    panel._view({ q: 'notes', sort: 'size', cls: 'test_file' });
    panel.load('');
    expect(pending[0].url).toContain('q=notes');
    expect(pending[0].url).toContain('sort=size');
    expect(pending[0].url).toContain('classes%5B%5D=test_file');
  });

  it('selects only the test files that may go', async () => {
    panel.load('');
    respond(0, listing([testFile, kept, plain]));
    await flush();
    expect(document.querySelectorAll('#shared-folder-tbody input[type=checkbox]')).toHaveLength(0);
    panel.selectTests();
    expect(Array.from(panel._selected())).toEqual(['monadic-test-1-a.txt']);
    expect(document.getElementById('shared-folder-trash').disabled).toBe(false);
  });

  // Which rows are chosen, as the page shows them (null: a row that may not go).
  function chosen() {
    return Array.from(document.querySelectorAll('#shared-folder-tbody tr')).map((tr, n) =>
      (panel._state().items[n].capabilities.trash ? tr.classList.contains('sf-selected') : null));
  }

  function cell(index, column = 1) {
    return document.querySelectorAll('#shared-folder-tbody tr')[index].children[column];
  }

  function mouse(type, node, opts) {
    node.dispatchEvent(new MouseEvent(type, Object.assign({ bubbles: true, cancelable: true, button: 0 }, opts)));
  }

  function key(k, opts) {
    document.getElementById('shared-folder-tbody').dispatchEvent(new KeyboardEvent('keydown', Object.assign({ key: k, bubbles: true, cancelable: true }, opts)));
  }

  const click = (index, opts) => { mouse('mousedown', cell(index), opts); mouse('mouseup', document); };

  const file = (n) => ({ name: 'f' + n + '.txt', path: 'f' + n + '.txt', kind: 'file', size_status: 'complete', bytes: 1,
    classification: 'other', capabilities: { reveal: true, trash: true } });

  async function rows(items) {
    panel.load('');
    respond(0, listing(items));
    await flush();
  }

  it('a click chooses that row alone; Cmd/Ctrl+click adds or removes; Shift+click adds the range', async () => {
    await rows([file(0), file(1), file(2), file(3), file(4)]);
    click(1);
    expect(chosen()).toEqual([false, true, false, false, false]);
    click(3);
    expect(chosen()).toEqual([false, false, false, true, false]);
    click(0, { metaKey: true });
    expect(chosen()).toEqual([true, false, false, true, false]);
    click(3, { ctrlKey: true });
    expect(chosen()).toEqual([true, false, false, false, false]);
    click(2, { shiftKey: true }); // from the row clicked last (3), as a file manager does
    expect(chosen()).toEqual([true, false, true, true, false]);
    expect(document.getElementById('shared-folder-trash').title).toContain('(3)');
    panel.clearSelection();
    expect(chosen()).toEqual([false, false, false, false, false]);
    expect(Array.from(panel._selected())).toEqual([]);
  });

  it('a drag chooses the rows it passes now, skipping what is kept, and stops when released', async () => {
    await rows([file(0), file(1), kept, file(3), file(4)]);
    mouse('mousedown', cell(0), { clientY: 0 });
    mouse('mousemove', cell(4), { clientY: 40, buttons: 1 });
    mouse('mousemove', cell(3), { clientY: 30, buttons: 1 }); // back up: row 4 is no longer passed
    mouse('mouseup', document);
    mouse('mousemove', cell(4), { clientY: 50, buttons: 1 });
    expect(chosen()).toEqual([true, true, null, true, false]);
  });

  it('a click chooses one row even when the page moves under the still pointer', async () => {
    await rows([file(0), file(1), file(2)]);
    mouse('mousedown', cell(0), { clientX: 5, clientY: 5 });
    mouse('mousemove', cell(1), { clientX: 5, clientY: 5, buttons: 1 });
    mouse('mouseup', document);
    expect(chosen()).toEqual([true, false, false]);
  });

  it('ends a drag released outside the window', async () => {
    await rows([file(0), file(1), file(2)]);
    mouse('mousedown', cell(0), { clientY: 1 });
    mouse('mousemove', cell(2), { clientY: 30, buttons: 0 });
    expect(chosen()).toEqual([true, false, false]);
  });

  it('a click on a button in a row is the button\'s, not a choice', async () => {
    panel.load('');
    respond(0, Object.assign(listing([file(0)]), { chat_root: '/monadic/data' }));
    await flush();
    const button = document.querySelector('#shared-folder-tbody button');
    mouse('mousedown', button);
    expect(chosen()).toEqual([false]);
  });

  it('a row that may not go is never chosen, even by a click on it', async () => {
    await rows([kept, file(1)]);
    click(0);
    expect(panel._selected().size).toBe(0);
  });

  it('keeps the choice across pages and orders, and clears it when the search or a filter changes', async () => {
    panel.load('');
    respond(0, Object.assign(listing([file(0), file(1)]), { matched: 400, total: 400, per_page: 200 }));
    await flush();
    click(0);
    panel.goToPage(2);
    respond(1, Object.assign(listing([file(5)]), { page: 2, matched: 400, total: 400, per_page: 200 }));
    await flush();
    expect(Array.from(panel._selected())).toEqual(['f0.txt']);
    expect(document.getElementById('shared-folder-selection').textContent).toContain('1');
    const filter = document.getElementById('shared-folder-filter');
    filter.value = 'test_file';
    filter.dispatchEvent(new Event('change'));
    expect(panel._selected().size).toBe(0);
  });

  it('chooses every matching entry on every page, asked of the server with the same search and filters', async () => {
    panel._view({ q: 'f', cls: 'other' });
    panel.load('');
    respond(0, Object.assign(listing([file(0)]), { matched: 3, total: 3, per_page: 1 }));
    await flush();
    const every = document.getElementById('shared-folder-select-matching');
    expect(every.style.display).toBe('');
    every.click();
    const url = pending[1].url;
    expect(url).toMatch(/^\/api\/shared_folder\/matching\?/);
    expect(url).toContain('q=f');
    expect(url).toContain('classes%5B%5D=other');
    expect(url).not.toContain('page=');
    respond(1, { success: true, matched: 3, truncated: false, items: [
      { path: 'f0.txt', kind: 'file', bytes: 1 }, { path: 'f1.txt', kind: 'file', bytes: 2 }, { path: 'f2.txt', kind: 'file', bytes: 3 }] });
    await flush();
    expect(panel._selected().size).toBe(3);
    expect(document.getElementById('shared-folder-selection').textContent).toContain('3');
  });

  it('opens a folder or previews a file on a double-click or Enter', async () => {
    const folder = { name: 'sub', path: 'sub', kind: 'folder', size_status: 'pending', classification: 'other', capabilities: { reveal: true, trash: true } };
    await rows([folder, file(1)]);
    mouse('dblclick', cell(0));
    expect(pending[pending.length - 1].url).toContain('path=sub');
  });

  it('keys: arrows move and Shift extends, Cmd/Ctrl+A chooses all, Esc clears', async () => {
    await rows([file(0), file(1), file(2), file(3)]);
    key('ArrowDown');
    expect(chosen()).toEqual([true, false, false, false]);
    key('ArrowDown'); key('ArrowDown', { shiftKey: true });
    expect(chosen()).toEqual([false, true, true, false]);
    document.getElementById('sharedFolderModal').appendChild(document.getElementById('shared-folder-tbody').closest('table'));
    key('a', { metaKey: true }); // handled by the panel, wherever the focus is in it
    expect(chosen()).toEqual([true, true, true, true]);
    const esc = new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true });
    document.getElementById('shared-folder-tbody').dispatchEvent(esc);
    expect(chosen()).toEqual([false, false, false, false]);
    expect(esc.defaultPrevented).toBe(true);
  });

  it('asks the desktop app to move the chosen entries, then lists the folder again', async () => {
    panel.load('');
    respond(0, listing([testFile, plain]));
    await flush();
    panel.selectTests();
    document.getElementById('shared-folder-trash').click();
    await flush();
    expect(window.electronAPI.trashSharedEntries).toHaveBeenCalledWith(ROOT, ['monadic-test-1-a.txt']);
    expect(pending).toHaveLength(2);
    respond(1, listing([plain]));
    await flush();
    expect(Array.from(panel._selected())).toEqual([]);
  });

  it('keeps the list and the choice when the dialog of the desktop app is cancelled', async () => {
    window.electronAPI.trashSharedEntries = jest.fn(async () => ({ ok: false, cancelled: true, error: 'cancelled' }));
    panel.load('');
    respond(0, listing([testFile, plain]));
    await flush();
    panel.selectTests();
    document.getElementById('shared-folder-trash').click();
    await flush();
    expect(pending).toHaveLength(1);
    expect(Array.from(panel._selected())).toEqual(['monadic-test-1-a.txt']);
    expect(document.getElementById('shared-folder-status').textContent).toBe('');
  });

  it('says which entries could not be moved', async () => {
    window.electronAPI.trashSharedEntries = jest.fn(async () => ({ ok: false, results: [{ path: 'notes.txt', ok: false, error: 'not to be removed' }] }));
    panel.load('');
    respond(0, listing([plain]));
    await flush();
    const row = document.querySelector('#shared-folder-tbody tr td:nth-child(2)');
    row.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0 }));
    document.getElementById('shared-folder-trash').click();
    await flush();
    respond(1, listing([plain]));
    await flush();
    expect(document.getElementById('shared-folder-status').textContent).toContain('notes.txt (not to be removed)');
    expect(Array.from(panel._selected())).toEqual(['notes.txt']); // stays chosen, to try again
  });

  it('starts one move at a time, and tells what was not tried', async () => {
    let finish;
    window.electronAPI.trashSharedEntries = jest.fn(() => new Promise((r) => { finish = r; }));
    await rows([file(0), file(1)]);
    click(0); click(1, { metaKey: true });
    const trash = document.getElementById('shared-folder-trash');
    trash.click();
    expect(trash.disabled).toBe(true);
    panel.trashSelected();
    expect(window.electronAPI.trashSharedEntries).toHaveBeenCalledTimes(1);
    finish({ ok: false, results: [{ path: 'f0.txt', ok: true }, { path: 'f1.txt', ok: false, not_tried: true, error: 'not tried' }] });
    await flush();
    respond(1, listing([file(1)]));
    await flush();
    expect(Array.from(panel._selected())).toEqual(['f1.txt']);
    expect(document.getElementById('shared-folder-status').textContent).toContain('1');
    expect(trash.disabled).toBe(false);
  });

  it('a late "choose all" does not bring back a choice cleared after it was asked', async () => {
    await rows([file(0)]);
    panel.selectMatching();
    panel.clearSelection();
    respond(1, { success: true, items: [{ path: 'hidden.txt', kind: 'file', bytes: 1, size_status: 'complete' }], truncated: false });
    await flush();
    expect(Array.from(panel._selected())).toEqual([]);
  });

  it('a late "choose all" does not undo "choose all shown" pressed after it', async () => {
    document.body.insertAdjacentHTML('beforeend', '<button id="shared-folder-select-all"></button>');
    await rows([file(0)]);
    click(0);
    panel.selectMatching();
    panel.selectAllShown(); // every shown one was chosen: this clears them
    expect(Array.from(panel._selected())).toEqual([]);
    respond(1, { success: true, items: [{ path: 'f0.txt', kind: 'file', bytes: 1, size_status: 'complete' }, { path: 'y.txt', kind: 'file', bytes: 1, size_status: 'complete' }], truncated: false });
    await flush();
    expect(Array.from(panel._selected())).toEqual([]);
  });

  it('a Shift range does not start from a row of another page', async () => {
    panel.load('');
    respond(0, Object.assign(listing([file(0), file(1), file(2)]), { matched: 400, total: 400, per_page: 200 }));
    await flush();
    click(1);
    panel.goToPage(2);
    respond(1, Object.assign(listing([file(5), file(6), file(7)]), { page: 2, matched: 400, total: 400, per_page: 200 }));
    await flush();
    key('ArrowDown', { shiftKey: true });
    expect(Array.from(panel._selected()).sort()).toEqual(['f1.txt', 'f5.txt']);
  });

  it('shows the row the keyboard is on, also one that cannot be selected', async () => {
    await rows([file(0), kept, file(2)]);
    key('ArrowDown');
    key('ArrowDown');
    const trs = document.querySelectorAll('#shared-folder-tbody tr');
    expect(trs[1].classList.contains('sf-cursor')).toBe(true);
    expect(trs[1].getAttribute('aria-current')).toBe('true');
    expect(trs[0].classList.contains('sf-cursor')).toBe(false);
  });

  it('a key on a button in a row is left to the button', async () => {
    await rows([file(0), file(1)]);
    const btn = document.createElement('button');
    cell(0).appendChild(btn);
    btn.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
    expect(chosen()).toEqual([false, false]);
  });
});

describe('shared folder panel: preview, choosing all, age and copying', () => {
  let panel;
  let pending;
  const ROOT = 'a'.repeat(32);
  const entry = (name, extra) => Object.assign({ name, path: name, kind: 'file', size_status: 'complete', bytes: 1024,
    classification: 'other', capabilities: { reveal: true, trash: true } }, extra);

  function listing(items) {
    return { success: true, path: '', page: 1, total: items.length, matched: items.length, root_id: ROOT,
      chat_root: '/monadic/data', items };
  }
  async function flush() { for (let i = 0; i < 10; i += 1) await Promise.resolve(); }
  function respond(index, body, ok = true) {
    pending[index].resolve({ ok, status: ok ? 200 : 404, json: async () => body });
  }

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = `
      <div id="sharedFolderModal"></div>
      <div id="shared-folder-path"></div><span id="shared-folder-info"></span>
      <input id="shared-folder-search"><select id="shared-folder-sort"><option value="name"></option></select>
      <select id="shared-folder-filter"><option value=""></option></select>
      <select id="shared-folder-age"><option value=""></option><option value="90"></option></select>
      <span id="shared-folder-selection"></span>
      <button id="shared-folder-select-tests"></button>
      <button id="shared-folder-trash"></button>
      <div id="shared-folder-status" style="display:none"></div>
      <div id="shared-folder-preview" style="display:none"><span id="shared-folder-preview-name"></span>
        <span id="shared-folder-preview-count"></span><button id="shared-folder-preview-close"></button>
        <button id="shared-folder-preview-prev"></button><div id="shared-folder-preview-body"></div>
        <button id="shared-folder-preview-next"></button></div>
      <button id="shared-folder-select-all"></button>
      <table><thead><tr><th></th></tr></thead>
      <tbody id="shared-folder-tbody"></tbody></table>`;
    global.$id = (id) => document.getElementById(id);
    global.$on = (node, ev, fn) => node && node.addEventListener(ev, fn);
    window.bootstrap = { Modal: { getOrCreateInstance: () => ({ show() {} }) } };
    global.bootstrap = window.bootstrap;
    window.electronAPI = { trashSharedEntries: jest.fn(), writeClipboard: jest.fn(async () => true) };
    pending = [];
    global.fetch = jest.fn((url, opts) => new Promise((resolve) => { pending.push({ url, opts, resolve }); }));
    panel = require('../../docker/services/ruby/public/js/monadic/shared-folder-panel.js');
  });

  afterEach(() => {
    delete global.fetch;
    delete window.electronAPI;
  });

  async function shown(items) {
    panel.load('');
    respond(0, listing(items));
    await flush();
  }

  it('shows a text file as text, never as markup', async () => {
    await shown([entry('page.html', { preview: 'text' })]);
    document.querySelector('#shared-folder-tbody tr td').dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
    expect(pending[1].url).toBe('/api/shared_folder/text?path=page.html');
    respond(1, { success: true, text: '<img src=x onerror=alert(1)>', truncated: false, file_bytes: 28, shown_bytes: 28 });
    await flush();
    const body = document.getElementById('shared-folder-preview-body');
    expect(body.querySelector('pre').textContent).toBe('<img src=x onerror=alert(1)>');
    expect(body.querySelector('img')).toBeNull();
    expect(document.getElementById('shared-folder-preview').style.display).toBe('');
  });

  it('shows media from the file route, and an answer for an earlier file is dropped', async () => {
    await shown([entry('a.txt', { preview: 'text' }), entry('dir/b c.png', { name: 'b c.png', preview: 'image' })]);
    panel.openPreview(entry('a.txt', { preview: 'text' }));
    panel.openPreview(entry('dir/b c.png', { preview: 'image' }));
    respond(1, { success: true, text: 'late', truncated: false, file_bytes: 4, shown_bytes: 4 });
    await flush();
    const body = document.getElementById('shared-folder-preview-body');
    expect(body.querySelector('pre')).toBeNull();
    expect(body.querySelector('img').getAttribute('src')).toBe('/api/shared_folder/file?path=dir%2Fb+c.png');
    expect(pending[1].opts.signal.aborted).toBe(true);
  });

  it('plays nothing on its own, and stops the media when closed', async () => {
    await shown([entry('clip.mp4', { preview: 'video' })]);
    panel.openPreview(entry('clip.mp4', { preview: 'video' }));
    const video = document.querySelector('#shared-folder-preview-body video');
    expect(video.autoplay).toBe(false);
    expect(video.controls).toBe(true);
    video.pause = jest.fn();
    video.load = jest.fn();
    document.getElementById('shared-folder-preview-close').click();
    expect(video.pause).toHaveBeenCalled();
    expect(video.getAttribute('src')).toBeNull();
    expect(document.getElementById('shared-folder-preview').style.display).toBe('none');
  });

  it('moves to the files before and after on the page with the arrows, and Esc closes only the preview', async () => {
    await shown([entry('a.png', { preview: 'image' }), entry('notes'), entry('b.pdf', { preview: 'pdf' }), entry('c.mp4', { preview: 'video' })]);
    panel.openPreview(entry('b.pdf', { preview: 'pdf' }));
    expect(document.getElementById('shared-folder-preview-count').textContent).toBe('2 / 3');
    const key = (k) => { const e = new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }); document.body.dispatchEvent(e); return e; };
    key('ArrowRight');
    expect(document.getElementById('shared-folder-preview-name').textContent).toBe('c.mp4');
    expect(document.getElementById('shared-folder-preview-next').disabled).toBe(true);
    key('ArrowLeft'); key('ArrowLeft'); // past "notes", which cannot be previewed
    expect(document.getElementById('shared-folder-preview-name').textContent).toBe('a.png');
    expect(panel._selected().has('a.png')).toBe(true); // the row follows
    const modal = document.getElementById('sharedFolderModal');
    const closedPanel = jest.fn();
    modal.addEventListener('keydown', closedPanel);
    const esc = key('Escape');
    expect(esc.defaultPrevented).toBe(true);
    expect(document.getElementById('shared-folder-preview').style.display).toBe('none');
    expect(closedPanel).not.toHaveBeenCalled();
  });

  it('shows a spinner over the panel while entries are moved, and takes no other action', async () => {
    document.body.insertAdjacentHTML('afterbegin', '<div id="content"><div id="behind"></div><div id="shared-folder-busy" style="display:none"></div></div>');
    let finish;
    window.electronAPI.trashSharedEntries = jest.fn(() => new Promise((r) => { finish = r; }));
    await shown([entry('a.txt')]);
    document.querySelector('#shared-folder-tbody tr td:nth-child(2)').dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0 }));
    panel.trashSelected();
    expect(document.getElementById('shared-folder-busy').style.display).toBe('');
    expect(document.getElementById('behind').hasAttribute('inert')).toBe(true);
    const hide = new Event('hide.bs.modal', { cancelable: true });
    document.getElementById('sharedFolderModal').dispatchEvent(hide);
    expect(hide.defaultPrevented).toBe(true); // the panel stays open
    finish({ ok: true, results: [{ path: 'a.txt', ok: true }] });
    await flush();
    expect(document.getElementById('shared-folder-busy').style.display).toBe('none');
    expect(document.getElementById('behind').hasAttribute('inert')).toBe(false);
    const later = new Event('hide.bs.modal', { cancelable: true });
    document.getElementById('sharedFolderModal').dispatchEvent(later);
    expect(later.defaultPrevented).toBe(false);
  });

  it('Cmd/Ctrl+A in the panel chooses all shown, but in a field selects its text', async () => {
    await shown([entry('a.txt'), entry('b.txt')]);
    const modal = document.getElementById('sharedFolderModal');
    const inPanel = new KeyboardEvent('keydown', { key: 'a', metaKey: true, bubbles: true, cancelable: true });
    modal.dispatchEvent(inPanel);
    expect(inPanel.defaultPrevented).toBe(true); // not the text of the page
    expect(Array.from(panel._selected()).sort()).toEqual(['a.txt', 'b.txt']);
    // The desktop app's Edit menu selects the page's text just after: taken back.
    window.getSelection().selectAllChildren(document.body);
    document.dispatchEvent(new Event('selectionchange'));
    expect(window.getSelection().rangeCount).toBe(0);
    panel.clearSelection();
    const field = document.createElement('input');
    modal.appendChild(field);
    const inField = new KeyboardEvent('keydown', { key: 'a', ctrlKey: true, bubbles: true, cancelable: true });
    field.dispatchEvent(inField);
    expect(inField.defaultPrevented).toBe(false);
    expect(Array.from(panel._selected())).toEqual([]);
  });

  it('leaves out folders when choosing all, if asked to', async () => {
    document.body.insertAdjacentHTML('beforeend', '<div id="shared-folder-files-only-wrap"><input type="checkbox" id="shared-folder-files-only"></div><button id="shared-folder-select-matching"></button>');
    const folder = entry('box', { kind: 'folder' });
    panel.load('');
    respond(0, Object.assign(listing([entry('a.txt'), folder]), { matched: 300, total: 300 }));
    await flush();
    const box = document.getElementById('shared-folder-files-only');
    box.checked = true; // read when choosing (the box is added after the panel was set up here)
    document.getElementById('shared-folder-select-all').click();
    expect(document.getElementById('shared-folder-select-matching').title).toContain('300');
    expect(Array.from(panel._selected())).toEqual(['a.txt']);
    panel.clearSelection();
    document.getElementById('sharedFolderModal').dispatchEvent(new KeyboardEvent('keydown', { key: 'a', metaKey: true, bubbles: true, cancelable: true }));
    expect(Array.from(panel._selected())).toEqual(['a.txt']);
    panel.clearSelection();
    panel.selectMatching();
    respond(1, { success: true, items: [{ path: 'a.txt', kind: 'file' }, { path: 'box', kind: 'folder' }, { path: 'far/b.txt', kind: 'file' }], truncated: false });
    await flush();
    expect(Array.from(panel._selected()).sort()).toEqual(['a.txt', 'far/b.txt']);
    // A folder can still be chosen by itself.
    document.querySelectorAll('#shared-folder-tbody tr')[1].children[1].dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0, metaKey: true }));
    expect(panel._selected().has('box')).toBe(true);
  });

  it('keeps the keys and the focus in the preview while it is shown', async () => {
    document.body.insertAdjacentHTML('afterbegin', '<div id="content"><div id="behind"><input id="field"></div></div>');
    const content = document.getElementById('content');
    content.appendChild(document.getElementById('shared-folder-preview'));
    await shown([entry('a.png', { preview: 'image' }), entry('b.png', { preview: 'image' })]);
    const field = document.getElementById('field');
    field.focus();
    panel.openPreview(entry('a.png', { preview: 'image' }));
    expect(document.getElementById('behind').hasAttribute('inert')).toBe(true);
    expect(document.activeElement.id).toBe('shared-folder-preview-close');
    const right = new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true });
    field.dispatchEvent(right);
    expect(right.defaultPrevented).toBe(false);
    expect(document.getElementById('shared-folder-preview-name').textContent).toBe('a.png');
    panel.openPreview(entry('b.png', { preview: 'image' })); // stepping keeps the overlay as it is
    expect(document.getElementById('behind').hasAttribute('inert')).toBe(true);
    panel.closePreview();
    expect(document.getElementById('behind').hasAttribute('inert')).toBe(false);
    expect(document.activeElement.id).toBe('field');
  });

  it('a search typed just before the panel closes is not sent', async () => {
    jest.useFakeTimers();
    try {
      await shown([entry('a.txt')]);
      const box = document.getElementById('shared-folder-search');
      box.value = 'new';
      box.dispatchEvent(new Event('input'));
      document.getElementById('sharedFolderModal').dispatchEvent(new Event('hidden.bs.modal'));
      jest.advanceTimersByTime(1000);
      expect(pending).toHaveLength(1);
    } finally {
      jest.useRealTimers();
    }
  });

  it('a search still waiting goes with a move to another folder', async () => {
    await shown([entry('a.txt')]);
    const box = document.getElementById('shared-folder-search');
    box.value = 'new';
    box.dispatchEvent(new Event('input'));
    panel.load('box');
    expect(pending[1].url).toContain('path=box');
    expect(pending[1].url).toContain('q=new');
    await new Promise((r) => setTimeout(r, 400));
    expect(pending).toHaveLength(2); // the waiting search does not undo the move
  });

  it('opens and closes with Space on the chosen row, as Quick Look does', async () => {
    await shown([entry('a.png', { preview: 'image' })]);
    const list = document.getElementById('shared-folder-tbody');
    list.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
    list.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true, cancelable: true }));
    expect(document.getElementById('shared-folder-preview').style.display).toBe('');
    document.body.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true, cancelable: true }));
    expect(document.getElementById('shared-folder-preview').style.display).toBe('none');
  });

  it('frames a PDF without a sandbox attribute, so the viewer can open it', async () => {
    await shown([entry('doc.pdf', { preview: 'pdf' })]);
    panel.openPreview(entry('doc.pdf', { preview: 'pdf' }));
    const frame = document.querySelector('#shared-folder-preview-body iframe');
    expect(frame.getAttribute('src')).toBe('/api/shared_folder/file?path=doc.pdf');
    expect(frame.hasAttribute('sandbox')).toBe(false);
  });

  it('chooses every entry shown that may go, and tells how many and how much', async () => {
    const kept = entry('scripts', { kind: 'folder', capabilities: { reveal: true, trash: false } });
    const pendingFolder = entry('big', { kind: 'folder', size_status: 'pending', bytes: undefined });
    await shown([entry('a.txt'), entry('b.txt'), kept, pendingFolder]);
    const all = document.getElementById('shared-folder-select-all');
    all.click();
    expect(Array.from(panel._selected()).sort()).toEqual(['a.txt', 'b.txt', 'big']);
    expect(document.getElementById('shared-folder-selection').textContent).toContain('3');
    expect(document.getElementById('shared-folder-selection').textContent).toContain('≥');
    expect(document.getElementById('shared-folder-selection').style.visibility).toBe('visible');
    all.click();
    expect(panel._selected().size).toBe(0);
    expect(document.getElementById('shared-folder-selection').style.visibility).toBe('hidden');
  });

  it('asks the server for entries not modified in the chosen days, from the top', async () => {
    const age = document.getElementById('shared-folder-age');
    age.value = '90';
    age.dispatchEvent(new Event('change'));
    expect(pending[0].url).toContain('older_than_days=90');
  });

  it('names each row button after its item, and keeps the focus on it when the list is drawn again', async () => {
    await shown([entry('a.txt'), entry('b.txt')]);
    const copyB = document.querySelectorAll('#shared-folder-tbody tr')[1].querySelector('[data-action="copy"]');
    expect(copyB.getAttribute('aria-label')).toContain('b.txt');
    copyB.focus();
    panel.selectAllShown(); // draws the rows anew
    const again = document.querySelectorAll('#shared-folder-tbody tr')[1].querySelector('[data-action="copy"]');
    expect(again).not.toBe(copyB);
    expect(document.activeElement).toBe(again);
  });

  it('copies the path the chat uses, and says so only when the copy worked', async () => {
    await shown([entry('notes/a b.txt', { name: 'a b.txt' })]);
    const button = document.querySelector('#shared-folder-tbody .fa-copy').closest('button');
    await panel.copyPath(entry('notes/a b.txt'), button);
    expect(window.electronAPI.writeClipboard).toHaveBeenCalledWith('/monadic/data/notes/a b.txt');
    expect(button.querySelector('i').className).toBe('fa-solid fa-check');
    expect(button.className).not.toContain('btn-success');

    window.electronAPI.writeClipboard = jest.fn(async () => false);
    await panel.copyPath(entry('x.txt'), null);
    expect(document.getElementById('shared-folder-status').textContent).toContain('/monadic/data/x.txt');
  });
});
