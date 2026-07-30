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
const { filterModelsForAllMode, appOffersSpeechToSpeech } = require('../../docker/services/ruby/public/js/monadic/model_utils');

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
 * Speech-to-speech availability is an APP decision, not a list decision.
 *
 * Two failed designs bracket this one. Excluding STS unconditionally in
 * listModels made the path unreachable (the curated list never passes
 * through filterModelsForAllMode, so even a declaring app lost the entry).
 * Including it unconditionally leaked it into every app: the server
 * auto-fills `models` from the provider's API list for apps that declare
 * none (dsl.rb model_list_code), so gpt-realtime-2.1 appeared in Chat and
 * selecting it failed with a 404 — realtime models are not chat models.
 *
 * Hence the explicit opt-in: MDSL `speech_to_speech true` →
 * opts.allowSpeechToSpeech. Presence in the models array proves nothing.
 */
describe('speech-to-speech model availability', () => {
  const STS = { allowSpeechToSpeech: true };

  afterEach(() => {
    delete window.modelSpec;
  });

  // The regression that shipped: an API-sourced list containing the STS
  // model reached an ordinary chat app's dropdown.
  it('drops STS models by default even when the API list contains them', () => {
    withSpec({
      'gpt-5.6-terra': {},
      'gpt-realtime-2.1': { supports_speech_to_speech: true }
    });

    const html = listModels(['gpt-5.6-terra', 'gpt-realtime-2.1'], true);

    expect(html).toContain('gpt-5.6-terra');
    expect(html).not.toContain('gpt-realtime-2.1');
  });

  it('offers STS models when the app opted in', () => {
    withSpec({ 'gpt-realtime-2.1': { supports_speech_to_speech: true } });

    expect(listModels(['gpt-realtime-2.1'], true, STS)).toContain('gpt-realtime-2.1');
  });

  it('is excluded from the show-all list regardless of opt-in', () => {
    withSpec({
      'gpt-5.6-terra': {},
      'gpt-realtime-2.1': { supports_speech_to_speech: true }
    });

    const result = filterModelsForAllMode(['gpt-5.6-terra', 'gpt-realtime-2.1'], 'openai');

    expect(result).toContain('gpt-5.6-terra');
    expect(result).not.toContain('gpt-realtime-2.1');
  });

  it('reads the MDSL speech_to_speech flag through appOffersSpeechToSpeech', () => {
    expect(appOffersSpeechToSpeech({ speech_to_speech: true })).toBe(true);
    expect(appOffersSpeechToSpeech({ speech_to_speech: 'true' })).toBe(true);
    expect(appOffersSpeechToSpeech({ speech_to_speech: false })).toBe(false);
    expect(appOffersSpeechToSpeech({})).toBe(false);
    expect(appOffersSpeechToSpeech(null)).toBe(false);
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

    const html = listModels(['gpt-5.6-terra', 'gpt-realtime-2.1'], false, STS);

    expect(html).toContain('>gpt-realtime-2.1 (realtime)<');
    expect(html).toContain('value="gpt-realtime-2.1"');
    // Ordinary models stay unlabelled.
    expect(html).toContain('>gpt-5.6-terra<');
  });
});

/**
 * Source guard: every dropdown population site must pass the app's opt-in.
 * A site calling listModels without it silently reverts that dropdown to
 * "drop STS always", which is exactly how the reachability gap looked.
 */
describe('dropdown call sites pass the opt-in', () => {
  const fs = require('fs');
  const path = require('path');
  const read = (rel) => fs.readFileSync(path.resolve(__dirname, '../..', rel), 'utf8');

  const sites = {
    'utilities.js': 'docker/services/ruby/public/js/monadic/utilities.js',
    'monadic.js': 'docker/services/ruby/public/js/monadic.js',
    'ws-app-data-handlers.js': 'docker/services/ruby/public/js/monadic/ws-app-data-handlers.js'
  };

  Object.entries(sites).forEach(([label, rel]) => {
    it(`${label} passes allowSpeechToSpeech to every listModels call`, () => {
      const src = read(rel);
      // Match listModels invocations (not the function definition).
      const calls = src.match(/listModels\((?!models, openai = false)[^)]*\)/g) || [];
      expect(calls.length).toBeGreaterThan(0);
      calls.forEach(call => {
        expect(call).toContain('allowSpeechToSpeech');
      });
    });
  });
});
