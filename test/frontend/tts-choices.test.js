// ttsChoices (model_spec.js) resolved by tts-provider.js: the same expectations
// as the Ruby side (docker/services/ruby/spec/fixtures/tts/choices_expected.json),
// so the browser and the server read a selector value the same way.
const path = require('path');
const expected = require('../../docker/services/ruby/spec/fixtures/tts/choices_expected.json');

describe('TTS choices', () => {
  let TtsProvider;

  beforeEach(() => {
    jest.resetModules();
    const spec = require('../../docker/services/ruby/public/js/monadic/model_spec.js');
    window.ttsChoices = spec.ttsChoices;
    TtsProvider = require('../../docker/services/ruby/public/js/monadic/tts-provider.js');
  });

  afterEach(() => {
    delete window.ttsChoices;
  });

  it('resolves every value, saved aliases included, as the server does', () => {
    expect(Object.keys(window.ttsChoices).sort()).toEqual(Object.keys(expected).sort());
    Object.entries(expected).forEach(([label, want]) => {
      const got = TtsProvider.choice(label);
      expect(got).toEqual({ requestedId: label, id: want.id, provider: want.provider,
        model: want.model, execution: want.execution || 'server' });
      expect(TtsProvider.providerOf(label)).toBe(want.provider);
      expect(TtsProvider.modelFor(label)).toBe(want.model);
    });
  });

  it('resolves nothing for an empty, unknown or circular value', () => {
    expect(TtsProvider.choice('')).toBeNull();
    expect(TtsProvider.choice(undefined)).toBeNull();
    expect(TtsProvider.choice('toString')).toBeNull();
    window.ttsChoices = { a: { alias: 'b' }, b: { alias: 'a' } };
    expect(TtsProvider.choice('a')).toBeNull();
  });

  it('gives every value and TTS model the same text family as the server', () => {
    const families = require('../../docker/services/ruby/spec/fixtures/tts/families_expected.json');
    window.modelSpec = require('../../docker/services/ruby/public/js/monadic/model_spec.js');
    require('../../docker/services/ruby/public/js/monadic/tts-tag-sanitizer.js');
    Object.entries(families).forEach(([key, family]) => {
      expect([key, window.TtsTagSanitizer.familyFor(key)]).toEqual([key, family]);
    });
    delete window.modelSpec;
  });

  it('restores a value saved by an earlier version as its successor, only for its provider', () => {
    window.modelSpec = require('../../docker/services/ruby/public/js/monadic/model_spec.js');
    window.ttsChoices = window.ttsChoices || window.modelSpec.ttsChoices;
    const TtsProvider = require('../../docker/services/ruby/public/js/monadic/tts-provider.js');
    document.body.innerHTML = '<select id="p"><option value="webspeech">W</option>' +
      '<option value="elevenlabs-flash">F</option><option value="mistral" disabled>M</option></select>';
    const select = document.getElementById('p');
    window.$dispatch = jest.fn();
    expect(TtsProvider.restoreSaved(select, 'elevenlabs', 'gemini')).toBe(false);
    expect(select.value).toBe('webspeech');
    expect(TtsProvider.restoreSaved(select, 'mistral', 'mistral')).toBe(false);
    expect(TtsProvider.restoreSaved(select, 'unknown-value')).toBe(false);
    expect(TtsProvider.restoreSaved(select, 'elevenlabs', 'elevenlabs')).toBe(true);
    expect(select.value).toBe('elevenlabs-flash');
    expect(window.$dispatch).toHaveBeenCalledTimes(1);
    expect(TtsProvider.idsOf('openai').sort()).toEqual(['openai-tts', 'openai-tts-4o', 'openai-tts-hd']);
    delete window.$dispatch;
    delete window.modelSpec;
    document.body.innerHTML = '';
  });

  it('keeps the table out of the model list', () => {
    const spec = require('../../docker/services/ruby/public/js/monadic/model_spec.js');
    expect(Object.keys(spec)).not.toContain('ttsChoices');
    Object.values(window.ttsChoices).forEach((entry) => {
      if (entry.alias || entry.execution === 'browser') return;
      expect(spec[entry.model] && spec[entry.model].tts_capability).toBe(true);
    });
  });
});
