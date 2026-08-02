/**
 * @jest-environment jsdom
 */

/**
 * Live Conversation — the dedicated speech-to-speech app UI.
 *
 * The pinned invariants are about session discipline, learned from the five
 * integration gaps of the integrated design:
 *   - the mode is driven by the APP flag (speech_to_speech), nothing else
 *   - Start sends STS_START with the greet flag derived from the
 *     initiate checkbox AND an empty conversation (resume never greets)
 *   - every audio chunk carries chat_model (deterministic routing input)
 *   - Stop tears everything down and unlocks cards — including when the
 *     SERVER reports the session stopped (mic must not stream into a dead
 *     bridge)
 *   - capture failure aborts honestly (no half-started conversation)
 */

let LC;
let sent;
let capture;

beforeEach(() => {
  jest.resetModules();
  document.body.innerHTML = `
    <div id="user-panel">
      <div class="row"><textarea id="message"></textarea></div>
    </div>
    <div id="discourse"></div>
    <select id="model"><option value="gpt-realtime-2.1" selected>r</option></select>
    <input type="checkbox" id="initiate-from-assistant" checked>
  `;
  window.$id = (id) => document.getElementById(id);
  window.$on = (el, ev, fn) => el && el.addEventListener(ev, fn);
  window.$dispatch = (el, ev) => el && el.dispatchEvent(new Event(ev, { bubbles: true }));
  sent = [];
  window.safeWsSend = jest.fn((m) => { sent.push(m); return true; });
  window.messages = [];
  window.setAlert = jest.fn();

  LC = require('../../docker/services/ruby/public/js/monadic/live-conversation');
  capture = { stop: jest.fn() };
  LC._setCaptureFactory(jest.fn(async (onChunk) => {
    capture.onChunk = onChunk;
    return capture;
  }));
});

afterEach(() => {
  LC._reset();
  delete window.safeWsSend;
  delete window.messages;
  delete window.setAlert;
  delete window.LiveConversation;
  document.body.className = '';
});

const lcApp = { speech_to_speech: true, app_name: 'LiveConversationOpenAI' };
const normalApp = { app_name: 'ChatOpenAI' };

describe('app-mode switching', () => {
  it('enters LC mode only for apps declaring speech_to_speech', () => {
    LC.setAppMode(lcApp);
    expect(document.body.classList.contains('lc-app')).toBe(true);
    expect(document.getElementById('lc-panel')).not.toBeNull();

    LC.setAppMode(normalApp);
    expect(document.body.classList.contains('lc-app')).toBe(false);
  });

  it('accepts the flag as a string ("true") since app data crosses JSON', () => {
    LC.setAppMode({ speech_to_speech: 'true' });
    expect(LC.isLcMode()).toBe(true);
  });

  // Hiding the toggles is not enough: a checked auto-speech carried over from
  // another app would TTS the assistant card on top of the realtime audio.
  it('force-unchecks auto-speech and easy-submit on entering LC mode', () => {
    document.body.insertAdjacentHTML('beforeend',
      '<input type="checkbox" id="check-auto-speech" checked>' +
      '<input type="checkbox" id="check-easy-submit" checked>');
    const changed = [];
    document.getElementById('check-auto-speech')
      .addEventListener('change', () => changed.push('auto-speech'));

    LC.setAppMode(lcApp);

    expect(document.getElementById('check-auto-speech').checked).toBe(false);
    expect(document.getElementById('check-easy-submit').checked).toBe(false);
    expect(changed).toContain('auto-speech'); // listeners must see the change
  });

  // CSS and JS can skew (cached stylesheet vs fresh markup left the AI User
  // row operable in dogfood) — the JS inline enforcement must not depend on
  // the stylesheet at all.
  it('inline-hides pipeline-only UI on entering LC mode and restores it on exit', () => {
    document.body.insertAdjacentHTML('beforeend',
      '<div id="ai-user-row"></div><div id="voice-panel"></div>');

    LC.setAppMode(lcApp);
    expect(document.getElementById('ai-user-row').style.display).toBe('none');
    expect(document.getElementById('voice-panel').style.display).toBe('none');

    LC.setAppMode(normalApp);
    expect(document.getElementById('ai-user-row').style.display).toBe('');
    expect(document.getElementById('voice-panel').style.display).toBe('');
  });

  // Review P1-B: setAppMode(off) runs at the end of EVERY loadParams. It
  // must restore only what LC itself hid (none!important signature) — an
  // unconditional removeProperty stripped hides that loadParams had just
  // applied for ordinary apps (e.g. $hide of #model_parameters).
  it('leaves non-LC inline hides intact when exiting LC mode', () => {
    document.body.insertAdjacentHTML('beforeend',
      '<div id="model_parameters"></div><div id="voice-panel"></div>');
    // Simulate loadParams' own $hide (plain inline none, no priority)
    document.getElementById('model_parameters').style.display = 'none';

    LC.setAppMode(lcApp);   // LC re-hides with none!important
    LC.setAppMode(normalApp);

    // LC's own hide restored…
    expect(document.getElementById('voice-panel').style.display).toBe('');
    // …but a hide LC re-asserted over gets restored too (LC signature wins);
    // the critical case: an element LC never touched with importance keeps
    // its plain hide. Re-hide model_parameters plainly after exit to model
    // the ordinary-app loadParams order (hide happens before setAppMode).
    document.getElementById('model_parameters').style.display = 'none';
    LC.setAppMode(normalApp); // another non-LC loadParams pass
    expect(document.getElementById('model_parameters').style.display).toBe('none');
  });

  it('stops an active conversation when switching to a normal app', async () => {
    LC.setAppMode(lcApp);
    await LC.startConversation();
    expect(LC.isActive()).toBe(true);

    LC.setAppMode(normalApp);

    expect(LC.isActive()).toBe(false);
    expect(capture.stop).toHaveBeenCalled();
    expect(sent.map(m => m.message)).toContain('STS_STOP');
  });
});

describe('start', () => {
  beforeEach(() => LC.setAppMode(lcApp));

  it('sends STS_START with greet=true for a fresh conversation', async () => {
    await LC.startConversation();

    const start = sent.find(m => m.message === 'STS_START');
    expect(start).toEqual({ message: 'STS_START', chat_model: 'gpt-realtime-2.1', greet: true });
  });

  // Resume-vs-fresh is decided SERVER-side against the canonical
  // session[:messages]; the client's messages array proved stale in dogfood
  // and silently suppressed the greeting. The client only reports the
  // toggle state — even with local messages present.
  it('sends the toggle state regardless of the local messages array', async () => {
    window.messages = [{ role: 'user', text: 'earlier turn' }];

    await LC.startConversation();

    expect(sent.find(m => m.message === 'STS_START').greet).toBe(true);
  });

  it('honors the initiate checkbox being off', async () => {
    document.getElementById('initiate-from-assistant').checked = false;

    await LC.startConversation();

    expect(sent.find(m => m.message === 'STS_START').greet).toBe(false);
  });

  it('locks cards while active', async () => {
    await LC.startConversation();
    expect(document.body.classList.contains('lc-locked')).toBe(true);
  });

  // Gemini Live consumes 16kHz input while OpenAI/xAI take 24kHz — the
  // capture rate comes from the app's MDSL (sts_input_rate), not a constant.
  it('passes the app-declared capture rate to the capture factory', async () => {
    const factory = jest.fn(async () => capture);
    LC._setCaptureFactory(factory);
    LC.setAppMode({ speech_to_speech: true, sts_input_rate: '16000' });

    await LC.startConversation();

    expect(factory).toHaveBeenCalledWith(expect.any(Function), 16000);
  });

  it('defaults the capture rate to 24000 when the app declares none', async () => {
    const factory = jest.fn(async () => capture);
    LC._setCaptureFactory(factory);
    LC.setAppMode(lcApp);

    await LC.startConversation();

    expect(factory).toHaveBeenCalledWith(expect.any(Function), 24000);
  });

  it('streams captured chunks as AUDIO_CHUNK with chat_model', async () => {
    await LC.startConversation();

    capture.onChunk(new ArrayBuffer(8));

    const chunk = sent.find(m => m.message === 'AUDIO_CHUNK');
    expect(chunk).toBeTruthy();
    expect(chunk.chat_model).toBe('gpt-realtime-2.1');
    expect(typeof chunk.content).toBe('string');
  });

  // P2-2 (review finding): getUserMedia's permission prompt is arbitrarily
  // long; a Stop (or RESET) landing during the await must leave no orphaned
  // capture streaming and must not open the bridge.
  it('releases the capture and sends no STS_START when stopped mid-startup', async () => {
    let resolveCapture;
    LC._setCaptureFactory(jest.fn(() => new Promise(res => { resolveCapture = res; })));

    const starting = LC.startConversation();
    LC.stopConversation();          // user stops while the prompt is up
    resolveCapture(capture);        // permission granted too late
    await starting;

    expect(capture.stop).toHaveBeenCalled();
    expect(LC.isActive()).toBe(false);
    expect(sent.find(m => m.message === 'STS_START')).toBeUndefined();
  });

  // Echo gate: with speakers the assistant's own voice leaks into the mic
  // and the upstream VAD answers itself. While playback is audible, quiet
  // chunks are dropped; loud (direct) speech passes so barge-in survives.
  describe('echo gate', () => {
    function pcmChunk(amplitude) {
      const samples = new Int16Array(240);
      samples.fill(Math.round(amplitude * 32767));
      return samples.buffer;
    }

    afterEach(() => {
      delete window.WsStsPlayback;
      delete window.LC_ECHO_GATE_RMS;
    });

    it('drops quiet chunks while assistant audio is playing', async () => {
      window.WsStsPlayback = { isPlaying: () => true, stopAll: () => {} };
      await LC.startConversation();
      sent.length = 0;

      capture.onChunk(pcmChunk(0.005)); // below the default RMS gate

      expect(sent.find(m => m.message === 'AUDIO_CHUNK')).toBeUndefined();
    });

    it('passes loud chunks during playback (barge-in must survive)', async () => {
      window.WsStsPlayback = { isPlaying: () => true, stopAll: () => {} };
      await LC.startConversation();
      sent.length = 0;

      capture.onChunk(pcmChunk(0.2));

      expect(sent.find(m => m.message === 'AUDIO_CHUNK')).toBeTruthy();
    });

    it('passes quiet chunks when nothing is playing', async () => {
      window.WsStsPlayback = { isPlaying: () => false, stopAll: () => {} };
      await LC.startConversation();
      sent.length = 0;

      capture.onChunk(pcmChunk(0.005));

      expect(sent.find(m => m.message === 'AUDIO_CHUNK')).toBeTruthy();
    });

    it('window.LC_ECHO_GATE_RMS = 0 disables the gate', async () => {
      window.WsStsPlayback = { isPlaying: () => true, stopAll: () => {} };
      window.LC_ECHO_GATE_RMS = 0;
      await LC.startConversation();
      sent.length = 0;

      capture.onChunk(pcmChunk(0.005));

      expect(sent.find(m => m.message === 'AUDIO_CHUNK')).toBeTruthy();
    });
  });

  it('drops chunks from a worklet callback that outlives the conversation', async () => {
    await LC.startConversation();
    LC.stopConversation();
    sent.length = 0;

    capture.onChunk(new ArrayBuffer(8));

    expect(sent.find(m => m.message === 'AUDIO_CHUNK')).toBeUndefined();
  });

  it('aborts honestly when the microphone fails', async () => {
    LC._setCaptureFactory(jest.fn(async () => { throw new Error('NotAllowed'); }));

    await LC.startConversation();

    expect(LC.isActive()).toBe(false);
    expect(document.body.classList.contains('lc-locked')).toBe(false);
    expect(sent.find(m => m.message === 'STS_START')).toBeUndefined();
    expect(window.setAlert).toHaveBeenCalled();
  });
});

describe('stop', () => {
  beforeEach(async () => {
    LC.setAppMode(lcApp);
    await LC.startConversation();
  });

  it('sends STS_STOP, releases the mic, and unlocks cards', () => {
    LC.stopConversation();

    expect(sent.map(m => m.message)).toContain('STS_STOP');
    expect(capture.stop).toHaveBeenCalled();
    expect(document.body.classList.contains('lc-locked')).toBe(false);
    expect(LC.isActive()).toBe(false);
  });

  it('mirrors a server-side stop so the mic never streams into a dead bridge', () => {
    LC.onStsSession({ state: 'stopped' });

    expect(capture.stop).toHaveBeenCalled();
    expect(LC.isActive()).toBe(false);
  });

  // Stop-time consolidation folds VAD-split fragments server-side; the
  // client re-renders the discourse from the canon only when told so.
  it('reloads the discourse when the server merged fragments at stop', () => {
    LC.onStsSession({ state: 'stopped', merged: true });

    expect(sent.find(m => m.message === 'LOAD')).toBeTruthy();
  });

  it('does not reload when nothing was merged', () => {
    sent.length = 0;
    LC.onStsSession({ state: 'stopped', merged: false });

    expect(sent.find(m => m.message === 'LOAD')).toBeUndefined();
  });

  it('marks the toggle with the live style while active, violet otherwise', () => {
    const btn = document.getElementById('lc-toggle');
    expect(btn.classList.contains('btn-lc')).toBe(true);
    expect(btn.classList.contains('btn-lc-live')).toBe(true); // active (from beforeEach)

    LC.stopConversation();
    expect(btn.classList.contains('btn-lc-live')).toBe(false);
    expect(btn.classList.contains('btn-lc')).toBe(true);
  });
});

describe('live user transcript (temp card)', () => {
  beforeEach(async () => {
    // The temp card belongs to CARD view; the default live view renders
    // user speech into its own current zone instead.
    window.params = { sts_card_view: true };
    LC.setAppMode(lcApp);
    await LC.startConversation();
  });

  afterEach(() => {
    delete window.params;
  });

  it('renders partials into a temp card and clears it on the final transcript', () => {
    LC.onSttPartial({ content: 'hello wor' });

    const temp = document.getElementById('lc-user-temp');
    expect(temp).not.toBeNull();
    expect(temp.textContent).toContain('hello wor');

    LC.onStt({ content: 'hello world' });
    expect(document.getElementById('lc-user-temp')).toBeNull();
  });

  it('ignores partials when no conversation is active', () => {
    LC.stopConversation();
    LC.onSttPartial({ content: 'stray' });
    expect(document.getElementById('lc-user-temp')).toBeNull();
  });
});

describe('intro card + trailing action icon + idle auto-stop', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('shows the panel instruction while the conversation is empty and hides it on Start', async () => {
    LC.setAppMode(lcApp);
    const el = document.getElementById('lc-instruction');
    expect(el).not.toBeNull();
    expect(el.style.display).not.toBe('none');
    expect(el.textContent.length).toBeGreaterThan(0);

    await LC.startConversation();
    expect(el.style.display).toBe('none');
  });

  it('shows no instruction when the conversation already has messages', () => {
    window.messages = [{ role: 'user', text: 'earlier' }];
    LC.setAppMode(lcApp);
    expect(document.getElementById('lc-instruction').style.display).toBe('none');
  });

  it('renders the ACTION icon after the label: play idle, stop while live', async () => {
    LC.setAppMode(lcApp);
    const icon = document.getElementById('lc-action-icon');
    expect(icon.className).toContain('fa-play');
    // trailing position: icon is the last element inside the button
    expect(document.getElementById('lc-toggle').lastElementChild).toBe(icon);

    await LC.startConversation();
    expect(icon.className).toContain('fa-stop');
  });

  it('auto-stops after the idle window with no speech either way', async () => {
    window.setAlert = jest.fn();
    LC.setAppMode(lcApp);
    await LC.startConversation();
    expect(LC.isActive()).toBe(true);

    jest.advanceTimersByTime(190000); // default idle window is 180s

    expect(LC.isActive()).toBe(false);
    expect(capture.stop).toHaveBeenCalled();
    expect(window.setAlert).toHaveBeenCalled();
  });

  it('activity (VAD / partials / assistant audio) defers the idle stop', async () => {
    LC.setAppMode(lcApp);
    await LC.startConversation();

    jest.advanceTimersByTime(170000);
    LC.onStsVad({ event: 'speech_started' }); // user speaks at t=170s
    jest.advanceTimersByTime(170000);         // only 170s since activity

    expect(LC.isActive()).toBe(true);

    jest.advanceTimersByTime(20000);          // now past the window
    expect(LC.isActive()).toBe(false);
  });

  it('sts_idle_stop_seconds 0 disables the idle stop', async () => {
    LC.setAppMode({ speech_to_speech: true, sts_idle_stop_seconds: '0' });
    await LC.startConversation();

    jest.advanceTimersByTime(600000);

    expect(LC.isActive()).toBe(true);
  });
});

describe('streaming-surface ordering + auto-scroll (onCardAppended)', () => {
  beforeEach(() => {
    LC.setAppMode(lcApp);
    window.isElementInViewport = () => false;
    Element.prototype.scrollIntoView = jest.fn();
  });

  afterEach(() => {
    delete window.isElementInViewport;
    delete Element.prototype.scrollIntoView;
    delete window.autoScroll;
  });

  function discourse() { return document.getElementById('discourse'); }

  it('moves a visible temp-card below a newly appended card', () => {
    discourse().innerHTML =
      '<div id="temp-card" class="card" style=""></div>' +
      '<div class="card" id="new-user-card"></div>';

    LC.onCardAppended();

    const ids = Array.from(discourse().children).map(el => el.id);
    expect(ids).toEqual(['new-user-card', 'temp-card']);
  });

  it('keeps the live user transcript below the temp-card (interrupting speech is newer)', async () => {
    window.params = { sts_card_view: true }; // lc-user-temp exists only in card view
    await LC.startConversation();
    LC.onSttPartial({ content: 'user is talking' }); // creates #lc-user-temp
    discourse().insertAdjacentHTML('afterbegin', '<div id="temp-card" class="card" style=""></div>');
    discourse().insertAdjacentHTML('afterbegin', '<div class="card" id="finalized"></div>');

    LC.onCardAppended();

    const ids = Array.from(discourse().children).map(el => el.id);
    expect(ids).toEqual(['finalized', 'temp-card', 'lc-user-temp']);
    delete window.params;
  });

  it('does not resurrect a hidden temp-card', () => {
    discourse().innerHTML =
      '<div id="temp-card" class="card" style="display:none"></div>' +
      '<div class="card" id="latest"></div>';

    LC.onCardAppended();

    const ids = Array.from(discourse().children).map(el => el.id);
    expect(ids).toEqual(['temp-card', 'latest']);
  });

  it('scrolls the newest element into view when auto-scroll is on', () => {
    discourse().innerHTML = '<div class="card" id="latest"></div>';
    window.autoScroll = true;

    LC.onCardAppended();

    expect(Element.prototype.scrollIntoView).toHaveBeenCalled();
  });

  it('respects the auto-scroll toggle being off', () => {
    discourse().innerHTML = '<div class="card" id="latest"></div>';
    window.autoScroll = false;

    LC.onCardAppended();

    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
  });

  // appendCard is the single place finalized cards enter the DOM; the LC
  // hook must be wired there or the ordering invariant silently dies.
  it('websocket.js appendCard calls the LC hook (source pin)', () => {
    const fs = require('fs');
    const path = require('path');
    const src = fs.readFileSync(path.resolve(__dirname, '../..',
      'docker/services/ruby/public/js/monadic/websocket.js'), 'utf8');
    const start = src.indexOf('function appendCard(');
    const end = src.indexOf('window.appendCard = appendCard');
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    expect(src.slice(start, end)).toMatch(/onCardAppended/);
  });
});

describe('card text refresh (sts_card_text)', () => {
  beforeEach(() => LC.setAppMode(lcApp));

  function addCard(mid, text) {
    document.getElementById('discourse').insertAdjacentHTML('beforeend',
      '<div class="card" id="' + mid + '"><div class="card-body">' +
      '<div class="card-text"><p>' + text + '</p></div></div></div>');
  }

  it('replaces the card body in place by mid', () => {
    addCard('m1', 'partial answ');

    LC.onCardText({ mid: 'm1', content: 'partial answer, full sentence.' });

    const body = document.querySelector('#m1 .card-text');
    expect(body.textContent).toBe('partial answer, full sentence.');
  });

  it('is injection-safe via textContent (no escaping dependency)', () => {
    addCard('m2', 'x');

    LC.onCardText({ mid: 'm2', content: '<img src=x onerror=alert(1)>' });

    expect(document.querySelector('#m2 .card-text').innerHTML).not.toContain('<img');
    expect(document.querySelector('#m2 .card-text').textContent).toContain('<img src=x');
  });

  it('ignores unknown mids without throwing', () => {
    expect(() => LC.onCardText({ mid: 'nope', content: 'x' })).not.toThrow();
  });

  it('is grow-only: shorter text does not replace the card body', () => {
    addCard('m3', 'the full text already present');

    LC.onCardText({ mid: 'm3', content: 'short' });

    expect(document.querySelector('#m3 .card-text').textContent)
      .toBe('the full text already present');
  });

  it('is inert outside LC mode', () => {
    addCard('m4', 'x');
    LC.setAppMode(normalApp);

    LC.onCardText({ mid: 'm4', content: 'much longer replacement text' });

    expect(document.querySelector('#m4 .card-text').textContent).toBe('x');
  });
});

describe('status line', () => {
  beforeEach(async () => {
    LC.setAppMode(lcApp);
    await LC.startConversation();
  });

  const status = () => document.getElementById('lc-status').textContent;

  it('follows VAD events', () => {
    LC.onStsVad({ event: 'speech_started' });
    expect(status()).toMatch(/speaking/i);

    LC.onStsVad({ event: 'speech_stopped' });
    expect(status()).toMatch(/listening/i);
  });

  it('shows assistant speech from audio deltas and returns to listening', () => {
    LC.onAssistantAudio();
    expect(status()).toMatch(/assistant/i);

    LC.onAssistantAudioEnd();
    expect(status()).toMatch(/listening/i);
  });

  it('reports reconnecting and recovers on started', () => {
    LC.onStsSession({ state: 'reconnecting' });
    expect(status()).toMatch(/reconnecting/i);

    LC.onStsSession({ state: 'started' });
    expect(status()).toMatch(/listening/i);
  });
});

describe('voice and speed controls', () => {
  const stsSpec = {
    'gpt-realtime-2.1': {
      supports_speech_to_speech: true,
      sts_provider: 'openai',
      sts_voice: 'alloy',
      sts_voices: ['alloy', 'marin', 'cedar'],
      sts_speed_capability: true
    },
    'grok-voice-think-fast-2.0': {
      supports_speech_to_speech: true,
      sts_provider: 'xai',
      sts_voice: 'eve',
      sts_voices: ['eve', 'ara', 'luna']
    }
  };

  beforeEach(() => {
    window.modelSpec = stsSpec;
    window.params = {};
    window.broadcastParamsUpdate = jest.fn();
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.modelSpec;
    delete window.params;
    delete window.broadcastParamsUpdate;
  });

  const select = () => document.getElementById('lc-voice-select');

  it('populates the selector from model_spec sts_voices with the spec default selected', () => {
    expect(select()).not.toBeNull();
    expect([...select().options].map(o => o.value)).toEqual(['alloy', 'marin', 'cedar']);
    expect(select().value).toBe('alloy');
  });

  it('prefers params.sts_voice over the spec default', () => {
    window.params['sts_voice'] = 'marin';
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(select().value).toBe('marin');
  });

  it('writes params.sts_voice and broadcasts on change', () => {
    select().value = 'cedar';
    select().dispatchEvent(new Event('change', { bubbles: true }));
    expect(window.params['sts_voice']).toBe('cedar');
    expect(window.broadcastParamsUpdate).toHaveBeenCalledWith('sts_voice_change');
  });

  it('shows the speed control only for sts_speed_capability models', () => {
    const wrap = document.getElementById('lc-speed-wrap');
    expect(wrap.style.display).not.toBe('none');

    const modelEl = document.getElementById('model');
    modelEl.replaceChildren(new Option('grok-voice-think-fast-2.0', 'grok-voice-think-fast-2.0', true, true));
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(document.getElementById('lc-speed-wrap').style.display).toBe('none');
    expect([...select().options].map(o => o.value)).toEqual(['eve', 'ara', 'luna']);
    expect(select().value).toBe('eve');
  });

  it('writes params.sts_speed and broadcasts on speed change', () => {
    const range = document.getElementById('lc-speed-range');
    range.value = '1.25';
    range.dispatchEvent(new Event('change', { bubbles: true }));
    expect(window.params['sts_speed']).toBe('1.25');
    expect(window.broadcastParamsUpdate).toHaveBeenCalledWith('sts_speed_change');
    expect(document.getElementById('lc-speed-value').textContent).toBe('1.25');
  });
});

describe('websearch toggle (native search, capability-gated)', () => {
  const wsSpec = {
    'gpt-realtime-2.1': {
      supports_speech_to_speech: true,
      sts_provider: 'openai',
      sts_voice: 'alloy',
      sts_voices: ['alloy']
    },
    'grok-voice-think-fast-2.0': {
      supports_speech_to_speech: true,
      sts_provider: 'xai',
      sts_voice: 'eve',
      sts_voices: ['eve'],
      sts_websearch_capability: true
    },
    'gemini-3.1-flash-live-preview': {
      supports_speech_to_speech: true,
      sts_provider: 'gemini',
      sts_voice: 'Kore',
      sts_voices: ['Kore'],
      sts_websearch_capability: true
    }
  };

  beforeEach(() => {
    window.modelSpec = wsSpec;
    window.params = {};
    window.broadcastParamsUpdate = jest.fn();
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.modelSpec;
    delete window.params;
    delete window.broadcastParamsUpdate;
  });

  const wrap = () => document.getElementById('lc-websearch-wrap');
  const toggle = () => document.getElementById('lc-websearch-toggle');
  const setModel = (m) => {
    const el = document.getElementById('model');
    el.replaceChildren(new Option(m, m, true, true));
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
  };

  it('is hidden for OpenAI (no sts_websearch_capability) and shown for xAI/Gemini', () => {
    expect(wrap().style.display).toBe('none');

    setModel('grok-voice-think-fast-2.0');
    expect(wrap().style.display).toBe('flex');
    // xAI cost note removed (user decision)
    expect(document.getElementById('lc-websearch-note').textContent).toBe('');

    setModel('gemini-3.1-flash-live-preview');
    expect(wrap().style.display).toBe('flex');
    // Gemini keeps only the sources-not-shown caveat (ToS)
    expect(document.getElementById('lc-websearch-note').textContent).toMatch(/sources not shown/i);
  });

  it('defaults to OFF (cost safety) even when the capability exists', () => {
    setModel('grok-voice-think-fast-2.0');
    expect(toggle().checked).toBe(false);
  });

  it('reflects params.websearch when set', () => {
    window.params['websearch'] = true;
    setModel('grok-voice-think-fast-2.0');
    expect(toggle().checked).toBe(true);
  });

  it('writes params.websearch and broadcasts on change', () => {
    setModel('grok-voice-think-fast-2.0');
    toggle().checked = true;
    toggle().dispatchEvent(new Event('change', { bubbles: true }));
    expect(window.params['websearch']).toBe(true);
    expect(window.broadcastParamsUpdate).toHaveBeenCalledWith('websearch_toggle');
  });
});

describe('live view (non-card display, default during active)', () => {
  beforeEach(() => {
    window.params = {};
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
  });

  const start = async () => { await LC.startConversation(); };
  const discourse = () => document.getElementById('discourse');
  const lv = () => document.getElementById('lc-liveview');
  const prevText = () => document.querySelector('#lc-live-prev .lc-live-text').textContent;
  const curText = () => document.querySelector('#lc-live-current .lc-live-text').textContent;

  it('hides discourse and shows the 2-zone live view while active (default)', async () => {
    await start();
    expect(discourse().style.display).toBe('none');
    expect(lv().style.display).toBe('block');
  });

  it('fills current zone with user partial, then promotes it when assistant streams', async () => {
    await start();
    LC.onSttPartial({ content: 'hello there' });
    expect(curText()).toBe('hello there');

    LC.onAssistantFragment({ content: 'Hi! ', is_first: true });
    expect(prevText()).toBe('hello there');
    expect(curText()).toBe('Hi! ');

    LC.onAssistantFragment({ content: 'nice to meet you.' });
    expect(curText()).toBe('Hi! nice to meet you.');
  });

  it('promotes the assistant turn to prev on the next user utterance', async () => {
    await start();
    LC.onSttPartial({ content: 'q1' });
    LC.onAssistantFragment({ content: 'a1', is_first: true });
    LC.onSttPartial({ content: 'q2' });
    expect(prevText()).toBe('a1');
    expect(curText()).toBe('q2');
  });

  it('restores discourse on Stop (always returns to the card list)', async () => {
    await start();
    expect(discourse().style.display).toBe('none');
    LC.stopConversation();
    expect(discourse().style.display).not.toBe('none');
    expect(lv().style.display).toBe('none');
  });

  it('restores discourse on _reset', async () => {
    await start();
    LC._reset();
    expect(discourse().style.display).not.toBe('none');
  });

  it('keeps discourse visible in card view (sts_card_view on)', async () => {
    window.params['sts_card_view'] = true;
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    await start();
    expect(discourse().style.display).not.toBe('none');
    expect(lv().style.display).toBe('none');
  });

  it('switches immediately when the card view toggle changes', async () => {
    await start();
    const toggle = document.getElementById('lc-cardview-toggle');
    toggle.checked = true;
    toggle.dispatchEvent(new Event('change', { bubbles: true }));
    expect(discourse().style.display).not.toBe('none');
    expect(window.params['sts_card_view']).toBe(true);
  });

  it('updates the assistant zone on sts_card_text (interrupted card refresh)', async () => {
    await start();
    LC.onAssistantFragment({ content: 'partial ans', is_first: true });
    // sts_card_text requires the real card to exist (it always does in prod)
    discourse().insertAdjacentHTML('beforeend',
      '<div class="card" id="mid-x"><div class="card-text">partial ans</div></div>');
    LC.onCardText({ mid: 'mid-x', content: 'partial answer in full' });
    expect(curText()).toBe('partial answer in full');
  });

  it('suppresses the user temp card while live view is active', async () => {
    await start();
    LC.onSttPartial({ content: 'hi' });
    expect(document.getElementById('lc-user-temp')).toBeNull();
  });
});

describe('live view empty-transcript guard', () => {
  beforeEach(() => {
    window.params = {};
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
  });

  it('does not promote or bubble on blank stt (hallucination suppression)', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'assistant talking', is_first: true });
    const before = document.querySelector('#lc-live-current .lc-live-text').textContent;

    // Server sends blank stt when it suppresses a hallucinated transcript:
    // the assistant zone must stay put and no empty You bubble may appear.
    LC.onStt({ content: '' });
    LC.onSttPartial({ content: '' });

    expect(document.querySelector('#lc-live-current .lc-live-text').textContent).toBe(before);
    expect(document.querySelector('#lc-live-prev .lc-live-text').textContent).toBe('');
  });
});

describe('panel layout and model-ready re-render', () => {
  beforeEach(() => {
    window.modelSpec = {
      'gpt-realtime-2.1': { supports_speech_to_speech: true, sts_provider: 'openai',
                            sts_voice: 'alloy', sts_voices: ['alloy'] },
      'grok-voice-think-fast-2.0': { supports_speech_to_speech: true, sts_provider: 'xai',
                            sts_voice: 'eve', sts_voices: ['eve', 'luna'] }
    };
    window.params = {};
  });

  afterEach(() => {
    delete window.modelSpec;
    delete window.params;
  });

  it('decomposes the toggle: app label is plain text, the button holds only the action', () => {
    LC.setAppMode(lcApp);
    const btn = document.getElementById('lc-toggle');
    expect(btn.querySelector('.fa-tower-broadcast')).toBeNull();
    expect(document.getElementById('lc-app-label')).not.toBeNull();
    expect(document.getElementById('lc-app-label').textContent.length).toBeGreaterThan(0);
    // action icon stays inside the button
    expect(btn.querySelector('#lc-action-icon')).not.toBeNull();
  });

  it('places the voice-controls row above the Start/Stop button row', () => {
    LC.setAppMode(lcApp);
    const panel = document.getElementById('lc-panel');
    const rows = [...panel.children].map(el => el.id || el.className);
    const controlsIdx = rows.indexOf('lc-controls-row');
    const buttonRowIdx = rows.findIndex((_, i) =>
      panel.children[i].contains(document.getElementById('lc-toggle')));
    expect(controlsIdx).toBeGreaterThanOrEqual(0);
    expect(controlsIdx).toBeLessThan(buttonRowIdx);
  });

  it('re-populates the voice selector when the model select changes after load', () => {
    // Start with an EMPTY model select (async dropdown not built yet)
    const modelEl = document.getElementById('model');
    modelEl.replaceChildren();
    LC.setAppMode(lcApp);
    expect(document.getElementById('lc-voice-select').options.length).toBe(0);

    // Dropdown is built later → change event re-renders
    modelEl.replaceChildren(new Option('grok-voice-think-fast-2.0', 'grok-voice-think-fast-2.0', true, true));
    modelEl.dispatchEvent(new Event('change', { bubbles: true }));
    const sel = document.getElementById('lc-voice-select');
    expect([...sel.options].map(o => o.value)).toEqual(['eve', 'luna']);
  });
});

describe('live view resume-swap (late stt_partial during assistant stream)', () => {
  beforeEach(() => {
    window.params = {};
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
  });

  const curText = () => document.querySelector('#lc-live-current .lc-live-text').textContent;
  const prevText = () => document.querySelector('#lc-live-prev .lc-live-text').textContent;

  it('keeps the full assistant text when a late stt_partial interleaves mid-stream', async () => {
    await LC.startConversation();
    LC.onStt({ content: 'user question' });
    LC.onAssistantFragment({ content: 'Sorry, that ', is_first: true });
    LC.onAssistantFragment({ content: 'sounded ' });

    // late partial for the SAME user utterance mid-stream (server sends
    // cumulative partials while the assistant is already answering)
    LC.onSttPartial({ content: 'user question' });
    LC.onAssistantFragment({ content: 'a bit cut off.' });

    expect(curText()).toBe('Sorry, that sounded a bit cut off.');
  });

  it('resets accumulation on a real barge-in (is_first of the new response)', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'first answer ', is_first: true });
    LC.onSttPartial({ content: 'interrupt!' });
    LC.onAssistantFragment({ content: 'second answer', is_first: true });
    expect(curText()).toBe('second answer');
  });

  it('keeps the interleaved user text in prev after the swap', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'assistant ', is_first: true });
    LC.onSttPartial({ content: 'user text' });
    LC.onAssistantFragment({ content: 'continues' });
    expect(curText()).toBe('assistant continues');
    expect(prevText()).toBe('user text');
  });
});

describe('websearch toggle mirrors into the standard #websearch checkbox', () => {
  const wsSpec = {
    'grok-voice-think-fast-2.0': {
      supports_speech_to_speech: true, sts_provider: 'xai',
      sts_voice: 'eve', sts_voices: ['eve'], sts_websearch_capability: true
    }
  };

  beforeEach(() => {
    // the standard (hidden in LC) checkbox that sanitizeParamsForSync reads
    document.body.insertAdjacentHTML('beforeend',
      '<input type="checkbox" id="websearch">');
    window.modelSpec = wsSpec;
    window.params = {};
    window.broadcastParamsUpdate = jest.fn();
    const modelEl = document.getElementById('model');
    modelEl.replaceChildren(new Option('grok-voice-think-fast-2.0', 'grok-voice-think-fast-2.0', true, true));
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    document.getElementById('websearch').remove();
    delete window.modelSpec;
    delete window.params;
    delete window.broadcastParamsUpdate;
  });

  it('mirrors the LC toggle state so sanitize keeps websearch=true', () => {
    const toggle = document.getElementById('lc-websearch-toggle');
    toggle.checked = true;
    toggle.dispatchEvent(new Event('change', { bubbles: true }));

    expect(window.params['websearch']).toBe(true);
    // sanitizeParamsForSync reads THIS checkbox as the source of truth —
    // without the mirror it would overwrite the broadcast with false.
    expect(document.getElementById('websearch').checked).toBe(true);
  });

  it('renders params.websearch=true into BOTH checkboxes at load', () => {
    window.params['websearch'] = true;
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(document.getElementById('lc-websearch-toggle').checked).toBe(true);
    expect(document.getElementById('websearch').checked).toBe(true);
  });

  it('mirrors BEFORE broadcasting so the toggle\'s own broadcast carries true', () => {
    // Order matters: sanitizeParamsForSync (called inside the broadcast)
    // reads the standard checkbox. Mirroring after the broadcast would make
    // the toggle's own UPDATE_PARAMS carry the stale false, the server echo
    // then rolls params back, and a toggle→Start flow opens the STS session
    // without tools (the audit-caught ordering regression).
    let checkedAtBroadcast = null;
    window.broadcastParamsUpdate = jest.fn(() => {
      checkedAtBroadcast = document.getElementById('websearch').checked;
    });

    const toggle = document.getElementById('lc-websearch-toggle');
    toggle.checked = true;
    toggle.dispatchEvent(new Event('change', { bubbles: true }));

    expect(window.broadcastParamsUpdate).toHaveBeenCalled();
    expect(checkedAtBroadcast).toBe(true);
  });
});

describe('tools toggle (function calling wave 1)', () => {
  const toolsSpec = {
    'gpt-realtime-2.1': { supports_speech_to_speech: true, sts_provider: 'openai',
                          sts_voice: 'alloy', sts_voices: ['alloy'], sts_tools_capability: true }
  };

  beforeEach(() => {
    window.modelSpec = toolsSpec;
    window.params = {};
    window.broadcastParamsUpdate = jest.fn();
    const modelEl = document.getElementById('model');
    modelEl.replaceChildren(new Option('gpt-realtime-2.1', 'gpt-realtime-2.1', true, true));
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.modelSpec;
    delete window.params;
    delete window.broadcastParamsUpdate;
  });

  it('shows the toggle for sts_tools_capability models, default OFF, with next-Start note', () => {
    const wrap = document.getElementById('lc-tools-wrap');
    expect(wrap.style.display).toBe('flex');
    expect(document.getElementById('lc-tools-toggle').checked).toBe(false);
  });

  it('writes params.sts_tools and broadcasts on change', () => {
    const toggle = document.getElementById('lc-tools-toggle');
    toggle.checked = true;
    toggle.dispatchEvent(new Event('change', { bubbles: true }));
    expect(window.params['sts_tools']).toBe(true);
    expect(window.broadcastParamsUpdate).toHaveBeenCalledWith('sts_tools_toggle');
  });

  it('reflects params.sts_tools when set', () => {
    window.params['sts_tools'] = true;
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(document.getElementById('lc-tools-toggle').checked).toBe(true);
  });
});
