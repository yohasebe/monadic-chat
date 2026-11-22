/**
 * Lazy loader for heavy vendor libraries.
 *
 * Libraries are loaded on first use instead of at page startup.
 * Each loader returns a Promise that resolves when the library is ready.
 *
 * Savings: ~1.1 MB deferred from initial page load
 *   - ABCjs:    472 KB (music notation)
 *   - maxgraph: 608 KB (workflow graphs)
 *
 * Mermaid is read by the work screen's drawing frame (workbench-render.js).
 */
/* global ABCJS */

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

    const promise = new Promise((resolve, reject) => {
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

    // A cached REJECTION would veto every later attempt forever — with no
    // CDN fallback (maxgraph) that is a permanent dead end. Evict
    // failures so the next call retries the network.
    promise.catch(function () {
      if (_cache[key] === promise) delete _cache[key];
    });
    _cache[key] = promise;

    return _cache[key];
  }

  return {

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
        case "abcjs": return typeof window.ABCJS !== "undefined";
        case "maxgraph": return typeof window.maxgraph !== "undefined";
        default: return false;
      }
    }
  };
})();
