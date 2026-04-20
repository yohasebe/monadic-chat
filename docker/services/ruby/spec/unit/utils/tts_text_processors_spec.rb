# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/tts_text_processors'

RSpec.describe Monadic::Utils::TtsTextProcessors do
  describe '.family_for' do
    it 'maps xAI provider strings to the xai family' do
      expect(described_class.family_for('grok')).to eq('xai')
      expect(described_class.family_for('xai-tts')).to eq('xai')
    end

    it 'maps ElevenLabs v3 (and alias) to its own tag-aware family' do
      expect(described_class.family_for('elevenlabs-v3')).to eq('elevenlabs-v3')
      expect(described_class.family_for('eleven_v3')).to eq('elevenlabs-v3')
    end

    it 'maps legacy ElevenLabs variants to the non-tag-aware elevenlabs family' do
      %w[elevenlabs elevenlabs-flash elevenlabs-multilingual eleven_multilingual_v2 eleven_flash_v2_5].each do |p|
        expect(described_class.family_for(p)).to eq('elevenlabs')
      end
    end

    it 'maps OpenAI TTS variants to the openai family' do
      %w[openai-tts openai-tts-4o openai-tts-hd tts-1 tts-1-hd].each do |p|
        expect(described_class.family_for(p)).to eq('openai')
      end
    end

    it 'maps Gemini TTS variants to the gemini family' do
      %w[gemini gemini-flash gemini-pro].each do |p|
        expect(described_class.family_for(p)).to eq('gemini')
      end
    end

    it 'maps Mistral / Voxtral to the mistral family' do
      %w[mistral voxtral-mini-tts-2603].each do |p|
        expect(described_class.family_for(p)).to eq('mistral')
      end
    end

    it 'is case-insensitive and nil-safe' do
      expect(described_class.family_for('GROK')).to eq('xai')
      expect(described_class.family_for(nil)).to eq('')
    end
  end

  describe '.pre_send' do
    it 'is the identity function for unregistered providers' do
      expect(described_class.pre_send('openai-tts-4o', 'hello world')).to eq('hello world')
      expect(described_class.pre_send('mistral', 'こんにちは')).to eq('こんにちは')
    end

    it 'returns the original text for nil / empty input without raising' do
      expect(described_class.pre_send('grok', nil)).to be_nil
      expect(described_class.pre_send('grok', '')).to eq('')
    end

    context 'marker translation to xAI target' do
      it 'normalises ElevenLabs plural [laughs] to xAI singular [laugh]' do
        expect(described_class.pre_send('grok', 'Oh [laughs] that was wild.'))
          .to eq('Oh [laugh] that was wild.')
      end

      it 'normalises [sighs]/[crying]/[inhales] to xAI forms' do
        input = 'Well, [sighs] okay [crying] really sad, then [inhales] calm.'
        expect(described_class.pre_send('grok', input))
          .to eq('Well, [sigh] okay [cry] really sad, then [inhale] calm.')
      end

      it 'drops Gemini concepts without xAI equivalents' do
        # [gasp] maps to xAI [inhale] (mapped); [giggles] maps to [laugh].
        # Other free-form Gemini descriptors untouched by translation and
        # later handled by sanitizer on display.
        expect(described_class.pre_send('grok', 'Hmm [giggles] cute. [gasp] wait.'))
          .to eq('Hmm [laugh] cute. [inhale] wait.')
      end
    end

    context 'marker translation to ElevenLabs v3 target' do
      it 'normalises xAI singular [laugh] to ElevenLabs plural [laughs]' do
        expect(described_class.pre_send('elevenlabs-v3', 'Wait [laugh] really?'))
          .to eq('Wait [laughs] really?')
      end

      it 'drops xAI [pause] that ElevenLabs does not support' do
        expect(described_class.pre_send('elevenlabs-v3', 'Think [pause] and speak.'))
          .to eq('Think and speak.')
      end

      it 'collapses xAI wrap <whisper>X</whisper> to inline [whispers] X' do
        expect(described_class.pre_send('elevenlabs-v3', 'Now <whisper>quiet here</whisper> okay?'))
          .to eq('Now [whispers] quiet here okay?')
      end

      it 'drops wrap tags other than whisper (no ElevenLabs equivalent)' do
        expect(described_class.pre_send('elevenlabs-v3', 'Shout <loud>hey</loud> then quiet.'))
          .to eq('Shout hey then quiet.')
      end
    end

    context 'marker translation to Gemini target' do
      it 'normalises xAI [laugh] to Gemini [laughs]' do
        expect(described_class.pre_send('gemini-flash', 'Funny [laugh] story.'))
          .to eq('Funny [laughs] story.')
      end

      it 'maps xAI [inhale] to Gemini [gasp]' do
        expect(described_class.pre_send('gemini-pro', 'Oh [inhale] really?'))
          .to eq('Oh [gasp] really?')
      end

      it 'drops [exhale] / [pause] / [long-pause] (no Gemini equivalent)' do
        input = 'Think [pause] deeply, [long-pause] then [exhale] relax.'
        expect(described_class.pre_send('gemini-flash', input))
          .to eq('Think deeply, then relax.')
      end
    end

    context 'nested and malformed wrap tags' do
      it 'handles inline marker inside wrap correctly' do
        input = '<whisper>hello [laugh] friend</whisper>'
        expect(described_class.pre_send('elevenlabs-v3', input))
          .to eq('[whispers] hello [laughs] friend')
      end

      it 'handles two different wraps nested (inner is converted/dropped)' do
        input = '<loud>big <whisper>quiet</whisper> end</loud>'
        expect(described_class.pre_send('elevenlabs-v3', input))
          .to eq('big [whispers] quiet end')
      end

      it 'strips orphan whisper tags from nested same-name wraps' do
        # Non-greedy regex leaves one pair dangling; orphan cleanup removes it.
        input = '<whisper>A<whisper>nested</whisper>B</whisper>'
        expect(described_class.pre_send('elevenlabs-v3', input))
          .to eq('[whispers] AnestedB')
      end

      it 'strips unclosed <whisper> tags' do
        expect(described_class.pre_send('gemini-flash', '<whisper>no close here'))
          .to eq('no close here')
      end

      it 'strips orphan </whisper> closing tags' do
        # Orphan removal may leave a single trailing space; acceptable
        # cosmetic residue vs risking literal readout of the tag.
        expect(described_class.pre_send('elevenlabs-v3', '<whisper>hi</whisper> and </whisper>'))
          .to match(/^\[whispers\] hi and\s*$/)
      end

      it 'leaves xAI wrap structure untouched when target is xAI' do
        # xAI is the only engine that natively interprets span-wrap syntax;
        # we preserve user intent and let the engine handle edge cases.
        input = '<whisper>hello [laugh] friend</whisper>'
        expect(described_class.pre_send('grok', input))
          .to eq(input)
      end
    end

    context 'foreign marker drop (prevents literal readout)' do
      it 'drops ElevenLabs-only emotion markers when target is xAI' do
        input = 'Oh [excited] wow, [sarcastic] really, [trembling] scary!'
        expect(described_class.pre_send('grok', input))
          .to eq('Oh wow, really, scary!')
      end

      it 'drops Gemini-only emotion markers when target is xAI' do
        input = 'Hmm [mischievously] and [panicked] then [shouting] hey!'
        expect(described_class.pre_send('grok', input))
          .to eq('Hmm and then hey!')
      end

      it 'drops xAI mouth sounds when target is ElevenLabs v3' do
        expect(described_class.pre_send('elevenlabs-v3', 'Go [click] [smack] hey.'))
          .to eq('Go hey.')
      end

      it 'drops xAI mouth sounds and Gemini-specific markers when target is Gemini' do
        expect(described_class.pre_send('gemini-flash', 'Wait [smack] okay.'))
          .to eq('Wait okay.')
      end

      it 'preserves user-typed brackets like [TODO] (uppercase) and [1] (numeric)' do
        input = 'See [TODO] in ticket [1] please.'
        # None of these are vocabulary markers; they pass through to the engine.
        expect(described_class.pre_send('grok', input)).to eq(input)
        expect(described_class.pre_send('elevenlabs-v3', input)).to eq(input)
        expect(described_class.pre_send('gemini-flash', input)).to eq(input)
      end
    end
  end

  describe 'user-text preservation in union display sanitize' do
    it 'does NOT strip lowercase user-typed brackets that are not fixed markers' do
      # [done] is lowercase and not in any family's fixed vocabulary; the
      # active-family (xAI) strict regex ignores it, and cross-family STRICT
      # regexes also ignore it (they use fixed lists only, no catch-all).
      expect(described_class.sanitize_for_display('grok', 'Task [done] yesterday.'))
        .to eq('Task [done] yesterday.')
    end

    it 'still applies own-family catch-all when active provider is Gemini' do
      # Gemini family keeps its free-form catch-all for its OWN sanitizer —
      # so a multi-word descriptor IS stripped when user is on Gemini.
      expect(described_class.sanitize_for_display('gemini-flash', 'Say this [quickly but clearly] now.'))
        .to eq('Say this now.')
    end
  end

  describe '.sanitize_for_display' do
    context 'with the xai family' do
      it 'strips inline markers' do
        input = 'Oh wow [laugh] that is surprising [pause] I think.'
        expect(described_class.sanitize_for_display('grok', input))
          .to eq('Oh wow that is surprising I think.')
      end

      it 'strips wrapping tags while keeping their inner text' do
        input = '<whisper>Do not tell anyone.</whisper> Okay?'
        expect(described_class.sanitize_for_display('grok', input))
          .to eq('Do not tell anyone. Okay?')
      end

      it 'handles the complete marker vocabulary' do
        input = '[long-pause][inhale][exhale][click][smack][sigh][cry] text ' \
                '<loud>x</loud><soft>y</soft><high>z</high><low>w</low>' \
                '<fast>a</fast><slow>b</slow><sing>c</sing>'
        out = described_class.sanitize_for_display('grok', input)
        expect(out).not_to match(/\[[a-z-]+\]/)
        expect(out).not_to match(%r{</?[a-z]+>})
        expect(out).to include('x', 'y', 'z', 'w', 'a', 'b', 'c', 'text')
      end

      it 'does not punch holes before punctuation' do
        expect(described_class.sanitize_for_display('grok', 'Wait [pause] , really?'))
          .to eq('Wait, really?')
      end

      it 'strips BBCode-style malformed wrap tags emitted by confused LLMs' do
        # Real-world case: LLM mixed up wrap-tag syntax, wrote `[high]text[/high]`
        # in square brackets (should have been `<high>text</high>`). Neither the
        # engine nor the primary regex recognises these; the malformed catchers
        # handle them defensively.
        input = 'surprise [high]Wow![/high], fear Eek![/inhale], and more.'
        expect(described_class.sanitize_for_display('grok', input))
          .to eq('surprise Wow!, fear Eek!, and more.')
      end

      it 'strips stray closing-style brackets for inline markers' do
        expect(described_class.sanitize_for_display('grok', 'Thinking. [/pause] Okay.'))
          .to eq('Thinking. Okay.')
      end
    end

    context 'with the elevenlabs-v3 family' do
      it 'strips curated inline tags' do
        input = 'Oh wow [laughs] that is hilarious. [sighs] Anyway.'
        expect(described_class.sanitize_for_display('elevenlabs-v3', input))
          .to eq('Oh wow that is hilarious. Anyway.')
      end

      it 'also strips improvised multi-word lowercase descriptors' do
        input = 'Hmm [laughing harder] this is priceless.'
        out = described_class.sanitize_for_display('elevenlabs-v3', input)
        expect(out).to eq('Hmm this is priceless.')
      end

      it 'does not strip ordinary bracketed text such as TODO markers' do
        # Uppercase and digit-only brackets are preserved since they are
        # unlikely to be TTS markers.
        expect(described_class.sanitize_for_display('elevenlabs-v3', 'See [TODO] and [1].'))
          .to eq('See [TODO] and [1].')
      end

      it 'leaves tags untouched for non-v3 ElevenLabs models (no sanitizer registered)' do
        input = '[laughs] kept because Flash cannot interpret it anyway.'
        %w[elevenlabs-flash elevenlabs-multilingual elevenlabs].each do |p|
          expect(described_class.sanitize_for_display(p, input)).to eq(input)
        end
      end
    end

    describe 'cross-provider union (mid-session TTS switch cleanup)' do
      it 'strips xAI wrap markers when the current provider is ElevenLabs v3' do
        input = 'Sure, <whisper>secret</whisper> and [laugh] here.'
        expect(described_class.sanitize_for_display('elevenlabs-v3', input))
          .to eq('Sure, secret and here.')
      end

      it 'strips ElevenLabs markers when the current provider is xAI' do
        input = 'Oh [laughs] that is [excited] great news!'
        expect(described_class.sanitize_for_display('grok', input))
          .to eq('Oh that is great news!')
      end

      it 'strips Gemini markers when the current provider is xAI' do
        input = 'Well, [mischievously] sneaky [trembling] reply.'
        expect(described_class.sanitize_for_display('grok', input))
          .to eq('Well, sneaky reply.')
      end
    end

    context 'with the gemini family' do
      it 'strips the 16 fixed audio tags' do
        input = 'Really [amazed] wow [mischievously] sneaky [whispers] secret.'
        expect(described_class.sanitize_for_display('gemini-flash', input))
          .to eq('Really wow sneaky secret.')
      end

      it 'strips free-form descriptor tags Gemini supports' do
        input = 'Saying this [sarcastically, one painfully slow word at a time] is the point.'
        expect(described_class.sanitize_for_display('gemini-pro', input))
          .to eq('Saying this is the point.')
      end
    end

    it 'is the identity function for providers without a registered sanitizer' do
      input = '<whisper>kept as-is</whisper>'
      expect(described_class.sanitize_for_display('openai-tts-4o', input)).to eq(input)
      expect(described_class.sanitize_for_display('mistral', input)).to eq(input)
    end

    it 'is nil-safe' do
      expect(described_class.sanitize_for_display('grok', nil)).to be_nil
      expect(described_class.sanitize_for_display('grok', '')).to eq('')
    end
  end

  describe '.tag_aware?' do
    it 'reports true for providers with a display sanitizer' do
      expect(described_class.tag_aware?('grok')).to be true
    end

    it 'reports true for ElevenLabs v3 and Gemini families' do
      expect(described_class.tag_aware?('elevenlabs-v3')).to be true
      expect(described_class.tag_aware?('gemini-flash')).to be true
    end

    it 'reports false for ElevenLabs Flash / Multilingual (non-v3 models)' do
      %w[elevenlabs elevenlabs-flash elevenlabs-multilingual eleven_flash_v2_5 eleven_multilingual_v2].each do |p|
        expect(described_class.tag_aware?(p)).to be(false), "expected #{p} to NOT be tag-aware"
      end
    end

    it 'reports false for providers without one' do
      expect(described_class.tag_aware?('openai-tts-4o')).to be false
      expect(described_class.tag_aware?('mistral')).to be false
      expect(described_class.tag_aware?('webspeech')).to be false
    end
  end
end
