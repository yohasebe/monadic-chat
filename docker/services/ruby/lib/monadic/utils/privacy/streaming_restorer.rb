# frozen_string_literal: true

module Monadic
  module Utils
    module Privacy
      # Buffers streaming chunks so a placeholder split across chunk boundaries
      # ("Dear <<PERSO" + "N_1>>, ...") is restored correctly rather than
      # leaking partial tokens to the UI.
      #
      # Strategy: keep the trailing MAX_PARTIAL_LENGTH chars in reserve until
      # the next chunk arrives. On flush, restore everything.
      class StreamingRestorer
        PLACEHOLDER_RE = /<<[A-Z_]+_\d+>>/
        MAX_PARTIAL_LENGTH = 64

        def initialize(pipeline)
          @pipeline = pipeline
          @buffer = String.new
        end

        # @param chunk [String]
        # @return [String] restored text safe to flush to the UI now
        def feed(chunk)
          @buffer << chunk
          return '' if @buffer.length <= MAX_PARTIAL_LENGTH

          safe_len = @buffer.length - MAX_PARTIAL_LENGTH
          # Avoid splitting in the middle of a "<<...>>" — if the safe slice
          # would end inside an open placeholder, retract to before "<<".
          safe_len = retract_if_open(@buffer, safe_len)
          return '' if safe_len <= 0

          safe = @buffer[0...safe_len]
          @buffer = @buffer[safe_len..] || String.new
          @pipeline.after_receive_from_llm(safe).text
        end

        # End of stream: restore everything still in the buffer.
        def flush
          return '' if @buffer.empty?
          out = @pipeline.after_receive_from_llm(@buffer).text
          @buffer = String.new
          out
        end

        private

        # If the safe-slice boundary lies inside an unclosed "<<...>>",
        # retract to just before the "<<".
        def retract_if_open(buf, boundary)
          last_open = buf.rindex('<<', boundary)
          return boundary unless last_open
          last_close = buf.rindex('>>', boundary)
          return boundary if last_close && last_close > last_open
          last_open
        end
      end
    end
  end
end
