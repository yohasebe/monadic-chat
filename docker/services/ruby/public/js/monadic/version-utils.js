// Semantic version comparison utilities
// Based on the semver specification: https://semver.org/

/**
 * Parse a semantic version string into its components
 * @param {string} version - Version string (e.g., "1.0.0-beta.1")
 * @returns {Object} Parsed version object
 */
function parseVersion(version) {
  const match = version.match(/^(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z0-9.-]+))?(?:\+([a-zA-Z0-9.-]+))?$/);
  
  if (!match) {
    throw new Error(`Invalid version format: ${version}`);
  }
  
  return {
    major: parseInt(match[1], 10),
    minor: parseInt(match[2], 10),
    patch: parseInt(match[3], 10),
    prerelease: match[4] ? match[4].split('.') : [],
    build: match[5] || ''
  };
}

/**
 * Compare two semantic versions
 * @param {string} v1 - First version
 * @param {string} v2 - Second version
 * @returns {number} -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
 */
function compareVersions(v1, v2) {
  try {
    const parsed1 = parseVersion(v1);
    const parsed2 = parseVersion(v2);
    
    // Compare major, minor, patch
    for (const key of ['major', 'minor', 'patch']) {
      if (parsed1[key] < parsed2[key]) return -1;
      if (parsed1[key] > parsed2[key]) return 1;
    }
    
    // If one has prerelease and other doesn't, the one without is greater
    if (parsed1.prerelease.length === 0 && parsed2.prerelease.length > 0) return 1;
    if (parsed1.prerelease.length > 0 && parsed2.prerelease.length === 0) return -1;
    
    // Compare prerelease versions
    const minLength = Math.min(parsed1.prerelease.length, parsed2.prerelease.length);
    
    for (let i = 0; i < minLength; i++) {
      const a = parsed1.prerelease[i];
      const b = parsed2.prerelease[i];
      
      // Numeric comparison
      if (!isNaN(a) && !isNaN(b)) {
        const numA = parseInt(a, 10);
        const numB = parseInt(b, 10);
        if (numA < numB) return -1;
        if (numA > numB) return 1;
      } else {
        // String comparison
        if (a < b) return -1;
        if (a > b) return 1;
      }
    }
    
    // If all prerelease parts are equal, the one with more parts is greater
    if (parsed1.prerelease.length < parsed2.prerelease.length) return -1;
    if (parsed1.prerelease.length > parsed2.prerelease.length) return 1;
    
    return 0;
  } catch (e) {
    console.warn('Version comparison failed, falling back to string comparison:', e);
    return v1.localeCompare(v2);
  }
}

/**
 * Check if a version is newer than another
 * @param {string} newVersion - New version to check
 * @param {string} oldVersion - Old version to compare against
 * @returns {boolean} true if newVersion > oldVersion
 */
function isVersionNewer(newVersion, oldVersion) {
  return compareVersions(newVersion, oldVersion) > 0;
}

/**
 * Check if a version is a prerelease
 * @param {string} version - Version to check
 * @returns {boolean} true if version is a prerelease
 */
function isPrerelease(version) {
  try {
    const parsed = parseVersion(version);
    return parsed.prerelease.length > 0;
  } catch (e) {
    // Fallback check
    return version.includes('-') && 
           (version.includes('beta') || version.includes('alpha') || version.includes('rc'));
  }
}

// Export for use in other modules if running in Node.js environment
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    parseVersion,
    compareVersions,
    isVersionNewer,
    isPrerelease
  };
}

// Make available globally in browser
if (typeof window !== 'undefined') {
  window.versionUtils = {
    parseVersion,
    compareVersions,
    isVersionNewer,
    isPrerelease
  };
}