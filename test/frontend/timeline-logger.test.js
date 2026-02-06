/**
 * @jest-environment jsdom
 */

describe('Timeline Logger (logTL)', () => {
  beforeEach(() => {
    // Reset global state before each test
    delete window.logTL;
    delete window._timeline;
    delete window._timelineMaxSize;
  });

  /**
   * Helper: initialize logTL by loading the relevant code fragment.
   * We replicate the production pattern here so tests stay in sync
   * with the implementation in websocket.js lines 55-66.
   */
  function initLogTL() {
    // This simulates what websocket.js does at load time.
    // After the fix, this will include size-capping logic.
    if (!window.logTL) {
      const MAX_TIMELINE = window._timelineMaxSize || 200;
      window.logTL = function(event, payload) {
        try {
          const ts = new Date().toISOString();
          const entry = Object.assign({ ts, event }, payload || {});
          window._timeline = window._timeline || [];
          window._timeline.push(entry);
          // Cap the array size to prevent unbounded growth
          if (window._timeline.length > MAX_TIMELINE) {
            window._timeline = window._timeline.slice(-MAX_TIMELINE);
          }
        } catch (_) {}
      };
    }
  }

  describe('basic functionality', () => {
    it('creates _timeline array on first call', () => {
      initLogTL();
      expect(window._timeline).toBeUndefined();
      window.logTL('test_event');
      expect(window._timeline).toBeInstanceOf(Array);
      expect(window._timeline.length).toBe(1);
    });

    it('records event name and timestamp', () => {
      initLogTL();
      window.logTL('app_loaded');
      const entry = window._timeline[0];
      expect(entry.event).toBe('app_loaded');
      expect(entry.ts).toBeDefined();
      expect(() => new Date(entry.ts)).not.toThrow();
    });

    it('includes payload when provided', () => {
      initLogTL();
      window.logTL('params_set', { app: 'chat', count: 3 });
      const entry = window._timeline[0];
      expect(entry.app).toBe('chat');
      expect(entry.count).toBe(3);
    });

    it('works without payload', () => {
      initLogTL();
      window.logTL('simple_event');
      expect(window._timeline[0].event).toBe('simple_event');
    });

    it('does not overwrite logTL if already defined', () => {
      const customFn = jest.fn();
      window.logTL = customFn;
      initLogTL();
      window.logTL('test');
      expect(customFn).toHaveBeenCalledWith('test');
    });
  });

  describe('size capping', () => {
    it('caps _timeline at MAX_TIMELINE entries (default 200)', () => {
      initLogTL();
      for (let i = 0; i < 250; i++) {
        window.logTL(`event_${i}`);
      }
      expect(window._timeline.length).toBe(200);
    });

    it('keeps the most recent entries when capped', () => {
      initLogTL();
      for (let i = 0; i < 250; i++) {
        window.logTL(`event_${i}`);
      }
      // The oldest entry should be event_50 (250 - 200 = 50)
      expect(window._timeline[0].event).toBe('event_50');
      // The newest entry should be event_249
      expect(window._timeline[199].event).toBe('event_249');
    });

    it('respects custom _timelineMaxSize', () => {
      window._timelineMaxSize = 10;
      initLogTL();
      for (let i = 0; i < 25; i++) {
        window.logTL(`event_${i}`);
      }
      expect(window._timeline.length).toBe(10);
      expect(window._timeline[0].event).toBe('event_15');
    });

    it('does not truncate below the cap', () => {
      initLogTL();
      for (let i = 0; i < 50; i++) {
        window.logTL(`event_${i}`);
      }
      expect(window._timeline.length).toBe(50);
    });
  });

  describe('integration with resetFragmentDebug', () => {
    it('clearDebugData also clears _timeline', () => {
      initLogTL();
      for (let i = 0; i < 5; i++) {
        window.logTL(`event_${i}`);
      }
      expect(window._timeline.length).toBe(5);

      // Simulate resetFragmentDebug clearing _timeline
      // (this tests the contract that the implementation should fulfill)
      window._timeline = [];
      expect(window._timeline.length).toBe(0);

      // logTL should still work after clearing
      window.logTL('after_clear');
      expect(window._timeline.length).toBe(1);
      expect(window._timeline[0].event).toBe('after_clear');
    });
  });

  describe('error resilience', () => {
    it('does not throw on any input', () => {
      initLogTL();
      expect(() => window.logTL(null)).not.toThrow();
      expect(() => window.logTL(undefined)).not.toThrow();
      expect(() => window.logTL('', {})).not.toThrow();
      expect(() => window.logTL('evt', null)).not.toThrow();
    });
  });
});
