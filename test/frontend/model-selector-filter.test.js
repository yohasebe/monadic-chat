/**
 * @jest-environment jsdom
 */

/**
 * Which models may appear in the chat-model dropdown.
 *
 * This exercises the REAL `listModels` from utilities.js rather than a
 * test-local copy: the existing utilities.test.js reimplements the function,
 * so a filter change there would pass while the shipped dropdown still leaked.
 *
 * The stake is concrete. A model that only works through a dedicated path
 * (STT, TTS, music, realtime transcription, speech-to-speech) is selectable
 * from an ordinary chat app if it reaches this list, and the failure surfaces
 * later as a request error with nothing on screen explaining the cause.
 */

const { listModels } = require('../../docker/services/ruby/public/js/monadic/utilities');

function withSpec(spec) {
  window.modelSpec = spec;
}

describe('chat model dropdown filter', () => {
  afterEach(() => {
    delete window.modelSpec;
  });

  it('keeps ordinary chat models', () => {
    withSpec({ 'gpt-5.6-terra': { context_window: [[1, 400000], 400000] } });

    expect(listModels(['gpt-5.6-terra'])).toContain('gpt-5.6-terra');
  });

  it('keeps models it has no spec for, rather than hiding them', () => {
    withSpec({});

    // An unknown id is more likely a new chat model than a speech model;
    // dropping it would make the dropdown silently incomplete.
    expect(listModels(['some-new-model'])).toContain('some-new-model');
  });

  describe('drops models that belong to a dedicated panel', () => {
    const cases = {
      'STT': { stt_capability: true },
      'TTS': { tts_capability: true },
      'music generation': { music_capability: true },
      'realtime transcription': { supports_realtime_streaming: true },
      'speech-to-speech': { supports_speech_to_speech: true }
    };

    Object.entries(cases).forEach(([label, spec]) => {
      it(label, () => {
        withSpec({ 'chat-model': {}, 'special-model': spec });

        const html = listModels(['chat-model', 'special-model']);

        expect(html).toContain('chat-model');
        expect(html).not.toContain('special-model');
      });
    });
  });

  // Regression: gpt-realtime-2.1 carries supports_speech_to_speech and nothing
  // else, so every other clause in the filter passes it through.
  it('drops a speech-to-speech model whose spec has no other capability flag', () => {
    withSpec({
      'gpt-5.6-terra': {},
      'gpt-realtime-2.1': { supports_speech_to_speech: true }
    });

    const html = listModels(['gpt-5.6-terra', 'gpt-realtime-2.1'], true);

    expect(html).toContain('gpt-5.6-terra');
    expect(html).not.toContain('gpt-realtime-2.1');
  });

  it('drops them in the OpenAI grouped layout too', () => {
    withSpec({ 'gpt-realtime-whisper': { supports_realtime_streaming: true } });

    expect(listModels(['gpt-realtime-whisper'], true)).not.toContain('gpt-realtime-whisper');
  });

  it('returns an empty selector when every candidate was filtered out', () => {
    withSpec({ 'gpt-realtime-2.1': { supports_speech_to_speech: true } });

    expect(listModels(['gpt-realtime-2.1'])).not.toContain('gpt-realtime-2.1');
  });
});
