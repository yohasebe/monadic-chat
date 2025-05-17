// Global debug configuration - loaded first
const ENABLE_DEBUG_LOGGING = false;

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
}