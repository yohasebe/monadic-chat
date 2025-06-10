// Global debug configuration - loaded first
// Can be enabled by adding ?debug=true to URL or setting localStorage
const urlParams = new URLSearchParams(window.location.search);
const ENABLE_DEBUG_LOGGING = urlParams.get('debug') === 'true' || 
                            localStorage.getItem('ENABLE_DEBUG_LOGGING') === 'true' ||
                            false;

// Override console methods to respect debug flag
const originalConsole = {
  log: console.log,
  error: console.error,
  warn: console.warn,
  debug: console.debug
};

if (!ENABLE_DEBUG_LOGGING) {
  console.log = function() {};
  console.debug = function() {};
  // Keep error and warn for important messages
  // console.error = function() {};
  // console.warn = function() {};
} else {
  // Notify that debug mode is enabled
  console.info('%c🐛 Debug mode enabled', 'color: #4CAF50; font-weight: bold');
  console.info('To disable: localStorage.removeItem("ENABLE_DEBUG_LOGGING")');
}