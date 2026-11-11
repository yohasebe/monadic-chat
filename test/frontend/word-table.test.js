/**
 * @jest-environment jsdom
 */
// The panel where the user decides what a chat hides.
describe('word table', () => {
  let wt;
  let sent;

  const table = (over) => Object.assign({ chat: 'c1', marked: false, active: [], kept: [] }, over);
  const lastSent = () => sent[sent.length - 1];

  beforeEach(() => {
    jest.resetModules();
    sent = [];
    document.body.innerHTML = `
      <button id="anonymize"></button><button id="word-table-status" style="display:none"></button>
      <div id="word-table-panel" style="display:none">
        <button id="word-table-close"></button>
        <div id="word-table-preview"></div>
        <select id="word-table-type"></select>
        <button id="word-table-hide-selection"></button>
        <div id="word-table-list"></div><div id="word-table-kept"></div>
        <div id="word-table-error" style="display:none"></div>
        <button id="word-table-apply"></button>
      </div>
      <textarea id="message"></textarea><button id="voice"></button><button id="image-file"></button>`;
    global.$id = (id) => document.getElementById(id);
    global.$on = (el, event, fn) => { if (el) el.addEventListener(event, fn); };
    global.setAlert = jest.fn();
    window.safeWsSend = (payload) => { sent.push(payload); return { sent: true }; };
    wt = require('../../docker/services/ruby/public/js/monadic/word-table.js');
    wt.handleTable(table());
  });

  const found = (candidates) => {
    document.getElementById('anonymize').click();
    wt.handleFound({ request: lastSent().request, chat: 'c1', candidates });
  };

  it('splits a text by the words, taking the longest where several start together', () => {
    expect(wt.splitByWords('Ada Lovelace and Ada.', ['Ada', 'Ada Lovelace'])).toEqual([
      { text: 'Ada Lovelace', word: 'Ada Lovelace' }, { text: ' and ' }, { text: 'Ada', word: 'Ada' }, { text: '.' }
    ]);
  });

  it('matches words literally', () => {
    expect(wt.splitByWords('a.c abc', ['a.c'])).toEqual([{ text: 'a.c', word: 'a.c' }, { text: ' abc' }]);
  });

  it('asks the server about the message and shows what it found, hidden in the text', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);

    expect(sent[0]).toMatchObject({ message: 'WORDS_FIND', text: 'Hi Ada' });
    expect(document.getElementById('word-table-panel').style.display).toBe('');
    expect(document.querySelector('#word-table-preview mark').textContent).toContain('Ada');
  });

  it('does not show a word as text in markup', () => {
    document.getElementById('message').value = 'x <img src=q> y';
    found([{ word: '<img src=q>', type: 'PERSON' }]);

    expect(document.querySelector('#word-table-preview img')).toBeNull();
    expect(document.querySelector('#word-table-list img')).toBeNull();
  });

  it('ignores an answer to an older request', () => {
    document.getElementById('message').value = 'Hi Ada';
    document.getElementById('anonymize').click();
    const old = lastSent().request;
    document.getElementById('anonymize').click();
    wt.handleFound({ request: old, chat: 'c1', candidates: [{ word: 'Ada', type: 'PERSON' }] });

    expect(document.querySelector('#word-table-list .word-table-word')).toBeNull();
  });

  it('sends the words decided, those taken off as words to leave', () => {
    document.getElementById('message').value = 'Ada and Bob';
    found([{ word: 'Ada', type: 'PERSON' }, { word: 'Bob', type: 'PERSON' }]);
    document.querySelector('#word-table-list .word-table-off').click();

    document.getElementById('word-table-apply').click();

    expect(lastSent()).toMatchObject({ message: 'WORDS_CHANGE', chat: 'c1', hide: [{ word: 'Bob', type: 'PERSON' }], keep: ['Ada'] });
  });

  it('holds a message until what was decided is taken, and sends it then', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);
    const resend = jest.fn();

    expect(wt.holdSend(resend)).toBe(true);
    expect(resend).not.toHaveBeenCalled();
    wt.handleChanged({ request: lastSent().request, success: true });

    expect(resend).toHaveBeenCalledTimes(1);
    expect(wt.holdSend(resend)).toBe(false);
  });

  it('does not send the message when the words could not be taken', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);
    const resend = jest.fn();
    wt.holdSend(resend);

    wt.handleChanged({ request: lastSent().request, success: false, error: 'words_refused' });

    expect(resend).not.toHaveBeenCalled();
    expect(document.getElementById('word-table-error').style.display).toBe('');
    expect(wt.holdSend(resend)).toBe(true);
  });

  // What the Send button does: asks, and goes out when nothing holds it.
  const pressSend = () => {
    const out = jest.fn();
    const press = () => { if (!wt.holdSend(press)) out(); };
    press();
    return out;
  };
  const changes = () => sent.filter((m) => m.message === 'WORDS_CHANGE');
  const answer = (request, over) => wt.handleChanged(Object.assign({ request, success: true }, over));

  it('holds a message while names are being looked for, and does not send it by itself', () => {
    const message = document.getElementById('message');
    message.value = 'Hi Ada';
    document.getElementById('anonymize').click();
    const out = pressSend();

    expect(out).not.toHaveBeenCalled();
    expect(document.getElementById('word-table-error').textContent).toBe('stillFinding');

    wt.handleFound({ request: lastSent().request, chat: 'c1', candidates: [{ word: 'Ada', type: 'PERSON' }] });
    expect(out).not.toHaveBeenCalled();
    expect(document.querySelector('#word-table-list .word-table-word')).not.toBeNull();
  });

  it('holds a message after a search that failed, until the panel is closed', () => {
    document.getElementById('message').value = 'Hi Ada';
    document.getElementById('anonymize').click();
    wt.handleFound({ request: lastSent().request, chat: 'c1', error: 'privacy_container_starting' });

    expect(pressSend()).not.toHaveBeenCalled();
    expect(document.getElementById('word-table-error').textContent).toBe('closeToSend');

    document.getElementById('word-table-close').click();
    expect(pressSend()).toHaveBeenCalledTimes(1);
  });

  it('gives up a search when the panel is closed', () => {
    document.getElementById('message').value = 'Hi Ada';
    document.getElementById('anonymize').click();
    const request = lastSent().request;
    document.getElementById('word-table-close').click();

    wt.handleFound({ request, chat: 'c1', candidates: [{ word: 'Ada', type: 'PERSON' }] });

    expect(pressSend()).toHaveBeenCalledTimes(1);
  });

  it('takes words added while a change is on its way before the message goes', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);
    const out = pressSend();
    const first = lastSent().request;

    document.getElementById('message').value = 'Ada and Bob';
    document.getElementById('anonymize').click();
    wt.handleFound({ request: lastSent().request, chat: 'c1', candidates: [{ word: 'Bob', type: 'PERSON' }] });
    answer(first);

    expect(out).not.toHaveBeenCalled();
    const second = lastSent();
    expect(second).toMatchObject({ message: 'WORDS_CHANGE', hide: [{ word: 'Bob', type: 'PERSON' }] });
    answer(second.request);
    expect(out).toHaveBeenCalledTimes(1);
  });

  it('keeps a type changed while the word is on its way undecided', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);
    document.getElementById('word-table-apply').click();
    const request = lastSent().request;
    const select = document.querySelector('#word-table-list .word-table-type-select');
    select.value = 'LOCATION';
    select.dispatchEvent(new Event('change'));

    answer(request);

    expect(wt._state.drafts).toEqual([{ word: 'Ada', type: 'LOCATION' }]);
  });

  it('sends changes one at a time and keeps the held message through them', () => {
    wt.handleTable(table({ marked: true, active: [{ word: 'Ada', type: 'PERSON' }, { word: 'Bob', type: 'PERSON' }] }));
    document.getElementById('word-table-status').click();
    document.querySelector('#word-table-list .word-table-off').click();
    const out = pressSend();
    document.querySelector('#word-table-list .word-table-off').click();

    expect(changes()).toHaveLength(1);
    answer(changes()[0].request);
    expect(changes()).toHaveLength(2);
    expect(out).not.toHaveBeenCalled();
    answer(changes()[1].request);
    expect(out).toHaveBeenCalledTimes(1);
  });

  it('sends a message once however often Send is pressed while it waits', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);
    const resend = jest.fn();
    wt.holdSend(resend);
    wt.holdSend(resend);

    expect(changes()).toHaveLength(1);
    answer(lastSent().request);
    expect(resend).toHaveBeenCalledTimes(1);
  });

  it('shows why a message did not go when the panel was closed', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);
    document.getElementById('word-table-close').click();
    wt.holdSend(jest.fn());

    answer(lastSent().request, { success: false, error: 'words_refused' });

    expect(document.getElementById('word-table-panel').style.display).toBe('');
    expect(document.getElementById('word-table-error').style.display).toBe('');
  });

  it('does not wait for an answer when the connection is lost or the change cannot be sent', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);
    const resend = jest.fn();
    wt.holdSend(resend);
    wt.connectionLost();

    expect(wt._state.waiting).toBeNull();
    expect(resend).not.toHaveBeenCalled();
    expect(wt._state.drafts).toHaveLength(1);

    window.safeWsSend = () => ({ sent: false });
    wt.holdSend(resend);
    expect(wt._state.waiting).toBeNull();
    expect(resend).not.toHaveBeenCalled();
  });

  it('treats a search lost with the connection as a failed one', () => {
    document.getElementById('message').value = 'Hi Ada';
    document.getElementById('anonymize').click();
    wt.connectionLost();

    expect(pressSend()).not.toHaveBeenCalled();
    expect(document.getElementById('word-table-error').textContent).toBe('closeToSend');
  });

  it('treats a search that could not be asked for as a failed one, also after the table is shown again', () => {
    document.getElementById('message').value = 'Hi Ada';
    const send = window.safeWsSend;
    window.safeWsSend = () => ({ sent: false });
    document.getElementById('anonymize').click();
    window.safeWsSend = send;

    wt.handleTable(table());
    expect(pressSend()).not.toHaveBeenCalled();
    expect(document.getElementById('word-table-error').textContent).toBe('closeToSend');
  });

  it.each([
    ['running', undefined],
    ['failed', { error: 'words_find_failed' }]
  ])('does not give up a search that is %s when asked to hide the words', (_state, result) => {
    document.getElementById('message').value = 'Hi Ada';
    document.getElementById('anonymize').click();
    if (result) wt.handleFound(Object.assign({ request: lastSent().request, chat: 'c1' }, result));

    document.getElementById('word-table-apply').click();

    expect(document.getElementById('word-table-panel').style.display).toBe('');
    expect(pressSend()).not.toHaveBeenCalled();
  });

  it('keeps the panel open when words are taken after a search that failed', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);
    document.getElementById('anonymize').click();
    wt.handleFound({ request: lastSent().request, chat: 'c1', error: 'words_find_failed' });
    document.getElementById('word-table-apply').click();

    answer(lastSent().request);

    expect(document.getElementById('word-table-panel').style.display).toBe('');
    expect(pressSend()).not.toHaveBeenCalled();
  });

  it('keeps the panel open when words are taken while a search runs', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);
    document.getElementById('anonymize').click();
    document.getElementById('word-table-apply').click();

    answer(lastSent().request);

    expect(document.getElementById('word-table-panel').style.display).toBe('');
  });

  it('holds reading aloud until the words shown are decided, without deciding them', () => {
    expect(wt.holdSpeech()).toBe(false);
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);

    expect(wt.holdSpeech()).toBe(true);
    expect(changes()).toHaveLength(0);
    expect(document.getElementById('word-table-error').textContent).toBe('decideFirst');

    document.getElementById('word-table-apply').click();
    expect(wt.holdSpeech()).toBe(true);
    answer(lastSent().request);
    expect(wt.holdSpeech()).toBe(false);
  });

  it('holds reading aloud during a search', () => {
    document.getElementById('message').value = 'Hi Ada';
    document.getElementById('anonymize').click();

    expect(wt.holdSpeech()).toBe(true);
    expect(document.getElementById('word-table-error').textContent).toBe('stillFinding');
  });

  describe('the play button of a card', () => {
    const pressPlay = (held) => {
      const vm = require('vm');
      const fs = require('fs');
      const path = require('path');
      document.body.insertAdjacentHTML('beforeend', `
        <div class="card" id="card1"><div class="card-text">Hi</div><button class="func-play"></button></div>
        <div id="monadic-spinner" style="display:none"><span></span></div>`);
      const send = jest.fn();
      const stop = jest.fn();
      const context = {
        window: {
          WordTable: { holdSpeech: () => held },
          TtsProvider: { providerOf: () => 'openai' },
          safeWsSend: send
        },
        document, console,
        $id: (id) => document.getElementById(id),
        $show: (el) => { el.style.display = ''; },
        ttsStop: stop,
        cleanupCardTextListeners: jest.fn(), cleanupAllTooltips: jest.fn(),
        removeCode: (text) => text, removeMarkdown: (text) => text, removeEmojis: (text) => text,
        setTimeout: (fn) => fn()
      };
      const source = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/js/monadic/cards.js'), 'utf8');
      vm.runInNewContext(source, context);
      context.attachEventListeners(document.getElementById('card1'));
      document.querySelector('.func-play').click();
      return { send, stop };
    };

    it('starts nothing while it is held', () => {
      const { send, stop } = pressPlay(true);

      expect(send).not.toHaveBeenCalled();
      expect(stop).not.toHaveBeenCalled();
      expect(document.getElementById('monadic-spinner').style.display).toBe('none');
    });

    it('reads aloud when it is not held', () => {
      const { send } = pressPlay(false);

      expect(send).toHaveBeenCalledWith(expect.objectContaining({ message: 'PLAY_TTS' }));
      expect(document.getElementById('monadic-spinner').style.display).toBe('');
    });
  });

  it.each([
    ['AI User', 'public/js/monadic.js', 'aiUserButton', 'message: "AI_USER_QUERY"'],
    ['Verify', 'public/js/monadic/cards.js', 'verifyBtn', 'message: "VERIFY_CONFIDENCE"']
  ])('holds %s like a message', (_name, file, button, request) => {
    const source = require('fs').readFileSync(require('path').join(__dirname, '../../docker/services/ruby', file), 'utf8');
    const hold = source.indexOf('holdSend(() => { ' + button + '.click(); })');

    expect(hold).toBeGreaterThan(-1);
    expect(source.indexOf(request, hold)).toBeGreaterThan(hold);
  });

  it('holds nothing when nothing is undecided', () => {
    expect(wt.holdSend(jest.fn())).toBe(false);
  });

  it('drops what was undecided when the tab is in another chat', () => {
    document.getElementById('message').value = 'Hi Ada';
    found([{ word: 'Ada', type: 'PERSON' }]);

    wt.handleTable(table({ chat: 'c2' }));

    expect(wt.holdSend(jest.fn())).toBe(false);
    expect(document.getElementById('word-table-panel').style.display).toBe('none');
  });

  it('ignores what was found for another chat', () => {
    document.getElementById('message').value = 'Hi Ada';
    document.getElementById('anonymize').click();
    wt.handleFound({ request: lastSent().request, chat: 'c2', candidates: [{ word: 'Ada', type: 'PERSON' }] });

    expect(wt.holdSend(jest.fn())).toBe(false);
  });

  it('takes a hidden word off at once', () => {
    wt.handleTable(table({ marked: true, active: [{ word: 'Ada', type: 'PERSON' }] }));
    document.getElementById('word-table-status').click();
    document.querySelector('#word-table-list .word-table-off').click();

    expect(lastSent()).toMatchObject({ message: 'WORDS_CHANGE', keep: ['Ada'] });
  });

  it('shows how many words are hidden, and when the table is lost', () => {
    const status = document.getElementById('word-table-status');
    wt.handleTable(table({ marked: true, active: [{ word: 'Ada', type: 'PERSON' }] }));
    expect(status.style.display).toBe('');
    expect(status.textContent).toContain('1');

    wt.handleTable(table({ marked: true, unavailable: true }));
    expect(status.classList.contains('word-table-unavailable')).toBe(true);
  });

  it('shows the words a file of an earlier version hides', () => {
    wt.handleTable(table({ marked: true, active: [{ word: 'Ada', type: 'PERSON' }] }));

    wt.noticeOlderFile(1);

    expect(document.getElementById('word-table-panel').style.display).toBe('');
    expect(document.querySelector('#word-table-list .word-table-word')).not.toBeNull();
    expect(document.getElementById('word-table-error').textContent).toContain('1');
  });

  it('keeps the words of an imported file shown when the table comes again', () => {
    wt.handleTable(table({ chat: 'c2', marked: true, active: [{ word: 'Ada', type: 'PERSON' }] }));
    wt.noticeOlderFile(1);

    wt.handleTable(table({ chat: 'c2', marked: true, active: [{ word: 'Ada', type: 'PERSON' }] }));

    expect(document.getElementById('word-table-panel').style.display).toBe('');
  });

  it('says how to get a lost table back when the panel opens', () => {
    wt.handleTable(table({ marked: true, unavailable: true }));

    document.getElementById('word-table-status').click();

    const error = document.getElementById('word-table-error');
    expect(error.style.display).toBe('');
    expect(error.textContent).toBe('table_unavailable');
  });

  it('says once for a chat that images and voice are not hidden', () => {
    document.getElementById('voice').click();
    expect(global.setAlert).not.toHaveBeenCalled();

    wt.handleTable(table({ marked: true }));
    document.getElementById('voice').click();
    document.getElementById('image-file').click();
    expect(global.setAlert).toHaveBeenCalledTimes(1);

    wt.handleTable(table({ chat: 'c2', marked: true }));
    document.getElementById('image-file').click();
    expect(global.setAlert).toHaveBeenCalledTimes(2);
  });

  it('refuses a selection that cannot be a word', () => {
    expect(wt.selectionProblem('  ')).toBe('selectFirst');
    expect(wt.selectionProblem('a\nb')).toBe('oneLine');
    expect(wt.selectionProblem('a<<b')).toBe('cannotHide');
    expect(wt.selectionProblem('Ada')).toBeNull();
  });
});
