/**
 * Lazy loader for heavy vendor libraries.
 *
 * Libraries are loaded on first use instead of at page startup.
 * Each loader returns a Promise that resolves when the library is ready.
 *
 * Savings: ~3.6 MB deferred from initial page load
 *   - Mermaid:  2.5 MB (diagram rendering)
 *   - ABCjs:    472 KB (music notation)
 *   - maxgraph: 608 KB (DrawIO diagrams)
 */
/* global mermaid, ABCJS */

window.LazyLoader = (function () {
  "use strict";

  const _cache = {};

  /**
   * Load a script by URL. Returns a cached Promise on subsequent calls.
   * @param {string} key   - Cache key (library name)
   * @param {string} local - Local path (vendor/js/...)
   * @param {string} cdn   - CDN fallback URL
   * @returns {Promise<void>}
   */
  function _load(key, local, cdn) {
    if (_cache[key]) return _cache[key];

    _cache[key] = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = local;
      script.onerror = function () {
        // Fallback to CDN
        script.onerror = null;
        const fallback = document.createElement("script");
        fallback.src = cdn;
        fallback.onload = resolve;
        fallback.onerror = () => reject(new Error(`Failed to load ${key} from both local and CDN`));
        document.head.appendChild(fallback);
      };
      script.onload = resolve;
      document.head.appendChild(script);
    });

    return _cache[key];
  }

  return {
    /**
     * Ensure Mermaid is loaded and initialized.
     * @returns {Promise<void>}
     */
    mermaid: function () {
      if (typeof window.mermaid !== "undefined") {
        return Promise.resolve();
      }
      return _load(
        "mermaid",
        "vendor/js/mermaid.min.js",
        "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"
      );
    },

    /**
     * Ensure ABCjs is loaded.
     * @returns {Promise<void>}
     */
    abcjs: function () {
      if (typeof window.ABCJS !== "undefined") {
        return Promise.resolve();
      }
      return _load(
        "abcjs",
        "vendor/js/abcjs-basic-min.min.js",
        "https://cdn.jsdelivr.net/npm/abcjs@6.4.4/dist/abcjs-basic-min.min.js"
      );
    },

    /**
     * Ensure maxgraph is loaded.
     * @returns {Promise<void>}
     */
    maxgraph: function () {
      if (typeof window.maxgraph !== "undefined") {
        return Promise.resolve();
      }
      return _load(
        "maxgraph",
        "vendor/js/maxgraph.bundle.js",
        "" // No CDN fallback for maxgraph (custom bundle)
      );
    },

    /**
     * Check if a library is already loaded.
     * @param {string} key
     * @returns {boolean}
     */
    isLoaded: function (key) {
      switch (key) {
        case "mermaid": return typeof window.mermaid !== "undefined";
        case "abcjs": return typeof window.ABCJS !== "undefined";
        case "maxgraph": return typeof window.maxgraph !== "undefined";
        default: return false;
      }
    }
  };
})();
