/**
 * @jest-environment jsdom
 */
// The chat history in the sidebar and in the window it shares with the
// shared folder, on the page's own markup: names are set as text, an open
// chat is neither continued nor removed from here, a Private chat is
// replaced only after a question, and nothing shows while no history is kept.
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

describe('chat history', () => {
  let sent;
  let modal;

  function load() {
    jest.resetModules();
    require('../../docker/services/ruby/public/js/monadic/history-panel.js');
  }

  function list(items, extra) {
    window.HistoryPanel.onMessage(Object.assign({ type: 'history_list', enabled: true, query: '', offset: 0, items }, extra));
  }

  const item = (over) => Object.assign({
    chat_id: 'c_aaaaaaaaaaaaaaaa', title_user: null, heading_first: 'Plan a trip', heading_recent: 'The slides',
    app_name: 'ChatOpenAI', message_count: 4, last_activity_at: '2026-10-24T10:00:00Z', open: false
  }, over);

  beforeEach(() => {
    jest.useFakeTimers();
    document.body.innerHTML = cut('<div id="history-panel"', '<div id="shared-folder-panel"') +
      cut('<div class="modal fade" id="sharedFolderModal"', '<div class="modal fade" id="libraryBrowseModal"');
    global.$id = (id) => document.getElementById(id);
    global.$on = (node, ev, fn) => node && node.addEventListener(ev, fn);
    global.$show = (node) => { if (node) node.style.display = ''; };
    global.$hide = (node) => { if (node) node.style.display = 'none'; };
    global.$toggle = (node, on) => (on ? global.$show(node) : global.$hide(node));
    modal = document.getElementById('sharedFolderModal');
    // As Bootstrap does, the window is marked shown only after its fade.
    const instance = { show() { setTimeout(() => modal.classList.add('show'), 150); }, hide() { modal.classList.remove('show'); } };
    window.bootstrap = { Modal: { getOrCreateInstance: () => instance } };
    global.bootstrap = window.bootstrap;
    sent = [];
    window.safeWsSend = (payload) => { sent.push(payload); return { sent: true }; };
    load();
  });

  afterEach(() => {
    jest.useRealTimers();
    delete window.HistoryPanel;
  });

  it('stays hidden while the server keeps no history', () => {
    list([], { enabled: false });
    expect(document.getElementById('history-panel').style.display).toBe('none');
    expect(document.getElementById('manage-tabs').style.display).toBe('none');
    list([item()]);
    expect(document.getElementById('history-panel').style.display).toBe('');
  });

  it('sets names and headings as text, and continues a chat from the sidebar', () => {
    list([item({ title_user: '<img src=x onerror=alert(1)>' })]);
    const recent = document.getElementById('history-recent');
    expect(recent.querySelector('img')).toBeNull();
    expect(recent.textContent).toContain('<img src=x onerror=alert(1)>');
    recent.querySelector('button').click();
    expect(sent).toContainEqual({ message: 'HISTORY_RESUME', chat_id: 'c_aaaaaaaaaaaaaaaa' });
  });

  it('shows the chats tab, and neither continues nor removes a chat open in a tab', () => {
    list([]);
    window.HistoryPanel.open();
    expect(document.getElementById('history-chats-body').style.display).toBe('');
    expect(document.getElementById('shared-folder-files-body').style.display).toBe('none');
    list([item({ open: true }), item({ chat_id: 'c_bbbbbbbbbbbbbbbb' })]);
    const rows = document.querySelectorAll('#history-tbody tr');
    expect(rows).toHaveLength(2);
    const buttons = (row) => Array.from(row.querySelectorAll('button'));
    expect(buttons(rows[0]).map((b) => b.disabled)).toEqual([true, false, true]);
    expect(buttons(rows[1]).map((b) => b.disabled)).toEqual([false, false, false]);
  });

  it('removes a chat only after it is asked again', () => {
    list([]);
    window.HistoryPanel.open();
    list([item()]);
    const remove = () => Array.from(document.querySelectorAll('#history-tbody button')).pop();
    remove().click();
    expect(sent.some((m) => m.message === 'HISTORY_DELETE')).toBe(false);
    document.querySelector('#history-tbody .btn-danger').click();
    expect(sent).toContainEqual({ message: 'HISTORY_DELETE', chat_id: 'c_aaaaaaaaaaaaaaaa' });
  });

  it('names a chat with Enter, not while text is still being composed', () => {
    list([]);
    window.HistoryPanel.open();
    list([item()]);
    document.querySelectorAll('#history-tbody button')[1].click();
    jest.runOnlyPendingTimers();
    const input = document.querySelector('#history-tbody input');
    input.value = 'Trip';
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', isComposing: true, bubbles: true }));
    expect(sent.some((m) => m.message === 'HISTORY_RENAME')).toBe(false);
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    expect(sent).toContainEqual({ message: 'HISTORY_RENAME', chat_id: 'c_aaaaaaaaaaaaaaaa', title: 'Trip' });
  });

  it('asks before a Private chat here is replaced, and sends the answer', () => {
    list([]);
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    jest.advanceTimersByTime(200);
    expect(modal.classList.contains('show')).toBe(true);
    const status = document.getElementById('history-status');
    expect(status.style.display).toBe('');
    status.querySelector('.btn-warning').click();
    expect(sent).toContainEqual({ message: 'HISTORY_RESUME', chat_id: 'c_aaaaaaaaaaaaaaaa', confirm: true });
  });

  it('keeps the question about the Private chat while lists arrive', () => {
    list([]);
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: false, error: 'history_private_here' });
    jest.advanceTimersByTime(200);
    expect(sent.some((m) => m.message === 'HISTORY_LIST')).toBe(true);
    list([item()]);
    const status = document.getElementById('history-status');
    expect(status.style.display).toBe('');
    status.querySelector('.btn-secondary').click();
    expect(status.style.display).toBe('none');
    list([item()]);
    expect(status.style.display).toBe('none');
  });

  it('closes the window when the chat is continued here', () => {
    list([]);
    window.HistoryPanel.open();
    window.HistoryPanel.onMessage({ type: 'history_resumed', chat_id: 'c_aaaaaaaaaaaaaaaa', success: true });
    expect(modal.classList.contains('show')).toBe(false);
  });
});
