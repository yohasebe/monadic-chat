/**
 * @jest-environment jsdom
 */
// Deleting a turn (the user's message and the reply) from the deletion
// dialog, and whether what the AI drew on whiteboards stays with it.
const path = require('path');

const js = (f) => path.join(__dirname, '../../docker/services/ruby/public/js', f);

describe('deleting messages from the dialog', () => {
  let sent;

  function card(mid, turn) {
    const el = document.createElement('div');
    el.className = 'card mt-3';
    el.id = mid;
    el.setAttribute('data-turn', String(turn));
    el.innerHTML = `<span class="card-turn-badge" data-turn="${turn}">T${turn}</span><div class="card-body">${mid}</div>`;
    return el;
  }

  beforeEach(() => {
    document.body.innerHTML = '<div id="discourse"></div>';
    const discourse = document.getElementById('discourse');
    [['u1', 1], ['a1', 1], ['u2', 2], ['a2', 2], ['u3', 3], ['a3', 3]].forEach(([mid, turn]) => discourse.appendChild(card(mid, turn)));
    sent = [];
    global.$id = (id) => document.getElementById(id);
    global.messages = ['u1', 'a1', 'u2', 'a2', 'u3', 'a3'].map((mid) => ({ mid: mid, role: mid[0] === 'u' ? 'user' : 'assistant' }));
    global.mids = new Set(global.messages.map((m) => m.mid));
    window.safeWsSend = (payload) => sent.push(payload);
    global.cleanupAllTooltips = () => {};
    jest.isolateModules(() => { require(js('monadic/cards.js')); });
    window.detachEventListeners = () => {};
    global.detachEventListeners = () => {};
  });

  test('deletes the turn: the user\'s message and the reply, the later turns numbered again once', () => {
    window.deleteTurn('a2');
    expect(sent).toEqual([{ message: 'DELETE', mid: 'u2' }, { message: 'DELETE', mid: 'a2' }]);
    expect(global.messages.map((m) => m.mid)).toEqual(['u1', 'a1', 'u3', 'a3']);
    expect([...document.querySelectorAll('#discourse .card')].map((el) => [el.id, el.getAttribute('data-turn')]))
      .toEqual([['u1', '1'], ['a1', '1'], ['u3', '2'], ['a3', '2']]);
    expect(document.querySelector('#u3 .card-turn-badge').textContent).toBe('T2');
  });

  test('asks the server to keep the AI\'s drawings only when the dialog chose so, and only for its deletes', () => {
    window.withDeleteChoice({ keepDrawn: true }, () => window.deleteTurn('u3'));
    window.deleteMessageOnly('a1', global.messages.findIndex((m) => m.mid === 'a1'));
    expect(sent).toEqual([{ message: 'DELETE', mid: 'u3', keep_drawn: true }, { message: 'DELETE', mid: 'a3', keep_drawn: true },
      { message: 'DELETE', mid: 'a1' }]);
  });
});
