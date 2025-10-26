/**
 * Tests for semantic version comparison logic in main.js
 *
 * The compareVersions function must correctly handle:
 * - Standard semantic versions (major.minor.patch)
 * - Prerelease versions (1.0.0-beta.3, 1.0.0-rc.1, etc.)
 * - Important rule: Stable versions are always newer than prerelease versions
 *   Example: 1.0.0 > 1.0.0-beta.3
 */

const { readFileSync } = require('fs');
const { join } = require('path');

// Extract compareVersions function from main.js
const mainJsPath = join(__dirname, '../../app/main.js');
const mainJsContent = readFileSync(mainJsPath, 'utf8');

// Extract the compareVersions function
const funcMatch = mainJsContent.match(/function compareVersions\(version1, version2\) \{[\s\S]*?\n\}/);
if (!funcMatch) {
  throw new Error('Could not extract compareVersions function from main.js');
}

// Create a function from the extracted code
const compareVersions = eval(`(${funcMatch[0]})`);

describe('Version Comparison', () => {
  describe('Standard semantic versions', () => {
    test('should compare major versions correctly', () => {
      expect(compareVersions('2.0.0', '1.0.0')).toBeGreaterThan(0);
      expect(compareVersions('1.0.0', '2.0.0')).toBeLessThan(0);
      expect(compareVersions('1.0.0', '1.0.0')).toBe(0);
    });

    test('should compare minor versions correctly', () => {
      expect(compareVersions('1.2.0', '1.1.0')).toBeGreaterThan(0);
      expect(compareVersions('1.1.0', '1.2.0')).toBeLessThan(0);
      expect(compareVersions('1.1.0', '1.1.0')).toBe(0);
    });

    test('should compare patch versions correctly', () => {
      expect(compareVersions('1.0.2', '1.0.1')).toBeGreaterThan(0);
      expect(compareVersions('1.0.1', '1.0.2')).toBeLessThan(0);
      expect(compareVersions('1.0.1', '1.0.1')).toBe(0);
    });
  });

  describe('Prerelease versions', () => {
    test('should treat stable version as newer than prerelease', () => {
      // This is the critical bug fix: 1.0.0 > 1.0.0-beta.3
      expect(compareVersions('1.0.0', '1.0.0-beta.3')).toBeGreaterThan(0);
      expect(compareVersions('1.0.0-beta.3', '1.0.0')).toBeLessThan(0);
    });

    test('should compare different prerelease versions', () => {
      expect(compareVersions('1.0.0-beta.3', '1.0.0-beta.2')).toBeGreaterThan(0);
      expect(compareVersions('1.0.0-beta.2', '1.0.0-beta.3')).toBeLessThan(0);
      expect(compareVersions('1.0.0-beta.3', '1.0.0-beta.3')).toBe(0);
    });

    test('should compare rc vs beta', () => {
      expect(compareVersions('1.0.0-rc.1', '1.0.0-beta.5')).toBeGreaterThan(0);
      expect(compareVersions('1.0.0-beta.5', '1.0.0-rc.1')).toBeLessThan(0);
    });
  });

  describe('Real-world version scenarios', () => {
    test('should handle the reported bug case', () => {
      // Bug report: App version 1.0.0 incorrectly showed 1.0.0-beta.3 as newer
      const currentVersion = '1.0.0';
      const githubVersion = '1.0.0-beta.3';

      expect(compareVersions(currentVersion, githubVersion)).toBeGreaterThan(0);
      // This means currentVersion is newer, so no update notification should appear
    });

    test('should correctly identify when update is available', () => {
      expect(compareVersions('1.0.0', '1.0.1')).toBeLessThan(0);
      expect(compareVersions('1.0.0', '1.1.0')).toBeLessThan(0);
      expect(compareVersions('1.0.0', '2.0.0')).toBeLessThan(0);
    });

    test('should handle beta progression correctly', () => {
      expect(compareVersions('1.0.0-beta.3', '1.0.0-beta.4')).toBeLessThan(0);
      expect(compareVersions('1.0.0-beta.5', '1.0.0-beta.3')).toBeGreaterThan(0);
    });
  });

  describe('Edge cases', () => {
    test('should handle malformed versions with fallback', () => {
      // Invalid format should fall back to string comparison
      expect(compareVersions('invalid', 'also-invalid')).not.toThrow;
      expect(compareVersions('1.0', '1.0.0')).not.toThrow;
    });
  });
});
