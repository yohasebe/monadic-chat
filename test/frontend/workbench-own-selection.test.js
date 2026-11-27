/**
 * @jest-environment jsdom
 */
// What this tab's user puts, makes or opens on the work screen (a file
// put, a new whiteboard, an address opened) becomes the item selected in
// the tab, as a click on its tab selects it, even while the user writes a
// message or has turned the switching off. What the AI or another tab adds
// does not take the selection then.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

describe('An item this tab puts, makes or opens', () => {
  let sent;
  let layout;
  let added;
  let addListener;

  const NOTES = { id: 'i_a', kind: 'file', preview: 'text', actor: 'user', name: 'notes.txt', path: 'notes.txt',
                  sha256: 'a'.repeat(64), version: 'a'.repeat(64), status: 'ok' };
  const BOARD = { id: 'i_wb', kind: 'file', preview: 'text', render: 'whiteboard', actor: 'user', name: 'whiteboard-1.wb.json',
                  path: 'whiteboard-1.wb.json', sha256: 'b'.repeat(64), version: 'b'.repeat(64), status: 'ok' };
  const PAPER = { id: 'i_pdf', kind: 'file', preview: 'pdf', actor: 'user', name: 'paper.pdf', path: 'paper.pdf',
                  sha256: 'c'.repeat(64), version: 'c'.repeat(64), status: 'ok' };
  const BROWSER = { id: 'i_br', kind: 'browser', actor: 'agent', instance: 1 };

  let revision = 0;
  function view(items, selected) {
    revision += 1;
    window.Workbench.onView({
      board: { board_id: 'b1', chat_id: 'c_1', revision: revision, items: items },
      approvals: Object.fromEntries(items.map((i) => [i.id, `tok-${i.id}`])),
      assets: Object.fromEntries(items.map((i) => [i.id, `/workbench/asset/${i.id}`])),
      selected: selected
    });
  }

  const selectedTab = () => {
    const tab = document.querySelector('.workbench-item[aria-selected="true"]');
    return tab ? tab.dataset.item : null;
  };
  const lastSelect = () => sent.filter((x) => x.payload.message === 'WORKBENCH_SELECT').pop();
  const lastOf = (message) => sent.filter((x) => x.payload.message === message).pop();
  const flush = async () => { for (let i = 0; i < 5; i += 1) await new Promise((r) => setTimeout(r, 0)); };

  // The user is writing a message, with the switching to new items off.
  function busyUser() {
    const box = document.getElementById('message');
    box.value = 'a message being written';
    box.focus();
    window.getCookie = () => 'false';
  }

  afterEach(() => {
    added.forEach(([type, fn, opts]) => document.removeEventListener(type, fn, opts));
    document.addEventListener = addListener;
    delete window.getCookie;
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
      <div id="work-screen-pane">
        <button id="workbench-put"></button><input type="file" id="workbench-put-input" hidden>
        <button id="workbench-new-whiteboard"></button>
        <div id="workbench-status"></div>
        <div id="workbench-items" hidden></div>
        <div id="work-screen-browser"></div>
        <div id="workbench-view" hidden></div>
      </div>
      <div id="discourse"></div>
      <textarea id="message"></textarea>`;
    sent = [];
    revision = 0;
    layout = { hidden: false, pane: 'work' };
    window.LayoutController = {
      isMenuHidden: () => layout.hidden,
      setMenuHidden: jest.fn((h) => { layout.hidden = h; }),
      selectedPane: () => layout.pane,
      setPane: jest.fn((p) => { layout.pane = p; })
    };
    window.WorkScreen = { refresh: jest.fn() };
    window.safeWsSend = (payload, opts) => sent.push({ payload, opts });
    window.SessionState = { getMessages: () => [] };
    window.WorkbenchPdf = { show: jest.fn(() => ({ dispose: jest.fn() })) };
    window.setAlert = jest.fn();
    global.fetch = jest.fn(() => new Promise(() => {}));
    delete window.electronAPI;
    delete global.webUIi18n;
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/workbench.js'));
    view([NOTES], 'i_a');
  });

  test('a new whiteboard the user made is selected, over the item selected before', () => {
    expect(selectedTab()).toBe('i_a');
    busyUser();
    document.getElementById('workbench-new-whiteboard').click();
    const request = lastOf('WORKBENCH_WHITEBOARD_NEW').payload.request;
    window.Workbench.onWhiteboard({ type: 'workbench_whiteboard', request: request, status: 'saved', item_id: 'i_wb',
                                    version: BOARD.sha256 });
    view([NOTES, BOARD], 'i_wb');
    expect(selectedTab()).toBe('i_wb');
    expect(lastSelect().payload.item_id).toBe('i_wb');
  });

  test('a new whiteboard that was refused selects nothing new', () => {
    document.getElementById('workbench-new-whiteboard').click();
    const request = lastOf('WORKBENCH_WHITEBOARD_NEW').payload.request;
    window.Workbench.onWhiteboard({ type: 'workbench_whiteboard', request: request, status: 'refused', reason: 'full' });
    view([NOTES], 'i_a');
    expect(selectedTab()).toBe('i_a');
  });

  test('a file the user dropped on the work screen is selected once the server opened it', async () => {
    window.monadicFetch = { postJson: jest.fn(async () => ({ attachment_id: 'a_1', name: 'paper.pdf', size: 10 })) };
    try {
      busyUser();
      const drop = new Event('drop', { bubbles: true, cancelable: true });
      Object.defineProperty(drop, 'dataTransfer', {
        value: { types: ['Files'], files: [new File(['%PDF-'], 'paper.pdf', { type: 'application/pdf' })] }
      });
      document.getElementById('work-screen-pane').dispatchEvent(drop);
      await flush();
      const request = lastOf('WORKBENCH_OPEN_ATTACHMENT').payload.request;
      window.Workbench.onAttachmentOpened({ type: 'workbench_attachment_opened', status: 'accepted', request: request,
                                            attachment_id: 'a_1', item_id: 'i_pdf' });
      view([NOTES, PAPER], 'i_a');
      expect(selectedTab()).toBe('i_pdf');
      expect(lastSelect().payload.item_id).toBe('i_pdf');
    } finally {
      delete window.monadicFetch;
    }
  });

  test('what an address opened (the browser, or a PDF put as a file) is selected, on the board or when it comes', () => {
    view([NOTES, BROWSER], 'i_a');
    busyUser();
    window.Workbench.showOwn('i_br');
    expect(selectedTab()).toBe('i_br');
    // A PDF the server put as a file: its item comes with the next board.
    window.Workbench.showOwn('i_pdf');
    expect(selectedTab()).toBe('i_br');
    view([NOTES, BROWSER, PAPER], 'i_br');
    expect(selectedTab()).toBe('i_pdf');
  });

  test('an item the AI adds while the user writes does not take the selection', () => {
    busyUser();
    view([NOTES, BOARD], 'i_wb');
    expect(selectedTab()).toBe('i_a');
  });
});
