/**
 * Badge Rendering System for Monadic Chat
 *
 * Renders tool and capability badges for the selected app.
 * Handles defensive parsing of badge data from multiple formats.
 *
 * Dependencies: window.apps, window.setBaseAppDescription (from utilities.js)
 *
 * Extracted from utilities.js for modularity.
 */
(function() {
'use strict';

/**
 * Update badges display for the selected app.
 * Parses badge data defensively with multiple fallback strategies.
 * @param {string} selectedApp - App name
 */
function updateAppBadges(selectedApp) {
  if (!selectedApp || !apps[selectedApp]) {
    console.warn('[Badges] App ' + selectedApp + ' not found');
    return;
  }

  var currentDesc = apps[selectedApp]["description"] || "";

  // DEFENSIVE: Parse badge data with multiple fallback strategies
  var allBadges = { tools: [], capabilities: [] };
  var rawBadges = apps[selectedApp]["all_badges"];

  if (!rawBadges) {
    // Strategy 1: Fallback to imported_tool_groups if available
    var importedToolGroups = apps[selectedApp]["imported_tool_groups"];
    if (importedToolGroups) {
      try {
        var parsedGroups = typeof importedToolGroups === 'string' ? JSON.parse(importedToolGroups) : importedToolGroups;
        if (Array.isArray(parsedGroups) && parsedGroups.length > 0) {
          allBadges.tools = parsedGroups.map(function(group) {
            return {
              id: group.name,
              label: group.name,
              description: group.tool_count + ' tools (' + group.visibility + ')',
              icon: 'fa-toolbox',
              visibility: group.visibility || 'always',
              type: 'tools'
            };
          });
        }
      } catch (e) {
        console.warn('[Badges] Failed to parse imported_tool_groups for ' + selectedApp + ':', e);
      }
    } else {
      console.debug('[Badges] No badges defined for ' + selectedApp);
    }
  } else if (typeof rawBadges === 'object') {
    // Strategy 2: Already an object
    allBadges = rawBadges;
  } else if (typeof rawBadges === 'string') {
    // Strategy 3: JSON string
    if (rawBadges.trim() === '') {
      console.debug('[Badges] Empty badge string for ' + selectedApp);
    } else {
      try {
        var parsed = JSON.parse(rawBadges);
        if (parsed && typeof parsed === 'object') {
          if (Array.isArray(parsed.tools) && Array.isArray(parsed.capabilities)) {
            allBadges = parsed;
          } else {
            console.error('[Badges] Invalid badge structure for ' + selectedApp + ':', parsed);
            allBadges.tools = Array.isArray(parsed.tools) ? parsed.tools : [];
            allBadges.capabilities = Array.isArray(parsed.capabilities) ? parsed.capabilities : [];
          }
        }
      } catch (e) {
        console.error('[Badges] Failed to parse badges for ' + selectedApp + ':', e);
        console.debug('[Badges] Raw badge data:', rawBadges);
      }
    }
  } else {
    console.error('[Badges] Unexpected badge data type for ' + selectedApp + ':', typeof rawBadges);
  }

  // Defensive: ensure arrays
  allBadges.tools = allBadges.tools || [];
  allBadges.capabilities = allBadges.capabilities || [];

  // Filter badges
  var visibleToolBadges = filterToolBadges(allBadges.tools);
  var visibleCapabilityBadges = filterCapabilityBadges(allBadges.capabilities);

  // Separate tools by visibility
  var alwaysTools = visibleToolBadges.filter(function(b) { return b.visibility === 'always'; });
  var conditionalTools = visibleToolBadges.filter(function(b) { return b.visibility === 'conditional'; });

  // Render badges
  var badgeHtml = '';

  if (alwaysTools.length > 0) {
    badgeHtml += '<div class="badge-category">';
    badgeHtml += '<span class="badge-category-label">Tools (Always):</span>';
    badgeHtml += '<div class="badge-container">';
    badgeHtml += alwaysTools.map(renderBadge).join('');
    badgeHtml += '</div></div>';
  }

  if (conditionalTools.length > 0) {
    badgeHtml += '<div class="badge-category">';
    badgeHtml += '<span class="badge-category-label">Tools (Conditional):</span>';
    badgeHtml += '<div class="badge-container">';
    badgeHtml += conditionalTools.map(renderBadge).join('');
    badgeHtml += '</div></div>';
  }

  if (visibleCapabilityBadges.length > 0) {
    badgeHtml += '<div class="badge-category">';
    badgeHtml += '<span class="badge-category-label">Capabilities:</span>';
    badgeHtml += '<div class="badge-container">';
    badgeHtml += visibleCapabilityBadges.map(renderBadge).join('');
    badgeHtml += '</div></div>';
  }

  // Update DOM
  if (badgeHtml) {
    setBaseAppDescription(currentDesc + '<div class="tool-groups-display">' + badgeHtml + '</div>');
  } else {
    setBaseAppDescription(currentDesc);
  }
}

/**
 * Filter tool badges by conditional availability.
 * @param {Array} toolBadges
 * @returns {Array} Visible tool badges
 */
function filterToolBadges(toolBadges) {
  return toolBadges.filter(function(badge) {
    if (badge.visibility === 'conditional') {
      return isToolGroupAvailable(badge.id);
    }
    return true;
  });
}

/**
 * Return all capability badges (no filtering).
 * Badges show app CAPABILITIES, not current settings.
 * @param {Array} capabilityBadges
 * @returns {Array}
 */
function filterCapabilityBadges(capabilityBadges) {
  return capabilityBadges;
}

/**
 * Render a single badge as HTML.
 * @param {Object} badge - Badge object with icon, label, description
 * @returns {string} HTML string
 */
function renderBadge(badge) {
  var colorClass = getBadgeColorClass(badge);
  var icon = '<i class="fas ' + badge.icon + '"></i>';
  return '<span class="tool-group-badge ' + colorClass + '" title="' + badge.description + '">' +
    icon + ' ' + badge.label + '</span>';
}

/**
 * Get CSS class for badge color based on type.
 * @param {Object} badge
 * @returns {string} CSS class name
 */
function getBadgeColorClass(badge) {
  if (badge.type === 'tools') return 'badge-tools';
  if (badge.type === 'capabilities') return 'badge-capabilities';
  return 'badge-default';
}

/**
 * Get checkbox element ID for user-controlled features.
 * @param {string} featureId
 * @returns {string|undefined}
 */
function getUserControlCheckbox(featureId) {
  if ($id(featureId)) return featureId;
  var legacyMapping = { 'math': 'math', 'mermaid': 'mermaid', 'websearch': 'websearch' };
  return legacyMapping[featureId];
}

/**
 * Check if a conditional tool group is available.
 * Stub — always returns true. Implement actual check when needed.
 * @param {string} groupId
 * @returns {boolean}
 */
function isToolGroupAvailable(groupId) {
  return true;
}

// Export for browser environment
window.updateAppBadges = updateAppBadges;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    updateAppBadges,
    filterToolBadges,
    filterCapabilityBadges,
    renderBadge,
    getBadgeColorClass,
    getUserControlCheckbox,
    isToolGroupAvailable
  };
}
})();
