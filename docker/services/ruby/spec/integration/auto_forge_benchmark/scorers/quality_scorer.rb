# frozen_string_literal: true

# Quality Scorer
#
# Measures generated code quality on a 0-10 scale combining:
# - Lint pass (40%): syntactic correctness, basic style
# - Readability (30%): structure, naming, comments
# - Adherence to "single-file" constraint and reasonable LOC (30%)
#
# Step 2a (this commit): Skeleton only. The actual checks are TODO for
# Step 2b. The intent is to be conservative — measure things we can
# automate (lint), defer subjective judgments to human review (a
# scoring sheet emitted alongside the artifact).

module AutoForgeBenchmark
  class QualityScorer
    LINT_WEIGHT        = 0.4
    READABILITY_WEIGHT = 0.3
    STRUCTURE_WEIGHT   = 0.3

    def initialize(task)
      @task = task
    end

    # @param output_file [String] absolute path to the generated artifact
    # @return [Hash] {
    #   total: Float (0-10),
    #   lint: { score, max, details },
    #   readability: { score, max, pending_human },
    #   structure: { score, max, details },
    # }
    def score(output_file)
      lint        = score_lint(output_file)
      readability = score_readability(output_file)
      structure   = score_structure(output_file)

      total = (lint[:normalized] * LINT_WEIGHT +
               readability[:normalized] * READABILITY_WEIGHT +
               structure[:normalized] * STRUCTURE_WEIGHT) * 10

      {
        total: total.round(2),
        lint: lint,
        readability: readability,
        structure: structure
      }
    end

    private

    def score_lint(_output_file)
      # TODO (Step 2b):
      # - HTML files: run a basic HTML5 validator (or html5_validator gem)
      # - JS extracted from <script>: run jshint via Selenium container or local
      # - CSS extracted: run stylelint or a basic regex check
      { normalized: 0.0, pending: true, notes: 'pending: lint automation deferred to Step 2b' }
    end

    def score_readability(_output_file)
      # Subjective — defer to human review. Produce a checklist the
      # runner emits for the human to fill in after the run.
      # Suggested items:
      # - Are function/class names meaningful?
      # - Is the code organized into recognizable sections?
      # - Are non-obvious bits commented?
      # - Is there any dead code or commented-out blocks?
      { normalized: 0.0, pending_human: true, notes: 'pending: requires human review' }
    end

    def score_structure(output_file)
      # Automatable checks:
      # - LOC vs target (penalize 2× over target)
      # - Number of separate files (single-file constraint)
      # - Presence of <script> and <style> tags
      return { normalized: 0.0, pending: true, notes: 'no output file' } unless output_file && File.exist?(output_file)

      lines = File.read(output_file).lines.count
      target = @task['loc_target'].to_i
      target = 200 if target.zero?

      ratio = target.zero? ? 0 : (lines.to_f / target)
      structure_score =
        if ratio.between?(0.5, 2.0)
          1.0
        elsif ratio.between?(0.3, 3.0)
          0.5
        else
          0.0
        end

      {
        normalized: structure_score,
        actual_loc: lines,
        target_loc: target,
        ratio: ratio.round(2),
        notes: 'LOC heuristic only; broader structural checks deferred to Step 2b'
      }
    end
  end
end
