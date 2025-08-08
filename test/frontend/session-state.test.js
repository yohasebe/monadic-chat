/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

// Helper to load SessionState file
function loadSessionState() {
  const filePath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/session_state.js');
  const code = fs.readFileSync(filePath, 'utf8');
  
  // Execute the code in the current context
  eval(code);
}

describe('SessionState Tests', () => {
  beforeEach(() => {
    // Clear any existing SessionState
    delete window.SessionState;
    delete window.safeSessionState;
    delete window.messages;
    delete window.forceNewSession;
    delete window.justReset;
    
    // Clear localStorage
    localStorage.clear();
    
    // Load fresh SessionState
    loadSessionState();
  });
  
  afterEach(() => {
    // Clean up after each test
    localStorage.clear();
  });
  
  describe('Core Functionality', () => {
    test('should initialize with default values', () => {
      expect(window.SessionState).toBeDefined();
      expect(window.SessionState.session).toBeDefined();
      expect(window.SessionState.conversation).toBeDefined();
      expect(window.SessionState.conversation.messages).toEqual([]);
      expect(window.SessionState.app).toBeDefined();
      expect(window.SessionState.ui).toBeDefined();
    });
    
    test('should handle messages correctly', () => {
      // Add message
      const message1 = { role: 'user', text: 'Hello', mid: 'm1' };
      window.SessionState.addMessage(message1);
      expect(window.SessionState.conversation.messages.length).toBe(1);
      expect(window.SessionState.conversation.messages[0]).toEqual(message1);
      
      // Add another message
      const message2 = { role: 'assistant', text: 'Hi', mid: 'm2' };
      window.SessionState.addMessage(message2);
      expect(window.SessionState.conversation.messages.length).toBe(2);
      
      // Remove message
      window.SessionState.removeMessage(0);
      expect(window.SessionState.conversation.messages.length).toBe(1);
      expect(window.SessionState.conversation.messages[0]).toEqual(message2);
      
      // Clear messages
      window.SessionState.clearMessages();
      expect(window.SessionState.conversation.messages.length).toBe(0);
    });
    
    test('should handle reset flags correctly', () => {
      // Set flags
      window.SessionState.setResetFlags();
      expect(window.SessionState.session.forceNew).toBe(true);
      expect(window.SessionState.session.justReset).toBe(true);
      expect(window.SessionState.forceNewSession).toBe(true);
      expect(window.SessionState.justReset).toBe(true);
      
      // Check shouldForceNewSession
      expect(window.SessionState.shouldForceNewSession()).toBe(true);
      
      // Clear specific flag
      window.SessionState.clearForceNewSession();
      expect(window.SessionState.session.forceNew).toBe(false);
      expect(window.SessionState.forceNewSession).toBe(false);
      expect(window.SessionState.shouldForceNewSession()).toBe(false);
      
      // Clear all flags
      window.SessionState.clearResetFlags();
      expect(window.SessionState.session.justReset).toBe(false);
      expect(window.SessionState.justReset).toBe(false);
    });
  });
  
  describe('Messages Array Compatibility', () => {
    test('should sync messages array with SessionState', () => {
      // messages should be the same as SessionState.conversation.messages
      expect(window.messages).toBe(window.SessionState.conversation.messages);
      
      // Adding via SessionState should reflect in messages
      window.SessionState.addMessage({ role: 'user', text: 'Test', mid: 't1' });
      expect(window.messages.length).toBe(1);
      expect(window.messages[0].text).toBe('Test');
      
      // Array methods should work
      const found = window.messages.find(m => m.mid === 't1');
      expect(found).toBeDefined();
      expect(found.text).toBe('Test');
      
      const filtered = window.messages.filter(m => m.role === 'user');
      expect(filtered.length).toBe(1);
      
      // Direct assignment should work (with warning)
      const consoleWarnSpy = jest.spyOn(console, 'warn').mockImplementation();
      window.messages = [{ role: 'system', text: 'Reset', mid: 's1' }];
      expect(consoleWarnSpy).toHaveBeenCalledWith(expect.stringContaining('deprecated'));
      expect(window.SessionState.conversation.messages.length).toBe(1);
      expect(window.SessionState.conversation.messages[0].text).toBe('Reset');
      consoleWarnSpy.mockRestore();
    });
  });
  
  describe('Error Handling', () => {
    test('should handle invalid inputs gracefully', () => {
      // Invalid message
      const result1 = window.SessionState.addMessage(null);
      expect(result1).toBeNull();
      expect(window.SessionState.conversation.messages.length).toBe(0);
      
      // Invalid index
      const result2 = window.SessionState.removeMessage(-1);
      expect(result2).toBeNull();
      
      const result3 = window.SessionState.removeMessage('not a number');
      expect(result3).toBeNull();
      
      // Out of bounds index
      const result4 = window.SessionState.removeMessage(100);
      expect(result4).toBeNull();
    });
    
    test('should provide safe wrappers', () => {
      // Safe operations should return boolean
      expect(window.safeSessionState.isAvailable()).toBe(true);
      
      const added = window.safeSessionState.addMessage({ role: 'test', text: 'Test', mid: 't1' });
      expect(added).toBe(true);
      expect(window.SessionState.conversation.messages.length).toBe(1);
      
      const cleared = window.safeSessionState.clearMessages();
      expect(cleared).toBe(true);
      expect(window.SessionState.conversation.messages.length).toBe(0);
      
      // Invalid operations should return false
      const invalid = window.safeSessionState.addMessage(null);
      expect(invalid).toBe(false);
    });
  });
  
  describe('State Persistence', () => {
    test('should save state to localStorage', () => {
      // Add some data
      window.SessionState.session.id = 'test-session';
      window.SessionState.addMessage({ role: 'user', text: 'Test', mid: 'm1' });
      window.SessionState.app.current = 'TestApp';
      
      // Save state
      window.SessionState.save();
      
      // Check localStorage - SessionState saves to 'monadicState' key
      const saved = localStorage.getItem('monadicState');
      expect(saved).toBeDefined();
      
      const parsed = JSON.parse(saved);
      expect(parsed.session.id).toBe('test-session');
      expect(parsed.conversation.messages.length).toBe(1);
      expect(parsed.app.current).toBe('TestApp');
    });
    
    test('should restore state from localStorage', () => {
      // Set up saved state - SessionState uses 'monadicState' key
      const savedState = {
        session: { id: 'restored-session', started: true },
        conversation: { messages: [{ role: 'user', text: 'Restored', mid: 'r1' }] },
        app: { current: 'RestoredApp', params: {}, model: null }
      };
      localStorage.setItem('monadicState', JSON.stringify(savedState));
      
      // Restore state
      window.SessionState.restore();
      
      // Check restored values
      expect(window.SessionState.session.id).toBe('restored-session');
      expect(window.SessionState.conversation.messages.length).toBe(1);
      expect(window.SessionState.conversation.messages[0].text).toBe('Restored');
      expect(window.SessionState.app.current).toBe('RestoredApp');
    });
  });
  
  describe('Event System', () => {
    test('should handle event listeners', () => {
      const listener = jest.fn();
      
      // Add listener
      window.SessionState.on('message:added', listener);
      
      // Trigger event
      window.SessionState.addMessage({ role: 'user', text: 'Test', mid: 't1' });
      
      // Check listener was called
      expect(listener).toHaveBeenCalledWith(expect.objectContaining({
        role: 'user',
        text: 'Test',
        mid: 't1'
      }));
      
      // Remove listener
      window.SessionState.off('message:added', listener);
      
      // Add another message
      window.SessionState.addMessage({ role: 'user', text: 'Test2', mid: 't2' });
      
      // Listener should not be called again
      expect(listener).toHaveBeenCalledTimes(1);
    });
    
    test('should handle once listeners', () => {
      const listener = jest.fn();
      
      // Add once listener
      window.SessionState.once('message:added', listener);
      
      // Trigger event twice
      window.SessionState.addMessage({ role: 'user', text: 'Test1', mid: 't1' });
      window.SessionState.addMessage({ role: 'user', text: 'Test2', mid: 't2' });
      
      // Listener should only be called once
      expect(listener).toHaveBeenCalledTimes(1);
      expect(listener).toHaveBeenCalledWith(expect.objectContaining({
        text: 'Test1'
      }));
    });
  });
  
  describe('Legacy Compatibility', () => {
    test('should maintain backward compatibility with global variables', () => {
      // forceNewSession
      window.forceNewSession = true;
      expect(window.SessionState.forceNewSession).toBe(true);
      
      window.SessionState.forceNewSession = false;
      expect(window.forceNewSession).toBe(false);
      
      // justReset
      window.justReset = true;
      expect(window.SessionState.justReset).toBe(true);
      
      window.SessionState.justReset = false;
      expect(window.justReset).toBe(false);
    });
  });
});