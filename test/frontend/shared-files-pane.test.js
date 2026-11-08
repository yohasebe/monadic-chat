/**
 * @jest-environment jsdom
 */
// The Shared folder pane of the side column: one folder as a list, read
// when the pane comes into view, a file the work screen shows opened there,
// and the window for the rest.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);
const flush = async () => { for (let i = 0; i < 5; i += 1) await new Promise((r) => setTimeout(r, 0)); };

describe('SharedFilesPane', () => {
  let pending;
  let paneShown;
  let pane;

  function listing(at, items, extra = {}) {
    return Object.assign({ success: true, path: at, page: 1, total: items.length, matched: items.length, items }, extra);
  }
  const file = (name, preview = 'text', at = '') => ({ name, path: at ? `${at}/${name}` : name, kind: 'file', preview });
  const folder = (name) => ({ name, path: name, kind: 'folder' });
  const respond = (i, body) => pending[i].resolve({ ok: true, status: 200, json: () => Promise.resolve(body) });
  const names = () => Array.from(document.querySelectorAll('#sfp-list .sfp-label')).map((n) => n.textContent);
  const show = () => { paneShown = true; document.dispatchEvent(new Event('layoutchange')); };
  const hide = () => { paneShown = false; document.dispatchEvent(new Event('layoutchange')); };

  beforeEach(() => {
    jest.resetModules();
    pending = [];
    paneShown = false;
    global.fetch = jest.fn((url, opts) => new Promise((resolve) => { pending.push({ url, opts, resolve }); }));
    document.body.innerHTML =
      '<div id="shared-files-pane">' +
      '<button id="sfp-up"></button><span id="sfp-where"></span><button id="sfp-refresh"></button><button id="sfp-all"></button>' +
      '<input id="sfp-search"><div id="sfp-status" hidden></div><ul id="sfp-list"></ul><button id="sfp-more" hidden></button>' +
      '</div>';
    window.LayoutController = { selectedPane: () => (paneShown ? 'files' : 'settings'), isMenuHidden: () => false };
    window.Workbench = { openFile: jest.fn() };
    window.SharedFolderPanel = {
      open: jest.fn(),
      workScreenShows: (item) => item.kind === 'file' && ['text', 'pdf', 'image'].includes(item.preview),
      kindIcon: () => 'fa-regular fa-file'
    };
    require(js('monadic/dom-helpers.js'));
    pane = require(js('monadic/shared-files-pane.js'));
  });

  afterEach(() => {
    delete global.fetch;
    jest.useRealTimers();
  });

  test('reads the folder when the pane comes into view, not on every layout change', async () => {
    document.dispatchEvent(new Event('layoutchange'));
    expect(pending).toHaveLength(0);
    show();
    expect(pending).toHaveLength(1);
    expect(pending[0].url).toContain('/api/shared_folder?path=&page=1&per_page=50');
    document.dispatchEvent(new Event('layoutchange'));
    expect(pending).toHaveLength(1);
    respond(0, listing('', [folder('box'), file('notes.txt')]));
    await flush();
    expect(names()).toEqual(['box', 'notes.txt']);
    hide();
    show();
    expect(pending).toHaveLength(2);
  });

  test('opens a folder and goes up again', async () => {
    show();
    respond(0, listing('', [folder('box')]));
    await flush();
    expect(document.getElementById('sfp-up').disabled).toBe(true);
    document.querySelector('#sfp-list .sfp-name').click();
    expect(pending[1].url).toContain('path=box');
    respond(1, listing('box', [file('a.pdf', 'pdf', 'box')]));
    await flush();
    expect(document.getElementById('sfp-where').textContent).toBe('box');
    expect(document.getElementById('sfp-up').disabled).toBe(false);
    document.getElementById('sfp-up').click();
    expect(pending[2].url).toContain('path=&');
  });

  test('opens a file the work screen shows there, from its name or its button; any other in the window', async () => {
    show();
    respond(0, listing('', [folder('box')]));
    await flush();
    document.querySelector('#sfp-list .sfp-name').click();
    respond(1, listing('box', [file('notes.txt', 'text', 'box'), file('song.zip', null, 'box')]));
    await flush();
    const rows = document.querySelectorAll('#sfp-list .sfp-row');
    rows[0].querySelector('.sfp-name').click();
    rows[0].querySelector('.sfp-open').click();
    expect(window.Workbench.openFile.mock.calls).toEqual([['box/notes.txt'], ['box/notes.txt']]);
    expect(rows[1].querySelector('.sfp-open')).toBeNull();
    rows[1].querySelector('.sfp-name').click();
    expect(window.Workbench.openFile).toHaveBeenCalledTimes(2);
    expect(window.SharedFolderPanel.open).toHaveBeenCalledWith({ path: 'box', q: 'song.zip' });
  });

  test('keeps showing, and acting on, the folder shown when another cannot be read', async () => {
    show();
    respond(0, listing('', [folder('box'), file('a.txt')]));
    await flush();
    document.querySelector('#sfp-list .sfp-name').click();
    pending[1].resolve({ ok: false, status: 500, json: () => Promise.resolve({ success: false, error: 'x' }) });
    await flush();
    expect(names()).toEqual(['box', 'a.txt']);
    expect(document.getElementById('sfp-where').textContent).toBe('Shared folder');
    expect(document.getElementById('sfp-status').textContent).toContain('could not be read');
    document.getElementById('sfp-all').click();
    expect(window.SharedFolderPanel.open).toHaveBeenCalledWith({ path: '', q: '' });
    document.getElementById('sfp-refresh').click();
    expect(pending[2].url).toContain('path=&');
  });

  test('gives the window the search as typed, before its pause is over', async () => {
    jest.useFakeTimers();
    show();
    const box = document.getElementById('sfp-search');
    box.value = 'draft';
    box.dispatchEvent(new Event('input'));
    document.getElementById('sfp-all').click();
    expect(window.SharedFolderPanel.open).toHaveBeenCalledWith({ path: '', q: 'draft' });
    jest.advanceTimersByTime(1000);
    expect(pending).toHaveLength(1);
  });

  test('adds the next page with Show more, and drops an answer to an older request', async () => {
    show();
    respond(0, listing('', [file('a.txt')], { matched: 120, total: 120 }));
    await flush();
    const more = document.getElementById('sfp-more');
    expect(more.hidden).toBe(false);
    more.click();
    expect(pending[1].url).toContain('page=2');
    // The folder changes before the second page comes.
    document.getElementById('sfp-refresh').click();
    respond(1, listing('', [file('late.txt')], { page: 2, matched: 120 }));
    respond(2, listing('', [file('b.txt')], { matched: 1 }));
    await flush();
    expect(names()).toEqual(['b.txt']);
    expect(more.hidden).toBe(true);
  });

  test('searches the names after a pause, and offers to clear a search that finds nothing', async () => {
    jest.useFakeTimers();
    show();
    const box = document.getElementById('sfp-search');
    box.value = 'zzz';
    box.dispatchEvent(new Event('input'));
    jest.advanceTimersByTime(300);
    expect(pending[1].url).toContain('q=zzz');
    jest.useRealTimers();
    respond(0, listing('', [file('old.txt')]));
    respond(1, listing('', [], { total: 4 }));
    await flush();
    const status = document.getElementById('sfp-status');
    expect(status.hidden).toBe(false);
    expect(status.textContent).toContain('No names match');
    status.querySelector('.sfp-clear').click();
    expect(box.value).toBe('');
    expect(pending[2].url).not.toContain('q=');
  });

  test('opens the window on the same folder and search with Show all', async () => {
    show();
    respond(0, listing('', [folder('box')]));
    await flush();
    document.querySelector('#sfp-list .sfp-name').click();
    respond(1, listing('box', []));
    await flush();
    document.getElementById('sfp-all').click();
    expect(window.SharedFolderPanel.open).toHaveBeenCalledWith({ path: 'box', q: '' });
  });

  test('says when the folder could not be read', async () => {
    show();
    pending[0].resolve({ ok: false, status: 500, json: () => Promise.resolve({ success: false, error: 'x' }) });
    await flush();
    expect(document.getElementById('sfp-status').textContent).toContain('could not be read');
  });
});
