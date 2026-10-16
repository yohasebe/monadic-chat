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
      <div id="shared-folder-error" style="display:none"></div>
      <table><tbody id="shared-folder-tbody"></tbody></table>
      <button id="shared-folder-more"></button>`;
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

  it('gives a page added later its own turns to ask for sizes', async () => {
    panel.open();
    respond(0, listing('', [{ name: 'a', path: 'a', kind: 'folder', size_status: 'pending' }]).valueOf());
    await flush();
    for (let i = 1; i <= 15; i += 1) {
      jest.advanceTimersByTime(2000);
      respond(i, { success: true, sizes: { a: { size_status: 'pending' } } });
      await flush();
    }
    expect(document.getElementById('shared-folder-tbody').textContent).toContain('not counted yet');
    const more = Object.assign(listing('', [{ name: 'b', path: 'b', kind: 'folder', size_status: 'pending' }]), { page: 2 });
    panel.loadMore();
    respond(16, more);
    await flush();
    jest.advanceTimersByTime(2000);
    expect(pending[17].url).toMatch(/paths%5B%5D=b/);
    expect(pending[17].url).not.toMatch(/paths%5B%5D=a/);
  });

  it('in size order, asks for more from the top rather than for the next page', async () => {
    panel._view({ sort: 'size' });
    panel.open();
    respond(0, Object.assign(listing('', [{ name: 'a', path: 'a', kind: 'file', size_status: 'complete', bytes: 1 }]), { matched: 2, total: 2, per_page: 200 }));
    await flush();
    panel.loadMore();
    expect(pending[1].url).toContain('page=1');
    expect(pending[1].url).toContain('per_page=201');
    respond(1, Object.assign(listing('', [
      { name: 'b', path: 'b', kind: 'file', size_status: 'complete', bytes: 9 },
      { name: 'a', path: 'a', kind: 'file', size_status: 'complete', bytes: 1 }
    ]), { matched: 2, total: 2, per_page: 201 }));
    await flush();
    expect(panel._state().items.map((i) => i.path)).toEqual(['b', 'a']);
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

  it('in size order, stops at what one request lists and says so', async () => {
    panel._view({ sort: 'size' });
    panel.open();
    const many = Array.from({ length: 1000 }, (_, i) => ({ name: 'f' + i, path: 'f' + i, kind: 'file', size_status: 'complete', bytes: i }));
    respond(0, Object.assign(listing('', many), { matched: 1200, total: 1200, per_page: 1000 }));
    await flush();
    expect(document.getElementById('shared-folder-more').style.display).toBe('none');
    expect(document.getElementById('shared-folder-info').textContent).toContain('up to 1,000 entries');
    panel.loadMore();
    expect(global.fetch).toHaveBeenCalledTimes(1);
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
      <button id="shared-folder-select-tests"></button>
      <button id="shared-folder-trash"><span id="shared-folder-trash-label"></span></button>
      <div id="shared-folder-confirm" class="d-none"><span id="shared-folder-confirm-text"></span>
        <button id="shared-folder-confirm-yes"></button><button id="shared-folder-confirm-no"></button></div>
      <div id="shared-folder-error" style="display:none"></div>
      <table><tbody id="shared-folder-tbody"></tbody></table>
      <button id="shared-folder-more"></button>`;
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

  it('selects only the test files that may go, and offers no box for what is kept', async () => {
    panel.load('');
    respond(0, listing([testFile, kept, plain]));
    await flush();
    expect(document.querySelectorAll('#shared-folder-tbody input[type=checkbox]')).toHaveLength(2);
    panel.selectTests();
    expect(Array.from(panel._selected())).toEqual(['monadic-test-1-a.txt']);
    expect(document.getElementById('shared-folder-trash').disabled).toBe(false);
  });

  it('moves the chosen entries only after the confirmation, then lists the folder again', async () => {
    panel.load('');
    respond(0, listing([testFile, plain]));
    await flush();
    panel.selectTests();
    document.getElementById('shared-folder-trash').click();
    expect(document.getElementById('shared-folder-confirm').classList.contains('d-none')).toBe(false);
    expect(window.electronAPI.trashSharedEntries).not.toHaveBeenCalled();
    document.getElementById('shared-folder-confirm-yes').click();
    await flush();
    expect(window.electronAPI.trashSharedEntries).toHaveBeenCalledWith(ROOT, ['monadic-test-1-a.txt']);
    expect(pending).toHaveLength(2);
    respond(1, listing([plain]));
    await flush();
    expect(Array.from(panel._selected())).toEqual([]);
  });

  it('says which entries could not be moved', async () => {
    window.electronAPI.trashSharedEntries = jest.fn(async () => ({ ok: false, results: [{ path: 'notes.txt', ok: false, error: 'not to be removed' }] }));
    panel.load('');
    respond(0, listing([plain]));
    await flush();
    document.querySelector('#shared-folder-tbody input[type=checkbox]').click();
    document.getElementById('shared-folder-trash').click();
    document.getElementById('shared-folder-confirm-yes').click();
    await flush();
    respond(1, listing([plain]));
    await flush();
    expect(document.getElementById('shared-folder-error').textContent).toContain('notes.txt (not to be removed)');
  });
});
