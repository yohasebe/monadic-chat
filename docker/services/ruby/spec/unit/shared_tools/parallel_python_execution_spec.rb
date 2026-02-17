# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/parallel_python_execution"

# Mock MonadicHelper for testing
module MonadicHelper
end unless defined?(MonadicHelper)

# Mock CONFIG for testing
unless defined?(CONFIG)
  CONFIG = {}.freeze
end

# Mock WebSocketHelper for testing
module WebSocketHelper
  def self.send_progress_fragment(fragment, session_id = nil)
    # no-op in tests
  end
end unless defined?(WebSocketHelper)

RSpec.describe "MonadicSharedTools::ParallelPythonExecution" do
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::ParallelPythonExecution

      # Stub run_code to simulate Python execution
      def run_code(code:, command:, extension:)
        '{"success": true, "output": "mock output"}'
      end

      # Make private methods accessible for testing
      public :send_code_progress
    end
  end

  let(:app) { test_class.new }

  let(:valid_tasks) do
    [
      { "id" => "stats", "code" => "print('statistics')", "description" => "Compute statistics" },
      { "id" => "chart", "code" => "print('chart')", "description" => "Generate chart" }
    ]
  end

  let(:session) do
    { parameters: { "model" => "gpt-4.1" } }
  end

  describe "#parallel_run_code" do
    context "input validation" do
      it "returns error for nil tasks" do
        result = app.parallel_run_code(tasks: nil, session: session)
        expect(result).to include("ERROR")
        expect(result).to include("non-empty array")
      end

      it "returns error for empty tasks" do
        result = app.parallel_run_code(tasks: [], session: session)
        expect(result).to include("ERROR")
        expect(result).to include("non-empty array")
      end

      it "returns error for non-array tasks" do
        result = app.parallel_run_code(tasks: "not an array", session: session)
        expect(result).to include("ERROR")
      end

      it "returns error when tasks exceed MAX_PARALLEL_CODE_TASKS" do
        tasks = 6.times.map { |i| { "id" => "t#{i}", "code" => "print(#{i})" } }
        result = app.parallel_run_code(tasks: tasks, session: session)
        expect(result).to include("ERROR")
        expect(result).to include("Maximum 5")
      end

      it "returns error for task missing 'id'" do
        tasks = [{ "code" => "print(1)" }]
        result = app.parallel_run_code(tasks: tasks, session: session)
        expect(result).to include("ERROR")
        expect(result).to include("'id' and 'code'")
      end

      it "returns error for task missing 'code'" do
        tasks = [{ "id" => "t1" }]
        result = app.parallel_run_code(tasks: tasks, session: session)
        expect(result).to include("ERROR")
        expect(result).to include("'id' and 'code'")
      end

      it "returns error for non-hash task" do
        tasks = ["not a hash"]
        result = app.parallel_run_code(tasks: tasks, session: session)
        expect(result).to include("ERROR")
      end
    end

    context "successful execution" do
      it "returns PARALLEL CODE EXECUTION COMPLETED message" do
        result = app.parallel_run_code(tasks: valid_tasks, session: session)
        expect(result).to include("PARALLEL CODE EXECUTION COMPLETED")
      end

      it "returns correct success count" do
        result = app.parallel_run_code(tasks: valid_tasks, session: session)
        expect(result).to include("2/2 succeeded")
      end

      it "includes task IDs in results" do
        result = app.parallel_run_code(tasks: valid_tasks, session: session)
        expect(result).to include("stats")
        expect(result).to include("chart")
      end

      it "includes instruction to present results" do
        result = app.parallel_run_code(tasks: valid_tasks, session: session)
        expect(result).to include("Do NOT call any more tools")
      end

      it "calls run_code for each task" do
        expect(app).to receive(:run_code).exactly(2).times.and_return('{"success": true}')
        app.parallel_run_code(tasks: valid_tasks, session: session)
      end

      it "passes python command and py extension to run_code" do
        expect(app).to receive(:run_code)
          .with(code: "print('statistics')", command: "python", extension: "py")
          .and_return('{"success": true}')
        expect(app).to receive(:run_code)
          .with(code: "print('chart')", command: "python", extension: "py")
          .and_return('{"success": true}')
        app.parallel_run_code(tasks: valid_tasks, session: session)
      end
    end

    context "force-stop via call_depth_per_turn" do
      it "sets call_depth_per_turn to 9999 after completion" do
        session_with_depth = { parameters: { "model" => "gpt-4.1" }, call_depth_per_turn: 3 }
        app.parallel_run_code(tasks: valid_tasks, session: session_with_depth)
        expect(session_with_depth[:call_depth_per_turn]).to eq(9999)
      end

      it "does not raise when session is nil" do
        expect {
          app.parallel_run_code(tasks: valid_tasks, session: nil)
        }.not_to raise_error
      end
    end

    context "partial failure" do
      it "reports partial success when some tasks fail" do
        call_count = 0
        allow(app).to receive(:run_code) do
          call_count += 1
          if call_count == 1
            '{"success": true, "output": "ok"}'
          else
            raise "Python error"
          end
        end

        result = app.parallel_run_code(tasks: valid_tasks, session: session)
        expect(result).to include("PARALLEL CODE EXECUTION COMPLETED")
        expect(result).to include("1/2 succeeded")
      end
    end

    context "timeout handling" do
      it "records timeout error for tasks that exceed timeout" do
        allow(app).to receive(:run_code) do
          raise Timeout::Error, "execution expired"
        end

        result = app.parallel_run_code(tasks: valid_tasks, timeout: 60, session: session)
        expect(result).to include("PARALLEL CODE EXECUTION COMPLETED")
        expect(result).to include("0/2 succeeded")
        expect(result).to include("Timed out")
      end

      it "clamps timeout to MAX_CODE_TIMEOUT" do
        tasks = [{ "id" => "t1", "code" => "print(1)" }]
        result = app.parallel_run_code(tasks: tasks, timeout: 999, session: session)
        expect(result).to include("PARALLEL CODE EXECUTION COMPLETED")
      end
    end

    context "progress reporting" do
      it "sends initial progress" do
        expect(WebSocketHelper).to receive(:send_progress_fragment).at_least(:once)
        app.parallel_run_code(tasks: valid_tasks, session: session)
      end

      it "uses description as step label when available" do
        expect(WebSocketHelper).to receive(:send_progress_fragment).at_least(:once) do |fragment, _|
          steps = fragment.dig("step_progress", "steps")
          expect(steps).to include("Compute statistics") if steps
        end
        app.parallel_run_code(tasks: valid_tasks, session: session)
      end

      it "falls back to id when description is missing" do
        tasks = [
          { "id" => "task_a", "code" => "print(1)" },
          { "id" => "task_b", "code" => "print(2)" }
        ]
        expect(WebSocketHelper).to receive(:send_progress_fragment).at_least(:once) do |fragment, _|
          steps = fragment.dig("step_progress", "steps")
          expect(steps).to include("task_a") if steps
        end
        app.parallel_run_code(tasks: tasks, session: session)
      end
    end
  end

  describe "#send_code_progress" do
    it "sends fragment with correct structure" do
      labels = ["Task A", "Task B"]
      expect(WebSocketHelper).to receive(:send_progress_fragment) do |fragment, _ws_id|
        expect(fragment["type"]).to eq("wait")
        expect(fragment["source"]).to eq("ParallelCodeExecution")
        sp = fragment["step_progress"]
        expect(sp["mode"]).to eq("parallel")
        expect(sp["current"]).to eq(1)
        expect(sp["total"]).to eq(2)
        expect(sp["steps"]).to eq(["Task A", "Task B"])
      end

      app.send_code_progress("test message", nil, labels, 1)
    end

    it "does not raise if WebSocketHelper fails" do
      allow(WebSocketHelper).to receive(:send_progress_fragment).and_raise(StandardError)
      expect {
        app.send_code_progress("msg", nil, ["a"], 0)
      }.not_to raise_error
    end
  end

  describe "constants" do
    it "defines MAX_PARALLEL_CODE_TASKS as 5" do
      expect(MonadicSharedTools::ParallelPythonExecution::MAX_PARALLEL_CODE_TASKS).to eq(5)
    end

    it "defines DEFAULT_CODE_TIMEOUT as 60" do
      expect(MonadicSharedTools::ParallelPythonExecution::DEFAULT_CODE_TIMEOUT).to eq(60)
    end

    it "defines MAX_CODE_TIMEOUT as 180" do
      expect(MonadicSharedTools::ParallelPythonExecution::MAX_CODE_TIMEOUT).to eq(180)
    end
  end
end
