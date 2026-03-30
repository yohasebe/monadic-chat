/**
 * @jest-environment jsdom
 */

// Mock window object
global.window = {
  ...global.window,
  firefoxAudioMode: false,
  firefoxAudioQueue: []
};

// Mock global utilities
global.setAlert = jest.fn();
global.setInputFocus = jest.fn();
global.atob = jest.fn().mockReturnValue('test-audio-data');
global.Uint8Array = {
  from: jest.fn().mockReturnValue(new Uint8Array([116, 101, 115, 116]))
};
global.autoScroll = false;
global.isElementInViewport = jest.fn().mockReturnValue(true);
global.messages = [];
global.URL = {
  createObjectURL: jest.fn().mockReturnValue('blob:test-url'),
  revokeObjectURL: jest.fn()
};
global.createCard = jest.fn().mockImplementation((role, header, content, lang, mid, isAssistant, images) => {
  return '<div class="card">Test Card</div>';
});
global.autoScrollToBottom = jest.fn();
global.setTimeout = jest.fn().mockImplementation((cb) => {
  if (typeof cb === 'function') cb();
  return 123;
});
global.clearTimeout = jest.fn();
global.Blob = jest.fn().mockImplementation(() => ({
  size: 1024,
  type: 'audio/mpeg'
}));
global.Audio = jest.fn().mockImplementation(() => ({
  play: jest.fn().mockResolvedValue(undefined),
  pause: jest.fn(),
  src: '',
  onended: null
}));

// Import the module under test
const handlers = require('../../docker/services/ruby/public/js/monadic/websocket-handlers');

// Helper: set up DOM elements for a test
function setupDom(ids) {
  ids.forEach(id => {
    let el = document.getElementById(id);
    if (!el) {
      el = document.createElement('div');
      el.id = id;
      document.body.appendChild(el);
    }
  });
}

// Common element IDs used across tests
const commonIds = [
  'api-token', 'ai-user-initial-prompt', 'message', 'monadic-spinner',
  'send', 'clear', 'image-file', 'voice', 'doc', 'url', 'ai_user',
  'ai_user_provider', 'select-role', 'cancel_query', 'discourse',
  'asr-p-value', 'amplitude', 'user-panel', 'check-easy-submit',
  'temp-card', 'chat-bottom'
];

// Reset all mocks before each test
beforeEach(() => {
  jest.clearAllMocks();

  // Clean body
  document.body.innerHTML = '';

  // Set up common DOM elements
  setupDom(commonIds);

  // Also add a span inside monadic-spinner for spinner text updates
  const spinnerEl = document.getElementById('monadic-spinner');
  const spinnerSpan = document.createElement('span');
  spinnerEl.appendChild(spinnerSpan);

  // Ensure global functions are defined
  if (!global.setAlert) global.setAlert = jest.fn();
  if (!global.setInputFocus) global.setInputFocus = jest.fn();
  if (!global.createCard) global.createCard = jest.fn().mockReturnValue('<div class="card">Mock Card</div>');
});

describe('WebSocket Handlers', () => {
  // Test the token verification handler
  describe('handleTokenVerification', () => {
    it('should process token verification message', () => {
      const data = {
        type: 'token_verified',
        token: 'test-token',
        ai_user_initial_prompt: 'test-prompt'
      };

      const result = handlers.handleTokenVerification(data);

      expect(result).toBe(true);
      expect(document.getElementById('api-token').value).toBe('test-token');
      expect(document.getElementById('ai-user-initial-prompt').value).toBe('test-prompt');
    });

    it('should return false for non-token messages', () => {
      const result = handlers.handleTokenVerification({ type: 'something-else' });
      expect(result).toBe(false);
    });

    it('should handle token message with additional model data', () => {
      const data = {
        type: 'token_verified',
        token: 'test-token',
        ai_user_initial_prompt: 'test-prompt',
        models: ['gpt-4.1', 'gpt-3.5-turbo']
      };

      const result = handlers.handleTokenVerification(data);

      expect(result).toBe(true);
      expect(document.getElementById('api-token').value).toBe('test-token');
      expect(document.getElementById('ai-user-initial-prompt').value).toBe('test-prompt');
    });
  });

  // Test the error message handler
  describe('handleErrorMessage', () => {
    it('should handle error messages', () => {
      const data = {
        type: 'error',
        content: 'Test error message'
      };

      const result = handlers.handleErrorMessage(data);

      expect(result).toBe(true);
      // Verify controls were re-enabled
      expect(document.getElementById('send').disabled).toBe(false);
      expect(document.getElementById('clear').disabled).toBe(false);
      expect(document.getElementById('message').disabled).toBe(false);

      // Verify createCard was called
      expect(global.createCard).toHaveBeenCalledWith(
        "system",
        expect.stringContaining('System'),
        expect.stringContaining('error-message'),
        "en",
        null,
        true,
        []
      );

      // Verify the error card was appended to discourse
      expect(document.getElementById('discourse').innerHTML).toContain('card');
    });

    it('should specifically handle AI User error from Perplexity', () => {
      const data = {
        type: 'error',
        content: 'AI User error with provider perplexity: Last message must have role `user`'
      };

      const result = handlers.handleErrorMessage(data);

      expect(result).toBe(true);
      expect(document.getElementById('ai_user').disabled).toBe(false);

      expect(global.createCard).toHaveBeenCalledWith(
        "system",
        expect.stringContaining('System'),
        expect.stringContaining('AI User error with provider perplexity'),
        "en",
        null,
        true,
        []
      );
    });

    it('should return false for non-error messages', () => {
      const result = handlers.handleErrorMessage({ type: 'something-else' });
      expect(result).toBe(false);
    });

    it('should handle error messages when setAlert is undefined', () => {
      const originalSetAlert = global.setAlert;
      global.setAlert = undefined;

      const data = {
        type: 'error',
        content: 'Test error message'
      };

      const result = handlers.handleErrorMessage(data);

      expect(result).toBe(true);
      expect(document.getElementById('send').disabled).toBe(false);
      expect(document.getElementById('message').disabled).toBe(false);

      global.setAlert = originalSetAlert;
    });

    it('should handle error messages with HTML content', () => {
      const data = {
        type: 'error',
        content: '<strong>Error:</strong> Connection failed'
      };

      const result = handlers.handleErrorMessage(data);

      expect(result).toBe(true);
      expect(global.createCard).toHaveBeenCalledWith(
        "system",
        expect.stringContaining('System'),
        expect.stringContaining('error-message'),
        "en",
        null,
        true,
        []
      );
      expect(document.getElementById('discourse').innerHTML).toContain('card');
    });

    it('should handle null or empty error content', () => {
      // Test with empty content
      const data = {
        type: 'error',
        content: ''
      };

      const result = handlers.handleErrorMessage(data);
      expect(result).toBe(true);
      expect(global.createCard).toHaveBeenCalledWith(
        "system",
        expect.stringContaining('System'),
        expect.any(String),
        "en",
        null,
        true,
        []
      );

      // Test with null content
      global.createCard.mockClear();
      const nullData = {
        type: 'error',
        content: null
      };

      const nullResult = handlers.handleErrorMessage(nullData);
      expect(nullResult).toBe(true);
      expect(global.createCard).toHaveBeenCalledWith(
        "system",
        expect.stringContaining('System'),
        expect.any(String),
        "en",
        null,
        true,
        []
      );
    });
  });

  // Test the audio message handler
  describe('handleAudioMessage', () => {
    beforeEach(() => {
      handlers.clearProcessedAudioIds();
    });

    it('should handle audio messages', () => {
      const processAudio = jest.fn();
      const data = {
        type: 'audio',
        content: 'dGVzdC1hdWRpby1kYXRh'
      };

      const result = handlers.handleAudioMessage(data, processAudio);

      expect(result).toBe(true);
      expect(atob).toHaveBeenCalledWith('dGVzdC1hdWRpby1kYXRh');
      expect(processAudio).toHaveBeenCalled();
    });

    it('should return false for non-audio messages', () => {
      const result = handlers.handleAudioMessage({ type: 'something-else' });
      expect(result).toBe(false);
    });

    it('should handle errors during audio processing', () => {
      atob.mockImplementationOnce(() => {
        throw new Error('Test error');
      });

      const consoleSpy = jest.spyOn(console, 'error').mockImplementation();

      const data = {
        type: 'audio',
        content: 'invalid-data'
      };

      const result = handlers.handleAudioMessage(data);

      expect(result).toBe(false);
      expect(consoleSpy).toHaveBeenCalled();
      consoleSpy.mockRestore();
    });

    it('should handle invalid content format', () => {
      const consoleSpy = jest.spyOn(console, 'error').mockImplementation();

      const data = {
        type: 'audio',
        content: { invalidFormat: true }
      };

      const result = handlers.handleAudioMessage(data);

      expect(result).toBe(true);
      expect(consoleSpy).toHaveBeenCalled();
      consoleSpy.mockRestore();
    });

    it('should handle audio in Firefox mode', () => {
      window.firefoxAudioMode = true;
      window.firefoxAudioQueue = [];

      const processAudio = jest.fn();
      const data = {
        type: 'audio',
        content: 'ZmlyZWZveC10ZXN0LWRhdGE='
      };

      const result = handlers.handleAudioMessage(data, processAudio);

      expect(result).toBe(true);
      expect(processAudio).toHaveBeenCalled();

      window.firefoxAudioMode = false;
      window.firefoxAudioQueue = [];
    });

    it('should handle audio with empty content', () => {
      const data = {
        type: 'audio',
        content: ''
      };

      atob.mockReturnValueOnce('');

      const result = handlers.handleAudioMessage(data);
      expect(result).toBe(true);
    });
  });

  // Test the HTML message handler
  describe('handleHtmlMessage', () => {
    it('should handle HTML messages from assistant', () => {
      const createCard = jest.fn();

      const data = {
        type: 'html',
        content: {
          role: 'assistant',
          html: '<p>Test response</p>',
          thinking: 'Thinking process',
          lang: 'en',
          mid: 'test123'
        }
      };

      const result = handlers.handleHtmlMessage(data, createCard);

      expect(result).toBe(true);
      expect(createCard).toHaveBeenCalled();
      const msgEl = document.getElementById('message');
      expect(msgEl.style.display).toBe('');
      expect(msgEl.value).toBe('');
      expect(msgEl.disabled).toBe(false);
    });

    it('should handle messages with reasoning_content', () => {
      const createCard = jest.fn();

      const data = {
        type: 'html',
        content: {
          role: 'assistant',
          html: '<p>Test response</p>',
          reasoning_content: 'Reasoning process',
          lang: 'en',
          mid: 'test123'
        }
      };

      const result = handlers.handleHtmlMessage(data, createCard);

      expect(result).toBe(true);
      expect(createCard).toHaveBeenCalled();
      expect(createCard.mock.calls[0][2]).toContain('Reasoning process');

      const msgEl = document.getElementById('message');
      expect(msgEl.style.display).toBe('');
      expect(msgEl.value).toBe('');
    });

    it('should return false for non-assistant role messages', () => {
      const createCard = jest.fn();

      const data = {
        type: 'html',
        content: {
          role: 'user',
          html: '<p>User message</p>',
          lang: 'en',
          mid: 'test456'
        }
      };

      const result = handlers.handleHtmlMessage(data, createCard);
      expect(result).toBe(false);
      expect(createCard).not.toHaveBeenCalled();
    });

    it('should return false for non-html messages', () => {
      const result = handlers.handleHtmlMessage({ type: 'something-else' }, jest.fn());
      expect(result).toBe(false);
    });

    it('should handle HTML messages without createCard function', () => {
      const data = {
        type: 'html',
        content: {
          role: 'assistant',
          html: '<p>Test response</p>',
          lang: 'en',
          mid: 'test123'
        }
      };

      const result = handlers.handleHtmlMessage(data, null);

      expect(result).toBe(true);
      const msgEl = document.getElementById('message');
      expect(msgEl.style.display).toBe('');
      expect(msgEl.value).toBe('');
      expect(msgEl.disabled).toBe(false);
    });

    it('should handle HTML messages with code blocks', () => {
      const createCard = jest.fn();

      const data = {
        type: 'html',
        content: {
          role: 'assistant',
          html: '<p>Here is a code example:</p><pre><code class="language-javascript">console.log("Hello");</code></pre>',
          lang: 'en',
          mid: 'test123'
        }
      };

      const result = handlers.handleHtmlMessage(data, createCard);

      expect(result).toBe(true);
      expect(createCard).toHaveBeenCalled();
      expect(createCard.mock.calls[0][2]).toContain('code class="language-javascript"');

      const msgEl = document.getElementById('message');
      expect(msgEl.style.display).toBe('');
      expect(msgEl.value).toBe('');
    });

    it('should handle messages with malformed content', () => {
      // Test with incomplete content object
      const incompleteData = {
        type: 'html',
        content: { role: 'assistant' }
      };

      const result = handlers.handleHtmlMessage(incompleteData, null);
      expect(result).toBe(true);
      const msgEl = document.getElementById('message');
      expect(msgEl.style.display).toBe('');
      expect(msgEl.value).toBe('');

      // Test with empty html
      const emptyHtmlData = {
        type: 'html',
        content: {
          role: 'assistant',
          html: '',
          mid: 'test123'
        }
      };

      const emptyResult = handlers.handleHtmlMessage(emptyHtmlData, null);
      expect(emptyResult).toBe(true);
      expect(msgEl.style.display).toBe('');
      expect(msgEl.value).toBe('');
    });
  });

  // Test the STT message handler
  describe('handleSTTMessage', () => {
    it('should handle STT messages', () => {
      const msgEl = document.getElementById('message');
      msgEl.value = 'Existing text';

      const data = {
        type: 'stt',
        content: 'Voice transcription',
        logprob: 0.85
      };

      const result = handlers.handleSTTMessage(data);

      expect(result).toBe(true);
      expect(msgEl.value).toBe('Existing text Voice transcription');
      expect(document.getElementById('asr-p-value').textContent).toBe('Last Speech-to-Text p-value: 0.85');
      expect(document.getElementById('send').disabled).toBe(false);
      expect(document.getElementById('clear').disabled).toBe(false);
      expect(document.getElementById('voice').disabled).toBe(false);
      expect(global.setAlert).toHaveBeenCalled();
      expect(global.setInputFocus).toHaveBeenCalled();
    });

    it('should return false for non-STT messages', () => {
      const result = handlers.handleSTTMessage({ type: 'something-else' });
      expect(result).toBe(false);
    });

    it('should handle STT messages with auto-submit enabled', () => {
      const msgEl = document.getElementById('message');
      msgEl.value = '';

      // Create a proper checkbox
      const easySubmitEl = document.getElementById('check-easy-submit');
      easySubmitEl.checked = true;
      // We need a real input element for .checked to work
      // The div we have won't have checked natively, but we set it directly

      const sendEl = document.getElementById('send');
      const clickSpy = jest.spyOn(sendEl, 'click');

      const data = {
        type: 'stt',
        content: 'Voice transcription with auto-submit',
        logprob: 0.9
      };

      const result = handlers.handleSTTMessage(data);

      expect(result).toBe(true);
      expect(clickSpy).toHaveBeenCalled();
      clickSpy.mockRestore();
    });

    it('should handle STT messages when utility functions are undefined', () => {
      const originalSetAlert = global.setAlert;
      const originalSetInputFocus = global.setInputFocus;
      global.setAlert = undefined;
      global.setInputFocus = undefined;

      const msgEl = document.getElementById('message');
      msgEl.value = '';

      const data = {
        type: 'stt',
        content: 'Voice transcription',
        logprob: 0.85
      };

      const result = handlers.handleSTTMessage(data);

      expect(result).toBe(true);
      expect(msgEl.value).toContain('Voice transcription');

      global.setAlert = originalSetAlert;
      global.setInputFocus = originalSetInputFocus;
    });

    it('should append content to existing message text', () => {
      const msgEl = document.getElementById('message');
      msgEl.value = 'Existing text';

      const data = {
        type: 'stt',
        content: ' additional text',
        logprob: 0.85
      };

      const result = handlers.handleSTTMessage(data);

      expect(result).toBe(true);
      expect(msgEl.value).toBe('Existing text  additional text');
    });

    it('should handle STT messages without logprob value', () => {
      const msgEl = document.getElementById('message');
      msgEl.value = 'Existing text';

      const data = {
        type: 'stt',
        content: 'Voice transcription'
      };

      const result = handlers.handleSTTMessage(data);

      expect(result).toBe(true);
      expect(msgEl.value).toContain('Voice transcription');
    });
  });

  // Test the cancel message handler
  describe('handleCancelMessage', () => {
    it('should handle cancel messages', () => {
      const data = {
        type: 'cancel'
      };

      const result = handlers.handleCancelMessage(data);

      expect(result).toBe(true);
      const msgEl = document.getElementById('message');
      expect(msgEl.getAttribute('placeholder')).toBe('Type your message...');
      expect(msgEl.disabled).toBe(false);
      expect(msgEl.style.display).toBe('');
      expect(document.getElementById('send').disabled).toBe(false);
      expect(document.getElementById('clear').disabled).toBe(false);
      expect(document.getElementById('select-role').disabled).toBe(false);
      expect(document.getElementById('cancel_query').style.display).toBe('none');
    });

    it('should return false for non-cancel messages', () => {
      const result = handlers.handleCancelMessage({ type: 'something-else' });
      expect(result).toBe(false);
    });

    it('should handle cancel messages when setInputFocus is undefined', () => {
      const originalSetInputFocus = global.setInputFocus;
      global.setInputFocus = undefined;

      const data = {
        type: 'cancel'
      };

      const result = handlers.handleCancelMessage(data);

      expect(result).toBe(true);
      const msgEl = document.getElementById('message');
      expect(msgEl.getAttribute('placeholder')).toBe('Type your message...');
      expect(msgEl.disabled).toBe(false);
      expect(document.getElementById('send').disabled).toBe(false);
      expect(document.getElementById('cancel_query').style.display).toBe('none');

      global.setInputFocus = originalSetInputFocus;
    });

    it('should reset placeholder text for message input', () => {
      const data = {
        type: 'cancel'
      };

      const result = handlers.handleCancelMessage(data);

      const msgEl = document.getElementById('message');
      expect(msgEl.getAttribute('placeholder')).toBe('Type your message...');
    });
  });

  // Additional tests for error edge cases and integration
  describe('Integration and edge cases', () => {
    it('should handle all message types coherently', () => {
      const tokenMsg = { type: 'token_verified', token: 'test-token' };
      const cancelMsg = { type: 'cancel' };
      const errorMsg = { type: 'error', content: 'Error message' };

      expect(handlers.handleTokenVerification(tokenMsg)).toBe(true);
      expect(handlers.handleErrorMessage(errorMsg)).toBe(true);
      expect(handlers.handleCancelMessage(cancelMsg)).toBe(true);
    });

    it('should handle completely invalid input gracefully', () => {
      const invalidInputs = [
        undefined,
        { type: null }
      ];

      invalidInputs.forEach(input => {
        expect(handlers.handleTokenVerification(input)).toBe(false);
        expect(handlers.handleErrorMessage(input)).toBe(false);
      });
    });
  });
});
