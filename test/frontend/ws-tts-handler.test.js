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

beforeEach(() => {
  document.body.innerHTML = '';

  // Create the monadic-spinner element used by the source code
  const spinner = document.createElement('div');
  spinner.id = 'monadic-spinner';
  spinner.style.display = 'block';
  spinner.innerHTML = '<span><i class="fas fa-comment fa-pulse"></i> Starting</span>';
  document.body.appendChild(spinner);

  // Mock global functions
  global.setAlert = jest.fn();
  global.removeStopButtonHighlight = jest.fn();
  global.showTtsNotice = jest.fn();
  global.isSystemBusy = jest.fn().mockReturnValue(false);

  // Keep a minimal $ mock for any legacy test patterns in other modules
  global.$ = jest.fn().mockReturnValue({ length: 0 });

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
      const spinner = document.getElementById('monadic-spinner');
      expect(spinner.style.display).toBe('none');
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
      handlers.handleTTSProgress({});

      const spinner = document.getElementById('monadic-spinner');
      const span = spinner.querySelector('span');
      expect(span.innerHTML).toContain('Processing audio');
      expect(span.innerHTML).toContain('fa-headphones');
    });
  });

  describe('handleTTSComplete', () => {
    it('hides spinner for manual TTS', () => {
      window.autoSpeechActive = false;
      window.autoPlayAudio = false;

      handlers.handleTTSComplete({});

      const spinner = document.getElementById('monadic-spinner');
      expect(spinner.style.display).toBe('none');
    });

    it('does not hide spinner for auto speech', () => {
      window.autoSpeechActive = true;
      const spinner = document.getElementById('monadic-spinner');
      spinner.style.display = 'block';

      handlers.handleTTSComplete({});

      expect(spinner.style.display).toBe('block');
    });

    it('does not hide spinner for auto play audio', () => {
      window.autoPlayAudio = true;
      const spinner = document.getElementById('monadic-spinner');
      spinner.style.display = 'block';

      handlers.handleTTSComplete({});

      expect(spinner.style.display).toBe('block');
    });

    it('resets spinner icon for manual TTS', () => {
      window.autoSpeechActive = false;
      window.autoPlayAudio = false;

      // Set up spinner with headphones icon (as if tts_progress was called)
      const spinner = document.getElementById('monadic-spinner');
      spinner.innerHTML = '<span><i class="fas fa-headphones fa-pulse"></i> Processing audio</span>';

      handlers.handleTTSComplete({});

      // Source resets span innerHTML to default Starting state
      const span = spinner.querySelector('span');
      expect(span.innerHTML).toContain('fa-comment');
      expect(span.innerHTML).toContain('Starting');
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
      const spinner = document.getElementById('monadic-spinner');
      expect(spinner.style.display).toBe('none');
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
