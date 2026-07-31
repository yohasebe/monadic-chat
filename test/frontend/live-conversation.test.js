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

  it('never greets on resume (messages present), regardless of the checkbox', async () => {
    window.messages = [{ role: 'user', text: 'earlier turn' }];

    await LC.startConversation();

    expect(sent.find(m => m.message === 'STS_START').greet).toBe(false);
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

  it('streams captured chunks as AUDIO_CHUNK with chat_model', async () => {
    await LC.startConversation();

    capture.onChunk(new ArrayBuffer(8));

    const chunk = sent.find(m => m.message === 'AUDIO_CHUNK');
    expect(chunk).toBeTruthy();
    expect(chunk.chat_model).toBe('gpt-realtime-2.1');
    expect(typeof chunk.content).toBe('string');
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
});

describe('live user transcript (temp card)', () => {
  beforeEach(async () => {
    LC.setAppMode(lcApp);
    await LC.startConversation();
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
