/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-privacy-handler.js — focused on the unmask-highlight layer.
 * The handler also wires the export dialog, which is indirect (it depends
 * on Bootstrap modal globals + WebSocket); the highlight function is pure
 * DOM walking.
 */

require('../../docker/services/ruby/public/js/monadic/ws-privacy-handler');

describe('WsPrivacyHandler.highlightUnmaskedSpans', () => {
  let root;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  function highlight(spans) {
    window.WsPrivacyHandler.highlightUnmaskedSpans(root, spans);
  }

  it('wraps a single occurrence of an original value with class and metadata', () => {
    root.innerHTML = '<p>Hello Alice and goodbye.</p>';
    highlight([{ placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: 'Alice' }]);

    const span = root.querySelector('span.privacy-unmasked');
    expect(span).not.toBeNull();
    expect(span.textContent).toBe('Alice');
    expect(span.getAttribute('data-entity-type')).toBe('PERSON');
    expect(span.getAttribute('data-placeholder')).toBe('<<PERSON_1>>');
    expect(span.getAttribute('data-color')).toMatch(/^[0-7]$/);
    expect(span.getAttribute('title')).toContain('<<PERSON_1>>');
  });

  it('assigns the same data-color to every occurrence of the same placeholder', () => {
    // Same placeholder must produce the same color slot in every card —
    // hash(placeholder) % palette_size is deterministic.
    root.innerHTML = '<div class="card"><p>Hi Alice.</p></div>'
      + '<div class="card"><p>Hello Alice, again Alice.</p></div>';
    highlight([{ placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: 'Alice' }]);

    const colors = Array.from(root.querySelectorAll('span.privacy-unmasked'))
      .map(s => s.getAttribute('data-color'));
    expect(colors.length).toBeGreaterThanOrEqual(3);
    expect(new Set(colors).size).toBe(1); // all the same
  });

  it('assigns different data-color slots to different placeholders (when hashes differ)', () => {
    root.innerHTML = '<p>Alice met Bob.</p>';
    highlight([
      { placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: 'Alice' },
      { placeholder: '<<PERSON_2>>', entity_type: 'PERSON', original: 'Bob' }
    ]);
    const aliceSpan = Array.from(root.querySelectorAll('span.privacy-unmasked'))
      .find(s => s.textContent === 'Alice');
    const bobSpan = Array.from(root.querySelectorAll('span.privacy-unmasked'))
      .find(s => s.textContent === 'Bob');
    expect(aliceSpan).not.toBeNull();
    expect(bobSpan).not.toBeNull();
    expect(aliceSpan.getAttribute('data-color')).not.toBe(bobSpan.getAttribute('data-color'));
  });

  it('wraps every occurrence inside a single text node', () => {
    root.innerHTML = '<p>Alice met Alice.</p>';
    highlight([{ placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: 'Alice' }]);

    const spans = root.querySelectorAll('span.privacy-unmasked');
    expect(spans.length).toBe(2);
    spans.forEach(s => expect(s.textContent).toBe('Alice'));
  });

  it('skips text inside <code> and <pre> blocks', () => {
    root.innerHTML = '<p>Alice <code>Alice</code> Alice</p>';
    highlight([{ placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: 'Alice' }]);

    expect(root.querySelectorAll('span.privacy-unmasked').length).toBe(2);
    expect(root.querySelector('code').querySelector('span.privacy-unmasked')).toBeNull();
  });

  it('highlights restored PII inside <a> hyperlinks while keeping the href intact', () => {
    // Markdown auto-links restored emails/URLs into <a>; the tracked value must
    // still be highlighted. The link itself (href + clickability) is untouched
    // because only the text node inside the anchor is wrapped.
    root.innerHTML = '<p><a href="mailto:alice@example.com">alice@example.com</a> and again alice@example.com</p>';
    highlight([{ placeholder: '<<EMAIL_ADDRESS_1>>', entity_type: 'EMAIL_ADDRESS', original: 'alice@example.com' }]);

    const anchor = root.querySelector('a');
    expect(anchor.getAttribute('href')).toBe('mailto:alice@example.com');
    // Both the linkified occurrence and the plain-text one are wrapped.
    expect(root.querySelectorAll('span.privacy-unmasked').length).toBe(2);
    expect(anchor.querySelector('span.privacy-unmasked')).not.toBeNull();
    expect(anchor.querySelector('span.privacy-unmasked').textContent).toBe('alice@example.com');
  });

  it('processes longer originals first so multi-word values are not pre-empted', () => {
    root.innerHTML = '<p>Alice Smith met Alice.</p>';
    highlight([
      // Deliberately list short value first; the handler must sort by length desc.
      { placeholder: '<<PERSON_2>>', entity_type: 'PERSON', original: 'Alice' },
      { placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: 'Alice Smith' }
    ]);

    const spans = root.querySelectorAll('span.privacy-unmasked');
    expect(spans.length).toBe(2);
    expect(Array.from(spans).map(s => s.textContent)).toEqual(['Alice Smith', 'Alice']);
  });

  it('does not double-wrap text already inside privacy-unmasked', () => {
    root.innerHTML = '<p><span class="privacy-unmasked">Alice</span> said hi to Alice.</p>';
    highlight([{ placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: 'Alice' }]);

    expect(root.querySelectorAll('span.privacy-unmasked').length).toBe(2);
    // Original wrapped span stays untouched (no nested span inside it).
    const original = root.querySelector('p > span.privacy-unmasked');
    expect(original.querySelector('span.privacy-unmasked')).toBeNull();
  });

  it('is a no-op when spans is empty, null, or root is missing', () => {
    root.innerHTML = '<p>Hello Alice.</p>';
    expect(() => highlight([])).not.toThrow();
    expect(() => highlight(null)).not.toThrow();
    expect(() => window.WsPrivacyHandler.highlightUnmaskedSpans(null, [{}])).not.toThrow();
    expect(root.querySelectorAll('span.privacy-unmasked').length).toBe(0);
  });

  it('matches CJK substrings without word boundaries', () => {
    root.innerHTML = '<p>本日は田中太郎様にお会いしました。田中太郎は…</p>';
    highlight([{ placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: '田中太郎' }]);

    const spans = root.querySelectorAll('span.privacy-unmasked');
    expect(spans.length).toBe(2);
    spans.forEach(s => expect(s.textContent).toBe('田中太郎'));
  });
});

describe('WsPrivacyHandler.resetExportDialog — content default', () => {
  function buildDialog() {
    document.body.innerHTML = `
      <input type="checkbox" id="export-encrypt-toggle" />
      <input type="radio" name="privacyExportContent" id="privacyExportContentRestored" value="restored" checked />
      <input type="radio" name="privacyExportContent" id="privacyExportContentMasked" value="masked" />
      <input type="text" id="privacy-export-passphrase" />
      <input type="text" id="privacy-export-passphrase-confirm" />
      <div id="privacy-export-content-section" style="display:none;"></div>
      <div id="privacy-export-status"></div>
      <div id="privacy-export-pass-section"></div>
      <div id="privacy-export-restored-warning"></div>
      <button id="privacy-export-continue"></button>
      <div class="privacy-strength-bar"></div>
      <div id="privacy-strength-label"></div>
    `;
  }

  function chatHidesWords(hides) {
    window.WordTable = { hidesWords: () => hides };
  }

  afterEach(() => { document.body.innerHTML = ''; delete window.WordTable; });

  it('defaults to "masked" when the chat hides words', () => {
    buildDialog();
    chatHidesWords(true);
    window.WsPrivacyHandler.resetExportDialog();
    expect(document.getElementById('privacyExportContentMasked').checked).toBe(true);
    expect(document.getElementById('privacyExportContentRestored').checked).toBe(false);
  });

  it('defaults to "restored" when the chat hides no words', () => {
    buildDialog();
    chatHidesWords(false);
    window.WsPrivacyHandler.resetExportDialog();
    expect(document.getElementById('privacyExportContentRestored').checked).toBe(true);
    expect(document.getElementById('privacyExportContentMasked').checked).toBe(false);
  });

  describe('while the dialog is open', () => {
    function openDialog(chat) {
      buildDialog();
      const modal = document.createElement('div');
      modal.id = 'privacyExportModal';
      modal.className = 'show';
      document.body.appendChild(modal);
      window.WordTable = { hidesWords: () => false, chat: () => chat };
      window.WsPrivacyHandler.resetExportDialog();
    }
    const tableNow = (hides, chat) => {
      window.WordTable = { hidesWords: () => hides, chat: () => chat };
      document.dispatchEvent(new CustomEvent('wordtable:changed'));
    };
    const byId = (id) => document.getElementById(id);

    it('offers "masked" when the table arrives after it was opened', () => {
      openDialog(null);
      tableNow(true, 'chat-1');
      expect(byId('privacyExportContentMasked').checked).toBe(true);
      expect(byId('privacy-export-content-section').style.display).toBe('');
    });

    it('keeps what the user picked when the words change', () => {
      openDialog('chat-1');
      tableNow(true, 'chat-1');
      byId('privacyExportContentRestored').checked = true;
      byId('privacyExportContentRestored').dispatchEvent(new Event('change', { bubbles: true }));
      tableNow(true, 'chat-1');
      expect(byId('privacyExportContentRestored').checked).toBe(true);
    });

    it('does not keep "masked" when no word is hidden any more', () => {
      openDialog('chat-1');
      tableNow(true, 'chat-1');
      byId('privacyExportContentMasked').dispatchEvent(new Event('change', { bubbles: true }));
      tableNow(false, 'chat-1');
      expect(byId('privacyExportContentRestored').checked).toBe(true);
      expect(byId('privacy-export-content-section').style.display).toBe('none');
    });

    it('starts over for another chat, whatever was picked', () => {
      openDialog('chat-1');
      tableNow(true, 'chat-1');
      byId('privacyExportContentRestored').checked = true;
      byId('privacyExportContentRestored').dispatchEvent(new Event('change', { bubbles: true }));
      byId('privacy-export-passphrase').value = 'typed for the other chat';
      tableNow(true, 'chat-2');
      expect(byId('privacyExportContentMasked').checked).toBe(true);
      expect(byId('privacy-export-passphrase').value).toBe('');
    });
  });

  it('hides the content section when the chat hides no words', () => {
    buildDialog();
    chatHidesWords(false);
    window.WsPrivacyHandler.resetExportDialog();
    expect(document.getElementById('privacy-export-content-section').style.display).toBe('none');
  });
});
