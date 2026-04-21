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

    it('maps ElevenLabs v3 to its own tag-aware family', () => {
      expect(window.TtsTagSanitizer.familyFor('elevenlabs-v3')).toBe('elevenlabs-v3');
      expect(window.TtsTagSanitizer.familyFor('eleven_v3')).toBe('elevenlabs-v3');
    });

    it('maps legacy ElevenLabs variants to the non-tag-aware elevenlabs family', () => {
      ['elevenlabs', 'elevenlabs-flash', 'elevenlabs-multilingual',
       'eleven_multilingual_v2', 'eleven_flash_v2_5']
        .forEach(p => expect(window.TtsTagSanitizer.familyFor(p)).toBe('elevenlabs'));
    });

    it('maps OpenAI / Gemini / Mistral / Voxtral variants to their families', () => {
      // openai-tts-4o is the only OpenAI TTS model accepting `instructions`
      // — it lives in its own instruction-meta family.
      expect(window.TtsTagSanitizer.familyFor('openai-tts-4o')).toBe('openai-instruction');
      expect(window.TtsTagSanitizer.familyFor('openai-tts')).toBe('openai');
      expect(window.TtsTagSanitizer.familyFor('openai-tts-hd')).toBe('openai');
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

    it('strips BBCode-style malformed wrap tags (LLM syntax confusion)', () => {
      const input = 'surprise [high]Wow![/high], fear Eek![/inhale], and more.';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'grok'))
        .toBe('surprise Wow!, fear Eek!, and more.');
    });

    it('strips stray closing-style brackets even for inline markers', () => {
      expect(window.TtsTagSanitizer.sanitizeForDisplay('Thinking. [/pause] Okay.', 'grok'))
        .toBe('Thinking. Okay.');
    });
  });

  describe('sanitizeForDisplay (elevenlabs-v3)', () => {
    it('strips curated inline tags', () => {
      const input = 'Oh wow [laughs] that is hilarious. [sighs] Anyway.';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'elevenlabs-v3'))
        .toBe('Oh wow that is hilarious. Anyway.');
    });

    it('also strips improvised multi-word lowercase descriptors', () => {
      expect(window.TtsTagSanitizer.sanitizeForDisplay('Hmm [laughing harder] priceless.', 'elevenlabs-v3'))
        .toBe('Hmm priceless.');
    });

    it('preserves all-caps and numeric brackets (non-markers)', () => {
      expect(window.TtsTagSanitizer.sanitizeForDisplay('See [TODO] and [1].', 'elevenlabs-v3'))
        .toBe('See [TODO] and [1].');
    });

    it('is the identity function for non-v3 ElevenLabs models', () => {
      const input = '[laughs] Flash cannot interpret this.';
      ['elevenlabs-flash', 'elevenlabs-multilingual', 'elevenlabs'].forEach(p => {
        expect(window.TtsTagSanitizer.sanitizeForDisplay(input, p)).toBe(input);
      });
    });
  });

  describe('sanitizeForDisplay cross-provider union (mid-session TTS switch)', () => {
    it('strips xAI wrap markers when current provider is ElevenLabs v3', () => {
      const input = 'Sure, <whisper>secret</whisper> and [laugh] here.';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'elevenlabs-v3'))
        .toBe('Sure, secret and here.');
    });

    it('strips ElevenLabs markers when current provider is xAI', () => {
      const input = 'Oh [laughs] that is [excited] great news!';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'grok'))
        .toBe('Oh that is great news!');
    });

    it('strips Gemini markers when current provider is xAI', () => {
      const input = 'Well, [mischievously] sneaky [trembling] reply.';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'grok'))
        .toBe('Well, sneaky reply.');
    });

    it('preserves user-typed lowercase brackets that are not fixed markers', () => {
      // [done] is lowercase but NOT in any family's fixed vocabulary; the
      // cross-family STRICT regexes ignore it (they use fixed lists only,
      // no catch-all). Active family (xAI) is already strict by design.
      expect(window.TtsTagSanitizer.sanitizeForDisplay('Task [done] yesterday.', 'grok'))
        .toBe('Task [done] yesterday.');
    });

    it("still applies own-family catch-all when provider is Gemini (multi-word descriptor)", () => {
      // Gemini is the active family — its OWN sanitizer keeps its free-form
      // catch-all, so `[quickly but clearly]` IS stripped.
      expect(window.TtsTagSanitizer.sanitizeForDisplay('Say this [quickly but clearly] now.', 'gemini-flash'))
        .toBe('Say this now.');
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
      // openai-tts-4o now has its own (instruction-mode) sanitizer that
      // strips the <<TTS:...>> sentinel. Without a sentinel in the input,
      // it also behaves as identity.
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'openai-tts')).toBe(input);
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'mistral')).toBe(input);
    });

    it('strips the <<TTS:...>> sentinel for openai-tts-4o (instruction mode)', () => {
      const input = '<<TTS:Voice: warm.\nTone: sincere.>>\nHello, how can I help?';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'openai-tts-4o'))
        .toBe('Hello, how can I help?');
    });

    it('strips a leftover <<TTS:...>> sentinel for a cross-family active provider', () => {
      // Session was on openai-tts-4o, now on grok — leftover sentinel in
      // a prior message should still not surface in the transcript.
      const input = '<<TTS:Voice: warm.>>\nLeftover from earlier turn.';
      expect(window.TtsTagSanitizer.sanitizeForDisplay(input, 'grok'))
        .toBe('Leftover from earlier turn.');
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
      // Use openai-tts (plain, no instruction support) — openai-tts-4o is
      // now tag-aware because it has a sanitizer for the instruction-mode
      // sentinel.
      window.params = { tts_provider: 'openai-tts' };
      expect(window.TtsTagSanitizer.tagAware()).toBe(false);
    });

    it('is tag-aware for openai-tts-4o (instruction-mode sanitizer)', () => {
      window.params = { tts_provider: 'openai-tts-4o' };
      expect(window.TtsTagSanitizer.tagAware()).toBe(true);
    });

    it('is tag-aware for ElevenLabs v3 only (Flash v2.5 / Multilingual v2 are NOT)', () => {
      window.params = { tts_provider: 'elevenlabs-v3' };
      expect(window.TtsTagSanitizer.tagAware()).toBe(true);

      ['elevenlabs-flash', 'elevenlabs-multilingual', 'elevenlabs'].forEach(p => {
        window.params = { tts_provider: p };
        expect(window.TtsTagSanitizer.tagAware()).toBe(false);
      });
    });

    it('is tag-aware for Gemini TTS variants', () => {
      window.params = { tts_provider: 'gemini-flash' };
      expect(window.TtsTagSanitizer.tagAware()).toBe(true);
    });
  });
});
