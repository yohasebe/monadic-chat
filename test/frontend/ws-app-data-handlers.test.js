/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-app-data-handlers.js
 *
 * Tests the extracted WebSocket message handlers for:
 * - handleElevenLabsVoices: Populate ElevenLabs TTS voice selector
 * - handleGeminiVoices: Populate Gemini TTS voice selector
 */

// Track prop calls per selector for verification
const propCalls = {};
const valCalls = {};
const triggerCalls = {};

function createSelectElement(id) {
  const options = [];
  let selectedValue = null;

  return {
    _options: options,
    empty: jest.fn(function () { options.length = 0; return this; }),
    append: jest.fn(function (html) {
      // Parse option HTML to extract value and text
      const match = html.match(/value="([^"]*)"[^>]*>([^<]*)</);
      if (match) {
        options.push({ value: match[1], text: match[2], selected: html.includes('selected') });
        if (html.includes('selected')) selectedValue = match[1];
      }
      return this;
    }),
    val: jest.fn(function (v) {
      if (v === undefined) return selectedValue;
      // Check if option exists
      const found = options.find(o => o.value === v);
      if (found) selectedValue = v;
      valCalls[id] = v;
      return this;
    }),
    prop: jest.fn(function (name, value) {
      if (!propCalls[id]) propCalls[id] = {};
      propCalls[id][name] = value;
      return this;
    }),
    trigger: jest.fn(function (event) {
      triggerCalls[id] = event;
      return this;
    }),
    length: 1
  };
}

// Build mock elements
let mockElements;

function setupMockElements() {
  mockElements = {
    '#elevenlabs-tts-voice': createSelectElement('elevenlabs-tts-voice'),
    '#gemini-tts-voice': createSelectElement('gemini-tts-voice'),
    '#tts-provider': createSelectElement('tts-provider'),
    '#elevenlabs-flash-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-multilingual-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-v3-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-stt-scribe-v2': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-stt-scribe': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-stt-scribe-experimental': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#gemini-flash-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#gemini-pro-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#gemini-stt-flash': { prop: jest.fn().mockReturnThis(), length: 1 }
  };
}

beforeEach(() => {
  setupMockElements();

  // Clear tracking
  Object.keys(propCalls).forEach(k => delete propCalls[k]);
  Object.keys(valCalls).forEach(k => delete valCalls[k]);
  Object.keys(triggerCalls).forEach(k => delete triggerCalls[k]);

  // Mock jQuery
  global.$ = jest.fn().mockImplementation(selector => {
    // Handle attribute selector for option existence check
    if (typeof selector === 'string' && selector.includes('option[value=')) {
      // Extract the voice ID from the selector
      const match = selector.match(/option\[value="([^"]+)"\]/);
      if (match) {
        const voiceId = match[1];
        // Check if option exists in any select
        for (const key of Object.keys(mockElements)) {
          const el = mockElements[key];
          if (el._options) {
            const found = el._options.find(o => o.value === voiceId);
            if (found) return { length: 1 };
          }
        }
      }
      return { length: 0 };
    }
    return mockElements[selector] || { prop: jest.fn().mockReturnThis(), val: jest.fn().mockReturnThis(), trigger: jest.fn().mockReturnThis(), length: 0 };
  });

  // Mock getCookie
  global.getCookie = jest.fn().mockReturnValue(null);
});

afterEach(() => {
  jest.restoreAllMocks();
});

// Load the module
const handlers = require('../../docker/services/ruby/public/js/monadic/ws-app-data-handlers');

describe('ws-app-data-handlers', () => {
  describe('handleElevenLabsVoices', () => {
    it('populates voice selector with voices', () => {
      const data = {
        content: [
          { voice_id: 'v1', name: 'Rachel' },
          { voice_id: 'v2', name: 'Drew' }
        ]
      };

      handlers.handleElevenLabsVoices(data);

      const el = mockElements['#elevenlabs-tts-voice'];
      expect(el.empty).toHaveBeenCalled();
      expect(el.append).toHaveBeenCalledTimes(2);
      expect(el._options).toHaveLength(2);
      expect(el._options[0].value).toBe('v1');
      expect(el._options[0].text).toBe('Rachel');
      expect(el._options[1].value).toBe('v2');
      expect(el._options[1].text).toBe('Drew');
    });

    it('enables TTS and STT options when voices are available', () => {
      const data = {
        content: [{ voice_id: 'v1', name: 'Rachel' }]
      };

      handlers.handleElevenLabsVoices(data);

      // TTS provider options should be enabled
      expect(mockElements['#elevenlabs-flash-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#elevenlabs-multilingual-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#elevenlabs-v3-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      // STT options should be enabled
      expect(mockElements['#elevenlabs-stt-scribe-v2'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#elevenlabs-stt-scribe'].prop).toHaveBeenCalledWith('disabled', false);
    });

    it('disables all options when no voices', () => {
      const data = { content: [] };

      handlers.handleElevenLabsVoices(data);

      expect(mockElements['#elevenlabs-flash-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#elevenlabs-multilingual-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#elevenlabs-v3-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#elevenlabs-stt-scribe-v2'].prop).toHaveBeenCalledWith('disabled', true);
    });

    it('restores saved voice from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'elevenlabs-tts-voice') return 'v2';
        return null;
      });

      const data = {
        content: [
          { voice_id: 'v1', name: 'Rachel' },
          { voice_id: 'v2', name: 'Drew' }
        ]
      };

      handlers.handleElevenLabsVoices(data);

      // v2 should be selected
      expect(mockElements['#elevenlabs-tts-voice'].val).toHaveBeenCalledWith('v2');
    });

    it('restores saved provider from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'elevenlabs-flash';
        return null;
      });

      const data = {
        content: [{ voice_id: 'v1', name: 'Rachel' }]
      };

      handlers.handleElevenLabsVoices(data);

      expect(mockElements['#tts-provider'].val).toHaveBeenCalledWith('elevenlabs-flash');
    });

    it('does not restore non-elevenlabs provider', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'openai-tts-4o';
        return null;
      });

      const data = {
        content: [{ voice_id: 'v1', name: 'Rachel' }]
      };

      handlers.handleElevenLabsVoices(data);

      // Should not try to set a non-elevenlabs provider
      expect(mockElements['#tts-provider'].val).not.toHaveBeenCalled();
    });
  });

  describe('handleGeminiVoices', () => {
    it('populates voice selector with voices', () => {
      const data = {
        content: [
          { voice_id: 'Aoede', name: 'Aoede' },
          { voice_id: 'Charon', name: 'Charon' }
        ]
      };

      handlers.handleGeminiVoices(data);

      const el = mockElements['#gemini-tts-voice'];
      expect(el.empty).toHaveBeenCalled();
      expect(el._options).toHaveLength(2);
      expect(el._options[0].value).toBe('Aoede');
      expect(el._options[1].value).toBe('Charon');
    });

    it('enables provider and STT options when voices are available', () => {
      const data = {
        content: [{ voice_id: 'Aoede', name: 'Aoede' }]
      };

      handlers.handleGeminiVoices(data);

      expect(mockElements['#gemini-flash-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#gemini-pro-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#gemini-stt-flash'].prop).toHaveBeenCalledWith('disabled', false);
    });

    it('disables all options when no voices', () => {
      const data = { content: [] };

      handlers.handleGeminiVoices(data);

      expect(mockElements['#gemini-flash-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#gemini-pro-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#gemini-stt-flash'].prop).toHaveBeenCalledWith('disabled', true);
    });

    it('restores saved voice from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'gemini-tts-voice') return 'Charon';
        return null;
      });

      const data = {
        content: [
          { voice_id: 'Aoede', name: 'Aoede' },
          { voice_id: 'Charon', name: 'Charon' }
        ]
      };

      handlers.handleGeminiVoices(data);

      expect(mockElements['#gemini-tts-voice'].val).toHaveBeenCalledWith('Charon');
    });

    it('restores saved gemini provider from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'gemini-flash';
        return null;
      });

      const data = {
        content: [{ voice_id: 'Aoede', name: 'Aoede' }]
      };

      handlers.handleGeminiVoices(data);

      expect(mockElements['#tts-provider'].val).toHaveBeenCalledWith('gemini-flash');
    });

    it('does not restore non-gemini provider', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'openai-tts-4o';
        return null;
      });

      const data = { content: [{ voice_id: 'Aoede', name: 'Aoede' }] };

      handlers.handleGeminiVoices(data);

      expect(mockElements['#tts-provider'].val).not.toHaveBeenCalled();
    });
  });

  describe('module exports', () => {
    it('exports handleElevenLabsVoices', () => {
      expect(typeof handlers.handleElevenLabsVoices).toBe('function');
    });

    it('exports handleGeminiVoices', () => {
      expect(typeof handlers.handleGeminiVoices).toBe('function');
    });

    it('exposes handlers on window.WsAppDataHandlers', () => {
      expect(typeof window.WsAppDataHandlers).toBe('object');
      expect(typeof window.WsAppDataHandlers.handleElevenLabsVoices).toBe('function');
      expect(typeof window.WsAppDataHandlers.handleGeminiVoices).toBe('function');
    });
  });
});
