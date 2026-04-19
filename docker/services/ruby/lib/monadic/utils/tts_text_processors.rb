# frozen_string_literal: true

module Monadic
  module Utils
    # Provider-keyed registry for TTS text transformations.
    #
    # Two transformation roles:
    #   * PRE_SEND        — applied to the text just before it leaves for the TTS API.
    #                       Default is identity. Registered only when a provider needs
    #                       custom normalization (rare — most engines accept raw text).
    #   * DISPLAY_SANITIZE — strip audio-control markup so that text shown in the UI
    #                       does not expose engine tags. Registered only for providers
    #                       whose tags would otherwise leak into the rendered output.
    #
    # xAI Grok TTS recognizes:
    #   * Inline markers: [pause] [long-pause] [laugh] [sigh] [cry]
    #                     [click] [smack] [inhale] [exhale]
    #   * Wrapping tags:  <loud> <soft> <high> <low> <fast> <slow> <whisper> <sing>
    # (see https://docs.x.ai/ Text-to-Speech reference)
    #
    # ElevenLabs v3 supports a similar inline-tag vocabulary; its sanitizer slot is
    # reserved below as a TODO so that a future app integration can register it
    # without touching this file's structure.
    module TtsTextProcessors
      module_function

      # Canonical family for a provider string. Voice Chat apps and WS handlers
      # emit varied values (e.g., "grok", "openai-tts-4o", "elevenlabs-v3"); this
      # collapses them into a single key that the registries look up against.
      def family_for(provider)
        key = provider.to_s.downcase
        return "xai" if key == "grok" || key.start_with?("xai")
        # ONLY ElevenLabs v3 interprets inline audio tags. Flash v2.5 and
        # Multilingual v2 read bracket content as literal text, so they must
        # not share the v3 family identifier (otherwise Expressive Speech
        # would inject markers the engine cannot interpret).
        return "elevenlabs-v3" if key == "elevenlabs-v3" || key == "eleven_v3"
        return "elevenlabs" if key.start_with?("elevenlabs") || key.start_with?("eleven_")
        return "gemini"     if key.start_with?("gemini")
        return "mistral"    if key.start_with?("mistral") || key.include?("voxtral")
        return "openai"     if key.start_with?("openai") || key.start_with?("tts-")
        key
      end

      XAI_INLINE_MARKERS = %w[pause long-pause laugh sigh cry click smack inhale exhale].freeze
      XAI_WRAP_TAGS      = %w[loud soft high low fast slow whisper sing].freeze

      XAI_INLINE_RE = /\[(?:#{XAI_INLINE_MARKERS.join('|')})\]/i
      XAI_WRAP_RE   = %r{</?(?:#{XAI_WRAP_TAGS.join('|')})>}i

      # ElevenLabs v3 audio tags include compound phrases (e.g., "laughing
      # harder"); the display regex matches a tighter curated set but accepts
      # multi-word lowercase descriptors up to ~30 chars so the UI still
      # cleans up when the model improvises a tag the prompt did not list.
      ELEVENLABS_INLINE_MARKERS = %w[laughs sighs whispers excited sarcastic curious
                                      crying angry sad happy giggles sobs sings
                                      exhales inhales].freeze
      # NOTE: no `i` flag — the free-form catch-all is intentionally
      # lowercase-only so that ordinary all-caps brackets like `[TODO]` or
      # numeric brackets like `[1]` are preserved in the transcript.
      ELEVENLABS_INLINE_RE      = /\[(?:#{ELEVENLABS_INLINE_MARKERS.join('|')}|[a-z][a-z ]{2,30})\]/

      # Gemini TTS supports 16 fixed tags plus arbitrary free-form descriptors.
      # We strip the fixed set plus any short lowercase descriptor in brackets
      # (same loose fallback as ElevenLabs) — see vocabulary registry for why
      # the prompt deliberately restricts the LLM to the fixed set only.
      GEMINI_INLINE_MARKERS = %w[amazed crying curious excited sighs gasp giggles
                                  laughs mischievously panicked sarcastic serious
                                  shouting tired trembling whispers].freeze
      # NOTE: no `i` flag — see the ElevenLabs regex above for the rationale.
      GEMINI_INLINE_RE      = /\[(?:#{GEMINI_INLINE_MARKERS.join('|')}|[a-z][a-z ,]{2,60})\]/

      PRE_SEND = {
        # Registered providers receive a Proc; unregistered ones pass through identity.
        # xAI, ElevenLabs and Gemini currently need no pre-send transformation —
        # their engines consume tags verbatim.
      }.freeze

      DISPLAY_SANITIZE = {
        "xai" => ->(text) {
          text.to_s
              .gsub(XAI_WRAP_RE, "")
              .gsub(XAI_INLINE_RE, "")
              .gsub(/[ \t]{2,}/, " ")
              .gsub(/\s+([,.!?;:])/, '\1')
        },
        "elevenlabs-v3" => ->(text) {
          text.to_s
              .gsub(ELEVENLABS_INLINE_RE, "")
              .gsub(/[ \t]{2,}/, " ")
              .gsub(/\s+([,.!?;:])/, '\1')
        },
        "gemini" => ->(text) {
          text.to_s
              .gsub(GEMINI_INLINE_RE, "")
              .gsub(/[ \t]{2,}/, " ")
              .gsub(/\s+([,.!?;:])/, '\1')
        }
      }.freeze

      def pre_send(provider, text)
        return text if text.nil? || text.empty?
        fn = PRE_SEND[family_for(provider)]
        fn ? fn.call(text) : text
      end

      def sanitize_for_display(provider, text)
        return text if text.nil? || text.empty?
        fn = DISPLAY_SANITIZE[family_for(provider)]
        fn ? fn.call(text) : text
      end

      def tag_aware?(provider)
        DISPLAY_SANITIZE.key?(family_for(provider))
      end
    end
  end
end
