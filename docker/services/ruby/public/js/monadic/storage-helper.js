/**
 * Storage Helper - Safe localStorage wrapper with quota handling
 *
 * Provides safe methods for localStorage operations with proper error handling
 * for QuotaExceededError and other storage-related issues.
 */

const StorageHelper = {
  /**
   * Safely set an item in localStorage
   * @param {string} key - Storage key
   * @param {string} value - Value to store
   * @param {boolean} clearOnQuota - Whether to clear storage on quota exceeded (default: true)
   * @returns {boolean} - Success status
   */
  safeSetItem(key, value, clearOnQuota = true) {
    try {
      localStorage.setItem(key, value);
      return true;
    } catch (e) {
      if (e.name === 'QuotaExceededError') {
        console.warn('[StorageHelper] Quota exceeded for key:', key);

        if (clearOnQuota) {
          // Try to free up space by removing non-critical items
          this._clearNonCriticalItems();

          // Retry once after cleanup
          try {
            localStorage.setItem(key, value);
            console.info('[StorageHelper] Successfully stored after cleanup');
            return true;
          } catch (e2) {
            console.error('[StorageHelper] Failed even after cleanup:', e2);
            return false;
          }
        } else {
          console.error('[StorageHelper] Quota exceeded and clearOnQuota=false');
          return false;
        }
      } else if (e.name === 'SecurityError') {
        console.error('[StorageHelper] Storage access denied (private browsing?):', e);
        return false;
      } else {
        console.error('[StorageHelper] Unexpected storage error:', e);
        return false;
      }
    }
  },

  /**
   * Safely get an item from localStorage
   * @param {string} key - Storage key
   * @param {*} defaultValue - Default value if key doesn't exist or error occurs
   * @returns {*} - Stored value or default
   */
  safeGetItem(key, defaultValue = null) {
    try {
      const value = localStorage.getItem(key);
      return value !== null ? value : defaultValue;
    } catch (e) {
      console.error('[StorageHelper] Error reading from storage:', e);
      return defaultValue;
    }
  },

  /**
   * Safely remove an item from localStorage
   * @param {string} key - Storage key
   * @returns {boolean} - Success status
   */
  safeRemoveItem(key) {
    try {
      localStorage.removeItem(key);
      return true;
    } catch (e) {
      console.error('[StorageHelper] Error removing from storage:', e);
      return false;
    }
  },

  /**
   * Clear non-critical items from localStorage
   * Critical items: monadicState, theme, language
   * @private
   */
  _clearNonCriticalItems() {
    const criticalKeys = [
      'monadicState',
      'theme',
      'monadic-ui-theme',
      'ui-language',
      'rouge_theme'
    ];

    const keysToRemove = [];

    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key && !criticalKeys.includes(key)) {
          keysToRemove.push(key);
        }
      }

      keysToRemove.forEach(key => {
        try {
          localStorage.removeItem(key);
          console.info('[StorageHelper] Removed non-critical item:', key);
        } catch (e) {
          console.warn('[StorageHelper] Failed to remove item:', key, e);
        }
      });

      console.info(`[StorageHelper] Cleared ${keysToRemove.length} non-critical items`);
    } catch (e) {
      console.error('[StorageHelper] Error during cleanup:', e);
    }
  },

  /**
   * Get storage usage information
   * @returns {Object} - Storage info (used, available, total)
   */
  getStorageInfo() {
    try {
      let used = 0;
      for (let key in localStorage) {
        if (localStorage.hasOwnProperty(key)) {
          used += localStorage[key].length + key.length;
        }
      }

      // localStorage quota is typically 5-10MB per origin
      // This is an approximation
      const usedKB = (used / 1024).toFixed(2);
      const usedMB = (used / 1024 / 1024).toFixed(2);

      return {
        used: used,
        usedKB: usedKB,
        usedMB: usedMB,
        itemCount: localStorage.length
      };
    } catch (e) {
      console.error('[StorageHelper] Error getting storage info:', e);
      return {
        used: 0,
        usedKB: '0.00',
        usedMB: '0.00',
        itemCount: 0
      };
    }
  },

  /**
   * Check if storage is available
   * @returns {boolean} - Availability status
   */
  isAvailable() {
    try {
      const test = '__storage_test__';
      localStorage.setItem(test, test);
      localStorage.removeItem(test);
      return true;
    } catch (e) {
      console.warn('[StorageHelper] Storage not available:', e);
      return false;
    }
  }
};

// Make globally available
window.StorageHelper = StorageHelper;

// Log storage info on load (only if debug enabled)
if (localStorage.getItem('ENABLE_DEBUG_LOGGING') === 'true') {
  console.log('[StorageHelper] Storage info:', StorageHelper.getStorageInfo());
}
