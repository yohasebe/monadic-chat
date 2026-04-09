/**
 * Centralized Error Handling Module
 * Provides consistent error formatting and logging
 */

(function(window) {
  'use strict';
  
  // Error severity levels
  const ERROR_LEVELS = {
    DEBUG: 'debug',
    INFO: 'info',
    WARNING: 'warning',
    ERROR: 'error',
    CRITICAL: 'critical'
  };
  
  // Error categories
  const ERROR_CATEGORIES = {
    NETWORK: 'Network',
    API: 'API',
    UI: 'UI',
    DATA: 'Data',
    SYSTEM: 'System',
    VALIDATION: 'Validation',
    PERMISSION: 'Permission'
  };
  
  /**
   * Format error message consistently
   * @param {Object} options - Error configuration
   * @returns {string} Formatted error message
   */
  function formatError(options) {
    const {
      category = ERROR_CATEGORIES.SYSTEM,
      message = 'An error occurred',
      details = null,
      code = null,
      suggestion = null,
      level = ERROR_LEVELS.ERROR
    } = options;
    
    // Build formatted message
    let formatted = `[${category}] ${message}`;
    
    if (code) {
      formatted += ` (Code: ${code})`;
    }
    
    if (details) {
      formatted += `\nDetails: ${details}`;
    }
    
    if (suggestion) {
      formatted += `\nSuggestion: ${suggestion}`;
    }
    
    return formatted;
  }
  
  /**
   * Log error with consistent format
   * @param {Object} options - Error configuration
   */
  function logError(options) {
    const formatted = formatError(options);
    const level = options.level || ERROR_LEVELS.ERROR;
    
    // Add timestamp
    const timestamp = new Date().toISOString();
    const logMessage = `[${timestamp}] ${formatted}`;
    
    // Log based on level
    switch (level) {
      case ERROR_LEVELS.DEBUG:
        if (window.DEBUG_MODE) {
          console.debug(logMessage);
        }
        break;
      case ERROR_LEVELS.INFO:
        console.info(logMessage);
        break;
      case ERROR_LEVELS.WARNING:
        console.warn(logMessage);
        break;
      case ERROR_LEVELS.CRITICAL:
        console.error('%c' + logMessage, 'color: red; font-weight: bold;');
        break;
      case ERROR_LEVELS.ERROR:
      default:
        console.error(logMessage);
        break;
    }
    
    // Store in error history if available
    if (window.UIState) {
      const errorHistory = window.UIState.get('errorHistory') || [];
      errorHistory.push({
        timestamp,
        level,
        message: formatted,
        options
      });
      
      // Keep only last 50 errors
      if (errorHistory.length > 50) {
        errorHistory.shift();
      }
      
      window.UIState.set('errorHistory', errorHistory);
    }
  }
  
  /**
   * Handle async errors consistently
   * @param {Function} fn - Async function to wrap
   * @param {Object} errorConfig - Error configuration for failures
   * @returns {Function} Wrapped function
   */
  function handleAsync(fn, errorConfig = {}) {
    return async function(...args) {
      try {
        return await fn.apply(this, args);
      } catch (error) {
        logError({
          ...errorConfig,
          message: error.message || errorConfig.message,
          details: error.stack,
          level: ERROR_LEVELS.ERROR
        });
        
        // Re-throw if critical
        if (errorConfig.level === ERROR_LEVELS.CRITICAL) {
          throw error;
        }
        
        return null;
      }
    };
  }
  
  /**
   * Create a safe wrapper for functions
   * @param {Function} fn - Function to wrap
   * @param {string} functionName - Name for logging
   * @returns {Function} Wrapped function
   */
  function safeWrap(fn, functionName = 'anonymous') {
    return function(...args) {
      try {
        return fn.apply(this, args);
      } catch (error) {
        logError({
          category: ERROR_CATEGORIES.SYSTEM,
          message: `Error in ${functionName}`,
          details: error.message,
          level: ERROR_LEVELS.ERROR
        });
        return null;
      }
    };
  }
  
  /**
   * Initialize global error handler
   */
  function initializeGlobalHandler() {
    // Handle uncaught errors (filter out browser extension errors)
    window.addEventListener('error', function(event) {
      // Skip errors from browser extensions
      if (event.filename && (event.filename.indexOf('chrome-extension://') !== -1 || event.filename.indexOf('moz-extension://') !== -1)) {
        return;
      }

      logError({
        category: ERROR_CATEGORIES.SYSTEM,
        message: 'Uncaught error',
        details: event.message,
        code: event.filename + ':' + event.lineno,
        level: ERROR_LEVELS.ERROR
      });
    });
    
    // Handle promise rejections (filter out browser extension errors)
    window.addEventListener('unhandledrejection', function(event) {
      // Skip errors from browser extensions (e.g., 1Password, Adobe Acrobat)
      var reason = event.reason;
      if (reason instanceof Error) {
        var stack = reason.stack || '';
        var msg = reason.message || '';
        // Filter by extension URL in stack trace
        if (stack.indexOf('chrome-extension://') !== -1 || stack.indexOf('moz-extension://') !== -1) {
          return;
        }
        // Filter known extension-caused errors (jQuery removed from project)
        if (msg === '$ is not defined' || msg === 'jQuery is not defined') {
          return;
        }
      }

      logError({
        category: ERROR_CATEGORIES.SYSTEM,
        message: 'Unhandled promise rejection',
        details: reason,
        level: ERROR_LEVELS.WARNING
      });

      // Prevent default browser behavior
      event.preventDefault();
    });
  }
  
  // Public API
  const ErrorHandler = {
    LEVELS: ERROR_LEVELS,
    CATEGORIES: ERROR_CATEGORIES,
    format: formatError,
    log: logError,
    handleAsync: handleAsync,
    safeWrap: safeWrap,
    initialize: initializeGlobalHandler
  };
  
  // Export to window
  window.ErrorHandler = ErrorHandler;
  
  // Auto-initialize if document is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeGlobalHandler);
  } else {
    initializeGlobalHandler();
  }
  
  // Export for testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ErrorHandler;
  }
  
})(typeof window !== 'undefined' ? window : this);