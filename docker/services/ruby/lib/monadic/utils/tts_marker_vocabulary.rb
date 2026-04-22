# frozen_string_literal: true

require_relative 'tts_text_processors'

module Monadic
  module Utils
    # Provider-keyed registry of TTS speech-marker vocabularies used by the
    # Expressive Speech feature.
    #
    # When a user turns on Auto Speech and selects a TTS provider whose engine
    # interprets inline markers (xAI Grok, ElevenLabs v3, Gemini TTS, ...),
    # the request builder appends a short "output format" addendum to the
    # system prompt teaching the LLM which markers to emit. The addendum is
    # always attached at the end of the system prompt so that prompt caching
    # (Anthropic, OpenAI) keeps the stable prefix hot.
    #
    # Families use the same canonical key scheme as `TtsTextProcessors` so
    # that display sanitization and prompt injection share one normalization
    # path.
    module TtsMarkerVocabulary
      module_function

      VOCABULARIES = {
        "xai" => {
          inline:   %w[pause long-pause laugh sigh cry inhale exhale click smack].freeze,
          wrapping: %w[whisper soft loud fast slow high low sing].freeze,
          examples: [
            'Oh wow [laugh] that is quite a story.',
            "Let me think. [pause] Okay, here's an idea.",
            '<whisper>Between you and me</whisper> I am not so sure either.'
          ].freeze
        }.freeze,
        # ElevenLabs v3 audio-tag vocabulary. ONLY the v3 model interprets
        # these tags; Flash v2.5 and Multilingual v2 read bracket content as
        # literal text, so the family key is deliberately "elevenlabs-v3" to
        # exclude the other variants from Expressive Speech activation.
        # The engine accepts a broader set than listed here (including
        # multi-word tags like "laughing harder"), but the prompt only
        # advertises curated single-word tags for output predictability.
        # The display sanitizer matches a wider regex so the UI still
        # cleans up if the model improvises.
        "elevenlabs-v3" => {
          inline:   %w[laughs sighs whispers excited sarcastic curious crying
                       angry sad happy giggles sobs sings exhales inhales].freeze,
          wrapping: [].freeze,
          examples: [
            'Oh wow [laughs] that is quite a story.',
            '[whispers] Between you and me, I am not so sure either.',
            '[excited] That is brilliant news!'
          ].freeze
        }.freeze,
        # Gemini TTS advertises 16 fixed audio tags and also accepts free-form
        # descriptive tags (e.g., "[like a cartoon dog]"). We intentionally
        # restrict the prompt to the fixed set to keep LLM output predictable.
        "gemini" => {
          inline:   %w[amazed crying curious excited sighs gasp giggles laughs
                       mischievously panicked sarcastic serious shouting tired
                       trembling whispers].freeze,
          wrapping: [].freeze,
          examples: [
            '[laughs] That is hilarious!',
            'Okay, [whispers] do not tell anyone.',
            '[excited] Guess what just happened?'
          ].freeze
        }.freeze
      }.freeze

      # Canonical family key for a provider string.
      def family_for(provider)
        Monadic::Utils::TtsTextProcessors.family_for(provider)
      end

      # True when the provider has an inline-marker vocabulary (xAI /
      # ElevenLabs v3 / Gemini). Used to decide if the LLM should be taught
      # marker syntax.
      def tag_aware?(provider)
        VOCABULARIES.key?(family_for(provider))
      end

      # True when the provider supports out-of-band instruction-mode (OpenAI
      # gpt-4o-mini-tts). This is a distinct mechanism from inline markers —
      # the LLM produces a directive block that rides alongside, not inside,
      # the message text.
      def instruction_mode?(provider)
        family_for(provider) == "openai-instruction"
      end

      # True when the provider accepts natural-language voice/style
      # directives — either as an out-of-band parameter (OpenAI) or as a
      # leading in-band prefix (Gemini). Callers use this to decide whether
      # to extract a `<<TTS:...>>` block from the LLM response.
      #
      # Gemini officially supports both inline tags AND natural-language
      # style prompts per `ai.google.dev/gemini-api/docs/speech-generation`
      # ("Controlling speech style with prompts"). We treat the Gemini
      # family as hybrid: the LLM may emit markers, a directive block, or
      # both, and the backend routes the directive into the text prefix.
      def instruction_capable?(provider)
        return true if instruction_mode?(provider)
        family_for(provider) == "gemini"
      end

      def vocabulary_for(provider)
        VOCABULARIES[family_for(provider)]
      end

      # Produce the addendum text to be appended to the system prompt when
      # Expressive Speech is active. Dispatches to the right generator by
      # family × capability × app-Monadic state. Returns nil when the
      # provider has no applicable addendum.
      #
      # Dispatch precedence (most specific first):
      #   tag_aware + instruction_capable (Gemini) → hybrid addendum
      #   tag_aware only (xAI / ElevenLabs v3)     → marker addendum
      #   instruction_mode (OpenAI 4o)             → instruction addendum
      #   else                                     → nil
      #
      # @param provider [String] TTS provider dropdown value
      # @param app_is_monadic [Boolean] whether the active app is Monadic
      def prompt_addendum_for(provider, app_is_monadic: false)
        if tag_aware?(provider) && instruction_capable?(provider)
          return hybrid_addendum_for(provider, app_is_monadic: app_is_monadic)
        end
        return marker_addendum_for(provider)         if tag_aware?(provider)
        return instruction_addendum(app_is_monadic:) if instruction_mode?(provider)
        nil
      end

      # Inline-marker addendum (xAI / ElevenLabs v3 / Gemini). Extracted from
      # the original prompt_addendum_for body; unchanged behaviour.
      def marker_addendum_for(provider)
        vocab = vocabulary_for(provider)
        return nil unless vocab

        inline_line   = vocab[:inline].map { |m| "[#{m}]" }.join(" ")
        wrap_line     = vocab[:wrapping].map { |m| "<#{m}>...</#{m}>" }.join("  ")
        examples_text = vocab[:examples].map { |e| "  \"#{e}\"" }.join("\n")

        sections = []
        sections << "Expressive Speech — the user has enabled a voice engine that interprets inline speech markers. Weave them sparingly into your reply at genuine emotional moments — at most one or two per response. When unsure, omit them entirely."
        sections << ""
        sections << "Inline markers (single token in square brackets, placed mid-sentence):"
        sections << "  #{inline_line}"
        unless vocab[:wrapping].empty?
          sections << ""
          sections << "Wrapping markers (surround a short span with matching angle-bracket tags):"
          sections << "  #{wrap_line}"
        end
        sections << ""
        sections << "Good examples:"
        sections << examples_text
        sections << ""
        sections << "Strict rules about the markers (treat these as hard constraints):"
        sections << "- Never name, quote, describe, explain, or list the markers. They are silent stage directions for the voice engine, not topics of conversation."
        sections << "- If the user asks about your laughter, sighing, whispering, or \"tags\", answer in plain natural language about the feeling itself, without ever spelling out the marker syntax."
        sections << "- Never open a conversation with a marker — the first utterance should read cleanly."
        sections << "- When in doubt, write the sentence without any marker."
        unless vocab[:wrapping].empty?
          sections << "- Syntax is strict: inline markers are a single token in SQUARE brackets with NO closing form (e.g., `[laugh]` — never `[/laugh]` or `[laugh]...[/laugh]`). Wrapping markers use ANGLE brackets with a matching closing tag (e.g., `<whisper>secret</whisper>` — never `[whisper]secret[/whisper]` or `[high]text[/high]`). Mixing the two syntaxes produces broken output."
        end

        sections.join("\n")
      end

      # The six-line attribute template shared by both instruction-mode
      # variants. The LLM fills in each slot with a short natural-language
      # description. See `docs_dev/expressive_speech_instruction_mode.md` §5.5
      # for the rationale.
      INSTRUCTION_ATTRIBUTE_TEMPLATE = <<~TMPL.strip
        Voice: <character of the voice — e.g., warm and clear, cool and mellow>
        Tone: <emotional coloring — e.g., sincere, playful, serious>
        Pacing: <speed and rhythm — e.g., steady and unhurried, rapid and punchy>
        Emotion: <state being conveyed — e.g., empathetic, excited, calm>
        Pronunciation: <articulation style — e.g., clear and precise>
        Pauses: <where to break — e.g., brief after apologies>
      TMPL

      # Out-of-band instruction-mode addendum (OpenAI gpt-4o-mini-tts).
      # Produces one of two variants based on whether the active app is
      # Monadic:
      #   * Monadic app  → JSON sibling `tts_instructions` field
      #   * non-Monadic  → `<<TTS:...>>` sentinel prefix (stripped in backend
      #                    before display; plain text follows the sentinel)
      def instruction_addendum(app_is_monadic:)
        app_is_monadic ? instruction_addendum_json : instruction_addendum_sentinel
      end

      # Intensity-matching guidance shared by both variants. Teaches the LLM
      # to escalate the directive's vividness when the reply is emotionally
      # strong, using visceral body-state verbs rather than mild adjectives.
      # Without this guidance, the LLM tends to default to neutral wording
      # ("warm and playful") even when the user requested dramatic delivery,
      # which the TTS engine then interprets as mild variation.
      INSTRUCTION_INTENSITY_GUIDANCE = <<~TEXT.strip
        Match the directive's intensity to the reply's intensity. For neutral or factual content, keep directives neutral ("Voice: natural, balanced. Tone: conversational. Pacing: steady."). For strong emotional content — laughter, tears, anger, excitement, fear, awe — use visceral body-state verbs like "breathless", "gasping", "trembling", "choked", "bursting", "whispered", "quivering". The TTS engine responds far more strongly to vivid physical descriptions than to abstract emotion words alone.
      TEXT

      def instruction_addendum_json
        <<~ADDENDUM.strip
          Expressive Speech (instruction mode): your JSON response should include an additional top-level field `tts_instructions` alongside `message` and `context`. The value is a 3-6 line directive for the text-to-speech engine using this exact attribute structure (one per line):

          #{INSTRUCTION_ATTRIBUTE_TEMPLATE.lines.map { |l| "  #{l}" }.join.rstrip}

          #{INSTRUCTION_INTENSITY_GUIDANCE}

          Keep `tts_instructions` under 600 characters.

          Plain prose only in `message` — no bracketed stage directions like [laugh] or [pause], no angle-bracket tags like <whisper>.

          Example (strong amusement):
          {
            "message": "Oh my goodness, stop — you completely caught me off guard with that one.",
            "context": { ... your app's usual context fields ... },
            "tts_instructions": "Voice: breathless, barely containing laughter.\\nTone: uncontrollably amused, losing composure.\\nPacing: broken by gasps and mid-word chuckles.\\nEmotion: helpless joy, tears of laughter.\\nPronunciation: words faltering between giggles.\\nPauses: sudden bursts for air between thoughts."
          }
        ADDENDUM
      end

      def instruction_addendum_sentinel
        <<~ADDENDUM.strip
          Expressive Speech (instruction mode): begin every response with a text-to-speech directive block, then the actual reply on the next line.

          The directive block uses the literal delimiters `<<TTS:` and `>>` around a 3-6 line instruction set, one attribute per line:

          #{INSTRUCTION_ATTRIBUTE_TEMPLATE.lines.map { |l| "  #{l}" }.join.rstrip}

          #{INSTRUCTION_INTENSITY_GUIDANCE}

          Keep the directive block under 600 characters. The delimiters `<<TTS:` and `>>` are stripped before the message is shown to the user; only the reply text after `>>` is displayed and spoken aloud. Never refer to the delimiters in your reply.

          Plain prose only in the reply — no bracketed stage directions like [laugh] or [pause], no angle-bracket tags like <whisper>.

          Example (strong amusement):
          <<TTS:Voice: breathless, barely containing laughter.
          Tone: uncontrollably amused, losing composure.
          Pacing: broken by gasps and mid-word chuckles.
          Emotion: helpless joy, tears of laughter.
          Pronunciation: words faltering between giggles.
          Pauses: sudden bursts for air between thoughts.>>

          Oh my goodness, stop — you completely caught me off guard with that one.
        ADDENDUM
      end

      # Hybrid addendum for engines that accept BOTH inline markers and a
      # leading natural-language directive block (Gemini TTS). The LLM is
      # free to choose per-turn: markers only, directive only, both, or
      # neither. The backend reads the directive block (when present) and
      # prepends it to the text as an in-band prefix before calling the
      # Gemini API — Gemini's own models interpret it as a director's note
      # rather than literal speech. See `docs_dev/expressive_speech.md`.
      def hybrid_addendum_for(provider, app_is_monadic: false)
        vocab = vocabulary_for(provider)
        return nil unless vocab

        inline_line = vocab[:inline].map { |m| "[#{m}]" }.join(" ")
        attribute_template =
          INSTRUCTION_ATTRIBUTE_TEMPLATE.lines.map { |l| "  #{l}" }.join.rstrip

        sections = []
        sections << "Expressive Speech — the Gemini voice engine supports TWO complementary controls that may be used independently or together:"
        sections << ""
        sections << "1) Inline markers in the reply text (same as xAI / ElevenLabs v3 style):"
        sections << "   #{inline_line}"
        sections << "   Use sparingly at genuine emotional moments — at most one or two per response."
        sections << ""
        sections << "2) A leading directive block for higher-level voice shaping. When present, it appears at the very start of the response between the literal delimiters `<<TTS:` and `>>`, with a 3-6 line attribute set (one per line):"
        sections << ""
        sections << attribute_template
        sections << ""
        sections << "   You may also add extra free-form lines inside the same block for scene, audio-profile, or accent descriptions (e.g., \"Scene: late-night radio studio, warm ambient room tone.\"). Keep the entire block under 600 characters."
        sections << ""
        sections << INSTRUCTION_INTENSITY_GUIDANCE
        sections << ""
        sections << "Rules (hard constraints):"
        sections << "- Never name, quote, describe, or list the markers or the directive block's delimiters in your reply. They are silent stage directions, not conversation topics."
        sections << "- The `<<TTS:...>>` block is stripped before the message is shown to the user; the engine reads it as a director's note, not as speech."
        sections << "- Never open a conversation with a marker or directive block — the first-turn utterance should read cleanly."
        sections << "- Per-turn you may use markers only, the directive block only, both, or neither. Match the tool to the moment."
        sections << ""
        sections << "Example (hybrid, strong amusement):"
        sections << "<<TTS:Voice: breathless, barely containing laughter."
        sections << "Tone: uncontrollably amused."
        sections << "Pacing: broken by gasps and mid-word chuckles.>>"
        sections << ""
        sections << "[laughs] Oh my goodness, stop — [sighs] you completely caught me off guard with that one."

        sections.join("\n")
      end
    end
  end
end
