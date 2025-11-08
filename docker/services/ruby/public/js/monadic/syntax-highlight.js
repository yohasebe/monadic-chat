/**
 * Syntax highlighting helper using highlight.js
 * Abstraction layer for easy library switching in the future
 */

(function(window) {
  'use strict';

  const SyntaxHighlight = {
    /**
     * Apply syntax highlighting to code blocks in container
     * @param {HTMLElement} container - Container element with code blocks
     */
    apply: function(container) {
      if (typeof hljs === 'undefined') {
        console.warn('highlight.js not loaded, skipping syntax highlighting');
        return;
      }

      // Find code blocks that haven't been highlighted yet
      const codeBlocks = container.querySelectorAll('pre code:not(.hljs)');

      codeBlocks.forEach(block => {
        try {
          hljs.highlightElement(block);
        } catch (err) {
          console.error('Failed to highlight code block:', err);
          // Error時も素のコードは表示される
        }
      });
    },

    /**
     * Re-highlight all code blocks (for theme changes)
     * @param {HTMLElement} container - Container element
     */
    reapply: function(container) {
      if (typeof hljs === 'undefined') {
        return;
      }

      const codeBlocks = container.querySelectorAll('pre code.hljs');
      codeBlocks.forEach(block => {
        // Remove hljs classes to force re-highlight
        block.className = block.className.replace(/\bhljs\b/g, '').trim();
        try {
          hljs.highlightElement(block);
        } catch (err) {
          console.error('Failed to re-highlight code block:', err);
        }
      });
    },

    /**
     * Change highlight.js theme
     * @param {string} themeName - Theme name (e.g., 'github', 'monokai')
     */
    changeTheme: function(themeName) {
      const themeLink = document.getElementById('hljs-theme');
      if (!themeLink) {
        console.warn('hljs-theme link element not found');
        return;
      }

      const newHref = `/vendor/hljs/${themeName}.min.css`;
      if (themeLink.href !== newHref) {
        themeLink.href = newHref;

        // Re-highlight after theme change
        setTimeout(() => {
          this.reapply(document.body);
        }, 100);
      }
    }
  };

  // Export to global scope
  window.SyntaxHighlight = SyntaxHighlight;

  // Auto-highlight on DOMContentLoaded
  document.addEventListener('DOMContentLoaded', () => {
    SyntaxHighlight.apply(document.body);
  });

})(window);
