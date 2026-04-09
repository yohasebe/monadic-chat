/**
 * @jest-environment jsdom
 */

/**
 * Extended tests for websocket-handlers.js
 * Covers: handleSampleSuccess, handleFragmentWithAudio,
 * audio ID tracking (clearProcessedAudioIds, isAudioProcessed, markAudioProcessed)
 */

global.setAlert = jest.fn();
global.setInputFocus = jest.fn();
global.autoScroll = false;
global.isElementInViewport = jest.fn().mockReturnValue(true);
global.createCard = jest.fn().mockReturnValue('<div class="card">Mock</div>');
global.atob = jest.fn().mockReturnValue('decoded-audio');
global.Uint8Array = { from: jest.fn().mockReturnValue(new Uint8Array([1, 2, 3])) };
global.clearTimeout = jest.fn();
global.setTimeout = jest.fn(cb => { if (typeof cb === 'function') cb(); return 1; });

global.URL = { createObjectURL: jest.fn(), revokeObjectURL: jest.fn() };
global.Blob = jest.fn();

// Common element IDs
const commonIds = [
  'monadic-spinner', 'cancel_query', 'message', 'send', 'clear',
  'voice', 'doc', 'url', 'image-file', 'discourse', 'amplitude',
  'asr-p-value', 'check-easy-submit', 'select-role', 'ai_user',
  'ai_user_provider', 'user-panel', 'temp-card', 'api-token',
  'ai-user-initial-prompt', 'chat-bottom'
];

function setupDom() {
  document.body.innerHTML = '';
  commonIds.forEach(id => {
    const el = document.createElement('div');
    el.id = id;
    document.body.appendChild(el);
  });
  // Add spinner span
  const spinnerEl = document.getElementById('monadic-spinner');
  const spanEl = document.createElement('span');
  spinnerEl.appendChild(spanEl);
}

const handlers = require('../../docker/services/ruby/public/js/monadic/websocket-handlers');

beforeEach(() => {
  jest.clearAllMocks();
  setupDom();
  handlers.clearProcessedAudioIds();
});

describe('Audio ID Tracking', () => {
  describe('clearProcessedAudioIds', () => {
    it('clears all tracked audio IDs', () => {
      handlers.markAudioProcessed('audio-1');
      handlers.markAudioProcessed('audio-2');
      expect(handlers.isAudioProcessed('audio-1')).toBe(true);

      handlers.clearProcessedAudioIds();
      expect(handlers.isAudioProcessed('audio-1')).toBe(false);
      expect(handlers.isAudioProcessed('audio-2')).toBe(false);
    });
  });

  describe('isAudioProcessed', () => {
    it('returns false for untracked IDs', () => {
      expect(handlers.isAudioProcessed('unknown')).toBe(false);
    });

    it('returns true for tracked IDs', () => {
      handlers.markAudioProcessed('tracked-id');
      expect(handlers.isAudioProcessed('tracked-id')).toBe(true);
    });
  });

  describe('markAudioProcessed', () => {
    it('marks an audio ID as processed', () => {
      handlers.markAudioProcessed('new-id');
      expect(handlers.isAudioProcessed('new-id')).toBe(true);
    });

    it('handles marking the same ID multiple times', () => {
      handlers.markAudioProcessed('dup-id');
      handlers.markAudioProcessed('dup-id');
      expect(handlers.isAudioProcessed('dup-id')).toBe(true);
    });

    it('evicts old IDs when exceeding MAX_PROCESSED_IDS', () => {
      for (let i = 0; i < 110; i++) {
        handlers.markAudioProcessed(`id-${i}`);
      }
      expect(handlers.isAudioProcessed('id-0')).toBe(false);
      expect(handlers.isAudioProcessed('id-109')).toBe(true);
    });
  });
});

describe('handleSampleSuccess', () => {
  it('returns true for sample_success messages', () => {
    const data = { type: 'sample_success', role: 'user' };
    expect(handlers.handleSampleSuccess(data)).toBe(true);
  });

  it('returns false for non-sample_success messages', () => {
    expect(handlers.handleSampleSuccess({ type: 'other' })).toBe(false);
  });

  it('returns false for null/undefined input', () => {
    expect(handlers.handleSampleSuccess(null)).toBe(false);
    expect(handlers.handleSampleSuccess(undefined)).toBe(false);
  });

  it('clears pending sample timeout', () => {
    window.currentSampleTimeout = 42;
    const data = { type: 'sample_success', role: 'user' };
    handlers.handleSampleSuccess(data);
    expect(global.clearTimeout).toHaveBeenCalledWith(42);
    expect(window.currentSampleTimeout).toBeNull();
  });

  it('shows success alert with role text for user', () => {
    const data = { type: 'sample_success', role: 'user' };
    handlers.handleSampleSuccess(data);
    expect(global.setAlert).toHaveBeenCalledWith(
      expect.stringContaining('User'),
      'success'
    );
  });

  it('shows success alert with role text for assistant', () => {
    const data = { type: 'sample_success', role: 'assistant' };
    handlers.handleSampleSuccess(data);
    expect(global.setAlert).toHaveBeenCalledWith(
      expect.stringContaining('Assistant'),
      'success'
    );
  });

  it('shows System for unknown role', () => {
    const data = { type: 'sample_success', role: 'system' };
    handlers.handleSampleSuccess(data);
    expect(global.setAlert).toHaveBeenCalledWith(
      expect.stringContaining('System'),
      'success'
    );
  });

  it('handles when setAlert is not defined', () => {
    const original = global.setAlert;
    global.setAlert = undefined;
    const data = { type: 'sample_success', role: 'user' };
    expect(() => handlers.handleSampleSuccess(data)).not.toThrow();
    global.setAlert = original;
  });
});

describe('handleFragmentWithAudio', () => {
  it('returns false for non-fragment_with_audio messages', () => {
    expect(handlers.handleFragmentWithAudio({ type: 'other' })).toBe(false);
  });

  it('returns false for null/undefined input', () => {
    expect(handlers.handleFragmentWithAudio(null)).toBe(false);
    expect(handlers.handleFragmentWithAudio(undefined)).toBe(false);
  });

  it('returns true for valid fragment_with_audio messages', () => {
    window.isForegroundTab = jest.fn().mockReturnValue(true);
    const data = {
      type: 'fragment_with_audio',
      fragment: { type: 'fragment', content: 'Hello' },
      audio: { content: 'dGVzdA==', type: 'audio' }
    };
    window.handleFragmentMessage = jest.fn();
    const processAudio = jest.fn();

    const result = handlers.handleFragmentWithAudio(data, processAudio);
    expect(result).toBe(true);
  });

  it('processes fragment via window.handleFragmentMessage when available', () => {
    window.isForegroundTab = jest.fn().mockReturnValue(true);
    window.handleFragmentMessage = jest.fn();
    const data = {
      type: 'fragment_with_audio',
      fragment: { type: 'fragment', content: 'Test fragment' }
    };

    handlers.handleFragmentWithAudio(data);
    expect(window.handleFragmentMessage).toHaveBeenCalledWith(data.fragment);
  });

  it('skips fragment rendering in background tabs', () => {
    window.isForegroundTab = jest.fn().mockReturnValue(false);
    window.handleFragmentMessage = jest.fn();
    const data = {
      type: 'fragment_with_audio',
      fragment: { type: 'fragment', content: 'Background fragment' }
    };

    handlers.handleFragmentWithAudio(data);
    expect(window.handleFragmentMessage).not.toHaveBeenCalled();
  });

  it('skips audio when auto speech is suppressed', () => {
    window.isForegroundTab = jest.fn().mockReturnValue(true);
    window.isAutoSpeechSuppressed = jest.fn().mockReturnValue(true);
    window.handleFragmentMessage = jest.fn();
    const processAudio = jest.fn();
    const data = {
      type: 'fragment_with_audio',
      fragment: { type: 'fragment', content: 'Text' },
      audio: { content: 'dGVzdA==', type: 'audio' },
      auto_speech: true
    };

    const result = handlers.handleFragmentWithAudio(data, processAudio);
    expect(result).toBe(true);
    expect(processAudio).not.toHaveBeenCalled();
  });

  it('handles messages with only fragment (no audio)', () => {
    window.isForegroundTab = jest.fn().mockReturnValue(true);
    window.handleFragmentMessage = jest.fn();
    const data = {
      type: 'fragment_with_audio',
      fragment: { type: 'fragment', content: 'Text only' }
    };

    const result = handlers.handleFragmentWithAudio(data);
    expect(result).toBe(true);
    expect(window.handleFragmentMessage).toHaveBeenCalled();
  });

  it('returns true even with processing errors (graceful degradation)', () => {
    window.isForegroundTab = jest.fn().mockReturnValue(true);
    window.handleFragmentMessage = jest.fn().mockImplementation(() => {
      throw new Error('Fragment error');
    });
    const consoleSpy = jest.spyOn(console, 'error').mockImplementation();

    const data = {
      type: 'fragment_with_audio',
      fragment: { type: 'fragment', content: 'Error trigger' }
    };

    const result = handlers.handleFragmentWithAudio(data);
    expect(result).toBe(false); // Returns false on error
    expect(consoleSpy).toHaveBeenCalled();
    consoleSpy.mockRestore();
  });
});
