/**
 * Module loader helper for testing IIFE modules
 */

const fs = require('fs');
const path = require('path');
const vm = require('vm');

/**
 * Load an IIFE module in a controlled environment
 * @param {string} modulePath - Path to the module file
 * @param {Object} mockWindow - Mock window object to use
 * @returns {Object} The module's exports
 */
function loadModule(modulePath, mockWindow = {}) {
  const fullPath = path.resolve(__dirname, '..', modulePath);
  const moduleCode = fs.readFileSync(fullPath, 'utf8');
  
  // Create a sandbox environment
  const $ = mockWindow.$ || global.$ || (() => ({ width: () => 1024 }));
  const jQuery = mockWindow.jQuery || global.jQuery || $;
  
  const sandbox = {
    window: {
      ...mockWindow,
      // Ensure jQuery is available
      $: $,
      jQuery: jQuery,
      // Add any other required globals
      setTimeout: global.setTimeout,
      clearTimeout: global.clearTimeout,
      setInterval: global.setInterval,
      clearInterval: global.clearInterval,
      Date: global.Date,
      console: global.console,
      document: global.document,
      performance: mockWindow.performance || {
        now: () => Date.now(),
        timing: {},
        memory: {}
      }
    },
    $: $,  // Make $ available at top level too
    jQuery: jQuery,
    document: global.document,
    console: global.console,
    module: { exports: {} },
    require: () => ({}), // Mock require for modules that check for it
    global: {}
  };
  
  // Make window reference itself
  sandbox.window.window = sandbox.window;
  
  // Execute the module code in the sandbox
  try {
    vm.createContext(sandbox);
    vm.runInContext(moduleCode, sandbox);
  } catch (error) {
    console.error(`Error loading module ${modulePath}:`, error);
    throw error;
  }
  
  // Return the window object with the module attached
  return sandbox.window;
}

/**
 * Clean up module from window
 * @param {string} moduleName - Name of the module to clean up
 */
function cleanupModule(moduleName) {
  if (global.window && global.window[moduleName]) {
    delete global.window[moduleName];
  }
  if (window[moduleName]) {
    delete window[moduleName];
  }
}

module.exports = {
  loadModule,
  cleanupModule
};