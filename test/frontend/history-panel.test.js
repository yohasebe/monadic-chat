/**
 * @jest-environment jsdom
 */
// The History tab of the side column, on the page's own markup: names are
// set as text, an open chat is neither continued nor removed from here, a
// Private chat is replaced only after a question tied to that chat, and the
// tab is there only while a history is kept.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../../docker/services/ruby');
const PAGE = fs.readFileSync(path.join(ROOT, 'views/index.erb'), 'utf8');
const TRANSLATIONS = fs.readFileSync(path.join(ROOT, 'public/js/i18n/translations.js'), 'utf8');

function cut(from, to) {
  const start = PAGE.indexOf(from);
  const end = PAGE.indexOf(to, start);
  if (start < 0 || end < 0) throw new Error('markup not found: ' + from);
  return PAGE.slice(start, end);
}

describe('chat history words', () => {
  it('are in every language with the same keys', () => {
    const blocks = TRANSLATIONS.split(/\n {2}(?=\w\w: \{\n {4}ui: \{)/).slice(1);
    expect(blocks.map((b) => b.slice(0, 2))).toEqual(['en', 'ja', 'zh', 'ko', 'es', 'fr', 'de']);
    const keysOf = (block) => {
      const body = block.match(/\n {6}historyPanel: \{\n([\s\S]*?)\n {6}\},/);
      expect(body).not.toBeNull();
      return body[1].split('\n').map((l) => l.trim().split(':')[0]);
    };
    const english = keysOf(blocks[0]);
    blocks.forEach((b) => expect(keysOf(b)).toEqual(english));
    // Every key the page and the script use is there.
    const used = new Set();
    (PAGE.match(/ui\.historyPanel\.(\w+)/g) || []).forEach((k) => used.add(k.split('.').pop()));
    const script = fs.readFileSync(path.join(ROOT, 'public/js/monadic/history-panel.js'), 'utf8');
    (script.match(/\bt\('(\w+)'/g) || []).forEach((k) => used.add(k.slice(3, -1)));
    used.forEach((k) => expect(english).toContain(k));
  });
});

describe('History tab', () => {
  let sent;
  let pane;
  let narrow;

  function load() {
    jest.resetModules();
    require('../../docker/services/ruby/public/js/monadic/dom-helpers.js');
    require('../../docker/services/ruby/public/js/monadic/row-menu.js');
    require('../../docker/services/ruby/public/js/monadic/history-panel.js');
  }

  function list(items, extra) {
    window.HistoryPanel.onMessage(Object.assign({ type: 'history_list', enabled: true, query: '', offset: 0, items }, extra));
  }

  const item = (over) => Object.assign({
    chat_id: 'c_aaaaaaaaaaaaaaaa', title_user: null, heading_first: 'Plan a trip', heading_recent: 'The slides',
    app_name: 'ChatOpenAI', message_count: 4, last_activity_at: '2026-10-24T10:00:00Z', open: false
  }, over);
  const rows = () => Array.from(document.querySelectorAll('#history-list .history-row'));
  const show = () => { pane = 'history'; document.dispatchEvent(new Event('layoutchange')); };
  const leave = () => { pane = 'settings'; document.dispatchEvent(new Event('layoutchange')); };
  const menuItem = (label) => Array.from(document.querySelectorAll('.row-menu .dropdown-item')).find((b) => b.textContent.includes(label));
  const status = () => document.getElementById('history-status');

  beforeEach(() => {
    jest.useFakeTimers();
    document.body.innerHTML = '<div id="side-pane-tabs"><button id="side-tab-history" hidden></button></div>' +
      cut('<%# The kept chats', '<%# The border between the columns');
    pane = 'settings';
    narrow = false;
    window.LayoutController = {
      selectedPane: () => pane, isMenuHidden: () => false,
      setPane: jest.fn((p) => { pane = p; }), setMenuHidden: jest.fn()
    };
    window.UIConfig = { isTabletView: () => narrow };
    sent = [];
    window.safeWsSend = (payload) => { sent.push(payload); return { sent: true }; };
    load();
  });

  afterEach(() => {
    if (window.RowMenu) window.RowMenu.close();
    jest.useRealTimers();
    delete window.HistoryPanel;
  });

  it('shows the tab only while the server keeps a history, and leaves it when it stops', () => {
    list([], { enabled: false });
    expect(document.getElementById('side-tab-history').hidden).toBe(true);
    list([]);
    expect(document.getElementById('side-tab-history').hidden).toBe(false);
    show();
    list([], { enabled: false });
    expect(window.LayoutController.setPane).toHaveBeenCalledWith('settings');
  });

  it('asks for the chats when the tab comes into view', () => {
    show();
    expect(sent).toContainEqual({ message: 'HISTORY_LIST', query: '', offset: 0 });
  });

  it('sets names and headings as text, and continues a chat with a click', () => {
    show();
    list([item({ title_user: '<img src=x onerror=alert(1)>' })]);
    const list_ = document.getElementById('history-list');
    expect(list_.querySelector('img')).toBeNull();
    expect(list_.textContent).toContain('<img src=x onerror=alert(1)>');
    rows()[0].querySelector('.history-name').click();
    expect(sent).toContainEqual({ message: 'HISTORY_RESUME', chat_id: 'c_aaaaaaaaaaaaaaaa' });
  });

  it('neither continues nor removes a chat open in a tab', () => {
    show();
    list([item({ open: true })]);
    expect(rows()[0].querySelector('.history-name').disabled).toBe(true);
    rows()[0].querySelector('.sfp-row-menu').click();
    expect(menuItem('Continue').disabled).toBe(true);
    expect(menuItem('Remove').disabled).toBe(true);
  });

  it('removes a chat only after it is asked again', () => {
    show();
    list([item()]);
    rows()[0].querySelector('.sfp-row-menu').click();
    menuItem('Remove').click();
    expect(sent.some((m) => m.message === 'HISTORY_DELETE')).toBe(false);
    rows()[0].querySelector('.btn-danger').click();
    expect(sent).toContainEqual({ message: 'HISTORY_DELETE', chat_id: 'c_aaaaaaaaaaaaaaaa' });
  });

  it('names a chat with Enter, not while text is still being composed', () => {
    show();
    list([item()]);
    rows()[0].querySelector('.sfp-row-menu').click();
    menuItem('Name').click();
    jest.runOnlyPendingTimers();
    const input = document.querySelector('#history-list input');
    input.value = 'Trip';
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', isComposing: true, bubbles: true }));
    expect(sent.some((m) => m.message === 'HISTORY_RENAME')).toBe(false);
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    expect(sent).toContainEqual({ message: 'HISTORY_RENAME', chat_id: 'c_aaaaaaaaaaaaaaaa', title: 'Trip' });
  });

  it('asks before a Private chat here is replaced, keeps the question while lists arrive, and sends the answer for that chat', () => {
    show();
    list([item()]);
    rows()[0].querySelector('.history-name').click();
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    expect(status().hidden).toBe(false);
    list([item(), item({ chat_id: 'c_bbbbbbbbbbbbbbbb' })]);
    expect(status().hidden).toBe(false);
    status().querySelector('.btn-warning').click();
    expect(sent).toContainEqual({ message: 'HISTORY_RESUME', chat_id: 'c_aaaaaaaaaaaaaaaa', confirm: true });
  });

  it('takes the question back when the tab is left, and a late answer does not bring it back', () => {
    show();
    list([item()]);
    rows()[0].querySelector('.history-name').click();
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    leave();
    expect(status().hidden).toBe(true);
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    show();
    list([item()]);
    expect(status().hidden).toBe(true);
    expect(sent.some((m) => m.confirm)).toBe(false);
  });

  it('asks nothing for a request given up on by leaving the tab, also once the tab is back', () => {
    show();
    list([item()]);
    rows()[0].querySelector('.history-name').click();
    leave();
    show();
    list([item()]);
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    expect(status().hidden).toBe(true);
  });

  it('asks only about the chat the standing request is for', () => {
    show();
    list([item(), item({ chat_id: 'c_bbbbbbbbbbbbbbbb' })]);
    rows()[1].querySelector('.history-name').click();
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    expect(status().hidden).toBe(true);
  });

  it('continues one chat at a time: a second click waits for the first answer, and the question is asked for the request that stands', () => {
    show();
    list([item(), item({ chat_id: 'c_bbbbbbbbbbbbbbbb' })]);
    rows()[0].querySelector('.history-name').click();
    rows()[1].querySelector('.history-name').click();
    expect(sent.filter((m) => m.message === 'HISTORY_RESUME')).toHaveLength(1);
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    expect(status().hidden).toBe(false);
    status().querySelector('.btn-secondary').click();
    rows()[1].querySelector('.history-name').click();
    expect(sent.filter((m) => m.message === 'HISTORY_RESUME').pop()).toEqual({ message: 'HISTORY_RESUME', chat_id: 'c_bbbbbbbbbbbbbbbb' });
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_bbbbbbbbbbbbbbbb', success: false, error: 'history_private_here' });
    expect(status().hidden).toBe(false);
  });

  it('does not let a late answer to a request given up on stand for the same chat asked again', () => {
    show();
    list([item()]);
    rows()[0].querySelector('.history-name').click();
    leave();
    show();
    list([item()]);
    rows()[0].querySelector('.history-name').click();
    expect(sent.filter((m) => m.message === 'HISTORY_RESUME')).toHaveLength(1);
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    expect(status().hidden).toBe(true);
    rows()[0].querySelector('.history-name').click();
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    expect(status().hidden).toBe(false);
  });

  it('keeps waiting for an answer however long it takes, and lets the next request go on a new connection', () => {
    show();
    list([item()]);
    rows()[0].querySelector('.history-name').click();
    leave();
    show();
    list([item()]);
    jest.advanceTimersByTime(60000);
    rows()[0].querySelector('.history-name').click();
    expect(sent.filter((m) => m.message === 'HISTORY_RESUME')).toHaveLength(1);
    // The old answer, late: it is the one given up on, and asks nothing.
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    expect(status().hidden).toBe(true);
    rows()[0].querySelector('.history-name').click();
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    expect(status().hidden).toBe(false);
    // An answer lost with its connection: a new connection lets the next go.
    status().querySelector('.btn-secondary').click();
    rows()[0].querySelector('.history-name').click();
    window.HistoryPanel.connectionOpened();
    rows()[0].querySelector('.history-name').click();
    expect(sent.filter((m) => m.message === 'HISTORY_RESUME')).toHaveLength(4);
  });

  it('lets the next request go after a failure, which may name no chat', () => {
    show();
    list([item()]);
    rows()[0].querySelector('.history-name').click();
    window.HistoryPanel.onMessage({ type: 'history_resumed', success: false, error: 'history_failed' });
    expect(status().textContent).toContain('did not work');
    rows()[0].querySelector('.history-name').click();
    expect(sent.filter((m) => m.message === 'HISTORY_RESUME')).toHaveLength(2);
  });

  it('shows the conversation after a chat is continued on a narrow screen', () => {
    show();
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: true });
    expect(window.LayoutController.setMenuHidden).not.toHaveBeenCalled();
    narrow = true;
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: true });
    expect(window.LayoutController.setMenuHidden).toHaveBeenCalledWith(true);
  });
});
