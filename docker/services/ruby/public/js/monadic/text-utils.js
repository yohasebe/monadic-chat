/**
 * Text Utility Functions for Monadic Chat
 *
 * Pure string manipulation helpers used across the application:
 * - removeCode: Strip code blocks, script/style/img tags
 * - removeMarkdown: Remove markdown formatting characters
 * - removeEmojis: Remove emoji characters
 * - convertString: Convert snake_case to Title Case
 *
 * Extracted from utilities.js for modularity.
 */
(function() {
'use strict';

/**
 * Remove code blocks, script/style tags, and img tags from text.
 * @param {string} text - Input text
 * @returns {string} Cleaned text
 */
function removeCode(text) {
  return text.replace(/```[\s\S]+?```|\<(script|style)[\s\S]+?<\/\1>|\<img [\s\S]+?\/>/g, " ");
}

/**
 * Remove markdown formatting characters (bold, italic, code).
 * @param {string} text - Input text
 * @returns {string} Plain text without markdown
 */
function removeMarkdown(text) {
  return text.replace(/(\*\*|__|[\*_`])/g, "");
}

/**
 * Remove emoji characters from text.
 * Falls back to returning original text if regex fails.
 * @param {string} text - Input text
 * @returns {string} Text without emojis
 */
function removeEmojis(text) {
  try {
    return text.replace(/\p{Extended_Pictographic}/gu, "");
  } catch (error) {
    return text;
  }
}

/**
 * Convert snake_case string to Title Case.
 * e.g. "initial_prompt" → "Initial Prompt"
 * @param {string} str - Snake case string
 * @returns {string} Title case string
 */
function convertString(str) {
  return str
    .split("_")
    .map(function(s) { return s.charAt(0).toUpperCase() + s.slice(1); })
    .join(" ");
}

// Export for browser environment
window.removeCode = removeCode;
window.removeMarkdown = removeMarkdown;
window.removeEmojis = removeEmojis;
window.convertString = convertString;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { removeCode, removeMarkdown, removeEmojis, convertString };
}
})();
