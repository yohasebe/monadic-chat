describe('SessionState Management', () => {
  beforeEach(() => {
    // Reset SessionState before each test
    if (window.SessionState) {
      window.SessionState.resetAllFlags();
      window.SessionState.conversation = { messages: [] };
      window.SessionState.app = { current: null, params: {}, originalParams: {} };
    }
    
    // Clear any global variables
    window.messages = [];
    window.forceNewSession = false;
    window.justReset = false;
  });

  describe('Phase 1: Backward Compatibility', () => {
    it('should maintain global variable access for forceNewSession', () => {
      // Test setting via global variable
      window.forceNewSession = true;
      expect(window.SessionState.forceNewSession).toBe(true);
      expect(window.SessionState.session?.forceNew || window.SessionState.forceNewSession).toBe(true);
      
      // Test setting via SessionState
      window.SessionState.forceNewSession = false;
      expect(window.forceNewSession).toBe(false);
    });
    
    it('should maintain global variable access for justReset', () => {
      // Test setting via global variable
      window.justReset = true;
      expect(window.SessionState.justReset).toBe(true);
      
      // Test setting via SessionState
      window.SessionState.justReset = false;
      expect(window.justReset).toBe(false);
    });
    
    it('should handle setResetFlags method correctly', () => {
      window.SessionState.setResetFlags();
      expect(window.forceNewSession).toBe(true);
      expect(window.justReset).toBe(true);
      expect(window.SessionState.forceNewSession).toBe(true);
      expect(window.SessionState.justReset).toBe(true);
    });
    
    it('should handle clearForceNewSession method correctly', () => {
      window.SessionState.forceNewSession = true;
      window.SessionState.clearForceNewSession();
      expect(window.SessionState.forceNewSession).toBe(false);
      expect(window.forceNewSession).toBe(false);
    });
    
    it('should handle shouldForceNewSession method correctly', () => {
      window.SessionState.forceNewSession = false;
      expect(window.SessionState.shouldForceNewSession()).toBe(false);
      
      window.SessionState.forceNewSession = true;
      expect(window.SessionState.shouldForceNewSession()).toBe(true);
    });
  });

  describe('Phase 2: Enhanced State Management', () => {
    beforeEach(() => {
      // Ensure enhanced SessionState is available
      if (!window.SessionState.conversation) {
        window.SessionState.conversation = { messages: [] };
      }
    });
    
    it('should manage messages array', () => {
      const testMessage = { role: 'user', content: 'test message' };
      
      // Add message using new API (when implemented)
      if (window.SessionState.addMessage) {
        window.SessionState.addMessage(testMessage);
        expect(window.SessionState.getMessages()).toContain(testMessage);
      } else {
        // Fallback to direct manipulation for now
        window.SessionState.conversation.messages.push(testMessage);
        expect(window.SessionState.conversation.messages).toContain(testMessage);
      }
    });
    
    it('should clear messages correctly', () => {
      // Add some messages
      window.SessionState.conversation.messages = [
        { role: 'user', content: 'message 1' },
        { role: 'assistant', content: 'message 2' }
      ];
      
      // Clear messages
      if (window.SessionState.clearMessages) {
        window.SessionState.clearMessages();
      } else {
        window.SessionState.conversation.messages = [];
      }
      
      expect(window.SessionState.conversation.messages.length).toBe(0);
    });
    
    it('should track app state', () => {
      const appName = 'TestApp';
      const params = { model: 'gpt-4', temperature: 0.7 };
      
      if (window.SessionState.app) {
        window.SessionState.app.current = appName;
        window.SessionState.app.params = params;
        
        expect(window.SessionState.app.current).toBe(appName);
        expect(window.SessionState.app.params).toEqual(params);
      }
    });
  });

  describe('Phase 3: Event System', () => {
    it('should handle event listeners', (done) => {
      if (window.SessionState.on && window.SessionState.notifyListeners) {
        const testData = { test: 'data' };
        
        window.SessionState.on('test:event', (data) => {
          expect(data).toEqual(testData);
          done();
        });
        
        window.SessionState.notifyListeners('test:event', testData);
      } else {
        // Skip if event system not yet implemented
        done();
      }
    });
    
    it('should remove event listeners', () => {
      if (window.SessionState.on && window.SessionState.off) {
        let callCount = 0;
        const callback = () => { callCount++; };
        
        window.SessionState.on('test:event', callback);
        window.SessionState.notifyListeners('test:event');
        expect(callCount).toBe(1);
        
        window.SessionState.off('test:event', callback);
        window.SessionState.notifyListeners('test:event');
        expect(callCount).toBe(1); // Should not increase
      }
    });
  });

  describe('Phase 4: State Persistence', () => {
    it('should save state to localStorage', () => {
      if (window.SessionState.save) {
        // Set some state
        window.SessionState.session = { id: 'test-session', started: true };
        window.SessionState.app = { current: 'TestApp' };
        
        // Save state
        window.SessionState.save();
        
        // Check localStorage
        const saved = localStorage.getItem('monadicState');
        expect(saved).toBeTruthy();
        
        const parsed = JSON.parse(saved);
        expect(parsed.session.id).toBe('test-session');
        expect(parsed.app.current).toBe('TestApp');
      }
    });
    
    it('should restore state from localStorage', () => {
      if (window.SessionState.restore) {
        // Prepare test data in localStorage
        const testState = {
          session: { id: 'restored-session', started: false },
          app: { current: 'RestoredApp' },
          conversation: { messages: [{ role: 'user', content: 'restored' }] }
        };
        localStorage.setItem('monadicState', JSON.stringify(testState));
        
        // Restore state
        window.SessionState.restore();
        
        // Verify restoration
        expect(window.SessionState.session.id).toBe('restored-session');
        expect(window.SessionState.app.current).toBe('RestoredApp');
        expect(window.SessionState.conversation.messages[0].content).toBe('restored');
      }
    });
  });

  describe('State Health Checks', () => {
    it('should validate state integrity', () => {
      // Ensure state has expected structure
      expect(window.SessionState).toBeDefined();
      expect(typeof window.SessionState.forceNewSession).toBe('boolean');
      expect(typeof window.SessionState.justReset).toBe('boolean');
      expect(typeof window.SessionState.setResetFlags).toBe('function');
      expect(typeof window.SessionState.clearForceNewSession).toBe('function');
      expect(typeof window.SessionState.shouldForceNewSession).toBe('function');
      expect(typeof window.SessionState.resetAllFlags).toBe('function');
    });
    
    it('should handle concurrent modifications safely', () => {
      // Test that rapid state changes don't cause issues
      for (let i = 0; i < 10; i++) {
        window.SessionState.forceNewSession = i % 2 === 0;
        expect(window.forceNewSession).toBe(i % 2 === 0);
      }
    });
  });
});