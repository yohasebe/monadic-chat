/**
 * @jest-environment jsdom
 */
// The workbench in the work screen pane: each image is shown there with
// "Save to the shared folder" while it is not saved, and a × that removes it;
// nothing waits for an answer. The conversation keeps one line of text (the
// name opens the image). A new image is brought forward without opening a
// column the user hid or taking the pane while they type.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

describe('Workbench', () => {
  let sent;
  let messages;
  let layout;

  function card(mid) {
    const el = document.createElement('div');
    el.id = mid;
    el.innerHTML = '<div class="card-body"><div class="card-text"><p>done</p></div></div>';
    document.getElementById('discourse').appendChild(el);
    return el;
  }

  function item(overrides = {}) {
    return Object.assign({ id: 'i_1', kind: 'image', mid: 'm-1', name: 'cat.png', sha256: 'a'.repeat(64), save: null }, overrides);
  }

  function view(items, extra = {}) {
    window.Workbench.onView(Object.assign({
      board: { board_id: 'b1', chat_id: 'c_1', revision: 1, items: items },
      approvals: Object.fromEntries(items.map((i) => [i.id, `tok-${i.id}`])),
      assets: Object.fromEntries(items.map((i) => [i.id, `/workbench/asset/${i.id}`]))
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
    delete global.webUIi18n;
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/workbench.js'));
  });

  test('shows a new image in the pane with Save, and only a line of text in the conversation', () => {
    const el = card('m-1');
    view([item()]);
    const pane = document.getElementById('workbench-view');
    expect(pane.hidden).toBe(false);
    expect(pane.querySelector('img').getAttribute('src')).toBe('/workbench/asset/i_1');
    expect(pane.querySelector('.btn-primary').textContent).toBe('Save to the shared folder');
    expect(document.getElementById('work-screen-browser').hidden).toBe(true);
    expect(window.Workbench.showsBrowser()).toBe(false);
    expect(window.LayoutController.setPane).toHaveBeenCalledWith('work');
    expect(document.getElementById('workbench-status').textContent).not.toBe('');
    expect(el.querySelector('img')).toBeNull();
    expect(el.querySelector('.workbench-note').textContent).toContain('cat.png — Not saved');
  });

  test('brings nothing forward from the board a connection is sent first (a reload)', () => {
    card('m-1');
    view([item()], { initial: true });
    expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    expect(window.Workbench.showsBrowser()).toBe(true);
  });

  test('does not open a column the user hid, nor take the pane while the user types', () => {
    layout.hidden = true;
    view([item()]);
    expect(window.LayoutController.setMenuHidden).not.toHaveBeenCalled();
    expect(window.LayoutController.setPane).not.toHaveBeenCalled();

    layout.hidden = false;
    window.Workbench.select('browser');
    document.getElementById('message').focus();
    view([item(), item({ id: 'i_2', name: 'dog.png', sha256: 'b'.repeat(64) })]);
    expect(window.LayoutController.setPane).not.toHaveBeenCalled();
    expect(window.Workbench.showsBrowser()).toBe(true);
  });

  test('saves with the image\'s token and one operation id, the same when sent again', () => {
    card('m-1');
    view([item()]);
    document.querySelector('#workbench-view .btn-primary').click();
    view([item()]);
    document.querySelector('#workbench-view .btn-primary').click();
    expect(sent.map((s) => s.payload.message)).toEqual(['WORKBENCH_ACTION', 'WORKBENCH_ACTION']);
    expect(sent[0].payload).toMatchObject({ item_id: 'i_1', action: 'save', token: 'tok-i_1' });
    expect(sent[0].payload).not.toHaveProperty('confirmation_revision');
    expect(sent[1].payload.operation_id).toBe(sent[0].payload.operation_id);
    expect(sent[0].opts).toMatchObject({ idempotent: true });
  });

  test('offers Save only while an image is not saved, and no × while its save is under way', () => {
    card('m-1');
    view([item({ save: { state: 'original_kept', name: null } })]);
    window.Workbench.select('i_1');
    expect(document.querySelector('#workbench-view .btn-primary')).toBeNull();
    expect(document.querySelector('#workbench-view .btn-outline-secondary').textContent).toBe('Try again');
    expect(document.querySelector('.workbench-item-remove')).toBeNull();
    const saved = item({ save: { state: 'recorded', name: 'cat-2.png' } });
    view([saved], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [saved] } });
    expect(document.querySelector('#workbench-view .btn-primary')).toBeNull();
    expect(document.querySelector('#workbench-view code').textContent).toBe('cat-2.png');
    expect(document.querySelector('.workbench-item-remove')).not.toBeNull();
  });

  test('removes an image with its ×, and keeps a line saying so', () => {
    const el = card('m-1');
    view([item()]);
    document.querySelector('.workbench-item-remove').click();
    expect(sent[0].payload).toMatchObject({ message: 'WORKBENCH_ACTION', item_id: 'i_1', action: 'remove' });
    window.Workbench.onResult({ status: 'accepted', action: 'remove', item_id: 'i_1' });
    view([], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [] }, approvals: {}, assets: {} });
    expect(el.querySelector('.workbench-note').textContent).toContain('Removed from the work screen');
    expect(window.Workbench.showsBrowser()).toBe(true);
    expect(document.getElementById('workbench-items').hidden).toBe(true);
  });

  test('says so when the board put an older image away to make room', () => {
    view([item()]);
    document.getElementById('workbench-status').textContent = '';
    const next = item({ id: 'i_2', sha256: 'b'.repeat(64) });
    view([next], { board: { board_id: 'b1', chat_id: 'c_1', revision: 2, items: [next] } });
    expect(document.getElementById('workbench-status').textContent).toContain('older image');
  });

  test('opens the image in the pane from its line, showing the column the user hid', () => {
    const el = card('m-1');
    view([item()]);
    window.Workbench.select('browser');
    layout.hidden = true;
    layout.pane = 'settings';
    el.querySelector('.workbench-note button').click();
    expect(window.LayoutController.setMenuHidden).toHaveBeenCalledWith(false);
    expect(layout.pane).toBe('work');
    expect(window.Workbench.showsBrowser()).toBe(false);
  });

  test('names a long image by its start and end in the list, with the whole name on hover', () => {
    view([item({ name: 'generate_gpt-image-2_1793879585_0.png' })]);
    const tab = document.querySelector('#workbench-items [data-item="i_1"]');
    expect(tab.querySelector('.workbench-item-name').textContent).toBe('generate_…3879585_0.png');
    expect(tab.title).toBe('generate_gpt-image-2_1793879585_0.png');
  });

  test('ignores an older revision of the board, and starts over for another chat', () => {
    const el = card('m-1');
    view([item()], { board: { board_id: 'b1', chat_id: 'c_1', revision: 5, items: [item()] } });
    view([], { board: { board_id: 'b1', chat_id: 'c_1', revision: 4, items: [] }, approvals: {}, assets: {} });
    expect(el.querySelector('.workbench-note')).not.toBeNull();
    view([], { board: { board_id: null, chat_id: 'c_2', revision: 0, items: [] }, approvals: {}, assets: {} });
    expect(el.querySelector('.workbench-note')).toBeNull();
  });

  test('leaves nothing of the chat before on a message of the same id in the next chat', () => {
    card('m-1');
    view([item()]);
    document.getElementById('discourse').replaceChildren();
    const next = card('m-1');
    messages = [{ mid: 'm-1', role: 'assistant', text: 'other' }];
    window.Workbench.drawRecord('m-1', []);
    view([], { board: { board_id: null, chat_id: 'c_2', revision: 0, items: [] }, approvals: {}, assets: {} });
    expect(next.querySelector('.workbench-note')).toBeNull();
  });

  test('keeps the next chat\'s own record when its board arrives after its messages', () => {
    card('m-1');
    view([item()]);
    document.getElementById('discourse').replaceChildren();
    const next = card('m-1');
    const record = [{ id: 'r_2', name: 'b.png' }];
    messages = [{ mid: 'm-1', role: 'assistant', text: 'other', artifacts: record }];
    window.Workbench.drawRecord('m-1', record);
    view([], { board: { board_id: null, chat_id: 'c_2', revision: 0, items: [] }, approvals: {}, assets: {} });
    const lines = Array.from(next.querySelectorAll('.workbench-note-line')).map((l) => l.textContent);
    expect(lines).toEqual(['b.png — Saved']);
  });

  test('lists what a message saved by name, drawn as text, and keeps it with the message', () => {
    const el = card('m-1');
    const record = [{ id: 'r_1', name: '<img src=x onerror=alert(1)>.png' }];
    window.Workbench.onArtifacts({ mid: 'm-1', artifacts: record });
    const note = el.querySelector('.workbench-note');
    expect(note.querySelector('img')).toBeNull();
    expect(note.querySelector('code').textContent).toBe('<img src=x onerror=alert(1)>.png');
    expect(messages[0].artifacts).toEqual(record);
  });

  test('tells the user when an operation was refused or a save did not finish', () => {
    window.Workbench.onResult({ status: 'refused' });
    window.Workbench.onResult({ status: 'incomplete', action: 'save' });
    window.Workbench.onResult({ status: 'accepted', action: 'save', state: 'recorded', name: 'a.png' });
    expect(window.setAlert).toHaveBeenCalledTimes(2);
  });
});
