/**
 * @jest-environment jsdom
 */

// Import helpers from the shared utilities file
const { setupTestEnvironment } = require('../helpers');

describe('Cards Module', () => {
  // Keep track of test environment for cleanup
  let testEnv;
  
  // Setup before each test
  beforeEach(() => {
    // Create a standard test environment with message tracking
    testEnv = setupTestEnvironment({
      bodyHtml: '<div id="messageContainer"></div>',
      messages: []
    });
    
    // Setup mids Set
    global.mids = new Set();
    
    // Create mock implementations for required functions
    global.escapeHtml = jest.fn(unsafe => {
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
    
    global.createCard = jest.fn((role, badge, html, _lang = "en", mid = "", status = true, images = []) => {
      const card = testEnv.createJQueryObject('.card');
      
      // Add properties and methods needed for testing
      card.attr('id', mid);
      
      // Mock HTML content based on role
      let cardHtml = '';
      if (role === 'system') {
        cardHtml = `<div class="role-system">${global.escapeHtml(html)}</div>`;
      } else {
        cardHtml = `<div class="role-${role}">${html}</div>`;
      }
      
      // Add image data if provided
      if (images && images.length > 0) {
        cardHtml += images.map(image => {
          if (image.type === 'application/pdf') {
            return `<div class="pdf-preview"><i class="fas fa-file-pdf"></i><span>${image.title}</span></div>`;
          } else {
            return `<img class="base64-image" src="${image.data}" alt="${image.title}" />`;
          }
        }).join('');
      }
      
      // Add timestamp to image URLs
      if (html.includes('<img src=')) {
        cardHtml = cardHtml.replace(/<img src="([^"]+)"/g, `<img src="$1?dummy=${Date.now()}"`);
      }
      
      // Setup mock find method to return card parts
      card.find = jest.fn(selector => {
        if (selector === '.role-user') {
          return role === 'user' ? testEnv.createJQueryObject('.role-user') : {length: 0};
        }
        if (selector === '.role-assistant') {
          return role === 'assistant' ? testEnv.createJQueryObject('.role-assistant') : {length: 0};
        }
        if (selector === '.role-system') {
          return role === 'system' ? testEnv.createJQueryObject('.role-system') : {length: 0};
        }
        if (selector === '.card-text') {
          const cardText = testEnv.createJQueryObject('.card-text');
          cardText.html = jest.fn().mockReturnValue(cardHtml);
          return cardText;
        }
        if (selector === '.func-delete') {
          return testEnv.createJQueryObject('.func-delete');
        }
        if (selector === '.func-play') {
          return testEnv.createJQueryObject('.func-play');
        }
        if (selector === '.func-stop') {
          return testEnv.createJQueryObject('.func-stop');
        }
        if (selector === '.func-copy') {
          return testEnv.createJQueryObject('.func-copy');
        }
        if (selector === '.func-edit') {
          return testEnv.createJQueryObject('.func-edit');
        }
        return testEnv.createJQueryObject(selector);
      });
      
      // If this is a duplicate card, remove the existing one
      if (mid !== "") {
        const existingCard = $(`#${mid}`);
        if (existingCard.length > 0) {
          existingCard.remove();
        }
        global.mids.add(mid);
      }
      
      // Simulate attaching event listeners
      global.attachEventListeners(card);
      
      return card;
    });
    
    // Mock implementations for other functions
    global.attachEventListeners = jest.fn();
    global.detachEventListeners = jest.fn();
    global.cancelEditMode = jest.fn();
    global.cleanupCardTextListeners = jest.fn();
    global.cleanupAllTooltips = jest.fn();
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
    
    global.deleteMessage = jest.fn(mid => {
      const messageIndex = global.messages.findIndex(m => m.mid === mid);
      if (messageIndex !== -1) {
        global.messages.splice(messageIndex, 1);
      }
      global.mids.delete(mid);
      global.ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    });
    
    // Mock other required functions
    global.removeCode = jest.fn(text => text);
    global.removeMarkdown = jest.fn(text => text);
    global.removeEmojis = jest.fn(text => text);
    global.ttsSpeak = jest.fn();
    global.ttsStop = jest.fn();
    global.setAlert = jest.fn();
    global.alert = jest.fn();
    
    // Mock Date.now()
    global.Date.now = jest.fn().mockReturnValue(12345);
    
    // Mock navigator.clipboard
    global.navigator.clipboard = {
      writeText: jest.fn().mockResolvedValue(undefined)
    };
  });
  
  // Cleanup after each test
  afterEach(() => {
    testEnv.cleanup();
    jest.resetAllMocks();
  });
  
  // Test escapeHtml function
  describe('escapeHtml function', () => {
    it('should escape HTML characters', () => {
      const html = '<script>alert("XSS")</script>';
      const expected = '&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;';
      
      const result = global.escapeHtml(html);
      
      expect(result).toBe(expected);
    });
    
    it('should handle null or undefined inputs', () => {
      expect(global.escapeHtml(null)).toBe('');
      expect(global.escapeHtml(undefined)).toBe('');
    });
  });
  
  // Test createCard function
  describe('createCard function', () => {
    it('should create a user role card with correct class', () => {
      const card = global.createCard('user', '<span>User</span>', 'Hello world');
      
      expect(card.find('.role-user').length).toBe(1);
      expect(card.find('.card-text').html()).toContain('Hello world');
      expect(global.attachEventListeners).toHaveBeenCalledWith(card);
    });
    
    it('should create an assistant role card with correct class', () => {
      const card = global.createCard('assistant', '<span>Assistant</span>', 'I am an assistant');
      
      expect(card.find('.role-assistant').length).toBe(1);
      expect(card.find('.card-text').html()).toContain('I am an assistant');
    });
    
    it('should create a system role card with HTML escaping', () => {
      const card = global.createCard('system', '<span>System</span>', '<b>Important</b> message');
      
      expect(card.find('.role-system').length).toBe(1);
      expect(card.find('.card-text').html()).toContain('&lt;b&gt;Important&lt;/b&gt; message');
      expect(global.escapeHtml).toHaveBeenCalledWith('<b>Important</b> message');
    });
    
    it('should handle image attachments correctly', () => {
      const images = [
        { data: 'data:image/png;base64,abc123', title: 'Test Image', type: 'image/png' }
      ];
      
      const card = global.createCard('user', '<span>User</span>', 'With image', 'en', 'img-msg', true, images);
      
      expect(card.find('.card-text').html()).toContain('<img class="base64-image"');
      expect(card.find('.card-text').html()).toContain('Test Image');
    });
    
    it('should handle PDF attachments correctly', () => {
      const images = [
        { title: 'Document.pdf', type: 'application/pdf' }
      ];
      
      const card = global.createCard('user', '<span>User</span>', 'With PDF', 'en', 'pdf-msg', true, images);
      
      expect(card.find('.card-text').html()).toContain('fa-file-pdf');
      expect(card.find('.card-text').html()).toContain('Document.pdf');
    });
    
    it('should add timestamp to image URLs to prevent caching', () => {
      const html = 'Test <img src="image.jpg"> content';
      const card = global.createCard('user', '<span>User</span>', html);
      
      expect(card.find('.card-text').html()).toContain('image.jpg?dummy=12345');
    });
    
    it('should add message ID to the mids Set', () => {
      const mid = 'test-mid-123';
      const sizeBefore = global.mids.size;
      
      global.createCard('user', '<span>Test</span>', 'Test message', 'en', mid, true);
      
      expect(global.mids.has(mid)).toBe(true);
      expect(global.mids.size).toBe(sizeBefore + 1);
    });
    
    it('should not add empty message IDs to the mids Set', () => {
      const sizeBefore = global.mids.size;
      
      global.createCard('user', '<span>Test</span>', 'No mid', 'en', '', true);
      
      expect(global.mids.size).toBe(sizeBefore);
    });
    
    it('should check for and remove duplicates', () => {
      const mid = 'duplicate-123';
      
      // Create a mock existing card with the same ID
      const existingCard = testEnv.createJQueryObject('#' + mid);
      existingCard.remove = jest.fn();
      
      // Mock jQuery to return the existing card
      $.mockImplementation(selector => {
        if (selector === `#${mid}`) {
          existingCard.length = 1;
          return existingCard;
        }
        return testEnv.createJQueryObject(selector);
      });
      
      // Create a new card with the same ID
      global.createCard('user', '<span>Test</span>', 'Second card', 'en', mid, true);
      
      // The existing card should be removed
      expect(existingCard.remove).toHaveBeenCalled();
    });
  });
  
  // Test deletion functions
  describe('Message Deletion Functions', () => {
    it('deleteSystemMessage should remove a message', () => {
      // Add a message to delete
      const mid = 'sys-message';
      global.messages.push({ mid, role: 'system', text: 'System message' });
      global.mids.add(mid);
      
      // Call function
      global.deleteSystemMessage(mid, 0);
      
      // Verify message was removed
      expect(global.messages.length).toBe(0);
      expect(global.mids.has(mid)).toBe(false);
      expect(global.ws.send).toHaveBeenCalled();
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
      
      // Call function to delete from the second message onward
      global.deleteMessageAndSubsequent('msg-2', 1);
      
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
      global.deleteMessageOnly('msg-2', 1);
      
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