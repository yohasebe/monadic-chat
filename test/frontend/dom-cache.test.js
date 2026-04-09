/**
 * @jest-environment jsdom
 */

describe('DOMCache Module', () => {
  let DOMCache;

  beforeEach(() => {
    jest.resetModules();

    // Setup minimal DOM elements for initialize()
    document.body.innerHTML = `
      <div id="main"></div>
      <div id="menu"></div>
      <div id="messages"></div>
      <div id="message"></div>
      <div id="toggle-menu"></div>
      <div id="back_to_top"></div>
      <div id="back_to_bottom"></div>
      <div id="monadic-spinner"></div>
      <div id="status-message"></div>
      <div id="send"></div>
      <div id="clear"></div>
      <div id="apps"></div>
      <div id="model"></div>
      <div class="navbar-brand"></div>
    `;

    // dom-cache.js uses native DOM APIs

    require('../../docker/services/ruby/public/js/monadic/dom-cache.js');
    DOMCache = window.DOMCache;
  });

  afterEach(() => {
    delete window.DOMCache;
    document.body.innerHTML = '';
  });

  describe('get', () => {
    it('returns DOM element for valid selector', () => {
      const result = DOMCache.get('#main');
      expect(result).toBeDefined();
      expect(result).toBeInstanceOf(HTMLElement);
    });

    it('caches element on first query', () => {
      DOMCache.clearAll();
      const statsBefore = DOMCache.getStats();
      const initialMisses = statsBefore.misses;

      DOMCache.get('#main');
      DOMCache.get('#main');

      const statsAfter = DOMCache.getStats();
      // Second call should be a cache hit
      expect(statsAfter.hits).toBeGreaterThan(statsBefore.hits);
    });

    it('does not cache elements with length 0', () => {
      DOMCache.clearAll();
      DOMCache.get('#nonexistent');
      expect(DOMCache.getStats().cacheSize).toBe(0);
    });

    it('refreshes cache when forceRefresh is true', () => {
      DOMCache.get('#main');
      const result = DOMCache.get('#main', true);
      expect(result).toBeDefined();
    });
  });

  describe('getMultiple', () => {
    it('returns object with selector keys', () => {
      const results = DOMCache.getMultiple(['#main', '#menu']);
      expect(results['#main']).toBeDefined();
      expect(results['#menu']).toBeDefined();
    });
  });

  describe('clear', () => {
    it('removes specific selector from cache', () => {
      DOMCache.get('#main');
      const sizeBefore = DOMCache.getStats().cacheSize;
      DOMCache.clear('#main');
      expect(DOMCache.getStats().cacheSize).toBeLessThan(sizeBefore);
    });
  });

  describe('clearAll', () => {
    it('empties the entire cache', () => {
      DOMCache.get('#main');
      DOMCache.get('#menu');
      DOMCache.clearAll();
      expect(DOMCache.getStats().cacheSize).toBe(0);
    });
  });

  describe('refresh', () => {
    it('clears and re-fetches the element', () => {
      DOMCache.get('#main');
      const result = DOMCache.refresh('#main');
      expect(result).toBeDefined();
      expect(result).toBeInstanceOf(HTMLElement);
    });
  });

  describe('getStats', () => {
    it('returns performance statistics', () => {
      DOMCache.clearAll();
      // Reset stats by reloading
      const stats = DOMCache.getStats();
      expect(stats).toHaveProperty('hits');
      expect(stats).toHaveProperty('misses');
      expect(stats).toHaveProperty('queries');
      expect(stats).toHaveProperty('cacheSize');
      expect(stats).toHaveProperty('hitRate');
    });

    it('hitRate is between 0 and 1', () => {
      DOMCache.get('#main');
      DOMCache.get('#main');
      const stats = DOMCache.getStats();
      expect(stats.hitRate).toBeGreaterThanOrEqual(0);
      expect(stats.hitRate).toBeLessThanOrEqual(1);
    });
  });

  describe('getCached / $c alias', () => {
    it('getCached behaves same as get', () => {
      const a = DOMCache.get('#main');
      const b = DOMCache.getCached('#main');
      expect(a).toBe(b); // Same cached reference
    });

    it('$c is an alias for getCached', () => {
      expect(DOMCache.$c).toBe(DOMCache.getCached);
    });
  });
});
