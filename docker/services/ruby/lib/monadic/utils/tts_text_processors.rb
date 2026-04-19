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
        return "xai"        if key == "grok" || key.start_with?("xai")
        return "elevenlabs" if key.start_with?("elevenlabs")
        return "gemini"     if key.start_with?("gemini")
        return "mistral"    if key.start_with?("mistral") || key.include?("voxtral")
        return "openai"     if key.start_with?("openai") || key.start_with?("tts-")
        key
      end

      XAI_INLINE_MARKERS = %w[pause long-pause laugh sigh cry click smack inhale exhale].freeze
      XAI_WRAP_TAGS      = %w[loud soft high low fast slow whisper sing].freeze

      XAI_INLINE_RE = /\[(?:#{XAI_INLINE_MARKERS.join('|')})\]/i
      XAI_WRAP_RE   = %r{</?(?:#{XAI_WRAP_TAGS.join('|')})>}i

      PRE_SEND = {
        # Registered providers receive a Proc; unregistered ones pass through identity.
        # xAI and ElevenLabs currently need no pre-send transformation — their
        # engines consume tags verbatim.
      }.freeze

      DISPLAY_SANITIZE = {
        "xai" => ->(text) {
          text.to_s
              .gsub(XAI_WRAP_RE, "")
              .gsub(XAI_INLINE_RE, "")
              .gsub(/[ \t]{2,}/, " ")
              .gsub(/\s+([,.!?;:])/, '\1')
        }
        # "elevenlabs" => TODO once Eleven v3 audio tags are used by any app.
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
