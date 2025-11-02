/**
 * Theme Manager
 * Handles dark mode / light mode switching for Monadic Chat
 * Integrates with Electron's nativeTheme API for system theme detection
 */

(function() {
  'use strict';

  class ThemeManager {
    constructor() {
      this.currentTheme = 'light'; // 'light' or 'dark'
      this.themeSource = 'system'; // 'system', 'light', or 'dark'
      this.initialized = false;
    }

    /**
     * Initialize theme manager
     * - Detect current theme
     * - Apply theme classes
     * - Set up event listeners
     */
    async init() {
      if (this.initialized) {
        console.warn('[ThemeManager] Already initialized');
        return;
      }

      console.log('[ThemeManager] Initializing...');

      try {
        // Web UI theme is always managed independently via cookies
        // Electron native UI (window frame, dialogs) follows system preference
        this.themeSource = this.getStoredThemePreference();

        if (window.electronAPI) {
          console.log('[ThemeManager] Running in Electron mode (Web UI theme independent)');
        } else {
          console.log('[ThemeManager] Running in external browser mode');
        }

        // Determine and apply theme
        this.updateTheme();

        this.initialized = true;
        console.log('[ThemeManager] Initialized successfully');
      } catch (error) {
        console.error('[ThemeManager] Initialization error:', error);
        // Fallback to light theme
        this.applyTheme('light');
      }
    }

    /**
     * Update theme based on current theme source
     */
    updateTheme() {
      // Check system preference for 'system' theme source
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      this.currentTheme = (this.themeSource === 'system' && prefersDark) || this.themeSource === 'dark' ? 'dark' : 'light';
      this.applyTheme(this.currentTheme);
    }

    /**
     * Apply theme to the page
     * @param {string} theme - 'light' or 'dark'
     */
    applyTheme(theme) {
      console.log(`[ThemeManager] Applying theme: ${theme}`);

      const html = document.documentElement;

      if (theme === 'dark') {
        html.classList.add('dark-theme');
        html.classList.remove('light-theme');
        html.setAttribute('data-theme', 'dark');
      } else {
        html.classList.add('light-theme');
        html.classList.remove('dark-theme');
        html.setAttribute('data-theme', 'light');
      }

      this.currentTheme = theme;

      // Save preference to Cookie (both Electron and external browser modes)
      // This ensures theme persists across app restarts and Reset All operations
      this.saveThemePreference(this.themeSource);

      // Dispatch custom event for other components
      window.dispatchEvent(new CustomEvent('theme-applied', { detail: { theme } }));
    }

    /**
     * Set theme programmatically
     * @param {string} themeSource - 'system', 'light', or 'dark'
     */
    async setTheme(themeSource) {
      if (!['system', 'light', 'dark'].includes(themeSource)) {
        console.error('[ThemeManager] Invalid theme source:', themeSource);
        return false;
      }

      console.log(`[ThemeManager] Setting theme to: ${themeSource}`);
      this.themeSource = themeSource;

      // Apply theme directly (both Electron and external browser)
      // Web UI theme is independent from Electron native theme
      this.updateTheme();
      return true;
    }

    /**
     * Get stored theme preference from Cookie
     * @returns {string} Theme source
     */
    getStoredThemePreference() {
      try {
        // Use getCookie function from utilities.js
        const stored = typeof getCookie === 'function' ? getCookie('theme-preference') : null;
        if (stored && ['system', 'light', 'dark'].includes(stored)) {
          return stored;
        }
      } catch (e) {
        console.warn('[ThemeManager] Failed to read theme preference:', e);
      }
      return 'system'; // Default to system
    }

    /**
     * Save theme preference to Cookie (30 days, same as voice settings)
     * @param {string} themeSource - Theme source to save
     */
    saveThemePreference(themeSource) {
      try {
        // Use setCookie function from utilities.js (30 days expiration)
        if (typeof setCookie === 'function') {
          setCookie('theme-preference', themeSource, 30);
        }
      } catch (e) {
        console.warn('[ThemeManager] Failed to save theme preference:', e);
      }
    }

    /**
     * Get current theme
     * @returns {string} Current theme ('light' or 'dark')
     */
    getCurrentTheme() {
      return this.currentTheme;
    }

    /**
     * Get current theme source
     * @returns {string} Current theme source ('system', 'light', or 'dark')
     */
    getThemeSource() {
      return this.themeSource;
    }

    /**
     * Toggle between light and dark themes
     */
    async toggleTheme() {
      const newTheme = this.currentTheme === 'light' ? 'dark' : 'light';
      return await this.setTheme(newTheme);
    }
  }

  // Create global instance
  const themeManager = new ThemeManager();
  window.themeManager = themeManager;

  // Auto-initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      themeManager.init().catch(err => console.error('[ThemeManager] Init failed:', err));
    });
  } else {
    // DOM already loaded
    themeManager.init().catch(err => console.error('[ThemeManager] Init failed:', err));
  }

  // Listen for system theme changes (both Electron and external browser)
  // Web UI theme is independent and always checks system preference
  const darkModeQuery = window.matchMedia('(prefers-color-scheme: dark)');
  darkModeQuery.addEventListener('change', (e) => {
    if (themeManager.getThemeSource() === 'system') {
      themeManager.updateTheme();
    }
  });
})();
