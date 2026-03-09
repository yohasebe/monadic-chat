/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-fragment-handler.js
 *
 * Handles streaming fragment messages: duplicate detection (sequence, index,
 * timestamp), temp-card creation, DOM text appending, and debug utilities.
 *
 * Uses a hybrid jQuery mock that returns real DOM elements at [0]
 * because handleFragmentMessage calls tempText[0].appendChild().
 */

// Real DOM container for #discourse and #temp-card
let discourseEl;
let tempCardEl;
let cardTextEl;

function createRealTempCard() {
  tempCardEl = document.createElement('div');
  tempCardEl.id = 'temp-card';
  tempCardEl.className = 'card mt-3 streaming-card';
  tempCardEl.innerHTML = `
    <div class="card-header p-2 ps-3 d-flex justify-content-between align-items-center">
      <div class="fs-5 card-title mb-0">
        <span><i class="fas fa-robot" style="color: #DC4C64;"></i></span>
        <span class="fw-bold fs-6" style="color: #DC4C64;">Assistant</span>
      </div>
    </div>
    <div class="card-body role-assistant">
      <div class="card-text"></div>
    </div>
  `;
  discourseEl.appendChild(tempCardEl);
  cardTextEl = tempCardEl.querySelector('.card-text');
  return tempCardEl;
}

// jQuery-like wrapper for real DOM elements
function jqWrap(el) {
  if (!el) {
    return {
      length: 0, 0: undefined,
      hide: jest.fn().mockReturnThis(),
      show: jest.fn().mockReturnThis(),
      is: jest.fn().mockReturnValue(false),
      css: jest.fn().mockReturnValue(''),
      html: jest.fn().mockReturnValue(''),
      text: jest.fn().mockReturnValue(''),
      empty: jest.fn().mockReturnThis(),
      append: jest.fn().mockReturnThis(),
      detach: jest.fn().mockReturnThis(),
      find: jest.fn().mockImplementation(() => jqWrap(null))
    };
  }
  const obj = {
    length: 1,
    0: el,
    hide: jest.fn().mockImplementation(() => { el.style.display = 'none'; return obj; }),
    show: jest.fn().mockImplementation(() => { el.style.display = ''; return obj; }),
    is: jest.fn().mockImplementation((sel) => {
      if (sel === ':visible') return el.style.display !== 'none';
      return false;
    }),
    css: jest.fn().mockImplementation((prop) => {
      if (prop === 'display') return el.style.display || '';
      return '';
    }),
    html: jest.fn().mockImplementation((val) => {
      if (val === undefined) return el.innerHTML;
      el.innerHTML = val;
      return obj;
    }),
    text: jest.fn().mockImplementation((val) => {
      if (val === undefined) return el.textContent;
      el.textContent = val;
      return obj;
    }),
    empty: jest.fn().mockImplementation(() => { el.innerHTML = ''; return obj; }),
    append: jest.fn().mockImplementation((child) => {
      if (child && child[0]) el.appendChild(child[0]);
      else if (child instanceof HTMLElement) el.appendChild(child);
      else if (typeof child === 'string') el.insertAdjacentHTML('beforeend', child);
      return obj;
    }),
    detach: jest.fn().mockImplementation(() => {
      if (el.parentNode) el.parentNode.removeChild(el);
      return obj;
    }),
    find: jest.fn().mockImplementation((sel) => {
      const found = el.querySelector(sel);
      return jqWrap(found);
    })
  };
  return obj;
}

describe('WsFragmentHandler', () => {
  beforeEach(() => {
    // Real DOM setup
    document.body.innerHTML = '<div id="discourse"></div><div id="chat"></div>';
    discourseEl = document.getElementById('discourse');
    tempCardEl = null;
    cardTextEl = null;

    // jQuery mock that routes selectors to real DOM
    global.$ = jest.fn().mockImplementation((selector) => {
      if (typeof selector === 'string') {
        if (selector === '#temp-card') {
          const el = document.getElementById('temp-card');
          return jqWrap(el);
        }
        if (selector === '#temp-card .card-text') {
          const tc = document.getElementById('temp-card');
          const ct = tc ? tc.querySelector('.card-text') : null;
          return jqWrap(ct);
        }
        if (selector === '#discourse') return jqWrap(discourseEl);
        if (selector === '#chat') return jqWrap(document.getElementById('chat'));
        // Template string from createTempCard — parse and create element
        if (selector.includes('id="temp-card"')) {
          const wrapper = document.createElement('div');
          wrapper.innerHTML = selector.trim();
          const newCard = wrapper.firstElementChild;
          return jqWrap(newCard);
        }
      }
      return jqWrap(null);
    });

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
    delete global.$;
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
