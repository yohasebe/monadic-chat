# frozen_string_literal: true

require 'json'
require 'timeout'

module MonadicSharedTools
  module ParallelDispatch
    include MonadicHelper

    MAX_PARALLEL_TASKS = 5
    DEFAULT_TIMEOUT = 120
    MAX_TIMEOUT = 300

    # Provider configuration for direct API calls (no tools in request body).
    # Grouped by API format family so sub-agents never trigger tool loops.
    PROVIDER_CONFIG = {
      "ClaudeHelper"     => { type: :anthropic,      websearch_strategy: :native_tool,
                               endpoint: "https://api.anthropic.com/v1/messages",
                               api_key_env: "ANTHROPIC_API_KEY" },
      "GeminiHelper"     => { type: :gemini,          websearch_strategy: :grounding,
                               endpoint: "https://generativelanguage.googleapis.com/v1beta",
                               api_key_env: "GEMINI_API_KEY" },
      "CohereHelper"     => { type: :cohere,          websearch_strategy: :tavily,
                               endpoint: "https://api.cohere.ai/v2/chat",
                               api_key_env: "COHERE_API_KEY" },
      "DeepSeekHelper"   => { type: :openai_compat,   websearch_strategy: :tavily,
                               endpoint: "https://api.deepseek.com/chat/completions",
                               api_key_env: "DEEPSEEK_API_KEY" },
      "GrokHelper"       => { type: :openai_compat,   websearch_strategy: :responses_api,
                               endpoint: "https://api.x.ai/v1/chat/completions",
                               responses_endpoint: "https://api.x.ai/v1/responses",
                               api_key_env: "XAI_API_KEY" },
      "MistralHelper"    => { type: :openai_compat,   websearch_strategy: :tavily,
                               endpoint: "https://api.mistral.ai/v1/chat/completions",
                               api_key_env: "MISTRAL_API_KEY" },
      "PerplexityHelper" => { type: :openai_compat,   websearch_strategy: :native,
                               endpoint: "https://api.perplexity.ai/chat/completions",
                               api_key_env: "PERPLEXITY_API_KEY" },
      "OpenAIHelper"     => { type: :openai_compat,   websearch_strategy: :responses_api,
                               endpoint: "https://api.openai.com/v1/chat/completions",
                               responses_endpoint: "https://api.openai.com/v1/responses",
                               api_key_env: "OPENAI_API_KEY" }
    }.freeze

    # Dispatch multiple independent sub-tasks to run in parallel.
    # Each sub-task runs as a separate text-only API call (no tools).
    # Results are collected and returned for the orchestrator to synthesize.
    #
    # @param tasks [Array<Hash>] Array of {id:, prompt:, context:?} objects (max 5)
    # @param timeout [Integer, nil] Per-task timeout in seconds (default: 120, max: 300)
    # @param session [Hash, nil] Injected by process_functions
    # @return [String] Formatted result for the model to synthesize
    def dispatch_parallel_tasks(tasks:, timeout: nil, websearch: nil, session: nil)
      # --- Input validation ---
      unless tasks.is_a?(Array) && !tasks.empty?
        return "ERROR: tasks parameter is required and must be a non-empty array"
      end

      if tasks.length > MAX_PARALLEL_TASKS
        return "ERROR: Maximum #{MAX_PARALLEL_TASKS} parallel tasks allowed, got #{tasks.length}"
      end

      tasks.each_with_index do |task, i|
        unless task.is_a?(Hash) && task["id"] && task["prompt"]
          return "ERROR: Task at index #{i} must have 'id' and 'prompt' fields"
        end
      end

      # --- Configuration ---
      model = session&.dig(:parameters, "model") || "gpt-4.1"
      timeout_val = [[(timeout || DEFAULT_TIMEOUT), DEFAULT_TIMEOUT].max, MAX_TIMEOUT].min

      # Resolve websearch: explicit param > session setting > false
      ws_enabled = if !websearch.nil?
                     websearch == true || websearch == "true"
                   else
                     ws_val = session&.dig(:parameters, "websearch")
                     ws_val == true || ws_val == "true"
                   end
      parent_ws_session_id = Thread.current[:websocket_session_id]
      provider_cfg = resolve_provider_config

      # --- Initial progress ---
      send_parallel_progress(
        "Dispatching #{tasks.length} parallel sub-agents...",
        parent_ws_session_id, tasks, 0
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
            prompt = if t["context"]
                       "Context: #{t["context"]}\n\nTask: #{t["prompt"]}"
                     else
                       t["prompt"]
                     end

            text = Timeout.timeout(timeout_val) do
              sub_agent_api_call(model, prompt, provider_cfg, timeout_val, websearch: ws_enabled)
            end

            results_mutex.synchronize do
              results << { "id" => t["id"], "success" => true, "content" => text }
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
              send_parallel_progress(
                "Parallel tasks: #{completed_count}/#{tasks.length} completed",
                parent_ws_session_id, tasks, completed_count
              )
            end
          end
        end
      end

      # Wait for all threads (with buffer beyond per-task timeout)
      threads.each { |t| t.join(timeout_val + 10) }

      # Kill any hung threads
      threads.each { |t| t.kill if t.alive? }

      # Force-stop further tool calls after synthesis (same pattern as verification.rb).
      # The provider's depth check only blocks tool-call responses, not text-only
      # responses, so the model can still synthesize results in one more API turn.
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
        PARALLEL TASKS COMPLETED. #{succeeded}/#{tasks.length} succeeded.

        Results:
        #{results_json}

        Now synthesize these results into a coherent response for the user.
        Do NOT call any more tools.
      RESULT
    end

    private

    # Detect which provider API to use based on the app's included helper module.
    def resolve_provider_config
      ancestor_names = self.class.ancestors.map { |a| a.name.to_s }
      PROVIDER_CONFIG.each do |helper_name, config|
        return config if ancestor_names.any? { |a| a.include?(helper_name) }
      end
      PROVIDER_CONFIG["OpenAIHelper"] # fallback
    end

    # Route API call to the appropriate method based on provider and websearch flag.
    def sub_agent_api_call(model, prompt, provider_cfg, timeout_secs, websearch: false)
      api_key = CONFIG[provider_cfg[:api_key_env]] if provider_cfg[:api_key_env]

      if websearch
        case provider_cfg[:websearch_strategy]
        when :responses_api
          responses_api_sub_call(provider_cfg[:responses_endpoint], api_key, model, prompt, timeout_secs)
        when :grounding
          gemini_websearch_sub_call(provider_cfg[:endpoint], api_key, model, prompt, timeout_secs)
        when :native_tool
          anthropic_websearch_sub_call(provider_cfg[:endpoint], api_key, model, prompt, timeout_secs)
        when :tavily
          enriched = tavily_prefetch_and_inject(prompt)
          standard_sub_call(provider_cfg, api_key, model, enriched, timeout_secs)
        else # :native (Perplexity) — search is built-in
          standard_sub_call(provider_cfg, api_key, model, prompt, timeout_secs)
        end
      else
        standard_sub_call(provider_cfg, api_key, model, prompt, timeout_secs)
      end
    end

    # Standard (non-websearch) routing by provider type.
    def standard_sub_call(provider_cfg, api_key, model, prompt, timeout_secs)
      case provider_cfg[:type]
      when :anthropic
        anthropic_sub_call(provider_cfg[:endpoint], api_key, model, prompt, timeout_secs)
      when :gemini
        gemini_sub_call(provider_cfg[:endpoint], api_key, model, prompt, timeout_secs)
      when :cohere
        cohere_sub_call(provider_cfg[:endpoint], api_key, model, prompt, timeout_secs)
      else # :openai_compat
        openai_compat_sub_call(provider_cfg[:endpoint], api_key, model, prompt, timeout_secs)
      end
    end

    # OpenAI-compatible chat completions (OpenAI, DeepSeek, Grok, Mistral, Perplexity)
    def openai_compat_sub_call(endpoint, api_key, model, prompt, timeout_secs)
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }
      body = {
        "model" => model,
        "messages" => [{ "role" => "user", "content" => prompt }],
        "temperature" => 0.0
      }
      # OpenAI newer models use max_completion_tokens; others use max_tokens
      if endpoint.include?("api.openai.com")
        body["max_completion_tokens"] = 4096
      else
        body["max_tokens"] = 4096
      end
      res = HTTP.headers(headers)
                .timeout(write: timeout_secs, connect: 10, read: timeout_secs)
                .post(endpoint, json: body)
      parsed = JSON.parse(res.body.to_s)
      raise "API error: #{parsed.dig("error", "message") || parsed["error"] || res.status}" if parsed["error"] || res.status >= 400
      parsed.dig("choices", 0, "message", "content") || ""
    end

    # Anthropic Messages API
    def anthropic_sub_call(endpoint, api_key, model, prompt, timeout_secs)
      headers = {
        "Content-Type" => "application/json",
        "x-api-key" => api_key,
        "anthropic-version" => "2023-06-01"
      }
      body = {
        "model" => model,
        "messages" => [{ "role" => "user", "content" => prompt }],
        "max_tokens" => 4096,
        "temperature" => 0.0
      }
      res = HTTP.headers(headers)
                .timeout(write: timeout_secs, connect: 10, read: timeout_secs)
                .post(endpoint, json: body)
      parsed = JSON.parse(res.body.to_s)
      raise "API error: #{parsed.dig("error", "message") || parsed["error"] || res.status}" if parsed["error"] || res.status >= 400
      parsed.dig("content", 0, "text") || ""
    end

    # Google Gemini GenerateContent API
    def gemini_sub_call(endpoint, api_key, model, prompt, timeout_secs)
      target_uri = "#{endpoint}/models/#{model}:generateContent?key=#{api_key}"
      body = {
        "contents" => [{ "role" => "user", "parts" => [{ "text" => prompt }] }],
        "generationConfig" => { "temperature" => 0.0, "maxOutputTokens" => 4096 }
      }
      res = HTTP.headers("Content-Type" => "application/json")
                .timeout(write: timeout_secs, connect: 10, read: timeout_secs)
                .post(target_uri, json: body)
      parsed = JSON.parse(res.body.to_s)
      raise "API error: #{parsed.dig("error", "message") || parsed["error"] || res.status}" if parsed["error"] || res.status >= 400
      parsed.dig("candidates", 0, "content", "parts", 0, "text") || ""
    end

    # Cohere v2 Chat API
    def cohere_sub_call(endpoint, api_key, model, prompt, timeout_secs)
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }
      is_reasoning = model.to_s.include?("reasoning") || model.to_s.include?("thinking")
      body = {
        "model" => model,
        "messages" => [{ "role" => "user", "content" => prompt }]
      }
      # Reasoning models require thinking parameter and don't support temperature
      if is_reasoning
        body["thinking"] = { "type" => "enabled" }
      else
        body["temperature"] = 0.0
      end
      res = HTTP.headers(headers)
                .timeout(write: timeout_secs, connect: 10, read: timeout_secs)
                .post(endpoint, json: body)
      parsed = JSON.parse(res.body.to_s)
      raise "API error: #{parsed["message"] || res.status}" if res.status >= 400
      # Extract text content — reasoning models return [thinking, text] blocks
      content = parsed.dig("message", "content")
      return "" unless content.is_a?(Array)
      text_items = content.select { |item| item["type"] == "text" }
      return text_items.map { |item| item["text"] }.join("\n") if text_items.any?
      # Fallback: extract thinking content if no text blocks
      thinking_items = content.select { |item| item["type"] == "thinking" }
      thinking_items.map { |item| item["thinking"] }.compact.join("\n")
    end

    # OpenAI/Grok Responses API with web_search tool.
    def responses_api_sub_call(endpoint, api_key, model, prompt, timeout_secs)
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }
      body = {
        "model" => model,
        "input" => prompt,
        "tools" => [{ "type" => "web_search" }]
      }
      res = HTTP.headers(headers)
                .timeout(write: timeout_secs, connect: 10, read: timeout_secs)
                .post(endpoint, json: body)
      parsed = JSON.parse(res.body.to_s)
      raise "API error: #{parsed.dig("error", "message") || parsed["error"] || res.status}" if parsed["error"] || res.status >= 400

      # Extract text from Responses API output format
      output = parsed["output"] || []
      output.select { |item| item["type"] == "message" }
            .flat_map { |item| Array(item["content"]) }
            .select { |c| c["type"] == "output_text" }
            .map { |c| c["text"] }
            .join
    end

    # Gemini with google_search grounding tool.
    def gemini_websearch_sub_call(endpoint, api_key, model, prompt, timeout_secs)
      target_uri = "#{endpoint}/models/#{model}:generateContent?key=#{api_key}"
      body = {
        "contents" => [{ "role" => "user", "parts" => [{ "text" => prompt }] }],
        "tools" => [{ "google_search" => {} }],
        "generationConfig" => { "temperature" => 0.0, "maxOutputTokens" => 4096 }
      }
      res = HTTP.headers("Content-Type" => "application/json")
                .timeout(write: timeout_secs, connect: 10, read: timeout_secs)
                .post(target_uri, json: body)
      parsed = JSON.parse(res.body.to_s)
      raise "API error: #{parsed.dig("error", "message") || parsed["error"] || res.status}" if parsed["error"] || res.status >= 400
      parsed.dig("candidates", 0, "content", "parts", 0, "text") || ""
    end

    # Anthropic Messages API with web_search_20250305 server-side tool.
    def anthropic_websearch_sub_call(endpoint, api_key, model, prompt, timeout_secs)
      headers = {
        "Content-Type" => "application/json",
        "x-api-key" => api_key,
        "anthropic-version" => "2023-06-01"
      }
      body = {
        "model" => model,
        "messages" => [{ "role" => "user", "content" => prompt }],
        "max_tokens" => 4096,
        "temperature" => 0.0,
        "tools" => [{ "type" => "web_search_20250305", "name" => "web_search", "max_uses" => 5 }]
      }
      res = HTTP.headers(headers)
                .timeout(write: timeout_secs, connect: 10, read: timeout_secs)
                .post(endpoint, json: body)
      parsed = JSON.parse(res.body.to_s)
      raise "API error: #{parsed.dig("error", "message") || parsed["error"] || res.status}" if parsed["error"] || res.status >= 400

      # Extract only text blocks (skip web_search_tool_result blocks)
      content = parsed["content"]
      return "" unless content.is_a?(Array)
      text_blocks = content.select { |c| c["type"] == "text" }
      text_blocks.map { |c| c["text"] }.join("\n")
    end

    # Prefetch Tavily search results and inject into prompt.
    # Raises RuntimeError if TAVILY_API_KEY is not configured.
    def tavily_prefetch_and_inject(prompt)
      api_key = CONFIG["TAVILY_API_KEY"]
      raise "TAVILY_API_KEY is not configured. Web search requires a Tavily API key for this provider." if api_key.nil? || api_key.empty?

      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }
      body = {
        "query" => prompt.slice(0, 400),
        "search_depth" => "basic",
        "max_results" => 3,
        "include_answer" => false,
        "include_raw_content" => false,
        "include_images" => false
      }

      begin
        res = HTTP.headers(headers)
                  .timeout(connect: 10, write: 15, read: 15)
                  .post("https://api.tavily.com/search", json: body)
        parsed = JSON.parse(res.body.to_s)
        results = parsed["results"]
        return prompt unless results.is_a?(Array) && !results.empty?

        search_block = results.map do |r|
          "### #{r["title"]}\nURL: #{r["url"]}\n#{r["content"]}"
        end.join("\n\n")

        "=== Web Search Results ===\n#{search_block}\n=== End Search Results ===\n\n#{prompt}"
      rescue StandardError
        # Tavily API error — fall back to original prompt
        prompt
      end
    end

    # Send progress update to the WebSocket for temp card display.
    def send_parallel_progress(message, ws_session_id, tasks, completed)
      return unless defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_progress_fragment)

      task_names = tasks.map { |t| t["id"] }
      fragment = {
        "type" => "wait",
        "content" => message,
        "source" => "ParallelDispatch",
        "parallel_progress" => {
          "completed" => completed,
          "total" => tasks.length,
          "task_names" => task_names
        },
        "step_progress" => {
          "mode" => "parallel",
          "current" => completed,
          "total" => tasks.length,
          "steps" => task_names
        }
      }
      WebSocketHelper.send_progress_fragment(fragment, ws_session_id)
    rescue StandardError
      # Progress reporting is best-effort; don't fail the dispatch
    end
  end
end
