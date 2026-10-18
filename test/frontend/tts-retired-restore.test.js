/**
 * @jest-environment jsdom
 */
// A saved, retired TTS choice (Gemini Pro TTS) on the real page code: the
// saved value is restored before the provider's voices arrive, while its
// option is still disabled; the notice waits until the option is usable,
// is told once, and the saved value is kept when no voices come.
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '../..');
const js = file => path.join(root, 'docker/services/ruby/public/js', file);
const html = fs.readFileSync(path.join(root, 'docker/services/ruby/views/index.erb'), 'utf8');
const providerSelect = html.match(/<select\b[^>]*id="tts-provider"[\s\S]*?<\/select>/)[0];

let page;

function load() {
  jest.isolateModules(() => {
    require(js('monadic/dom-helpers.js'));
    require(js('monadic/model_spec.js'));
    window.TtsProvider = require(js('monadic/tts-provider.js'));
    page = {
      cookie: require(js('monadic/cookie-utils.js')),
      data: require(js('monadic/ws-app-data-handlers.js'))
    };
  });
}

beforeEach(() => {
  document.cookie.split(';').forEach(c => { document.cookie = c.split('=')[0].trim() + '=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/'; });
  document.body.innerHTML = providerSelect + '<select id="gemini-tts-voice"></select>' +
    '<select id="tts-voice"></select><select id="tts-speed"></select><select id="asr-lang"></select>';
  load();
  page.cookie.setCookie('tts-provider', 'gemini-pro', 30);
  window.getCookie = global.getCookie = page.cookie.getCookie;
  window.setAlert = jest.fn();
  // The page's change handler stores the selected value
  document.getElementById('tts-provider').addEventListener('change', e => { page.cookie.setCookie('tts-provider', e.target.value, 30); });
});

afterEach(() => {
  delete window.setAlert;
  document.body.innerHTML = '';
});

const select = () => document.getElementById('tts-provider');
const voices = { content: [{ voice_id: 'kore', name: 'Kore' }] };

test('restored before the voices arrive: told once, when Flash TTS becomes usable', () => {
  page.cookie.setCookieValues();
  expect(select().value).toBe('gemini-flash');
  expect(window.setAlert).not.toHaveBeenCalled();
  page.data.handleGeminiVoices(voices);
  expect(select().value).toBe('gemini-flash');
  expect(window.setAlert).toHaveBeenCalledTimes(1);
  expect(window.setAlert.mock.calls[0][0]).toContain('Gemini (Flash TTS)');
  page.data.handleGeminiVoices(voices);
  expect(window.setAlert).toHaveBeenCalledTimes(1);
});

test('restored, then no voices: nothing is told and the wish is kept', () => {
  page.cookie.setCookieValues();
  page.data.handleGeminiVoices({ content: [] });
  expect(window.setAlert).not.toHaveBeenCalled();
  expect(page.cookie.getCookie('tts-provider')).toBe('gemini-flash');
});

test('voices arrive first: told once when the saved value is moved', () => {
  page.data.handleGeminiVoices(voices);
  expect(select().value).toBe('gemini-flash');
  expect(window.setAlert).toHaveBeenCalledTimes(1);
  page.cookie.setCookieValues();
  expect(select().value).toBe('gemini-flash');
  expect(window.setAlert).toHaveBeenCalledTimes(1);
});
