/**
 * @jest-environment jsdom
 */
// The workbench in the work screen pane: each image is shown there with its
// path in the shared folder, "Save as…" (the desktop app) or "Download" (a
// browser), and a × that takes it off the workbench. An image whose file
// changed or is gone is not shown; the pane says which. The conversation
// keeps one line of text per image the message made, from its record. A new
// image is brought forward without opening a column the user hid or taking
// the pane while they type.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

describe('Workbench', () => {
  let sent;
  let messages;
  let layout;

  const PATH = 'conversations/20261106-090000_image-generator_w_aaaaaaaaaaaaaaaa/artifacts/20261106-091233_cat.png';

  function card(mid) {
    const el = document.createElement('div');
    el.id = mid;
    el.innerHTML = '<div class="card-body"><div class="card-text"><p>done</p></div></div>';
    document.getElementById('discourse').appendChild(el);
    return el;
  }

  function item(overrides = {}) {
    return Object.assign({
      id: 'i_1', kind: 'image', actor: 'agent', mid: 'm-1', artifact_id: 'r_1', name: '20261106-091233_cat.png', path: PATH,
      sha256: 'a'.repeat(64), status: 'ok'
    }, overrides);
  }

  // What was sent, without the number each selection carries.
  function payloads() {
    return sent.map((x) => {
      const { seq, ...rest } = x.payload;
      return rest;
    });
  }

  // The item the pane shows, or null.
  // The user writes in the message box (focus and text).
  function writeMessage() {
    const box = document.getElementById('message');
    box.value = 'draft';
    box.focus();
  }

  function shown() {
    const pane = document.getElementById('workbench-view');
    return pane && !pane.hidden ? (pane.dataset.item || null) : null;
  }

  // An item's menu (… beside its name): its entries, without the lines
  // between them; one by its label; running one.
  function menuOf(id) {
    let entries = [];
    window.RowMenu = { open: (_button, list) => { entries = list.filter((e) => e !== 'divider'); } };
    const button = document.querySelector(`#workbench-view [data-item="${id}"] .workbench-item-menu`);
    if (button) button.click();
    return entries;
  }
  const menuEntry = (id, label) => menuOf(id).find((e) => e.label === label) || null;
  function run(id, label) {
    const found = menuEntry(id, label);
    if (!found) throw new Error(`no menu entry ${label} for ${id}`);
    found.action();
  }

  function entry(overrides = {}) {
    return Object.assign({ id: 'r_1', path: PATH, name: '20261106-091233_cat.png' }, overrides);
  }

  function view(items, extra = {}) {
    window.Workbench.onView(Object.assign({
      board: { board_id: 'b1', chat_id: 'c_1', revision: 1, items: items },
      approvals: Object.fromEntries(items.map((i) => [i.id, `tok-${i.id}`])),
      assets: Object.fromEntries(items.filter((i) => i.status === 'ok').map((i) => [i.id, `/workbench/asset/${i.id}`])),
      // What the server holds for this tab: the item made for it last.
      selected: items.length ? items[items.length - 1].id : null
    }, extra));
  }

  beforeEach(() => {
    jest.resetModules();
    document.body.innerHTML = `
      <div id="discourse"></div>
      <div id="workbench-status"></div>
      <div id="work-screen-browser"></div>
      <div id="workbench-view" hidden></div>
      <textarea id="message"></textarea>
      <span id="side-tab-work-new" hidden></span>
      <div id="work-screen-pane"><button id="workbench-put"></button><input type="file" id="workbench-put-input" multiple></div>`;
    sent = [];
    messages = [{ mid: 'm-1', role: 'assistant', text: 'done' }];
    layout = { hidden: false, pane: 'settings' };
    window.LayoutController = {
      isMenuHidden: () => layout.hidden,
      setMenuHidden: jest.fn((h) => { layout.hidden = h; }),
      selectedPane: () => layout.pane,
      setPane: jest.fn((p) => { layout.pane = p; })
    };
    window.WorkScreen = { refresh: jest.fn() };
    window.safeWsSend = (payload, opts) => sent.push({ payload, opts });
    window.SessionState = { getMessages: () => messages };
    window.setAlert = jest.fn();
    delete window.electronAPI;
    delete global.webUIi18n;
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/workbench-places.js'));
    require(js('monadic/workbench.js'));
  });

  test("shows the reply's line naming the image in the page's language, keeping the path and other paragraphs", () => {
    const el = card('m-1');
    el.querySelector('.card-text').innerHTML = '<p>Made with a note.</p><p>The image is in the work screen and in the shared folder: <code>' + PATH + '</code></p>';
    global.webUIi18n = { t: (key) => (key === 'ui.workbench.offerLine' ? '画像は作業画面と共有フォルダにあります：' : key) };
    window.Workbench.drawRecord('m-1', [entry()]);
    const paragraphs = [...el.querySelectorAll('.card-text > p')];
    expect(paragraphs[0].textContent).toBe('Made with a note.');
    expect(paragraphs[1].textContent).toBe('画像は作業画面と共有フォルダにあります： ' + PATH);
    expect(paragraphs[1].querySelector('code').textContent).toBe(PATH);
  });

  test("finds the line by the whole path when the page shortened it", () => {
    const el = card('m-1');
    el.querySelector('.card-text').innerHTML = '<p>The image is in the work screen and in the shared folder: <code class="short-path" data-full-path="' + PATH + '">x.png</code></p>';
    global.webUIi18n = { t: (key) => (key === 'ui.workbench.offerLine' ? '画像は作業画面と共有フォルダにあります：' : key) };
    window.Workbench.drawRecord('m-1', [entry()]);
    expect(el.querySelector('.card-text > p').textContent).toBe('画像は作業画面と共有フォルダにあります： x.png');
  });

  test('shows a new image in the pane with its path and Download, and only a line of text in the conversation', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry()]);
    view([item()]);
    const pane = document.getElementById('workbench-view');
    expect(pane.hidden).toBe(false);
    expect(pane.querySelector('img').getAttribute('src')).toBe('/workbench/asset/i_1');
    expect(pane.querySelector('code').textContent).toBe(PATH);
    expect(menuEntry('i_1', 'Download')).toMatchObject({ icon: 'fa-solid fa-floppy-disk' });
    expect(document.getElementById('work-screen-browser').hidden).toBe(true);
    expect(shown()).not.toBeNull();
    expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
    expect(document.getElementById('workbench-status').textContent).not.toBe('');
    expect(el.querySelector('img')).toBeNull();
    const note = el.querySelector('.workbench-note');
    expect(note.querySelector('code').textContent).toBe(PATH);
    expect(note.querySelector('.workbench-save').textContent).toBe('Download');
  });

  test('says on the message what the reply looked at in the work screen and how far it went', () => {
    const el = card('m-1');
    window.Workbench.drawLooks('m-1', [
      { id: 'look_1', kind: 'image', name: 'shot.png', state: 'sent', version: 'abcdef123456' },
      { id: 'look_2', kind: 'text', name: '<b>n</b>.txt', state: 'unknown', lines: { first: 1, last: 3, partial: true }, truncated: true },
      { id: 'look_4', kind: 'text', name: 'e.txt', state: 'sent', empty: true },
      { id: 'look_3', kind: 'image', name: 'x.png', state: 'made-up' }
    ]);
    const lines = el.querySelectorAll('.workbench-look-line');
    expect(lines.length).toBe(3);
    expect(lines[0].textContent).toContain('Sent to the AI provider');
    expect(lines[0].textContent).toContain('shot.png');
    expect(lines[0].textContent).toContain('abcdef123456');
    expect(lines[1].textContent).toContain('whether it arrived is not known');
    expect(lines[1].textContent).toContain('lines 1–3');
    expect(lines[1].textContent).toContain('cut short');
    expect(lines[2].textContent).toContain('empty');
    // A name is shown as text, never as markup.
    expect(lines[1].querySelector('code').textContent).toBe('<b>n</b>.txt');
    expect(lines[1].querySelector('b')).toBeNull();
    window.Workbench.drawLooks('m-1', []);
    expect(el.querySelector('.workbench-look-note')).toBeNull();
  });

  test('says which pages of a PDF a look read and which of its parts it gave', () => {
    const el = card('m-1');
    window.Workbench.drawLooks('m-1', [
      { id: 'look_1', kind: 'pdf', name: 'p.pdf', state: 'sent', pages: { first: 2, last: 2, total: 9 },
        parts: { image: true, page_text: 'pdf_text_unavailable', selection: true } },
      { id: 'look_2', kind: 'pdf', name: 'q.pdf', state: 'sent', pages: { first: 1, last: 100, total: 140 },
        parts: { page_text: true }, truncated: true },
      { id: 'look_3', kind: 'pdf', name: 'r.pdf', state: 'sent', pages: { first: 1, last: 1 }, empty: true }
    ]);
    const lines = el.querySelectorAll('.workbench-look-line');
    expect(lines[0].textContent).toContain('page 2');
    expect(lines[0].textContent).toContain('image of the part in view');
    expect(lines[0].textContent).toContain('selected text');
    expect(lines[0].textContent).not.toContain('text of the page');
    expect(lines[1].textContent).toContain('pages 1–100 of 140');
    expect(lines[1].textContent).toContain('cut short');
    expect(lines[2].textContent).toContain('no text extracted');
    expect(lines[2].textContent).not.toContain('empty');
  });

  test('says a PDF text that stopped because the time ran out apart from one cut short', () => {
    const el = card('m-1');
    // Records as a message, or a history read back, gives them.
    window.Workbench.drawLooks('m-1', [
      { id: 'look_1', kind: 'pdf', name: 'slow.pdf', state: 'sent', pages: { first: 1, last: 2, total: 40 },
        parts: { page_text: true }, cuts: ['page_text'], truncated: true, stopped: 'time' },
      { id: 'look_2', kind: 'pdf', name: 'long.pdf', state: 'sent', pages: { first: 1, last: 2, total: 40 },
        parts: { page_text: true }, cuts: ['page_text'], truncated: true },
      { id: 'look_3', kind: 'text', name: 'n.txt', state: 'sent', lines: { first: 1, last: 3 }, truncated: true, stopped: 'time' }
    ]);
    const lines = el.querySelectorAll('.workbench-look-line');
    expect(lines[0].textContent).toContain('pages 1–2 of 40');
    expect(lines[0].textContent).toContain('stopped: out of time');
    expect(lines[0].textContent).not.toContain('cut short');
    expect(lines[1].textContent).toContain('cut short');
    expect(lines[1].textContent).not.toContain('out of time');
    expect(lines[2].textContent).toContain('cut short');
    expect(lines[2].textContent).not.toContain('out of time');
  });

  test('says Save as… in the desktop app', () => {
    window.electronAPI = {};
    view([item()]);
    expect(menuEntry('i_1', 'Save as…')).not.toBeNull();
  });

  test('shows no image for a file that changed or is gone, says which, and offers no save', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry()]);
    view([item({ status: 'changed' })]);
    const pane = document.getElementById('workbench-view');
    expect(pane.querySelector('img')).toBeNull();
    expect(pane.textContent).toContain('changed in the shared folder');
    expect(menuEntry('i_1', 'Download')).toBeNull();
    expect(el.querySelector('.workbench-note').textContent).toContain('changed in the shared folder');
    view([item({ status: 'missing' })], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item({ status: 'missing' })] } });
    expect(pane.textContent).toContain('no longer in the shared folder');
  });

  test('brings nothing forward from the board a connection is sent first (a reload)', () => {
    card('m-1');
    view([item()], { initial: true });
    expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    expect(shown()).toBeNull();
  });

  test('does not open a column the user hid, nor take the pane while the user types', () => {
    layout.hidden = true;
    view([item()]);
    expect(window.LayoutController.setMenuHidden).not.toHaveBeenCalled();
    expect(window.LayoutController.setPane).not.toHaveBeenCalled();

    layout.hidden = false;
    window.Workbench.select(null);
    writeMessage();
    view([item(), item({ id: 'i_2', artifact_id: 'r_2', name: 'dog.png', sha256: 'b'.repeat(64) })]);
    expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    expect(shown()).toBeNull();
  });

  test('asks for an address to save the image by its record, from the pane and from the line', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry()]);
    view([item()]);
    run('i_1', 'Download');
    el.querySelector('.workbench-save').click();
    expect(sent.map((s) => s.payload)).toEqual([
      { message: 'WORKBENCH_DOWNLOAD', artifact_id: 'r_1' }, { message: 'WORKBENCH_DOWNLOAD', artifact_id: 'r_1' }
    ]);
  });

  test('asks for an address to save a file of the shared folder by its item and the version shown', () => {
    const clip = { id: 'i_a', kind: 'file', actor: 'user', name: '曲 1.mp3', path: 'music/曲 1.mp3', preview: 'audio',
      sha256: 'd'.repeat(64), version: 'd'.repeat(64), status: 'ok' };
    view([clip]);
    run('i_a', 'Download');
    expect(sent.map((s) => s.payload)).toEqual([{ message: 'WORKBENCH_DOWNLOAD', item_id: 'i_a', sha256: 'd'.repeat(64) }]);
    view([Object.assign({}, clip, { status: 'changed' })]);
    expect(menuEntry('i_a', 'Download')).toBeNull();
  });

  test('says on its tab and above its items that the notes are being updated, without touching the reply\'s status', () => {
    document.body.insertAdjacentHTML('beforeend',
      '<button id="side-tab-work"><i id="side-tab-work-mark" hidden></i></button><div id="workbench-notes-status" hidden></div>');
    const mark = () => document.getElementById('side-tab-work-mark');
    const line = () => document.getElementById('workbench-notes-status');
    view([], { notes: 'updating' });
    expect(mark().hidden).toBe(false);
    expect(line().hidden).toBe(false);
    expect(line().textContent).toContain('Updating the notes');
    view([]);
    expect(mark().hidden).toBe(true);
    expect(line().hidden).toBe(true);
    expect(window.setAlert).not.toHaveBeenCalled();
    expect(window.LayoutController.setPane).not.toHaveBeenCalled();
  });

  describe('a chat continued from the history', () => {
    test('shows the work screen when its board has something on it', () => {
      window.Workbench.expectResumed('c_1');
      view([item()], { selected: null });
      expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
      expect(window.LayoutController.setMenuHidden).not.toHaveBeenCalled();
    });

    test('keeps the pane when the board is empty, and only for the board of that chat', () => {
      window.Workbench.expectResumed('c_1');
      view([], { selected: null });
      view([item()], { selected: null });
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();

      window.Workbench.expectResumed('c_2');
      view([item()], { selected: null });
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    });
  });

  describe('saving a copy', () => {
    let clicked;

    beforeEach(() => {
      clicked = [];
      global.URL.createObjectURL = jest.fn(() => 'blob:x');
      global.URL.revokeObjectURL = jest.fn();
      jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function () {
        clicked.push({ href: this.getAttribute('href'), download: this.download });
      });
    });

    afterEach(() => {
      HTMLAnchorElement.prototype.click.mockRestore();
      delete global.fetch;
    });

    test('fetches the address and hands the file to the browser under its name, staying on the page', async () => {
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, blob: () => Promise.resolve(new Blob(['x'])) }));
      await window.Workbench.onDownload({ type: 'workbench_download', artifact_id: 'r_1', url: '/workbench/asset/t', name: '20261106-091233_cat.png' });
      expect(global.fetch).toHaveBeenCalledWith('/workbench/asset/t', expect.objectContaining({ credentials: 'same-origin' }));
      expect(clicked).toEqual([{ href: 'blob:x', download: '20261106-091233_cat.png' }]);
      expect(window.setAlert).not.toHaveBeenCalled();
    });

    test('says when the file changed, is gone, the address expired or the file did not come, and saves nothing', async () => {
      for (const [status, words] of [[409, 'changed'], [410, 'no longer'], [404, 'expired']]) {
        global.fetch = jest.fn(() => Promise.resolve({ ok: false, status }));
        await window.Workbench.onDownload({ artifact_id: 'r_1', url: '/workbench/asset/t', name: 'x.png' });
        expect(document.getElementById('workbench-status').textContent).toContain(words);
      }
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, blob: () => Promise.reject(new TypeError('cut')) }));
      await window.Workbench.onDownload({ artifact_id: 'r_1', url: '/workbench/asset/t', name: 'x.png' });
      expect(document.getElementById('workbench-status').textContent).toContain('Could not get');
      window.Workbench.onDownload({ artifact_id: 'r_1', status: 'refused' });
      expect(document.getElementById('workbench-status').textContent).toContain('not accepted');
      expect(clicked).toEqual([]);
    });

    test('saves a file under the name the server gives, and says when the version shown is gone', async () => {
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, blob: () => Promise.resolve(new Blob(['x'])) }));
      await window.Workbench.onDownload({ type: 'workbench_download', item_id: 'i_a', url: '/workbench/asset/t', name: '曲 1.mp3' });
      expect(clicked).toEqual([{ href: 'blob:x', download: '曲 1.mp3' }]);
      window.Workbench.onDownload({ item_id: 'i_a', status: 'refused', reason: 'changed' });
      expect(document.getElementById('workbench-status').textContent).toContain('changed');
    });
  });

  test('removes an image with its ×; the line stays, with no link to the pane', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry()]);
    view([item({ fresh: true })]);
    run('i_1', 'Remove from the work screen');
    expect(sent[0].payload).toMatchObject({ message: 'WORKBENCH_ACTION', item_id: 'i_1', action: 'remove', token: 'tok-i_1' });
    expect(sent[0].opts).toMatchObject({ idempotent: true });
    window.Workbench.onResult({ status: 'accepted', action: 'remove', item_id: 'i_1', state: 'removed' });
    view([], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [] }, approvals: {}, assets: {} });
    expect(el.querySelector('.workbench-note code').textContent).toBe(PATH);
    expect(el.querySelector('.workbench-open')).toBeNull();
    expect(el.querySelector('.workbench-save')).not.toBeNull();
    expect(shown()).toBeNull();
    expect(document.getElementById('workbench-status').textContent).not.toContain('older item');
  });

  test('keeps an item the server put away instead of removing it', () => {
    view([item()]);
    run('i_1', 'Put away');
    window.Workbench.onResult({ status: 'accepted', action: 'remove', item_id: 'i_1', state: 'stashed' });
    const kept = item();
    view([kept], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [kept] } });
    expect(shown()).toBe('i_1');
    expect(document.getElementById('workbench-status').textContent).not.toContain('Removed');
  });

  test('says so when an item left the board without the user taking it off', () => {
    view([item()]);
    document.getElementById('workbench-status').textContent = '';
    const next = item({ id: 'i_2', artifact_id: 'r_2', sha256: 'b'.repeat(64) });
    view([next], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [next] } });
    expect(document.getElementById('workbench-status').textContent).toContain('older item');
  });

  test('opens the image in the pane from its line, showing the column the user hid', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry()]);
    view([item()]);
    window.Workbench.select(null);
    layout.hidden = true;
    layout.pane = 'settings';
    el.querySelector('.workbench-open').click();
    expect(window.LayoutController.setMenuHidden).toHaveBeenCalledWith(false);
    expect(layout.pane).toBe('work');
    expect(shown()).not.toBeNull();
  });

  test('names each item by its head, with its whole name', () => {
    view([item({ name: '20261106-091233_generate_gpt-image-2_0.png' })]);
    const head = document.querySelector('#workbench-view .workbench-section[data-item="i_1"] .workbench-section-head');
    expect(head.textContent).toBe('20261106-091233_generate_gpt-image-2_0.png');
  });

  test('names the item chosen by its head, still shown, and marks it as the current one', () => {
    view([item(), item({ id: 'i_2', artifact_id: 'r_2', name: 'dog.png', sha256: 'b'.repeat(64) })], { selected: 'i_1' });
    const part = document.querySelector('#workbench-view .workbench-section[data-item="i_1"]');
    const head = part.querySelector('.workbench-section-head');
    expect(part.classList.contains('is-focus')).toBe(true);
    expect(head.hidden).toBe(false);
    expect(head.getAttribute('aria-current')).toBe('true');
    expect(document.querySelector('#workbench-view .workbench-section[data-item="i_2"] .workbench-section-head')
      .getAttribute('aria-current')).toBe('false');
  });

  test('ignores an older revision of the board, and starts over for another chat', () => {
    const el = card('m-1');
    view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 5, items: [item()] } });
    view([], { board: { board_id: 'b1', chat_id: 'c_1', revision: 4, items: [] }, approvals: {}, assets: {} });
    expect(shown()).not.toBeNull();
    window.Workbench.drawRecord('m-1', [entry()]);
    expect(el.querySelector('.workbench-note')).not.toBeNull();
    messages = [{ mid: 'm-1', role: 'assistant', text: 'other' }];
    view([], { board: { board_id: null, chat_id: 'c_2', revision: 0, items: [] }, approvals: {}, assets: {} });
    expect(el.querySelector('.workbench-note')).toBeNull();
  });

  test('keeps the next chat\'s own record when its board arrives after its messages', () => {
    card('m-1');
    view([item()]);
    document.getElementById('discourse').replaceChildren();
    const next = card('m-1');
    const record = [entry({ id: 'r_2', path: PATH.replace('_cat.png', '_dog.png') })];
    messages = [{ mid: 'm-1', role: 'assistant', text: 'other', artifacts: record }];
    window.Workbench.drawRecord('m-1', record);
    view([], { board: { board_id: null, chat_id: 'c_2', revision: 0, items: [] }, approvals: {}, assets: {} });
    const lines = Array.from(next.querySelectorAll('.workbench-note-line code')).map((l) => l.textContent);
    expect(lines).toEqual([PATH.replace('_cat.png', '_dog.png')]);
  });

  test('draws a record as text, and clears what was drawn for a message without one', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry({ path: '<img src=x onerror=alert(1)>.png' })]);
    const note = el.querySelector('.workbench-note');
    expect(note.querySelector('img')).toBeNull();
    expect(note.querySelector('code').textContent).toBe('<img src=x onerror=alert(1)>.png');
    window.Workbench.drawRecord('m-1', []);
    expect(el.querySelector('.workbench-note')).toBeNull();
  });

  test('tells the user when a removal was refused', () => {
    window.Workbench.onResult({ status: 'refused' });
    window.Workbench.onResult({ status: 'accepted', action: 'remove', item_id: 'i_1', state: 'removed' });
    expect(window.setAlert).toHaveBeenCalledTimes(1);
  });
  describe('files and the row', () => {
    function file(overrides = {}) {
      return Object.assign({
        id: 'i_f', kind: 'file', actor: 'user', mid: null, name: 'notes.txt', path: 'reports/notes.txt',
        preview: 'text', sha256: 'c'.repeat(64), status: 'ok'
      }, overrides);
    }

    afterEach(() => { delete global.fetch; });

    test('shows a text file as numbered lines, and says when only its beginning is shown', async () => {
      global.fetch = jest.fn(() => Promise.resolve({
        ok: true, status: 200, text: () => Promise.resolve('one\ntwo'),
        headers: { get: (h) => (h === 'x-workbench-truncated' ? '1' : null) }
      }));
      view([file()]);
      await new Promise((r) => setTimeout(r, 0));
      const lines = document.querySelectorAll('#workbench-view .workbench-lines li');
      expect(Array.from(lines).map((l) => l.textContent)).toEqual(['one', 'two']);
      expect(document.getElementById('workbench-view').textContent).toContain('Only the beginning');
    });

    test('moves along the items with their heads and the arrow keys, telling the server what the tab shows', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      document.body.insertAdjacentHTML('beforeend', '<div id="work-screen-pane" tabindex="0"></div>');
      jest.resetModules();
      require(js('monadic/workbench-places.js'));
      require(js('monadic/workbench.js'));
      view([item(), file()]);
      expect(shown()).not.toBeNull();
      sent.length = 0;
      document.querySelector('#workbench-view .workbench-section[data-item="i_1"] .workbench-section-head').click();
      expect(payloads()).toEqual([{ message: 'WORKBENCH_SELECT', item_id: 'i_1' }]);
      expect(document.querySelector('#workbench-view img')).not.toBeNull();
      const pane = document.getElementById('work-screen-pane');
      pane.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
      expect(payloads().pop()).toEqual({ message: 'WORKBENCH_SELECT', item_id: 'i_f' });
      sent.length = 0;
      pane.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
      expect(payloads()).toEqual([]);
    });

    test('leaves the item shown as it is when its own head is pressed again', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      view([item(), file()]);
      const before = shown();
      sent.length = 0;
      document.querySelector('#workbench-view .workbench-section[data-item="i_f"] .workbench-section-head').click();
      expect(payloads()).toEqual([]);
      expect(shown()).toBe(before);
      document.querySelector('#workbench-view .workbench-section[data-item="i_1"] .workbench-section-head').click();
      expect(payloads()).toEqual([{ message: 'WORKBENCH_SELECT', item_id: 'i_1' }]);
    });

    test('brings forward only what the server selected for this tab, once', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      view([file()], { selected: null });
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
      expect(shown()).toBeNull();
      view([file()], { selected: 'i_f', board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [file()] } });
      expect(shown()).not.toBeNull();
      window.Workbench.select(null);
      view([file()], { selected: 'i_f', board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [file()] } });
      expect(shown()).toBeNull();
    });

    test('opens a file the user asked for, showing the column, or says why not', () => {
      layout.hidden = true;
      window.Workbench.openFile('reports/notes.txt');
      expect(sent[0].payload).toEqual({ message: 'WORKBENCH_OPEN', path: 'reports/notes.txt' });
      window.Workbench.onOpened({ type: 'workbench_opened', item_id: 'i_f', path: 'reports/notes.txt', added: true });
      // Shown when the board has it, even while the user types and whatever
      // the server's selection was before.
      writeMessage();
      global.fetch = jest.fn(() => new Promise(() => {}));
      view([item(), file()], { selected: 'i_1' });
      expect(window.LayoutController.setMenuHidden).toHaveBeenCalledWith(false);
      expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
      expect(shown()).toBe('i_f');
      expect(payloads()).toContainEqual({ message: 'WORKBENCH_SELECT', item_id: 'i_f' });
      window.Workbench.openFile('x.pdf');
      window.Workbench.onOpened({ type: 'workbench_opened', status: 'refused', reason: 'the file cannot be previewed' });
      expect(document.getElementById('workbench-status').textContent).toContain('cannot be previewed');
    });

    test('takes what the server holds when a selection is refused, and asks for the board when it changed', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      view([item(), file()], { selected: null });
      window.Workbench.select('i_f');
      window.Workbench.onSelected({ type: 'workbench_selected', status: 'refused', item_id: 'i_1' });
      expect(document.querySelector('#workbench-view img')).not.toBeNull();
      sent.length = 0;
      window.Workbench.onChanged();
      expect(sent[0].payload).toEqual({ message: 'WORKBENCH_VIEW' });
    });

    test('says a file changed after it was opened, and offers to open it as it is now', () => {
      view([file({ status: 'changed' })]);
      const pane = document.getElementById('workbench-view');
      expect(pane.textContent).toContain('after it was opened here');
      sent.length = 0;
      run('i_f', 'Open it as it is now');
      expect(sent[0].payload).toEqual({ message: 'WORKBENCH_OPEN', path: 'reports/notes.txt' });
      expect(menuEntry('i_f', 'Reload')).toBeNull();
    });

    test('reads a file shown as it is again when the user asks to reload it', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      view([file()]);
      const pane = document.getElementById('workbench-view');
      sent.length = 0;
      run('i_f', 'Reload');
      expect(sent[0].payload).toEqual({ message: 'WORKBENCH_OPEN', path: 'reports/notes.txt' });
    });

    test('puts everything done with a file in one menu beside its name', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      view([file({ path: 'conversations/c_1/documents/notes.md', name: 'notes.md' })]);
      const entries = menuOf('i_f');
      expect(entries.map((e) => e.label)).toEqual(['Put away', 'Download', 'Reload', 'Versions']);
      expect(entries.every((e) => typeof e.icon === 'string' && e.icon.startsWith('fa-'))).toBe(true);
      // No row of buttons is left under the item.
      expect(document.querySelector('#workbench-view .workbench-actions')).toBeNull();
    });

    test('lists the versions of a document, newest first, and opens the one chosen', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      const doc = 'conversations/c_1/documents/reply-to-tanaka.md';
      view([file({ path: doc, name: 'reply-to-tanaka.md' })]);
      const pane = document.getElementById('workbench-view');
      sent.length = 0;
      run('i_f', 'Versions');
      expect(sent[0].payload).toEqual({ message: 'WORKBENCH_VERSIONS', path: doc });
      window.Workbench.onVersions({ type: 'workbench_versions', path: doc, versions: [
        { section: 'draft', path: 'conversations/c_1/artifacts/j_1/reply-to-tanaka--draft.md', version: 1 },
        { section: 'draft', path: 'conversations/c_1/artifacts/j_2/reply-to-tanaka--draft.md', version: 2 }
      ] });
      const entries = Array.from(pane.querySelectorAll('.workbench-versions button'));
      expect(entries.map((e) => e.textContent)).toEqual(['§ draft — version 2', '§ draft — version 1']);
      sent.length = 0;
      entries[1].click();
      expect(sent[0].payload).toEqual({ message: 'WORKBENCH_OPEN', path: 'conversations/c_1/artifacts/j_1/reply-to-tanaka--draft.md' });
    });

    test('asks for the versions again when the board changes while they are listed', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      const doc = 'conversations/c_1/documents/reply-to-tanaka.md';
      view([file({ path: doc, name: 'reply-to-tanaka.md' })]);
      const pane = document.getElementById('workbench-view');
      run('i_f', 'Versions');
      sent.length = 0;
      view([file({ path: doc, name: 'reply-to-tanaka.md', sha256: 'b'.repeat(64) })]);
      expect(sent.map((s) => s.payload)).toContainEqual({ message: 'WORKBENCH_VERSIONS', path: doc });
    });

    test('offers no versions for a file that is not a document', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      view([file()]);
      const pane = document.getElementById('workbench-view');
      expect(menuEntry('i_f', 'Versions')).toBeNull();
    });
  });
  describe('the browser as an item', () => {
    function browser(overrides = {}) {
      return Object.assign({ id: 'i_b', kind: 'browser', actor: 'agent', version: 'browser:1', status: 'open' }, overrides);
    }

    test('shows the relay area for the open browser, and says when it was closed', () => {
      view([browser()]);
      expect(window.Workbench.showsBrowser()).toBe(true);
      expect(document.getElementById('work-screen-browser').hidden).toBe(false);
      // A way back to the work screen's places while the browser is shown.
      const back = document.querySelector('#work-screen-browser .workbench-back');
      expect(back.hidden).toBe(false);
      sent.length = 0;
      back.click();
      expect(payloads()).toEqual([{ message: 'WORKBENCH_SELECT', item_id: null }]);
      expect(document.getElementById('work-screen-browser').hidden).toBe(true);
      expect(document.getElementById('workbench-view').hidden).toBe(false);
      view([browser({ status: 'closed' })], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [browser({ status: 'closed' })] } });
      expect(window.Workbench.showsBrowser()).toBe(false);
      expect(document.getElementById('work-screen-browser').hidden).toBe(true);
      expect(document.getElementById('workbench-view').textContent).toContain('closed');
    });

    test('a page loaded again shows the open browser without taking the pane', () => {
      view([item(), browser()], { initial: true, selected: null });
      expect(window.Workbench.showsBrowser()).toBe(true);
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
      expect(payloads()).toContainEqual({ message: 'WORKBENCH_SELECT', item_id: 'i_b' });
    });

    test('with nothing selected, shows the places and no browser area', () => {
      view([item()], { selected: null });
      expect(shown()).toBeNull();
      expect(document.getElementById('work-screen-browser').hidden).toBe(true);
      expect(document.querySelectorAll('#workbench-view .workbench-place').length).toBe(4);
    });
  });
  describe('the mark on the work screen tab', () => {
    const mark = () => document.getElementById('side-tab-work-new');
    const notes = (version) => item({ id: 'i_n', kind: 'file', name: 'notes.md', version, sha256: version });
    const board = (items, revision) => ({ board: { board_id: 'b1', chat_id: 'c_1', revision, items }, selected: null });

    test('marks a new version of an item that comes while another pane is shown, until the work screen is shown', () => {
      view([notes('v1')], Object.assign(board([notes('v1')], 1), { initial: true }));
      expect(mark().hidden).toBe(true);
      view([notes('v2')], board([notes('v2')], 2));
      expect(mark().hidden).toBe(false);
      window.LayoutController.setPane('work');
      document.dispatchEvent(new Event('layoutchange'));
      expect(mark().hidden).toBe(true);
    });

    test('marks a new item, but nothing that comes while the work screen is shown', () => {
      layout.pane = 'work';
      view([notes('v1')], board([notes('v1')], 1));
      view([notes('v2')], board([notes('v2')], 2));
      expect(mark().hidden).toBe(true);
      layout.pane = 'settings';
      const next = item({ id: 'i_2', version: 'x' });
      view([notes('v2'), next], board([notes('v2'), next], 3));
      expect(mark().hidden).toBe(false);
    });

    test('does not mark the board a connection is sent first, nor the board of another chat', () => {
      view([notes('v1')], Object.assign(board([notes('v1')], 1), { initial: true }));
      expect(mark().hidden).toBe(true);
      view([notes('v1')], { board: { board_id: 'b2', chat_id: 'c_2', revision: 1, items: [notes('v1')] }, selected: null });
      expect(mark().hidden).toBe(true);
    });
  });

  describe('keeping the page and the server in step', () => {
    test('tells the server what the pane still shows when an item arrives while the user types', () => {
      view([item()]);
      writeMessage();
      sent.length = 0;
      const next = item({ id: 'i_2', artifact_id: 'r_2', sha256: 'b'.repeat(64) });
      view([item(), next], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item(), next] }, selected: 'i_2' });
      expect(shown()).toBe('i_1');
      expect(payloads()).toEqual([{ message: 'WORKBENCH_SELECT', item_id: 'i_1' }]);
    });

    test('turns the pane to a quietly offered item that is the first of the work screen', () => {
      view([], { selected: null });
      sent.length = 0;
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item()] },
        selected: 'i_1', selection_quiet: true });
      expect(shown()).toBe('i_1');
      expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
      expect(payloads()).toEqual([]);
    });

    test('turns the pane to the first quietly offered item while the message box only has the focus', () => {
      view([], { selected: null });
      document.getElementById('message').focus();
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item()] },
        selected: 'i_1', selection_quiet: true });
      expect(shown()).toBe('i_1');
      expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
    });

    test('turns the pane to the first item when its quiet selection comes in a later view', () => {
      view([], { selected: null });
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item()] }, selected: null });
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [item()] }, selected: 'i_1',
        selection_quiet: true });
      expect(shown()).toBe('i_1');
      expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
    });

    test('takes the pane for the first item only at its first offer, and not after the work screen was shown', () => {
      view([], { selected: null });
      writeMessage();
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item()] }, selected: 'i_1',
        selection_quiet: true });
      document.getElementById('message').value = '';
      window.Workbench.select(null);
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [item()] }, selected: 'i_1',
        selection_quiet: true });
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();

      // Another chat (its board resets the page).
      view([], { board: { board_id: 'b2', chat_id: 'c_2', revision: 1, items: [] }, selected: null });
      view([item()], { board: { board_id: 'b2', chat_id: 'c_2', revision: 2, items: [item()] }, selected: null });
      window.LayoutController.setPane('work');
      document.dispatchEvent(new Event('layoutchange'));
      window.LayoutController.setPane('settings');
      window.LayoutController.setPane.mockClear();
      view([item()], { board: { board_id: 'b2', chat_id: 'c_2', revision: 3, items: [item()] }, selected: 'i_1',
        selection_quiet: true });
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    });

    test('does not take the pane for an item that came while the work screen was shown', () => {
      layout.pane = 'work';
      view([], { selected: null });
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item()] }, selected: null });
      layout.pane = 'settings';
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [item()] }, selected: 'i_1',
        selection_quiet: true });
      expect(shown()).toBe('i_1');
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    });

    test('does not take the pane for an item that was on the board a connection is sent first', () => {
      view([item()], { selected: null, initial: true });
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item()] }, selected: 'i_1',
        selection_quiet: true });
      expect(shown()).toBe('i_1');
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    });

    test('counts spaces in the message box as writing, and not a focused slider', () => {
      view([], { selected: null });
      const box = document.getElementById('message');
      box.value = '    ';
      box.focus();
      const next = item({ id: 'i_2', artifact_id: 'r_2', sha256: 'b'.repeat(64) });
      view([next], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [next] }, selected: 'i_2',
        selection_quiet: true });
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();

      box.value = '';
      const slider = document.createElement('input');
      slider.type = 'range';
      slider.value = '0.5';
      document.body.appendChild(slider);
      slider.focus();
      window.Workbench.select(null);
      layout.pane = 'settings';
      const third = item({ id: 'i_3', artifact_id: 'r_3', sha256: 'c'.repeat(64) });
      view([next, third], { board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [next, third] }, selected: 'i_3' });
      expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
    });

    test('shows the first quietly offered item without taking the pane while the user types', () => {
      view([], { selected: null });
      writeMessage();
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item()] },
        selected: 'i_1', selection_quiet: true });
      expect(shown()).toBe('i_1');
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    });

    test('shows a later quietly offered item on a work screen that shows nothing, without taking the pane', () => {
      view([item()]);
      window.Workbench.select(null);
      layout.pane = 'settings';
      window.LayoutController.setPane.mockClear();
      sent.length = 0;
      const next = item({ id: 'i_2', artifact_id: 'r_2', sha256: 'b'.repeat(64) });
      view([item(), next], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item(), next] },
        selected: 'i_2', selection_quiet: true });
      expect(shown()).toBe('i_2');
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
      expect(payloads()).toEqual([]);
    });

    test('takes a quiet selection whose item comes in a later view, and one in a first view', () => {
      view([], { selected: null });
      view([], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [] }, selected: 'i_1',
        selection_quiet: true });
      expect(shown()).toBeNull();
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [item()] }, selected: 'i_1',
        selection_quiet: true });
      expect(shown()).toBe('i_1');

      window.Workbench.select(null);
      view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 4, items: [item()] }, selected: 'i_1',
        selection_quiet: true, initial: true });
      expect(shown()).toBe('i_1');
    });

    test('a first view shows the open browser before an item offered quietly', () => {
      const open = { id: 'i_b', kind: 'browser', actor: 'agent', version: 'browser:1', status: 'open' };
      view([item(), open], { selected: 'i_1', selection_quiet: true, initial: true });
      expect(window.Workbench.showsBrowser()).toBe(true);
      expect(payloads()).toContainEqual({ message: 'WORKBENCH_SELECT', item_id: 'i_b' });
    });

    test('keeps what the work screen shows when an item is offered quietly', () => {
      view([item()]);
      window.LayoutController.setPane.mockClear();
      sent.length = 0;
      const next = item({ id: 'i_2', artifact_id: 'r_2', sha256: 'b'.repeat(64) });
      view([item(), next], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item(), next] },
        selected: 'i_2', selection_quiet: true });
      expect(shown()).toBe('i_1');
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
      expect(payloads()).toEqual([{ message: 'WORKBENCH_SELECT', item_id: 'i_1' }]);
    });

    test('keeps the media element of the item shown when the board comes again', () => {
      const clip = { id: 'i_a', kind: 'file', actor: 'user', name: 'a.mp3', path: 'a.mp3', preview: 'audio',
        sha256: 'd'.repeat(64), version: 'd'.repeat(64), status: 'ok' };
      view([clip]);
      const first = document.querySelector('#workbench-view audio');
      view([clip], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [clip] } });
      expect(document.querySelector('#workbench-view audio')).toBe(first);
    });

    test('asks once more for a medium that fails, then says it could not be played instead of asking again', () => {
      jest.useFakeTimers();
      try {
        const clip = { id: 'i_a', kind: 'file', actor: 'user', name: 'a.mkv', path: 'a.mkv', preview: 'video',
          sha256: 'd'.repeat(64), version: 'd'.repeat(64), status: 'ok' };
        view([clip]);
        sent.length = 0;
        document.querySelector('#workbench-view video').dispatchEvent(new Event('error'));
        jest.runOnlyPendingTimers();
        const asked = payloads().filter((p) => p.message === 'WORKBENCH_VIEW').length;
        expect(asked).toBeGreaterThan(0);

        view([clip], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [clip] },
          assets: { i_a: '/workbench/asset/i_a-again' } });
        document.querySelector('#workbench-view video').dispatchEvent(new Event('error'));
        jest.runOnlyPendingTimers();
        expect(document.querySelector('#workbench-view video')).toBeNull();
        expect(document.getElementById('workbench-view').textContent).toContain('could not be played');
        expect(payloads().filter((p) => p.message === 'WORKBENCH_VIEW').length).toBe(asked);
      } finally {
        jest.useRealTimers();
      }
    });

    test('asks again for a medium that played and then failed (its address ran out)', () => {
      jest.useFakeTimers();
      try {
        const clip = { id: 'i_a', kind: 'file', actor: 'user', name: 'a.mp4', path: 'a.mp4', preview: 'video',
          sha256: 'd'.repeat(64), version: 'd'.repeat(64), status: 'ok' };
        view([clip]);
        document.querySelector('#workbench-view video').dispatchEvent(new Event('error'));
        jest.runOnlyPendingTimers();
        view([clip], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [clip] },
          assets: { i_a: '/workbench/asset/i_a-again' } });
        const media = document.querySelector('#workbench-view video');
        media.dispatchEvent(new Event('loadedmetadata'));
        sent.length = 0;
        // Later, past the pause between two asks for a view.
        jest.advanceTimersByTime(60000);
        media.dispatchEvent(new Event('error'));
        jest.runOnlyPendingTimers();
        expect(payloads().some((p) => p.message === 'WORKBENCH_VIEW')).toBe(true);
        expect(document.getElementById('workbench-view').textContent).not.toContain('not played');
      } finally {
        jest.useRealTimers();
      }
    });

    test('tells a new connection what the page still shows', () => {
      view([item()]);
      sent.length = 0;
      view([item()], { initial: true, selected: null, board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item()] } });
      expect(payloads()).toEqual([{ message: 'WORKBENCH_SELECT', item_id: 'i_1' }]);
    });

    test('lets a board go when a new connection is in another chat with an empty work screen (the app restarted)', () => {
      view([item()]);
      expect(shown()).toBe('i_1');
      sent.length = 0;
      view([], { initial: true, selected: null, board: { board_id: null, chat_id: 'c_2', revision: 0, items: [] } });
      expect(shown()).toBeNull();
      expect(document.querySelectorAll('#workbench-view .workbench-section').length).toBe(0);
      expect(payloads()).toEqual([]);
    });
  });
  describe('answers and failures', () => {
    const lastSeq = () => sent.filter((x) => x.payload.message === 'WORKBENCH_SELECT').pop().payload.seq;

    test('brings forward an item the server selects again after the page kept another', () => {
      view([item()]);
      writeMessage();
      const next = item({ id: 'i_2', artifact_id: 'r_2', sha256: 'b'.repeat(64) });
      const both = { board_id: 'b1', chat_id: 'c_1', items: [item(), next] };
      view([item(), next], { board: Object.assign({ revision: 2 }, both), selected: 'i_2' });
      expect(shown()).toBe('i_1');
      // The server took what the page still shows.
      window.Workbench.onSelected({ type: 'workbench_selected', status: 'accepted', item_id: 'i_1', seq: lastSeq() });
      document.getElementById('message').blur();
      view([item(), next], { board: Object.assign({ revision: 3 }, both), selected: 'i_2' });
      expect(shown()).toBe('i_2');
    });

    test('takes no answer to an older selection', () => {
      const next = item({ id: 'i_2', artifact_id: 'r_2', sha256: 'b'.repeat(64) });
      view([item(), next], { selected: 'i_2' });
      window.Workbench.select('i_1');
      const older = lastSeq();
      window.Workbench.select('i_2');
      window.Workbench.onSelected({ type: 'workbench_selected', status: 'refused', item_id: null, seq: older });
      expect(shown()).toBe('i_2');
    });

    test('gets a text again from a new address after the server was busy, and says it was busy', async () => {
      const notes = { id: 'i_t', kind: 'file', actor: 'user', name: 'a.txt', path: 'a.txt', preview: 'text',
        sha256: 'e'.repeat(64), version: 'e'.repeat(64), status: 'ok' };
      const answers = [{ ok: false, status: 503 }, { ok: true, status: 200, text: async () => 'one\ntwo', headers: { get: () => null } }];
      const asked = [];
      global.fetch = jest.fn((url) => { asked.push(url); return Promise.resolve(answers.shift()); });
      try {
        view([notes], { assets: { i_t: '/workbench/asset/one' } });
        await new Promise((r) => setTimeout(r, 0));
        expect(document.querySelector('#workbench-view .workbench-text').textContent).toContain('reading other files');
        view([notes], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [notes] }, assets: { i_t: '/workbench/asset/two' } });
        await new Promise((r) => setTimeout(r, 0));
        expect(asked).toEqual(['/workbench/asset/one', '/workbench/asset/two']);
        expect(document.querySelectorAll('#workbench-view .workbench-lines li')).toHaveLength(2);
      } finally {
        delete global.fetch;
      }
    });

    test('draws media again from a new address once it failed, and leaves it connected otherwise', () => {
      const clip = { id: 'i_a', kind: 'file', actor: 'user', name: 'a.mp3', path: 'a.mp3', preview: 'audio',
        sha256: 'd'.repeat(64), version: 'd'.repeat(64), status: 'ok' };
      view([clip], { assets: { i_a: '/workbench/asset/one' } });
      const first = document.querySelector('#workbench-view audio');
      const held = first.parentNode;
      view([clip], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [clip] }, assets: { i_a: '/workbench/asset/two' } });
      expect(document.querySelector('#workbench-view audio')).toBe(first);
      expect(first.parentNode).toBe(held);
      first.dispatchEvent(new Event('error'));
      view([clip], { board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [clip] }, assets: { i_a: '/workbench/asset/three' } });
      const again = document.querySelector('#workbench-view audio');
      expect(again).not.toBe(first);
      expect(again.getAttribute('src')).toBe('/workbench/asset/three');
    });

    test('names the browser it shows for the relay, and says when the browser could not be put on', () => {
      view([{ id: 'i_b', kind: 'browser', actor: 'agent', instance: 3, version: 'browser:3', status: 'open' }]);
      expect(window.Workbench.shownBrowser()).toBe(3);
      window.Workbench.onBrowserFull();
      expect(document.getElementById('workbench-status').textContent).toContain('work screen is full');
    });

    test('numbers lines as the server does', () => {
      view([]);
      const cases = [['', []], ['\n', ['']], ['a', ['a']], ['a\n', ['a']], ['a\n\n', ['a', '']],
        ['a\n\nb', ['a', '', 'b']], ['\n\n', ['', '']]];
      cases.forEach(([text, lines]) => expect(window.Workbench.textLines(text)).toEqual(lines));
    });

    test('says a file cannot be shown as text, and asks for nothing again', async () => {
      const notes = { id: 'i_t', kind: 'file', actor: 'user', name: 'a.txt', path: 'a.txt', preview: 'text',
        sha256: 'e'.repeat(64), version: 'e'.repeat(64), status: 'ok' };
      global.fetch = jest.fn(() => Promise.resolve({ ok: false, status: 415 }));
      try {
        view([notes], { assets: { i_t: '/workbench/asset/one' } });
        await new Promise((r) => setTimeout(r, 0));
        expect(document.querySelector('#workbench-view .workbench-text').textContent).toContain('cannot be shown as text');
        expect(sent.filter((x) => x.payload.message === 'WORKBENCH_VIEW')).toHaveLength(0);
        view([notes], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [notes] }, assets: { i_t: '/workbench/asset/two' } });
        await new Promise((r) => setTimeout(r, 0));
        expect(global.fetch).toHaveBeenCalledTimes(1);
      } finally {
        delete global.fetch;
      }
    });

    test('says the server was busy when a file could not be opened for that', () => {
      view([]);
      window.Workbench.openFile('a.txt');
      window.Workbench.onOpened({ type: 'workbench_opened', status: 'refused', reason: 'busy' });
      expect(document.getElementById('workbench-status').textContent).toContain('reading other files');
    });
  });
  describe('what is in view, sent with a message', () => {
    const notes = { id: 'i_t', kind: 'file', actor: 'user', name: 'a.txt', path: 'a.txt', preview: 'text',
      sha256: 'e'.repeat(64), version: 'e'.repeat(64), status: 'ok' };
    const flush = () => new Promise((r) => setTimeout(r, 0));

    async function showText(lines) {
      global.fetch = jest.fn(() => Promise.resolve({
        ok: true, status: 200, text: async () => lines.join('\n'), headers: { get: () => null }
      }));
      view([notes], { assets: { i_t: '/workbench/asset/t' } });
      await flush();
      // Each line 20px high from the top; the box shows 40px to 100px.
      const box = document.querySelector('#workbench-view .workbench-text');
      box.getBoundingClientRect = () => ({ top: 40, bottom: 100, left: 0, right: 400, height: 60 });
      box.querySelectorAll('li').forEach((li, i) => {
        li.getBoundingClientRect = () => ({ top: i * 20, bottom: i * 20 + 20 });
      });
      return box;
    }

    afterEach(() => { delete global.fetch; });

    test('gives the lines in view of the text shown, with its item and version', async () => {
      layout.pane = 'work';
      const box = await showText(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
      box.closest('.workbench-section').getBoundingClientRect = () => ({ top: 20, bottom: 120, left: 0, right: 400 });
      expect(window.Workbench.rangeNow()).toEqual({
        item_id: 'i_t', version: 'e'.repeat(64), range: { first_line: 3, last_line: 5 }, note: null, selection_chars: 0,
        in_view: [{ item_id: 'i_t', version: 'e'.repeat(64) }]
      });
    });

    test('names the items in view, in their order, and none while the pane is not shown', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      const a = item({ id: 'i_a', artifact_id: 'r_a', name: 'a.png', version: 'a'.repeat(64) });
      const b = item({ id: 'i_b', artifact_id: 'r_b', name: 'b.png', sha256: 'b'.repeat(64), version: 'b'.repeat(64) });
      const c = item({ id: 'i_c', artifact_id: 'r_c', name: 'c.png', sha256: 'c'.repeat(64), version: 'c'.repeat(64) });
      layout.pane = 'work';
      view([a, b, c], { selected: 'i_c' });
      const part = (id) => Array.from(document.querySelectorAll('#workbench-view .workbench-section')).find((n) => n.dataset.item === id);
      part('i_a').getBoundingClientRect = () => ({ top: -300, bottom: -10, left: 0, right: 400 });
      part('i_b').getBoundingClientRect = () => ({ top: -10, bottom: 200, left: 0, right: 400 });
      part('i_c').getBoundingClientRect = () => ({ top: 200, bottom: 500, left: 0, right: 400 });
      expect(window.Workbench.rangeNow().in_view).toEqual([
        { item_id: 'i_b', version: 'b'.repeat(64) }, { item_id: 'i_c', version: 'c'.repeat(64) }
      ]);
      layout.pane = 'settings';
      expect(window.Workbench.rangeNow()).not.toHaveProperty('in_view');
    });

    test('says the item is not shown when the pane is not, and counts only a selection inside the item', async () => {
      layout.pane = 'work';
      const box = await showText(['héllo 😀 world', 'b']);
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(box.querySelector('li'));
      selection.removeAllRanges();
      selection.addRange(range);
      expect(window.Workbench.rangeNow().selection_chars).toBe(13);
      range.selectNodeContents(document.getElementById('message'));
      selection.removeAllRanges();
      selection.addRange(range);
      expect(window.Workbench.rangeNow().selection_chars).toBe(0);
      layout.pane = 'settings';
      expect(window.Workbench.rangeNow()).toMatchObject({ range: null, note: 'not_shown' });
    });

    test('counts only what an ancestor that scrolls leaves in view, and says when none of the item is', async () => {
      layout.pane = 'work';
      const box = await showText(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
      // The side column scrolled: its own top is at 70px.
      const column = document.getElementById('workbench-view');
      column.style.overflowY = 'auto';
      column.getBoundingClientRect = () => ({ top: 70, bottom: 1000, left: 0, right: 500 });
      box.getBoundingClientRect = () => ({ top: 40, bottom: 100, left: 0, right: 400, height: 60 });
      expect(window.Workbench.rangeNow().range).toEqual({ first_line: 4, last_line: 5 });
      column.getBoundingClientRect = () => ({ top: 120, bottom: 1000, left: 0, right: 500 });
      expect(window.Workbench.rangeNow()).toMatchObject({ range: null, note: 'not_shown' });
    });

    describe('answering what the server asks (a look)', () => {
      const asked = (extra = {}) => Object.assign({
        type: 'workbench_capture', id: 'cap-1', item_id: 'i_t', version: 'e'.repeat(64), serial: 7, wants: ['range']
      }, extra);

      // The answer the page posted, and where.
      async function answer(request) {
        const posted = jest.fn(() => Promise.resolve({ status: 204 }));
        global.fetch = posted;
        window.Workbench.onCapture(request);
        await flush();
        expect(posted).toHaveBeenCalledTimes(1);
        const [url, init] = posted.mock.calls[0];
        return { url, init, body: JSON.parse(init.body) };
      }

      async function showAsSelected(lines) {
        layout.pane = 'work';
        const box = await showText(lines);
        view([notes], { assets: { i_t: '/workbench/asset/t' }, selected: 'i_t', selection_serial: 7,
          board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [notes] } });
        return box;
      }

      test('gives the lines in view of the item asked for, by POST to the address of the request only', async () => {
        await showAsSelected(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
        const { url, init, body } = await answer(asked());
        expect(url).toBe('/workbench/capture/cap-1');
        expect(init).toMatchObject({ method: 'POST', credentials: 'same-origin', cache: 'no-store', redirect: 'error' });
        expect(body).toEqual({ range: { first_line: 3, last_line: 5 }, note: null });
      });

      function selectLines(box, first, last) {
        const lis = box.querySelectorAll('.workbench-lines li');
        const range = document.createRange();
        range.setStart(lis[first - 1].firstChild, 0);
        range.setEnd(lis[last - 1].firstChild, 1);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
        document.dispatchEvent(new Event('selectionchange'));
      }

      test('offers the lines the user selects in a text to go with a message, by their numbers', async () => {
        const box = await showAsSelected(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
        expect(box.querySelector('.workbench-text-bar .workbench-selection-chip')).toBeNull();
        selectLines(box, 4, 2);
        selectLines(box, 2, 4);
        selectLines(box, 6, 6);
        selectLines(box, 2, 4);
        expect(document.querySelectorAll('.workbench-selection-chip')).toHaveLength(1);
        expect(box.querySelector('.workbench-text-bar .workbench-selection-text').textContent).toBe('Send lines 2–4');
        const offered = window.Workbench.selectionNow();
        expect(offered.data).toEqual({ item_id: 'i_t', version: 'e'.repeat(64), first: 2, last: 4 });
        offered.sent();
        expect(window.Workbench.selectionNow()).toBeNull();
        // Sent, the lines stay marked, and the chip stays to take the mark away.
        expect(box.querySelector('.workbench-selection-text').textContent).toBe('Lines 2–4');
        expect(box.querySelector('.workbench-selection-aside').title).toBe('Clear the selected lines');
        box.querySelector('.workbench-selection-aside').click();
        expect(box.querySelector('.workbench-selection-chip')).toBeNull();
        expect(box.querySelectorAll('.workbench-line-held')).toHaveLength(0);
      });

      test('keeps the selected lines marked when the selection goes and after they are sent, until set aside', async () => {
        const box = await showAsSelected(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
        const held = () => Array.from(box.querySelectorAll('.workbench-lines li'))
          .map((li, i) => (li.classList.contains('workbench-line-held') ? i + 1 : 0)).filter(Boolean);
        selectLines(box, 2, 4);
        window.getSelection().removeAllRanges();
        expect(held()).toEqual([2, 3, 4]);
        window.Workbench.selectionNow().sent();
        expect(held()).toEqual([2, 3, 4]);
        selectLines(box, 6, 7);
        expect(held()).toEqual([6, 7]);
        box.querySelector('.workbench-selection-aside').click();
        expect(held()).toEqual([]);
      });

      test('marks the lines the AI points at, with a chip that says where and takes the mark away', async () => {
        const box = await showAsSelected(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
        const marked = () => Array.from(box.querySelectorAll('.workbench-lines li'))
          .map((li, i) => (li.classList.contains('workbench-line-ai') ? i + 1 : 0)).filter(Boolean);
        window.Workbench.onPoint({ type: 'workbench_point', item_id: 'i_t', version: 'e'.repeat(64),
          point: { lines: [3, 4], label: 'the loop' } });
        expect(marked()).toEqual([3, 4]);
        expect(box.querySelector('.workbench-ai-chip .workbench-selection-text').textContent).toBe('AI: lines 3–4 · the loop');
        // Another version of the file, or another item: not marked.
        window.Workbench.onPoint({ item_id: 'i_t', version: 'f'.repeat(64), point: { lines: [1, 1] } });
        expect(marked()).toEqual([]);
        window.Workbench.onPoint({ item_id: 'i_t', version: 'e'.repeat(64), point: { lines: [5, 5] } });
        expect(marked()).toEqual([5]);
        box.querySelector('.workbench-ai-chip .workbench-selection-aside').click();
        expect(marked()).toEqual([]);
        expect(box.querySelector('.workbench-ai-chip')).toBeNull();
        window.Workbench.onPoint({ item_id: 'i_t', version: 'e'.repeat(64), point: { lines: [2, 2] } });
        window.Workbench.clearAiPoint();
        expect(marked()).toEqual([]);
      });

      test('draws where the AI pointed under its message, and marks it there again when clicked', async () => {
        const box = await showAsSelected(['a', 'b', 'c', 'd']);
        document.body.insertAdjacentHTML('beforeend', '<div id="m-ai" class="card"><div class="card-text"></div></div>');
        window.Workbench.drawShown('m-ai', [{ path: 'a.txt', name: 'a.txt', sha256: 'e'.repeat(64), preview: 'text',
          point: { lines: [2, 3], label: 'here' } }]);
        const line = document.querySelector('#m-ai .workbench-shown-note');
        expect(line.textContent).toContain('Pointed at in the work screen');
        expect(line.textContent).toContain('lines 2–3');
        line.querySelector('button').click();
        expect(Array.from(box.querySelectorAll('.workbench-line-ai')).length).toBe(2);
        document.getElementById('m-ai').remove();
      });

      test('gives the lines the user selected with the lines in view, held when the selection is gone', async () => {
        const box = await showAsSelected(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
        selectLines(box, 6, 7);
        expect((await answer(asked({ wants: ['range', 'selection'] }))).body)
          .toEqual({ range: { first_line: 3, last_line: 5 }, note: null, selected_lines: { first: 6, last: 7 } });
        window.getSelection().removeAllRanges();
        expect((await answer(asked({ wants: ['range', 'selection'] }))).body.selected_lines).toEqual({ first: 6, last: 7 });
        // Not asked for: not given.
        expect((await answer(asked())).body.selected_lines).toBeUndefined();
      });

      test('says the selection is changing while one of its selections waits for the server, and answers after', async () => {
        await showAsSelected(['a', 'b', 'c', 'd']);
        window.Workbench.select('i_t');
        expect((await answer(asked())).body).toEqual({ range: null, note: 'changing' });
        const seq = sent.filter((x) => x.payload.message === 'WORKBENCH_SELECT').pop().payload.seq;
        window.Workbench.onSelected({ type: 'workbench_selected', status: 'accepted', item_id: 'i_t', serial: 9, seq: seq });
        expect((await answer(asked())).body.note).toBe('selection_changed');
        expect((await answer(asked({ serial: 9 }))).body.range).toEqual({ first_line: 3, last_line: 4 });
      });

      test('a refused selection also ends the wait', async () => {
        await showAsSelected(['a', 'b', 'c', 'd']);
        window.Workbench.select('i_t');
        const seq = sent.filter((x) => x.payload.message === 'WORKBENCH_SELECT').pop().payload.seq;
        window.Workbench.onSelected({ type: 'workbench_selected', status: 'refused', item_id: 'i_t', serial: 7, seq: seq });
        expect((await answer(asked())).body.range).toEqual({ first_line: 3, last_line: 4 });
      });

      test('gives nothing for another item, version or selection, and says why it has no lines', async () => {
        await showAsSelected(['a', 'b', 'c', 'd']);
        for (const other of [{ item_id: 'i_x' }, { version: 'f'.repeat(64) }, { serial: 6 }]) {
          expect((await answer(asked(other))).body).toEqual({ range: null, note: 'selection_changed' });
        }
        layout.pane = 'settings';
        expect((await answer(asked())).body).toEqual({ range: null, note: 'not_shown' });
        expect((await answer(asked({ wants: [] }))).body.range).toBeNull();
      });
    });

    test('says a text is empty once drawn with no line, and drawing before', async () => {
      layout.pane = 'work';
      let release;
      global.fetch = jest.fn(() => new Promise((resolve) => { release = resolve; }));
      view([notes], { assets: { i_t: '/workbench/asset/t' } });
      const box = document.querySelector('#workbench-view .workbench-text');
      box.getBoundingClientRect = () => ({ top: 40, bottom: 100, left: 0, right: 400, height: 60 });
      expect(window.Workbench.rangeNow()).toMatchObject({ range: null, note: 'drawing' });
      release({ ok: true, status: 200, text: async () => '', headers: { get: () => null } });
      await flush();
      await flush();
      expect(window.Workbench.rangeNow()).toMatchObject({ range: null, note: 'empty' });
    });

    describe('answering a capture of an image', () => {
      const photo = { id: 'i_g', kind: 'file', actor: 'user', name: 'g.png', path: 'g.png', preview: 'image',
        sha256: 'e'.repeat(64), version: 'e'.repeat(64), status: 'ok' };
      let pointerNow;
      let drawnShapes;
      let drawImage;
      let markChanged;
      let markSeq;

      beforeEach(async () => {
        layout.pane = 'work';
        pointerNow = null;
        markSeq = 1;
        drawnShapes = [];
        drawImage = jest.fn();
        window.WorkbenchPointer = {
          COLORS: { cyan: { fill: 'rgba(0,0,0,0.2)', line: '#000' } },
          attach: (opts) => {
            markChanged = opts.changed;
            return { controls: Object.assign(document.createElement('div'), { className: 'workbench-pointer-controls' }),
              pointer: () => pointerNow, pointerSeq: () => markSeq, escape: () => false, setPointable: () => {},
              marks: () => (pointerNow ? [Object.assign({ id: 'm_fakemark0001', rev: markSeq }, pointerNow)] : []),
              drop: () => {}, clear: () => { pointerNow = null; }, dispose: jest.fn() };
          }
        };
        jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => ({
          drawImage, save: () => {}, restore: () => {}, beginPath: () => {}, fill: () => {}, stroke: () => {},
          rect: (...a) => drawnShapes.push(['rect', ...a]), ellipse: (...a) => drawnShapes.push(['ellipse', ...a]),
          arc: () => {}, fillText: (text) => drawnShapes.push(['number', text])
        }));
        jest.spyOn(HTMLCanvasElement.prototype, 'toDataURL').mockImplementation(() => 'data:image/png;base64,QUJD');
        view([photo], { assets: { i_g: '/workbench/asset/g' }, selected: 'i_g', selection_serial: 3 });
        await flush();
        const img = document.querySelector('#workbench-view .workbench-image-frame img');
        Object.defineProperty(img, 'complete', { value: true });
        Object.defineProperty(img, 'naturalWidth', { value: 800 });
        Object.defineProperty(img, 'naturalHeight', { value: 600 });
      });

      afterEach(() => {
        delete window.WorkbenchPointer;
        jest.restoreAllMocks();
      });

      async function answer(wants = ['image']) {
        const posted = jest.fn(() => Promise.resolve({ status: 204 }));
        global.fetch = posted;
        window.Workbench.onCapture({ type: 'workbench_capture', id: 'cap-g', item_id: 'i_g', version: 'e'.repeat(64),
          serial: 3, wants: wants });
        await flush();
        return JSON.parse(posted.mock.calls[0][1].body);
      }

      test('shows the image with the pointer\'s buttons above it', () => {
        expect(document.querySelector('#workbench-view .workbench-image-bar .workbench-pointer-controls')).not.toBeNull();
        expect(document.querySelector('#workbench-view .workbench-image-frame img.workbench-image')).not.toBeNull();
      });

      test('shows the pointer\'s own buttons over an image, which is not dragged as a file', async () => {
        window.WorkbenchPointer = undefined;
        jest.isolateModules(() => { require(js('monadic/workbench-pointer.js')); });
        const other = Object.assign({}, photo, { id: 'i_h', name: 'h.png', path: 'h.png' });
        view([other], { assets: { i_h: '/workbench/asset/h' }, selected: 'i_h', selection_serial: 4 });
        await flush();
        const controls = document.querySelector('#workbench-view .workbench-image-bar .workbench-pointer-controls');
        expect(controls).not.toBeNull();
        expect(controls.hidden).toBe(false);
        expect(document.querySelector('#workbench-view .workbench-image-frame img').draggable).toBe(false);
        expect(document.querySelector('#workbench-view .workbench-image-frame .workbench-pointer-layer')).not.toBeNull();
      });

      test('gives the whole image with the mark drawn on it, and where the mark is', async () => {
        pointerNow = { at: 1, by: 'user', shape: 'ellipse', color: 'cyan', x: 0.25, y: 0.5, w: 0.5, h: 0.25 };
        const body = await answer();
        expect(drawImage).toHaveBeenCalledWith(expect.anything(), 0, 0, 800, 600, 0, 0, 800, 600);
        expect(drawnShapes).toEqual([['ellipse', 400, 375, 200, 75, 0, 0, Math.PI * 2]]);
        expect(body).toMatchObject({ image: 'QUJD', mark: { shape: 'ellipse', color: 'cyan', x: 0.25, y: 0.5, w: 0.5, h: 0.25 },
          crop: { x: 0, y: 0, width: 800, height: 600, sent_width: 800, sent_height: 600 } });
      });

      test('takes the image with the mark drawn on it when the mark is made, to go with a message once for each place of it', () => {
        expect(window.Workbench.picturesNow()).toBeNull();
        pointerNow = { at: 1, by: 'user', shape: 'rect', color: 'cyan', x: 0.25, y: 0.5, w: 0.5, h: 0.25 };
        markChanged();
        const pictures = window.Workbench.picturesNow();
        expect(pictures.data).toHaveLength(1);
        expect(pictures.data[0]).toMatchObject({ item_id: 'i_g', version: 'e'.repeat(64), image: 'QUJD' });
        expect(pictures.data[0].marks).toEqual([{ id: 'm_fakemark0001', rev: 1,
          mark: { shape: 'rect', color: 'cyan', x: 0.25, y: 0.5, w: 0.5, h: 0.25 }, rect: { x: 0.25, y: 0.5, w: 0.5, h: 0.25 } }]);
        // The marked item's picture goes, not the chosen item's single one.
        expect(window.Workbench.pictureNow()).toBeNull();
        pictures.sent();
        expect(window.Workbench.picturesNow()).toBeNull();
        // Moved: it goes again, as the same mark.
        markSeq = 2;
        pointerNow = Object.assign({}, pointerNow, { x: 0.1 });
        markChanged();
        const again = window.Workbench.picturesNow();
        expect(again.data[0].marks[0]).toMatchObject({ id: 'm_fakemark0001', rev: 2 });
        // Taken away: nothing goes.
        pointerNow = null;
        markChanged();
        expect(window.Workbench.picturesNow()).toBeNull();
      });

      test('sends the marked items on the desk in their order, at most four, and says which go when more are marked', () => {
        document.getElementById('work-screen-pane').insertAdjacentHTML('afterbegin', '<div class="workbench-head"></div>');
        const hooks = [];
        window.WorkbenchPointer.attach = (opts) => {
          hooks.push(opts.changed);
          return { controls: document.createElement('div'), pointer: () => pointerNow, pointerSeq: () => 1, escape: () => false,
            marks: () => (pointerNow ? [Object.assign({ id: 'm_fakemark0001', rev: 1 }, pointerNow)] : []),
            drop: () => {}, setPointable: () => {}, dispose: jest.fn() };
        };
        const photos = [1, 2, 3, 4, 5].map((n) => Object.assign({}, photo, { id: `i_${n}`, name: `${n}.png`,
          sha256: String(n).repeat(64), version: String(n).repeat(64), place: n === 5 ? 'latest' : 'current' }));
        view(photos, { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: photos } });
        pointerNow = { at: 1, by: 'user', shape: 'rect', color: 'cyan', x: 0.25, y: 0.5, w: 0.5, h: 0.25 };
        photos.forEach((p) => {
          window.Workbench.select(p.id);
          const img = document.querySelector(`.workbench-section[data-item="${p.id}"] .workbench-image-frame img`);
          Object.defineProperty(img, 'complete', { value: true });
          Object.defineProperty(img, 'naturalWidth', { value: 80 });
          Object.defineProperty(img, 'naturalHeight', { value: 60 });
        });
        // Each drawn image's mark is made.
        hooks.forEach((changed) => changed());
        const pictures = window.Workbench.picturesNow();
        expect(pictures.data.map((d) => d.item_id)).toEqual(['i_1', 'i_2', 'i_3', 'i_4']);
        expect(pictures.left).toBe(1);
        const line = document.getElementById('workbench-marks');
        expect(line.hidden).toBe(false);
        expect(line.textContent).toContain('5 marked pictures wait');
        pictures.sent();
        expect(window.Workbench.picturesNow().data.map((d) => d.item_id)).toEqual(['i_5']);
        expect(line.hidden).toBe(true);
      });

      test('draws the marks earlier messages sent, lighter and fixed, and erases them with the next message', () => {
        const marks = [{ id: 'm_aaaaaa', rev: 1, shape: 'ellipse', color: 'cyan', rect: { x: 0.1, y: 0.2, w: 0.3, h: 0.4 } }];
        const marked = Object.assign({}, photo, { place: 'latest', marks: marks });
        view([marked], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [marked] } });
        const box = document.querySelector('.workbench-section[data-item="i_g"] .workbench-marks-earlier .workbench-mark-earlier');
        expect(box.classList.contains('is-ellipse')).toBe(true);
        expect([box.style.left, box.style.top, box.style.width, box.style.height]).toEqual(['10%', '20%', '30%', '40%']);
        expect(menuEntry('i_g', 'Erase marks (1)')).toMatchObject({ icon: 'fa-solid fa-eraser' });
        expect(window.Workbench.erasuresNow()).toBeNull();
        run('i_g', 'Erase marks (1)');
        expect(document.querySelectorAll('.workbench-section[data-item="i_g"] .workbench-mark-earlier')).toHaveLength(0);
        const erasures = window.Workbench.erasuresNow();
        expect(erasures.data).toEqual([{ item_id: 'i_g', version: 'e'.repeat(64), targets: [['m_aaaaaa', 1]] }]);
        erasures.sent();
        expect(window.Workbench.erasuresNow()).toBeNull();
        // Before: drawn, and not erased from there.
        const before = Object.assign({}, marked, { place: 'previous' });
        view([before], { board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [before] } });
        expect(document.querySelectorAll('.workbench-section[data-item="i_g"] .workbench-mark-earlier')).toHaveLength(1);
        expect(menuOf('i_g').some((e) => e.label.startsWith('Erase marks'))).toBe(false);
      });

      test('sends the marks of an image in one picture, numbered, and forgets those drawn as earlier ones', () => {
        let list = [
          { id: 'm_first000001', rev: 1, page: 1, shape: 'rect', color: 'cyan', x: 0.1, y: 0.1, w: 0.2, h: 0.2 },
          { id: 'm_second00002', rev: 3, page: 1, shape: 'ellipse', color: 'cyan', x: 0.5, y: 0.5, w: 0.25, h: 0.25 }];
        const dropped = [];
        window.WorkbenchPointer.attach = (opts) => {
          markChanged = opts.changed;
          return { controls: document.createElement('div'), pointer: () => list[1], pointerSeq: () => 4, escape: () => false,
            marks: () => list, drop: (ids) => { dropped.push(ids); list = list.filter((m) => !ids.includes(m.id)); },
            setPointable: () => {}, clear: () => {}, dispose: jest.fn() };
        };
        const other = Object.assign({}, photo, { id: 'i_h', name: 'h.png', path: 'h.png', place: 'current' });
        view([other], { assets: { i_h: '/workbench/asset/h' }, selected: 'i_h', selection_serial: 4,
          board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [other] } });
        const img = document.querySelector('.workbench-section[data-item="i_h"] .workbench-image-frame img');
        Object.defineProperty(img, 'complete', { value: true });
        Object.defineProperty(img, 'naturalWidth', { value: 800 });
        Object.defineProperty(img, 'naturalHeight', { value: 600 });
        drawnShapes.length = 0;
        markChanged();
        const pictures = window.Workbench.picturesNow();
        expect(pictures.data).toHaveLength(1);
        expect(pictures.data[0].marks.map((m) => [m.id, m.rev, m.mark.shape])).toEqual([
          ['m_first000001', 1, 'rect'], ['m_second00002', 3, 'ellipse']]);
        expect(drawnShapes.map((d) => (d[0] === 'number' ? d[1] : d[0]))).toEqual(['rect', '1', 'ellipse', '2']);
        pictures.sent();
        expect(window.Workbench.picturesNow()).toBeNull();
        // The next view has them as the item's marks: they are no longer here to change.
        const sent = Object.assign({}, other, { marks: [
          { id: 'm_first000001', rev: 1, shape: 'rect', color: 'cyan', rect: { x: 0.1, y: 0.1, w: 0.2, h: 0.2 } }] });
        view([sent], { board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [sent] } });
        expect(dropped.at(-1)).toEqual(['m_first000001']);
        expect(list.map((m) => m.id)).toEqual(['m_second00002']);
      });

      test('sends where the mark is on the whole image with its picture', () => {
        pointerNow = { at: 1, by: 'user', shape: 'rect', color: 'cyan', x: 0.25, y: 0.5, w: 0.5, h: 0.25 };
        markChanged();
        expect(window.Workbench.picturesNow().data[0].marks[0].rect).toEqual({ x: 0.25, y: 0.5, w: 0.5, h: 0.25 });
      });

      test('gives no image when nothing is marked, or when no image is asked for', async () => {
        expect((await answer()).image).toBeUndefined();
        pointerNow = { at: 1, by: 'user', shape: 'rect', color: 'cyan', x: 0.25, y: 0.5, w: 0.5, h: 0.25 };
        expect((await answer(['range'])).image).toBeUndefined();
        expect(drawImage).not.toHaveBeenCalled();
      });
    });

    describe('answering a capture of a PDF', () => {
      const paper = { id: 'i_p', kind: 'file', actor: 'user', name: 'p.pdf', path: 'p.pdf', preview: 'pdf',
        sha256: 'f'.repeat(64), version: 'f'.repeat(64), status: 'ok' };
      let shown;
      let canvas;
      let layer;
      let drawImage;
      let encoded;
      let pointerNow;
      let drawnShapes;
      let turnedTo;
      let settled;

      beforeEach(async () => {
        layout.pane = 'work';
        pointerNow = null;
        drawnShapes = [];
        shown = { status: 'ready', page: 2, pages: 5, scale: 1, drawing: 4 };
        // The canvas is drawn at twice the screen's pixels: 800 × 1000 for
        // 400 × 500 on screen, its top 100px above the window.
        canvas = document.createElement('canvas');
        canvas.width = 800;
        canvas.height = 1000;
        canvas.getBoundingClientRect = () => ({ top: -100, bottom: 400, left: 0, right: 400, width: 400, height: 500 });
        layer = document.createElement('div');
        layer.className = 'textLayer';
        layer.innerHTML = '<span>chosen words</span>';
        drawImage = jest.fn();
        encoded = () => 'data:image/png;base64,QUJD';
        jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => ({
          drawImage, save: () => {}, restore: () => {}, beginPath: () => {}, fill: () => {}, stroke: () => {},
          rect: (...a) => drawnShapes.push(['rect', ...a]), ellipse: (...a) => drawnShapes.push(['ellipse', ...a])
        }));
        jest.spyOn(HTMLCanvasElement.prototype, 'toDataURL').mockImplementation(() => encoded());
        turnedTo = null;
        window.WorkbenchPdf = {
          show: (box, _bytes, onChange) => {
            const sheet = document.createElement('div');
            sheet.className = 'workbench-pdf-page';
            sheet.getBoundingClientRect = () => ({ top: -100, bottom: 400, left: 0, right: 400 });
            const bar = document.createElement('div');
            bar.className = 'workbench-pdf-bar';
            sheet.append(canvas, layer);
            box.append(bar, sheet);
            settled = onChange;
            return { shown: () => shown, canvas: () => canvas, textLayer: () => layer, dispose: () => {}, state: () => ({}),
              pointer: () => pointerNow, pointerSeq: () => 1, setPointable: () => {}, goTo: (n) => { turnedTo = n; } };
          }
        };
        global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, arrayBuffer: async () => new ArrayBuffer(4) }));
        view([paper], { assets: { i_p: '/workbench/asset/p' }, selected: 'i_p', selection_serial: 3 });
        await flush();
        document.querySelector('#workbench-view .workbench-pdf').getBoundingClientRect =
          () => ({ top: 0, bottom: 500, left: 0, right: 400, height: 500 });
      });

      afterEach(() => {
        delete window.WorkbenchPdf;
        jest.restoreAllMocks();
      });

      async function answer(wants = ['range', 'image', 'selection']) {
        const posted = jest.fn(() => Promise.resolve({ status: 204 }));
        global.fetch = posted;
        window.Workbench.onCapture({ type: 'workbench_capture', id: 'cap-p', item_id: 'i_p', version: 'f'.repeat(64),
          serial: 3, wants: wants });
        await flush();
        return JSON.parse(posted.mock.calls[0][1].body);
      }

      function select(node) {
        const range = document.createRange();
        range.selectNodeContents(node);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
      }

      test('cuts the part of the page in view in the canvas\'s own pixels, and gives the text selected in it', async () => {
        select(layer.querySelector('span'));
        const body = await answer();
        // In view: the page from 100px below its top, 400 × 400 on screen.
        expect(drawImage).toHaveBeenCalledWith(canvas, 0, 200, 800, 800, 0, 0, 800, 800);
        expect(body).toEqual({
          range: { page: 2, pages: 5 }, note: null, image: 'QUJD',
          crop: { x: 0, y: 200, width: 800, height: 800, sent_width: 800, sent_height: 800 },
          selection_text: 'chosen words', selection_cut: false
        });
      });

      test('turns to the page the AI points at, and marks the pieces of its text the quote is in', async () => {
        layer.innerHTML = '<span>the east</span><span>ern  library</span><span>other</span>';
        window.Workbench.onPoint({ item_id: 'i_p', version: 'f'.repeat(64), point: { page: 4, quote: 'eastern library' } });
        expect(turnedTo).toBe(4);
        expect(layer.querySelectorAll('.workbench-ai-hit')).toHaveLength(0);
        shown = { status: 'ready', page: 4, pages: 5, scale: 1, drawing: 5 };
        settled(shown);
        expect(Array.from(layer.querySelectorAll('.workbench-ai-hit')).map((el) => el.textContent))
          .toEqual(['the east', 'ern  library']);
        expect(document.querySelector('.workbench-pdf-bar .workbench-ai-chip').textContent).toContain('AI: page 4');
      });

      test('draws the mark the user put on the page on the part cut, and says where it is', async () => {
        // On the canvas: x 0.25..0.75 of 800, y 0.3..0.4 of 1000 (300..400px),
        // which is 100..200px of the part cut from 200px down.
        // The page's palette (workbench-pointer.js), as the page loads it.
        require(js('monadic/workbench-pointer.js'));
        pointerNow = { page: 2, shape: 'rect', color: 'cyan', x: 0.25, y: 0.3, w: 0.5, h: 0.1 };
        const body = await answer();
        expect(body.mark).toEqual({ shape: 'rect', color: 'cyan', x: 0.25, y: 0.125, w: 0.5, h: 0.125 });
        expect(drawnShapes).toEqual([['rect', 200, 100, 400, 100]]);
        // A mark on another page is neither drawn nor said.
        pointerNow = Object.assign({}, pointerNow, { page: 3 });
        drawnShapes = [];
        expect((await answer()).mark).toBeUndefined();
        expect(drawnShapes).toEqual([]);
        delete window.WorkbenchPointer;
      });

      test('gives the text inside the mark, from the pieces of the text layer whose middle is in it', async () => {
        // The mark on screen: x 100..300, y 50..100 (the canvas's top is
        // 100px above the window).
        pointerNow = { page: 2, shape: 'rect', color: 'cyan', x: 0.25, y: 0.3, w: 0.5, h: 0.1 };
        const piece = (text, left, top) => {
          const span = document.createElement('span');
          span.textContent = text;
          span.getBoundingClientRect = () => ({ left: left, top: top, width: 40, height: 10 });
          return span;
        };
        layer.innerHTML = '';
        layer.append(piece('the eastern', 102, 52), document.createElement('br'), piece('library', 200, 80),
                     piece('outside', 200, 300), piece('edge', 290, 60));
        const body = await answer();
        expect(body.mark_text).toBe('the eastern library');
        expect(body.mark_cut).toBe(false);
        // An ellipse leaves out what is in the corners of its box.
        pointerNow = Object.assign({}, pointerNow, { shape: 'ellipse' });
        expect((await answer()).mark_text).toBe('library');
        // Nothing of the layer inside it: no text.
        pointerNow = Object.assign({}, pointerNow, { shape: 'rect', y: 0.9, h: 0.05 });
        expect((await answer()).mark_text).toBeUndefined();
      });

      test('gives the text the user selected on the page when the selection itself is gone', async () => {
        select(layer.querySelector('span'));
        document.dispatchEvent(new Event('selectionchange'));
        window.getSelection().removeAllRanges();
        const body = await answer(['range', 'selection']);
        expect(body).toMatchObject({ selection_text: 'chosen words', selection_cut: false });
      });

      test('draws a large part no larger than it sends', async () => {
        canvas.width = 4000;
        canvas.height = 5000;
        const body = await answer(['range', 'image']);
        expect(body.crop).toMatchObject({ width: 4000, height: 4000, sent_width: 2048, sent_height: 2048 });
        expect(drawImage).toHaveBeenCalledWith(canvas, 0, 1000, 4000, 4000, 0, 0, 2048, 2048);
        // Wider than high: the long side is held to 2048, the pixels too.
        canvas.width = 8000;
        canvas.height = 2500;
        canvas.getBoundingClientRect = () => ({ top: 0, bottom: 125, left: 0, right: 400, width: 400, height: 125 });
        const wide = (await answer(['range', 'image'])).crop;
        expect(wide).toMatchObject({ width: 8000, height: 2500, sent_width: 2048, sent_height: 640 });
        expect(wide.sent_width * wide.sent_height).toBeLessThanOrEqual(4194304);
      });

      test('gives no image when the page was drawn again meanwhile, nor a selection outside the PDF', async () => {
        encoded = () => {
          shown = Object.assign({}, shown, { drawing: 5 });
          return 'data:image/png;base64,QUJD';
        };
        select(document.getElementById('message'));
        const body = await answer();
        expect(body).toEqual({ range: { page: 2, pages: 5 }, note: null, image_note: 'redrawn' });
      });

      test('says when none of the page is in view, and gives only what was asked for', async () => {
        canvas.getBoundingClientRect = () => ({ top: 900, bottom: 1400, left: 0, right: 400, width: 400, height: 500 });
        expect((await answer()).image_note).toBe('not_in_view');
        expect(await answer(['range'])).toEqual({ range: { page: 2, pages: 5 }, note: null });
      });

      test('cuts a long selection', async () => {
        layer.innerHTML = `<span>${'x'.repeat(8005)}</span>`;
        select(layer.querySelector('span'));
        const body = await answer(['range', 'selection']);
        expect(body.selection_text.length).toBe(8000);
        expect(body.selection_cut).toBe(true);
      });
    });

    test('gives a PDF page only once it is drawn, and nothing with no item selected', async () => {
      layout.pane = 'work';
      expect(window.Workbench.rangeNow()).toBeNull();
      let shown = { status: 'drawing' };
      let sheet = null;
      window.WorkbenchPdf = {
        show: (box) => {
          // The bar, then the page, as workbench-pdf.js draws them.
          sheet = document.createElement('div');
          sheet.className = 'workbench-pdf-page';
          sheet.getBoundingClientRect = () => ({ top: 40, bottom: 500, left: 0, right: 400 });
          box.appendChild(sheet);
          return { shown: () => shown, dispose: () => {}, state: () => ({}) };
        }
      };
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, arrayBuffer: async () => new ArrayBuffer(4) }));
      const paper = { id: 'i_p', kind: 'file', actor: 'user', name: 'p.pdf', path: 'p.pdf', preview: 'pdf',
        sha256: 'f'.repeat(64), version: 'f'.repeat(64), status: 'ok' };
      try {
        view([paper], { assets: { i_p: '/workbench/asset/p' } });
        await flush();
        document.querySelector('#workbench-view .workbench-pdf').getBoundingClientRect =
          () => ({ top: 0, bottom: 500, left: 0, right: 400, height: 500 });
        expect(window.Workbench.rangeNow()).toMatchObject({ range: null, note: 'drawing' });
        shown = { status: 'ready', page: 2, pages: 5, scale: 1.25 };
        expect(window.Workbench.rangeNow()).toMatchObject({ range: { page: 2, pages: 5, scale_percent: 125 }, note: null });
        // Part of the page in view (the window is 768px high): still that page.
        sheet.getBoundingClientRect = () => ({ top: 700, bottom: 1200, left: 0, right: 400 });
        expect(window.Workbench.rangeNow()).toMatchObject({ range: { page: 2 }, note: null });
        // Only the bar above the page in view.
        sheet.getBoundingClientRect = () => ({ top: 800, bottom: 1300, left: 0, right: 400 });
        expect(window.Workbench.rangeNow()).toMatchObject({ range: null, note: 'not_shown' });
        // None of the PDF in view.
        document.querySelector('#workbench-view .workbench-pdf').getBoundingClientRect =
          () => ({ top: 900, bottom: 1400, left: 0, right: 400, height: 500 });
        expect(window.Workbench.rangeNow()).toMatchObject({ range: null, note: 'not_shown' });
      } finally {
        delete window.WorkbenchPdf;
      }
    });

    test('gives the part of the PDF in view with the pointer drawn on it, once for each placing of it', async () => {
      layout.pane = 'work';
      const drawn = [];
      const realGetContext = HTMLCanvasElement.prototype.getContext;
      const realToDataURL = HTMLCanvasElement.prototype.toDataURL;
      HTMLCanvasElement.prototype.getContext = () => ({
        drawImage: () => {}, save: () => {}, restore: () => {}, beginPath: () => {}, fill: () => {}, stroke: () => {},
        rect: (...a) => drawn.push(['rect', ...a]), ellipse: (...a) => drawn.push(['ellipse', ...a])
      });
      HTMLCanvasElement.prototype.toDataURL = () => 'data:image/png;base64,UElDVFVSRQ==';
      let pointer = null;
      let seq = 0;
      let marked = null;
      const page = document.createElement('canvas');
      page.width = 800;
      page.height = 1000;
      // The canvas drawn 400 × 500, the upper half of it in view.
      page.getBoundingClientRect = () => ({ top: 0, bottom: 500, left: 0, right: 400, width: 400, height: 500 });
      window.WorkbenchPdf = {
        show: (box, _bytes, _onChange, onMark) => {
          marked = onMark;
          const sheet = document.createElement('div');
          sheet.className = 'workbench-pdf-page';
          sheet.getBoundingClientRect = () => ({ top: 0, bottom: 500, left: 0, right: 400 });
          box.appendChild(sheet);
          return { shown: () => ({ status: 'ready', page: 2, pages: 5, scale: 1, drawing: 1 }), dispose: () => {},
            state: () => ({}), canvas: () => page, pointer: () => pointer, pointerSeq: () => seq, setPointable: () => {},
            marks: () => (pointer ? [Object.assign({ id: 'm_fakemark0002', rev: seq }, pointer)] : []) };
        }
      };
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, arrayBuffer: async () => new ArrayBuffer(4) }));
      const paper = { id: 'i_p', kind: 'file', actor: 'user', name: 'p.pdf', path: 'p.pdf', preview: 'pdf',
        sha256: 'f'.repeat(64), version: 'f'.repeat(64), status: 'ok' };
      try {
        view([paper], { assets: { i_p: '/workbench/asset/p' } });
        await flush();
        document.querySelector('#workbench-view .workbench-pdf').getBoundingClientRect =
          () => ({ top: 0, bottom: 500, left: 0, right: 400, height: 500 });
        window.innerHeight = 250;
        expect(window.Workbench.picturesNow()).toBeNull();
        // On the page shown, in the upper half of the canvas.
        pointer = { page: 2, shape: 'ellipse', x: 0.25, y: 0.1, w: 0.5, h: 0.2 };
        seq = 1;
        marked();
        const pictures = window.Workbench.picturesNow();
        expect(pictures.data[0]).toMatchObject({ item_id: 'i_p', version: 'f'.repeat(64), page: 2, pages: 5, image: 'UElDVFVSRQ==' });
        expect(pictures.data[0].marks).toEqual([{ id: 'm_fakemark0002', rev: 1,
          mark: { shape: 'ellipse', color: 'orange', x: 0.25, y: 0.2, w: 0.5, h: 0.4 }, rect: { x: 0.25, y: 0.1, w: 0.5, h: 0.2 } }]);
        expect(drawn.map((d) => d[0])).toEqual(['ellipse']);
        // Sent: not again until the pointer changes.
        pictures.sent();
        expect(window.Workbench.picturesNow()).toBeNull();
        seq = 2;
        marked();
        expect(window.Workbench.picturesNow()).not.toBeNull();
        // Made on a page not shown: no picture of it.
        pointer = Object.assign({}, pointer, { page: 3 });
        seq = 3;
        marked();
        expect(window.Workbench.picturesNow()).toBeNull();
        // Below what is in view: the part cut is widened to it.
        pointer = { page: 2, shape: 'rect', x: 0.1, y: 0.8, w: 0.2, h: 0.1 };
        seq = 4;
        marked();
        expect(window.Workbench.picturesNow().data[0].marks).toHaveLength(1);
        // For a model that takes no images: none.
        pointer = { page: 2, shape: 'rect', x: 0.1, y: 0.1, w: 0.2, h: 0.1 };
        seq = 5;
        marked();
        document.body.insertAdjacentHTML('beforeend', '<select id="model"><option value="blind" selected>blind</option></select>');
        window.modelSpec = { blind: { vision_capability: false } };
        expect(window.Workbench.picturesNow()).toBeNull();
      } finally {
        delete window.WorkbenchPdf;
        delete window.modelSpec;
        HTMLCanvasElement.prototype.getContext = realGetContext;
        HTMLCanvasElement.prototype.toDataURL = realToDataURL;
      }
    });

    test('gives the page in view unmarked, each time, for a model that takes images and no tools, while the item is in view', async () => {
      layout.pane = 'work';
      const realGetContext = HTMLCanvasElement.prototype.getContext;
      const realToDataURL = HTMLCanvasElement.prototype.toDataURL;
      HTMLCanvasElement.prototype.getContext = () => ({ drawImage: () => {} });
      HTMLCanvasElement.prototype.toDataURL = () => 'data:image/png;base64,UElDVFVSRQ==';
      const page = document.createElement('canvas');
      page.width = 800;
      page.height = 1000;
      page.getBoundingClientRect = () => ({ top: 0, bottom: 500, left: 0, right: 400, width: 400, height: 500 });
      window.WorkbenchPdf = {
        show: () => ({ shown: () => ({ status: 'ready', page: 2, pages: 5, scale: 1, drawing: 1 }), dispose: () => {},
          state: () => ({}), canvas: () => page, pointer: () => null, pointerSeq: () => 0, setPointable: () => {} })
      };
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, arrayBuffer: async () => new ArrayBuffer(4) }));
      const paper = { id: 'i_p', kind: 'file', actor: 'user', name: 'p.pdf', path: 'p.pdf', preview: 'pdf',
        sha256: 'f'.repeat(64), version: 'f'.repeat(64), status: 'ok' };
      document.body.insertAdjacentHTML('beforeend', '<select id="model"><option value="looker" selected>looker</option></select>');
      try {
        view([paper], { assets: { i_p: '/workbench/asset/p' } });
        await flush();
        const part = document.querySelector('#workbench-view .workbench-section');
        part.getBoundingClientRect = () => ({ top: 0, bottom: 500, left: 0, right: 400 });
        window.innerHeight = 600;
        // A model that can look itself: nothing unmarked.
        window.modelSpec = { looker: { vision_capability: true } };
        expect(window.Workbench.pictureNow()).toBeNull();
        window.modelSpec = { looker: { vision_capability: true, tool_capability: false } };
        const picture = window.Workbench.pictureNow();
        expect(picture.data).toMatchObject({ item_id: 'i_p', version: 'f'.repeat(64), page: 2, pages: 5, unmarked: true,
          image: 'UElDVFVSRQ==' });
        expect(picture.data).not.toHaveProperty('mark');
        picture.sent();
        expect(window.Workbench.pictureNow()).not.toBeNull();
        // Out of view: none.
        part.getBoundingClientRect = () => ({ top: 700, bottom: 900, left: 0, right: 400 });
        expect(window.Workbench.pictureNow()).toBeNull();
      } finally {
        delete window.WorkbenchPdf;
        delete window.modelSpec;
        document.getElementById('model').remove();
        HTMLCanvasElement.prototype.getContext = realGetContext;
        HTMLCanvasElement.prototype.toDataURL = realToDataURL;
      }
    });

    test('holds text selected in the PDF shown, offers it with a chip, and sends it once', async () => {
      layout.pane = 'work';
      const text = document.createElement('div');
      text.className = 'textLayer';
      text.innerHTML = '<span>the eastern library</span> <span>the western library</span>';
      window.WorkbenchPdf = {
        show: (box) => {
          const bar = document.createElement('div');
          bar.className = 'workbench-pdf-bar';
          box.appendChild(bar);
          box.appendChild(text);
          return { shown: () => ({ status: 'ready', page: 2, pages: 5, scale: 1, drawing: 1 }), dispose: () => {},
            state: () => ({}), textLayer: () => text, setPointable: () => {} };
        }
      };
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, arrayBuffer: async () => new ArrayBuffer(4) }));
      const paper = { id: 'i_p', kind: 'file', actor: 'user', name: 'p.pdf', path: 'p.pdf', preview: 'pdf',
        sha256: 'f'.repeat(64), version: 'f'.repeat(64), status: 'ok' };
      const select = (node) => {
        const range = document.createRange();
        range.selectNodeContents(node);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        document.dispatchEvent(new Event('selectionchange'));
      };
      const chip = () => document.querySelector('#workbench-view .workbench-selection-chip');
      try {
        view([paper], { assets: { i_p: '/workbench/asset/p' } });
        await flush();
        expect(chip()).toBeNull();
        expect(window.Workbench.selectionNow()).toBeNull();
        select(text.children[0]);
        expect(chip().textContent).toContain('(19 characters)');
        // Held when the selection moves to the message box.
        select(document.getElementById('message'));
        const offered = window.Workbench.selectionNow();
        expect(offered.data).toEqual({ item_id: 'i_p', version: 'f'.repeat(64), page: 2, pages: 5,
          text: 'the eastern library', cut: false });
        // Sent: not offered again until another is selected.
        offered.sent();
        expect(chip()).toBeNull();
        expect(window.Workbench.selectionNow()).toBeNull();
        select(text.children[0]);
        expect(window.Workbench.selectionNow()).toBeNull();
        select(text.children[1]);
        expect(window.Workbench.selectionNow().data.text).toBe('the western library');
        // Set aside with ×.
        chip().querySelector('.workbench-selection-aside').click();
        expect(chip()).toBeNull();
        expect(window.Workbench.selectionNow()).toBeNull();
        // A long selection is cut, and says so.
        text.children[0].textContent = 'x'.repeat(2500);
        select(text.children[0]);
        const long = window.Workbench.selectionNow().data;
        expect(Array.from(long.text)).toHaveLength(2000);
        expect(long.cut).toBe(true);
      } finally {
        delete window.WorkbenchPdf;
      }
    });

    test('draws a line on the card of a message sent with selected text, which shows the text', () => {
      const el = card('m-s');
      window.Workbench.drawSelection('m-s', { item_id: 'i_p', version: 'v', page: 3, pages: 5, text: '<b>the eastern</b> library', cut: false });
      const line = el.querySelector('.workbench-selection-note');
      expect(line.textContent).toContain('page 3');
      const quote = line.querySelector('.workbench-selection-quote');
      expect(quote.hidden).toBe(true);
      line.querySelector('button').click();
      expect(quote.hidden).toBe(false);
      expect(quote.textContent).toBe('<b>the eastern</b> library');
      expect(quote.querySelector('b')).toBeNull();
      window.Workbench.drawSelection('m-s', null);
      expect(el.querySelector('.workbench-selection-note')).toBeNull();
    });

    test('draws a line on the card of a message sent with a picture, which asks for it and shows it', () => {
      const el = card('m-u');
      window.Workbench.drawPicture('m-u', { id: 'p_' + 'a'.repeat(20), page: 3 });
      const line = el.querySelector('.workbench-picture-note');
      expect(line.textContent).toContain('page 3');
      line.querySelector('button').click();
      expect(sent.at(-1).payload).toEqual({ message: 'WORKBENCH_PICTURE', picture_id: 'p_' + 'a'.repeat(20) });
      layout.pane = 'work';
      window.Workbench.onPicture({ picture_id: 'p_' + 'a'.repeat(20), found: true, data: 'data:image/png;base64,UElDVFVSRQ==' });
      expect(document.querySelector('#workbench-view img').getAttribute('src')).toBe('data:image/png;base64,UElDVFVSRQ==');
      window.Workbench.onPicture({ picture_id: 'p_' + 'b'.repeat(20), found: false });
      expect(window.setAlert).toHaveBeenCalled();
      // Lines of a text: their numbers, and the lines as they are.
      window.Workbench.drawSelection('m-u', { kind: 'text', first: 2, last: 3, text: 'def a\n  1\nend' });
      const lines = el.querySelector('.workbench-selection-note');
      expect(lines.textContent).toContain('Selected lines (2–3)');
      expect(lines.querySelector('pre.workbench-selection-lines').textContent).toBe('def a\n  1\nend');
      // A picture of an image has no page.
      window.Workbench.drawPicture('m-u', { id: 'p_' + 'c'.repeat(20), kind: 'image' });
      expect(el.querySelector('.workbench-picture-note').textContent).toContain('(image)');
      window.Workbench.drawPicture('m-u', null);
      expect(el.querySelector('.workbench-picture-note')).toBeNull();
    });

    test('offers the image a look sent, and the images an edit sent, which ask for them and show them', () => {
      const el = card('m-r');
      const sha = 'a'.repeat(64);
      window.Workbench.drawLooks('m-r', [
        { id: 'look_' + 'a'.repeat(16), name: 'cat.png', kind: 'image', state: 'sent', image_sha256: sha },
        { id: 'look_' + 'b'.repeat(16), name: 'notes.txt', kind: 'text', state: 'sent' },
        { id: 'look_' + 'c'.repeat(16), name: 'dog.png', kind: 'image', state: 'unsent', image_sha256: 'c'.repeat(64) }
      ]);
      const buttons = [...el.querySelectorAll('.workbench-look-note .workbench-sent-open')];
      expect(buttons.map((b) => b.dataset.sha256)).toEqual([sha]);
      buttons[0].click();
      expect(sent.at(-1).payload).toEqual({ message: 'WORKBENCH_SENT_IMAGE', mid: 'm-r', sha256: sha });
      window.Workbench.drawEdits('m-r', [
        { call: 'e_' + 'd'.repeat(16), role: 'original', sha256: 'd'.repeat(64), content_type: 'image/png', state: 'sent' },
        { call: 'e_' + 'd'.repeat(16), role: 'reference', sha256: 'e'.repeat(64), content_type: 'image/png', state: 'sent' }
      ]);
      const edits = [...el.querySelectorAll('.workbench-edit-note .workbench-sent-open')];
      expect(edits.map((b) => b.textContent)).toEqual(['the image', 'the drawing on it']);
      edits[1].click();
      expect(sent.at(-1).payload).toEqual({ message: 'WORKBENCH_SENT_IMAGE', mid: 'm-r', sha256: 'e'.repeat(64) });
      layout.pane = 'work';
      window.Workbench.onSentImage({ mid: 'm-r', sha256: sha, found: true, data: 'data:image/png;base64,U0VOVA==' });
      expect(document.querySelector('#workbench-view img').getAttribute('src')).toBe('data:image/png;base64,U0VOVA==');
      window.setAlert.mockClear();
      window.Workbench.onSentImage({ mid: 'm-r', sha256: sha, found: false });
      expect(window.setAlert).toHaveBeenCalled();
      window.Workbench.drawEdits('m-r', []);
      expect(el.querySelector('.workbench-edit-note')).toBeNull();
    });

    test('says what a reply read from the Library, and opens it from the note and from a cited link', () => {
      const el = card('m-l');
      const cited = 'x_' + 'b'.repeat(16);
      window.Workbench.drawReadings('m-l', [
        { id: 'r_' + 'a'.repeat(16), query: 'notes', path: 'conversations/c/workbench/library-r.md',
          excerpts: [{ id: 'x_' + 'a'.repeat(16), conversation_id: 'conv-1', text: 'one' },
            { id: cited, conversation_id: 'conv-1', text: 'two' }],
          cited: [cited] },
        { id: 'r_' + 'c'.repeat(16), query: 'nothing', excerpts: [] }
      ]);
      const lines = [...el.querySelectorAll('.workbench-reading-note .workbench-note-line')];
      expect(lines.map((l) => l.textContent)).toEqual([
        'Read from the Library: notes (2 passages, 1 cited) Show in the work screen',
        'Read from the Library: nothing (nothing found)'
      ]);
      lines[0].querySelector('.workbench-reading-open').click();
      expect(sent.at(-1).payload).toEqual({ message: 'WORKBENCH_OPEN', path: 'conversations/c/workbench/library-r.md' });
      sent.length = 0;
      const link = document.createElement('a');
      link.setAttribute('href', `mc:read:${cited}`);
      el.appendChild(link);
      link.click();
      expect(sent.at(-1).payload).toEqual({ message: 'WORKBENCH_OPEN', path: 'conversations/c/workbench/library-r.md' });
      window.Workbench.drawReadings('m-l', []);
      expect(el.querySelector('.workbench-reading-note')).toBeNull();
    });

    test('shows a cited passage as it was recorded once its copy on the work screen is gone, or when it had none', () => {
      const el = card('m-g');
      const shown = [];
      // Copies of the script loaded for earlier tests listen too, with no
      // records: they say a passage is gone (null), which is left out here.
      window.libraryPanel = { showExcerpt: (e) => { if (e) shown.push(e.text); } };
      try {
        const gone = 'x_' + 'd'.repeat(16);
        const bare = 'x_' + 'e'.repeat(16);
        window.Workbench.drawReadings('m-g', [
          { id: 'r_' + 'd'.repeat(16), query: 'tides', path: 'conversations/c/workbench/library-gone.md',
            excerpts: [{ id: gone, conversation_id: 'conv-1', title: 'Tides', text: 'as read' }], cited: [gone] },
          { id: 'r_' + 'e'.repeat(16), query: 'moon', excerpts: [{ id: bare, conversation_id: 'conv-2', text: 'no copy' }] }
        ]);
        const link = (id) => {
          const a = document.createElement('a');
          a.setAttribute('href', `mc:read:${id}`);
          el.appendChild(a);
          return a;
        };
        link(gone).click();
        expect(sent.at(-1).payload).toEqual({ message: 'WORKBENCH_OPEN', path: 'conversations/c/workbench/library-gone.md' });
        window.Workbench.onOpened({ status: 'refused', reason: 'missing', path: 'conversations/c/workbench/library-gone.md' });
        link(bare).click();
        expect(shown).toEqual(['as read', 'no copy']);
      } finally {
        delete window.libraryPanel;
        window.Workbench.drawReadings('m-g', []);
      }
    });
  });

  describe('a file put from the computer', () => {
    const file = (name, size = 10) => new File(['x'.repeat(size)], name);
    const flush = async () => { for (let i = 0; i < 20; i += 1) await new Promise((r) => setTimeout(r, 0)); };
    let posted;

    beforeEach(() => {
      posted = [];
      window.monadicFetch = {
        postJson: jest.fn(async (url, form) => {
          const f = form.get('file');
          posted.push({ url, purpose: form.get('purpose'), name: f.name });
          if (f.name.endsWith('.exe')) {
            const e = new Error('Files of this type cannot be attached here.');
            e.body = { reason: 'extension' };
            throw e;
          }
          return { attachment_id: `a_${f.name.replace(/\W/g, '')}`, name: f.name, size: f.size };
        })
      };
    });

    afterEach(() => { delete window.monadicFetch; });

    const opened = () => sent.filter((x) => x.payload.message === 'WORKBENCH_OPEN_ATTACHMENT').map((x) => x.payload.attachment_id);

    test('is put from the files a message was sent with (its data), as one from the computer is', async () => {
      window.Workbench.putDataFiles([
        { title: 'shot.png', type: 'image/png', data: 'data:image/png;base64,iVBORw0KGgo=' },
        { title: 'linked.pdf', type: 'application/pdf', data: 'https://example.com/linked.pdf' }
      ]);
      await flush();
      expect(posted).toEqual([{ url: '/attachments', purpose: 'workbench', name: 'shot.png' }]);
      expect(opened()).toEqual(['a_shotpng']);
    });

    test('is saved for the work screen and opened as an item, from the button', async () => {
      const input = document.getElementById('workbench-put-input');
      Object.defineProperty(input, 'files', { value: [file('paper.pdf')], configurable: true });
      input.dispatchEvent(new Event('change'));
      await flush();
      expect(posted).toEqual([{ url: '/attachments', purpose: 'workbench', name: 'paper.pdf' }]);
      expect(opened()).toEqual(['a_paperpdf']);
      expect(layout.pane).toBe('work');
    });

    test('is put when dropped on the work screen, a few at a time, and what is refused says why', async () => {
      const pane = document.getElementById('work-screen-pane');
      const drop = (type, files) => {
        const e = new Event(type, { bubbles: true, cancelable: true });
        e.dataTransfer = { types: ['Files'], files: files, dropEffect: 'none' };
        pane.dispatchEvent(e);
        return e;
      };
      drop('dragenter', []);
      expect(pane.classList.contains('workbench-dropping')).toBe(true);
      expect(drop('dragover', []).defaultPrevented).toBe(true);
      const files = ['a.png', 'tool.exe', 'c.md', 'd.md', 'e.md', 'f.md', 'g.md'].map((n) => file(n));
      expect(drop('drop', files).defaultPrevented).toBe(true);
      await flush();
      await flush();
      expect(pane.classList.contains('workbench-dropping')).toBe(false);
      expect(posted.map((p) => p.name)).toEqual(['a.png', 'tool.exe', 'c.md', 'd.md', 'e.md']);
      expect(opened()).toEqual(['a_apng', 'a_cmd', 'a_dmd', 'a_emd']);
      const alerts = window.setAlert.mock.calls.map((c) => String(c[0]));
      expect(alerts.some((a) => a.includes('Up to 5 files'))).toBe(true);
      expect(alerts.some((a) => a.includes('tool.exe') && a.includes('does not show this kind of file'))).toBe(true);
    });

    test('says on a view of an attachment that the AI does not see it', () => {
      layout.pane = 'work';
      window.Workbench.showAttachment({ key: 'img:1', kind: 'image', name: 'cat.png', data: 'data:image/png;base64,AAAA' });
      expect(document.querySelector('#workbench-view .workbench-local-note').textContent).toContain('The AI does not see this view');
    });
  });

  describe('in a Live Conversation', () => {
    const flush = async () => { for (let i = 0; i < 20; i += 1) await new Promise((r) => setTimeout(r, 0)); };

    afterEach(() => {
      document.body.classList.remove('lc-app');
      delete window.modelSpec;
      delete window.WorkbenchPdf;
    });

    async function pdfLive(provider) {
      document.body.insertAdjacentHTML('beforeend', '<select id="model"><option value="voice" selected>voice</option></select>');
      window.modelSpec = { voice: { sts_provider: provider } };
      layout.pane = 'work';
      const text = document.createElement('div');
      text.className = 'textLayer';
      text.innerHTML = '<span>the eastern library</span>';
      const pointable = [];
      window.WorkbenchPdf = {
        show: (box) => {
          const bar = document.createElement('div');
          bar.className = 'workbench-pdf-bar';
          box.append(bar, text);
          return { shown: () => ({ status: 'ready', page: 2, pages: 5, scale: 1, drawing: 1 }), dispose: () => {},
            state: () => ({}), textLayer: () => text, setPointable: (f) => pointable.push(f) };
        }
      };
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, arrayBuffer: async () => new ArrayBuffer(4) }));
      view([{ id: 'i_p', kind: 'file', actor: 'user', name: 'p.pdf', path: 'p.pdf', preview: 'pdf',
        sha256: 'f'.repeat(64), version: 'f'.repeat(64), status: 'ok' }], { assets: { i_p: '/workbench/asset/p' } });
      await flush();
      document.body.classList.add('lc-app');
      await flush();
      const range = document.createRange();
      range.selectNodeContents(text.firstChild);
      window.getSelection().removeAllRanges();
      window.getSelection().addRange(range);
      document.dispatchEvent(new Event('selectionchange'));
      return pointable;
    }

    test('offers the mark where the session takes the image of a look, and no chip: nothing is sent with a message', async () => {
      const pointable = await pdfLive('openai');
      expect(pointable.at(-1)).toBe(true);
      expect(document.querySelector('.workbench-selection-chip')).toBeNull();
      expect(window.Workbench.selectionNow()).toBeNull();
    });

    test('offers the mark in a Gemini session too, whose video input takes the image of a look', async () => {
      const pointable = await pdfLive('gemini');
      expect(pointable.at(-1)).toBe(true);
    });

    test('offers the mark in an xAI session too, whose look takes the text inside it', async () => {
      const pointable = await pdfLive('xai');
      expect(pointable.at(-1)).toBe(true);
      expect(document.querySelector('.workbench-selection-chip')).toBeNull();
    });
  });

  describe('a whiteboard', () => {
    const wb = { id: 'i_w', kind: 'file', actor: 'user', name: 'whiteboard-1.wb.json', path: 'c/whiteboards/whiteboard-1.wb.json',
      preview: 'text', render: 'whiteboard', sha256: 'a'.repeat(64), version: 'a'.repeat(64), status: 'ok' };
    const flushAll = async () => { for (let i = 0; i < 5; i += 1) await new Promise((r) => setTimeout(r, 0)); };
    let fetched;

    beforeEach(async () => {
      layout.pane = 'work';
      jest.isolateModules(() => {
        require(js('monadic/workbench-pointer.js'));
        require(js('monadic/workbench-whiteboard.js'));
      });
      fetched = [];
      global.fetch = jest.fn((url) => {
        fetched.push(url);
        return Promise.resolve({ ok: true, status: 200, text: async () => '{"shapes":[{"id":"a","type":"line","x1":0,"y1":0,"x2":10,"y2":10}]}',
          json: async () => ({ shapes: [] }), headers: { get: () => null } });
      });
      view([wb], { renders: { i_w: '/workbench/asset/render-i_w' }, selected: 'i_w', selection_serial: 2 });
      await flushAll();
      const svgEl = document.querySelector('#workbench-view svg');
      svgEl.getBoundingClientRect = () => ({ left: 0, top: 0, width: 800, height: 500 });
    });

    afterEach(() => {
      delete window.WorkbenchWhiteboard;
      delete global.fetch;
      jest.useRealTimers();
    });

    function drawStroke() {
      const svgEl = document.querySelector('#workbench-view svg');
      [['pointerdown', 10, 10], ['pointermove', 40, 40], ['pointerup', 40, 40]].forEach(([type, x, y]) => {
        svgEl.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, button: 0, bubbles: true }));
      });
    }

    const saves = () => sent.filter((x) => x.payload.message === 'WORKBENCH_WHITEBOARD_SAVE').map((x) => x.payload);

    test('draws the board from the file, and saves it a moment after the user stops drawing', async () => {
      expect(fetched).toContain('/workbench/asset/render-i_w');
      expect(document.querySelectorAll('#workbench-view .workbench-whiteboard-shape')).toHaveLength(1);
      jest.useFakeTimers();
      drawStroke();
      expect(saves()).toHaveLength(0);
      jest.advanceTimersByTime(1000);
      expect(saves()).toHaveLength(1);
      expect(saves()[0]).toMatchObject({ item_id: 'i_w', version: 'a'.repeat(64) });
      expect(saves()[0].data.shapes.map((sh) => sh.type)).toEqual(['line', 'pen']);
    });

    test('saves what was just drawn before a message, and draws a board that left Now as it was kept', async () => {
      jest.useFakeTimers();
      drawStroke();
      expect(saves()).toHaveLength(0);
      window.Workbench.flushWhiteboards();
      expect(saves()).toHaveLength(1);
      jest.useRealTimers();
      const kept = Object.assign({}, wb, { frozen: true, place: 'latest' });
      view([kept], { renders: { i_w: '/workbench/asset/render-i_w' }, selected: 'i_w', selection_serial: 3 });
      await flushAll();
      expect(document.querySelector('#workbench-view .workbench-whiteboard [data-tool]')).toBeNull();
      expect(document.querySelector('#workbench-view .workbench-whiteboard-frozen-note')).not.toBeNull();
    });

    test('draws no stroke on a board while a reply runs, and says why', async () => {
      view([Object.assign({}, wb, { place: 'current' })], { renders: { i_w: '/workbench/asset/render-i_w' }, selected: 'i_w',
        selection_serial: 3, board: { board_id: 'b1', chat_id: 'c_1', revision: 5, replying: true,
          items: [Object.assign({}, wb, { place: 'current' })] } });
      await flushAll();
      expect(document.querySelector('#workbench-view .workbench-whiteboard [data-tool]')).toBeNull();
      expect(document.querySelector('#workbench-view .workbench-whiteboard-frozen-note').textContent)
        .toBe('The work screen can be changed when the reply ends.');
    });

    test('says why a whiteboard was not placed or saved', () => {
      window.setAlert.mockClear();
      window.Workbench.onWhiteboard({ type: 'workbench_whiteboard', request: 999, status: 'refused', reason: 'whiteboard_used' });
      window.Workbench.onWhiteboard({ type: 'workbench_whiteboard', request: 998, status: 'refused', reason: 'whiteboard_frozen' });
      const texts = window.setAlert.mock.calls.map((c) => c[0]);
      expect(texts.some((x) => x.includes('placed in this turn already'))).toBe(true);
      expect(texts.some((x) => x.includes('left Now'))).toBe(true);
    });

    test('saves what was drawn meanwhile from the version the server answered, one save at a time', () => {
      jest.useFakeTimers();
      drawStroke();
      jest.advanceTimersByTime(1000);
      drawStroke();
      jest.advanceTimersByTime(1000);
      expect(saves()).toHaveLength(1);
      window.Workbench.onWhiteboard({ type: 'workbench_whiteboard', request: saves()[0].request, status: 'saved', item_id: 'i_w',
        version: 'b'.repeat(64) });
      expect(saves()).toHaveLength(2);
      expect(saves()[1].version).toBe('b'.repeat(64));
      expect(saves()[1].data.shapes).toHaveLength(3);
    });

    test('keeps the board drawn when the view brings the version it saved', () => {
      jest.useFakeTimers();
      drawStroke();
      jest.advanceTimersByTime(1000);
      window.Workbench.onWhiteboard({ request: saves()[0].request, status: 'saved', item_id: 'i_w', version: 'b'.repeat(64) });
      const svgEl = document.querySelector('#workbench-view svg');
      view([Object.assign({}, wb, { sha256: 'b'.repeat(64), version: 'b'.repeat(64) })],
        { renders: { i_w: '/workbench/asset/render-i_w-2' }, selected: 'i_w', selection_serial: 2 });
      expect(document.querySelector('#workbench-view svg')).toBe(svgEl);
      expect(fetched).not.toContain('/workbench/asset/render-i_w-2');
    });

    test('paints the whole board for a look that asks for an image', async () => {
      jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => new Proxy({}, {
        get: () => () => {}, set: () => true
      }));
      jest.spyOn(HTMLCanvasElement.prototype, 'toDataURL').mockImplementation(() => 'data:image/png;base64,V0I=');
      document.querySelector('#workbench-view .workbench-whiteboard').getBoundingClientRect =
        () => ({ top: 0, bottom: 500, left: 0, right: 800, height: 500 });
      const posted = jest.fn(() => Promise.resolve({ status: 204 }));
      global.fetch = posted;
      window.Workbench.onCapture({ type: 'workbench_capture', id: 'cap-w', item_id: 'i_w', version: 'a'.repeat(64), serial: 2,
        wants: ['image'] });
      await flushAll();
      const body = JSON.parse(posted.mock.calls[0][1].body);
      expect(body).toMatchObject({ image: 'V0I=', crop: { x: 0, y: 0, width: 1600, height: 1000, sent_width: 1600, sent_height: 1000 } });
      jest.restoreAllMocks();
    });

    test('gives a look no picture while lines wait to be saved, saving them, nor of another version than asked', async () => {
      jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => new Proxy({}, {
        get: () => () => {}, set: () => true
      }));
      jest.spyOn(HTMLCanvasElement.prototype, 'toDataURL').mockImplementation(() => 'data:image/png;base64,V0I=');
      document.querySelector('#workbench-view .workbench-whiteboard').getBoundingClientRect =
        () => ({ top: 0, bottom: 500, left: 0, right: 800, height: 500 });
      const posted = jest.fn(() => Promise.resolve({ status: 204 }));
      global.fetch = posted;
      const ask = async (version) => {
        window.Workbench.onCapture({ type: 'workbench_capture', id: 'cap-s', item_id: 'i_w', version: version, serial: 2,
          wants: ['image'] });
        await flushAll();
        return JSON.parse(posted.mock.calls.at(-1)[1].body);
      };
      drawStroke();
      const waiting = await ask('a'.repeat(64));
      expect(waiting.image).toBeUndefined();
      expect(waiting.image_note).toBe('saving');
      expect(saves()).toHaveLength(1);
      window.Workbench.onWhiteboard({ request: saves()[0].request, status: 'saved', item_id: 'i_w', version: 'b'.repeat(64) });
      view([Object.assign({}, wb, { sha256: 'b'.repeat(64), version: 'b'.repeat(64) })],
        { renders: { i_w: '/workbench/asset/render-i_w-2' }, selected: 'i_w', selection_serial: 2 });
      expect((await ask('b'.repeat(64))).image).toBe('V0I=');
      jest.restoreAllMocks();
    });

    test('writes the board out from its menu, named after it', () => {
      const exports = menuOf('i_w').filter((e) => e.label.startsWith('Export '));
      expect(exports.map((e) => e.label)).toEqual(['Export SVG', 'Export PNG', 'Export PDF']);
      const named = [];
      const click = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function record() { named.push(this.download); });
      const made = URL.createObjectURL;
      const revoke = URL.revokeObjectURL;
      URL.createObjectURL = jest.fn(() => 'blob:board');
      URL.revokeObjectURL = jest.fn();
      try {
        exports[0].action();
      } finally {
        click.mockRestore();
        URL.createObjectURL = made;
        URL.revokeObjectURL = revoke;
      }
      expect(named).toEqual(['whiteboard-1.svg']);
    });

    test('asks the server for a new whiteboard', () => {
      document.getElementById('work-screen-pane').insertAdjacentHTML('beforeend', '<button id="workbench-new-whiteboard"></button>');
      jest.resetModules();
      require(js('monadic/dom-helpers.js'));
      require(js('monadic/workbench-places.js'));
      require(js('monadic/workbench.js'));
      document.getElementById('workbench-new-whiteboard').click();
      expect(sent.at(-1).payload).toMatchObject({ message: 'WORKBENCH_WHITEBOARD_NEW' });
    });
  });

  describe('a file the work screen only holds', () => {
    test('shows its name, type and size, asks for nothing to show, and offers saving only when small enough', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      try {
        const doc = item({ id: 'i_d', kind: 'file', artifact_id: undefined, preview: 'file', name: 'report.docx',
          path: 'c/inputs/report.docx', size: 2 * 1024 * 1024, sha256: 'd'.repeat(64),
          content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' });
        view([doc], { selected: 'i_d' });
        const card = document.querySelector('#workbench-view .workbench-held-file');
        expect(card.textContent).toContain('report.docx');
        expect(card.textContent).toContain('2.0 MB');
        expect(card.querySelector('.fa-file-word')).not.toBeNull();
        expect(global.fetch).not.toHaveBeenCalled();
        expect(menuEntry('i_d', 'Download')).not.toBeNull();
        const big = Object.assign({}, doc, { size: 100 * 1024 * 1024 });
        view([big], { selected: 'i_d' });
        expect(menuEntry('i_d', 'Download')).toBeNull();
      } finally {
        delete global.fetch;
      }
    });
  });

  describe('the items one under another', () => {
    let observed;
    beforeEach(() => {
      observed = [];
      // Each item's part comes near the view when the test says so.
      global.IntersectionObserver = class {
        constructor(callback) { this.callback = callback; observed.push(this); this.nodes = []; }
        observe(node) { this.nodes.push(node); }
        unobserve(node) { this.nodes = this.nodes.filter((n) => n !== node); }
        near(node) { this.callback([{ target: node, isIntersecting: true }]); }
      };
      jest.resetModules();
      require(js('monadic/workbench-places.js'));
      require(js('monadic/workbench.js'));
    });
    afterEach(() => { delete global.IntersectionObserver; });

    const parts = () => Array.from(document.querySelectorAll('#workbench-view .workbench-section'));
    const partOf = (id) => parts().find((n) => n.dataset.item === id);

    test('shows every item in order, draws another once near, and moves the buttons to the one chosen without drawing again', () => {
      const a = item({ id: 'i_a', artifact_id: 'r_a', name: 'a.png' });
      const b = item({ id: 'i_b', artifact_id: 'r_b', name: 'b.png', sha256: 'b'.repeat(64) });
      view([a, b], { selected: 'i_b' });
      expect(parts().map((n) => n.dataset.item)).toEqual(['i_a', 'i_b']);
      expect(partOf('i_b').classList.contains('is-focus')).toBe(true);
      // Each is named by its head; the one chosen is marked as the current one.
      expect(partOf('i_b').querySelector('.workbench-section-head').getAttribute('aria-current')).toBe('true');
      expect(partOf('i_a').querySelector('.workbench-section-head').getAttribute('aria-current')).toBe('false');
      expect(partOf('i_a').querySelector('.workbench-section-head').textContent).toBe('a.png');
      // Its path under it; its actions in the menu beside its name, as every item's.
      expect(partOf('i_b').querySelector('.workbench-info code')).not.toBeNull();
      expect(partOf('i_a').querySelector('.workbench-item-menu')).not.toBeNull();
      // Not drawn until it comes near the view.
      expect(partOf('i_a').querySelector('img')).toBeNull();
      expect(partOf('i_a').querySelector('.workbench-later')).not.toBeNull();
      observed[0].near(partOf('i_a'));
      const imgA = partOf('i_a').querySelector('img');
      const imgB = partOf('i_b').querySelector('img');
      expect(imgA.getAttribute('src')).toBe('/workbench/asset/i_a');
      expect(partOf('i_a').querySelector('.workbench-info').children.length).toBe(0);
      sent.length = 0;
      partOf('i_a').dispatchEvent(new Event('pointerdown', { bubbles: true }));
      expect(payloads()).toEqual([{ message: 'WORKBENCH_SELECT', item_id: 'i_a' }]);
      expect(partOf('i_a').classList.contains('is-focus')).toBe(true);
      expect(partOf('i_b').classList.contains('is-focus')).toBe(false);
      expect(partOf('i_a').querySelector('.workbench-info code')).not.toBeNull();
      // Both stay as they were drawn.
      expect(partOf('i_a').querySelector('img')).toBe(imgA);
      expect(partOf('i_b').querySelector('img')).toBe(imgB);
      // The click of the touch that chose it does nothing more; the next one does.
      const clicked = jest.fn();
      imgA.addEventListener('click', clicked);
      imgA.click();
      expect(clicked).not.toHaveBeenCalled();
      imgA.click();
      expect(clicked).toHaveBeenCalledTimes(1);
    });

    test('keeps the mark on the one before when another is chosen, where it can no longer be moved', () => {
      jest.isolateModules(() => { require(js('monadic/workbench-pointer.js')); });
      jest.resetModules();
      require(js('monadic/workbench-places.js'));
      require(js('monadic/workbench.js'));
      const a = item({ id: 'i_a', artifact_id: 'r_a', name: 'a.png' });
      const b = item({ id: 'i_b', artifact_id: 'r_b', name: 'b.png', sha256: 'b'.repeat(64) });
      view([a, b], { selected: 'i_a' });
      const layer = partOf('i_a').querySelector('.workbench-pointer-layer');
      layer.getBoundingClientRect = () => ({ left: 0, top: 0, width: 200, height: 100 });
      layer.setPointerCapture = () => {};
      partOf('i_a').querySelector('.workbench-pointer-point').click();
      [['pointerdown', 10, 10], ['pointermove', 80, 60], ['pointerup', 80, 60]].forEach(([type, x, y]) => {
        layer.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, button: 0, bubbles: true }));
      });
      const mark = partOf('i_a').querySelector('.workbench-pointer');
      expect(mark.hidden).toBe(false);
      partOf('i_b').dispatchEvent(new Event('pointerdown', { bubbles: true }));
      expect(partOf('i_b').classList.contains('is-focus')).toBe(true);
      expect(mark.hidden).toBe(false);
      // Once it is Before, its mark stays and cannot be moved, also when it is chosen.
      const before = Object.assign({}, a, { place: 'previous' });
      view([before, b], { selected: 'i_b', board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [before, b] } });
      window.Workbench.select('i_a');
      expect(partOf('i_a').classList.contains('is-focus')).toBe(true);
      expect(mark.hidden).toBe(false);
      expect(partOf('i_a').querySelector('.workbench-pointer-controls').hidden).toBe(true);
      mark.dispatchEvent(new MouseEvent('pointerdown', { clientX: 40, clientY: 30, button: 0, bubbles: true }));
      expect(mark.classList.contains('workbench-pointer-held')).toBe(false);
      expect(partOf('i_a').querySelector('.workbench-info').textContent).toContain('Bring it into Now to mark it.');
      delete window.WorkbenchPointer;
    });

    test('shows one whiteboard at a time, and lets go of what was drawn for an item taken off', () => {
      const pic = item({ id: 'i_p', artifact_id: 'r_p', name: 'p.png' });
      const board = item({ id: 'i_w', kind: 'file', artifact_id: undefined, preview: 'text', name: 'b.whiteboard.json',
        path: 'c/whiteboards/b.whiteboard.json', sha256: 'c'.repeat(64), render: 'whiteboard' });
      view([board, pic], { selected: 'i_p' });
      expect(partOf('i_w').textContent).toContain('One whiteboard is shown at a time');
      observed[0].near(partOf('i_w'));
      expect(partOf('i_w').querySelector('canvas, .workbench-whiteboard')).toBeNull();
      view([pic], { selected: 'i_p' });
      expect(parts().map((n) => n.dataset.item)).toEqual(['i_p']);
    });

    test('lets go of a PDF drawn among the others once it is taken off', async () => {
      const dispose = jest.fn();
      window.WorkbenchPdf = { show: jest.fn(() => ({ dispose, setPointable: () => {}, clearPointer: () => {} })) };
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, arrayBuffer: async () => new ArrayBuffer(4),
        headers: { get: () => null } }));
      try {
        const pic = item({ id: 'i_p', artifact_id: 'r_p', name: 'p.png' });
        const pdf = item({ id: 'i_d', kind: 'file', artifact_id: undefined, preview: 'pdf', name: 'd.pdf', path: 'c/d.pdf',
          sha256: 'd'.repeat(64) });
        view([pdf, pic], { selected: 'i_p' });
        observed[0].near(partOf('i_d'));
        for (let i = 0; i < 5; i += 1) await new Promise((r) => setTimeout(r, 0));
        expect(window.WorkbenchPdf.show).toHaveBeenCalledTimes(1);
        view([pic], { selected: 'i_p' });
        expect(dispose).toHaveBeenCalledTimes(1);
      } finally {
        delete window.WorkbenchPdf;
        delete global.fetch;
      }
    });
  });

  describe('saving a file from the work screen', () => {
    test('is offered up to what is read whole, not for a longer video', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      try {
        const clip = item({ id: 'i_v', kind: 'file', artifact_id: undefined, preview: 'video', name: 'talk.mp4', path: 'c/talk.mp4',
          sha256: 'e'.repeat(64), size: 10 * 1024 * 1024 });
        view([clip], { selected: 'i_v' });
        expect(menuEntry('i_v', 'Download')).not.toBeNull();
        view([Object.assign({}, clip, { size: 65 * 1024 * 1024 })], { selected: 'i_v' });
        expect(menuEntry('i_v', 'Download')).toBeNull();
      } finally {
        delete global.fetch;
      }
    });
  });

  describe('the four places', () => {
    const at = (place) => Array.from(document.querySelectorAll(`.workbench-place-body[data-place="${place}"] > *`))
      .map((n) => n.dataset.item);
    const a = () => item({ id: 'i_a', artifact_id: 'r_a', name: 'a.png', place: 'current', by: 'user', fresh: true });
    const b = () => item({ id: 'i_b', artifact_id: 'r_b', name: 'b.png', sha256: 'b'.repeat(64), place: 'latest', by: 'agent' });
    const c = () => item({ id: 'i_c', artifact_id: 'r_c', name: 'c.png', sha256: 'c'.repeat(64), place: 'previous', by: 'user' });
    const d = () => item({ id: 'i_d', artifact_id: 'r_d', name: 'd.png', sha256: 'd'.repeat(64), place: 'stash', by: 'user' });
    const board = (items, revision, extra = {}) => ({
      board: Object.assign({ board_id: 'b1', chat_id: 'c_1', revision, items, layers: { latest: 'agent', previous: 'user' },
        now_limit: 10 }, extra), selected: null
    });
    const actions = () => payloads().filter((p) => p.message === 'WORKBENCH_ACTION');

    test('puts each item in its place, put-away ones as rows, and says who placed each layer', () => {
      view([a(), b(), c(), d()], board([a(), b(), c(), d()], 1));
      expect(at('current')).toEqual(['i_a']);
      expect(at('latest')).toEqual(['i_b']);
      expect(at('previous')).toEqual(['i_c']);
      expect(at('stash')).toEqual(['i_d']);
      expect(document.querySelector('.workbench-place-body[data-place="stash"] > .workbench-stash-row')).not.toBeNull();
      expect(document.querySelector('.workbench-place-body[data-place="stash"] img')).toBeNull();
      const count = (place) => document.querySelector(`.workbench-place[data-place="${place}"] .workbench-place-count`).textContent;
      expect(count('current')).toBe('1 / 10');
      expect(count('latest')).toBe('AI · 1');
      expect(count('previous')).toBe('You · 1');
    });

    test('moves an item with its buttons, each operation with an id of its own', () => {
      view([b()], board([b()], 1));
      sent.length = 0;
      run('i_b', 'Into Now');
      run('i_b', 'Put away');
      run('i_b', 'Into Now');
      const ops = actions();
      expect(ops.map((p) => p.action)).toEqual(['bring', 'stash', 'bring']);
      expect(ops.every((p) => p.item_id === 'i_b' && p.token === 'tok-i_b')).toBe(true);
      expect(new Set(ops.map((p) => p.operation_id)).size).toBe(3);
      // The menu acts at once on an item that is not the one chosen.
      expect(payloads().some((p) => p.message === 'WORKBENCH_SELECT')).toBe(false);
    });

    test('offers taking off only what was placed in this turn, after a line; anything else is put away', () => {
      view([a(), b()], board([a(), b()], 1));
      expect(menuOf('i_a').map((e) => e.label)).toContain('Remove from the work screen');
      expect(menuEntry('i_a', 'Remove from the work screen').danger).toBe(true);
      expect(menuOf('i_b').map((e) => e.label)).not.toContain('Remove from the work screen');
      expect(menuOf('i_b').map((e) => e.label)).toContain('Put away');
      expect(menuEntry('i_a', 'Into Now')).toBeNull();
    });

    test('takes an item dragged onto Now or Put away, once, and leaves files from the computer to the pane', () => {
      view([b(), d()], board([b(), d()], 1));
      sent.length = 0;
      const types = ['application/x-monadic-workbench-item'];
      const drop = (place, id) => {
        const root = document.querySelector(`.workbench-place[data-place="${place}"]`);
        const event = new Event('drop', { bubbles: true, cancelable: true });
        event.dataTransfer = { types, getData: () => id };
        root.dispatchEvent(event);
      };
      drop('current', 'i_d');
      drop('stash', 'i_b');
      drop('current', 'i_b');
      expect(actions().map((p) => [p.item_id, p.action])).toEqual([['i_d', 'bring'], ['i_b', 'stash'], ['i_b', 'bring']]);
      // An item dropped where it already is: nothing.
      sent.length = 0;
      drop('stash', 'i_d');
      expect(actions()).toEqual([]);
      // Files from the computer are not this kind of drop.
      const files = new Event('drop', { bubbles: true, cancelable: true });
      files.dataTransfer = { types: ['Files'], getData: () => '' };
      document.querySelector('.workbench-place[data-place="current"]').dispatchEvent(files);
      expect(actions()).toEqual([]);
    });

    test('keeps a drawn item as it is when it moves to another place', () => {
      view([a(), b()], board([a(), b()], 1));
      window.Workbench.select('i_b');
      const img = document.querySelector('.workbench-section[data-item="i_b"] img');
      expect(img).not.toBeNull();
      const moved = Object.assign(b(), { place: 'previous' });
      view([a(), moved], board([a(), moved], 2));
      expect(at('previous')).toEqual(['i_b']);
      expect(document.querySelector('.workbench-section[data-item="i_b"] img')).toBe(img);
    });

    test('while a reply runs, says so and offers nothing that changes the work screen, checked again when used', () => {
      document.getElementById('work-screen-pane').insertAdjacentHTML('afterbegin', '<div class="workbench-head"></div>');
      view([b()], board([b()], 1, { replying: true }));
      expect(document.getElementById('workbench-lock').hidden).toBe(false);
      expect(document.getElementById('workbench-put').disabled).toBe(true);
      expect(menuEntry('i_b', 'Put away').disabled).toBe(true);
      sent.length = 0;
      menuEntry('i_b', 'Put away').action();
      expect(actions()).toEqual([]);
      view([b()], board([b()], 2, { replying: false }));
      expect(document.getElementById('workbench-lock').hidden).toBe(true);
      expect(document.getElementById('workbench-put').disabled).toBe(false);
    });

    test('opens a put-away item here to read, and sends nothing of it with a message', () => {
      layout.pane = 'work';
      view([d()], board([d()], 1));
      document.querySelector('.workbench-stash-row[data-item="i_d"] .workbench-stash-open').click();
      expect(shown()).toBe('i_d');
      const part = document.querySelector('.workbench-place-body[data-place="stash"] .workbench-section[data-item="i_d"]');
      expect(part.querySelector('img')).not.toBeNull();
      expect(part.querySelector('.workbench-info').textContent).toContain('the AI does not read it');
      expect(window.Workbench.rangeNow()).toBeNull();
      expect(window.Workbench.pictureNow()).toBeNull();
    });

    test('names in view the items of the desk only, place by place', () => {
      layout.pane = 'work';
      view([a(), b(), d()], board([a(), b(), d()], 1));
      window.Workbench.select('i_a');
      const box = { top: 0, bottom: 200, left: 0, right: 400 };
      document.querySelectorAll('#workbench-view .workbench-section, #workbench-view .workbench-stash-row')
        .forEach((n) => { n.getBoundingClientRect = () => box; });
      expect(window.Workbench.rangeNow().in_view.map((v) => v.item_id)).toEqual(['i_a', 'i_b']);
    });

    test('says why an operation was not taken', () => {
      window.Workbench.onResult({ status: 'refused', reason: 'now_full' });
      expect(window.setAlert).toHaveBeenLastCalledWith(expect.stringContaining('Now is full'), expect.anything());
      window.Workbench.onResult({ status: 'refused', reason: 'replying' });
      expect(window.setAlert).toHaveBeenLastCalledWith(expect.stringContaining('when the reply ends'), expect.anything());
    });
  });

  describe('to the top and the end of a place', () => {
    test('shows the two while the place of the item chosen is longer than it shows, each kept from where it would not move', () => {
      document.getElementById('work-screen-pane').insertAdjacentHTML('beforeend',
        '<span class="workbench-jump" hidden><button id="workbench-top"></button><button id="workbench-bottom"></button></span>');
      jest.resetModules();
      require(js('monadic/workbench-places.js'));
      require(js('monadic/workbench.js'));
      const old = item({ id: 'i_o', artifact_id: 'r_o', name: 'old.png', sha256: 'b'.repeat(64), place: 'stash' });
      view([item(), old], { selected: 'i_1' });
      const bodyOf = (place) => document.querySelector(`.workbench-place-body[data-place="${place}"]`);
      const sizes = new Map();
      ['current', 'stash'].forEach((place) => {
        const body = bodyOf(place);
        const size = { scrollHeight: 300, clientHeight: 300 };
        sizes.set(place, size);
        Object.defineProperty(body, 'scrollHeight', { get: () => size.scrollHeight });
        Object.defineProperty(body, 'clientHeight', { get: () => size.clientHeight });
        body.scrollTo = jest.fn(({ top }) => { body.scrollTop = top; body.dispatchEvent(new Event('scroll')); });
      });
      const group = document.querySelector('.workbench-jump');
      const top = document.getElementById('workbench-top');
      const bottom = document.getElementById('workbench-bottom');
      window.dispatchEvent(new Event('resize'));
      expect(group.hidden).toBe(true);
      sizes.get('current').scrollHeight = 1000;
      window.dispatchEvent(new Event('resize'));
      expect(group.hidden).toBe(false);
      expect(top.disabled).toBe(true);
      expect(bottom.disabled).toBe(false);
      expect(bottom.getAttribute('aria-label')).toContain('Now');
      bottom.click();
      expect(bodyOf('current').scrollTo).toHaveBeenLastCalledWith({ top: 1000, behavior: 'smooth' });
      bodyOf('current').scrollTop = 700;
      bodyOf('current').dispatchEvent(new Event('scroll'));
      expect(top.disabled).toBe(false);
      expect(bottom.disabled).toBe(true);
      // The item chosen is put away: the two act on Put away.
      sizes.get('stash').scrollHeight = 900;
      window.Workbench.select('i_o');
      expect(bottom.getAttribute('aria-label')).toContain('Put away');
      bottom.click();
      expect(bodyOf('stash').scrollTo).toHaveBeenLastCalledWith({ top: 900, behavior: 'smooth' });
      expect(bodyOf('current').scrollTo).toHaveBeenCalledTimes(1);
    });
  });

  describe('an entry of the Library on the work screen', () => {
    test('is listed as an item, says it is from the Library, and is opened by its id', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      const entry = item({ id: 'i_l', kind: 'library', artifact_id: undefined, preview: 'text', name: 'Tides',
        library_id: 'conv-1', sha256: 'b'.repeat(64), version: 'b'.repeat(64), path: undefined });
      view([entry], { selected: 'i_l' });
      expect(document.querySelector('#workbench-view').textContent).toContain('From the Library (its text)');
      expect(document.querySelector('#workbench-view .workbench-to-library')).toBeNull();
      window.Workbench.openLibrary('conv-2');
      expect(sent.at(-1).payload).toEqual({ message: 'WORKBENCH_OPEN_LIBRARY', library_id: 'conv-2' });
    });
  });

  describe('a document kept in the Library', () => {
    test('offers it under a document the Library takes, asks for this version, and follows the import', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      const followImport = jest.fn(() => Promise.resolve({}));
      window.libraryPanel = { followImport };
      try {
        const doc = item({ id: 'i_m', kind: 'file', artifact_id: undefined, preview: 'text', name: 'notes.md',
          path: 'c/notes.md', sha256: 'c'.repeat(64), library: true });
        const pic = item({ id: 'i_q', kind: 'file', artifact_id: undefined, preview: 'image', name: 'b.png',
          path: 'c/b.png', sha256: 'd'.repeat(64) });
        view([pic, doc], { selected: 'i_q' });
        expect(menuEntry('i_q', 'Keep in the Library')).toBeNull();
        window.Workbench.select('i_m');
        expect(menuEntry('i_m', 'Keep in the Library')).toMatchObject({ icon: 'fa-solid fa-book' });
        run('i_m', 'Keep in the Library');
        expect(sent.at(-1).payload).toEqual({ message: 'LIBRARY_FROM_WORKBENCH', item_id: 'i_m', sha256: 'c'.repeat(64) });
        window.Workbench.onToLibrary({ item_id: 'i_m', import_id: 'imp-1' });
        expect(followImport).toHaveBeenCalledWith('imp-1', 'notes.md');
        window.setAlert.mockClear();
        window.Workbench.onToLibrary({ item_id: 'i_m', error: 'hides_words' });
        expect(window.setAlert).toHaveBeenCalled();
        expect(followImport).toHaveBeenCalledTimes(1);
      } finally {
        delete window.libraryPanel;
      }
    });

    test('names a record of the conversation first (blank: the server takes its first heading), then asks whether to update one kept already or keep this one besides', async () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      document.body.insertAdjacentHTML('beforeend', '<dialog id="libraryKeepChoice"><input id="library-keep-title">'
        + '<div id="library-keep-records" hidden><select id="library-keep-target"></select></div>'
        + '<button id="library-keep-new"></button><button id="library-keep-update" hidden></button></dialog>');
      const opened = [];
      window.MonadicDialog = { of: () => ({ open: () => opened.push(true), close: () => Promise.resolve(true) }) };
      const flush = () => new Promise((r) => setTimeout(r, 0));
      try {
        const doc = item({ id: 'i_d', kind: 'file', artifact_id: undefined, preview: 'text', name: 'conversation-1.md',
          path: 'c/conversation-1.md', sha256: 'e'.repeat(64), library: true, draft: true, title: 'Why tides?' });
        view([doc], { selected: 'i_d' });
        run('i_d', 'Keep in the Library');
        expect(opened.length).toBe(1);
        expect(document.getElementById('library-keep-title').value).toBe('');
        expect(document.getElementById('library-keep-records').hidden).toBe(true);
        document.getElementById('library-keep-title').value = 'Tides and moons';
        document.getElementById('library-keep-new').click();
        await flush();
        expect(sent.at(-1).payload).toEqual({ message: 'LIBRARY_FROM_WORKBENCH', item_id: 'i_d', sha256: 'e'.repeat(64),
          title: 'Tides and moons' });

        window.Workbench.onToLibrary({ item_id: 'i_d', error: 'choose', records: [
          { id: 'conv-2', title: 'Later', created_at: '2026-11-02T09:30:00Z', revision: 'v2' },
          { id: 'conv-1', title: 'Tides', created_at: '2026-11-01T08:15:00Z', revision: 'v1' }] });
        expect(opened.length).toBe(2);
        expect(document.getElementById('library-keep-records').hidden).toBe(false);
        expect(document.getElementById('library-keep-title').value).toBe('Tides and moons');
        const options = [...document.querySelectorAll('#library-keep-target option')];
        expect(options.map((o) => o.textContent)).toEqual(['Later (2026-11-02 09:30)', 'Tides (2026-11-01 08:15)']);
        document.getElementById('library-keep-target').value = 'conv-1';
        document.getElementById('library-keep-update').click();
        await flush();
        expect(sent.at(-1).payload).toEqual({ message: 'LIBRARY_FROM_WORKBENCH', item_id: 'i_d', sha256: 'e'.repeat(64),
          title: 'Tides and moons', choice: { update: 'conv-1', seen: 'v1' } });

        const count = sent.length;
        document.getElementById('library-keep-update').click();
        await flush();
        expect(sent.length).toBe(count);
      } finally {
        delete window.MonadicDialog;
        document.getElementById('libraryKeepChoice').remove();
      }
    });
  });

  describe('drawing on an image', () => {
    test('offers to draw on an image made or opened, as the version shown, and on nothing else', () => {
      view([item(), item({ id: 'i_2', kind: 'file', artifact_id: undefined, preview: 'image', path: 'photos/a.png', sha256: 'b'.repeat(64) }),
        item({ id: 'i_3', kind: 'file', artifact_id: undefined, preview: 'text', path: 'notes.txt', sha256: 'c'.repeat(64) })],
      { selected: 'i_1' });
      run('i_1', 'Draw on it');
      expect(sent.at(-1).payload).toMatchObject({ message: 'WORKBENCH_WHITEBOARD_NEW', item_id: 'i_1', version: 'a'.repeat(64) });
      window.Workbench.select('i_2');
      run('i_2', 'Draw on it');
      expect(sent.at(-1).payload).toMatchObject({ item_id: 'i_2', version: 'b'.repeat(64) });
      global.fetch = jest.fn(() => new Promise(() => {}));
      try {
        window.Workbench.select('i_3');
        expect(menuEntry('i_3', 'Draw on it')).toBeNull();
      } finally {
        delete global.fetch;
      }
    });

    test('says when the image changed since it was shown', () => {
      view([item()], { selected: 'i_1' });
      run('i_1', 'Draw on it');
      const request = sent.at(-1).payload.request;
      window.Workbench.onWhiteboard({ type: 'workbench_whiteboard', request: request, status: 'refused', reason: 'the image changed' });
      expect(window.setAlert).toHaveBeenCalledWith(expect.stringContaining('changed since it was shown'), 'warning');
    });
  });

  describe('a whiteboard drawn on a picture', () => {
    const wb = { id: 'i_p', kind: 'file', actor: 'user', name: 'whiteboard-2.wb.json', path: 'c/whiteboards/whiteboard-2.wb.json',
      preview: 'text', render: 'whiteboard', sha256: 'c'.repeat(64), version: 'c'.repeat(64), status: 'ok' };
    const board = { version: 2, width: 1200, height: 1600, shapes: [],
      background: { sha256: 'd'.repeat(64), content_type: 'image/png', pixel_width: 300, pixel_height: 400, orientation: 1 } };
    const flushAll = async () => { for (let i = 0; i < 8; i += 1) await new Promise((r) => setTimeout(r, 0)); };
    let fetched;
    let picture;

    beforeEach(() => {
      layout.pane = 'work';
      jest.isolateModules(() => {
        require(js('monadic/workbench-pointer.js'));
        require(js('monadic/workbench-whiteboard.js'));
      });
      fetched = [];
      picture = { ok: true, status: 200 };
      global.fetch = jest.fn((url) => {
        fetched.push(url);
        if (url.startsWith('/workbench/asset/background')) {
          return Promise.resolve({ ok: picture.ok, status: picture.status, blob: async () => new Blob(['p'], { type: 'image/png' }) });
        }
        return Promise.resolve({ ok: true, status: 200, text: async () => JSON.stringify(board), headers: { get: () => null } });
      });
      global.createImageBitmap = jest.fn(async () => ({ width: 300, height: 400, close: () => {} }));
      global.URL.createObjectURL = jest.fn(() => 'blob:picture');
      global.URL.revokeObjectURL = jest.fn();
      HTMLCanvasElement.prototype.toBlob = function toBlob(done, type) { done(new Blob(['x'], { type: type })); };
    });

    afterEach(() => {
      delete window.WorkbenchWhiteboard;
      delete global.fetch;
      delete global.createImageBitmap;
      delete HTMLCanvasElement.prototype.toBlob;
      jest.restoreAllMocks();
    });

    async function showIt(backgrounds) {
      jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => new Proxy({}, {
        get: () => () => {}, set: () => true
      }));
      jest.spyOn(HTMLCanvasElement.prototype, 'toDataURL').mockImplementation(() => 'data:image/png;base64,V0I=');
      view([wb], { renders: { i_p: '/workbench/asset/render-i_p' }, backgrounds: backgrounds, selected: 'i_p',
        selection_serial: 2 });
      await flushAll();
      document.querySelector('#workbench-view .workbench-whiteboard').getBoundingClientRect =
        () => ({ top: 0, bottom: 800, left: 0, right: 600, height: 800 });
    }

    async function look() {
      const posted = jest.fn(() => Promise.resolve({ status: 204 }));
      global.fetch = posted;
      window.Workbench.onCapture({ type: 'workbench_capture', id: 'cap-p', item_id: 'i_p', version: 'c'.repeat(64), serial: 2,
        wants: ['image'] });
      await flushAll();
      return JSON.parse(posted.mock.calls[0][1].body);
    }

    test('gets the picture from its own address and paints the board at its sheet\'s size for a look', async () => {
      await showIt({ i_p: '/workbench/asset/background-i_p' });
      expect(fetched).toEqual(['/workbench/asset/render-i_p', '/workbench/asset/background-i_p']);
      expect(document.querySelector('#workbench-view .workbench-whiteboard-picture image')).not.toBeNull();
      const body = await look();
      expect(body).toMatchObject({ image: 'V0I=', crop: { width: 1200, height: 1600, sent_width: 1200, sent_height: 1600 } });
    });

    test('gives a look no picture of the board while the picture under it is not had', async () => {
      picture = { ok: false, status: 410 };
      await showIt({ i_p: '/workbench/asset/background-i_p' });
      const body = await look();
      expect(body.image).toBeUndefined();
      expect(body.image_note).toBe('failed');
    });

    test('asks for the picture again when a view brings a new address for it', async () => {
      picture = { ok: false, status: 404 };
      await showIt({ i_p: '/workbench/asset/background-i_p' });
      picture = { ok: true, status: 200 };
      view([wb], { renders: { i_p: '/workbench/asset/render-i_p' }, backgrounds: { i_p: '/workbench/asset/background-i_p-2' },
        selected: 'i_p', selection_serial: 2 });
      await flushAll();
      expect(fetched).toContain('/workbench/asset/background-i_p-2');
      expect(document.querySelector('#workbench-view .workbench-whiteboard-picture image')).not.toBeNull();
    });
  });

  describe('the preference to show new items', () => {
    let jar;

    beforeEach(() => {
      jar = {};
      window.getCookie = (name) => (name in jar ? jar[name] : null);
      window.setCookie = jest.fn((name, value) => { jar[name] = value; });
    });

    afterEach(() => {
      delete window.getCookie;
      delete window.setCookie;
    });

    test('when turned off, a new item does not take the pane, but what the user opens does', () => {
      jar['work-screen-auto-switch'] = 'false';
      view([item()]);
      expect(window.LayoutController.setPane).not.toHaveBeenCalled();
      expect(shown()).toBeNull();
      expect(document.getElementById('workbench-status').textContent).not.toBe('');
      window.Workbench.openFile('reports/notes.txt');
      window.Workbench.onOpened({ type: 'workbench_opened', item_id: 'i_1', path: PATH, added: false });
      expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
      expect(shown()).toBe('i_1');
    });

    test('is kept from the switch in the menu', () => {
      document.body.insertAdjacentHTML('beforeend', '<input type="checkbox" id="work-screen-auto-switch" checked>');
      jest.resetModules();
      require(js('monadic/workbench-places.js'));
      require(js('monadic/workbench.js'));
      const box = document.getElementById('work-screen-auto-switch');
      expect(box.checked).toBe(true);
      box.checked = false;
      box.dispatchEvent(new Event('change'));
      expect(window.setCookie).toHaveBeenCalledWith('work-screen-auto-switch', 'false', 365);
    });
  });
  describe('a text file the work screen draws', () => {
    let drawn;

    function doc(overrides = {}) {
      return Object.assign({
        id: 'i_d', kind: 'file', actor: 'agent', mid: null, name: 'plan.md', path: 'conversations/c/workbench/plan.md',
        preview: 'text', render: 'markdown', sha256: 'd'.repeat(64), version: 'd'.repeat(64), status: 'ok'
      }, overrides);
    }

    function viewDoc(items, renders) {
      view(items, { renders: renders || Object.fromEntries(items.map((i) => [i.id, `/workbench/asset/render-${i.id}`])) });
    }

    const settle = () => new Promise((r) => setTimeout(r, 0));

    beforeEach(() => {
      drawn = [];
      const real = require(js('monadic/workbench-render.js'));
      window.WorkbenchRender = {
        Refused: real.Refused,
        failureNotice: real.failureNotice,
        draw: jest.fn((box, kind, text, opts) => {
          const handle = { done: Promise.resolve(), dispose: jest.fn() };
          box.textContent = `drawn ${kind}: ${text}`;
          drawn.push({ kind, text, opts, handle });
          return handle;
        })
      };
      global.fetch = jest.fn((url) => Promise.resolve({
        ok: true, status: 200, text: () => Promise.resolve(url.includes('render-') ? '# Plan' : '# Plan\nline two'),
        headers: { get: () => null }
      }));
    });

    afterEach(() => {
      delete global.fetch;
      delete window.WorkbenchRender;
    });

    test('draws it from its whole text, with a switch to its lines, and says its lines are not in view', async () => {
      layout.pane = 'work';
      viewDoc([doc()]);
      await settle();
      expect(global.fetch).toHaveBeenCalledWith('/workbench/asset/render-i_d', expect.anything());
      expect(drawn.map((d) => [d.kind, d.text, d.opts.name])).toEqual([['markdown', '# Plan', 'plan.md']]);
      const choices = document.querySelectorAll('#workbench-view .workbench-mode button');
      expect(Array.from(choices).map((b) => [b.dataset.mode, b.getAttribute('aria-pressed')]))
        .toEqual([['drawn', 'true'], ['source', 'false']]);
      document.querySelector('#workbench-view .workbench-drawable').getBoundingClientRect =
        () => ({ top: 0, bottom: 100, left: 0, right: 100, width: 100, height: 100 });
      expect(window.Workbench.rangeNow()).toMatchObject({ item_id: 'i_d', range: null, note: 'rendered' });
    });

    test('shows its numbered lines when switched, from the text view, and draws it again when switched back', async () => {
      viewDoc([doc()]);
      await settle();
      document.querySelector('#workbench-view .workbench-mode button[data-mode="source"]').click();
      await settle();
      expect(global.fetch).toHaveBeenLastCalledWith('/workbench/asset/i_d', expect.anything());
      const lines = document.querySelectorAll('#workbench-view .workbench-lines li');
      expect(Array.from(lines).map((l) => l.textContent)).toEqual(['# Plan', 'line two']);
      expect(drawn[0].handle.dispose).toHaveBeenCalled();
      document.querySelector('#workbench-view .workbench-mode button[data-mode="drawn"]').click();
      await settle();
      expect(drawn).toHaveLength(2);
    });

    test('keeps how each version is shown: a new version is drawn', async () => {
      viewDoc([doc()]);
      await settle();
      document.querySelector('#workbench-view .workbench-mode button[data-mode="source"]').click();
      await settle();
      viewDoc([doc({ sha256: 'e'.repeat(64), version: 'e'.repeat(64) })]);
      await settle();
      expect(document.querySelector('#workbench-view .workbench-mode button[aria-pressed="true"]').dataset.mode).toBe('drawn');
    });

    test('keeps where the drawing and the lines were scrolled to, each, when switched between them', async () => {
      viewDoc([doc()]);
      await settle();
      const pane = () => document.getElementById('workbench-view');
      pane().querySelector('.workbench-rendered').scrollTop = 120;
      pane().querySelector('.workbench-mode button[data-mode="source"]').click();
      await settle();
      pane().querySelector('.workbench-text').scrollTop = 40;
      pane().querySelector('.workbench-mode button[data-mode="drawn"]').click();
      await settle();
      expect(pane().querySelector('.workbench-rendered').scrollTop).toBe(120);
      pane().querySelector('.workbench-mode button[data-mode="source"]').click();
      await settle();
      expect(pane().querySelector('.workbench-text').scrollTop).toBe(40);
    });

    test('offers its lines when it is too large to draw, or when drawing it failed', async () => {
      global.fetch = jest.fn(() => Promise.resolve({ ok: false, status: 413 }));
      viewDoc([doc()]);
      await settle();
      const pane = document.getElementById('workbench-view');
      expect(pane.textContent).toContain('too large to draw');
      expect(window.WorkbenchRender.draw).not.toHaveBeenCalled();
      global.fetch = jest.fn(() => Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve('x'), headers: { get: () => null } }));
      window.WorkbenchRender.draw = jest.fn(() => ({ done: Promise.reject(new window.WorkbenchRender.Refused('bad spec')), dispose: jest.fn() }));
      viewDoc([doc({ id: 'i_e' })]);
      await settle();
      await settle();
      expect(pane.textContent).toContain('could not be drawn');
      expect(pane.textContent).toContain('bad spec');
      pane.querySelector('.alert ~ button').click();
      await settle();
      expect(pane.querySelector('.workbench-lines')).not.toBeNull();
    });

    test('shows a text as lines when the server gives no address to draw it', async () => {
      viewDoc([doc()], {});
      await settle();
      expect(window.WorkbenchRender.draw).not.toHaveBeenCalled();
      expect(document.querySelector('#workbench-view .workbench-mode')).toBeNull();
      expect(document.querySelector('#workbench-view .workbench-lines')).not.toBeNull();
    });

    test('says on the message which files the reply showed, and shows that version from the line', async () => {
      const el = card('m-1');
      viewDoc([doc()]);
      await settle();
      window.Workbench.drawShown('m-1', [
        { path: 'conversations/c/workbench/plan.md', name: 'plan.md', sha256: 'd'.repeat(64), preview: 'text', render: 'markdown' },
        { path: 'old.md', name: '<b>old</b>.md', sha256: 'f'.repeat(64), preview: 'text' },
        { path: 'bad' }
      ]);
      const lines = el.querySelectorAll('.workbench-shown-note .workbench-note-line');
      expect(lines).toHaveLength(2);
      expect(lines[1].querySelector('code').textContent).toBe('<b>old</b>.md');
      expect(lines[1].querySelector('b')).toBeNull();
      sent.length = 0;
      lines[0].querySelector('button').click();
      expect(payloads()).toEqual([{ message: 'WORKBENCH_SELECT', item_id: 'i_d' }]);
      sent.length = 0;
      lines[1].querySelector('button').click();
      expect(payloads()).toEqual([{ message: 'WORKBENCH_OPEN', path: 'old.md', sha256: 'f'.repeat(64) }]);
      window.Workbench.onOpened({ type: 'workbench_opened', path: 'old.md', status: 'refused', reason: 'changed' });
      expect(window.setAlert).toHaveBeenCalledWith(expect.stringContaining('changed after it was shown'), 'warning');
      window.Workbench.drawShown('m-1', []);
      expect(el.querySelector('.workbench-shown-note')).toBeNull();
    });

    test('opens a document from the line for one of its sections, as it is now, at that section', async () => {
      const el = card('m-2');
      window.WorkbenchRender.draw = jest.fn((box) => {
        box.innerHTML = '<div class="workbench-markdown"><h1>Story</h1><h6>§ 1</h6><p>One.</p><hr><h6>§ 2</h6><p>Two.</p></div>';
        return { done: Promise.resolve(), dispose: jest.fn() };
      });
      const entry = { path: 'conversations/c/documents/story.md', name: 'story.md', sha256: 'a'.repeat(64),
                      preview: 'text', render: 'markdown', section: '2' };
      window.Workbench.drawShown('m-2', [entry]);
      const button = el.querySelector('.workbench-shown-note button');
      expect(button.textContent).toBe('story.md § 2');
      sent.length = 0;
      button.click();
      // Not on the work screen yet: the document is opened as it is now.
      expect(payloads()).toEqual([{ message: 'WORKBENCH_OPEN', path: entry.path }]);

      layout.pane = 'work';
      const story = doc({ id: 'i_s', name: 'story.md', path: entry.path, sha256: 'b'.repeat(64), version: 'b'.repeat(64) });
      const marks = [];
      const rect = Element.prototype.getBoundingClientRect;
      Element.prototype.getBoundingClientRect = function () {
        if (this.tagName === 'H6') marks.push(this.textContent);
        return { top: this.tagName === 'H6' && this.textContent === '§ 2' ? 300 : 100 };
      };
      try {
        viewDoc([story]);
        await settle();
        await settle();
        const box = document.querySelector('#workbench-view .workbench-rendered');
        expect(marks).toContain('§ 2');
        expect(box.scrollTop).toBe(200);
      } finally {
        Element.prototype.getBoundingClientRect = rect;
      }
    });
  });
});

