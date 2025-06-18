// Test for version-utils.js
// Run with: npm test test/frontend/version-utils.test.js

const fs = require('fs');
const path = require('path');

// Load the version-utils.js file
const versionUtilsPath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/version-utils.js');
const versionUtilsCode = fs.readFileSync(versionUtilsPath, 'utf8');

// Create a function scope to avoid variable conflicts
const versionUtils = (() => {
  const mockWindow = {};
  const mockModule = { exports: {} };
  
  // Evaluate in isolated scope
  (function() {
    const window = mockWindow;
    const module = mockModule;
    eval(versionUtilsCode);
  })();
  
  // Return the utilities (prefer module.exports if available, otherwise window)
  return mockModule.exports.parseVersion ? mockModule.exports : mockWindow.versionUtils;
})();

// Extract the functions
const { parseVersion, compareVersions, isVersionNewer, isPrerelease } = versionUtils;

describe('Version Utils', () => {
  describe('parseVersion', () => {
    test('parses standard version', () => {
      const result = parseVersion('1.2.3');
      expect(result).toEqual({
        major: 1,
        minor: 2,
        patch: 3,
        prerelease: [],
        build: ''
      });
    });

    test('parses version with prerelease', () => {
      const result = parseVersion('1.0.0-beta.1');
      expect(result).toEqual({
        major: 1,
        minor: 0,
        patch: 0,
        prerelease: ['beta', '1'],
        build: ''
      });
    });

    test('parses version with build metadata', () => {
      const result = parseVersion('1.0.0+build.123');
      expect(result).toEqual({
        major: 1,
        minor: 0,
        patch: 0,
        prerelease: [],
        build: 'build.123'
      });
    });

    test('throws on invalid version', () => {
      expect(() => parseVersion('invalid')).toThrow('Invalid version format');
    });
  });

  describe('compareVersions', () => {
    test('1.0.0 is newer than 1.0.0-beta.1', () => {
      expect(compareVersions('1.0.0', '1.0.0-beta.1')).toBe(1);
    });

    test('1.0.0-beta.2 is newer than 1.0.0-beta.1', () => {
      expect(compareVersions('1.0.0-beta.2', '1.0.0-beta.1')).toBe(1);
    });

    test('1.0.0-beta.1 is newer than 1.0.0-alpha.1', () => {
      expect(compareVersions('1.0.0-beta.1', '1.0.0-alpha.1')).toBe(1);
    });

    test('1.0.0-rc.1 is newer than 1.0.0-beta.1', () => {
      expect(compareVersions('1.0.0-rc.1', '1.0.0-beta.1')).toBe(1);
    });

    test('1.0.0 is newer than 0.9.99', () => {
      expect(compareVersions('1.0.0', '0.9.99')).toBe(1);
    });

    test('same versions are equal', () => {
      expect(compareVersions('1.0.0', '1.0.0')).toBe(0);
    });

    test('1.0.0-beta.1 is older than 1.0.0', () => {
      expect(compareVersions('1.0.0-beta.1', '1.0.0')).toBe(-1);
    });

    test('handles numeric vs string prerelease parts', () => {
      expect(compareVersions('1.0.0-beta.2', '1.0.0-beta.10')).toBe(-1);
    });

    test('falls back to string comparison on parse error', () => {
      const consoleSpy = jest.spyOn(console, 'warn').mockImplementation();
      const result = compareVersions('invalid1', 'invalid2');
      expect(consoleSpy).toHaveBeenCalled();
      expect(typeof result).toBe('number');
      consoleSpy.mockRestore();
    });
  });

  describe('isVersionNewer', () => {
    test('returns true when first version is newer', () => {
      expect(isVersionNewer('1.0.0', '1.0.0-beta.1')).toBe(true);
    });

    test('returns false when first version is older', () => {
      expect(isVersionNewer('1.0.0-beta.1', '1.0.0')).toBe(false);
    });

    test('returns false when versions are equal', () => {
      expect(isVersionNewer('1.0.0', '1.0.0')).toBe(false);
    });
  });

  describe('isPrerelease', () => {
    test('detects beta versions', () => {
      expect(isPrerelease('1.0.0-beta.1')).toBe(true);
    });

    test('detects alpha versions', () => {
      expect(isPrerelease('1.0.0-alpha.1')).toBe(true);
    });

    test('detects rc versions', () => {
      expect(isPrerelease('1.0.0-rc.1')).toBe(true);
    });

    test('returns false for stable versions', () => {
      expect(isPrerelease('1.0.0')).toBe(false);
    });

    test('fallback detection for malformed versions', () => {
      expect(isPrerelease('1.0-beta')).toBe(true);
    });
  });
});