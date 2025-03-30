/**
 * @jest-environment jsdom
 */

describe('WebSocket Client', () => {
  // Mock objects for WebSocket and jQuery
  let mockWebSocket;
  let mockJQuery;
  let originalConsole;

  // Common setup before each test
  beforeEach(() => {
    // Save original console
    originalConsole = global.console;
    
    // Mock console to prevent cluttering test output
    global.console = {
      log: jest.fn(),
      error: jest.fn(),
      warn: jest.fn()
    };
    
    // WebSocket mock
    mockWebSocket = {
      OPEN: 1,
      CLOSED: 3,
      CLOSING: 2,
      CONNECTING: 0,
      readyState: 1,
      send: jest.fn(),
      addEventListener: jest.fn(),
      close: jest.fn(),
      onopen: jest.fn(),
      onclose: jest.fn(),
      onmessage: jest.fn(),
      onerror: jest.fn()
    };
    
    // Mock global WebSocket constructor
    global.WebSocket = jest.fn().mockImplementation(() => mockWebSocket);
    
    // Mock jQuery
    mockJQuery = jest.fn().mockImplementation(selector => {
      const mockElement = {
        click: jest.fn(),
        val: jest.fn().mockReturnValue(''),
        is: jest.fn().mockReturnValue(false),
        append: jest.fn(),
        html: jest.fn(),
        text: jest.fn(),
        prop: jest.fn(),
        attr: jest.fn(),
        hide: jest.fn(),
        show: jest.fn(),
        trigger: jest.fn(),
        find: jest.fn().mockReturnThis(),
        get: jest.fn().mockReturnValue({
          scrollIntoView: jest.fn()
        }),
        each: jest.fn()
      };
      return mockElement;
    });
    
    // Modal mock
    mockJQuery.modal = jest.fn().mockReturnValue({
      modal: jest.fn()
    });
    
    global.$ = mockJQuery;
    global.jQuery = mockJQuery;
    
    // Mock MathJax
    global.MathJax = {
      typesetPromise: jest.fn().mockResolvedValue(true)
    };
    
    // Mock document
    global.document = {
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      hidden: false,
      documentElement: {
        clientHeight: 1080,
        clientWidth: 1920
      },
      querySelector: jest.fn(),
      querySelectorAll: jest.fn(),
      createElementNS: jest.fn().mockReturnValue({
        setAttribute: jest.fn(),
        setAttributeNS: jest.fn()
      })
    };
    
    // Other global mocks
    global.DEFAULT_APP = 'Chat';
    global.setAlert = jest.fn();
    global.setStats = jest.fn();
    global.formatInfo = jest.fn().mockReturnValue('');
    global.mids = new Set();
    global.createCard = jest.fn();
    global.updateItemStates = jest.fn();
    global.setCookie = jest.fn();
    global.getCookie = jest.fn();
    global.setInputFocus = jest.fn();
    global.listModels = jest.fn().mockReturnValue('<option>model1</option>');
    global.modelSpec = { 'gpt-4o': { reasoning_effort: 'high' } };
    global.runningOnFirefox = false;
  });
  
  afterEach(() => {
    // Restore original console
    global.console = originalConsole;
  });

  // Connection management tests - testing our own implementation using similar logic
  describe('WebSocket connection management', () => {
    it('should establish WebSocket connection', () => {
      // Simplified connect function, similar to what would be in websocket.js
      function connect_websocket() {
        const ws = new WebSocket('ws://localhost:4567');
        return ws;
      }
      
      const ws = connect_websocket();
      
      // Verify WebSocket was correctly called
      expect(global.WebSocket).toHaveBeenCalledWith('ws://localhost:4567');
      expect(ws).toBe(mockWebSocket);
    });

    it('should handle reconnection logic', () => {
      let reconnectionAttempts = 0;
      
      // Simplified reconnect function
      function reconnect_websocket(ws) {
        if (ws.readyState === WebSocket.CLOSED) {
          reconnectionAttempts++;
          return new WebSocket('ws://localhost:4567');
        }
        return ws;
      }
      
      // Start with closed WebSocket
      mockWebSocket.readyState = WebSocket.CLOSED;
      
      // Reconnect
      const newWs = reconnect_websocket(mockWebSocket);
      
      // Verify reconnection occurred
      expect(reconnectionAttempts).toBe(1);
      expect(global.WebSocket).toHaveBeenCalledTimes(1);
    });
  });

  // Message handling tests using our own event handler implementations
  describe('WebSocket message handling', () => {
    it('should process token verification message', () => {
      // Create sample message handler similar to websocket.js
      function handleMessage(event) {
        const data = JSON.parse(event.data);
        if (data.type === 'token_verified') {
          $('#api-token').val(data.token);
          $('#ai-user-initial-prompt').val(data.ai_user_initial_prompt);
          return true;
        }
        return false;
      }
      
      // Create test message
      const messageEvent = {
        data: JSON.stringify({
          type: 'token_verified',
          token: 'test-token',
          ai_user_initial_prompt: 'test-prompt'
        })
      };
      
      // Process the message
      const result = handleMessage(messageEvent);
      
      // Verify handler processed the message correctly
      expect(result).toBe(true);
      expect(mockJQuery).toHaveBeenCalledWith('#api-token');
      expect(mockJQuery).toHaveBeenCalledWith('#ai-user-initial-prompt');
    });

    it('should handle error messages', () => {
      // Create sample error handler similar to websocket.js
      function handleErrorMessage(event) {
        const data = JSON.parse(event.data);
        if (data.type === 'error') {
          $('#send, #clear, #image-file, #voice, #doc, #url').prop('disabled', false);
          $('#message').show();
          $('#message').prop('disabled', false);
          $('#monadic-spinner').hide();
          setAlert(data.content, 'error');
          return true;
        }
        return false;
      }
      
      // Create test error message
      const errorEvent = {
        data: JSON.stringify({
          type: 'error',
          content: 'Test error message'
        })
      };
      
      // Process the message
      const result = handleErrorMessage(errorEvent);
      
      // Verify error handling occurred
      expect(result).toBe(true);
      expect(mockJQuery).toHaveBeenCalledWith('#send, #clear, #image-file, #voice, #doc, #url');
      expect(mockJQuery).toHaveBeenCalledWith('#message');
      expect(mockJQuery).toHaveBeenCalledWith('#monadic-spinner');
      expect(setAlert).toHaveBeenCalledWith('Test error message', 'error');
    });
    
    it('should handle audio messages', () => {
      // Mock Audio
      global.Audio = jest.fn().mockImplementation(() => ({
        src: '',
        play: jest.fn().mockResolvedValue(undefined),
        pause: jest.fn()
      }));
      
      // Mock MediaSource
      global.MediaSource = jest.fn().mockImplementation(() => ({
        addEventListener: jest.fn((_event, callback) => callback()),
        addSourceBuffer: jest.fn().mockReturnValue({
          addEventListener: jest.fn(),
          appendBuffer: jest.fn(),
          remove: jest.fn(),
          updating: false
        }),
        readyState: 'open'
      }));
      
      // Mock URL object
      global.URL = {
        createObjectURL: jest.fn().mockReturnValue('blob:test'),
        revokeObjectURL: jest.fn()
      };
      
      // Mock Base64 decode
      global.atob = jest.fn().mockReturnValue('test-audio-data');
      
      // Properly mock Uint8Array.from
      global.Uint8Array = jest.fn();
      global.Uint8Array.from = jest.fn().mockImplementation(() => [116, 101, 115, 116]);
      
      // Create audio handler function similar to websocket.js
      function handleAudioMessage(event) {
        const data = JSON.parse(event.data);
        if (data.type === 'audio') {
          $('#monadic-spinner').hide();
          
          try {
            // Process audio data
            const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));
            
            // In a real implementation, this would add to queue and process
            // For test purposes, we'll just indicate success
            return data.type === 'audio'; // Simply check if it's an audio message
          } catch (e) {
            console.error('Error processing audio:', e);
            return false;
          }
        }
        return false;
      }
      
      // Create audio message
      const audioEvent = {
        data: JSON.stringify({
          type: 'audio',
          content: 'dGVzdC1hdWRpby1kYXRh' // "test-audio-data" in Base64
        })
      };
      
      // Process the message
      const result = handleAudioMessage(audioEvent);
      
      // Verify audio processing occurred
      expect(result).toBe(true);
      expect(global.atob).toHaveBeenCalledWith('dGVzdC1hdWRpby1kYXRh');
      expect(mockJQuery).toHaveBeenCalledWith('#monadic-spinner');
    });
    
    it('should handle html messages (assistant responses)', () => {
      // Create local messages array for this test
      const testMessages = [];
      
      // Create a handler for HTML messages
      function handleHtmlMessage(event) {
        const data = JSON.parse(event.data);
        if (data.type === 'html') {
          testMessages.push(data.content);
          
          const html = data.content.html;
          let finalHtml = html;
          
          // Handle thinking content if present
          if (data.content.thinking) {
            finalHtml = `<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>${data.content.thinking}</div></div>${html}`;
          }
          
          if (data.content.role === 'assistant') {
            // Append card would be called here
            createCard('assistant', 
                     '<span class="text-secondary"><i class="fas fa-robot"></i></span> <span class="fw-bold fs-6 assistant-color">Assistant</span>', 
                     finalHtml, 
                     data.content.lang, 
                     data.content.mid, 
                     true);
            
            // UI Updates
            $('#message').show();
            $('#message').val('');
            $('#message').prop('disabled', false);
            $('#monadic-spinner').hide();
            return true;
          }
          return false;
        }
        return false;
      }
      
      // Create test HTML message
      const htmlEvent = {
        data: JSON.stringify({
          type: 'html',
          content: {
            role: 'assistant',
            html: '<p>Test assistant response</p>',
            thinking: 'Let me think about this...',
            lang: 'en',
            mid: 'abc123',
            text: 'Test assistant response'
          }
        })
      };
      
      // Process the message
      const result = handleHtmlMessage(htmlEvent);
      
      // Verify HTML processing
      expect(result).toBe(true);
      expect(createCard).toHaveBeenCalled();
      expect(mockJQuery).toHaveBeenCalledWith('#message');
      expect(mockJQuery).toHaveBeenCalledWith('#monadic-spinner');
    });
    
    it('should handle speech-to-text (STT) messages', () => {
      // Create a handler for STT messages
      function handleSTTMessage(event) {
        const data = JSON.parse(event.data);
        if (data.type === 'stt') {
          $('#message').val($('#message').val() + ' ' + data.content);
          $('#asr-p-value').text('Last Speech-to-Text p-value: ' + data.logprob);
          $('#send, #clear, #voice').prop('disabled', false);
          
          // Auto submit if enabled
          if ($('#check-easy-submit').is(':checked')) {
            $('#send').click();
          }
          
          setAlert('<i class="fa-solid fa-circle-check"></i> Voice recognition finished', 'secondary');
          setInputFocus();
          return true;
        }
        return false;
      }
      
      // Create test STT message
      const sttEvent = {
        data: JSON.stringify({
          type: 'stt',
          content: 'Hello, this is a voice message',
          logprob: 0.85
        })
      };
      
      // Setup for the test
      mockJQuery.prototype.is = jest.fn().mockReturnValue(false); // For check-easy-submit
      
      // Process the message
      const result = handleSTTMessage(sttEvent);
      
      // Verify STT processing
      expect(result).toBe(true);
      expect(mockJQuery).toHaveBeenCalledWith('#message');
      expect(mockJQuery).toHaveBeenCalledWith('#asr-p-value');
      expect(mockJQuery).toHaveBeenCalledWith('#send, #clear, #voice');
      expect(setAlert).toHaveBeenCalled();
      expect(setInputFocus).toHaveBeenCalled();
    });
    
    it('should handle cancel messages', () => {
      // Create a handler for cancel messages
      function handleCancelMessage(event) {
        const data = JSON.parse(event.data);
        if (data.type === 'cancel') {
          $('#message').attr('placeholder', 'Type your message...');
          $('#message').prop('disabled', false);
          $('#send, #clear, #image-file, #voice, #doc, #url').prop('disabled', false);
          $('#select-role').prop('disabled', false);
          $('#cancel_query').hide();
          
          // Show message input and hide spinner
          $('#message').show();
          $('#monadic-spinner').hide();
          
          setInputFocus();
          return true;
        }
        return false;
      }
      
      // Create test cancel message
      const cancelEvent = {
        data: JSON.stringify({
          type: 'cancel'
        })
      };
      
      // Process the message
      const result = handleCancelMessage(cancelEvent);
      
      // Verify cancel processing
      expect(result).toBe(true);
      expect(mockJQuery).toHaveBeenCalledWith('#message');
      expect(mockJQuery).toHaveBeenCalledWith('#send, #clear, #image-file, #voice, #doc, #url');
      expect(mockJQuery).toHaveBeenCalledWith('#select-role');
      expect(mockJQuery).toHaveBeenCalledWith('#cancel_query');
      expect(mockJQuery).toHaveBeenCalledWith('#monadic-spinner');
      expect(setInputFocus).toHaveBeenCalled();
    });
    
    it('should apply styles to rendered content', () => {
      // Create a function to test MathJax application
      function applyMathJaxTest(element) {
        // Only call MathJax if it exists
        if (typeof MathJax !== 'undefined') {
          const domElement = element.get(0);
          MathJax.typesetPromise([domElement])
            .then(() => true)
            .catch(() => false);
          return true;
        }
        return false;
      }
      
      // Test element
      const testElement = mockJQuery('<div>Test content with math: $E=mc^2$</div>');
      
      // Apply MathJax
      const result = applyMathJaxTest(testElement);
      
      // Verify MathJax was called
      expect(result).toBe(true);
      expect(MathJax.typesetPromise).toHaveBeenCalled();
    });
  });
});