const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '../..');
const TtsProvider = require('../../docker/services/ruby/public/js/monadic/tts-provider');
const handlers = require('../../docker/services/ruby/public/js/monadic/ws-app-data-handlers');
const audio = require('../../docker/services/ruby/public/js/monadic/ws-audio-handler');
const html = fs.readFileSync(path.join(root, 'docker/services/ruby/views/index.erb'), 'utf8');
const providerSelect = html.match(/<select\b[^>]*id="tts-provider"[\s\S]*?<\/select>/)[0];

beforeEach(() => {
  window.TtsProvider = TtsProvider;
  document.body.innerHTML = providerSelect + '<select id="gemini-tts-voice"></select>';
  global.getCookie = jest.fn(name => ({ 'tts-provider': 'gemini-flash-lite', 'gemini-tts-voice': 'puck' })[name]);
});

test.each(['gemini', 'gemini-flash', 'gemini-flash-lite', 'gemini-pro'])('classifies %s as Gemini', value => {
  expect(TtsProvider.isGemini(value)).toBe(true);
});
test.each([null, undefined, '', 'openai-tts', 'elevenlabs', 'mistral', 'grok', 'webspeech', 'gemini-unknown', 'gemini-3.8-flash-tts'])('rejects %s', value => {
  expect(TtsProvider.isGemini(value)).toBe(false);
});

test('the real selector exposes three initially disabled variants', () => {
  const options = [...document.querySelectorAll('#tts-provider option')].filter(option => TtsProvider.isGemini(option.value));
  expect(options.map(option => option.value)).toEqual(['gemini-flash', 'gemini-flash-lite', 'gemini-pro']);
  expect(options.every(option => option.disabled)).toBe(true);
  expect(options[1].textContent).toBe('Gemini (Flash-Lite TTS)');
});

test('voice availability enables every Gemini option, restores preferences, and dispatches change', () => {
  const select = document.getElementById('tts-provider');
  const change = jest.fn();
  select.addEventListener('change', change);
  const otherOptions = [...select.options].filter(option => !TtsProvider.isGemini(option.value));
  const before = otherOptions.map(option => option.disabled);
  handlers.handleGeminiVoices({ content: [{ voice_id: 'kore', name: 'Kore' }, { voice_id: 'puck', name: 'Puck' }] });
  expect([...select.options].filter(option => TtsProvider.isGemini(option.value)).every(option => !option.disabled)).toBe(true);
  expect(otherOptions.map(option => option.disabled)).toEqual(before);
  expect(select.value).toBe('gemini-flash-lite');
  expect(document.getElementById('gemini-tts-voice').value).toBe('puck');
  expect(change).toHaveBeenCalledTimes(1);
  handlers.handleGeminiVoices({ content: [] });
  expect([...select.options].filter(option => TtsProvider.isGemini(option.value)).every(option => option.disabled)).toBe(true);
});

test('Flash-Lite PCM is played through the Gemini audio path', () => {
  document.getElementById('tts-provider').value = 'gemini-flash-lite';
  window.wsHandlers = null;
  window.WsAudioPlayback = { playPCMAudio: jest.fn() };
  const bytes = [0, 0];
  global.Uint8Array.from.mockReturnValueOnce(bytes);
  audio.handleAudio({ content: 'AAA=', mime_type: 'audio/L16;rate=32000' });
  expect(window.WsAudioPlayback.playPCMAudio).toHaveBeenCalledWith(bytes, 32000);
});

test('the bundle loads the shared predicate before every consumer', () => {
  const build = fs.readFileSync(path.join(root, 'scripts/build_js_bundle.mjs'), 'utf8');
  const files = [...build.matchAll(/^  "(js\/[^"\n]+)",?$/gm)].map(match => match[1]);
  const helper = files.indexOf('js/monadic/tts-provider.js');
  expect(helper).toBeGreaterThanOrEqual(0);
  ['js/monadic.js', 'js/monadic/cards.js', 'js/monadic/ws-app-data-handlers.js', 'js/monadic/ws-audio-handler.js'].forEach(file => {
    expect(files.indexOf(file)).toBeGreaterThan(helper);
  });
});

// Execute the production change handler in an isolated context, with unrelated
// page initialization omitted. The provider table and handler are read together.
test.each(['gemini-flash', 'gemini-flash-lite', 'gemini-pro', 'gemini'])('%s selects the compatible voice panel', provider => {
  const vm = require('vm');
  const source = fs.readFileSync(path.join(root, 'docker/services/ruby/public/js/monadic.js'), 'utf8');
  const start = source.indexOf('  const TTS_VOICE_PANELS =');
  const end = source.indexOf('  $on($id("tts-voice"), "change"', start);
  expect(start).toBeGreaterThan(-1);
  expect(end).toBeGreaterThan(start);
  document.body.innerHTML += '<div id="gemini-voices"></div><div id="openai-voices"></div><div id="tts-speed-container"></div>';
  if (provider === 'gemini') {
    document.getElementById('tts-provider').add(new Option('Legacy', provider));
  }
  const context = {
    window, params: {}, $id: id => document.getElementById(id),
    $on: (el, event, fn) => el.addEventListener(event, fn),
    $show: el => { if (el) el.hidden = false; },
    $hide: el => { if (el) el.hidden = true; },
    getCookie, setCookie: jest.fn(), updateExpressiveSpeechIndicator: jest.fn(),
    isParamBroadcastSuppressed: () => true
  };
  vm.runInNewContext(source.slice(start, end), context);
  document.getElementById('tts-provider').value = provider;
  document.getElementById('tts-provider').dispatchEvent(new Event('change'));
  expect(document.getElementById('gemini-voices').hidden).toBe(provider === 'gemini');
  expect(document.getElementById('openai-voices').hidden).toBe(provider !== 'gemini');
  expect(context.params.tts_provider).toBe(provider);
});

test.each(['gemini-flash', 'gemini-flash-lite', 'gemini-pro', 'gemini'])('the card play button sends the compatible voice for %s', provider => {
  const vm = require('vm');
  const source = fs.readFileSync(path.join(root, 'docker/services/ruby/public/js/monadic/cards.js'), 'utf8');
  document.body.innerHTML += '<select id="tts-voice"><option value="alloy">Alloy</option></select><div class="card" id="card1"><div class="card-text">Hello</div><button class="func-play">Play</button></div>';
  const select = document.getElementById('tts-provider');
  if (provider === 'gemini') select.add(new Option('Legacy', provider));
  select.value = provider;
  document.getElementById('gemini-tts-voice').add(new Option('Kore', 'kore'));
  const send = jest.fn();
  const context = {
    window: { TtsProvider, safeWsSend: send }, document,
    $id: id => document.getElementById(id),
    cleanupCardTextListeners: jest.fn(), cleanupAllTooltips: jest.fn(),
    removeCode: text => text, removeMarkdown: text => text, removeEmojis: text => text,
    setTimeout: fn => fn(), console
  };
  vm.runInNewContext(source, context);
  context.attachEventListeners(document.getElementById('card1'));
  document.querySelector('.func-play').click();
  expect(send).toHaveBeenCalledWith(expect.objectContaining({
    message: 'PLAY_TTS', tts_provider: provider,
    tts_voice: provider === 'gemini' ? 'alloy' : 'kore', gemini_tts_voice: 'kore'
  }));
});
