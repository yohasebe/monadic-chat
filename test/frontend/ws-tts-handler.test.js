/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-tts-handler.js
 *
 * Tests TTS-related WebSocket handlers:
 * - handleWebSpeech: Browser Web Speech API synthesis
 * - handleTTSProgress: Spinner update during processing
 * - handleTTSComplete: Generation completion
 * - handleTTSNotice: Partial output warnings
 */

function createMockElement(id) {
  const innerSpan = {
    html: jest.fn().mockReturnThis(),
    removeClass: jest.fn().mockReturnThis(),
    addClass: jest.fn().mockReturnThis()
  };
  return {
    hide: jest.fn().mockReturnThis(),
    show: jest.fn().mockReturnThis(),
    find: jest.fn().mockReturnValue(innerSpan),
    css: jest.fn().mockReturnThis(),
    length: 1,
    0: document.createElement('div')
  };
}

let mockElements;

beforeEach(() => {
  mockElements = {
    '#monadic-spinner': createMockElement('monadic-spinner')
  };

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    return createMockElement('default');
  });

  // Mock global functions
  global.setAlert = jest.fn();
  global.removeStopButtonHighlight = jest.fn();
  global.showTtsNotice = jest.fn();
  global.isSystemBusy = jest.fn().mockReturnValue(false);

  // Window globals
  window.lastTTSMode = null;
  window.autoSpeechActive = false;
  window.autoPlayAudio = false;
  window.ttsSpeak = jest.fn();
  window.speechSynthesis = {
    speak: jest.fn(),
    getVoices: jest.fn().mockReturnValue([])
  };
  // Mock SpeechSynthesisUtterance for jsdom
  global.SpeechSynthesisUtterance = jest.fn().mockImplementation((text) => ({
    text,
    voice: null,
    rate: 1.0,
    onend: null,
    onerror: null
  }));
  window.webUIi18n = undefined;
});

afterEach(() => {
  jest.restoreAllMocks();
  document.body.innerHTML = '';
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-tts-handler');

describe('ws-tts-handler', () => {
  describe('handleWebSpeech', () => {
    it('sets lastTTSMode to web_speech', () => {
      handlers.handleWebSpeech({ content: 'Hello' });
      expect(window.lastTTSMode).toBe('web_speech');
    });

    it('hides the spinner', () => {
      handlers.handleWebSpeech({ content: 'Hello' });
      expect(mockElements['#monadic-spinner'].hide).toHaveBeenCalled();
    });

    it('speaks text using SpeechSynthesis', () => {
      handlers.handleWebSpeech({ content: 'Hello world' });
      expect(window.speechSynthesis.speak).toHaveBeenCalled();
    });

    it('selects voice from UI element', () => {
      const voiceEl = document.createElement('select');
      voiceEl.id = 'webspeech-voice';
      voiceEl.value = 'Google US English';
      document.body.appendChild(voiceEl);

      const mockVoice = { name: 'Google US English' };
      window.speechSynthesis.getVoices = jest.fn().mockReturnValue([mockVoice]);

      handlers.handleWebSpeech({ content: 'test' });

      // Verify speak was called (voice is set on the utterance)
      expect(window.speechSynthesis.speak).toHaveBeenCalled();
    });

    it('sets speech rate from speed element', () => {
      const speedEl = document.createElement('input');
      speedEl.id = 'tts-speed';
      speedEl.value = '1.5';
      document.body.appendChild(speedEl);

      handlers.handleWebSpeech({ content: 'test' });

      expect(window.speechSynthesis.speak).toHaveBeenCalled();
    });

    it('shows warning when Web Speech API not available', () => {
      window.speechSynthesis = null;

      handlers.handleWebSpeech({ content: 'test' });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Web Speech API not available'),
        'warning'
      );
    });

    it('removes stop button highlight when speech not available', () => {
      window.speechSynthesis = null;

      handlers.handleWebSpeech({ content: 'test' });

      expect(global.removeStopButtonHighlight).toHaveBeenCalled();
    });

    it('handles errors gracefully', () => {
      window.speechSynthesis = {
        speak: jest.fn().mockImplementation(() => { throw new Error('test error'); }),
        getVoices: jest.fn().mockReturnValue([])
      };

      handlers.handleWebSpeech({ content: 'test' });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('error'),
        'warning'
      );
      expect(global.removeStopButtonHighlight).toHaveBeenCalled();
    });
  });

  describe('handleTTSProgress', () => {
    it('updates spinner with processing audio message', () => {
      const innerSpan = { html: jest.fn().mockReturnThis() };
      mockElements['#monadic-spinner'].find = jest.fn().mockReturnValue(innerSpan);

      handlers.handleTTSProgress({});

      expect(mockElements['#monadic-spinner'].find).toHaveBeenCalledWith('span');
      expect(innerSpan.html).toHaveBeenCalledWith(
        expect.stringContaining('Processing audio')
      );
    });
  });

  describe('handleTTSComplete', () => {
    it('hides spinner for manual TTS', () => {
      window.autoSpeechActive = false;
      window.autoPlayAudio = false;

      handlers.handleTTSComplete({});

      expect(mockElements['#monadic-spinner'].hide).toHaveBeenCalled();
    });

    it('does not hide spinner for auto speech', () => {
      window.autoSpeechActive = true;

      handlers.handleTTSComplete({});

      expect(mockElements['#monadic-spinner'].hide).not.toHaveBeenCalled();
    });

    it('does not hide spinner for auto play audio', () => {
      window.autoPlayAudio = true;

      handlers.handleTTSComplete({});

      expect(mockElements['#monadic-spinner'].hide).not.toHaveBeenCalled();
    });

    it('resets spinner icon for manual TTS', () => {
      window.autoSpeechActive = false;
      window.autoPlayAudio = false;

      const innerSpan = {
        html: jest.fn().mockReturnThis(),
        removeClass: jest.fn().mockReturnThis(),
        addClass: jest.fn().mockReturnThis()
      };
      // find('span i') returns chainable mock, find('span') returns html-settable mock
      mockElements['#monadic-spinner'].find = jest.fn().mockImplementation(sel => {
        return innerSpan;
      });

      handlers.handleTTSComplete({});

      expect(mockElements['#monadic-spinner'].find).toHaveBeenCalled();
    });
  });

  describe('handleTTSNotice', () => {
    it('shows TTS notice with content', () => {
      handlers.handleTTSNotice({ content: 'Text too long, truncated' });

      expect(global.showTtsNotice).toHaveBeenCalledWith('Text too long, truncated');
    });

    it('does nothing when content is empty', () => {
      handlers.handleTTSNotice({ content: null });

      expect(global.showTtsNotice).not.toHaveBeenCalled();
    });
  });

  describe('handleTTSStopped', () => {
    it('hides spinner', () => {
      handlers.handleTTSStopped({});
      expect(mockElements['#monadic-spinner'].hide).toHaveBeenCalled();
    });

    it('resets responseStarted', () => {
      window.responseStarted = true;
      handlers.handleTTSStopped({});
      expect(window.responseStarted).toBe(false);
    });

    it('shows ready alert when system is not busy', () => {
      global.isSystemBusy = jest.fn().mockReturnValue(false);
      handlers.handleTTSStopped({});
      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Ready to start'),
        'success'
      );
    });

    it('does not show ready alert when system is busy', () => {
      global.isSystemBusy = jest.fn().mockReturnValue(true);
      handlers.handleTTSStopped({});
      expect(global.setAlert).not.toHaveBeenCalled();
    });
  });

  describe('module exports', () => {
    it('exports all five handlers', () => {
      expect(typeof handlers.handleWebSpeech).toBe('function');
      expect(typeof handlers.handleTTSProgress).toBe('function');
      expect(typeof handlers.handleTTSComplete).toBe('function');
      expect(typeof handlers.handleTTSNotice).toBe('function');
      expect(typeof handlers.handleTTSStopped).toBe('function');
    });

    it('exposes handlers on window.WsTTSHandler', () => {
      expect(typeof window.WsTTSHandler).toBe('object');
      expect(typeof window.WsTTSHandler.handleWebSpeech).toBe('function');
    });
  });
});
