/**
 * Status Message Configuration Module
 *
 * The kinds of #status-message, each with its icon and its text color. The
 * color is a palette token (tokens.css), so it follows the theme by itself.
 */

(function(window) {
  'use strict';

  const STATUS_CONFIG = {
    success: { icon: 'fa-circle-check', color: 'var(--pal-green-text)' },
    warning: { icon: 'fa-exclamation-triangle', color: 'var(--pal-amber-text)' },
    danger: { icon: 'fa-circle-exclamation', color: 'var(--pal-red-text)' },
    info: { icon: 'fa-info-circle', color: 'var(--pal-accent-text)' },
    secondary: { icon: 'fa-check', color: 'var(--text-secondary)' }
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
   * Text color for a status type (a CSS value), the secondary one for an
   * unknown type.
   * @param {string} type - Status type
   * @returns {string} CSS color value
   */
  function getTextColor(type) {
    const config = getStatusConfig(type) || STATUS_CONFIG.secondary;
    return config.color;
  }

  // Export to window
  window.StatusConfig = {
    STATUS_CONFIG,
    getStatusConfig,
    getValidStatusTypes,
    isValidStatusType,
    getIconClass,
    getTextColor
  };

})(window);
