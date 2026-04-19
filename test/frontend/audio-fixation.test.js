/**
 * @jest-environment jsdom
 *
 * Behavioural tests for window.applyAudioFixation defined in monadic.js.
 * Because monadic.js is a single large script that cannot be imported cleanly,
 * we mirror the function body here (same pattern used by monadic.test.js for
 * autoResize / setupTextarea) and verify the behaviour contract.
 */

describe('applyAudioFixation', () => {
  let cookieStore;

  // Mirror of the helpers that exist in monadic.js.
  function $id(id) { return document.getElementById(id); }
  function $dispatch(el, name) {
    if (!el) return;
    el.dispatchEvent(new Event(name, { bubbles: true }));
  }
  function setCookie(k, v) { cookieStore[k] = v; }
  function getCookie(k) { return cookieStore[k] || ''; }

  let params;

  // Cookie-write guard as defined in monadic.js.
  function __audioFixationShouldPersist(event) {
    return !event || event.isTrusted !== false;
  }

  // Mirror of the applyAudioFixation function itself.
  const AUDIO_FIXATION_TTS_PROVIDER_ALIAS = { xai: 'grok' };
  const AUDIO_FIXATION_VOICE_SELECT_BY_PROVIDER = {
    grok: 'grok-tts-voice',
    elevenlabs: 'elevenlabs-tts-voice',
    'elevenlabs-flash': 'elevenlabs-tts-voice',
    'elevenlabs-multilingual': 'elevenlabs-tts-voice',
    'elevenlabs-v3': 'elevenlabs-tts-voice',
    'gemini-flash': 'gemini-tts-voice',
    'gemini-pro': 'gemini-tts-voice',
    mistral: 'mistral-tts-voice'
  };
  const AUDIO_FIXATION_ALL_VOICE_SELECTS = [
    'tts-voice', 'elevenlabs-tts-voice', 'gemini-tts-voice',
    'mistral-tts-voice', 'grok-tts-voice'
  ];
  const AUDIO_FIXATION_LOCK_TITLE = 'Fixed by the current app';

  function applyAudioFixation(appData) {
    if (!appData) return;
    const ttsProviderEl = $id('tts-provider');
    if (ttsProviderEl) {
      if (appData.tts_provider) {
        const uiValue = AUDIO_FIXATION_TTS_PROVIDER_ALIAS[appData.tts_provider] || appData.tts_provider;
        if (ttsProviderEl.value !== uiValue) {
          ttsProviderEl.value = uiValue;
          $dispatch(ttsProviderEl, 'change');
        }
        ttsProviderEl.disabled = true;
        ttsProviderEl.setAttribute('title', AUDIO_FIXATION_LOCK_TITLE);
      } else if (ttsProviderEl.disabled) {
        const saved = getCookie('tts-provider');
        if (saved && saved !== ttsProviderEl.value) {
          ttsProviderEl.value = saved;
          $dispatch(ttsProviderEl, 'change');
        }
        ttsProviderEl.disabled = false;
        ttsProviderEl.removeAttribute('title');
      }
    }
    const activeProviderRaw = appData.tts_provider || params['tts_provider'];
    const activeProvider = AUDIO_FIXATION_TTS_PROVIDER_ALIAS[activeProviderRaw] || activeProviderRaw;
    const activeVoiceSelectId = AUDIO_FIXATION_VOICE_SELECT_BY_PROVIDER[activeProvider] || 'tts-voice';
    AUDIO_FIXATION_ALL_VOICE_SELECTS.forEach(function(id) {
      const el = $id(id);
      if (!el) return;
      if (appData.tts_voice && id === activeVoiceSelectId) {
        if (el.value !== appData.tts_voice) {
          el.value = appData.tts_voice;
          $dispatch(el, 'change');
        }
        el.disabled = true;
        el.setAttribute('title', AUDIO_FIXATION_LOCK_TITLE);
      } else if (el.disabled) {
        const saved = getCookie(id);
        if (saved && saved !== el.value) {
          el.value = saved;
          $dispatch(el, 'change');
        }
        el.disabled = false;
        el.removeAttribute('title');
      }
    });
    const sttEl = $id('stt-model');
    if (sttEl) {
      if (appData.stt_model) {
        if (sttEl.value !== appData.stt_model) {
          sttEl.value = appData.stt_model;
          $dispatch(sttEl, 'change');
        }
        sttEl.disabled = true;
        sttEl.setAttribute('title', AUDIO_FIXATION_LOCK_TITLE);
      } else if (sttEl.disabled) {
        const saved = getCookie('stt-model');
        if (saved && saved !== sttEl.value) {
          sttEl.value = saved;
          $dispatch(sttEl, 'change');
        }
        sttEl.disabled = false;
        sttEl.removeAttribute('title');
      }
    }
  }

  // Set up a select element with a given option list.
  function makeSelect(id, values) {
    const sel = document.createElement('select');
    sel.id = id;
    values.forEach(v => {
      const opt = document.createElement('option');
      opt.value = v;
      opt.textContent = v;
      sel.appendChild(opt);
    });
    document.body.appendChild(sel);
    return sel;
  }

  beforeEach(() => {
    document.body.innerHTML = '';
    cookieStore = {};
    params = {};

    makeSelect('tts-provider', ['openai-tts-4o', 'grok', 'elevenlabs-v3', 'webspeech']);
    makeSelect('tts-voice', ['alloy', 'nova']);
    makeSelect('grok-tts-voice', ['eve', 'ara', 'rex']);
    makeSelect('elevenlabs-tts-voice', ['noah', 'rachel']);
    makeSelect('gemini-tts-voice', ['Kore', 'Puck']);
    makeSelect('mistral-tts-voice', ['v1', 'v2']);
    makeSelect('stt-model', ['whisper-1', 'xai-stt', 'scribe_v2']);
  });

  it('is a no-op when given null / undefined', () => {
    expect(() => applyAudioFixation(null)).not.toThrow();
    expect(() => applyAudioFixation(undefined)).not.toThrow();
  });

  it('locks tts-provider dropdown when tts_provider is set, normalising xai -> grok', () => {
    applyAudioFixation({ tts_provider: 'xai' });
    const el = $id('tts-provider');
    expect(el.value).toBe('grok');
    expect(el.disabled).toBe(true);
    expect(el.getAttribute('title')).toBe(AUDIO_FIXATION_LOCK_TITLE);
  });

  it('locks the correct voice select based on provider', () => {
    applyAudioFixation({ tts_provider: 'xai', tts_voice: 'eve' });
    expect($id('grok-tts-voice').value).toBe('eve');
    expect($id('grok-tts-voice').disabled).toBe(true);
    // Other voice selects should not be fixated
    expect($id('elevenlabs-tts-voice').getAttribute('title')).toBeNull();
  });

  it('locks stt-model when declared', () => {
    applyAudioFixation({ stt_model: 'xai-stt' });
    const el = $id('stt-model');
    expect(el.value).toBe('xai-stt');
    expect(el.disabled).toBe(true);
  });

  it('restores unlocked dropdowns from cookies when app has no fixation', () => {
    // First lock
    applyAudioFixation({ tts_provider: 'xai', tts_voice: 'eve', stt_model: 'xai-stt' });
    expect($id('tts-provider').disabled).toBe(true);

    // User had 'openai-tts-4o' persisted in a cookie before locking
    cookieStore['tts-provider'] = 'openai-tts-4o';
    cookieStore['stt-model'] = 'whisper-1';
    cookieStore['grok-tts-voice'] = 'ara';

    // Switch to an app without fixation
    applyAudioFixation({});

    expect($id('tts-provider').value).toBe('openai-tts-4o');
    expect($id('tts-provider').disabled).toBe(false);
    expect($id('tts-provider').getAttribute('title')).toBeNull();
    expect($id('stt-model').value).toBe('whisper-1');
    expect($id('stt-model').disabled).toBe(false);
    expect($id('grok-tts-voice').value).toBe('ara');
    expect($id('grok-tts-voice').disabled).toBe(false);
  });

  it('dispatches change events that would bypass cookie writes (isTrusted = false)', () => {
    // Attach a listener that simulates what the real cookie-write handler does
    const writes = [];
    $id('tts-provider').addEventListener('change', function(event) {
      if (__audioFixationShouldPersist(event)) {
        writes.push(this.value);
      }
    });

    applyAudioFixation({ tts_provider: 'xai' });
    // Programmatic dispatch produced an untrusted event → cookie write skipped
    expect(writes).toEqual([]);
  });

  describe('__audioFixationShouldPersist', () => {
    it('returns true when no event is provided (defensive default)', () => {
      expect(__audioFixationShouldPersist(null)).toBe(true);
      expect(__audioFixationShouldPersist(undefined)).toBe(true);
    });

    it('returns true for trusted user events', () => {
      expect(__audioFixationShouldPersist({ isTrusted: true })).toBe(true);
    });

    it('returns false for untrusted programmatic events', () => {
      // new Event('change') always has isTrusted === false in browsers and jsdom.
      const programmatic = new Event('change');
      expect(programmatic.isTrusted).toBe(false);
      expect(__audioFixationShouldPersist(programmatic)).toBe(false);
    });
  });
});
