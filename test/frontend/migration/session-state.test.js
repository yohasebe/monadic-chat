/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

// Helper to load migration files
function loadMigrationFile(filename) {
  const filePath = path.join(__dirname, '../../../docker/services/ruby/public/js/monadic', filename);
  const code = fs.readFileSync(filePath, 'utf8');
  
  // Create a function that executes the code
  const func = new Function('window', 'document', 'console', code);
  
  // Execute in the context of the global window
  func(global.window, global.document, console);
}

describe('SessionState Migration', () => {
  beforeEach(() => {
    // Reset window state
    global.window = {
      location: { hostname: 'localhost' },
      localStorage: {
        getItem: jest.fn(),
        setItem: jest.fn(),
        removeItem: jest.fn()
      }
    };
    
    // Load SessionState
    loadMigrationFile('session_state.js');
  });
  
  describe('SessionState Core', () => {
    test('should initialize with default values', () => {
      expect(window.SessionState).toBeDefined();
      expect(window.SessionState.session).toBeDefined();
      expect(window.SessionState.conversation).toBeDefined();
      expect(window.SessionState.app).toBeDefined();
      expect(window.SessionState.ui).toBeDefined();
      expect(window.SessionState.connection).toBeDefined();
      expect(window.SessionState.audio).toBeDefined();
    });
    
    test('should handle reset flags correctly', () => {
      window.SessionState.setResetFlags();
      expect(window.SessionState.forceNewSession).toBe(true);
      expect(window.SessionState.justReset).toBe(true);
      expect(window.SessionState.session.forceNew).toBe(true);
      expect(window.SessionState.session.justReset).toBe(true);
      
      window.SessionState.clearForceNewSession();
      expect(window.SessionState.forceNewSession).toBe(false);
      expect(window.SessionState.session.forceNew).toBe(false);
      
      window.SessionState.clearJustReset();
      expect(window.SessionState.justReset).toBe(false);
      expect(window.SessionState.session.justReset).toBe(false);
    });
    
    test('should manage messages correctly', () => {
      const message1 = { role: 'user', content: 'Hello' };
      const message2 = { role: 'assistant', content: 'Hi there!' };
      
      window.SessionState.addMessage(message1);
      expect(window.SessionState.getMessages()).toHaveLength(1);
      expect(window.SessionState.getMessages()[0]).toEqual(message1);
      
      window.SessionState.addMessage(message2);
      expect(window.SessionState.getMessages()).toHaveLength(2);
      
      window.SessionState.clearMessages();
      expect(window.SessionState.getMessages()).toHaveLength(0);
    });
    
    test('should update last message', () => {
      const message = { role: 'assistant', content: 'Initial' };
      window.SessionState.addMessage(message);
      
      window.SessionState.updateLastMessage('Updated content');
      const messages = window.SessionState.getMessages();
      expect(messages[0].content).toBe('Updated content');
    });
    
    test('should delete message by index', () => {
      window.SessionState.addMessage({ role: 'user', content: '1' });
      window.SessionState.addMessage({ role: 'assistant', content: '2' });
      window.SessionState.addMessage({ role: 'user', content: '3' });
      
      const deleted = window.SessionState.deleteMessage(1);
      expect(deleted.content).toBe('2');
      expect(window.SessionState.getMessages()).toHaveLength(2);
      expect(window.SessionState.getMessages()[1].content).toBe('3');
    });
  });
  
  describe('App State Management', () => {
    test('should set and get current app', () => {
      const params = { model: 'gpt-4', temperature: 0.7 };
      window.SessionState.setCurrentApp('chat', params);
      
      expect(window.SessionState.getCurrentApp()).toBe('chat');
      expect(window.SessionState.getAppParams()).toEqual(params);
    });
    
    test('should update app params', () => {
      window.SessionState.setCurrentApp('chat', { model: 'gpt-4' });
      window.SessionState.updateAppParams({ temperature: 0.9 });
      
      const params = window.SessionState.getAppParams();
      expect(params.model).toBe('gpt-4');
      expect(params.temperature).toBe(0.9);
    });
  });
  
  describe('Event System', () => {
    test('should register and trigger event listeners', () => {
      const mockHandler = jest.fn();
      
      window.SessionState.on('test:event', mockHandler);
      window.SessionState.notifyListeners('test:event', { data: 'test' });
      
      expect(mockHandler).toHaveBeenCalledWith({ data: 'test' });
    });
    
    test('should remove event listeners', () => {
      const mockHandler = jest.fn();
      
      window.SessionState.on('test:event', mockHandler);
      window.SessionState.off('test:event', mockHandler);
      window.SessionState.notifyListeners('test:event', { data: 'test' });
      
      expect(mockHandler).not.toHaveBeenCalled();
    });
    
    test('should handle once listeners', () => {
      const mockHandler = jest.fn();
      
      window.SessionState.once('test:event', mockHandler);
      window.SessionState.notifyListeners('test:event', { data: 'first' });
      window.SessionState.notifyListeners('test:event', { data: 'second' });
      
      expect(mockHandler).toHaveBeenCalledTimes(1);
      expect(mockHandler).toHaveBeenCalledWith({ data: 'first' });
    });
  });
  
  describe('State Validation', () => {
    test('should validate state correctly', () => {
      expect(window.SessionState.validateState()).toBe(true);
      
      // Corrupt state
      window.SessionState.conversation.messages = 'not-an-array';
      expect(window.SessionState.validateState()).toBe(false);
      
      // Fix state
      window.SessionState.conversation.messages = [];
      expect(window.SessionState.validateState()).toBe(true);
    });
  });
  
  describe('State Persistence', () => {
    test('should save state to storage', () => {
      window.SessionState.session.id = 'test-123';
      window.SessionState.app.current = 'chat';
      window.SessionState.addMessage({ role: 'user', content: 'Test' });
      
      window.SessionState.save();
      
      expect(window.localStorage.setItem).toHaveBeenCalled();
      const savedData = JSON.parse(window.localStorage.setItem.mock.calls[0][1]);
      expect(savedData.session.id).toBe('test-123');
      expect(savedData.app.current).toBe('chat');
      expect(savedData.conversation.messages).toHaveLength(1);
    });
    
    test('should restore state from storage', () => {
      const savedState = {
        session: { id: 'restored-123', started: true },
        app: { current: 'code_interpreter', params: { model: 'gpt-4' } },
        conversation: { messages: [{ role: 'user', content: 'Restored' }] },
        ui: { autoScroll: false }
      };
      
      window.localStorage.getItem.mockReturnValue(JSON.stringify(savedState));
      window.SessionState.restore();
      
      expect(window.SessionState.session.id).toBe('restored-123');
      expect(window.SessionState.app.current).toBe('code_interpreter');
      expect(window.SessionState.getMessages()).toHaveLength(1);
      expect(window.SessionState.ui.autoScroll).toBe(false);
    });
  });
  
  describe('WebSocket State', () => {
    test('should set WebSocket connection', () => {
      const mockWs = { readyState: WebSocket.OPEN };
      window.SessionState.setWebSocket(mockWs);
      
      expect(window.SessionState.connection.ws).toBe(mockWs);
      expect(window.SessionState.connection.isConnected).toBe(true);
    });
  });
  
  describe('Backward Compatibility', () => {
    test('should maintain legacy flag compatibility', () => {
      // Test getter/setter for forceNewSession
      window.forceNewSession = true;
      expect(window.SessionState.forceNewSession).toBe(true);
      
      window.SessionState.forceNewSession = false;
      expect(window.forceNewSession).toBe(false);
      
      // Test getter/setter for justReset
      window.justReset = true;
      expect(window.SessionState.justReset).toBe(true);
      
      window.SessionState.justReset = false;
      expect(window.justReset).toBe(false);
    });
  });
});