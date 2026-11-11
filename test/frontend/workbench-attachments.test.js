/**
 * @jest-environment jsdom
 */
// Attachments on the work screen: the next message's files are listed above
// the board ("To send") and under the message box (name chips). An image or
// a PDF is shown from the page's own data and is never a board item, so
// while one is shown neither a message's range nor a look names a board
// item. Audio and video are opened by the server as board items, and only
// the answer to the page's latest request is taken.
const path = require('path');
const { useRealBinaryGlobals } = require('../helpers');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

const PNG = 'data:image/png;base64,iVBORw0KGgo=';
const PDF = 'data:application/pdf;base64,JVBERi0xLjQ=';

describe('Attachments on the work screen', () => {
  let sent;
  let drafts;
  let layout;
  let messages;

  const NOTES = { id: 'i_t', kind: 'file', preview: 'text', actor: 'user', name: 'notes.txt', path: 'notes.txt',
                  sha256: 'e'.repeat(64), version: 'e'.repeat(64), status: 'ok' };

  function view(items, extra = {}) {
    window.Workbench.onView(Object.assign({
      board: { board_id: 'b1', chat_id: 'c_1', revision: 1, items: items },
      approvals: Object.fromEntries(items.map((i) => [i.id, `tok-${i.id}`])),
      assets: Object.fromEntries(items.map((i) => [i.id, `/workbench/asset/${i.id}`])),
      selected: items.length ? items[items.length - 1].id : null
    }, extra));
  }

  function pane() {
    return document.getElementById('workbench-view');
  }

  function lastSelect() {
    return sent.filter((x) => x.payload.message === 'WORKBENCH_SELECT').pop();
  }

  function lastOpen() {
    return sent.filter((x) => x.payload.message === 'WORKBENCH_OPEN_ATTACHMENT').pop();
  }

  function changed() {
    document.dispatchEvent(new CustomEvent('attachments:changed'));
  }

  // Each test loads the script again: its handlers on the document go when
  // the test ends, so no earlier copy answers a later test's clicks.
  let added;
  let addListener;

  afterEach(() => {
    added.forEach(([type, fn, opts]) => document.removeEventListener(type, fn, opts));
    document.addEventListener = addListener;
  });

  beforeEach(() => {
    added = [];
    addListener = document.addEventListener;
    document.addEventListener = function (type, fn, opts) {
      added.push([type, fn, opts]);
      return addListener.call(this, type, fn, opts);
    };
    jest.resetModules();
    document.body.innerHTML = `
      <div id="discourse"></div>
      <div id="workbench-status"></div>
      <div id="workbench-drafts" hidden></div>
      <div id="workbench-items" hidden></div>
      <div id="work-screen-browser"></div>
      <div id="workbench-view" hidden></div>
      <textarea id="message"></textarea>`;
    sent = [];
    drafts = [];
    messages = [];
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
    window.AttachmentDrafts = { list: () => drafts };
    window.WorkbenchPdf = { show: jest.fn(() => ({ dispose: jest.fn() })) };
    window.setAlert = jest.fn();
    // A board item's body is fetched; these tests look only at what the pane holds.
    global.fetch = jest.fn(() => new Promise(() => {}));
    delete window.electronAPI;
    delete global.webUIi18n;
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/workbench.js'));
  });

  test('lists what the next message carries above the board, and a name shows that file', () => {
    drafts = [{ key: 'file:0:cat.png', kind: 'image', name: 'cat.png', size: 2048, data: PNG }];
    changed();
    const strip = document.getElementById('workbench-drafts');
    expect(strip.hidden).toBe(false);
    const chips = strip.querySelectorAll('.workbench-draft');
    expect(Array.from(chips, (c) => c.textContent)).toEqual(['cat.png']);
    expect(chips[0].classList.contains('mc-badge')).toBe(true);
    chips[0].click();
    expect(window.Workbench.shownAttachment()).toMatchObject({ source: 'draft', key: 'file:0:cat.png' });
    expect(pane().hidden).toBe(false);
    expect(pane().querySelector('img').getAttribute('src')).toBe(PNG);
    expect(pane().querySelector('code').textContent).toBe('cat.png');
    expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
    expect(document.getElementById('workbench-drafts').querySelector('.workbench-draft').getAttribute('aria-pressed')).toBe('true');
    drafts = [];
    changed();
    expect(strip.hidden).toBe(true);
  });

  test('while an attachment is shown, nothing of the board is selected for a range or a look', () => {
    view([NOTES], { selected: 'i_t', selection_serial: 7 });
    window.Workbench.select('i_t');
    window.Workbench.onSelected({ type: 'workbench_selected', status: 'accepted', item_id: 'i_t', serial: 7,
                                  seq: lastSelect().payload.seq });
    expect(window.Workbench.rangeNow()).not.toBeNull();
    window.Workbench.showAttachment({ source: 'draft', key: 'file:0:cat.png', kind: 'image', name: 'cat.png', data: PNG });
    expect(lastSelect().payload.item_id).toBeNull();
    expect(window.Workbench.rangeNow()).toBeNull();
    expect(pane().dataset.item).toBeUndefined();
    window.Workbench.onSelected({ type: 'workbench_selected', status: 'accepted', item_id: null, serial: 8,
                                  seq: lastSelect().payload.seq });
    const posted = jest.fn(() => Promise.resolve({ status: 204 }));
    global.fetch = posted;
    window.Workbench.onCapture({ type: 'workbench_capture', id: 'cap-1', item_id: 'i_t', version: 'e'.repeat(64),
                                 serial: 7, wants: ['range'] });
    return Promise.resolve().then(() => {
      expect(JSON.parse(posted.mock.calls[0][1].body)).toEqual({ range: null, note: 'selection_changed' });
    });
  });

  test('choosing a board item puts the attachment away', () => {
    view([NOTES], { selected: null });
    window.Workbench.showAttachment({ source: 'draft', key: 'file:0:cat.png', kind: 'image', name: 'cat.png', data: PNG });
    window.Workbench.select('i_t');
    expect(window.Workbench.shownAttachment()).toBeNull();
    expect(pane().dataset.local).toBeUndefined();
  });

  test('a new item the server brings forward puts the attachment away, so what is shown is what is named', () => {
    view([], { selected: null });
    window.Workbench.showAttachment({ source: 'draft', key: 'file:0:cat.png', kind: 'image', name: 'cat.png', data: PNG });
    expect(window.Workbench.rangeNow()).toBeNull();
    view([NOTES], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [NOTES] }, selected: 'i_t' });
    expect(window.Workbench.shownAttachment()).toBeNull();
    expect(pane().querySelector('img')).toBeNull();
    expect(pane().dataset.item).toBe('i_t');
  });

  test('the same PDF shown again keeps its live view, and other data is drawn anew', () => {
    const restore = useRealBinaryGlobals();
    try {
      const entry = { source: 'draft', key: 'file:0:a.pdf', kind: 'pdf', name: 'a.pdf', data: PDF };
      window.Workbench.showAttachment(entry);
      window.Workbench.showAttachment(Object.assign({}, entry));
      expect(window.WorkbenchPdf.show).toHaveBeenCalledTimes(1);
      const handle = window.WorkbenchPdf.show.mock.results[0].value;
      expect(handle.dispose).not.toHaveBeenCalled();

      window.Workbench.showAttachment(Object.assign({}, entry, { data: 'data:application/pdf;base64,JVBERi0xLjU=' }));
      expect(handle.dispose).toHaveBeenCalled();
      expect(window.WorkbenchPdf.show).toHaveBeenCalledTimes(2);
    } finally {
      restore();
    }
  });

  test('a removed attachment is no longer shown', () => {
    drafts = [{ key: 'file:0:cat.png', kind: 'image', name: 'cat.png', size: 2048, data: PNG }];
    window.Workbench.showAttachment(Object.assign({ source: 'draft' }, drafts[0]));
    drafts = [];
    changed();
    expect(window.Workbench.shownAttachment()).toBeNull();
    expect(pane().querySelector('img')).toBeNull();
  });

  test('a PDF is drawn from its bytes and let go when another file is shown', () => {
    const restore = useRealBinaryGlobals();
    try {
      window.Workbench.showAttachment({ source: 'draft', key: 'file:0:a.pdf', kind: 'pdf', name: 'a.pdf', data: PDF });
      expect(window.WorkbenchPdf.show).toHaveBeenCalledTimes(1);
      const bytes = window.WorkbenchPdf.show.mock.calls[0][1];
      expect([bytes[0], bytes[1], bytes[2], bytes[3]]).toEqual([0x25, 0x50, 0x44, 0x46]);
      const handle = window.WorkbenchPdf.show.mock.results[0].value;
      window.Workbench.showAttachment({ source: 'draft', key: 'file:1:cat.png', kind: 'image', name: 'cat.png', data: PNG });
      expect(handle.dispose).toHaveBeenCalled();
    } finally {
      restore();
    }
  });

  test('a sent PDF with no data in its message says there is nothing to show', () => {
    messages = [{ mid: 'm-1', role: 'user', text: 'see', images: [] }];
    document.getElementById('discourse').innerHTML =
      '<div class="card" id="m-1"><div class="pdf-preview">report.pdf</div></div>';
    document.querySelector('.pdf-preview').click();
    expect(window.Workbench.shownAttachment()).toMatchObject({ source: 'message', kind: 'pdf', name: 'report.pdf', data: null });
    expect(pane().querySelector('.alert').textContent).toBe('No data to show.');
    expect(window.WorkbenchPdf.show).not.toHaveBeenCalled();
  });

  test('a sent PDF is shown from its own message', () => {
    messages = [{ mid: 'm-1', role: 'user', text: 'see', images: [{ title: 'report.pdf', data: PDF }] }];
    document.getElementById('discourse').innerHTML =
      '<div class="card" id="m-1"><div class="pdf-preview">report.pdf</div></div>';
    document.querySelector('.pdf-preview').click();
    expect(window.WorkbenchPdf.show).toHaveBeenCalledTimes(1);
  });

  describe('audio and video', () => {
    const clip = { source: 'draft', key: 'attachment:a_1', kind: 'video', name: 'clip.mp4', size: 10, attachmentId: 'a_1' };

    test('are asked of the server by attachment id, and the item it opens is selected', () => {
      window.Workbench.showAttachment(clip);
      expect(lastOpen().payload).toEqual({ message: 'WORKBENCH_OPEN_ATTACHMENT', attachment_id: 'a_1', request: expect.any(Number) });
      const request = lastOpen().payload.request;
      const video = { id: 'i_v', kind: 'file', preview: 'video', actor: 'user', name: 'clip.mp4', path: 'clip.mp4',
                      sha256: 'f'.repeat(64), status: 'ok' };
      view([video], { selected: null });
      window.Workbench.onAttachmentOpened({ type: 'workbench_attachment_opened', status: 'accepted', request: request,
                                            attachment_id: 'a_1', item_id: 'i_v' });
      expect(window.Workbench.shownAttachment()).toBeNull();
      expect(lastSelect().payload.item_id).toBe('i_v');
    });

    test('a refusal is said in the pane', () => {
      window.Workbench.showAttachment(clip);
      window.Workbench.onAttachmentOpened({ type: 'workbench_attachment_opened', status: 'refused', reason: 'too_large',
                                            request: lastOpen().payload.request, attachment_id: 'a_1' });
      expect(pane().querySelector('.alert').textContent).toBe('This file is too large to play on the work screen.');
      expect(pane().querySelector('code').textContent).toBe('clip.mp4');
    });

    test('an answer to an earlier request, or from before a reset, is dropped', () => {
      view([], { selected: null });
      window.Workbench.showAttachment(clip);
      const first = lastOpen().payload.request;
      window.Workbench.showAttachment(Object.assign({}, clip, { key: 'attachment:a_2', attachmentId: 'a_2' }));
      window.Workbench.onAttachmentOpened({ type: 'workbench_attachment_opened', status: 'refused', reason: 'busy',
                                            request: first, attachment_id: 'a_1' });
      expect(window.Workbench.shownAttachment()).toMatchObject({ attachmentId: 'a_2', note: null });
      const second = lastOpen().payload.request;
      // Another chat: the page starts over.
      view([], { selected: null, board: { board_id: 'b2', chat_id: 'c_2', revision: 1, items: [] } });
      window.Workbench.onAttachmentOpened({ type: 'workbench_attachment_opened', status: 'refused', reason: 'busy',
                                            request: second, attachment_id: 'a_2' });
      expect(window.Workbench.shownAttachment()).toBeNull();
      expect(pane().querySelector('.alert')).toBeNull();
    });
  });
});

describe('Name chips under the message box', () => {
  const SOURCE = '../../docker/services/ruby/public/js/monadic/select_image.js';

  beforeEach(() => {
    document.body.innerHTML = `
      <div id="image-used"></div>
      <select id="apps"><option value="ChatApp" selected>ChatApp</option></select>
      <select id="model"><option value="m" selected>m</option></select>
      <button id="image-file"></button>
      <div id="imageModal"><h5 id="imageModalLabel"></h5>
        <input type="file" id="imageFile" accept=".jpg"><label for="imageFile">File to import</label>
        <div id="select_image_error"></div><button id="uploadImage"></button></div>`;
    global.$id = (id) => document.getElementById(id);
    global.$show = () => {};
    global.$hide = () => {};
    global.setAlert = jest.fn();
    global.getTranslation = (_key, fallback) => fallback;
    window.escapeHtml = (s) => String(s).replace(/</g, '&lt;');
    global.bootstrap = { Modal: { getOrCreateInstance: () => ({ show() {}, hide() {} }) } };
    global.apps = { ChatApp: {} };
    window.getMonadicTabId = () => 'tab 1';
    window.monadicFetch = { postJson: jest.fn() };
    window.Workbench = { showAttachment: jest.fn() };
    jest.isolateModules(() => { require(SOURCE); });
  });

  test('name each file, keep the image for the mask editor, and show the file on the work screen', () => {
    const heard = jest.fn();
    document.addEventListener('attachments:changed', heard);
    window.restoreImages([{ title: 'cat.png', type: 'image/png', data: PNG },
                          { title: 'a.pdf', type: 'application/pdf', data: PDF }]);
    window.restoreVideoAttachments([{ attachment_id: 'a_1', name: 'clip.mp4', size: 1048576, purpose: 'video' }]);
    expect(heard).toHaveBeenCalled();
    const chips = document.querySelectorAll('#image-used .attachment-chip-name');
    expect(chips).toHaveLength(3);
    expect(document.querySelector('#image-used img.base64-image').getAttribute('src')).toBe(PNG);
    expect(window.AttachmentDrafts.list().map((d) => [d.kind, d.name])).toEqual(
      [['image', 'cat.png'], ['pdf', 'a.pdf'], ['video', 'clip.mp4']]);
    chips[1].click();
    expect(window.Workbench.showAttachment).toHaveBeenLastCalledWith(
      expect.objectContaining({ source: 'draft', kind: 'pdf', name: 'a.pdf', data: PDF }));
    chips[2].click();
    expect(window.Workbench.showAttachment).toHaveBeenLastCalledWith(
      expect.objectContaining({ source: 'draft', kind: 'video', attachmentId: 'a_1' }));
  });
});
