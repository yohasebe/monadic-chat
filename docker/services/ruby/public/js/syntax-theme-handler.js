/**
 * Syntax Theme Handler
 * This script handles the application of theme-specific classes to code blocks
 * based on the current syntax highlighting theme in settings.
 */

(function() {
  'use strict';

  // Get the current Rouge theme from page or settings
  function getCurrentTheme() {
    // First try to get it from the server-side CONFIG
    let serverTheme;
    
    try {
      // Look for an element with data attribute that might contain the theme
      // This is a fallback mechanism if CONFIG isn't directly accessible
      const themeMetaElement = document.querySelector('meta[name="rouge-theme"]');
      if (themeMetaElement) {
        serverTheme = themeMetaElement.getAttribute('content');
      }
    } catch (e) {
      console.warn('Error accessing server-side theme setting:', e);
    }
    
    // Fall back to localStorage or default if server theme not available
    const storedTheme = serverTheme || localStorage.getItem('rouge_theme') || 'pastie:light';
    
    // Store the theme in localStorage for future reference
    if (!localStorage.getItem('rouge_theme')) {
      localStorage.setItem('rouge_theme', storedTheme);
    }
    
    // Extract the theme name from the format "theme:mode"
    const themeParts = storedTheme.split(':');
    return {
      name: themeParts[0],
      mode: themeParts.length > 1 ? themeParts[1] : 'light'
    };
  }

  // Apply the theme-specific class to all highlight elements
  function applyThemeClasses() {
    const theme = getCurrentTheme();
    const highlightElements = document.querySelectorAll('.highlight');
    
    // For each highlight element, apply the appropriate theme class
    highlightElements.forEach(element => {
      // Remove any existing theme classes
      element.classList.forEach(className => {
        if (className.startsWith('highlight-')) {
          element.classList.remove(className);
        }
      });
      
      // Add the appropriate theme class
      element.classList.add(`highlight-${theme.name}`);
      
      // If it's a dark theme, add a dark class as well for any additional styling
      if (theme.mode === 'dark') {
        element.classList.add('highlight-dark-mode');
      }
    });
  }

  // Function to observe DOM changes and apply theme to new elements
  function observeDOM() {
    // Create a new observer
    const observer = new MutationObserver(mutations => {
      // Check if any mutations added highlight elements
      const needsUpdate = mutations.some(mutation => {
        return Array.from(mutation.addedNodes).some(node => {
          // Check if the node itself is a highlight or contains highlights
          if (node.nodeType === Node.ELEMENT_NODE) {
            if (node.classList && node.classList.contains('highlight')) {
              return true;
            }
            return node.querySelectorAll('.highlight').length > 0;
          }
          return false;
        });
      });
      
      // If we found highlight elements, apply theme classes
      if (needsUpdate) {
        applyThemeClasses();
      }
    });
    
    // Start observing the document body for changes
    observer.observe(document.body, {
      childList: true,
      subtree: true
    });
    
    return observer;
  }

  // Handle theme changes from settings
  function setupThemeChangeListener() {
    // Listen for local storage changes (for theme changes)
    window.addEventListener('storage', event => {
      if (event.key === 'rouge_theme') {
        applyThemeClasses();
      }
    });
    
    // Custom event for when the theme is changed via UI
    document.addEventListener('rouge-theme-changed', () => {
      applyThemeClasses();
    });
    
    // Also listen for messages from the server that might indicate theme changes
    if (window.addEventListener) {
      window.addEventListener('message', function(event) {
        if (event.data && event.data.type === 'settingsUpdated') {
          applyThemeClasses();
        }
      });
    }
  }

  // Initialize when the DOM is fully loaded
  document.addEventListener('DOMContentLoaded', () => {
    // Apply theme classes to existing elements
    applyThemeClasses();
    
    // Start observing for new elements
    const observer = observeDOM();
    
    // Set up listeners for theme changes
    setupThemeChangeListener();
  });

  // Also apply when the page finishes loading (for elements added by JavaScript)
  window.addEventListener('load', () => {
    applyThemeClasses();
  });
})();