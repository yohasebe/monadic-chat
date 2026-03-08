/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-audio-handler.js
 *
 * Tests audio and fragment_with_audio WebSocket message handlers:
 * - handleFragmentWithAudio: Delegation to wsHandlers
 * - handleAudio: Delegation with fallback error handling and device-specific processing
 */

function createMockElement(id) {
  return {
    length: 1,
    0: document.createElement('div'),
    hide: jest.fn().mockReturnThis(),
    show: jest.fn().mockReturnThis(),
    val: jest.fn().mockReturnValue(''),
    prop: jest.fn().mockReturnThis()
  };
}

let mockElements;

beforeEach(() => {
  mockElements = {
    '#monadic-spinner': createMockElement('monadic-spinner'),
    '#tts-provider': createMockElement('tts-provider')
  };

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    return createMockElement('default');
  });

  global.setAlert = jest.fn();
  global.getTranslation = jest.fn().mockImplementation((key, fallback) => fallback);

  // Window globals
  window.wsHandlers = null;
  window.mediaSource = null;
  window.audio = null;
  window.audioDataQueue = [];
  window.processAudioDataQueue = jest.fn();
  window.initializeMediaSourceForAudio = jest.fn();
  window.playAudioDirectly = jest.fn();
  window.basicAudioMode = false;
  window.firefoxAudioMode = false;
  window.firefoxAudioQueue = null;
  window.autoSpeechActive = false;
  window.autoPlayAudio = false;
  window.globalAudioQueue = [];
  window.getIsProcessingAudioQueue = jest.fn().mockReturnValue(false);
  window.WsAudioQueue = { getCurrentSegmentAudio: jest.fn().mockReturnValue(null) };
  window.WsAudioPlayback = { playPCMAudio: jest.fn() };
  window.WsAudioConstants = { MAX_AUDIO_QUEUE_SIZE: 50 };
  window.debugWebSocket = false;
});

afterEach(() => {
  jest.restoreAllMocks();
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-audio-handler');

describe('ws-audio-handler', () => {
  describe('handleFragmentWithAudio', () => {
    it('delegates to wsHandlers.handleFragmentWithAudio', () => {
      const mockHandler = jest.fn().mockReturnValue(true);
      window.wsHandlers = { handleFragmentWithAudio: mockHandler };

      handlers.handleFragmentWithAudio({ type: 'fragment_with_audio', content: 'test' });

      expect(mockHandler).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'fragment_with_audio' }),
        expect.any(Function)
      );
    });

    it('logs warning when not handled', () => {
      const warnSpy = jest.spyOn(console, 'warn').mockImplementation();
      handlers.handleFragmentWithAudio({ type: 'fragment_with_audio' });
      expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('not handled'));
      warnSpy.mockRestore();
    });

    it('processAudio callback calls processAudioDataQueue for standard browsers', () => {
      let capturedProcessAudio;
      window.wsHandlers = {
        handleFragmentWithAudio: jest.fn((data, processAudio) => {
          capturedProcessAudio = processAudio;
          return true;
        })
      };
      window.mediaSource = {}; // Non-null to skip init

      handlers.handleFragmentWithAudio({ type: 'fragment_with_audio' });

      // Call the captured processAudio callback
      const audioData = new Uint8Array([1, 2, 3]);
      capturedProcessAudio(audioData);

      expect(window.processAudioDataQueue).toHaveBeenCalled();
    });

    it('processAudio callback uses Firefox queue when in Firefox mode', () => {
      let capturedProcessAudio;
      window.wsHandlers = {
        handleFragmentWithAudio: jest.fn((data, processAudio) => {
          capturedProcessAudio = processAudio;
          return true;
        })
      };
      window.firefoxAudioMode = true;
      window.firefoxAudioQueue = [];

      handlers.handleFragmentWithAudio({ type: 'fragment_with_audio' });

      const audioData = new Uint8Array([1, 2, 3]);
      capturedProcessAudio(audioData);

      expect(window.firefoxAudioQueue).toHaveLength(1);
      expect(window.processAudioDataQueue).toHaveBeenCalled();
    });

    it('processAudio callback uses playAudioDirectly in basic mode', () => {
      let capturedProcessAudio;
      window.wsHandlers = {
        handleFragmentWithAudio: jest.fn((data, processAudio) => {
          capturedProcessAudio = processAudio;
          return true;
        })
      };
      window.basicAudioMode = true;

      handlers.handleFragmentWithAudio({ type: 'fragment_with_audio' });

      capturedProcessAudio(new Uint8Array([1, 2, 3]));

      expect(window.playAudioDirectly).toHaveBeenCalled();
    });
  });

  describe('handleAudio', () => {
    it('delegates to wsHandlers.handleAudioMessage', () => {
      const mockHandler = jest.fn().mockReturnValue(true);
      window.wsHandlers = { handleAudioMessage: mockHandler };

      handlers.handleAudio({ type: 'audio', content: btoa('test') });

      expect(mockHandler).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'audio' }),
        expect.any(Function)
      );
    });

    it('hides spinner when not auto speech in fallback mode', () => {
      window.autoSpeechActive = false;
      window.autoPlayAudio = false;

      handlers.handleAudio({ type: 'audio', content: btoa('test') });

      expect(mockElements['#monadic-spinner'].hide).toHaveBeenCalled();
    });

    it('does not hide spinner when auto speech is active', () => {
      window.autoSpeechActive = true;

      handlers.handleAudio({ type: 'audio', content: btoa('test') });

      expect(mockElements['#monadic-spinner'].hide).not.toHaveBeenCalled();
    });

    it('skips duplicate audio in fallback', () => {
      const debugSpy = jest.spyOn(console, 'debug').mockImplementation();
      window.wsHandlers = {
        handleAudioMessage: jest.fn().mockReturnValue(false),
        isAudioProcessed: jest.fn().mockReturnValue(true)
      };

      handlers.handleAudio({ type: 'audio', content: btoa('test'), sequence_id: 'seq-1' });

      expect(debugSpy).toHaveBeenCalledWith(expect.stringContaining('Skipping duplicate'), expect.anything());
      debugSpy.mockRestore();
    });

    it('handles API error in object format', () => {
      const errorSpy = jest.spyOn(console, 'error').mockImplementation();
      const mockErrorHandler = jest.fn();
      window.wsHandlers = {
        handleAudioMessage: jest.fn().mockReturnValue(false),
        isAudioProcessed: jest.fn().mockReturnValue(false),
        markAudioProcessed: jest.fn(),
        handleErrorMessage: mockErrorHandler
      };

      handlers.handleAudio({
        type: 'audio',
        content: { error: 'test error', type: 'error' }
      });

      expect(mockErrorHandler).toHaveBeenCalled();
      errorSpy.mockRestore();
    });

    it('handles PCM audio from Gemini', () => {
      window.wsHandlers = {
        handleAudioMessage: jest.fn().mockReturnValue(false),
        isAudioProcessed: jest.fn().mockReturnValue(false),
        markAudioProcessed: jest.fn()
      };
      mockElements['#tts-provider'].val = jest.fn().mockReturnValue('gemini-flash');

      handlers.handleAudio({
        type: 'audio',
        content: btoa('test-pcm-data'),
        mime_type: 'audio/L16;codec=pcm;rate=24000'
      });

      expect(window.WsAudioPlayback.playPCMAudio).toHaveBeenCalledWith(
        expect.anything(),
        24000
      );
    });

    it('processes audio through Firefox queue when in Firefox mode', () => {
      window.wsHandlers = {
        handleAudioMessage: jest.fn().mockReturnValue(false),
        isAudioProcessed: jest.fn().mockReturnValue(false),
        markAudioProcessed: jest.fn()
      };
      window.firefoxAudioMode = true;
      window.firefoxAudioQueue = [];

      handlers.handleAudio({ type: 'audio', content: btoa('test') });

      expect(window.firefoxAudioQueue.length).toBeGreaterThan(0);
      expect(window.processAudioDataQueue).toHaveBeenCalled();
    });

    it('processes audio through basic mode for iOS', () => {
      window.wsHandlers = {
        handleAudioMessage: jest.fn().mockReturnValue(false),
        isAudioProcessed: jest.fn().mockReturnValue(false),
        markAudioProcessed: jest.fn()
      };
      window.basicAudioMode = true;

      handlers.handleAudio({ type: 'audio', content: btoa('test') });

      expect(window.playAudioDirectly).toHaveBeenCalled();
    });
  });

  describe('module exports', () => {
    it('exports handleAudio and handleFragmentWithAudio', () => {
      expect(typeof handlers.handleAudio).toBe('function');
      expect(typeof handlers.handleFragmentWithAudio).toBe('function');
    });

    it('exposes on window.WsAudioHandler', () => {
      expect(typeof window.WsAudioHandler).toBe('object');
    });
  });
});
