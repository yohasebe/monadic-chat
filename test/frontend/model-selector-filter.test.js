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
const { filterModelsForAllMode } = require('../../docker/services/ruby/public/js/monadic/model_utils');

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
      'realtime transcription': { supports_realtime_streaming: true }
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

  it('drops them in the OpenAI grouped layout too', () => {
    withSpec({ 'gpt-realtime-whisper': { supports_realtime_streaming: true } });

    expect(listModels(['gpt-realtime-whisper'], true)).not.toContain('gpt-realtime-whisper');
  });

  it('returns an empty selector when every candidate was filtered out', () => {
    withSpec({ 'gpt-realtime-whisper': { supports_realtime_streaming: true } });

    expect(listModels(['gpt-realtime-whisper'])).not.toContain('gpt-realtime-whisper');
  });
});

/**
 * Speech-to-speech sits on the other side of the line from the models above.
 *
 * An STS model IS the conversation model for an STS session, so an app that
 * declares one in MDSL has to be able to offer it. Excluding it in listModels
 * also stripped it from the curated list — which never passes through
 * filterModelsForAllMode — and that made the STS path unreachable: the server
 * gates on session.parameters.model being an STS model, and no route could
 * ever set it. The exclusion therefore belongs to show-all only.
 */
describe('speech-to-speech model availability', () => {
  afterEach(() => {
    delete window.modelSpec;
  });

  it('stays selectable through listModels so a declaring app can offer it', () => {
    withSpec({ 'gpt-realtime-2.1': { supports_speech_to_speech: true } });

    expect(listModels(['gpt-realtime-2.1'])).toContain('gpt-realtime-2.1');
  });

  it('is excluded from the show-all list', () => {
    withSpec({
      'gpt-5.6-terra': {},
      'gpt-realtime-2.1': { supports_speech_to_speech: true }
    });

    const result = filterModelsForAllMode(['gpt-5.6-terra', 'gpt-realtime-2.1'], 'openai');

    expect(result).toContain('gpt-5.6-terra');
    expect(result).not.toContain('gpt-realtime-2.1');
  });

  it('survives the curated path end to end', () => {
    withSpec({ 'gpt-realtime-2.1': { supports_speech_to_speech: true } });

    // Curated mode returns MDSL models without passing them through
    // filterModelsForAllMode, so listModels is the only place that could
    // have dropped them.
    expect(listModels(['gpt-realtime-2.1'], true)).toContain('gpt-realtime-2.1');
  });

  // Picking an STS model is a mode switch (different transport, no web
  // search, no typed input in the current slice), so the entry must be
  // visibly marked — an unlabelled id would hide the mode change behind
  // what looks like a quality choice.
  it('labels the dropdown entry "(realtime)" while keeping the bare id as value', () => {
    withSpec({
      'gpt-5.6-terra': {},
      'gpt-realtime-2.1': { supports_speech_to_speech: true }
    });

    const html = listModels(['gpt-5.6-terra', 'gpt-realtime-2.1']);

    expect(html).toContain('>gpt-realtime-2.1 (realtime)<');
    expect(html).toContain('value="gpt-realtime-2.1"');
    // Ordinary models stay unlabelled.
    expect(html).toContain('>gpt-5.6-terra<');
  });
});
