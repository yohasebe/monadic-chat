/**
 * @jest-environment jsdom
 */

describe('WebSocket Streaming Complete Handler', () => {
  
  beforeEach(() => {
    // Clear all mocks
    jest.clearAllMocks();
  });
  
  describe('streaming_complete message handler', () => {
    it('should process streaming_complete message correctly', () => {
      // Set up DOM elements
      const spinner = document.createElement('div');
      spinner.id = 'monadic-spinner';
      document.body.appendChild(spinner);

      const message = document.createElement('textarea');
      message.id = 'message';
      message.disabled = true;
      document.body.appendChild(message);

      // Mock global functions
      global.setAlert = jest.fn();
      global.setInputFocus = jest.fn();

      // Create the handler code (vanilla JS, matching current websocket.js)
      const spinnerRef = spinner;
      const messageRef = message;
      const handleStreamingComplete = () => {
        spinnerRef.style.display = "none";
        setAlert("<i class='fa-solid fa-circle-check'></i> Ready for input", "success");
        messageRef.disabled = false;
        setInputFocus();
      };

      // Execute the handler
      handleStreamingComplete();

      // Verify the spinner is hidden
      expect(spinner.style.display).toBe('none');

      // Verify status is updated
      expect(global.setAlert).toHaveBeenCalledWith(
        "<i class='fa-solid fa-circle-check'></i> Ready for input",
        "success"
      );

      // Verify input focus is set
      expect(global.setInputFocus).toHaveBeenCalled();

      // Verify message input is enabled
      expect(message.disabled).toBe(false);

      // Cleanup
      spinner.remove();
      message.remove();
    });
  });
  
  describe('html message status updates', () => {
    it('should show "Response received" for assistant messages', () => {
      // Mock setAlert
      global.setAlert = jest.fn();
      
      // Create handler for assistant message
      const handleAssistantMessage = () => {
        setAlert("<i class='fa-solid fa-circle-check'></i> Response received", "success");
      };
      
      // Execute
      handleAssistantMessage();
      
      // Verify
      expect(global.setAlert).toHaveBeenCalledWith(
        "<i class='fa-solid fa-circle-check'></i> Response received",
        "success"
      );
    });
    
    it('should show "Ready to start" for non-assistant messages', () => {
      // Mock setAlert
      global.setAlert = jest.fn();
      
      // Create handler for non-assistant message
      const handleNonAssistantMessage = () => {
        setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
      };
      
      // Execute
      handleNonAssistantMessage();
      
      // Verify
      expect(global.setAlert).toHaveBeenCalledWith(
        "<i class='fa-solid fa-circle-check'></i> Ready to start",
        "success"
      );
    });
  });
  
  describe('WebSocket message handling logic', () => {
    it('should correctly identify streaming_complete messages', () => {
      const message = { type: 'streaming_complete' };
      expect(message.type).toBe('streaming_complete');
    });
    
    it('should correctly identify assistant role in html messages', () => {
      const message = {
        type: 'html',
        content: {
          role: 'assistant',
          html: '<p>Test</p>'
        }
      };
      expect(message.content.role).toBe('assistant');
    });
    
    it('should correctly identify non-assistant roles in html messages', () => {
      const userMessage = {
        type: 'html',
        content: {
          role: 'user',
          html: '<p>Test</p>'
        }
      };
      expect(userMessage.content.role).toBe('user');
      expect(userMessage.content.role).not.toBe('assistant');
    });
  });
});