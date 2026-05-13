# frozen_string_literal: true

# Functional Scorer
#
# Executes the task's `smoke_test` operations against a generated
# artifact via Selenium and returns a boolean pass/fail.
#
# Step 2a (this commit): Skeleton only. The dispatch table is sketched
# but each action handler is a TODO for Step 2b.
#
# Step 2b: Wire up to the existing Selenium container (Monadic Chat
# already runs one for AutoForge debugging — see
# `apps/auto_forge/auto_forge_debugger.rb` for the pattern).

module AutoForgeBenchmark
  class FunctionalScorer
    def initialize(task)
      @task = task
      @steps = task['smoke_test'] || []
    end

    # @param output_file [String] absolute path to the generated artifact
    # @return [Hash] { pass: bool, failed_step: idx or nil, error: msg or nil }
    def score(output_file)
      return { pass: false, failed_step: nil, error: 'no smoke_test defined' } if @steps.empty?

      driver = build_driver
      begin
        @steps.each_with_index do |step, idx|
          run_step(driver, step, output_file)
        rescue StandardError => e
          return { pass: false, failed_step: idx, error: e.message }
        end
        { pass: true, failed_step: nil, error: nil }
      ensure
        driver&.quit
      end
    end

    private

    def build_driver
      # TODO (Step 2b): Connect to the Selenium container Monadic Chat
      # already manages. See `apps/auto_forge/auto_forge_debugger.rb` —
      # it has the same pattern. Likely something like:
      #
      #   Selenium::WebDriver.for(:remote,
      #     url: ENV.fetch('SELENIUM_URL', 'http://localhost:4444/wd/hub'),
      #     options: Selenium::WebDriver::Chrome::Options.new(args: %w[--headless --no-sandbox])
      #   )
      nil
    end

    # Dispatcher for the smoke_test actions defined in the task YAML.
    # The set of actions is intentionally narrow — extend only when a
    # new task demands a new action, not preemptively.
    def run_step(driver, step, output_file)
      case step['action']
      when 'open'
        target = step['target'].to_s.sub('{{output_file}}', output_file)
        # driver.navigate.to("file://#{target}")
        raise NotImplementedError, "TODO (Step 2b): open #{target}"
      when 'click_text'
        # element matching visible text == step['target']
        raise NotImplementedError, "TODO (Step 2b): click_text #{step['target']}"
      when 'type_in_textarea', 'type_in_input'
        raise NotImplementedError, "TODO (Step 2b): #{step['action']}"
      when 'press_key'
        raise NotImplementedError, "TODO (Step 2b): press_key #{step['key']}"
      when 'wait'
        # sleep step['duration_ms'].to_i / 1000.0
        raise NotImplementedError, "TODO (Step 2b): wait #{step['duration_ms']}ms"
      when 'assert_display_contains', 'assert_textarea_contains', 'assert_preview_contains_html',
           'assert_message_visible', 'assert_message_area_changed', 'assert_display_empty'
        raise NotImplementedError, "TODO (Step 2b): assertion #{step['action']}"
      when 'click_toolbar_button', 'click_sidebar_entry'
        raise NotImplementedError, "TODO (Step 2b): #{step['action']}"
      when 'reload_page'
        raise NotImplementedError, 'TODO (Step 2b): reload_page'
      else
        raise "Unknown smoke_test action: #{step['action']}"
      end
    end
  end
end
