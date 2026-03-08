/**
 * Tests for cookie-utils.js
 *
 * Cookie management with sessionStorage fallback.
 */

const { setCookie, getCookie, setCookieValues } = require('../../docker/services/ruby/public/js/monadic/cookie-utils');

describe('cookie-utils', () => {
  beforeEach(() => {
    // Reset document.cookie in jsdom
    document.cookie.split(';').forEach(function(c) {
      document.cookie = c.trim().split('=')[0] + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/';
    });
  });

  describe('setCookie', () => {
    it('sets a cookie with expiry', () => {
      setCookie('testKey', 'testValue', 7);
      expect(document.cookie).toContain('testKey=testValue');
    });

    it('handles empty value', () => {
      setCookie('emptyKey', '', 1);
      expect(document.cookie).toContain('emptyKey=');
    });

    it('handles null value', () => {
      setCookie('nullKey', null, 1);
      // null becomes empty string
      expect(document.cookie).toContain('nullKey=');
    });
  });

  describe('getCookie', () => {
    it('retrieves a set cookie', () => {
      setCookie('myKey', 'myValue', 7);
      expect(getCookie('myKey')).toBe('myValue');
    });

    it('returns null for nonexistent cookie', () => {
      expect(getCookie('nonexistent')).toBeNull();
    });

    it('handles multiple cookies', () => {
      setCookie('first', 'alpha', 7);
      setCookie('second', 'beta', 7);
      expect(getCookie('first')).toBe('alpha');
      expect(getCookie('second')).toBe('beta');
    });
  });

  describe('setCookieValues', () => {
    it('is a function', () => {
      expect(typeof setCookieValues).toBe('function');
    });

    it('does not throw when jQuery is unavailable', () => {
      // $ may be undefined in test env
      expect(() => setCookieValues()).not.toThrow();
    });
  });

  describe('sessionStorage fallback', () => {
    it('falls back to sessionStorage when cookie access fails', () => {
      // Override document.cookie to throw
      const originalDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie');
      Object.defineProperty(document, 'cookie', {
        get: function() { throw new Error('Blocked'); },
        set: function() { throw new Error('Blocked'); },
        configurable: true
      });

      // Should not throw, should fall back to sessionStorage
      expect(() => setCookie('fallbackKey', 'fallbackValue', 1)).not.toThrow();
      expect(getCookie('fallbackKey')).toBe('fallbackValue');

      // Restore
      Object.defineProperty(document, 'cookie', originalDescriptor);
    });
  });

  describe('exports', () => {
    it('exports all functions to window', () => {
      expect(window.setCookie).toBe(setCookie);
      expect(window.getCookie).toBe(getCookie);
      expect(window.setCookieValues).toBe(setCookieValues);
    });
  });
});
