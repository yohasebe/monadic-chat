/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-privacy-handler.js — focused on the unmask-highlight layer.
 * The handler also wires registry/export modal interactions, but those are
 * indirect (depend on Bootstrap modal globals + WebSocket); the highlight
 * function is pure DOM walking and worth direct coverage because it ships
 * with Phase 1 of the Privacy Filter unmask transparency UX.
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
      <div id="privacy-indicator" class="privacy-indicator privacy-active" style="display:">
        <i class="fas fa-lock"></i> Privacy ON (3)
      </div>
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

  afterEach(() => { document.body.innerHTML = ''; });

  it('defaults to "masked" when Privacy is active in the session', () => {
    buildDialog();
    // Indicator already shows "Privacy ON (3)" so isActive() returns true.
    window.WsPrivacyHandler.resetExportDialog();
    expect(document.getElementById('privacyExportContentMasked').checked).toBe(true);
    expect(document.getElementById('privacyExportContentRestored').checked).toBe(false);
  });

  it('defaults to "restored" when Privacy is not active', () => {
    buildDialog();
    // Hide the indicator so isActive() returns false (mirrors privacy OFF state).
    const ind = document.getElementById('privacy-indicator');
    ind.style.display = 'none';
    window.WsPrivacyHandler.resetExportDialog();
    expect(document.getElementById('privacyExportContentRestored').checked).toBe(true);
    expect(document.getElementById('privacyExportContentMasked').checked).toBe(false);
  });

  it('hides the content section when Privacy is not active', () => {
    buildDialog();
    const ind = document.getElementById('privacy-indicator');
    ind.style.display = 'none';
    window.WsPrivacyHandler.resetExportDialog();
    expect(document.getElementById('privacy-export-content-section').style.display).toBe('none');
  });
});

describe('WsPrivacyHandler.handleState — auto-detected language badge', () => {
  beforeEach(() => {
    const indicator = document.createElement('div');
    indicator.id = 'privacy-indicator';
    indicator.style.display = 'none';
    document.body.appendChild(indicator);
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('renders a language badge when detection is locked', () => {
    window.WsPrivacyHandler.handleState({
      enabled: true,
      registry_count: 2,
      detection: { language: 'ja', reliable: true, locked: true, attempts: 1 }
    });

    const indicator = document.getElementById('privacy-indicator');
    expect(indicator.style.display).toBe('');
    expect(indicator.innerHTML).toMatch(/privacy-lang-badge/);
    expect(indicator.innerHTML).toMatch(/ja/);
  });

  it('omits the language badge when detection is not yet locked', () => {
    window.WsPrivacyHandler.handleState({
      enabled: true,
      registry_count: 2,
      detection: { language: null, reliable: null, locked: false, attempts: 0 }
    });

    const indicator = document.getElementById('privacy-indicator');
    expect(indicator.innerHTML).not.toMatch(/privacy-lang-badge/);
  });

  it('omits the language badge when detection is missing entirely', () => {
    window.WsPrivacyHandler.handleState({
      enabled: true,
      registry_count: 0
    });

    const indicator = document.getElementById('privacy-indicator');
    expect(indicator.innerHTML).not.toMatch(/privacy-lang-badge/);
  });
});

describe('WsPrivacyHandler.handleState — re-arm reconciliation on backend OFF', () => {
  let toggle;

  beforeEach(() => {
    const indicator = document.createElement('div');
    indicator.id = 'privacy-indicator';
    document.body.appendChild(indicator);

    toggle = document.createElement('input');
    toggle.type = 'checkbox';
    toggle.id = 'check-privacy-session';
    document.body.appendChild(toggle);

    window.safeWsSend = jest.fn();
  });

  afterEach(() => {
    document.body.innerHTML = '';
    delete window.safeWsSend;
  });

  it('re-asserts PRIVACY_TOGGLE:true when the toggle is ON but backend reports OFF', () => {
    // App-change reset path: backend pushes enabled:false while the user's
    // toggle (restored from localStorage, no change event) is still ON.
    toggle.checked = true;
    toggle.disabled = false;

    window.WsPrivacyHandler.handleState({ enabled: false, registry_count: 0 });

    expect(window.safeWsSend).toHaveBeenCalledWith({ message: 'PRIVACY_TOGGLE', enabled: true });
  });

  it('does NOT re-arm when the user deliberately turned the toggle OFF', () => {
    toggle.checked = false;
    toggle.disabled = false;

    window.WsPrivacyHandler.handleState({ enabled: false, registry_count: 0 });

    expect(window.safeWsSend).not.toHaveBeenCalled();
  });

  it('does NOT re-arm when the toggle is locked/unusable (disabled)', () => {
    // disabled covers both post-send lock and unsupported-language gating.
    toggle.checked = true;
    toggle.disabled = true;

    window.WsPrivacyHandler.handleState({ enabled: false, registry_count: 0 });

    expect(window.safeWsSend).not.toHaveBeenCalled();
  });

  it('does NOT re-arm when the backend confirms ON (no mismatch)', () => {
    toggle.checked = true;
    toggle.disabled = false;

    window.WsPrivacyHandler.handleState({ enabled: true, registry_count: 1 });

    expect(window.safeWsSend).not.toHaveBeenCalled();
  });
});
