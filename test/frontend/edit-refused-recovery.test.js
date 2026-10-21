/**
 * @jest-environment jsdom
 */

// An edit the server refuses (a Privacy mark it cannot take) leaves the
// message as it was on the server; the page puts that card back too, and
// leaves the message box, a pending send and a running answer alone.

function el(tag, id) {
  const node = document.createElement(tag);
  node.id = id;
  document.body.appendChild(node);
  return node;
}

function card(mid, html) {
  const node = document.createElement('div');
  node.className = 'card';
  node.id = mid;
  node.innerHTML = `<div class="card-header"><span class="func-edit"><i class="fa-pen-to-square"></i></span></div>` +
    `<div class="card-text">${html}</div>`;
  document.getElementById('discourse').appendChild(node);
  return node;
}

beforeEach(() => {
  document.body.innerHTML = '';
  el('div', 'discourse');
  el('textarea', 'message').value = 'a draft being written';
  el('select', 'select-role');
  el('div', 'temp-card');
  el('div', 'cancel_query');
  global.messages = [
    { mid: 'm1', role: 'user', text: 'old words' },
    { mid: 'm2', role: 'assistant', text: 'an answer' }
  ];
  window.messages = global.messages;
  global.cleanupAllTooltips = jest.fn();
  global.setAlert = jest.fn();
  global.getTranslation = jest.fn((key, fallback) => fallback);
  global.deleteMessage = jest.fn();
  window.safeWsSend = jest.fn(() => ({ sent: true }));
  window.pendingEdits = undefined;
  window.pendingSend = { text: 'queued', attachments: [], images: [] };
  window.streamingResponse = true;
  jest.isolateModules(() => {
    require('../../docker/services/ruby/public/js/monadic/cards.js');
    require('../../docker/services/ruby/public/js/monadic/ws-error-handler.js');
  });
});

function editAndSave(node, newText) {
  window.attachEventListeners(node);
  node.querySelector('.func-edit').dispatchEvent(new MouseEvent('click', { bubbles: true }));
  const area = node.querySelector('.inline-edit-textarea');
  area.value = newText;
  node.querySelector('.save-edit').dispatchEvent(new MouseEvent('click', { bubbles: true }));
}

describe('a refused edit', () => {
  it('puts the card and the message back, and touches nothing else', () => {
    const first = card('m1', '<p>old words</p>');
    card('m2', '<p>an answer</p>');
    editAndSave(first, 'Hello ⟦Bob');

    expect(window.safeWsSend).toHaveBeenCalledWith(expect.objectContaining({ message: 'EDIT', mid: 'm1', content: 'Hello ⟦Bob' }));
    expect(global.messages[0].text).toBe('Hello ⟦Bob');

    window.WsErrorHandler.handleError({ content: 'Nothing was sent.', not_accepted: true, edit_refused: true, mid: 'm1' });

    expect(first.querySelector('.card-text').innerHTML).toBe('<p>old words</p>');
    expect(global.messages[0].text).toBe('old words');
    expect(window.pendingEdits.m1).toBeUndefined();
    expect(document.getElementById('message').value).toBe('a draft being written');
    expect(window.pendingSend).toEqual({ text: 'queued', attachments: [], images: [] });
    expect(window.streamingResponse).toBe(true);
    expect(global.deleteMessage).not.toHaveBeenCalled();
    expect(window.safeWsSend).toHaveBeenCalledTimes(1);
    expect(global.setAlert).toHaveBeenCalledWith('Nothing was sent.', 'error');
  });

  it('lets one edit of a message wait at a time, and leaves the edits of other cards alone', () => {
    const first = card('m1', '<p>old words</p>');
    const second = card('m2', '<p>an answer</p>');
    card('m3', '<p>last</p>');
    global.messages.push({ mid: 'm3', role: 'assistant', text: 'last' });
    editAndSave(first, 'first ⟦bad');
    first.querySelector('.func-edit').dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(first.querySelector('.inline-edit-textarea')).toBeNull();
    expect(global.setAlert).toHaveBeenLastCalledWith(expect.stringContaining('still being saved'), 'warning');
    editAndSave(second, 'a better answer');
    expect(window.safeWsSend).toHaveBeenCalledTimes(2);

    window.WsErrorHandler.handleError({ content: 'Nothing was sent.', not_accepted: true, edit_refused: true, mid: 'm1' });
    expect(first.querySelector('.card-text').innerHTML).toBe('<p>old words</p>');
    expect(global.messages[0].text).toBe('old words');
    expect(window.pendingEdits.m2).toEqual(expect.objectContaining({ text: 'an answer' }));
    expect(global.messages[1].text).toBe('a better answer');

    first.querySelector('.func-edit').dispatchEvent(new MouseEvent('click', { bubbles: true }));
    expect(first.querySelector('.inline-edit-textarea')).not.toBeNull();
  });

  it('puts the text back into the message list the page holds now, and forgets edits when the chat is reloaded', () => {
    const first = card('m1', '<p>old words</p>');
    card('m2', '<p>an answer</p>');
    editAndSave(first, 'Hello ⟦Bob');
    window.messages = global.messages = global.messages.map(m => ({ ...m }));
    window.WsErrorHandler.handleError({ content: 'Nothing was sent.', not_accepted: true, edit_refused: true, mid: 'm1' });
    expect(global.messages[0].text).toBe('old words');

    editAndSave(first, 'again ⟦Bob');
    jest.isolateModules(() => {
      require('../../docker/services/ruby/public/js/monadic/ws-message-renderer.js');
    });
    window.WsMessageRenderer.handlePastMessages({ content: [] });
    expect(window.pendingEdits).toEqual({});
  });

  it('is forgotten once the server takes the edit', () => {
    const first = card('m1', '<p>old words</p>');
    card('m2', '<p>an answer</p>');
    editAndSave(first, 'new words');
    expect(window.pendingEdits.m1).toEqual(expect.objectContaining({ text: 'old words' }));
    jest.isolateModules(() => {
      require('../../docker/services/ruby/public/js/monadic/ws-message-renderer.js');
    });
    window.WsMessageRenderer.handleEditSuccess({ mid: 'm1', content: 'Message updated successfully' });
    expect(window.pendingEdits.m1).toBeUndefined();
  });
});
