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
  function shown() {
    const pane = document.getElementById('workbench-view');
    return pane && !pane.hidden ? pane.dataset.item : null;
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
      <div id="workbench-items" hidden></div>
      <div id="work-screen-browser"></div>
      <div id="workbench-view" hidden></div>
      <textarea id="message"></textarea>`;
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
    require(js('monadic/workbench.js'));
  });

  test('shows a new image in the pane with its path and Download, and only a line of text in the conversation', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry()]);
    view([item()]);
    const pane = document.getElementById('workbench-view');
    expect(pane.hidden).toBe(false);
    expect(pane.querySelector('img').getAttribute('src')).toBe('/workbench/asset/i_1');
    expect(pane.querySelector('code').textContent).toBe(PATH);
    expect(pane.querySelector('.btn-primary').textContent).toBe('Download');
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
    expect(document.querySelector('#workbench-view .btn-primary').textContent).toBe('Save as…');
  });

  test('shows no image for a file that changed or is gone, says which, and offers no save', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry()]);
    view([item({ status: 'changed' })]);
    const pane = document.getElementById('workbench-view');
    expect(pane.querySelector('img')).toBeNull();
    expect(pane.textContent).toContain('changed in the shared folder');
    expect(pane.querySelector('.btn-primary')).toBeNull();
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
    document.getElementById('message').focus();
    view([item(), item({ id: 'i_2', artifact_id: 'r_2', name: 'dog.png', sha256: 'b'.repeat(64) })]);
    expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    expect(shown()).toBeNull();
  });

  test('asks for an address to save the image by its record, from the pane and from the line', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry()]);
    view([item()]);
    document.querySelector('#workbench-view .btn-primary').click();
    el.querySelector('.workbench-save').click();
    expect(sent.map((s) => s.payload)).toEqual([
      { message: 'WORKBENCH_DOWNLOAD', artifact_id: 'r_1' }, { message: 'WORKBENCH_DOWNLOAD', artifact_id: 'r_1' }
    ]);
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
  });

  test('removes an image with its ×; the line stays, with no link to the pane', () => {
    const el = card('m-1');
    window.Workbench.drawRecord('m-1', [entry()]);
    view([item()]);
    document.querySelector('.workbench-item-remove').click();
    expect(sent[0].payload).toMatchObject({ message: 'WORKBENCH_ACTION', item_id: 'i_1', action: 'remove', token: 'tok-i_1' });
    expect(sent[0].opts).toMatchObject({ idempotent: true });
    window.Workbench.onResult({ status: 'accepted', action: 'remove', item_id: 'i_1' });
    view([], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [] }, approvals: {}, assets: {} });
    expect(el.querySelector('.workbench-note code').textContent).toBe(PATH);
    expect(el.querySelector('.workbench-open')).toBeNull();
    expect(el.querySelector('.workbench-save')).not.toBeNull();
    expect(shown()).toBeNull();
    expect(document.getElementById('workbench-items').hidden).toBe(true);
    expect(document.getElementById('workbench-status').textContent).not.toContain('older item');
  });

  test('says so when the board put an older image away to make room', () => {
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

  test('names a long image by its start and end in the list, with the whole name on hover', () => {
    view([item({ name: '20261106-091233_generate_gpt-image-2_0.png' })]);
    const tab = document.querySelector('#workbench-items [data-item="i_1"]');
    expect(tab.querySelector('.workbench-item-name').textContent).toBe('generate_…image-2_0.png');
    expect(tab.title).toBe('20261106-091233_generate_gpt-image-2_0.png');
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
    window.Workbench.onResult({ status: 'accepted', action: 'remove', item_id: 'i_1' });
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

    test('moves along the row with its buttons and the arrow keys, telling the server what the tab shows', () => {
      global.fetch = jest.fn(() => new Promise(() => {}));
      document.body.insertAdjacentHTML('beforeend', '<div id="work-screen-pane" tabindex="0"></div>');
      jest.resetModules();
      require(js('monadic/workbench.js'));
      view([item(), file()]);
      expect(shown()).not.toBeNull();
      sent.length = 0;
      document.querySelector('#workbench-stepper .workbench-prev').click();
      expect(payloads()).toEqual([{ message: 'WORKBENCH_SELECT', item_id: 'i_1' }]);
      expect(document.querySelector('#workbench-view img')).not.toBeNull();
      const pane = document.getElementById('work-screen-pane');
      pane.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
      expect(payloads().pop()).toEqual({ message: 'WORKBENCH_SELECT', item_id: 'i_f' });
      expect(document.querySelector('#workbench-stepper .workbench-next').disabled).toBe(true);
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
      document.getElementById('message').focus();
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
      Array.from(pane.querySelectorAll('button')).find((b) => b.textContent.includes('as it is now')).click();
      expect(sent[0].payload).toEqual({ message: 'WORKBENCH_OPEN', path: 'reports/notes.txt' });
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
      expect(document.querySelector('#workbench-items .workbench-item').textContent).toBe('Browser');
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

    test('with nothing selected, shows the empty area and no stepper', () => {
      view([item()], { selected: null });
      expect(shown()).toBeNull();
      expect(document.getElementById('work-screen-browser').hidden).toBe(false);
      expect(document.getElementById('workbench-stepper').hidden).toBe(true);
    });
  });
  describe('keeping the page and the server in step', () => {
    test('tells the server what the pane still shows when an item arrives while the user types', () => {
      view([item()]);
      document.getElementById('message').focus();
      sent.length = 0;
      const next = item({ id: 'i_2', artifact_id: 'r_2', sha256: 'b'.repeat(64) });
      view([item(), next], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [item(), next] }, selected: 'i_2' });
      expect(shown()).toBe('i_1');
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
      expect(document.getElementById('workbench-view').hidden).toBe(true);
      expect(payloads()).toEqual([]);
    });
  });
  describe('answers and failures', () => {
    const lastSeq = () => sent.filter((x) => x.payload.message === 'WORKBENCH_SELECT').pop().payload.seq;

    test('brings forward an item the server selects again after the page kept another', () => {
      view([item()]);
      document.getElementById('message').focus();
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
      await showText(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
      expect(window.Workbench.rangeNow()).toEqual({
        item_id: 'i_t', version: 'e'.repeat(64), range: { first_line: 3, last_line: 5 }, note: null, selection_chars: 0
      });
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

    describe('showing the assistant what the work screen shows', () => {
      // The page's sends: each answered as sent.
      let wsSent;
      const ofType = (type) => wsSent.filter((m) => m.message === type);
      const flushAll = async () => { await flush(); await flush(); };

      beforeEach(() => {
        wsSent = [];
        window.safeWsSend = (payload) => { wsSent.push(payload); return { sent: true }; };
        // A different id for each press.
        let press = 0;
        jest.spyOn(window.crypto, 'randomUUID').mockImplementation(() => {
          press += 1;
          return `${String(press).padStart(8, '0')}-abcd-4ef0-9123-456789abcdef`;
        });
        // The message box sits in its wrapper, as on the page.
        const input = document.getElementById('message');
        const wrapper = document.createElement('div');
        wrapper.className = 'message-input-wrapper';
        input.parentNode.insertBefore(wrapper, input);
        wrapper.appendChild(input);
      });

      afterEach(() => {
        delete window.WsPrivacyHandler;
        jest.restoreAllMocks();
      });

      async function selectedText(lines) {
        layout.pane = 'work';
        await showText(lines);
        view([notes], { assets: { i_t: '/workbench/asset/t' }, selected: 'i_t', selection_serial: 7,
          board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [notes] } });
      }

      function pressShow() {
        document.querySelector('.workbench-show').click();
        return ofType('WORKBENCH_SHOW').pop();
      }

      async function answerCapture(request) {
        const posted = jest.fn(() => Promise.resolve({ status: 204 }));
        global.fetch = posted;
        window.Workbench.onCapture(request);
        await flushAll();
        return JSON.parse(posted.mock.calls[0][1].body);
      }

      const chips = () => Array.from(document.querySelectorAll('#workbench-shown-chips .workbench-shown-chip'));

      test('fixes the lines in view at the press, asks the server for them, and shows a chip being prepared', async () => {
        await selectedText(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
        const asked = pressShow();
        expect(asked).toMatchObject({ item_id: 'i_t', version: 'e'.repeat(64), serial: 7 });
        expect(asked.op_id).toMatch(/^[0-9a-f]{16}$/);
        expect(chips()).toHaveLength(1);
        expect(chips()[0].textContent).toContain('a.txt');
        expect(chips()[0].className).toContain('is-preparing');
        // What the pane shows later does not change what was fixed.
        const box = document.querySelector('#workbench-view .workbench-text');
        box.getBoundingClientRect = () => ({ top: 140, bottom: 200, left: 0, right: 400, height: 60 });
        const body = await answerCapture({ id: 'cap', op: asked.op_id, item_id: 'i_t', version: 'e'.repeat(64), serial: 7,
          wants: ['range'] });
        expect(body).toEqual({ range: { first_line: 3, last_line: 5 }, note: null });
      });

      test('answers a press it does not hold, or for another item, with a failure and not with what it shows now', async () => {
        await selectedText(['a', 'b', 'c', 'd']);
        const asked = pressShow();
        const other = await answerCapture({ id: 'c1', op: 'f'.repeat(16), item_id: 'i_t', version: 'e'.repeat(64), serial: 7, wants: ['range'] });
        expect(other).toEqual({ range: null, note: 'failed' });
        const wrong = await answerCapture({ id: 'c2', op: asked.op_id, item_id: 'i_x', version: 'e'.repeat(64), serial: 7, wants: ['range'] });
        expect(wrong).toEqual({ range: null, note: 'failed' });
        const later = await answerCapture({ id: 'c3', op: asked.op_id, item_id: 'i_t', version: 'e'.repeat(64), serial: 8, wants: ['range'] });
        expect(later).toEqual({ range: null, note: 'failed' });
      });

      test('holds a ready chip until the message goes, which takes it without taking it back', async () => {
        await selectedText(['a', 'b']);
        const asked = pressShow();
        window.Workbench.onShown({ op_id: asked.op_id, status: 'ready', snapshot_id: 's'.repeat(22), record: {}, expires_in: 60 });
        expect(chips()[0].className).toContain('is-ready');
        const forSend = window.Workbench.shownForSend();
        expect(forSend.ids).toEqual(['s'.repeat(22)]);
        window.Workbench.shownSent(forSend.ids);
        expect(chips()).toHaveLength(0);
        expect(ofType('WORKBENCH_SHOW_REMOVE')).toHaveLength(0);
      });

      test('keeps a message from going while a chip is being prepared or has expired', async () => {
        await selectedText(['a', 'b']);
        const asked = pressShow();
        expect(window.Workbench.shownForSend()).toMatchObject({ blocked: true });
        window.Workbench.onShown({ op_id: asked.op_id, status: 'ready', snapshot_id: 's'.repeat(22), record: {}, expires_in: 0 });
        expect(window.Workbench.shownForSend()).toMatchObject({ blocked: true });
        expect(chips()[0].className).toContain('is-expired');
      });

      test('takes a chip back with the server, and is not given it again by a late answer', async () => {
        await selectedText(['a', 'b']);
        const asked = pressShow();
        chips()[0].querySelector('button').click();
        expect(ofType('WORKBENCH_SHOW_REMOVE').pop()).toEqual({ message: 'WORKBENCH_SHOW_REMOVE', op_id: asked.op_id });
        window.Workbench.onShown({ op_id: asked.op_id, status: 'ready', snapshot_id: 's'.repeat(22), record: {}, expires_in: 60 });
        expect(chips()).toHaveLength(0);
        // Refused, a late word does not make it ready.
        const second = pressShow();
        window.Workbench.onShown({ op_id: second.op_id, status: 'refused', reason: 'busy' });
        window.Workbench.onShown({ op_id: second.op_id, status: 'ready', snapshot_id: 't'.repeat(22), record: {}, expires_in: 60 });
        expect(chips()[0].className).toContain('is-refused');
      });

      test('gives the chips back when the message was not accepted, the ones the server named as expired', async () => {
        await selectedText(['a', 'b']);
        const first = pressShow();
        window.Workbench.onShown({ op_id: first.op_id, status: 'ready', snapshot_id: 'a'.repeat(22), record: {}, expires_in: 60 });
        const pending = window.Workbench.shownForSend();
        window.Workbench.shownSent(pending.ids);
        window.Workbench.restoreShown(pending, ['a'.repeat(22)]);
        expect(chips()[0].className).toContain('is-expired');
        window.Workbench.dropShown();
        expect(chips()).toHaveLength(0);
        // Not in another connection or chat.
        window.Workbench.restoreShown(pending, []);
        expect(chips()).toHaveLength(0);
      });

      test('shows nothing in a Private chat, and a browser only with the frame on the screen', async () => {
        await selectedText(['a', 'b']);
        window.WsPrivacyHandler = { isChatPrivate: () => true };
        window.Workbench.showToAssistant();
        expect(ofType('WORKBENCH_SHOW')).toHaveLength(0);
        delete window.WsPrivacyHandler;
        window.WorkScreen = { refresh: jest.fn(), drawnFrame: () => null };
        const browserItem = { id: 'i_b', kind: 'browser', actor: 'agent', instance: 3, version: 'browser:3', status: 'open' };
        view([browserItem], { selected: 'i_b', selection_serial: 9,
          board: { board_id: 'b1', chat_id: 'c_1', revision: 3, items: [browserItem] } });
        window.Workbench.showToAssistant();
        expect(ofType('WORKBENCH_SHOW')).toHaveLength(0);
        window.WorkScreen.drawnFrame = () => ({ browser: 3, data: 'JPEGDATA' });
        window.Workbench.showToAssistant();
        const asked = ofType('WORKBENCH_SHOW').pop();
        expect(asked).toMatchObject({ item_id: 'i_b', version: 'browser:3', serial: 9 });
        const body = await answerCapture({ id: 'c', op: asked.op_id, item_id: 'i_b', version: 'browser:3', serial: 9, wants: ['relay'] });
        expect(body).toEqual({ range: null, relay: 'JPEGDATA', relay_browser: 3 });
      });

      test('keeps settled records that came before their message, and does not let the message bring older ones', () => {
        window.Workbench.onShownRecords({ mid: 'u-2', shown: [{ id: 'look_2', name: 'b.txt', kind: 'text', state: 'sent' }] });
        const kept = window.Workbench.shownFor('u-2', [{ id: 'look_2', name: 'b.txt', kind: 'text', state: 'acquired' }]);
        expect(kept[0].state).toBe('sent');
        // Taken once; and a Reset forgets what was kept.
        expect(window.Workbench.shownFor('u-2', [])).toEqual([]);
        view([], { board: { board_id: 'b1', chat_id: 'c_1', revision: 1, items: [] } });
        window.Workbench.onShownRecords({ mid: 'u-3', shown: [{ id: 'look_3', name: 'c.txt', kind: 'text', state: 'sent' }] });
        view([], { board: { board_id: 'b2', chat_id: 'c_2', revision: 1, items: [] } });
        expect(window.Workbench.shownFor('u-3', null)).toBeNull();
      });

      test('keeps the records of what a message showed with the message, and draws them on its card', () => {
        messages.push({ mid: 'u-1', role: 'user', text: '' });
        card('u-1');
        window.Workbench.onShownRecords({ mid: 'u-1', shown: [{ id: 'look_1', name: 'a.txt', kind: 'text', state: 'sent' }] });
        expect(messages.find((m) => m.mid === 'u-1').workbench_shown).toHaveLength(1);
        const note = document.querySelector('#u-1 .workbench-shown-note');
        expect(note.textContent).toContain('a.txt');
        expect(note.textContent).toContain('Sent to the AI provider');
      });
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

    describe('answering a capture of a PDF', () => {
      const paper = { id: 'i_p', kind: 'file', actor: 'user', name: 'p.pdf', path: 'p.pdf', preview: 'pdf',
        sha256: 'f'.repeat(64), version: 'f'.repeat(64), status: 'ok' };
      let shown;
      let canvas;
      let layer;
      let drawImage;
      let encoded;

      beforeEach(async () => {
        layout.pane = 'work';
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
        jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => ({ drawImage }));
        jest.spyOn(HTMLCanvasElement.prototype, 'toDataURL').mockImplementation(() => encoded());
        window.WorkbenchPdf = {
          show: (box) => {
            const sheet = document.createElement('div');
            sheet.className = 'workbench-pdf-page';
            sheet.getBoundingClientRect = () => ({ top: -100, bottom: 400, left: 0, right: 400 });
            sheet.append(canvas, layer);
            box.appendChild(sheet);
            return { shown: () => shown, canvas: () => canvas, textLayer: () => layer, dispose: () => {}, state: () => ({}) };
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
      require(js('monadic/workbench.js'));
      const box = document.getElementById('work-screen-auto-switch');
      expect(box.checked).toBe(true);
      box.checked = false;
      box.dispatchEvent(new Event('change'));
      expect(window.setCookie).toHaveBeenCalledWith('work-screen-auto-switch', 'false', 365);
    });
  });
});

