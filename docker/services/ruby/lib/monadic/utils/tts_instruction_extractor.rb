# frozen_string_literal: true

require 'json'

module Monadic
  module Utils
    # Extractors for Expressive Speech instruction-mode payloads.
    #
    # Two encodings coexist (see `docs_dev/expressive_speech_instruction_mode.md`):
    #
    #   * Monadic apps   → LLM emits JSON with a sibling `tts_instructions` key
    #                      alongside `message` and `context`.
    #   * Non-Monadic    → LLM prefixes the response with a `<<TTS:...>>`
    #                      sentinel block; the rest of the text is the reply.
    #
    # This module provides nil-safe parsers for both encodings plus a helper
    # to scrub `tts_instructions` from stored history so that replayed context
    # does not waste tokens on per-turn ephemeral TTS metadata.
    #
    # All entry points are total: on parse failure or missing fields they
    # return the original text with `nil` for instructions, never raising.
    module TtsInstructionExtractor
      module_function

      # Sentinel for the non-Monadic encoding. Matches at the absolute start
      # of the text (leading whitespace allowed) with a non-greedy body so
      # the first `>>` closes the block. Multi-line enabled for the `.`.
      SENTINEL_RE = /\A\s*<<TTS:(.*?)>>\s*/m

      # Cheap prefix check used by the streaming state machine to decide
      # whether a growing buffer is "possibly a sentinel start". Matches if
      # the buffer could still grow into a sentinel (prefix of `<<TTS:`).
      SENTINEL_PARTIAL_PREFIX_RE = /\A\s*(?:<(?:<(?:T(?:T(?:S:?)?)?)?)?)?\z/

      # -- Extractors --------------------------------------------------------

      # Unified entry point. Dispatches to the right parser by app state.
      # Returns [message_text, instructions_or_nil]. Never raises.
      def extract(text, app_is_monadic:)
        app_is_monadic ? extract_json(text) : extract_sentinel(text)
      end

      # Non-Monadic encoding: peel the leading `<<TTS:...>>` block.
      def extract_sentinel(text)
        return [text, nil] if text.nil? || text.to_s.empty?
        m = text.match(SENTINEL_RE)
        return [text, nil] unless m
        instructions = m[1].to_s.strip
        instructions = nil if instructions.empty?
        cleaned = text.sub(SENTINEL_RE, '')
        [cleaned, instructions]
      end

      # Monadic encoding: parse the JSON, pull `message` and `tts_instructions`.
      # The full JSON text is returned as-is when parsing fails so downstream
      # display code can still try the normal Monadic-mode render path.
      def extract_json(text)
        return [text, nil] if text.nil? || text.to_s.empty?
        parsed = safe_parse_json(text)
        return [text, nil] unless parsed.is_a?(Hash)
        return [text, nil] unless parsed["message"].is_a?(String)
        instructions = parsed["tts_instructions"]
        instructions = nil unless instructions.is_a?(String) && !instructions.empty?
        # Note: we return ONLY the message text (not a reshaped JSON). The
        # caller that needs the full structure for display should still work
        # off the original `text`; display-side suppression (§8.2) keeps the
        # `tts_instructions` field out of the rendered UI.
        [parsed["message"], instructions]
      end

      # Strip `tts_instructions` from a stored-history JSON string so that
      # next-turn LLM context does not carry per-turn ephemeral metadata.
      # Preserves everything else (including `context`). Returns the input
      # unchanged when it is not a valid `{ ...tts_instructions... }` object.
      def strip_from_history_json(json_text)
        return json_text unless json_text.is_a?(String)
        parsed = safe_parse_json(json_text)
        return json_text unless parsed.is_a?(Hash) && parsed.key?("tts_instructions")
        parsed.delete("tts_instructions")
        JSON.generate(parsed)
      end

      # -- Streaming helpers -------------------------------------------------

      # State-machine-friendly check: "could this buffer grow into a valid
      # sentinel start?". Used by the streaming stripper to decide whether
      # to keep buffering or forward the accumulated text (no sentinel).
      def possibly_sentinel_start?(buffer)
        buffer.to_s.match?(SENTINEL_PARTIAL_PREFIX_RE) || buffer.to_s.match?(/\A\s*<<TTS:/)
      end

      # Try to consume a complete sentinel from the buffer. Returns
      # [instructions, remainder_after_sentinel] when a complete `<<TTS:...>>`
      # is present at the start; returns nil otherwise (still accumulating).
      def try_consume_sentinel(buffer)
        return nil if buffer.to_s.empty?
        m = buffer.match(SENTINEL_RE)
        return nil unless m
        instructions = m[1].to_s.strip
        instructions = nil if instructions.empty?
        remainder = buffer.sub(SENTINEL_RE, '')
        [instructions, remainder]
      end

      # -- Internal ---------------------------------------------------------

      def safe_parse_json(text)
        JSON.parse(text.to_s)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
