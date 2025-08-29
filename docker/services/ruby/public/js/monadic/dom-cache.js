/**
 * DOM Element Cache Module
 * Caches frequently accessed DOM elements to improve performance
 */

(function(window) {
  'use strict';
  
  // Cache storage
  const elementCache = new Map();
  
  // Performance tracking
  const performanceStats = {
    hits: 0,
    misses: 0,
    queries: 0
  };
  
  /**
   * Get cached jQuery element or query and cache it
   * @param {string} selector - jQuery selector
   * @param {boolean} forceRefresh - Force refresh the cache
   * @returns {jQuery} Cached jQuery element
   */
  function get(selector, forceRefresh = false) {
    performanceStats.queries++;
    
    if (!forceRefresh && elementCache.has(selector)) {
      performanceStats.hits++;
      return elementCache.get(selector);
    }
    
    performanceStats.misses++;
    // Use jQuery $ directly - no conflict as we renamed the alias
    const element = $(selector);
    
    // Only cache if element exists
    if (element.length > 0) {
      elementCache.set(selector, element);
    }
    
    return element;
  }
  
  /**
   * Get multiple elements at once
   * @param {Array<string>} selectors - Array of selectors
   * @returns {Object} Object with selector keys and jQuery element values
   */
  function getMultiple(selectors) {
    const result = {};
    
    selectors.forEach(selector => {
      result[selector] = get(selector);
    });
    
    return result;
  }
  
  /**
   * Clear specific cache entry
   * @param {string} selector - Selector to clear
   */
  function clear(selector) {
    elementCache.delete(selector);
  }
  
  /**
   * Clear all cache
   */
  function clearAll() {
    elementCache.clear();
    console.log('DOM cache cleared');
  }
  
  /**
   * Refresh cache for specific selector
   * @param {string} selector - Selector to refresh
   * @returns {jQuery} Fresh jQuery element
   */
  function refresh(selector) {
    clear(selector);
    return get(selector);
  }
  
  /**
   * Get cache statistics
   * @returns {Object} Cache performance statistics
   */
  function getStats() {
    return {
      ...performanceStats,
      cacheSize: elementCache.size,
      hitRate: performanceStats.hits / (performanceStats.queries || 1)
    };
  }
  
  /**
   * Initialize common elements cache
   * Call this after DOM is ready
   */
  function initialize() {
    // Pre-cache commonly used elements
    const commonSelectors = [
      '#main',
      '#menu',
      '#messages',
      '#message',
      '#toggle-menu',
      '#back_to_top',
      '#back_to_bottom',
      '#monadic-spinner',
      '#status-message',
      '#send',
      '#clear',
      '#apps',
      '#model',
      '.navbar-brand'
    ];
    
    commonSelectors.forEach(selector => {
      get(selector);
    });
    
    console.log(`DOM cache initialized with ${commonSelectors.length} elements`);
  }
  
  /**
   * Setup automatic cache refresh on DOM changes
   */
  function setupAutoRefresh() {
    // Clear cache when significant DOM changes occur
    $(document).on('DOMContentLoaded', clearAll);
    
    // Clear cache before page unload
    $(window).on('beforeunload', clearAll);
  }
  
  // Convenience method for getting single element
  function getCached(selector, forceRefresh = false) {
    return get(selector, forceRefresh);
  }
  
  // Public API
  const DOMCache = {
    get,
    getMultiple,
    clear,
    clearAll,
    refresh,
    getStats,
    initialize,
    setupAutoRefresh,
    getCached,  // Explicit method name
    $c: getCached  // Short alias that doesn't conflict with jQuery's $
  };
  
  // Export to window
  window.DOMCache = DOMCache;
  
  // Auto-initialize when document is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      initialize();
      setupAutoRefresh();
    });
  } else {
    initialize();
    setupAutoRefresh();
  }
  
  // Export for testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = DOMCache;
  }
  
})(typeof window !== 'undefined' ? window : this);