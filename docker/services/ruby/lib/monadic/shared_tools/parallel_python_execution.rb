# frozen_string_literal: true

require 'json'
require 'timeout'

module MonadicSharedTools
  module ParallelPythonExecution
    include MonadicHelper

    MAX_PARALLEL_CODE_TASKS = 5
    DEFAULT_CODE_TIMEOUT = 60
    MAX_CODE_TIMEOUT = 180

    # Execute multiple independent Python code snippets in parallel.
    # Each snippet runs via the existing run_code method in its own thread.
    # Results are collected and returned together.
    #
    # @param tasks [Array<Hash>] Array of {id:, code:, description:?} objects (max 5)
    # @param timeout [Integer, nil] Per-task timeout in seconds (default: 60, max: 180)
    # @param session [Hash, nil] Injected by process_functions
    # @return [String] Formatted result for the model to present
    def parallel_run_code(tasks:, timeout: nil, session: nil)
      # --- Input validation ---
      unless tasks.is_a?(Array) && !tasks.empty?
        return "ERROR: tasks parameter is required and must be a non-empty array"
      end

      if tasks.length > MAX_PARALLEL_CODE_TASKS
        return "ERROR: Maximum #{MAX_PARALLEL_CODE_TASKS} parallel code tasks allowed, got #{tasks.length}"
      end

      tasks.each_with_index do |task, i|
        unless task.is_a?(Hash) && task["id"] && task["code"]
          return "ERROR: Task at index #{i} must have 'id' and 'code' fields"
        end
      end

      # --- Configuration ---
      timeout_val = [[(timeout || DEFAULT_CODE_TIMEOUT), DEFAULT_CODE_TIMEOUT].max, MAX_CODE_TIMEOUT].min
      parent_ws_session_id = Thread.current[:websocket_session_id]

      # --- Initial progress ---
      task_labels = tasks.map { |t| t["description"] || t["id"] }
      send_code_progress(
        "Executing #{tasks.length} Python tasks in parallel...",
        parent_ws_session_id, task_labels, 0
      )

      # --- Parallel execution ---
      results = []
      results_mutex = Mutex.new
      completed_count = 0
      completed_mutex = Mutex.new

      threads = tasks.map do |task|
        Thread.new(task) do |t|
          Thread.current.report_on_exception = false
          begin
            output = Timeout.timeout(timeout_val) do
              run_code(code: t["code"], command: "python", extension: "py")
            end

            results_mutex.synchronize do
              results << { "id" => t["id"], "success" => true, "output" => output }
            end
          rescue Timeout::Error
            results_mutex.synchronize do
              results << { "id" => t["id"], "success" => false, "error" => "Timed out after #{timeout_val}s" }
            end
          rescue => e
            results_mutex.synchronize do
              results << { "id" => t["id"], "success" => false, "error" => e.message }
            end
          ensure
            completed_mutex.synchronize do
              completed_count += 1
              send_code_progress(
                "Parallel code execution: #{completed_count}/#{tasks.length} completed",
                parent_ws_session_id, task_labels, completed_count
              )
            end
          end
        end
      end

      # Wait for all threads (with buffer beyond per-task timeout)
      threads.each { |t| t.join(timeout_val + 10) }

      # Kill any hung threads
      threads.each { |t| t.kill if t.alive? }

      # Force-stop further tool calls after results are returned.
      session[:call_depth_per_turn] = 9999 if session

      # --- Build result ---
      succeeded = results.count { |r| r["success"] }
      results_json = JSON.pretty_generate({
        "success" => true,
        "total_tasks" => tasks.length,
        "succeeded" => succeeded,
        "results" => results
      })

      <<~RESULT
        PARALLEL CODE EXECUTION COMPLETED. #{succeeded}/#{tasks.length} succeeded.

        Results:
        #{results_json}

        Present all results to the user. Show any generated images using <div class="generated_image"><img src="/data/FILENAME" /></div>.
        Do NOT call any more tools.
      RESULT
    end

    private

    # Send progress update to the WebSocket for temp card display.
    def send_code_progress(message, ws_session_id, task_labels, completed)
      return unless defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_progress_fragment)

      fragment = {
        "type" => "wait",
        "content" => message,
        "source" => "ParallelCodeExecution",
        "step_progress" => {
          "mode" => "parallel",
          "current" => completed,
          "total" => task_labels.length,
          "steps" => task_labels
        }
      }
      WebSocketHelper.send_progress_fragment(fragment, ws_session_id)
    rescue StandardError
      # Progress reporting is best-effort; don't fail the execution
    end
  end
end
