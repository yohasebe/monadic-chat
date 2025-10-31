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
        // Check if running in Electron
        if (window.electronAPI && typeof window.electronAPI.getTheme === 'function') {
          // Get initial theme from Electron
          this.themeSource = await window.electronAPI.getTheme();
          console.log(`[ThemeManager] Initial theme source: ${this.themeSource}`);

          // Listen for theme changes from Electron
          window.electronAPI.onThemeChanged(this.handleThemeChanged.bind(this));
        } else {
          // Running in external browser - use stored preference or system preference
          console.log('[ThemeManager] Running in external browser mode');
          this.themeSource = this.getStoredThemePreference();
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
     * Handle theme changed event from Electron
     * @param {Object} data - Theme change data
     * @param {boolean} data.shouldUseDarkColors - Whether to use dark colors
     * @param {string} data.themeSource - Theme source ('system', 'light', or 'dark')
     */
    handleThemeChanged(data) {
      console.log('[ThemeManager] Theme changed:', data);
      this.themeSource = data.themeSource;

      // Determine theme based on theme source
      if (this.themeSource === 'system') {
        this.currentTheme = data.shouldUseDarkColors ? 'dark' : 'light';
      } else {
        this.currentTheme = this.themeSource;
      }

      this.applyTheme(this.currentTheme);
    }

    /**
     * Update theme based on current theme source
     */
    updateTheme() {
      // In Electron, theme will be updated via IPC event
      // In external browser, check system preference
      if (!window.electronAPI) {
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        this.currentTheme = (this.themeSource === 'system' && prefersDark) || this.themeSource === 'dark' ? 'dark' : 'light';
        this.applyTheme(this.currentTheme);
      }
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

      // Save preference for external browser mode
      if (!window.electronAPI) {
        this.saveThemePreference(this.themeSource);
      }

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

      // In Electron, use IPC to set theme
      if (window.electronAPI && typeof window.electronAPI.setTheme === 'function') {
        try {
          const result = await window.electronAPI.setTheme(themeSource);
          if (result.success) {
            console.log('[ThemeManager] Theme set successfully:', result.theme);
            return true;
          } else {
            console.error('[ThemeManager] Failed to set theme:', result.error);
            return false;
          }
        } catch (error) {
          console.error('[ThemeManager] Error setting theme:', error);
          return false;
        }
      } else {
        // External browser - apply directly
        this.updateTheme();
        return true;
      }
    }

    /**
     * Get stored theme preference from localStorage
     * @returns {string} Theme source
     */
    getStoredThemePreference() {
      try {
        const stored = localStorage.getItem('theme-preference');
        if (stored && ['system', 'light', 'dark'].includes(stored)) {
          return stored;
        }
      } catch (e) {
        console.warn('[ThemeManager] Failed to read theme preference:', e);
      }
      return 'system'; // Default to system
    }

    /**
     * Save theme preference to localStorage
     * @param {string} themeSource - Theme source to save
     */
    saveThemePreference(themeSource) {
      try {
        if (typeof StorageHelper !== 'undefined' && StorageHelper.safeSetItem) {
          StorageHelper.safeSetItem('theme-preference', themeSource);
        } else {
          localStorage.setItem('theme-preference', themeSource);
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

  // Listen for system theme changes in external browser
  if (!window.electronAPI) {
    const darkModeQuery = window.matchMedia('(prefers-color-scheme: dark)');
    darkModeQuery.addEventListener('change', (e) => {
      if (themeManager.getThemeSource() === 'system') {
        themeManager.updateTheme();
      }
    });
  }
})();
