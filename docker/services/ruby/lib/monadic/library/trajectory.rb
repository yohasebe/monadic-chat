# frozen_string_literal: true

module Monadic
  module Library
    # Build sliding-window text snapshots over a sequence of turns, used
    # as input to Level T (trajectory) embeddings.
    #
    # For each turn k, the snapshot covers turns [k-W+1 .. k] (clipped to
    # 0). Concatenated text is the embedding input. The resulting vector
    # represents "discourse state at this point" — adjacent vectors land
    # near each other when the conversation is on a stable topic, and far
    # apart when the discourse pivots.
    module Trajectory
      module_function

      DEFAULT_WINDOW_SIZE = 3

      # @param turns [Array<Hash>] output of TurnSegmenter.segment
      # @param window_size [Integer] number of preceding turns to include
      #   (inclusive of the anchor turn). Must be >= 1.
      # @return [Array<Hash>] one window descriptor per turn:
      #   {
      #     turn_idx:       Integer (anchor turn),
      #     start_turn_idx: Integer (first turn included),
      #     end_turn_idx:   Integer (== turn_idx),
      #     window_size:    Integer (actual turn count, may be < W near start),
      #     text:           String (concatenated turn texts, "\n\n" separated)
      #   }
      def build_windows(turns, window_size: DEFAULT_WINDOW_SIZE)
        raise ArgumentError, 'window_size must be >= 1' if window_size < 1
        return [] if turns.nil? || turns.empty?

        turns.each_with_index.map do |_, idx|
          start_idx = [idx - window_size + 1, 0].max
          slice = turns[start_idx..idx]
          {
            turn_idx: idx,
            start_turn_idx: start_idx,
            end_turn_idx: idx,
            window_size: slice.size,
            text: slice.map { |t| t[:text].to_s }.join("\n\n").strip
          }
        end
      end
    end
  end
end
