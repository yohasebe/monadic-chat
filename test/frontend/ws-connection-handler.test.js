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

function createDOMElement(tag, id) {
  const el = document.createElement(tag);
  el.id = id;
  document.body.appendChild(el);
  return el;
}

beforeEach(() => {
  // Create DOM elements
  createDOMElement('input', 'api-token');
  createDOMElement('input', 'ai-user-initial-prompt');
  createDOMElement('option', 'openai-tts-4o');
  createDOMElement('option', 'openai-tts');
  createDOMElement('option', 'openai-tts-hd');
  createDOMElement('option', 'openai-stt-4o-mini');
  createDOMElement('option', 'openai-stt-4o');
  createDOMElement('option', 'openai-stt-4o-diarize');
  createDOMElement('option', 'openai-stt-whisper');

  // stt-model select with options
  const sttModel = createDOMElement('select', 'stt-model');
  const opt = document.createElement('option');
  opt.value = '';
  opt.selected = true;
  sttModel.appendChild(opt);
  const sttOpt = document.createElement('option');
  sttOpt.value = 'gpt-4o-mini-transcribe';
  sttModel.appendChild(sttOpt);

  // tts-provider select
  const ttsProvider = createDOMElement('select', 'tts-provider');
  const ttsOpt = document.createElement('option');
  ttsOpt.value = 'webspeech';
  ttsOpt.selected = true;
  ttsProvider.appendChild(ttsOpt);
  const ttsOpt2 = document.createElement('option');
  ttsOpt2.value = 'openai-tts-4o';
  ttsProvider.appendChild(ttsOpt2);

  createDOMElement('button', 'start');
  createDOMElement('button', 'send');
  createDOMElement('button', 'clear');
  createDOMElement('button', 'voice');
  createDOMElement('select', 'elevenlabs-tts-voice');
  createDOMElement('select', 'tts-voice');
  createDOMElement('select', 'conversation-language');
  createDOMElement('input', 'prompt-toggle-assistant');
  createDOMElement('input', 'prompt-toggle-aiuser');
  createDOMElement('input', 'check-auto-speech');
  createDOMElement('input', 'check-easy-submit');

  global.setAlert = jest.fn();
  global.getTranslation = jest.fn((key, fallback) => fallback);

  window.verified = null;
  window.providerDefaults = { openai: { audio_transcription: ['gpt-4o-mini-transcribe'] } };
  window.updateAvailableProviders = jest.fn();
});

afterEach(() => {
  jest.restoreAllMocks();
  document.body.innerHTML = '';
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
      expect(document.getElementById('api-token').value).toBe('sk-test123');
    });

    it('enables OpenAI TTS options', () => {
      document.getElementById('openai-tts-4o').disabled = true;
      document.getElementById('openai-tts').disabled = true;
      document.getElementById('openai-tts-hd').disabled = true;

      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });

      expect(document.getElementById('openai-tts-4o').disabled).toBe(false);
      expect(document.getElementById('openai-tts').disabled).toBe(false);
      expect(document.getElementById('openai-tts-hd').disabled).toBe(false);
    });

    it('enables OpenAI STT models', () => {
      document.getElementById('openai-stt-4o-mini').disabled = true;
      document.getElementById('openai-stt-4o').disabled = true;

      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });

      expect(document.getElementById('openai-stt-4o-mini').disabled).toBe(false);
      expect(document.getElementById('openai-stt-4o').disabled).toBe(false);
    });

    it('sets default STT model from providerDefaults', () => {
      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });

      expect(document.getElementById('stt-model').value).toBe('gpt-4o-mini-transcribe');
    });

    it('switches TTS from webspeech to openai', () => {
      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });

      expect(document.getElementById('tts-provider').value).toBe('openai-tts-4o');
    });

    it('calls updateAvailableProviders', () => {
      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });
      expect(window.updateAvailableProviders).toHaveBeenCalled();
    });

    it('enables start button', () => {
      document.getElementById('start').disabled = true;
      handlers.handleTokenVerified({ token: 'sk-test', ai_user_initial_prompt: '' });
      expect(document.getElementById('start').disabled).toBe(false);
    });
  });

  describe('handleOpenAIAPIError', () => {
    it('sets verified to partial', () => {
      handlers.handleOpenAIAPIError({});
      expect(window.verified).toBe('partial');
    });

    it('clears API token', () => {
      document.getElementById('api-token').value = 'sk-old';
      handlers.handleOpenAIAPIError({});
      expect(document.getElementById('api-token').value).toBe('');
    });

    it('disables OpenAI TTS options', () => {
      handlers.handleOpenAIAPIError({});

      expect(document.getElementById('openai-tts-4o').disabled).toBe(true);
      expect(document.getElementById('openai-tts').disabled).toBe(true);
    });

    it('disables OpenAI STT models', () => {
      handlers.handleOpenAIAPIError({});

      expect(document.getElementById('openai-stt-4o').disabled).toBe(true);
      expect(document.getElementById('openai-stt-whisper').disabled).toBe(true);
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
      document.getElementById('api-token').value = 'sk-old';
      handlers.handleTokenNotVerified({});
      expect(document.getElementById('api-token').value).toBe('');
    });

    it('disables OpenAI TTS and STT', () => {
      handlers.handleTokenNotVerified({});

      expect(document.getElementById('openai-tts-4o').disabled).toBe(true);
      expect(document.getElementById('openai-stt-4o-mini').disabled).toBe(true);
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
