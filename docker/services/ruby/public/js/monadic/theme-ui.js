/**
 * Theme UI Controller
 * Handles theme toggle button interactions and updates UI state
 */

(function() {
  'use strict';

  // Wait for both DOM and themeManager to be ready
  function init() {
    if (!window.themeManager) {
      console.warn('[ThemeUI] ThemeManager not available yet, retrying...');
      setTimeout(init, 100);
      return;
    }

    console.log('[ThemeUI] Initializing theme UI controls');

    const themeSystemBtn = document.getElementById('theme-system');
    const themeLightBtn = document.getElementById('theme-light');
    const themeDarkBtn = document.getElementById('theme-dark');

    if (!themeSystemBtn || !themeLightBtn || !themeDarkBtn) {
      console.warn('[ThemeUI] Theme buttons not found in DOM');
      return;
    }

    // Set up event listeners
    themeSystemBtn.addEventListener('click', () => {
      console.log('[ThemeUI] System theme selected');
      window.themeManager.setTheme('system').then(() => {
        updateButtonStates('system');
      });
    });

    themeLightBtn.addEventListener('click', () => {
      console.log('[ThemeUI] Light theme selected');
      window.themeManager.setTheme('light').then(() => {
        updateButtonStates('light');
      });
    });

    themeDarkBtn.addEventListener('click', () => {
      console.log('[ThemeUI] Dark theme selected');
      window.themeManager.setTheme('dark').then(() => {
        updateButtonStates('dark');
      });
    });

    // Update button states based on current theme
    function updateButtonStates(activeTheme) {
      // Remove active class from all buttons
      themeSystemBtn.classList.remove('active', 'theme-selected');
      themeLightBtn.classList.remove('active', 'theme-selected');
      themeDarkBtn.classList.remove('active', 'theme-selected');

      // Add active class to the selected button (using theme-selected instead of btn-primary)
      if (activeTheme === 'system') {
        themeSystemBtn.classList.add('active', 'theme-selected');
      } else if (activeTheme === 'light') {
        themeLightBtn.classList.add('active', 'theme-selected');
      } else if (activeTheme === 'dark') {
        themeDarkBtn.classList.add('active', 'theme-selected');
      }
    }

    // Initialize button states
    const currentThemeSource = window.themeManager.getThemeSource();
    updateButtonStates(currentThemeSource);

    // Listen for theme changes (from system or other sources)
    window.addEventListener('theme-applied', (event) => {
      const currentThemeSource = window.themeManager.getThemeSource();
      updateButtonStates(currentThemeSource);
    });

    console.log('[ThemeUI] Theme UI controls initialized');
  }

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
