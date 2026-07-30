# frozen_string_literal: true

module SttNoiseBenchmark
  # Word Error Rate between a reference transcript and a hypothesis.
  #
  # WER is the word-level Levenshtein distance divided by the reference word
  # count. It is the standard metric, but on its own it hides the distinction
  # that matters most for this project: an engine that *drops* words under
  # noise and one that *invents* fluent replacements can score similarly while
  # being worlds apart for language teaching. `analyze` therefore also reports
  # the edit breakdown, so a run can tell "omitted" from "fabricated".
  module Wer
    module_function

    # Lowercase, strip punctuation, collapse whitespace.
    def normalize(text)
      text.to_s
          .downcase
          .gsub(/[^\p{Alnum}\p{Space}']/, ' ')
          .split
    end

    # @return [Float] WER in 0.0..n (can exceed 1.0 when the hypothesis is
    #   longer than the reference, e.g. fabricated content)
    def rate(reference, hypothesis)
      analyze(reference, hypothesis)[:wer]
    end

    # @return [Hash] :wer, :substitutions, :deletions, :insertions,
    #   :reference_words, :hypothesis_words
    def analyze(reference, hypothesis)
      ref = normalize(reference)
      hyp = normalize(hypothesis)

      return empty_result(ref, hyp) if ref.empty?

      ops = edit_ops(ref, hyp)
      {
        wer: (ops[:sub] + ops[:del] + ops[:ins]).to_f / ref.length,
        substitutions: ops[:sub],
        deletions: ops[:del],
        insertions: ops[:ins],
        reference_words: ref.length,
        hypothesis_words: hyp.length
      }
    end

    def empty_result(ref, hyp)
      {
        wer: hyp.empty? ? 0.0 : Float::INFINITY,
        substitutions: 0,
        deletions: 0,
        insertions: hyp.length,
        reference_words: ref.length,
        hypothesis_words: hyp.length
      }
    end
    private_class_method :empty_result

    # Levenshtein over word arrays, carrying the operation counts along the
    # optimal path so the caller can distinguish omission from fabrication.
    def edit_ops(ref, hyp)
      # Each cell holds [cost, subs, dels, ins].
      prev = Array.new(hyp.length + 1) { |j| [j, 0, 0, j] }

      ref.each_with_index do |ref_word, i|
        current = Array.new(hyp.length + 1)
        current[0] = [i + 1, 0, i + 1, 0]

        hyp.each_with_index do |hyp_word, j|
          if ref_word == hyp_word
            current[j + 1] = prev[j].dup
            next
          end

          sub = prev[j]
          del = prev[j + 1]
          ins = current[j]

          best = [
            [sub[0] + 1, sub[1] + 1, sub[2], sub[3]],
            [del[0] + 1, del[1], del[2] + 1, del[3]],
            [ins[0] + 1, ins[1], ins[2], ins[3] + 1]
          ].min_by { |cell| cell[0] }

          current[j + 1] = best
        end

        prev = current
      end

      final = prev[hyp.length]
      { sub: final[1], del: final[2], ins: final[3] }
    end
    private_class_method :edit_ops
  end
end
