# frozen_string_literal: true

# Rubric Scorer
#
# Scores a generated artifact against the task's `rubric_items` spec
# coverage criteria.
#
# Step 2a (this commit): Skeleton with the scoring shape defined. The
# automated checks for each rubric item are intentionally left for
# Step 2b; some items are easy to automate (regex against the file
# contents), some require Selenium (already covered by functional
# scorer), and some require human review (e.g., "clean visual layout").
#
# Strategy for Step 2b:
# - Each rubric item gets a check_strategy field added: :auto_regex,
#   :auto_dom, :selenium, or :human
# - The scorer dispatches based on strategy
# - :human strategy emits a checklist file the runner can fill in
#   after the run

module AutoForgeBenchmark
  class RubricScorer
    def initialize(task)
      @task = task
      @items = task['rubric_items'] || []
    end

    # @param output_file [String] absolute path to the generated artifact
    # @return [Hash] {
    #   coverage: Float (0.0–1.0),
    #   total: Integer,
    #   passed: Integer,
    #   per_item: [{ id, type, score }],
    #   pending_human_review: [item_ids]
    # }
    def score(output_file)
      return empty_result if @items.empty?

      results = @items.map { |item| score_item(item, output_file) }

      total_points = results.sum { |r| r[:max_score] }
      earned       = results.sum { |r| r[:score] }
      coverage     = total_points.zero? ? 0.0 : (earned.to_f / total_points)

      {
        coverage: coverage.round(4),
        total: total_points,
        passed: earned,
        per_item: results,
        pending_human_review: results.select { |r| r[:pending_human] }.map { |r| r[:id] }
      }
    end

    private

    def empty_result
      { coverage: 0.0, total: 0, passed: 0, per_item: [], pending_human_review: [] }
    end

    def score_item(item, _output_file)
      max_score = item['type'] == 'graded' ? item['scale'].to_s.split('-').last.to_i : 1

      # TODO (Step 2b): dispatch by check_strategy. For now, mark all
      # items as pending_human so the result.json carries the contract
      # shape without producing fake numbers.
      {
        id: item['id'],
        description: item['description'],
        type: item['type'],
        max_score: max_score,
        score: 0,
        pending_human: true,
        notes: 'pending: rubric automation deferred to Step 2b'
      }
    end
  end
end
