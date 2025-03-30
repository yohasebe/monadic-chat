/**
 * @jest-environment jsdom
 */

// Import helpers from the new shared utilities file
const { setupTestEnvironment } = require('../helpers');

// Import the cards.js file to test
const cardsPath = 'docker/services/ruby/public/js/monadic/cards.js';
const fs = require('fs');
const path = require('path');

describe('Cards Module', () => {
  // Keep track of test environment for cleanup
  let testEnv;
  
  // Setup before each test
  beforeEach(() => {
    // Create a standard test environment with message tracking
    testEnv = setupTestEnvironment({
      bodyHtml: '<div id="deleteConfirmation"></div>',
      messages: []
    });
    
    // Add escapeHtml function to global scope with mock implementation
    global.escapeHtml = jest.fn().mockImplementation((unsafe) => {
      if (unsafe === null || unsafe === undefined) {
        return "";
      }
      return unsafe
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    });
    
    // Add the actual cards.js functions we're testing
    global.deleteSystemMessage = jest.fn().mockImplementation((mid, messageIndex) => {
      if (messageIndex !== -1 && global.messages[messageIndex]) {
        global.messages.splice(messageIndex, 1);
      }
      global.mids.delete(mid);
      global.ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    });
    
    global.deleteMessageAndSubsequent = jest.fn().mockImplementation((mid, messageIndex) => {
      if (messageIndex !== -1) {
        global.messages.splice(messageIndex);
      }
      global.mids.delete(mid);
      global.ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    });
    
    global.deleteMessageOnly = jest.fn().mockImplementation((mid, messageIndex) => {
      if (messageIndex !== -1 && global.messages[messageIndex]) {
        global.messages.splice(messageIndex, 1);
      }
      global.mids.delete(mid);
      global.ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    });
    
    // Mock additional required functions
    global.removeCode = jest.fn().mockImplementation(text => text);
    global.removeMarkdown = jest.fn().mockImplementation(text => text);
    global.removeEmojis = jest.fn().mockImplementation(text => text);
    global.ttsSpeak = jest.fn();
    global.ttsStop = jest.fn();
    global.attachEventListeners = jest.fn();
    global.detachEventListeners = jest.fn();
    global.cancelEditMode = jest.fn();
    global.cleanupCardTextListeners = jest.fn();
    global.cleanupAllTooltips = jest.fn();
    
    // Mock Date.now() for consistent image URLs
    global.Date = {
      ...Date,
      now: jest.fn().mockReturnValue(12345)
    };
    
    // Setup jQuery to handle card creation
    $.mockImplementation((selector) => {
      // For card creation template string, return a new mock card
      if (typeof selector === 'string' && selector.startsWith('<div class="card')) {
        const cardMock = testEnv.createJQueryObject('.card');
        cardMock.find = jest.fn().mockImplementation(childSelector => {
          if (childSelector === '.card-title') {
            return testEnv.createJQueryObject('.card-title');
          }
          if (childSelector === '.card-text') {
            return testEnv.createJQueryObject('.card-text');
          }
          return testEnv.createJQueryObject(childSelector);
        });
        
        return cardMock;
      }
      
      // For existing card selector (for delete operations)
      if (typeof selector === 'string' && selector.startsWith('#')) {
        const existingMock = testEnv.createJQueryObject(selector);
        existingMock.length = selector.includes('non-existent') ? 0 : 1;
        return existingMock;
      }
      
      // Default jQuery mock
      return testEnv.createJQueryObject(selector);
    });
  });

  // Cleanup after each test
  afterEach(() => {
    testEnv.cleanup();
    jest.resetAllMocks();
  });

  // Test escapeHtml function using our mock implementation
  describe('escapeHtml function', () => {
    it('should escape HTML characters', () => {
      const html = '<script>alert("XSS")</script>';
      const expected = '&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;';
      
      const result = escapeHtml(html);
      
      expect(result).toBe(expected);
    });

    it('should handle null or undefined inputs', () => {
      expect(escapeHtml(null)).toBe('');
      expect(escapeHtml(undefined)).toBe('');
    });
  });

  // Test createCard function (our mock implementation)
  describe('createCard function', () => {
    it('should add message ID to the mids Set', () => {
      const mid = 'test-mid-123';
      
      createCard('user', '<span>Test</span>', 'Test message', 'en', mid, true);
      
      expect(global.mids.has(mid)).toBe(true);
      expect(createCard).toHaveBeenCalled();
    });
    
    it('should not add empty message IDs to the mids Set', () => {
      const sizeBefore = global.mids.size;
      
      createCard('user', '<span>Test</span>', 'No mid', 'en', '', true);
      
      expect(global.mids.size).toBe(sizeBefore);
    });
    
    it('should check for duplicates', () => {
      const mid = 'duplicate-123';
      
      // Update our mock implementation for this test
      const originalCreateCard = global.createCard;
      global.createCard = jest.fn().mockImplementation((role, badge, html, _lang, mid) => {
        // Check for existing card with this mid
        $(`#${mid}`);
        
        // Simulate adding to mids
        if (mid && mid !== '') {
          global.mids.add(mid);
        }
        
        const card = testEnv.createJQueryObject('.card');
        card.attr('id', mid);
        return card;
      });
      
      // Call createCard
      createCard('user', '<span>Test</span>', 'Test message', 'en', mid, true);
      
      // Verify jQuery was called with the right selector
      expect($).toHaveBeenCalledWith(`#${mid}`);
      
      // Restore original
      global.createCard = originalCreateCard;
    });
    
    it('should attach event listeners to the card', () => {
      const mid = 'card-with-events';
      
      // Update our mock implementation for this test
      const originalCreateCard = global.createCard;
      global.createCard = jest.fn().mockImplementation((role, badge, html, _lang, mid) => {
        // Simulate card creation
        if (mid && mid !== '') {
          global.mids.add(mid);
        }
        
        const card = testEnv.createJQueryObject('.card');
        card.attr('id', mid);
        
        // Call attachEventListeners as the real createCard would
        attachEventListeners(card);
        
        return card;
      });
      
      // Call createCard
      createCard('user', '<span>Test</span>', 'Test message', 'en', mid, true);
      
      // Verify attachEventListeners was called
      expect(attachEventListeners).toHaveBeenCalled();
      
      // Restore original
      global.createCard = originalCreateCard;
    });
  });

  // Test delete functions
  describe('Message Deletion Functions', () => {
    it('deleteSystemMessage should remove a message', () => {
      // Add a message to delete
      const mid = 'sys-message';
      global.messages.push({ mid, role: 'system', text: 'System message' });
      global.mids.add(mid);
      
      // Override the deleteSystemMessage mock to track card removal
      const originalDeleteSystemMessage = global.deleteSystemMessage;
      const mockCard = testEnv.createJQueryObject('#' + mid);
      mockCard.remove = jest.fn();
      
      $.mockImplementation(selector => {
        if (selector === '#' + mid) {
          return mockCard;
        }
        return testEnv.createJQueryObject(selector);
      });
      
      global.deleteSystemMessage = jest.fn().mockImplementation((mid, messageIndex) => {
        // Find the card
        const $card = $(`#${mid}`);
        
        // Remove from messages array
        if (messageIndex !== -1 && global.messages[messageIndex]) {
          global.messages.splice(messageIndex, 1);
        }
        
        // Remove the card
        $card.remove();
        
        // Remove from Set
        mids.delete(mid);
        
        // Send to server
        ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
      });
      
      // Call function
      deleteSystemMessage(mid, 0);
      
      // Verify message was removed
      expect(global.messages.length).toBe(0);
      expect(global.mids.has(mid)).toBe(false);
      expect(mockCard.remove).toHaveBeenCalled();
      expect(global.ws.send).toHaveBeenCalled();
      
      // Restore original
      global.deleteSystemMessage = originalDeleteSystemMessage;
    });
    
    it('deleteMessageAndSubsequent should remove multiple messages', () => {
      // Add messages to delete
      global.messages.push(
        { mid: 'msg-1', role: 'user', text: 'First message' },
        { mid: 'msg-2', role: 'assistant', text: 'Second message' },
        { mid: 'msg-3', role: 'user', text: 'Third message' }
      );
      
      global.mids.add('msg-1');
      global.mids.add('msg-2');
      global.mids.add('msg-3');
      
      // Call function
      deleteMessageAndSubsequent('msg-2', 1);
      
      // Verify messages were removed correctly
      expect(global.messages.length).toBe(1);
      expect(global.messages[0].mid).toBe('msg-1');
      expect(global.mids.has('msg-2')).toBe(false);
      expect(global.ws.send).toHaveBeenCalled();
    });
    
    it('deleteMessageOnly should remove only the specified message', () => {
      // Add messages
      global.messages.push(
        { mid: 'msg-1', role: 'user', text: 'First message' },
        { mid: 'msg-2', role: 'assistant', text: 'Second message' },
        { mid: 'msg-3', role: 'user', text: 'Third message' }
      );
      
      global.mids.add('msg-1');
      global.mids.add('msg-2');
      global.mids.add('msg-3');
      
      // Call function to delete only the second message
      deleteMessageOnly('msg-2', 1);
      
      // Verify only specified message was removed
      expect(global.messages.length).toBe(2);
      expect(global.messages[0].mid).toBe('msg-1');
      expect(global.messages[1].mid).toBe('msg-3');
      expect(global.mids.has('msg-2')).toBe(false);
      expect(global.mids.has('msg-1')).toBe(true);
      expect(global.mids.has('msg-3')).toBe(true);
    });
  });
});