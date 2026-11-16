/**
 * @jest-environment jsdom
 *
 * The "Use Knowledge Base for retrieval" switch is remembered per app:
 * turning it on in one app leaves it off in the others, and coming back to
 * the app turns it on again. An app change reaches the switch through
 * applyAppCapabilityClasses (monadic.js), which every path that changes the
 * app calls; the test runs the real function.
 */

const fs = require('fs');
const path = require('path');

function loadCapabilityFunction() {
  const source = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/js/monadic.js'), 'utf8');
  const start = source.search(/function\s+applyAppCapabilityClasses\s*\(/);
  let depth = 0;
  let i = source.indexOf('{', start);
  for (; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}' && --depth === 0) break;
  }
  // eslint-disable-next-line no-new-func
  return new Function(`${source.slice(start, i + 1)}; return applyAppCapabilityClasses;`)();
}

describe('Knowledge Base retrieval switch per app', () => {
  let sent;

  function chooseApp(name) {
    document.getElementById('apps').value = name;
    window.applyAppCapabilityClasses(name);
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
    sent = [];
    window.apps = { ChatOpenAI: {}, MailComposerOpenAI: {} };
    window.applyAppCapabilityClasses = loadCapabilityFunction();
    window.safeWsSend = (body) => { sent.push(body); return { sent: true, state: 'OPEN' }; };
    require('../../docker/services/ruby/public/js/monadic/library-panel.js');
    window.libraryPanel.init();
  });

  afterEach(() => {
    delete window.apps;
    delete window.applyAppCapabilityClasses;
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
