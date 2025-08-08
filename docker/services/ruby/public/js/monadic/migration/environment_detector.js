// Environment Detection for Migration System
// Detects whether running in development, Docker, or Electron environment

(function() {
  'use strict';
  
  window.EnvironmentDetector = {
    // Detect current environment
    getEnvironment: function() {
      // Check for Electron
      if (window.electronAPI || window.electron) {
        return 'electron';
      }
      
      // Check for Docker container indicators
      if (window.location.hostname === 'localhost' && window.location.port === '4567') {
        // Could be either development or Docker
        // Check for Docker-specific markers if available
        if (this.isDockerEnvironment()) {
          return 'docker';
        }
        return 'development';
      }
      
      // Default to production if not localhost
      if (window.location.hostname !== 'localhost') {
        return 'production';
      }
      
      return 'development';
    },
    
    // Check if running in Docker container
    isDockerEnvironment: function() {
      // Check for Docker-specific indicators
      // This might need server-side assistance to be accurate
      if (window.DOCKER_ENV === true) {
        return true;
      }
      
      // Check URL for Docker-specific paths
      if (window.location.pathname.includes('/monadic/')) {
        return true;
      }
      
      return false;
    },
    
    // Get appropriate data path based on environment
    getDataPath: function(filename) {
      // In all environments, the web server serves files from /data URL path
      // which maps to either:
      // - Container: /monadic/data (mounted from ~/monadic/data)
      // - Development: ~/monadic/data (served directly)
      // The /data URL is handled by the Ruby server routing
      return `/data/${filename}`;
    },
    
    // Get WebSocket URL based on environment
    getWebSocketUrl: function() {
      const env = this.getEnvironment();
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      
      switch(env) {
        case 'electron':
          // Electron connects to Docker container
          return 'ws://localhost:4567';
          
        case 'docker':
          // Within Docker network
          return `${protocol}//localhost:4567`;
          
        case 'development':
          // Local development server
          return 'ws://localhost:4567';
          
        default:
          // Use current host
          return `${protocol}//${window.location.host}`;
      }
    },
    
    // Get storage strategy based on environment
    getStorageStrategy: function() {
      const env = this.getEnvironment();
      
      if (env === 'electron') {
        // Electron might use different storage
        if (window.electronAPI && window.electronAPI.store) {
          return 'electron-store';
        }
      }
      
      // Default to localStorage for all environments
      return 'localStorage';
    },
    
    // Safe storage operations that work across environments
    storage: {
      setItem: function(key, value) {
        const strategy = window.EnvironmentDetector.getStorageStrategy();
        
        try {
          if (strategy === 'electron-store' && window.electronAPI && window.electronAPI.store) {
            // Use Electron store
            window.electronAPI.store.set(key, value);
          } else {
            // Use localStorage
            localStorage.setItem(key, JSON.stringify(value));
          }
          return true;
        } catch (e) {
          console.error('[Storage] Failed to save:', e);
          return false;
        }
      },
      
      getItem: function(key) {
        const strategy = window.EnvironmentDetector.getStorageStrategy();
        
        try {
          if (strategy === 'electron-store' && window.electronAPI && window.electronAPI.store) {
            // Use Electron store
            return window.electronAPI.store.get(key);
          } else {
            // Use localStorage
            const item = localStorage.getItem(key);
            return item ? JSON.parse(item) : null;
          }
        } catch (e) {
          console.error('[Storage] Failed to retrieve:', e);
          return null;
        }
      },
      
      removeItem: function(key) {
        const strategy = window.EnvironmentDetector.getStorageStrategy();
        
        try {
          if (strategy === 'electron-store' && window.electronAPI && window.electronAPI.store) {
            // Use Electron store
            window.electronAPI.store.delete(key);
          } else {
            // Use localStorage
            localStorage.removeItem(key);
          }
          return true;
        } catch (e) {
          console.error('[Storage] Failed to remove:', e);
          return false;
        }
      }
    },
    
    // Get environment info for debugging
    getInfo: function() {
      return {
        environment: this.getEnvironment(),
        isDocker: this.isDockerEnvironment(),
        storageStrategy: this.getStorageStrategy(),
        webSocketUrl: this.getWebSocketUrl(),
        dataPathExample: this.getDataPath('example.txt'),
        userAgent: navigator.userAgent,
        hostname: window.location.hostname,
        port: window.location.port,
        protocol: window.location.protocol,
        pathname: window.location.pathname,
        hasElectronAPI: !!window.electronAPI,
        hasElectron: !!window.electron
      };
    },
    
    // Initialize and set up environment-specific configurations
    init: function() {
      const env = this.getEnvironment();
      
      console.log(`[Environment] Detected: ${env}`);
      
      // Set environment-specific flags
      window.IS_DEVELOPMENT = (env === 'development');
      window.IS_DOCKER = (env === 'docker');
      window.IS_ELECTRON = (env === 'electron');
      window.IS_PRODUCTION = (env === 'production');
      
      // Adjust migration settings based on environment
      if (window.MigrationConfig) {
        if (env === 'development') {
          // Enable migration in development
          console.log('[Environment] Development mode - enabling migration features');
          // Migration is already auto-enabled by MigrationConfig
        } else if (env === 'electron' || env === 'docker') {
          // Be more conservative in production environments
          console.log('[Environment] Production mode - migration disabled by default');
          window.MigrationConfig.enabled = false;
          window.MigrationConfig.features.messages = false;
          window.MigrationConfig.features.session = false;
        }
      }
      
      return this;
    }
  };
  
  // Initialize on load
  window.EnvironmentDetector.init();
  
})();