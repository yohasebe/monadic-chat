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

      # LLM sometimes confuses the two xAI syntaxes and emits BBCode-like
      # hybrids that neither the engine nor the two patterns above recognise.
      # Strip these defensively so they never surface in the transcript:
      #   [/anything]          — closing-style square bracket (inline markers
      #                          have no closing form, so this is always wrong)
      #   [wrap-tag]           — a wrap tag (e.g., `high`, `whisper`) written
      #                          with square brackets instead of angle brackets
      XAI_MALFORMED_CLOSING_RE = %r{\[/[a-z-]+\]}i
      XAI_MALFORMED_SQUARE_WRAP_RE = /\[(?:#{XAI_WRAP_TAGS.join('|')})\]/i

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
      # Strict variant — fixed markers only, no catch-all. Used for cross-
      # family union sanitisation where we must not false-positive on
      # user-typed lowercase brackets like `[done]` or `[foo bar]`.
      ELEVENLABS_INLINE_STRICT_RE = /\[(?:#{ELEVENLABS_INLINE_MARKERS.join('|')})\]/i

      # Gemini TTS supports 16 fixed tags plus arbitrary free-form descriptors.
      # We strip the fixed set plus any short lowercase descriptor in brackets
      # (same loose fallback as ElevenLabs) — see vocabulary registry for why
      # the prompt deliberately restricts the LLM to the fixed set only.
      GEMINI_INLINE_MARKERS = %w[amazed crying curious excited sighs gasp giggles
                                  laughs mischievously panicked sarcastic serious
                                  shouting tired trembling whispers].freeze
      # NOTE: no `i` flag — see the ElevenLabs regex above for the rationale.
      GEMINI_INLINE_RE      = /\[(?:#{GEMINI_INLINE_MARKERS.join('|')}|[a-z][a-z ,]{2,60})\]/
      # Strict variant — fixed markers only, no free-form catch-all.
      GEMINI_INLINE_STRICT_RE = /\[(?:#{GEMINI_INLINE_MARKERS.join('|')})\]/i

      # Semantic concept table for TTS marker translation.
      #
      # Each concept maps a family-agnostic meaning (LAUGH, SIGH, PAUSE, ...)
      # to (a) a regex matching ANY known form that LLMs might emit across
      # providers, and (b) per-target rendering. A `nil` target means "this
      # concept has no equivalent in the target engine — drop it".
      #
      # The translation layer (invoked via PRE_SEND at the TTS API boundary)
      # lets the LLM emit any familiar marker form; whatever it produces is
      # normalized to the target engine's syntax just before sending. This
      # is more robust than relying on the LLM to pick the right syntax
      # every turn.
      INLINE_CONCEPTS = {
        laugh: {
          match: /\[(?:laugh|laughs|laughing)\]/i,
          emit: { "xai" => "[laugh]", "elevenlabs-v3" => "[laughs]", "gemini" => "[laughs]" }
        },
        giggle: {
          match: /\[(?:giggle|giggles|giggling)\]/i,
          emit: { "xai" => "[laugh]", "elevenlabs-v3" => "[giggles]", "gemini" => "[giggles]" }
        },
        sigh: {
          match: /\[(?:sigh|sighs|sighing)\]/i,
          emit: { "xai" => "[sigh]", "elevenlabs-v3" => "[sighs]", "gemini" => "[sighs]" }
        },
        cry: {
          match: /\[(?:cry|crying|sob|sobs|sobbing)\]/i,
          emit: { "xai" => "[cry]", "elevenlabs-v3" => "[crying]", "gemini" => "[crying]" }
        },
        pause: {
          match: /\[pause\]/i,
          emit: { "xai" => "[pause]", "elevenlabs-v3" => nil, "gemini" => nil }
        },
        long_pause: {
          match: /\[long-pause\]/i,
          emit: { "xai" => "[long-pause]", "elevenlabs-v3" => nil, "gemini" => nil }
        },
        inhale: {
          match: /\[(?:inhale|inhales|gasp|gasps)\]/i,
          emit: { "xai" => "[inhale]", "elevenlabs-v3" => "[inhales]", "gemini" => "[gasp]" }
        },
        exhale: {
          match: /\[(?:exhale|exhales)\]/i,
          emit: { "xai" => "[exhale]", "elevenlabs-v3" => "[exhales]", "gemini" => nil }
        }
      }.freeze

      # Build drop regex per target family: any marker that belongs to ANOTHER
      # tag-aware family's vocabulary but is not recognised by the target.
      # After concept-level translation, these foreign markers would be read
      # literally by the target engine (e.g., xAI reading "excited" as a word
      # when it sees `[excited]` from an ElevenLabs-trained habit). The drop
      # keeps the audio clean; concept translation (above) keeps the
      # expressive intent where an equivalent exists.
      FOREIGN_MARKER_RE = {
        "xai"           => /\[(?:#{(ELEVENLABS_INLINE_MARKERS + GEMINI_INLINE_MARKERS - XAI_INLINE_MARKERS).uniq.join('|')})\]/i,
        "elevenlabs-v3" => /\[(?:#{(XAI_INLINE_MARKERS + GEMINI_INLINE_MARKERS - ELEVENLABS_INLINE_MARKERS).uniq.join('|')})\]/i,
        "gemini"        => /\[(?:#{(XAI_INLINE_MARKERS + ELEVENLABS_INLINE_MARKERS - GEMINI_INLINE_MARKERS).uniq.join('|')})\]/i
      }.freeze

      # Non-whisper xAI wrap tags have no direct equivalent in ElevenLabs or
      # Gemini inline syntax; we drop them when targeting those engines.
      # Derived from XAI_WRAP_TAGS so a new xAI wrap added upstream flows
      # through automatically (no second list to sync).
      XAI_NON_WHISPER_WRAP_RE = %r{</?(?:#{(XAI_WRAP_TAGS - ['whisper']).join('|')})>}i

      # Translate all known markers in `text` to whatever the target family's
      # engine actually understands. Happens in three passes:
      #   (1) Concept translation — cross-family plural/singular/synonym
      #       normalisation for markers that DO have target equivalents.
      #   (2) Wrap handling — xAI's span-wrap syntax is either kept (target
      #       is xAI) or collapsed to the nearest inline form (target is
      #       ElevenLabs/Gemini) or dropped (non-whisper wraps on those).
      #   (3) Foreign-marker drop — anything still bracketed that belongs to
      #       ANOTHER family's vocabulary is removed to prevent literal
      #       readout by the target engine.
      # Unknown brackets (user-typed `[TODO]`, numeric `[1]`, novel tokens)
      # are intentionally left untouched — the target engine will read them
      # as text, which is the right fallback for content we cannot classify.
      def translate_markers(text, target_family)
        return text if text.nil? || text.empty?
        result = text.to_s

        # Pass 1: concept translation
        INLINE_CONCEPTS.each_value do |concept|
          next unless concept[:emit].key?(target_family)
          target_form = concept[:emit][target_family]
          replacement = target_form.nil? ? "" : target_form
          result = result.gsub(concept[:match], replacement)
        end

        # Pass 2: wrap handling
        if target_family == "elevenlabs-v3" || target_family == "gemini"
          result = result.gsub(%r{<whisper>(.*?)</whisper>}i, '[whispers] \1')
          result = result.gsub(XAI_NON_WHISPER_WRAP_RE, "")
          # Strip any remaining orphan whisper tags that arise from:
          # (a) nested same-name wraps — non-greedy regex leaves one pair
          #     dangling, e.g. `<whisper>A<whisper>B</whisper></whisper>`,
          # (b) unclosed tags — LLM forgot to emit `</whisper>`,
          # (c) stray closing tags — extra `</whisper>` without a partner.
          # Without this pass they would pass through to the engine and be
          # read literally as text.
          result = result.gsub(%r{</?whisper>}i, "")
        end

        # Pass 3: foreign-marker drop
        foreign_re = FOREIGN_MARKER_RE[target_family]
        result = result.gsub(foreign_re, "") if foreign_re

        # Cosmetic cleanup (idempotent with DISPLAY_SANITIZE's own cleanup).
        result.gsub(/[ \t]{2,}/, " ").gsub(/\s+([,.!?;:])/, '\1')
      end

      PRE_SEND = {
        # Per-family translators. The LLM is free to emit any known marker
        # form (singular/plural, wrap/inline); the target engine sees only
        # its own preferred syntax. Unsupported concepts are dropped silently.
        "xai"           => ->(text) { Monadic::Utils::TtsTextProcessors.translate_markers(text, "xai") },
        "elevenlabs-v3" => ->(text) { Monadic::Utils::TtsTextProcessors.translate_markers(text, "elevenlabs-v3") },
        "gemini"        => ->(text) { Monadic::Utils::TtsTextProcessors.translate_markers(text, "gemini") }
      }.freeze

      DISPLAY_SANITIZE = {
        "xai" => ->(text) {
          text.to_s
              .gsub(XAI_WRAP_RE, "")
              .gsub(XAI_INLINE_RE, "")
              .gsub(XAI_MALFORMED_CLOSING_RE, "")
              .gsub(XAI_MALFORMED_SQUARE_WRAP_RE, "")
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
        return text unless tag_aware?(provider)

        fam = family_for(provider)
        # Own family: apply the full sanitizer (includes free-form catch-all
        # for ElevenLabs/Gemini so that improvised descriptors like
        # `[laughing harder]` or `[sarcastically, slowly]` are also cleaned).
        result = DISPLAY_SANITIZE[fam].call(text)
        # Cross-family cleanup: strip OTHER families' markers that may remain
        # from previous turns (e.g., xAI `<whisper>` in a session that has
        # since switched to Gemini). Use STRICT regex (fixed vocabulary only,
        # no catch-all) so that user-typed lowercase brackets such as
        # `[done]` or `[foo bar]` are NOT false-positive stripped when the
        # active engine would have left them alone.
        result = result.gsub(XAI_INLINE_RE, "") unless fam == "xai"
        result = result.gsub(XAI_WRAP_RE, "") unless fam == "xai"
        result = result.gsub(XAI_MALFORMED_CLOSING_RE, "") unless fam == "xai"
        result = result.gsub(XAI_MALFORMED_SQUARE_WRAP_RE, "") unless fam == "xai"
        result = result.gsub(ELEVENLABS_INLINE_STRICT_RE, "") unless fam == "elevenlabs-v3"
        result = result.gsub(GEMINI_INLINE_STRICT_RE, "") unless fam == "gemini"
        result.gsub(/[ \t]{2,}/, " ").gsub(/\s+([,.!?;:])/, '\1')
      end

      def tag_aware?(provider)
        DISPLAY_SANITIZE.key?(family_for(provider))
      end
    end
  end
end
