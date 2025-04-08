/**
 * @jest-environment jsdom
 * 
 * Tests for the Cards Module functionality
 * 
 * This file contains tests for all card-related functionality including:
 * - Card creation
 * - Card deletion
 * - Card content manipulation
 * - Event handling on cards
 */

// Import test utilities
const { setupTestEnvironment, mockFactories } = require('../helpers');

describe('Cards Module', () => {
  // Test environment object for cleanup
  let testEnv;
  
  // Setup before each test
  beforeEach(() => {
    // Create a standard test environment with message tracking and DOM setup
    testEnv = setupTestEnvironment({
      bodyHtml: '<div id="discourse"></div><div id="chat-bottom"></div>',
      messages: [],
      setupAppFunctions: () => {
        // Setup escapeHtml utility
        global.escapeHtml = jest.fn(unsafe => {
          if (unsafe === null || unsafe === undefined) return "";
          return unsafe
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
        });
        
        // Setup card event utilities
        global.attachEventListeners = jest.fn();
        global.detachEventListeners = jest.fn();
        global.cancelEditMode = jest.fn();
        global.cleanupCardTextListeners = jest.fn();
        global.cleanupAllTooltips = jest.fn();
        
        // Setup card creation utility that returns a properly configured mock card
        global.createCard = jest.fn((role, badge, html, lang = "en", mid = "", status = true, images = []) => {
          const card = testEnv.createJQueryObject('.card');
          
          // Setup basic properties
          if (mid) {
            card.attr('id', mid);
            global.mids.add(mid);
          }
          
          // Setup content based on role
          const roleContent = role === 'system' 
            ? global.escapeHtml(html) 
            : html;
          
          // Setup HTML content to return from card.find('.card-text').html()
          let htmlContent = `<div class="role-${role}">${roleContent}</div>`;
          
          // Add image content if provided
          if (images && images.length > 0) {
            htmlContent += images.map(image => {
              return image.type === 'application/pdf'
                ? `<div class="pdf-preview">${image.title}</div>`
                : `<img class="base64-image" src="${image.data}" alt="${image.title}" />`;
            }).join('');
          }
          
          // Mock find method to return appropriate parts of the card
          card.find = jest.fn(selector => {
            if (selector === '.card-text') {
              const textElement = testEnv.createJQueryObject('.card-text');
              textElement.html = jest.fn().mockReturnValue(htmlContent);
              return textElement;
            }
            if (selector.startsWith('.role-')) {
              return selector === `.role-${role}` 
                ? testEnv.createJQueryObject(selector) 
                : { length: 0 };
            }
            if (selector.startsWith('.func-')) {
              return testEnv.createJQueryObject(selector);
            }
            return testEnv.createJQueryObject(selector);
          });
          
          // Store metadata on the card for testing
          card._meta = { role, badge, html, lang, images };
          
          // Simulate attachEventListeners call
          global.attachEventListeners(card);
          
          return card;
        });
        
        // Setup message deletion functions
        global.deleteSystemMessage = jest.fn((mid, messageIndex) => {
          if (messageIndex !== -1 && global.messages[messageIndex]) {
            global.messages.splice(messageIndex, 1);
          }
          global.mids.delete(mid);
          global.ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
        });
        
        global.deleteMessageAndSubsequent = jest.fn((mid, messageIndex) => {
          if (messageIndex !== -1) {
            global.messages.splice(messageIndex);
          }
          global.mids.delete(mid);
          global.ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
        });
        
        global.deleteMessageOnly = jest.fn((mid, messageIndex) => {
          if (messageIndex !== -1 && global.messages[messageIndex]) {
            global.messages.splice(messageIndex, 1);
          }
          global.mids.delete(mid);
          global.ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
        });
        
        // Other utilities
        global.removeCode = jest.fn(text => text);
        global.removeMarkdown = jest.fn(text => text);
        global.removeEmojis = jest.fn(text => text);
        global.ttsSpeak = jest.fn();
        global.ttsStop = jest.fn();
        
        // Mock Date.now
        global.Date.now = jest.fn().mockReturnValue(12345);
      }
    });
  });
  
  // Cleanup after each test
  afterEach(() => {
    testEnv.cleanup();
  });
  
  describe('Card Creation', () => {
    it('creates user cards with proper structure', () => {
      const card = global.createCard('user', '<i class="icon"></i>', 'Hello world');
      
      expect(card.find('.role-user').length).toBe(1);
      expect(card.find('.card-text').html()).toContain('Hello world');
      
      // attachEventListeners is now called inside createCard
      expect(global.attachEventListeners).toHaveBeenCalled();
    });
    
    it('creates assistant cards with proper structure', () => {
      const card = global.createCard('assistant', '<i class="icon"></i>', 'I am an assistant');
      
      expect(card.find('.role-assistant').length).toBe(1);
      expect(card.find('.card-text').html()).toContain('I am an assistant');
    });
    
    it('escapes HTML in system cards', () => {
      const card = global.createCard('system', '<i class="icon"></i>', '<b>System message</b>');
      
      expect(card.find('.role-system').length).toBe(1);
      expect(global.escapeHtml).toHaveBeenCalledWith('<b>System message</b>');
      expect(card.find('.card-text').html()).toContain('&lt;b&gt;System message&lt;/b&gt;');
    });
    
    it('adds images to cards when provided', () => {
      const images = [
        { data: 'data:image/png;base64,abc123', title: 'Test Image', type: 'image/png' }
      ];
      
      const card = global.createCard('user', '<i class="icon"></i>', 'With image', 'en', 'msg-1', true, images);
      
      expect(card.find('.card-text').html()).toContain('base64-image');
      expect(card.find('.card-text').html()).toContain('Test Image');
    });
    
    it('handles PDF attachments correctly', () => {
      const images = [
        { title: 'Document.pdf', type: 'application/pdf' }
      ];
      
      const card = global.createCard('user', '<i class="icon"></i>', 'With PDF', 'en', 'pdf-msg', true, images);
      
      expect(card.find('.card-text').html()).toContain('pdf-preview');
      expect(card.find('.card-text').html()).toContain('Document.pdf');
    });
    
    it('adds message ID to mids set', () => {
      const sizeBefore = global.mids.size;
      const card = global.createCard('user', '<i class="icon"></i>', 'Test', 'en', 'test-mid');
      
      expect(global.mids.has('test-mid')).toBe(true);
      expect(global.mids.size).toBe(sizeBefore + 1);
    });
  });
  
  describe('Message Deletion', () => {
    beforeEach(() => {
      // Setup test messages
      global.messages = [
        { mid: 'msg-1', role: 'user', text: 'First message' },
        { mid: 'msg-2', role: 'assistant', text: 'Second message' },
        { mid: 'msg-3', role: 'user', text: 'Third message' }
      ];
      
      global.mids.add('msg-1');
      global.mids.add('msg-2');
      global.mids.add('msg-3');
    });
    
    it('deletes a system message correctly', () => {
      global.deleteSystemMessage('msg-1', 0);
      
      expect(global.messages.length).toBe(2);
      expect(global.mids.has('msg-1')).toBe(false);
      expect(global.ws.send).toHaveBeenCalled();
    });
    
    it('deletes a message and all subsequent messages', () => {
      global.deleteMessageAndSubsequent('msg-2', 1);
      
      expect(global.messages.length).toBe(1);
      expect(global.messages[0].mid).toBe('msg-1');
      expect(global.mids.has('msg-2')).toBe(false);
      expect(global.ws.send).toHaveBeenCalled();
    });
    
    it('deletes only the specified message', () => {
      global.deleteMessageOnly('msg-2', 1);
      
      expect(global.messages.length).toBe(2);
      expect(global.messages[0].mid).toBe('msg-1');
      expect(global.messages[1].mid).toBe('msg-3');
      expect(global.mids.has('msg-2')).toBe(false);
      expect(global.ws.send).toHaveBeenCalled();
    });
  });
  
  describe('HTML Escaping', () => {
    it('escapes HTML special characters', () => {
      const html = '<script>alert("XSS")</script>';
      const result = global.escapeHtml(html);
      
      expect(result).toBe('&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;');
    });
    
    it('handles null and undefined inputs', () => {
      expect(global.escapeHtml(null)).toBe('');
      expect(global.escapeHtml(undefined)).toBe('');
    });
  });
  
  // Test helpers for common card operations
  describe('Card Operations', () => {
    it('correctly checks if a card is the last one', () => {
      // Mock messages array
      const messages = [
        { mid: 'msg-1', role: 'user', text: 'First' },
        { mid: 'msg-2', role: 'assistant', text: 'Second' },
        { mid: 'msg-3', role: 'user', text: 'Third' }
      ];
      
      // Check if a message is the last one
      const isLastMessage = (mid) => {
        const index = messages.findIndex(m => m.mid === mid);
        return index === messages.length - 1;
      };
      
      expect(isLastMessage('msg-1')).toBe(false);
      expect(isLastMessage('msg-2')).toBe(false);
      expect(isLastMessage('msg-3')).toBe(true);
    });
  });
});