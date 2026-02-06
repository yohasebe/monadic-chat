/**
 * @jest-environment jsdom
 */

describe('StorageHelper Module', () => {
  let StorageHelper;
  let mockStorage;

  beforeEach(() => {
    jest.resetModules();

    // Create a real-ish localStorage mock
    mockStorage = {};
    const storageMock = {
      getItem: jest.fn(key => mockStorage[key] !== undefined ? mockStorage[key] : null),
      setItem: jest.fn((key, value) => { mockStorage[key] = String(value); }),
      removeItem: jest.fn(key => { delete mockStorage[key]; }),
      key: jest.fn(i => Object.keys(mockStorage)[i] || null),
      get length() { return Object.keys(mockStorage).length; }
    };

    Object.defineProperty(window, 'localStorage', {
      value: storageMock,
      writable: true,
      configurable: true
    });

    require('../../docker/services/ruby/public/js/monadic/storage-helper.js');
    StorageHelper = window.StorageHelper;
  });

  afterEach(() => {
    delete window.StorageHelper;
  });

  describe('safeSetItem', () => {
    it('stores value and returns true on success', () => {
      const result = StorageHelper.safeSetItem('key1', 'value1');
      expect(result).toBe(true);
      expect(localStorage.setItem).toHaveBeenCalledWith('key1', 'value1');
    });

    it('returns false on QuotaExceededError when clearOnQuota is false', () => {
      localStorage.setItem.mockImplementation(() => {
        const err = new Error('Quota exceeded');
        err.name = 'QuotaExceededError';
        throw err;
      });

      const result = StorageHelper.safeSetItem('key', 'val', false);
      expect(result).toBe(false);
    });

    it('retries after clearing non-critical items on QuotaExceededError', () => {
      let callCount = 0;
      localStorage.setItem.mockImplementation(() => {
        callCount++;
        if (callCount === 1) {
          const err = new Error('Quota exceeded');
          err.name = 'QuotaExceededError';
          throw err;
        }
        // Second call succeeds
      });

      const result = StorageHelper.safeSetItem('key', 'val', true);
      expect(result).toBe(true);
    });

    it('returns false on SecurityError', () => {
      localStorage.setItem.mockImplementation(() => {
        const err = new Error('Access denied');
        err.name = 'SecurityError';
        throw err;
      });

      const result = StorageHelper.safeSetItem('key', 'val');
      expect(result).toBe(false);
    });
  });

  describe('safeGetItem', () => {
    it('returns stored value', () => {
      mockStorage['myKey'] = 'myVal';
      expect(StorageHelper.safeGetItem('myKey')).toBe('myVal');
    });

    it('returns default value when key does not exist', () => {
      expect(StorageHelper.safeGetItem('missing', 'fallback')).toBe('fallback');
    });

    it('returns null as default when no default provided', () => {
      expect(StorageHelper.safeGetItem('missing')).toBeNull();
    });

    it('returns default on error', () => {
      localStorage.getItem.mockImplementation(() => { throw new Error('fail'); });
      expect(StorageHelper.safeGetItem('key', 'safe')).toBe('safe');
    });
  });

  describe('safeRemoveItem', () => {
    it('removes item and returns true', () => {
      const result = StorageHelper.safeRemoveItem('key');
      expect(result).toBe(true);
      expect(localStorage.removeItem).toHaveBeenCalledWith('key');
    });

    it('returns false on error', () => {
      localStorage.removeItem.mockImplementation(() => { throw new Error('fail'); });
      expect(StorageHelper.safeRemoveItem('key')).toBe(false);
    });
  });

  describe('_clearNonCriticalItems', () => {
    it('preserves critical keys', () => {
      mockStorage = {
        'monadicState': 'state',
        'theme': 'dark',
        'monadic-ui-theme': 'dark',
        'ui-language': 'en',
        'rouge_theme': 'monokai',
        'tempData': 'delete-me'
      };

      StorageHelper._clearNonCriticalItems();

      // tempData should be removed
      expect(localStorage.removeItem).toHaveBeenCalledWith('tempData');
      // Critical keys should NOT be removed
      expect(localStorage.removeItem).not.toHaveBeenCalledWith('monadicState');
      expect(localStorage.removeItem).not.toHaveBeenCalledWith('theme');
    });
  });

  describe('getStorageInfo', () => {
    it('returns storage usage information', () => {
      mockStorage = { 'key1': 'val1', 'key2': 'val2' };
      // Mock hasOwnProperty to work with our mockStorage
      Object.defineProperty(localStorage, 'hasOwnProperty', {
        value: (key) => key in mockStorage,
        configurable: true
      });
      // Expose keys for for-in iteration
      for (const key of Object.keys(mockStorage)) {
        localStorage[key] = mockStorage[key];
      }

      const info = StorageHelper.getStorageInfo();
      expect(info).toHaveProperty('used');
      expect(info).toHaveProperty('usedKB');
      expect(info).toHaveProperty('usedMB');
      expect(info).toHaveProperty('itemCount');
    });

    it('returns zero values on error', () => {
      // Make the for-in loop throw by making localStorage itself throw
      const origLS = window.localStorage;
      const throwingLS = new Proxy(origLS, {
        get(target, prop) {
          if (prop === 'hasOwnProperty') throw new Error('blocked');
          return target[prop];
        }
      });
      Object.defineProperty(window, 'localStorage', { value: throwingLS, configurable: true });

      const info = StorageHelper.getStorageInfo();
      expect(info.used).toBe(0);
      expect(info.itemCount).toBe(0);

      // Restore
      Object.defineProperty(window, 'localStorage', { value: origLS, configurable: true });
    });
  });

  describe('isAvailable', () => {
    it('returns true when localStorage works', () => {
      expect(StorageHelper.isAvailable()).toBe(true);
    });

    it('returns false when localStorage throws', () => {
      localStorage.setItem.mockImplementation(() => { throw new Error('blocked'); });
      expect(StorageHelper.isAvailable()).toBe(false);
    });
  });
});
