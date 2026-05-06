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
    expect(span.getAttribute('title')).toContain('<<PERSON_1>>');
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

  it('skips text inside <a> hyperlinks (href text remains intact)', () => {
    root.innerHTML = '<p><a href="#">Alice</a> Alice</p>';
    highlight([{ placeholder: '<<PERSON_1>>', entity_type: 'PERSON', original: 'Alice' }]);

    expect(root.querySelectorAll('span.privacy-unmasked').length).toBe(1);
    expect(root.querySelector('a').querySelector('span.privacy-unmasked')).toBeNull();
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
