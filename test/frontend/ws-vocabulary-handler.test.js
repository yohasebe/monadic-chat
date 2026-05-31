/**
 * @jest-environment jsdom
 *
 * Tests for ws-vocabulary-handler.js — the frontend layer that decorates
 * ${TOKEN} occurrences using the backend-shipped vocabulary_map, and opens the
 * resolved path in the file explorer (Electron) or copies it (browser).
 */

require('../../docker/services/ruby/public/js/monadic/ws-vocabulary-handler');

const MAP = { SHARED: '/Users/me/monadic/data' };

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

describe('WsVocabularyHandler.decorateTokens', () => {
  it('wraps ${SHARED} in a plain text node with path data + title', () => {
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
});
