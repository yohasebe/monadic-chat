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
        }.freeze
        # ElevenLabs v3 and Gemini are registered in Phase E.
      }.freeze

      # Canonical family key for a provider string.
      def family_for(provider)
        Monadic::Utils::TtsTextProcessors.family_for(provider)
      end

      def tag_aware?(provider)
        VOCABULARIES.key?(family_for(provider))
      end

      def vocabulary_for(provider)
        VOCABULARIES[family_for(provider)]
      end

      # Produce the addendum text to be appended to the system prompt when
      # Expressive Speech is active for the given provider. Returns nil when
      # the provider has no registered vocabulary.
      def prompt_addendum_for(provider)
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

        sections.join("\n")
      end
    end
  end
end
