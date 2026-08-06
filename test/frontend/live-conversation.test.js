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
  // startConversation sets this global (§37-7). Leaving it set would leak a
  // "the user already interacted" state into whatever suite runs next — the
  // test-isolation defect class this repo has been bitten by before.
  delete window.userHasInteractedInTab;
  delete window.responseStarted;
  delete window.streamingResponse;
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

  // §37-7: the app-switch reset confirmation keys on userHasInteractedInTab,
  // which only the TEXT submit paths set — a voice-only session left it
  // false and the switch wiped the conversation without asking.
  it('marks the tab as user-interacted (voice conversation is a user action)', async () => {
    delete window.userHasInteractedInTab; // an earlier start in this file set it
    await LC.startConversation();
    expect(window.userHasInteractedInTab).toBe(true);
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
    // inline-flex, not flex: a block-level flex next to the plain-inline
    // cardview wrap shifts the baseline (dogfood: misaligned checkboxes).
    expect(wrap.style.display).toBe('inline-flex');

    const modelEl = document.getElementById('model');
    modelEl.replaceChildren(new Option('grok-voice-think-fast-2.0', 'grok-voice-think-fast-2.0', true, true));
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(document.getElementById('lc-speed-wrap').style.display).toBe('none');
    expect([...select().options].map(o => o.value)).toEqual(['eve', 'ara', 'luna']);
    expect(select().value).toBe('eve');
  });

  // §37-14A: the voice choice is remembered per provider in a cookie
  // (sets are disjoint), restored only when the value is still offered.
  describe('voice cookie', () => {
    let store;
    beforeEach(() => {
      store = {};
      window.setCookie = jest.fn((k, v) => { store[k] = v; });
      window.getCookie = jest.fn((k) => store[k]);
    });
    afterEach(() => {
      delete window.setCookie;
      delete window.getCookie;
    });

    it('saves the choice under a per-provider key on change', () => {
      select().value = 'cedar';
      select().dispatchEvent(new Event('change', { bubbles: true }));
      expect(window.setCookie).toHaveBeenCalledWith('lc-voice-openai', 'cedar', 30);
    });

    it('restores the remembered voice when it is still offered', () => {
      store['lc-voice-openai'] = 'marin';
      LC.setAppMode(normalApp);
      LC.setAppMode(lcApp);
      expect(select().value).toBe('marin');
    });

    it('ignores a remembered voice the current model does not offer', () => {
      store['lc-voice-openai'] = 'retired-voice';
      LC.setAppMode(normalApp);
      LC.setAppMode(lcApp);
      expect(select().value).toBe('alloy'); // spec default, not the stale value
    });

    it('uses a different key per provider (no cross-provider bleed)', () => {
      store['lc-voice-xai'] = 'luna';
      const modelEl = document.getElementById('model');
      modelEl.replaceChildren(new Option('grok-voice-think-fast-2.0', 'grok-voice-think-fast-2.0', true, true));
      LC.setAppMode(normalApp);
      LC.setAppMode(lcApp);
      expect(select().value).toBe('luna');
    });

    // Switching provider leaves the PREVIOUS provider's voice in params.
    // Trusting the param unchecked would beat this provider's remembered
    // voice and then be rejected server-side (the lists share no ids).
    it('ignores a session param voice that this provider does not offer', () => {
      window.params['sts_voice'] = 'sage';      // an OpenAI voice
      store['lc-voice-xai'] = 'luna';           // what the user picked on xAI
      const modelEl = document.getElementById('model');
      modelEl.replaceChildren(new Option('grok-voice-think-fast-2.0', 'grok-voice-think-fast-2.0', true, true));
      LC.setAppMode(normalApp);
      LC.setAppMode(lcApp);
      expect(select().value).toBe('luna');
      expect(window.params['sts_voice']).toBe('luna'); // param realigned
    });
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

describe('live view zone discipline (§37-6: partial stream lags the response)', () => {
  beforeEach(() => {
    window.params = {};
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
  });

  const curText = () => document.querySelector('#lc-live-current .lc-live-text').textContent;
  const prevText = () => document.querySelector('#lc-live-prev .lc-live-text').textContent;

  it('keeps the full assistant text when a late partial of a FINALIZED utterance arrives', async () => {
    await LC.startConversation();
    LC.onStt({ content: 'user question' });
    LC.onAssistantFragment({ content: 'Sorry, that ', is_first: true });
    LC.onAssistantFragment({ content: 'sounded ' });

    // Late partial for the SAME finalized utterance mid-stream — a prefix
    // of the final, so it is display-only noise and must not move zones.
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

  // The measured dogfood round 6 path: the response starts BEFORE the
  // transcription finishes streaming, so fragments and partials interleave.
  // A resume-swap per fragment ping-ponged the same utterance between zones.
  it('does not ping-pong when fragments interleave an in-flight partial stream', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'ちょっと調', is_first: true });
    LC.onSttPartial({ content: '今日' });
    LC.onSttPartial({ content: '今日の天気は' });
    LC.onAssistantFragment({ content: 'べ' }); // fragment mid-partial-stream
    LC.onSttPartial({ content: '今日の天気はどうなる' });
    LC.onAssistantFragment({ content: 'るから、' });

    // Mid-stream (before the final): the user's LIVE transcript stays in
    // current and the response accumulates in prev — the old resume-swap
    // moved the partial to prev on every fragment, flickering the same
    // utterance between zones.
    expect(curText()).toBe('今日の天気はどうなる');
    expect(prevText()).toBe('ちょっと調べるから、');

    LC.onStt({ content: '今日の天気はどうなるだろう。' });
    LC.onAssistantFragment({ content: '午後の様子を' });

    // After the final: the finalized user text takes prev (resume-swap)
    // and the response continues in current.
    expect(curText()).toBe('ちょっと調べるから、午後の様子を');
    expect(prevText()).toBe('今日の天気はどうなるだろう。');
  });

  it('keeps the interleaved FINAL user text in prev after the swap', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'assistant ', is_first: true });
    LC.onSttPartial({ content: 'user text' });
    LC.onStt({ content: 'user text' }); // final — now the swap may happen
    LC.onAssistantFragment({ content: 'continues' });
    expect(curText()).toBe('assistant continues');
    expect(prevText()).toBe('user text');
  });

  it('never shows the same utterance in both zones (invariant b belt)', async () => {
    await LC.startConversation();
    LC.onStt({ content: 'same words' });
    LC.onAssistantFragment({ content: 'reply ', is_first: true });
    // A late re-stream must not resurrect the utterance in current while
    // it sits in prev.
    LC.onSttPartial({ content: 'same words' });
    const prevRole = document.querySelector('#lc-live-prev .lc-live-role').textContent;
    const curRole = document.querySelector('#lc-live-current .lc-live-role').textContent;
    expect(prevRole === curRole && prevText() !== '').toBe(false);
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
    expect(wrap.style.display).toBe('inline-flex');
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

describe('tool-use visibility in the live view (§37-5)', () => {
  beforeEach(() => {
    window.params = {};
    window.insertInlineToolBadge =
      require('../../docker/services/ruby/public/js/monadic/card-renderer').insertInlineToolBadge;
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
    delete window.insertInlineToolBadge;
  });

  it('anchors the tool badge at the paragraph boundary of the answer', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Let me check.', is_first: true });
    LC.onToolCall({ name: 'search_web', status: 'running' });
    LC.onToolCall({ name: 'search_web', status: 'done' });
    LC.onAssistantFragment({ content: 'The answer is 42.', is_first: true });

    const text = document.querySelector('#lc-live-current .lc-live-text');
    const paras = text.querySelectorAll(':scope > p');
    // Same semantics as the folded card: one accumulation, "\n\n" paragraphs.
    expect(paras.length).toBe(2);
    expect(paras[0].textContent).toBe('Let me check.');
    expect(paras[1].textContent).toBe('The answer is 42.');
    const badge = text.querySelector('.lc-tools-badge');
    expect(badge).not.toBeNull();
    expect(badge.textContent).toContain('search_web');
    expect(badge.nextElementSibling).toBe(paras[1]);
  });

  it('anchors sequential calls of one exchange at the same boundary', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'One moment.', is_first: true });
    LC.onToolCall({ name: 'get_current_time', status: 'running' });
    LC.onToolCall({ name: 'get_current_time', status: 'done' });
    LC.onToolCall({ name: 'search_web', status: 'running' });
    LC.onToolCall({ name: 'search_web', status: 'error' });
    LC.onAssistantFragment({ content: 'Combined answer.', is_first: true });

    const text = document.querySelector('#lc-live-current .lc-live-text');
    // §40: calls at the SAME boundary merge into one badge — unique names
    // joined, worst status (the error) coloring the whole badge.
    const badges = text.querySelectorAll('.lc-tools-badge');
    expect(badges.length).toBe(1);
    expect(badges[0].textContent).toContain('get_current_time');
    expect(badges[0].textContent).toContain('search_web');
    expect(badges[0].className).toContain('mc-badge--red'); // any error → red
    expect(text.querySelectorAll(':scope > p').length).toBe(2);
  });

  // §40: on every provider the tool continuation is the SAME turn, so its
  // first fragment carries no is_first — the server marks it tool_break
  // instead. Without handling it, the answer ran into the bridge paragraph
  // and the badge fell to the bottom (dogfood 2026-08-05, OpenAI).
  it('tool_break anchors the paragraph break and badge without is_first', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Let me check the forecast.', is_first: true, segment_id: 'r1' });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });
    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c1' });
    LC.onAssistantFragment({ content: 'Tomorrow looks sunny.', tool_break: true, segment_id: 'r2' });

    const text = document.querySelector('#lc-live-current .lc-live-text');
    const paras = text.querySelectorAll(':scope > p');
    expect(paras.length).toBe(2);
    expect(paras[0].textContent).toBe('Let me check the forecast.');
    expect(paras[1].textContent).toBe('Tomorrow looks sunny.');
    const badge = text.querySelector('.lc-tools-badge');
    expect(badge).not.toBeNull();
    expect(badge.nextElementSibling).toBe(paras[1]);
    // The segment map records the continuation at the POST-break offset, so
    // the speech highlight maps r2's playback onto r2's characters.
    const segs = LC._liveSegments();
    expect(segs).toEqual([
      { id: 'r1', startChar: 0 },
      { id: 'r2', startChar: 'Let me check the forecast.'.length + 2 }
    ]);
  });

  // §40: the segment map lives ON the zone, so the promote → resume-swap
  // round trip (a late user final landing mid-stream) no longer wipes it —
  // that wipe is what killed the speech highlight in dogfood.
  it('the segment map survives a late user final promoting the zone', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'First part of the reply. ', is_first: true, segment_id: 'r1' });
    // Late user final: promotes the in-flight assistant zone to prev.
    LC.onStt({ content: 'the user utterance' });
    // The stream resumes: resume-swap pulls the zone back with its map.
    LC.onAssistantFragment({ content: 'Second part.', segment_id: 'r1' });

    const segs = LC._liveSegments();
    expect(segs).toEqual([{ id: 'r1', startChar: 0 }]);
    const text = document.querySelector('#lc-live-current .lc-live-text');
    expect(text.textContent).toContain('First part of the reply. Second part.');
  });

  it('a new segment starting right after a resume-swap anchors at the resumed end, not 0', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Bridge before swap.', is_first: true, segment_id: 'r1' });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });
    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c1' });
    LC.onStt({ content: 'late user final' });
    // The continuation's first fragment arrives while the zone sits in prev:
    // resume-swap restores it, and r2 must map to the APPENDED text.
    LC.onAssistantFragment({ content: 'Continuation.', segment_id: 'r2' });

    const segs = LC._liveSegments();
    expect(segs[segs.length - 1]).toEqual(
      { id: 'r2', startChar: 'Bridge before swap.'.length });
  });

  it('discards the pending anchor when the next response is not the tool answer (barge-in)', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Let me check.', is_first: true });
    LC.onToolCall({ name: 'search_web', status: 'running' });
    // The user barges in before the tool's answer arrives.
    LC.onStt({ content: 'wait, never mind' });
    LC.onAssistantFragment({ content: 'Sure, what else?', is_first: true });

    const text = document.querySelector('#lc-live-current .lc-live-text');
    expect(text.querySelector('.lc-tools-badge')).toBeNull();
    expect(text.textContent).not.toContain('Let me check.');
  });

  it('no longer shows a tool chip on the role label (superseded by inline badges)', async () => {
    await LC.startConversation();
    LC.onToolCall({ name: 'run_code', status: 'running' });
    LC.onAssistantFragment({ content: 'checking', is_first: false });
    const role = document.querySelector('#lc-live-current .lc-live-role').textContent;
    expect(role).not.toContain('run_code');
  });

  it('shows "Using …" in the status line while running', async () => {
    await LC.startConversation();
    LC.onToolCall({ name: 'get_current_time', status: 'running' });
    expect(document.getElementById('lc-status').textContent).toContain('get_current_time');
  });
});

describe('running tool badge spins until done (§37-12)', () => {
  beforeEach(() => {
    window.params = {};
    window.insertInlineToolBadge =
      require('../../docker/services/ruby/public/js/monadic/card-renderer').insertInlineToolBadge;
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
    delete window.insertInlineToolBadge;
  });

  const curZone = () => document.querySelector('#lc-live-current .lc-live-text');
  const badges = () => curZone().querySelectorAll('.lc-tools-badge');

  it('draws the badge immediately at running with a spinning icon', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Let me check.', is_first: true });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });

    expect(badges().length).toBe(1);
    expect(badges()[0].textContent).toContain('search_web');
    expect(badges()[0].querySelector('i').className).toContain('fa-spin');
    // positioned at the boundary (before the paragraph the answer will start)
    expect(badges()[0].nextElementSibling).toBeNull();
  });

  it('done removes the spin WITHOUT adding a second badge', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Let me check.', is_first: true });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });
    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c1' });

    expect(badges().length).toBe(1);
    expect(badges()[0].querySelector('i').className).not.toContain('fa-spin');
    expect(badges()[0].className).toContain('mc-badge--grey');
  });

  // The GLYPH carries the state, not just the motion: a running call shows
  // the app's busy spinner, a finished one the tool icon. A spinning wrench
  // read as decoration rather than progress (user choice, dogfood).
  it('swaps the busy spinner glyph for the tool glyph when the call finishes', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Let me check.', is_first: true });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });
    expect(badges()[0].querySelector('i').className).toContain('fa-spinner');
    expect(badges()[0].querySelector('i').className).not.toContain('fa-tools');

    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c1' });
    expect(badges()[0].querySelector('i').className).toContain('fa-tools');
    expect(badges()[0].querySelector('i').className).not.toContain('fa-spinner');
  });

  it('error turns the badge red and stops the spin', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Let me check.', is_first: true });
    LC.onToolCall({ name: 'run_code', status: 'running', call_id: 'c1' });
    LC.onToolCall({ name: 'run_code', status: 'error', call_id: 'c1' });

    expect(badges().length).toBe(1);
    expect(badges()[0].className).toContain('mc-badge--red');
    expect(badges()[0].querySelector('i').className).not.toContain('fa-spin');
  });

  it('a repeated running with the same call_id never duplicates the badge', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'One moment.', is_first: true });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });

    expect(badges().length).toBe(1);
  });

  it('concurrent same-name calls render as ONE badge that spins until the last finishes', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Checking both.', is_first: true });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c2' });
    // §40: same boundary, same name → merged into one badge. The entries
    // stay separate underneath (call_id correlation), only the render merges.
    expect(badges().length).toBe(1);
    expect(badges()[0].querySelector('i').className).toContain('fa-spin');

    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c1' });
    // c2 still running → the merged badge keeps spinning (worst status wins).
    expect(badges()[0].querySelector('i').className).toContain('fa-spin');

    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c2' });
    expect(badges()[0].querySelector('i').className).not.toContain('fa-spin');
  });

  it('the answer anchor flips the running badge status instead of duplicating it', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Let me check.', is_first: true });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });
    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c1' });
    LC.onAssistantFragment({ content: 'The answer is 42.', is_first: true });

    expect(badges().length).toBe(1);
    expect(badges()[0].querySelector('i').className).not.toContain('fa-spin');
    const paras = curZone().querySelectorAll(':scope > p');
    expect(paras.length).toBe(2);
    expect(badges()[0].nextElementSibling).toBe(paras[1]);
  });

  // §37-14B: the running badge's `at` was fixed when the call started, but
  // the boundary only settles when the answer begins (the bridge can gain
  // paragraphs meanwhile) — the anchor refreshes it instead of leaving the
  // badge behind the answer.
  it('moves the running badge to the settled boundary when the answer begins', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'Let me check.', is_first: true, segment_id: 'r1' });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });
    expect(badges().length).toBe(1);

    // The bridge text gains a paragraph before the answer (e.g. a §37-11
    // second message folded into the same card).
    document.getElementById('discourse').insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-header"><div class="card-title"></div></div>' +
      '<div class="card-body"><div class="card-text">Let me check.</div></div></div>');
    LC.onCardText({ mid: 'm1', content: 'Let me check.\n\nMore bridge text.' });
    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c1' });
    LC.onAssistantFragment({ content: 'The answer.', is_first: true, segment_id: 'r2' });

    expect(badges().length).toBe(1); // still one badge — updated, not duplicated
    const paras = curZone().querySelectorAll(':scope > p');
    expect(paras.length).toBe(3);
    expect(badges()[0].nextElementSibling).toBe(paras[2]);
  });

  // §37-13A: Gemini finalizes the user turn only when the model starts
  // answering, so during the call the current zone is still USER — the
  // badge needs an empty assistant zone, and the answer must continue in
  // that same zone after the late user-final shuffles the zones around.
  it('gemini path: badge shows while the user zone is current, and the answer continues in the badge zone', async () => {
    await LC.startConversation();
    LC.onSttPartial({ content: '明日の天気は？' });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });

    // The badge is visible NOW, in a freshly opened empty assistant zone.
    expect(document.querySelector('#lc-live-current .lc-live-role').textContent).toContain('Assistant');
    expect(badges().length).toBe(1);
    expect(badges()[0].querySelector('i').className).toContain('fa-spin');

    // Gemini order: the user-final lands before the answer (zone shuffle).
    LC.onStt({ content: '明日の天気は？' });
    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c1' });
    LC.onAssistantFragment({ content: '明日は晴れです。', is_first: true });

    // The answer continues in the badge zone (no duplicate, no spin).
    const curRole = document.querySelector('#lc-live-current .lc-live-role').textContent;
    expect(curRole).toContain('Assistant');
    expect(badges().length).toBe(1);
    expect(badges()[0].querySelector('i').className).not.toContain('fa-spin');
    expect(curZone().textContent).toContain('明日は晴れです。');
    // The user's finalized utterance sits in prev, not lost.
    expect(document.querySelector('#lc-live-prev .lc-live-text').textContent).toBe('明日の天気は？');
  });
});


describe('tool-bridged fold client behavior (§37-2)', () => {
  beforeEach(() => {
    window.params = {};
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
  });

  it('renders the tools badge onto the pre-existing card when sts_card_text carries tools_used', async () => {
    await LC.startConversation();
    document.getElementById('discourse').insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-header"><div class="card-title">Assistant</div></div>' +
      '<div class="card-body"><div class="card-text">Let me check…</div></div></div>');

    LC.onCardText({ mid: 'm1', content: 'Let me check… The answer is 42.',
                    tools_used: [{ name: 'search_web', status: 'done' }] });

    const badge = document.querySelector('#m1 .card-title .lc-tools-badge');
    expect(badge).not.toBeNull();
    expect(badge.textContent).toContain('search_web');
    expect(document.querySelector('#m1 .card-text').textContent).toContain('The answer is 42.');

    // second arrival must not duplicate the badge
    LC.onCardText({ mid: 'm1', content: 'Let me check… The answer is 42. Extended now.',
                    tools_used: [{ name: 'search_web', status: 'done' }] });
    expect(document.querySelectorAll('#m1 .lc-tools-badge').length).toBe(1);
  });

  // §39: a suppressed (unspoken) continuation arrives as tools_used with
  // UNCHANGED text. The grow path used to wipe the body before re-inserting
  // badges, so re-sent entries could not pile up; the badge-only path has no
  // such wipe, and the server re-sends the UNION on every fold.
  it('does not duplicate inline badges when a badge-only update repeats', async () => {
    await LC.startConversation();
    document.getElementById('discourse').insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-header"><div class="card-title">Assistant</div></div>' +
      '<div class="card-body"><div class="card-text">Let me check…</div></div></div>');

    // The inline badge renderer lives in card-renderer.js, which this suite
    // does not load — wire the real one up so the badge path is exercised.
    const prevInsert = window.insertInlineToolBadge;
    window.insertInlineToolBadge =
      require('../../docker/services/ruby/public/js/monadic/card-renderer.js').insertInlineToolBadge;

    const tools = [{ name: 'run_code', status: 'done', at: 1 }];
    LC.onCardText({ mid: 'm1', content: 'Let me check…', tools_used: tools });
    LC.onCardText({ mid: 'm1', content: 'Let me check…', tools_used: tools });

    expect(document.querySelectorAll('#m1 .card-text .lc-tools-badge').length).toBe(1);
    window.insertInlineToolBadge = prevInsert;
  });

  it('removes the temp-card when its content is folded into the card', async () => {
    await LC.startConversation();
    const discourse = document.getElementById('discourse');
    discourse.insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-body"><div class="card-text">Let me check…</div></div></div>');
    discourse.insertAdjacentHTML('beforeend',
      '<div id="temp-card" class="card">The answer is 42.</div>');

    LC.onCardText({ mid: 'm1', content: 'Let me check… The answer is 42.' });

    expect(document.getElementById('temp-card')).toBeNull();
  });

  it('keeps the temp-card when its content is NOT part of the update', async () => {
    await LC.startConversation();
    const discourse = document.getElementById('discourse');
    discourse.insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-body"><div class="card-text">a</div></div></div>');
    discourse.insertAdjacentHTML('beforeend',
      '<div id="temp-card" class="card">unrelated ongoing stream</div>');

    LC.onCardText({ mid: 'm1', content: 'ab' });
    expect(document.getElementById('temp-card')).not.toBeNull();
  });
});

describe('streaming indicator reset on Stop (§37-5)', () => {
  beforeEach(() => {
    window.params = {};
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
    delete window.responseStarted;
    delete window.streamingResponse;
  });

  it('clears the typed pipeline streaming flags and shows READY when RESPONDING was up', async () => {
    await LC.startConversation();
    window.responseStarted = true;
    window.streamingResponse = true;

    LC.stopConversation();

    expect(window.responseStarted).toBe(false);
    expect(window.streamingResponse).toBe(false);
    expect(window.setAlert).toHaveBeenCalledWith(
      expect.stringContaining('Ready for input'), 'success');
  });

  it('does not manufacture a READY alert when nothing was responding', async () => {
    await LC.startConversation();
    window.responseStarted = false;
    window.streamingResponse = false;
    window.setAlert.mockClear();

    LC.stopConversation();

    expect(window.setAlert).not.toHaveBeenCalledWith(
      expect.stringContaining('Ready for input'), 'success');
  });

  it('resets the indicators on a server-side stop too', async () => {
    await LC.startConversation();
    window.responseStarted = true;
    window.streamingResponse = true;

    LC.onStsSession({ state: 'stopped' });

    expect(window.responseStarted).toBe(false);
    expect(window.streamingResponse).toBe(false);
  });
});

describe('single folded card with positioned badges (§37-3)', () => {
  beforeEach(() => {
    window.params = {};
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
    delete window.insertInlineToolBadge;
  });

  it('splits folded text into paragraphs and delegates positioned badges', async () => {
    window.insertInlineToolBadge = jest.fn();
    await LC.startConversation();
    document.getElementById('discourse').insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-header"><div class="card-title">Assistant</div></div>' +
      '<div class="card-body"><div class="card-text">Let me check…</div></div></div>');

    const toolsUsed = [{ name: 'search_web', status: 'done', at: 1 }];
    LC.onCardText({ mid: 'm1', content: 'Let me check…\n\nThe answer is 42.', tools_used: toolsUsed });

    const paras = document.querySelectorAll('#m1 .card-text > p');
    expect(paras.length).toBe(2);
    expect(paras[0].textContent).toBe('Let me check…');
    expect(paras[1].textContent).toBe('The answer is 42.');
    // §37-4: positioned entries render INLINE only — no header badge.
    expect(document.querySelector('#m1 .card-title .lc-tools-badge')).toBeNull();
    // positioned badges delegated with the card and the raw entries
    expect(window.insertInlineToolBadge).toHaveBeenCalledWith(
      document.getElementById('m1'), toolsUsed);
  });

  it('renders a header badge for UNPOSITIONED entries only (mixed data, §37-4)', async () => {
    window.insertInlineToolBadge = jest.fn();
    await LC.startConversation();
    document.getElementById('discourse').insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-header"><div class="card-title">Assistant</div></div>' +
      '<div class="card-body"><div class="card-text">Checking…</div></div></div>');

    // Merge canon can be mixed: the predecessor's own entry kept no `at`,
    // the folded-in fragment's entry is positioned.
    LC.onCardText({ mid: 'm1', content: 'Checking…\n\nDone.',
                    tools_used: [{ name: 'get_current_time', status: 'done' },
                                 { name: 'search_web', status: 'done', at: 1 }] });

    const header = document.querySelector('#m1 .card-title .lc-tools-badge');
    expect(header).not.toBeNull();
    expect(header.textContent).toContain('get_current_time');
    expect(header.textContent).not.toContain('search_web'); // inline's job
    // Both entries still go to the inline helper (it skips the at-less one).
    expect(window.insertInlineToolBadge).toHaveBeenCalledWith(
      document.getElementById('m1'),
      [{ name: 'get_current_time', status: 'done' },
       { name: 'search_web', status: 'done', at: 1 }]);
  });

  it('Stop removes a temp-card whose content was folded into a finalized card (ghost)', async () => {
    await LC.startConversation();
    const discourse = document.getElementById('discourse');
    discourse.insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-body"><div class="card-text">Let me check… The answer is 42.</div></div></div>');
    discourse.insertAdjacentHTML('beforeend',
      '<div id="temp-card" class="card"><div class="card-header">Assistant</div>' +
      '<div class="card-body"><div class="card-text">The answer is 42.</div></div></div>');

    LC.stopConversation();
    expect(document.getElementById('temp-card')).toBeNull();
  });

  it('Stop keeps a temp-card whose content is in NO card (unfinished response)', async () => {
    await LC.startConversation();
    const discourse = document.getElementById('discourse');
    discourse.insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-body"><div class="card-text">finalized</div></div></div>');
    discourse.insertAdjacentHTML('beforeend',
      '<div id="temp-card" class="card"><div class="card-body"><div class="card-text">still streaming</div></div></div>');

    LC.stopConversation();
    expect(document.getElementById('temp-card')).not.toBeNull();
  });

  it('Stop removes an empty temp-card shell', async () => {
    await LC.startConversation();
    document.getElementById('discourse').insertAdjacentHTML('beforeend',
      '<div id="temp-card" class="card"><div class="card-body"><div class="card-text"></div></div></div>');

    LC.stopConversation();
    expect(document.getElementById('temp-card')).toBeNull();
  });
});

describe('thinking display stays hidden in LC (dogfood: capability $show race)', () => {
  const fs = require('fs');
  const path = require('path');
  const utilsSrc = fs.readFileSync(
    path.join(__dirname, '../../docker/services/ruby/public/js/monadic/utilities.js'), 'utf8');
  const cssSrc = fs.readFileSync(
    path.join(__dirname, '../../docker/services/ruby/public/css/monadic.css'), 'utf8');

  it('the capability $show path is guarded by lc-app (JS layer)', () => {
    // The $show call for #thinking-display-container must only fire when the
    // body is NOT in lc-app mode — realtime models emit no reasoning, so
    // showing the toggle in LC is a UI lie.
    expect(utilsSrc).toMatch(
      /spec\["supports_thinking"\]\s*&&\s*!document\.body\.classList\.contains\('lc-app'\)/);
  });

  // Root cause (browser-measured, §37-4): for !important declarations the
  // cascade-layer order REVERSES — an unlayered .lc-app rule loses to
  // Bootstrap's vendor-layer .d-flex{display:flex !important}. The fix
  // declares lc-overrides BEFORE vendor and puts the hiding rules inside it.
  it('lc-overrides is declared before vendor (important inversion)', () => {
    expect(cssSrc).toMatch(/@layer lc-overrides, vendor,/);
  });

  // The statement in monadic.css is NOT enough: layer order is fixed by the
  // FIRST statement the browser sees, and vendor-layers.css (loaded earlier)
  // creates `vendor` via @import layer(vendor). A later statement can only
  // APPEND unknown names, so lc-overrides landed after utilities — last for
  // important, i.e. still losing to .d-flex. Browser-measured: the toggle
  // only disappeared once the order was declared here, ahead of the imports.
  it('vendor-layers.css declares the order before it creates the vendor layer', () => {
    const vendorSrc = fs.readFileSync(
      path.join(__dirname, '../../docker/services/ruby/public/css/vendor-layers.css'), 'utf8');
    const stmt = vendorSrc.indexOf('@layer lc-overrides, vendor,');
    const firstImport = vendorSrc.indexOf('@import');
    expect(stmt).toBeGreaterThan(-1);
    expect(stmt).toBeLessThan(firstImport);
  });

  it('the LC hiding rules live inside @layer lc-overrides', () => {
    const block = cssSrc.match(/@layer lc-overrides \{([\s\S]*?)\n\} \/\* end @layer lc-overrides \*\//);
    expect(block).not.toBeNull();
    expect(block[1]).toMatch(/\.lc-app #thinking-display-container/);
    // All HIDDEN_IN_LC surfaces ride the same layer (the .d-flex trap is
    // not specific to the thinking toggle).
    expect(block[1]).toMatch(/\.lc-app #websearch-form/);
    expect(block[1]).toMatch(/\.lc-app #model_parameters/);
  });
});

describe('speech highlight (§37-13C)', () => {
  beforeEach(() => {
    window.params = {};
    window.insertInlineToolBadge =
      require('../../docker/services/ruby/public/js/monadic/card-renderer').insertInlineToolBadge;
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
    delete window.insertInlineToolBadge;
    delete window.WsStsPlayback;
  });

  const speakingSpan = () => document.querySelector('#lc-live-current .lc-speaking');

  it('marks the sentence under the playback position', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'こんにちは。', is_first: true, segment_id: 'r1' });
    LC.onAssistantFragment({ content: '元気ですか。', segment_id: 'r1' });
    window.WsStsPlayback = { getPlaybackPosition: () => ({ segmentId: 'r1', offset: 5, total: 10 }) };

    LC._tickHighlight();
    expect(speakingSpan()).not.toBeNull();
    expect(speakingSpan().textContent).toBe('元気ですか。');
  });

  // `total` is the audio SCHEDULED so far and deltas outrun playback ~3-5x
  // (measured), so early in a response the fraction is inflated; as more
  // audio lands it drops and a raw mapping would walk the highlight BACK
  // over text already spoken. Speech only moves forward, so the highlight
  // must too — within a segment.
  it('never moves the highlight backward as the audio timeline grows', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: '一つ目。二つ目。三つ目。', is_first: true, segment_id: 'r1' });
    let pos = { segmentId: 'r1', offset: 1, total: 2 }; // only 2s scheduled yet
    window.WsStsPlayback = { getPlaybackPosition: () => pos };
    LC._tickHighlight();
    expect(speakingSpan().textContent).toBe('二つ目。');

    pos = { segmentId: 'r1', offset: 1, total: 20 }; // timeline filled in
    LC._tickHighlight();
    expect(speakingSpan().textContent).toBe('二つ目。'); // not back to 一つ目

    pos = { segmentId: 'r1', offset: 18, total: 20 };
    LC._tickHighlight();
    expect(speakingSpan().textContent).toBe('三つ目。'); // forward still works
  });

  it('starts a fresh floor for the next response', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: '一つ目。二つ目。', is_first: true, segment_id: 'r1' });
    window.WsStsPlayback = { getPlaybackPosition: () => ({ segmentId: 'r1', offset: 9, total: 10 }) };
    LC._tickHighlight();
    expect(speakingSpan().textContent).toBe('二つ目。');

    // A NEW response (barge-in or next turn): the floor must not carry over.
    LC.onAssistantFragment({ content: 'あたらしい。つぎの。', is_first: true, segment_id: 'r2' });
    window.WsStsPlayback = { getPlaybackPosition: () => ({ segmentId: 'r2', offset: 1, total: 10 }) };
    LC._tickHighlight();
    expect(speakingSpan().textContent).toBe('あたらしい。');
  });

  it('freezes on the last sentence during silence (no playback position)', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: '一つ目。二つ目。', is_first: true, segment_id: 'r1' });
    let pos = { segmentId: 'r1', offset: 1, total: 10 };
    window.WsStsPlayback = { getPlaybackPosition: () => pos };
    LC._tickHighlight();
    expect(speakingSpan().textContent).toBe('一つ目。');

    pos = null; // tool running / silence: nothing audible
    LC._tickHighlight();
    expect(speakingSpan().textContent).toBe('一つ目。'); // frozen, not cleared
  });

  it('maps a tool-bridged answer into its own segment, not the bridge', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'つなぎ。', is_first: true, segment_id: 'r1' });
    LC.onToolCall({ name: 'search_web', status: 'running', call_id: 'c1' });
    LC.onToolCall({ name: 'search_web', status: 'done', call_id: 'c1' });
    LC.onAssistantFragment({ content: '回答です。', is_first: true, segment_id: 'r2' });

    window.WsStsPlayback = { getPlaybackPosition: () => ({ segmentId: 'r2', offset: 1, total: 4 }) };
    LC._tickHighlight();
    expect(speakingSpan()).not.toBeNull();
    expect(speakingSpan().textContent).toBe('回答です。');
  });

  it('does not highlight in card view', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: 'テスト。', is_first: true, segment_id: 'r1' });
    window.params['sts_card_view'] = true;
    window.WsStsPlayback = { getPlaybackPosition: () => ({ segmentId: 'r1', offset: 1, total: 2 }) };

    LC._tickHighlight();
    expect(speakingSpan()).toBeNull();
  });

  it('keeps the highlight out when the audio is for an unknown segment (freeze)', async () => {
    await LC.startConversation();
    LC.onAssistantFragment({ content: '一つ目。', is_first: true, segment_id: 'r1' });
    window.WsStsPlayback = { getPlaybackPosition: () => ({ segmentId: 'rX', offset: 0, total: 1 }) };
    LC._tickHighlight();
    expect(speakingSpan()).toBeNull();
  });
});

describe('turn detection selector (§37-16)', () => {
  const vadSpec = {
    'gpt-realtime-2.1': {
      supports_speech_to_speech: true,
      sts_provider: 'openai',
      sts_voice: 'alloy',
      sts_voices: ['alloy'],
      sts_semantic_vad_capability: true
    },
    'grok-voice-think-fast-2.0': {
      supports_speech_to_speech: true,
      sts_provider: 'xai',
      sts_voice: 'eve',
      sts_voices: ['eve']
    }
  };

  let store;
  beforeEach(() => {
    store = {};
    window.setCookie = jest.fn((k, v) => { store[k] = v; });
    window.getCookie = jest.fn((k) => store[k]);
    window.modelSpec = vadSpec;
    window.params = {};
    window.broadcastParamsUpdate = jest.fn();
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.setCookie;
    delete window.getCookie;
    delete window.modelSpec;
    delete window.params;
    delete window.broadcastParamsUpdate;
  });

  const wrap = () => document.getElementById('lc-turn-wrap');
  const sel = () => document.getElementById('lc-turn-select');

  it('shows the selector only for sts_semantic_vad_capability models', () => {
    expect(wrap().style.display).toBe('inline-flex');

    const modelEl = document.getElementById('model');
    modelEl.replaceChildren(new Option('grok-voice-think-fast-2.0', 'grok-voice-think-fast-2.0', true, true));
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(wrap().style.display).toBe('none');
  });

  it('writes both wire keys and remembers the choice on change', () => {
    sel().value = 'low';
    sel().dispatchEvent(new Event('change', { bubbles: true }));
    expect(window.params['sts_vad_type']).toBe('semantic_vad');
    expect(window.params['sts_vad_eagerness']).toBe('low');
    expect(window.setCookie).toHaveBeenCalledWith('lc-turn-openai', 'low', 30);
    expect(window.broadcastParamsUpdate).toHaveBeenCalledWith('sts_vad_turn_change');
  });

  it('the silence choice removes the wire keys (MDSL default applies)', () => {
    window.params['sts_vad_type'] = 'semantic_vad';
    window.params['sts_vad_eagerness'] = 'low';
    sel().value = '';
    sel().dispatchEvent(new Event('change', { bubbles: true }));
    expect(window.params['sts_vad_type']).toBeUndefined();
    expect(window.params['sts_vad_eagerness']).toBeUndefined();
  });

  it('restores the remembered choice from the cookie', () => {
    store['lc-turn-openai'] = 'high';
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(sel().value).toBe('high');
  });

  // Restoring sets no `change` event, so the params the BRIDGE reads stayed
  // empty and the session silently fell back to the MDSL default: the UI
  // claimed "by meaning" while the wire carried server_vad (dogfood). The
  // selector's displayed value and the value that ships must never diverge.
  it('writes the restored choice into params, not just the selector', () => {
    store['lc-turn-openai'] = 'low';
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(sel().value).toBe('low');
    expect(window.params['sts_vad_type']).toBe('semantic_vad');
    expect(window.params['sts_vad_eagerness']).toBe('low');
  });

  it('clears a stale semantic choice for a provider without the capability', () => {
    window.params['sts_vad_type'] = 'semantic_vad';
    window.params['sts_vad_eagerness'] = 'low';
    const modelEl = document.getElementById('model');
    modelEl.replaceChildren(new Option('grok-voice-think-fast-2.0', 'grok-voice-think-fast-2.0', true, true));
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(wrap().style.display).toBe('none');
    expect(window.params['sts_vad_type']).toBeUndefined();
    expect(window.params['sts_vad_eagerness']).toBeUndefined();
  });

  it('ignores a cookie value that is not one of the four choices', () => {
    store['lc-turn-openai'] = 'bogus';
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(sel().value).toBe('');
  });

  it('session params win over the cookie', () => {
    store['lc-turn-openai'] = 'low';
    window.params['sts_vad_type'] = 'semantic_vad';
    window.params['sts_vad_eagerness'] = 'medium';
    LC.setAppMode(normalApp);
    LC.setAppMode(lcApp);
    expect(sel().value).toBe('medium');
  });
});

describe('badge-only card text update (§39 suppress path)', () => {
  beforeEach(() => {
    window.params = {};
    window.insertInlineToolBadge =
      require('../../docker/services/ruby/public/js/monadic/card-renderer').insertInlineToolBadge;
    LC.setAppMode(lcApp);
  });

  afterEach(() => {
    delete window.params;
    delete window.insertInlineToolBadge;
  });

  it('renders the badge even when the text does not grow', async () => {
    await LC.startConversation();
    document.getElementById('discourse').insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-header"><div class="card-title">Assistant</div></div>' +
      '<div class="card-body"><div class="card-text">Let me check…</div></div></div>');

    // §39: the unspoken continuation was suppressed server-side, so the
    // update carries the SAME text plus only the tool badge.
    LC.onCardText({ mid: 'm1', content: 'Let me check…',
                    tools_used: [{ name: 'search_web', status: 'done', at: 1 }] });

    const badge = document.querySelector('#m1 .card-text .lc-tools-badge');
    expect(badge).not.toBeNull();
    expect(badge.textContent).toContain('search_web');
    // text unchanged (no paragraph rebuild on the suppress path)
    expect(document.querySelector('#m1 .card-text').textContent).toContain('Let me check…');
    expect(document.querySelector('#m1 .card-text').textContent).not.toContain('unspoken');
  });

  it('still ignores a no-growth update with no tools', async () => {
    await LC.startConversation();
    document.getElementById('discourse').insertAdjacentHTML('beforeend',
      '<div class="card" id="m1"><div class="card-body"><div class="card-text">same text</div></div></div>');

    LC.onCardText({ mid: 'm1', content: 'same text' });
    expect(document.querySelector('#m1 .lc-tools-badge')).toBeNull();
  });
});
