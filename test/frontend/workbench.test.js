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

    test('says the server was busy when a file could not be opened for that', () => {
      view([]);
      window.Workbench.openFile('a.txt');
      window.Workbench.onOpened({ type: 'workbench_opened', status: 'refused', reason: 'busy' });
      expect(document.getElementById('workbench-status').textContent).toContain('reading other files');
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

