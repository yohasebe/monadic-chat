/**
 * Status Message Configuration Module
 *
 * Centralized configuration for #status-message styling and behavior.
 * Aligned with Electron UI design system (#status, #dockerStatus, #modeStatus).
 *
 * Design System:
 * - Background: Dark gray (#444444 light mode, #2a2a2a dark mode)
 * - Text: Colored by status type for visual differentiation
 */

(function(window) {
  'use strict';

  /**
   * Status type definitions
   * Each status type includes:
   * - icon: FontAwesome icon class (without 'fa-solid' prefix)
   * - colorLight: Text color for light mode
   * - colorDark: Text color for dark mode
   */
  const STATUS_CONFIG = {
    success: {
      icon: 'fa-circle-check',
      colorLight: '#5cd65c',  // Softer green (matches Electron UI .status.running)
      colorDark: '#7fd89f'    // Lighter green for dark mode
    },
    warning: {
      icon: 'fa-exclamation-triangle',
      colorLight: '#ffa64d',  // Softer orange (matches Electron UI .status.stopped)
      colorDark: '#ffb74d'    // Lighter orange for dark mode
    },
    danger: {
      icon: 'fa-circle-exclamation',
      colorLight: '#dc4c64',  // Red
      colorDark: '#ef5350'    // Lighter red for dark mode
    },
    info: {
      icon: 'fa-info-circle',
      colorLight: '#64b5f6',  // Blue
      colorDark: '#90caf9'    // Lighter blue for dark mode
    },
    secondary: {
      icon: 'fa-check',
      colorLight: '#757575',  // Gray
      colorDark: '#bdbdbd'    // Lighter gray for dark mode
    }
  };

  /**
   * Background colors (softer for light mode, inspired by Electron UI)
   */
  const STATUS_BG = {
    light: '#707070',  // Lighter gray (balanced for light mode UI)
    dark: '#2a2a2a'    // Darker gray for dark mode
  };

  /**
   * Border colors
   */
  const STATUS_BORDER = {
    light: '#808080',  // Slightly lighter than background
    dark: '#444444'    // Slightly lighter than dark background
  };

  /**
   * Get status configuration by type
   * @param {string} type - Status type (success, warning, danger, info, secondary)
   * @returns {Object} Status configuration or null if invalid
   */
  function getStatusConfig(type) {
    return STATUS_CONFIG[type] || null;
  }

  /**
   * Get all valid status types
   * @returns {Array} Array of valid status type names
   */
  function getValidStatusTypes() {
    return Object.keys(STATUS_CONFIG);
  }

  /**
   * Validate status type
   * @param {string} type - Status type to validate
   * @returns {boolean} True if valid, false otherwise
   */
  function isValidStatusType(type) {
    return STATUS_CONFIG.hasOwnProperty(type);
  }

  /**
   * Get icon class for status type
   * @param {string} type - Status type
   * @returns {string} Full icon class or default icon
   */
  function getIconClass(type) {
    const config = getStatusConfig(type);
    return config ? `fa-solid ${config.icon}` : 'fa-solid fa-circle-info';
  }

  /**
   * Get text color for status type and theme
   * @param {string} type - Status type
   * @param {boolean} isDark - Whether dark mode is active
   * @returns {string} Color hex value
   */
  function getTextColor(type, isDark) {
    const config = getStatusConfig(type);
    if (!config) {
      return isDark ? '#bdbdbd' : '#757575'; // Default to secondary color
    }
    return isDark ? config.colorDark : config.colorLight;
  }

  /**
   * Get background color for theme
   * @param {boolean} isDark - Whether dark mode is active
   * @returns {string} Color hex value
   */
  function getBackgroundColor(isDark) {
    return isDark ? STATUS_BG.dark : STATUS_BG.light;
  }

  /**
   * Get border color for theme
   * @param {boolean} isDark - Whether dark mode is active
   * @returns {string} Color hex value
   */
  function getBorderColor(isDark) {
    return isDark ? STATUS_BORDER.dark : STATUS_BORDER.light;
  }

  // Export to window
  window.StatusConfig = {
    STATUS_CONFIG,
    STATUS_BG,
    STATUS_BORDER,
    getStatusConfig,
    getValidStatusTypes,
    isValidStatusType,
    getIconClass,
    getTextColor,
    getBackgroundColor,
    getBorderColor
  };

  // Log initialization
  console.log('[StatusConfig] Initialized with status types:', Object.keys(STATUS_CONFIG));

})(window);
