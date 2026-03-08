/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-connection-handler.js
 *
 * Tests OpenAI token verification and connection status handlers:
 * - handleTokenVerified: Enable TTS/STT features
 * - handleOpenAIAPIError: Disable features on API failure
 * - handleTokenNotVerified: Disable features on invalid token
 */

function createMockElement(id) {
  return {
    prop: jest.fn().mockReturnThis(),
    val: jest.fn(function(v) { if (v === undefined) return ''; return this; }),
    trigger: jest.fn().mockReturnThis(),
    length: 1,
    0: document.createElement('div')
  };
}

let mockElements;

function setupMockElements() {
  mockElements = {
    '#api-token': createMockElement('api-token'),
    '#ai-user-initial-prompt': createMockElement('ai-user-initial-prompt'),
    '#openai-tts-4o': createMockElement('openai-tts-4o'),
    '#openai-tts': createMockElement('openai-tts'),
    '#openai-tts-hd': createMockElement('openai-tts-hd'),
    '#openai-stt-4o-mini': createMockElement('openai-stt-4o-mini'),
    '#openai-stt-4o': createMockElement('openai-stt-4o'),
    '#openai-stt-4o-diarize': createMockElement('openai-stt-4o-diarize'),
    '#openai-stt-whisper': createMockElement('openai-stt-whisper'),
    '#stt-model': createMockElement('stt-model'),
    '#tts-provider': createMockElement('tts-provider'),
    '#start': createMockElement('start')
  };
  // Special mock for stt-model option:selected
  mockElements['#stt-model option:selected'] = { prop: jest.fn().mockReturnValue(false) };
}

beforeEach(() => {
  setupMockElements();

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    return createMockElement('default');
  });

  global.setAlert = jest.fn();
  global.getTranslation = jest.fn((key, fallback) => fallback);

  window.verified = null;
  window.providerDefaults = { openai: { audio_transcription: ['gpt-4o-mini-transcribe'] } };
  window.updateAvailableProviders = jest.fn();
});

afterEach(() => {
  jest.restoreAllMocks();
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-connection-handler');

describe('ws-connection-handler', () => {
  describe('handleTokenVerified', () => {
    it('sets verified to full', () => {
      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: 'hello' });
      expect(window.verified).toBe('full');
    });

    it('sets API token value', () => {
      handlers.handleTokenVerified({ token: 'sk-test123', ai_user_initial_prompt: '' });
      expect(mockElements['#api-token'].val).toHaveBeenCalledWith('sk-test123');
    });

    it('enables OpenAI TTS options', () => {
      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });

      expect(mockElements['#openai-tts-4o'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#openai-tts'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#openai-tts-hd'].prop).toHaveBeenCalledWith('disabled', false);
    });

    it('enables OpenAI STT models', () => {
      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });

      expect(mockElements['#openai-stt-4o-mini'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#openai-stt-4o'].prop).toHaveBeenCalledWith('disabled', false);
    });

    it('sets default STT model from providerDefaults', () => {
      // No current STT model selected
      mockElements['#stt-model'].val = jest.fn(function(v) {
        if (v === undefined) return '';
        return this;
      });

      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });

      expect(mockElements['#stt-model'].val).toHaveBeenCalledWith('gpt-4o-mini-transcribe');
    });

    it('switches TTS from webspeech to openai', () => {
      mockElements['#tts-provider'].val = jest.fn(function(v) {
        if (v === undefined) return 'webspeech';
        return this;
      });
      mockElements['#tts-provider'].trigger = jest.fn().mockReturnThis();

      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });

      expect(mockElements['#tts-provider'].val).toHaveBeenCalledWith('openai-tts-4o');
    });

    it('calls updateAvailableProviders', () => {
      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });
      expect(window.updateAvailableProviders).toHaveBeenCalled();
    });

    it('enables start button', () => {
      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });
      expect(mockElements['#start'].prop).toHaveBeenCalledWith('disabled', false);
    });
  });

  describe('handleOpenAIAPIError', () => {
    it('sets verified to partial', () => {
      handlers.handleOpenAIAPIError({});
      expect(window.verified).toBe('partial');
    });

    it('clears API token', () => {
      handlers.handleOpenAIAPIError({});
      expect(mockElements['#api-token'].val).toHaveBeenCalledWith('');
    });

    it('disables OpenAI TTS options', () => {
      handlers.handleOpenAIAPIError({});

      expect(mockElements['#openai-tts-4o'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#openai-tts'].prop).toHaveBeenCalledWith('disabled', true);
    });

    it('disables OpenAI STT models', () => {
      handlers.handleOpenAIAPIError({});

      expect(mockElements['#openai-stt-4o'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#openai-stt-whisper'].prop).toHaveBeenCalledWith('disabled', true);
    });

    it('shows cannot connect warning', () => {
      handlers.handleOpenAIAPIError({});

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Cannot connect to OpenAI API'),
        'warning'
      );
    });
  });

  describe('handleTokenNotVerified', () => {
    it('sets verified to partial', () => {
      handlers.handleTokenNotVerified({});
      expect(window.verified).toBe('partial');
    });

    it('clears API token', () => {
      handlers.handleTokenNotVerified({});
      expect(mockElements['#api-token'].val).toHaveBeenCalledWith('');
    });

    it('disables OpenAI TTS and STT', () => {
      handlers.handleTokenNotVerified({});

      expect(mockElements['#openai-tts-4o'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#openai-stt-4o-mini'].prop).toHaveBeenCalledWith('disabled', true);
    });

    it('shows token not set warning', () => {
      handlers.handleTokenNotVerified({});

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Valid OpenAI token not set'),
        'warning'
      );
    });
  });

  describe('module exports', () => {
    it('exports all three handlers', () => {
      expect(typeof handlers.handleTokenVerified).toBe('function');
      expect(typeof handlers.handleOpenAIAPIError).toBe('function');
      expect(typeof handlers.handleTokenNotVerified).toBe('function');
    });

    it('exposes handlers on window.WsConnectionHandler', () => {
      expect(typeof window.WsConnectionHandler).toBe('object');
    });
  });
});
