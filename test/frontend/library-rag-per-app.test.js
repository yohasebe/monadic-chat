/**
 * @jest-environment jsdom
 *
 * The "Use Knowledge Base for retrieval" switch is remembered per app:
 * turning it on in one app leaves it off in the others, and coming back to
 * the app turns it on again.
 */

describe('Knowledge Base retrieval switch per app', () => {
  let handlers;
  let sent;

  function chooseApp(name) {
    document.getElementById('apps').value = name;
    (handlers['app:changed'] || []).forEach((fn) => fn());
  }

  function toggle() {
    return document.getElementById('library-rag-toggle');
  }

  function flip(on) {
    toggle().checked = on;
    toggle().onchange();
  }

  beforeEach(() => {
    jest.resetModules();
    window.localStorage.clear();
    document.body.innerHTML = `
      <select id="apps">
        <option value="ChatOpenAI">Chat</option>
        <option value="MailComposerOpenAI">Mail Composer</option>
      </select>
      <input type="checkbox" id="library-rag-toggle">`;
    document.getElementById('apps').value = 'ChatOpenAI';
    handlers = {};
    sent = [];
    window.SessionState = {
      on: (event, fn) => { (handlers[event] = handlers[event] || []).push(fn); }
    };
    window.safeWsSend = (body) => { sent.push(body); return { sent: true, state: 'OPEN' }; };
    require('../../docker/services/ruby/public/js/monadic/library-panel.js');
    window.libraryPanel.init();
  });

  afterEach(() => {
    delete window.SessionState;
    delete window.safeWsSend;
    delete window.libraryPanel;
  });

  const ragMessages = () => sent.filter((m) => m.message === 'LIBRARY_RAG_TOGGLE').map((m) => m.contents.enabled);

  it('starts off in an app it was never turned on in', () => {
    expect(toggle().checked).toBe(false);
    expect(ragMessages()).toEqual([]);
  });

  it('keeps the switch of one app out of another', () => {
    flip(true);
    chooseApp('MailComposerOpenAI');
    expect(toggle().checked).toBe(false);
    chooseApp('ChatOpenAI');
    expect(toggle().checked).toBe(true);
    expect(ragMessages()).toEqual([true, false, true]);
  });

  it('forgets an app when the switch is turned off there', () => {
    flip(true);
    flip(false);
    chooseApp('MailComposerOpenAI');
    chooseApp('ChatOpenAI');
    expect(toggle().checked).toBe(false);
  });

  it('applies the remembered state when the page opens on that app', () => {
    flip(true);
    jest.resetModules();
    sent = [];
    toggle().checked = false;
    require('../../docker/services/ruby/public/js/monadic/library-panel.js');
    window.libraryPanel.init();
    expect(toggle().checked).toBe(true);
    expect(ragMessages()).toEqual([true]);
  });
});
