# frozen_string_literal: true

module Monadic
  module Utils
    # Takes the Expressive Speech directive off a reply (see
    # `docs_dev/expressive_speech_instruction_mode.md`): the LLM begins the
    # reply with a `<<TTS:...>>` block, and the rest of the text is the
    # reply.
    #
    # All entry points are total: on a missing block they return the
    # original text with `nil` for instructions, never raising.
    module TtsInstructionExtractor
      module_function

      # The directive block. Matches at the absolute start
      # of the text (leading whitespace allowed) with a non-greedy body so
      # the first `>>` closes the block. Multi-line enabled for the `.`.
      SENTINEL_RE = /\A\s*<<TTS:(.*?)>>\s*/m

      # Cheap prefix check used by the streaming state machine to decide
      # whether a growing buffer is "possibly a sentinel start". Matches if
      # the buffer could still grow into a sentinel (prefix of `<<TTS:`).
      SENTINEL_PARTIAL_PREFIX_RE = /\A\s*(?:<(?:<(?:T(?:T(?:S:?)?)?)?)?)?\z/

      # -- Extractors --------------------------------------------------------

      # Returns [message_text, instructions_or_nil]: the reply without its
      # leading `<<TTS:...>>` block, and the block's text.
      def extract(text)
        return [text, nil] if text.nil? || text.to_s.empty?
        m = text.match(SENTINEL_RE)
        return [text, nil] unless m
        instructions = m[1].to_s.strip
        instructions = nil if instructions.empty?
        cleaned = text.sub(SENTINEL_RE, '')
        [cleaned, instructions]
      end

      # Strip a leading `<<TTS:...>>` block from a reply being stored, so
      # the next-turn LLM context starts from the user-facing reply. No-op
      # when the block is absent.
      def strip_from_history(text)
        return text unless text.is_a?(String)

        text.sub(SENTINEL_RE, '')
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

    end
  end
end
