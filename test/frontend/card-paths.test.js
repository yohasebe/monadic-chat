/**
 * @jest-environment jsdom
 */
// A card that shows a shared folder path by its file name reads out and
// copies the whole path.
const PATH = 'conversations/c1/artifacts/20260101-000100_image_1.jpg';

beforeEach(() => {
  document.body.innerHTML = '<div id="discourse"></div><select id="tts-provider"><option value="openai-tts" selected></option></select>';
  global.messages = [];
  window.messages = global.messages;
  global.cleanupAllTooltips = jest.fn();
  global.setAlert = jest.fn();
  global.getTranslation = jest.fn((key, fallback) => fallback);
  global.removeCode = (text) => text;
  global.removeMarkdown = (text) => text;
  global.removeEmojis = (text) => text;
  window.TtsProvider = { providerOf: () => 'openai' };
  window.safeWsSend = jest.fn(() => ({ sent: true }));
  jest.isolateModules(() => {
    require('../../docker/services/ruby/public/js/monadic/dom-helpers.js');
    require('../../docker/services/ruby/public/js/monadic/short-paths.js');
    require('../../docker/services/ruby/public/js/monadic/cards.js');
  });
});

afterEach(() => { delete window.ShortPaths; });

function card() {
  const node = document.createElement('div');
  node.className = 'card';
  node.id = 'm1';
  node.innerHTML = '<div class="card-header"><span class="func-play"></span><span class="func-copy"></span></div>' +
    `<div class="card-text"><p>The image is at <code>${PATH}</code></p></div>`;
  document.getElementById('discourse').appendChild(node);
  window.ShortPaths.apply(document.getElementById('discourse'));
  window.attachEventListeners(node);
  return node;
}

it('reads out the whole path', () => {
  jest.useFakeTimers();
  const node = card();
  expect(node.querySelector('.card-text').textContent).toBe('The image is at 20260101-000100_image_1.jpg');
  node.querySelector('.func-play').dispatchEvent(new MouseEvent('click', { bubbles: true }));
  jest.advanceTimersByTime(100);
  jest.useRealTimers();
  const sent = window.safeWsSend.mock.calls.map(([payload]) => payload).find((p) => p.message === 'PLAY_TTS');
  expect(sent.text).toContain(PATH);
});
