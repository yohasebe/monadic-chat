/**
 * @jest-environment jsdom
 *
 * Tests for window.TtsTagSanitizer, the frontend mirror of the backend
 * `Monadic::Utils::TtsTextProcessors` module.
 *
 * Responsibilities:
 *   - Normalise provider strings to a canonical family key.
 *   - Strip xAI audio-control markers ([laugh], <whisper>, ...) for display.
 *   - Pass through untouched for providers without a registered sanitizer.
 *   - Read the current provider from window.params when none is supplied.
 */

describe('TtsTagSanitizer', () => {
  beforeEach(() => {
    jest.resetModules();
    delete window.TtsTagSanitizer;
    delete window.params;
    // Load the module fresh so window.params lookup happens against the
    // current test's setup.
    require('../../docker/services/ruby/public/js/monadic/tts-tag-sanitizer.js');
  });

  describe('familyFor', () => {
    it('maps xAI provider strings to the xai family', () => {
      expect(window.TtsTagSanitizer.familyFor('grok')).toBe('xai');
      expect(window.TtsTagSanitizer.familyFor('xai-tts')).toBe('xai');
      expect(window.TtsTagSanitizer.familyFor('GROK')).toBe('xai');
    });

    it('maps ElevenLabs variants to the elevenlabs family', () => {
      ['elevenlabs', 'elevenlabs-flash', 'elevenlabs-multilingual', 'elevenlabs-v3']
        .forEach(p => expect(window.TtsTagSanitizer.familyFor(p)).toBe('elevenlabs'));
    });

    it('maps OpenAI / Gemini / Mistral / Voxtral variants to their families', () => {
      expect(window.TtsTagSanitizer.familyFor('openai-tts-4o')).toBe('openai');
      expect(window.TtsTagSanitizer.familyFor('tts-1-hd')).toBe('openai');
      expect(window.TtsTagSanitizer.familyFor('gemini-flash')).toBe('gemini');
      expect(window.TtsTagSanitizer.familyFor('mistral')).toBe('mistral');
      expect(window.TtsTagSanitizer.familyFor('voxtral-mini-tts-2603')).toBe('mistral');
    });

    it('tolerates nullish input', () => {
      expect(window.TtsTagSanitizer.familyFor(null)).toBe('');
      expect(window.TtsTagSanitizer.familyFor(undefined)).toBe('');
    });
  });

  describe('sanitizeForDisplay (xai)', () => {
    it('strips all inline markers', () => {
      const input = 'Oh wow [laugh] great [pause] idea. [sigh] Anyway.';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'grok'))
        .toBe('Oh wow great idea. Anyway.');
    });

    it('strips opening and closing wrap tags but keeps inner text', () => {
      const input = '<whisper>Tell no one.</whisper> Okay?';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'grok'))
        .toBe('Tell no one. Okay?');
    });

    it('covers every marker in the vocabulary', () => {
      const input = '[long-pause][inhale][exhale][click][smack][cry] ok ' +
        '<loud>A</loud><soft>B</soft><high>C</high><low>D</low>' +
        '<fast>E</fast><slow>F</slow><sing>G</sing>';
      const out = window.TtsTagSanitizer.sanitizeForDisplay(input, 'grok');
      expect(out).not.toMatch(/\[[a-z-]+\]/);
      expect(out).not.toMatch(/<\/?[a-z]+>/);
      ['A','B','C','D','E','F','G'].forEach(l => expect(out).toContain(l));
    });

    it('does not leave a space before punctuation after stripping', () => {
      expect(window.TtsTagSanitizer.sanitizeForDisplay('Wait [pause] , really?', 'grok'))
        .toBe('Wait, really?');
    });
  });

  describe('sanitizeForDisplay (elevenlabs)', () => {
    it('strips curated inline tags', () => {
      const input = 'Oh wow [laughs] that is hilarious. [sighs] Anyway.';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'elevenlabs-v3'))
        .toBe('Oh wow that is hilarious. Anyway.');
    });

    it('also strips improvised multi-word lowercase descriptors', () => {
      expect(window.TtsTagSanitizer.sanitizeForDisplay('Hmm [laughing harder] priceless.', 'elevenlabs'))
        .toBe('Hmm priceless.');
    });

    it('preserves all-caps and numeric brackets (non-markers)', () => {
      expect(window.TtsTagSanitizer.sanitizeForDisplay('See [TODO] and [1].', 'elevenlabs'))
        .toBe('See [TODO] and [1].');
    });
  });

  describe('sanitizeForDisplay (gemini)', () => {
    it('strips the 16 fixed audio tags', () => {
      const input = 'Really [amazed] wow [mischievously] sneaky [whispers] secret.';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'gemini-flash'))
        .toBe('Really wow sneaky secret.');
    });

    it('strips free-form descriptor tags Gemini supports', () => {
      const input = 'Saying this [sarcastically, one painfully slow word at a time] is the point.';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'gemini-pro'))
        .toBe('Saying this is the point.');
    });
  });

  describe('sanitizeForDisplay (other providers)', () => {
    it('is the identity function when no sanitizer is registered', () => {
      const input = '<whisper>kept</whisper> [laugh]';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'openai-tts-4o')).toBe(input);
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'mistral')).toBe(input);
    });

    it('is nil-safe and empty-string safe', () => {
      expect(window.TtsTagSanitizer.sanitizeForDisplay(null, 'grok')).toBeNull();
      expect(window.TtsTagSanitizer.sanitizeForDisplay('', 'grok')).toBe('');
      expect(window.TtsTagSanitizer.sanitizeForDisplay(undefined, 'grok')).toBeUndefined();
    });
  });

  describe('provider detection via window.params', () => {
    it('reads window.params.tts_provider when no provider argument is supplied', () => {
      window.params = { tts_provider: 'grok' };
      expect(window.TtsTagSanitizer.tagAware()).toBe(true);
      expect(window.TtsTagSanitizer.sanitizeForDisplay('hi [laugh] there'))
        .toBe('hi there');
    });

    it('defaults to identity when window.params is absent', () => {
      delete window.params;
      expect(window.TtsTagSanitizer.tagAware()).toBe(false);
      expect(window.TtsTagSanitizer.sanitizeForDisplay('hi [laugh] there'))
        .toBe('hi [laugh] there');
    });

    it('is not tag-aware when provider is a non-audio-tag provider', () => {
      window.params = { tts_provider: 'openai-tts-4o' };
      expect(window.TtsTagSanitizer.tagAware()).toBe(false);
    });

    it('is tag-aware for ElevenLabs variants', () => {
      window.params = { tts_provider: 'elevenlabs-v3' };
      expect(window.TtsTagSanitizer.tagAware()).toBe(true);
    });

    it('is tag-aware for Gemini TTS variants', () => {
      window.params = { tts_provider: 'gemini-flash' };
      expect(window.TtsTagSanitizer.tagAware()).toBe(true);
    });
  });
});
