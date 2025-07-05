/**
 * Test Utilities for No-Mock UI Testing
 * 
 * Provides helper functions for testing real DOM interactions,
 * WebSocket communication, and async operations.
 */

// Import ws module with better error handling
let WebSocket, Server;

try {
  const ws = require('ws');
  // Try to get WebSocket and Server from the module
  WebSocket = ws.WebSocket || ws;
  Server = ws.Server || ws.WebSocketServer;
  
  // If Server is still not available, try creating it directly
  if (!Server && ws.Server === undefined) {
    // For older versions of ws, it might be exported directly
    Server = ws;
  }
} catch (error) {
  console.error('Error loading ws module:', error);
}
const fs = require('fs').promises;
const path = require('path');

/**
 * Wait for an element to appear in the DOM
 * @param {string} selector - CSS selector
 * @param {number} timeout - Maximum wait time in ms
 * @returns {Promise<Element>} The found element
 */
async function waitForElement(selector, timeout = 5000) {
  const startTime = Date.now();
  
  while (Date.now() - startTime < timeout) {
    const element = document.querySelector(selector);
    if (element) {
      return element;
    }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  
  throw new Error(`Element ${selector} not found within ${timeout}ms`);
}

/**
 * Wait for a condition to be true
 * @param {Function} condition - Function that returns boolean
 * @param {number} timeout - Maximum wait time in ms
 * @param {string} message - Error message if timeout
 */
async function waitFor(condition, timeout = 5000, message = 'Condition not met') {
  const startTime = Date.now();
  
  while (Date.now() - startTime < timeout) {
    if (condition()) {
      return;
    }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  
  throw new Error(`${message} within ${timeout}ms`);
}

/**
 * Trigger a real DOM event
 * @param {Element|string} elementOrSelector - Element or CSS selector
 * @param {string} eventType - Event type (click, input, etc.)
 * @param {Object} eventData - Additional event properties
 */
function triggerEvent(elementOrSelector, eventType, eventData = {}) {
  const element = typeof elementOrSelector === 'string' 
    ? document.querySelector(elementOrSelector)
    : elementOrSelector;
    
  if (!element) {
    throw new Error('Element not found');
  }
  
  let event;
  
  // Create appropriate event type
  if (eventType === 'click' || eventType === 'dblclick') {
    event = new MouseEvent(eventType, {
      bubbles: true,
      cancelable: true,
      view: window,
      ...eventData
    });
  } else if (eventType === 'input' || eventType === 'change') {
    event = new Event(eventType, {
      bubbles: true,
      cancelable: true,
      ...eventData
    });
  } else if (eventType.startsWith('key')) {
    event = new KeyboardEvent(eventType, {
      bubbles: true,
      cancelable: true,
      ...eventData
    });
  } else {
    event = new CustomEvent(eventType, {
      bubbles: true,
      cancelable: true,
      detail: eventData
    });
  }
  
  element.dispatchEvent(event);
}

/**
 * Set input value and trigger appropriate events
 * @param {Element|string} elementOrSelector - Input element or selector
 * @param {string} value - Value to set
 */
function setInputValue(elementOrSelector, value) {
  const element = typeof elementOrSelector === 'string'
    ? document.querySelector(elementOrSelector)
    : elementOrSelector;
    
  if (!element) {
    throw new Error('Input element not found');
  }
  
  element.value = value;
  triggerEvent(element, 'input');
  triggerEvent(element, 'change');
}

/**
 * Create a test WebSocket server
 * @param {number} port - Port to listen on
 * @returns {Object} Server object with utilities
 */
function createTestWSServer(port = 8081) {
  // Try a different approach - use the ws module directly
  const ws = require('ws');
  
  // Create server using the most compatible method
  let server;
  try {
    if (ws.Server) {
      server = new ws.Server({ port });
    } else if (ws.WebSocketServer) {
      server = new ws.WebSocketServer({ port });
    } else {
      // Fallback - try using ws directly as constructor
      server = new ws({ port });
    }
  } catch (error) {
    console.error('Failed to create WebSocket server:', error);
    throw new Error('Could not create WebSocket server. Check ws module installation.');
  }
  const connections = [];
  const messages = [];
  
  server.on('connection', (ws) => {
    connections.push(ws);
    
    ws.on('message', (data) => {
      const message = JSON.parse(data.toString());
      messages.push(message);
      
      // Echo back for testing
      if (message.echo) {
        ws.send(JSON.stringify({
          type: 'echo',
          content: message.content
        }));
      }
    });
    
    ws.on('close', () => {
      const index = connections.indexOf(ws);
      if (index > -1) {
        connections.splice(index, 1);
      }
    });
  });
  
  return {
    server,
    
    // Get all received messages
    getMessages: () => [...messages],
    
    // Clear message history
    clearMessages: () => {
      messages.length = 0;
    },
    
    // Send message to all clients
    broadcast: (message) => {
      const data = JSON.stringify(message);
      connections.forEach(ws => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(data);
        }
      });
    },
    
    // Wait for specific message
    waitForMessage: async (matcher, timeout = 5000) => {
      const startTime = Date.now();
      
      while (Date.now() - startTime < timeout) {
        const found = messages.find(msg => {
          if (typeof matcher === 'function') {
            return matcher(msg);
          }
          return msg.type === matcher;
        });
        
        if (found) {
          return found;
        }
        
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      
      throw new Error(`Message not received within ${timeout}ms`);
    },
    
    // Close server
    close: () => {
      return new Promise((resolve) => {
        connections.forEach(ws => ws.close());
        server.close(resolve);
      });
    }
  };
}

/**
 * Load an HTML fixture file
 * @param {string} fixtureName - Name of fixture file
 * @returns {Promise<string>} HTML content
 */
async function loadFixture(fixtureName) {
  const fixturePath = path.join(__dirname, '../fixtures', fixtureName);
  try {
    return await fs.readFile(fixturePath, 'utf8');
  } catch (error) {
    throw new Error(`Fixture ${fixtureName} not found at ${fixturePath}`);
  }
}

/**
 * Load and execute a JavaScript file in the test environment
 * @param {string} scriptPath - Path to script file
 */
async function loadScript(scriptPath) {
  const fullPath = path.join(__dirname, '../../../docker/services/ruby/public', scriptPath);
  try {
    const scriptContent = await fs.readFile(fullPath, 'utf8');
    const scriptEl = document.createElement('script');
    scriptEl.textContent = scriptContent;
    document.head.appendChild(scriptEl);
  } catch (error) {
    throw new Error(`Script ${scriptPath} not found at ${fullPath}`);
  }
}

/**
 * Wait for jQuery to be ready
 */
async function waitForJQuery() {
  await waitFor(() => window.$ && window.$.fn, 5000, 'jQuery not loaded');
  
  // Wait for document ready
  return new Promise((resolve) => {
    if (window.$.isReady) {
      resolve();
    } else {
      window.$(resolve);
    }
  });
}

/**
 * Simulate file selection in an input
 * @param {string} selector - File input selector
 * @param {Object} fileData - File properties
 */
function selectFile(selector, fileData) {
  const input = document.querySelector(selector);
  if (!input) {
    throw new Error(`File input ${selector} not found`);
  }
  
  // Create a fake File object
  const file = new File([fileData.content || ''], fileData.name || 'test.txt', {
    type: fileData.type || 'text/plain'
  });
  
  // Create a fake FileList
  const fileList = {
    0: file,
    length: 1,
    item: (index) => index === 0 ? file : null
  };
  
  // Override the files property
  Object.defineProperty(input, 'files', {
    value: fileList,
    writable: false
  });
  
  // Trigger change event
  triggerEvent(input, 'change');
  
  return file;
}

/**
 * Get text content of an element, trimmed and normalized
 * @param {string} selector - CSS selector
 * @returns {string} Normalized text content
 */
function getElementText(selector) {
  const element = document.querySelector(selector);
  if (!element) {
    return '';
  }
  return element.textContent.trim().replace(/\s+/g, ' ');
}

/**
 * Check if element is visible
 * @param {Element|string} elementOrSelector - Element or selector
 * @returns {boolean} True if visible
 */
function isVisible(elementOrSelector) {
  const element = typeof elementOrSelector === 'string'
    ? document.querySelector(elementOrSelector)
    : elementOrSelector;
    
  if (!element) {
    return false;
  }
  
  const style = window.getComputedStyle(element);
  return style.display !== 'none' && 
         style.visibility !== 'hidden' &&
         style.opacity !== '0';
}

module.exports = {
  waitForElement,
  waitFor,
  triggerEvent,
  setInputValue,
  createTestWSServer,
  loadFixture,
  loadScript,
  waitForJQuery,
  selectFile,
  getElementText,
  isVisible
};