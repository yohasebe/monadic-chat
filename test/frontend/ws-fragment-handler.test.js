/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-fragment-handler.js
 *
 * Handles streaming fragment messages: duplicate detection (sequence, index,
 * timestamp), temp-card creation, DOM text appending, and debug utilities.
 *
 * Uses real DOM elements since the source code uses vanilla JS (getElementById,
 * querySelector, appendChild, etc.).
 */

describe('WsFragmentHandler', () => {
  beforeEach(() => {
    // Real DOM setup
    document.body.innerHTML = '<div id="discourse"></div><div id="chat"></div>';

    // Reset global state
    window._lastProcessedSequence = -1;
    window._lastProcessedIndex = -1;
    window._recentFragments = {};
    window._sequenceGaps = [];
    window._skippedFragments = [];
    window._lastFragmentTime = null;
    window.debugFragments = false;
    window.__lastSkippedFragment = null;
    window.isForegroundTab = jest.fn().mockReturnValue(true);

    // Clear Jest module cache so each test gets a fresh load
    jest.resetModules();
  });

  afterEach(() => {
    delete window._lastProcessedSequence;
    delete window._lastProcessedIndex;
    delete window._recentFragments;
    delete window._sequenceGaps;
    delete window._skippedFragments;
    delete window._lastFragmentTime;
    delete window.debugFragments;
    delete window.__lastSkippedFragment;
    delete window.isForegroundTab;
    delete window.WsFragmentHandler;
    delete window.handleFragmentMessage;
    delete window.debugFragmentSummary;
    delete window.resetFragmentDebug;
  });

  function loadHandler() {
    require('../../docker/services/ruby/public/js/monadic/ws-fragment-handler');
    return window.WsFragmentHandler;
  }

  describe('handleFragmentMessage', () => {
    it('should skip fragments in background tabs', () => {
      window.isForegroundTab.mockReturnValue(false);
      const handler = loadHandler();
      const fragment = { type: 'fragment', content: 'Hello' };
      handler.handleFragmentMessage(fragment);
      expect(window.__lastSkippedFragment).toBe(fragment);
    });

    it('should skip empty fragments', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: '', sequence: 1 });
      expect(document.getElementById('temp-card')).toBeNull();
    });

    it('should skip non-fragment type messages', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'other', content: 'Hello' });
      expect(document.getElementById('temp-card')).toBeNull();
    });

    it('should skip null/undefined input', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage(null);
      handler.handleFragmentMessage(undefined);
      expect(document.getElementById('temp-card')).toBeNull();
    });

    it('should create temp-card and append text for valid fragments', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: 'Hello', sequence: 1 });
      const tc = document.getElementById('temp-card');
      expect(tc).not.toBeNull();
      expect(tc.querySelector('.card-text').textContent).toBe('Hello');
    });

    it('should append multiple fragments in sequence', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: 'Hello', sequence: 1 });
      handler.handleFragmentMessage({ type: 'fragment', content: ' World', sequence: 2 });
      const ct = document.getElementById('temp-card').querySelector('.card-text');
      expect(ct.textContent).toBe('Hello World');
    });

    it('should skip duplicate sequence numbers', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: 'Hello', sequence: 1 });
      handler.handleFragmentMessage({ type: 'fragment', content: 'Duplicate', sequence: 1 });
      expect(document.getElementById('temp-card').querySelector('.card-text').textContent).toBe('Hello');
    });

    it('should skip out-of-order (older) sequence numbers', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: 'First', sequence: 5 });
      handler.handleFragmentMessage({ type: 'fragment', content: 'Old', sequence: 3 });
      expect(document.getElementById('temp-card').querySelector('.card-text').textContent).toBe('First');
    });

    it('should handle index-based duplicate detection as fallback', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: 'Hello', index: 0 });
      handler.handleFragmentMessage({ type: 'fragment', content: 'Dup', index: 0 });
      expect(document.getElementById('temp-card').querySelector('.card-text').textContent).toBe('Hello');
    });

    it('should clear content on is_first fragment', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: 'First', sequence: 1 });
      handler.handleFragmentMessage({ type: 'fragment', content: 'Second', sequence: 2 });
      // Reset with is_first
      handler.handleFragmentMessage({ type: 'fragment', content: 'New start', sequence: 3, is_first: true });
      expect(document.getElementById('temp-card').querySelector('.card-text').textContent).toBe('New start');
    });

    it('should handle newlines by creating br elements', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: 'Line1\nLine2', sequence: 1 });
      const ct = document.getElementById('temp-card').querySelector('.card-text');
      expect(ct.querySelectorAll('br').length).toBe(1);
      expect(ct.textContent).toBe('Line1Line2');
    });

    it('should reset tracking on final fragment', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: 'Data', sequence: 5 });
      handler.handleFragmentMessage({ type: 'fragment', content: 'End', sequence: 6, final: true });
      expect(window._lastProcessedSequence).toBe(-1);
      expect(window._lastProcessedIndex).toBe(-1);
    });

    it('should append temp-card inside #discourse', () => {
      const handler = loadHandler();
      handler.handleFragmentMessage({ type: 'fragment', content: 'Hello', sequence: 1 });
      const discourseEl = document.getElementById('discourse');
      expect(discourseEl.querySelector('#temp-card')).not.toBeNull();
    });
  });

  describe('debugFragmentSummary', () => {
    it('should be a function', () => {
      const handler = loadHandler();
      expect(typeof handler.debugFragmentSummary).toBe('function');
    });

    it('should not throw when debug is enabled', () => {
      const handler = loadHandler();
      window.debugFragments = true;
      window._lastProcessedSequence = 5;
      window._lastProcessedIndex = 3;
      expect(() => handler.debugFragmentSummary()).not.toThrow();
    });
  });

  describe('resetFragmentDebug', () => {
    it('should reset all tracking state', () => {
      const handler = loadHandler();
      window._lastProcessedSequence = 10;
      window._lastProcessedIndex = 5;
      window._sequenceGaps = [{ expected: 3, received: 5, time: 100 }];
      window._skippedFragments = [{ sequence: 2, content: 'x', time: 100 }];
      window._lastFragmentTime = 12345;

      handler.resetFragmentDebug();

      expect(window._lastProcessedSequence).toBe(-1);
      expect(window._lastProcessedIndex).toBe(-1);
      expect(window._sequenceGaps).toEqual([]);
      expect(window._skippedFragments).toEqual([]);
      expect(window._lastFragmentTime).toBeNull();
    });
  });

  describe('window exports', () => {
    it('should export functions to window and WsFragmentHandler', () => {
      loadHandler();
      expect(typeof window.handleFragmentMessage).toBe('function');
      expect(typeof window.WsFragmentHandler).toBe('object');
      expect(typeof window.WsFragmentHandler.handleFragmentMessage).toBe('function');
      expect(typeof window.WsFragmentHandler.debugFragmentSummary).toBe('function');
      expect(typeof window.WsFragmentHandler.resetFragmentDebug).toBe('function');
    });
  });
});
