/**
 * @jest-environment jsdom
 *
 * Tests for ws-vocabulary-handler.js — the frontend layer that transforms
 * ${TOKEN} occurrences using the backend-shipped vocabulary_map. Per-token
 * display mode (decision E): `decorate` keeps the literal symbol with hover +
 * click-to-reveal; `expand` replaces it with the resolved value.
 */

require('../../docker/services/ruby/public/js/monadic/ws-vocabulary-handler');

// New map shape: { TOKEN: { value, display } }.
const MAP = { SHARED: { value: '/Users/me/monadic/data', display: 'decorate' } };

function decorate(html, map = MAP) {
  const root = document.createElement('div');
  root.innerHTML = html;
  document.body.appendChild(root);
  window.WsVocabularyHandler.decorateTokens(root, map);
  return root;
}

afterEach(() => {
  document.body.innerHTML = '';
});

describe('WsVocabularyHandler.decorateTokens — decorate mode', () => {
  it('wraps ${SHARED} in a .vocab-token span with path data + title', () => {
    const root = decorate('<p>see ${SHARED}/x.txt now</p>');
    const span = root.querySelector('span.vocab-token');
    expect(span).not.toBeNull();
    expect(span.textContent).toBe('${SHARED}');
    expect(span.getAttribute('data-vocab-path')).toBe('/Users/me/monadic/data');
    expect(span.getAttribute('title')).toContain('/Users/me/monadic/data');
    // The path tail stays as plain text (only the token is wrapped).
    expect(root.textContent).toBe('see ${SHARED}/x.txt now');
  });

  it('decorates ${SHARED} INSIDE inline <code> (the LLM-backticked case)', () => {
    const root = decorate('<p>path <code>${SHARED}/a</code></p>');
    const span = root.querySelector('code span.vocab-token');
    expect(span).not.toBeNull();
    expect(span.textContent).toBe('${SHARED}');
  });

  it('does NOT decorate inside a <pre> code block', () => {
    const root = decorate('<pre><code>${SHARED}/a</code></pre>');
    expect(root.querySelector('span.vocab-token')).toBeNull();
  });

  it('leaves unknown tokens (not in the map) literal', () => {
    const root = decorate('<p>${OTHER}/x and ${SHARED}/y</p>');
    const spans = root.querySelectorAll('span.vocab-token');
    expect(spans.length).toBe(1);
    expect(spans[0].textContent).toBe('${SHARED}');
    expect(root.textContent).toContain('${OTHER}/x');
  });

  it('is idempotent — re-running does not double-wrap', () => {
    const root = decorate('<p>${SHARED}/x</p>');
    window.WsVocabularyHandler.decorateTokens(root, MAP);
    expect(root.querySelectorAll('span.vocab-token').length).toBe(1);
  });

  it('does nothing for an empty map', () => {
    const root = decorate('<p>${SHARED}/x</p>', {});
    expect(root.querySelector('span.vocab-token')).toBeNull();
  });

  it('treats a legacy plain-string map value as decorate', () => {
    const root = decorate('<p>${SHARED}/x</p>', { SHARED: '/legacy/path' });
    const span = root.querySelector('span.vocab-token');
    expect(span).not.toBeNull();
    expect(span.textContent).toBe('${SHARED}');
    expect(span.getAttribute('data-vocab-path')).toBe('/legacy/path');
    expect(root.querySelector('span.vocab-value')).toBeNull();
  });
});

describe('WsVocabularyHandler.decorateTokens — expand mode', () => {
  const EXPAND_MAP = {
    TODAY: { value: '2026-05-31', display: 'expand' },
    MODEL: { value: 'gpt-x', display: 'expand' }
  };

  it('replaces ${TODAY} with its value in a .vocab-value span titled by the token', () => {
    const root = decorate('<p>today is ${TODAY} ok</p>', EXPAND_MAP);
    const span = root.querySelector('span.vocab-value');
    expect(span).not.toBeNull();
    expect(span.textContent).toBe('2026-05-31');
    expect(span.getAttribute('title')).toBe('${TODAY}');
    // The literal symbol is gone from the text; the value replaces it.
    expect(root.textContent).toBe('today is 2026-05-31 ok');
    expect(root.querySelector('span.vocab-token')).toBeNull();
  });

  it('does not make .vocab-value clickable (no data-vocab-path)', () => {
    const root = decorate('<p>${MODEL}</p>', EXPAND_MAP);
    const span = root.querySelector('span.vocab-value');
    expect(span.getAttribute('data-vocab-path')).toBeNull();
  });

  it('mixes decorate and expand tokens in one pass', () => {
    const mixed = {
      SHARED: { value: '/data', display: 'decorate' },
      TODAY: { value: '2026-05-31', display: 'expand' }
    };
    const root = decorate('<p>${SHARED} on ${TODAY}</p>', mixed);
    expect(root.querySelector('span.vocab-token').textContent).toBe('${SHARED}');
    expect(root.querySelector('span.vocab-value').textContent).toBe('2026-05-31');
  });

  it('is idempotent — re-running does not reprocess a .vocab-value', () => {
    const root = decorate('<p>${TODAY}</p>', EXPAND_MAP);
    window.WsVocabularyHandler.decorateTokens(root, EXPAND_MAP);
    expect(root.querySelectorAll('span.vocab-value').length).toBe(1);
  });
});

describe('WsVocabularyHandler click action', () => {
  it('calls electronAPI.revealPath with the resolved path when in Electron', () => {
    const revealPath = jest.fn();
    window.electronAPI = { revealPath };
    const root = decorate('<p>${SHARED}/x</p>');
    root.querySelector('span.vocab-token').click();
    expect(revealPath).toHaveBeenCalledWith('/Users/me/monadic/data');
    delete window.electronAPI;
  });

  it('falls back to clipboard copy when no Electron bridge is present', () => {
    delete window.electronAPI;
    const writeText = jest.fn().mockResolvedValue();
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
    const root = decorate('<p>${SHARED}/x</p>');
    root.querySelector('span.vocab-token').click();
    expect(writeText).toHaveBeenCalledWith('/Users/me/monadic/data');
  });

  it('does not trigger reveal/clipboard when an expand .vocab-value is clicked', () => {
    const revealPath = jest.fn();
    window.electronAPI = { revealPath };
    const root = decorate('<p>${TODAY}</p>', { TODAY: { value: '2026-05-31', display: 'expand' } });
    root.querySelector('span.vocab-value').click();
    expect(revealPath).not.toHaveBeenCalled();
    delete window.electronAPI;
  });
});
