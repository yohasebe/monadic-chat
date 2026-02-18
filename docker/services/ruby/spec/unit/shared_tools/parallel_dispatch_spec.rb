# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/parallel_dispatch"

# Mock MonadicHelper for testing
module MonadicHelper
end unless defined?(MonadicHelper)

# Mock CONFIG for testing
unless defined?(CONFIG)
  CONFIG = {
    "OPENAI_API_KEY" => "test-key-openai",
    "ANTHROPIC_API_KEY" => "test-key-anthropic",
    "GEMINI_API_KEY" => "test-key-gemini",
    "COHERE_API_KEY" => "test-key-cohere",
    "DEEPSEEK_API_KEY" => "test-key-deepseek",
    "XAI_API_KEY" => "test-key-xai",
    "MISTRAL_API_KEY" => "test-key-mistral",
    "PERPLEXITY_API_KEY" => "test-key-perplexity",
    "TAVILY_API_KEY" => "test-key-tavily"
  }
end

# Mock WebSocketHelper for testing
module WebSocketHelper
  def self.send_progress_fragment(fragment, session_id = nil)
    # no-op in tests
  end
end unless defined?(WebSocketHelper)

RSpec.describe "MonadicSharedTools::ParallelDispatch" do
  # Create a test class that includes the module (simulating an app instance)
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::ParallelDispatch

      # Make private methods accessible for testing
      public :resolve_provider_config, :sub_agent_api_call,
             :openai_compat_sub_call, :anthropic_sub_call,
             :gemini_sub_call, :cohere_sub_call,
             :responses_api_sub_call,
             :gemini_websearch_sub_call,
             :anthropic_websearch_sub_call,
             :tavily_prefetch_and_inject,
             :standard_sub_call,
             :send_parallel_progress
    end
  end

  let(:app) { test_class.new }

  let(:valid_tasks) do
    [
      { "id" => "task_1", "prompt" => "Research topic A" },
      { "id" => "task_2", "prompt" => "Research topic B" }
    ]
  end

  let(:session) do
    { parameters: { "model" => "gpt-4.1" } }
  end

  describe "#dispatch_parallel_tasks" do
    context "input validation" do
      it "returns error for nil tasks" do
        result = app.dispatch_parallel_tasks(tasks: nil, session: session)
        expect(result).to include("ERROR")
        expect(result).to include("non-empty array")
      end

      it "returns error for empty tasks" do
        result = app.dispatch_parallel_tasks(tasks: [], session: session)
        expect(result).to include("ERROR")
        expect(result).to include("non-empty array")
      end

      it "returns error for non-array tasks" do
        result = app.dispatch_parallel_tasks(tasks: "not an array", session: session)
        expect(result).to include("ERROR")
      end

      it "returns error when tasks exceed MAX_PARALLEL_TASKS" do
        tasks = 6.times.map { |i| { "id" => "t#{i}", "prompt" => "p#{i}" } }
        result = app.dispatch_parallel_tasks(tasks: tasks, session: session)
        expect(result).to include("ERROR")
        expect(result).to include("Maximum 5")
      end

      it "returns error for task missing 'id'" do
        tasks = [{ "prompt" => "something" }]
        result = app.dispatch_parallel_tasks(tasks: tasks, session: session)
        expect(result).to include("ERROR")
        expect(result).to include("'id' and 'prompt'")
      end

      it "returns error for task missing 'prompt'" do
        tasks = [{ "id" => "t1" }]
        result = app.dispatch_parallel_tasks(tasks: tasks, session: session)
        expect(result).to include("ERROR")
        expect(result).to include("'id' and 'prompt'")
      end

      it "returns error for non-hash task" do
        tasks = ["not a hash"]
        result = app.dispatch_parallel_tasks(tasks: tasks, session: session)
        expect(result).to include("ERROR")
      end
    end

    context "successful execution" do
      before do
        # Mock the sub_agent_api_call to return text
        allow(app).to receive(:sub_agent_api_call).and_return("Mocked response text")
      end

      it "returns PARALLEL TASKS COMPLETED message" do
        result = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result).to include("PARALLEL TASKS COMPLETED")
      end

      it "returns correct success count" do
        result = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result).to include("2/2 succeeded")
      end

      it "includes synthesize instruction" do
        result = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result).to include("Synthesize these results")
        expect(result).to include("Do NOT call dispatch_parallel_tasks again")
      end

      it "includes result content from sub-agents" do
        result = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result).to include("Mocked response text")
      end

      it "includes task IDs in results" do
        result = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result).to include("task_1")
        expect(result).to include("task_2")
      end

      it "passes context when provided" do
        tasks = [{ "id" => "t1", "prompt" => "Analyze this", "context" => "Some context" }]
        expect(app).to receive(:sub_agent_api_call) do |model, prompt, _, _, **kwargs|
          expect(prompt).to include("Context: Some context")
          expect(prompt).to include("Task: Analyze this")
          "Response"
        end
        app.dispatch_parallel_tasks(tasks: tasks, session: session)
      end

      it "uses model from session parameters" do
        expect(app).to receive(:sub_agent_api_call).with("gpt-4.1", anything, anything, anything, websearch: false).and_return("text")
        tasks = [{ "id" => "t1", "prompt" => "test" }]
        app.dispatch_parallel_tasks(tasks: tasks, session: session)
      end
    end

    context "one dispatch per turn guard" do
      before do
        allow(app).to receive(:sub_agent_api_call).and_return("text")
      end

      it "allows the first call and blocks the second call in the same turn" do
        result1 = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result1).to include("PARALLEL TASKS COMPLETED")

        result2 = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result2).to include("ERROR: dispatch_parallel_tasks has already been called")
      end

      it "allows dispatch again after parallel_dispatch_called is cleared (new turn)" do
        app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(session[:parallel_dispatch_called]).to eq(true)

        # Simulate new user turn: vendor helper resets the flag
        session[:parallel_dispatch_called] = nil

        result = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result).to include("PARALLEL TASKS COMPLETED")
      end

      it "does not block when session is nil" do
        expect {
          app.dispatch_parallel_tasks(tasks: valid_tasks, session: nil)
        }.not_to raise_error
      end

      it "does not modify call_depth_per_turn" do
        session_with_depth = { parameters: { "model" => "gpt-4.1" }, call_depth_per_turn: 3 }
        app.dispatch_parallel_tasks(tasks: valid_tasks, session: session_with_depth)
        expect(session_with_depth[:call_depth_per_turn]).to eq(3)
      end

      it "instructs not to re-call dispatch_parallel_tasks but allows other tools" do
        result = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result).to include("Do NOT call dispatch_parallel_tasks again")
        expect(result).to include("You may use other tools")
      end
    end

    context "partial failure" do
      it "reports partial success when some tasks fail" do
        call_count = 0
        allow(app).to receive(:sub_agent_api_call) do
          call_count += 1
          if call_count == 1
            "Good response"
          else
            raise "API error"
          end
        end

        result = app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
        expect(result).to include("PARALLEL TASKS COMPLETED")
        expect(result).to include("1/2 succeeded")
      end
    end

    context "timeout handling" do
      it "records timeout error for tasks that exceed timeout" do
        allow(app).to receive(:sub_agent_api_call) do
          raise Timeout::Error, "execution expired"
        end

        result = app.dispatch_parallel_tasks(tasks: valid_tasks, timeout: 120, session: session)
        expect(result).to include("PARALLEL TASKS COMPLETED")
        expect(result).to include("0/2 succeeded")
        expect(result).to include("Timed out")
      end

      it "clamps timeout to MAX_TIMEOUT" do
        allow(app).to receive(:sub_agent_api_call).and_return("text")
        tasks = [{ "id" => "t1", "prompt" => "test" }]
        # Timeout of 999 should be clamped to MAX_TIMEOUT (300)
        result = app.dispatch_parallel_tasks(tasks: tasks, timeout: 999, session: session)
        expect(result).to include("PARALLEL TASKS COMPLETED")
      end
    end

    context "progress reporting" do
      it "sends initial dispatching progress" do
        allow(app).to receive(:sub_agent_api_call).and_return("text")
        expect(WebSocketHelper).to receive(:send_progress_fragment).at_least(:once) do |fragment, _|
          # At least one call should be the initial "Dispatching" message
          true
        end

        app.dispatch_parallel_tasks(tasks: valid_tasks, session: session)
      end
    end

    context "without session" do
      before do
        allow(app).to receive(:sub_agent_api_call).and_return("text")
      end

      it "uses provider default model when session is nil" do
        expect(app).to receive(:sub_agent_api_call).with(kind_of(String), anything, anything, anything, websearch: false).and_return("text")
        tasks = [{ "id" => "t1", "prompt" => "test" }]
        app.dispatch_parallel_tasks(tasks: tasks, session: nil)
      end
    end
  end

  describe "#resolve_provider_config" do
    it "returns OpenAI config by default (no known helper in ancestors)" do
      config = app.resolve_provider_config
      expect(config[:type]).to eq(:openai_compat)
      expect(config[:api_key_env]).to eq("OPENAI_API_KEY")
    end

    it "detects ClaudeHelper as anthropic type" do
      claude_class = Class.new do
        module ::ClaudeHelperStub; end
        include ClaudeHelperStub
        include MonadicSharedTools::ParallelDispatch
        public :resolve_provider_config
      end
      # Stub the ancestor check
      allow_any_instance_of(claude_class).to receive(:resolve_provider_config) do
        MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["ClaudeHelper"]
      end
      config = claude_class.new.resolve_provider_config
      expect(config[:type]).to eq(:anthropic)
    end
  end

  describe "#send_parallel_progress" do
    it "sends fragment with correct structure" do
      tasks = [{ "id" => "t1", "prompt" => "p1" }, { "id" => "t2", "prompt" => "p2" }]
      expect(WebSocketHelper).to receive(:send_progress_fragment) do |fragment, _ws_id|
        expect(fragment["type"]).to eq("wait")
        expect(fragment["source"]).to eq("ParallelDispatch")
        expect(fragment["parallel_progress"]["total"]).to eq(2)
        expect(fragment["parallel_progress"]["completed"]).to eq(1)
        expect(fragment["parallel_progress"]["task_names"]).to eq(["t1", "t2"])
      end

      app.send_parallel_progress("test message", nil, tasks, 1)
    end

    it "includes step_progress in the fragment" do
      tasks = [{ "id" => "t1", "prompt" => "p1" }, { "id" => "t2", "prompt" => "p2" }]
      expect(WebSocketHelper).to receive(:send_progress_fragment) do |fragment, _ws_id|
        sp = fragment["step_progress"]
        expect(sp).not_to be_nil
        expect(sp["mode"]).to eq("parallel")
        expect(sp["current"]).to eq(1)
        expect(sp["total"]).to eq(2)
        expect(sp["steps"]).to eq(["t1", "t2"])
      end

      app.send_parallel_progress("test message", nil, tasks, 1)
    end

    it "does not raise if WebSocketHelper is not available" do
      allow(WebSocketHelper).to receive(:send_progress_fragment).and_raise(StandardError)
      expect {
        app.send_parallel_progress("msg", nil, valid_tasks, 0)
      }.not_to raise_error
    end
  end

  describe "sub-agent API call methods" do
    let(:mock_response) { double("response", body: double(to_s: '{}'), status: 200) }
    let(:mock_http) { double("http") }

    before do
      allow(HTTP).to receive(:headers).and_return(mock_http)
      allow(mock_http).to receive(:timeout).and_return(mock_http)
      allow(mock_http).to receive(:post).and_return(mock_response)
    end

    describe "#openai_compat_sub_call" do
      it "extracts text from OpenAI-format response" do
        response_json = {
          "choices" => [{ "message" => { "content" => "Hello from OpenAI" } }]
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        result = app.openai_compat_sub_call(
          "https://api.openai.com/v1/chat/completions",
          "key", "gpt-4.1", "test", 120
        )
        expect(result).to eq("Hello from OpenAI")
      end

      it "raises on API error" do
        error_json = { "error" => { "message" => "Rate limited" } }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: error_json))
        allow(mock_response).to receive(:status).and_return(429)

        expect {
          app.openai_compat_sub_call("https://api.openai.com/v1/chat/completions", "key", "gpt-4.1", "test", 120)
        }.to raise_error(RuntimeError, /Rate limited/)
      end
    end

    describe "#anthropic_sub_call" do
      it "extracts text from Anthropic-format response" do
        response_json = {
          "content" => [{ "type" => "text", "text" => "Hello from Claude" }]
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        result = app.anthropic_sub_call(
          "https://api.anthropic.com/v1/messages",
          "key", "claude-sonnet-4-6", "test", 120
        )
        expect(result).to eq("Hello from Claude")
      end
    end

    describe "#gemini_sub_call" do
      it "extracts text from Gemini-format response" do
        response_json = {
          "candidates" => [{
            "content" => { "parts" => [{ "text" => "Hello from Gemini" }] }
          }]
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        result = app.gemini_sub_call(
          "https://generativelanguage.googleapis.com/v1beta",
          "key", "gemini-2.5-flash", "test", 120
        )
        expect(result).to eq("Hello from Gemini")
      end
    end

    describe "#cohere_sub_call" do
      it "extracts text from Cohere-format response" do
        response_json = {
          "message" => { "content" => [{ "type" => "text", "text" => "Hello from Cohere" }] }
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        result = app.cohere_sub_call(
          "https://api.cohere.ai/v2/chat",
          "key", "command-a-reasoning", "test", 120
        )
        expect(result).to eq("Hello from Cohere")
      end
    end
  end

  describe "constants" do
    it "defines MAX_PARALLEL_TASKS as 5" do
      expect(MonadicSharedTools::ParallelDispatch::MAX_PARALLEL_TASKS).to eq(5)
    end

    it "defines DEFAULT_TIMEOUT as 120" do
      expect(MonadicSharedTools::ParallelDispatch::DEFAULT_TIMEOUT).to eq(120)
    end

    it "defines MAX_TIMEOUT as 300" do
      expect(MonadicSharedTools::ParallelDispatch::MAX_TIMEOUT).to eq(300)
    end

    it "has PROVIDER_CONFIG for all major providers" do
      config = MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG
      expect(config.keys).to include(
        "OpenAIHelper", "ClaudeHelper", "GeminiHelper",
        "CohereHelper", "DeepSeekHelper", "GrokHelper",
        "MistralHelper", "PerplexityHelper"
      )
    end
  end

  # ===== Web Search Tests =====

  describe "PROVIDER_CONFIG websearch strategies" do
    let(:config) { MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG }

    it "defines websearch_strategy for all providers" do
      config.each do |name, cfg|
        expect(cfg).to have_key(:websearch_strategy), "#{name} missing websearch_strategy"
      end
    end

    it "maps OpenAI and Grok to :responses_api with responses_endpoint" do
      %w[OpenAIHelper GrokHelper].each do |name|
        expect(config[name][:websearch_strategy]).to eq(:responses_api)
        expect(config[name][:responses_endpoint]).to be_a(String)
      end
    end

    it "maps Perplexity to :native" do
      expect(config["PerplexityHelper"][:websearch_strategy]).to eq(:native)
    end

    it "maps Gemini to :grounding" do
      expect(config["GeminiHelper"][:websearch_strategy]).to eq(:grounding)
    end

    it "maps Claude to :native_tool" do
      expect(config["ClaudeHelper"][:websearch_strategy]).to eq(:native_tool)
    end

    it "maps Mistral, Cohere, and DeepSeek to :tavily" do
      %w[MistralHelper CohereHelper DeepSeekHelper].each do |name|
        expect(config[name][:websearch_strategy]).to eq(:tavily)
      end
    end
  end

  describe "#dispatch_parallel_tasks with websearch" do
    before do
      allow(app).to receive(:sub_agent_api_call).and_return("Mocked response")
    end

    it "propagates websearch: true to sub_agent_api_call" do
      expect(app).to receive(:sub_agent_api_call)
        .with(anything, anything, anything, anything, websearch: true)
        .and_return("text")
      tasks = [{ "id" => "t1", "prompt" => "test" }]
      app.dispatch_parallel_tasks(tasks: tasks, websearch: true, session: session)
    end

    it "inherits websearch from session parameters" do
      ws_session = { parameters: { "model" => "gpt-4.1", "websearch" => true } }
      expect(app).to receive(:sub_agent_api_call)
        .with(anything, anything, anything, anything, websearch: true)
        .and_return("text")
      tasks = [{ "id" => "t1", "prompt" => "test" }]
      app.dispatch_parallel_tasks(tasks: tasks, session: ws_session)
    end

    it "explicit websearch: false overrides session" do
      ws_session = { parameters: { "model" => "gpt-4.1", "websearch" => true } }
      expect(app).to receive(:sub_agent_api_call)
        .with(anything, anything, anything, anything, websearch: false)
        .and_return("text")
      tasks = [{ "id" => "t1", "prompt" => "test" }]
      app.dispatch_parallel_tasks(tasks: tasks, websearch: false, session: ws_session)
    end

    it "defaults to websearch: false when not specified" do
      expect(app).to receive(:sub_agent_api_call)
        .with(anything, anything, anything, anything, websearch: false)
        .and_return("text")
      tasks = [{ "id" => "t1", "prompt" => "test" }]
      app.dispatch_parallel_tasks(tasks: tasks, session: session)
    end
  end

  describe "websearch sub_call methods" do
    let(:mock_response) { double("response", body: double(to_s: '{}'), status: 200) }
    let(:mock_http) { double("http") }

    before do
      allow(HTTP).to receive(:headers).and_return(mock_http)
      allow(mock_http).to receive(:timeout).and_return(mock_http)
      allow(mock_http).to receive(:post).and_return(mock_response)
    end

    describe "#responses_api_sub_call" do
      it "extracts text from Responses API output format" do
        response_json = {
          "output" => [
            { "type" => "message", "content" => [
              { "type" => "output_text", "text" => "Search result from Responses API" }
            ] }
          ]
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        result = app.responses_api_sub_call(
          "https://api.openai.com/v1/responses", "key", "gpt-4.1", "test query", 120
        )
        expect(result).to eq("Search result from Responses API")
      end

      it "includes web_search tool in request body" do
        response_json = { "output" => [] }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        expect(mock_http).to receive(:post) do |_url, **opts|
          body = opts[:json]
          expect(body["tools"]).to include({ "type" => "web_search" })
          mock_response
        end

        app.responses_api_sub_call(
          "https://api.openai.com/v1/responses", "key", "gpt-4.1", "test", 120
        )
      end

      it "raises on API error" do
        error_json = { "error" => { "message" => "Bad request" } }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: error_json))
        allow(mock_response).to receive(:status).and_return(400)

        expect {
          app.responses_api_sub_call("https://api.openai.com/v1/responses", "key", "gpt-4.1", "test", 120)
        }.to raise_error(RuntimeError, /Bad request/)
      end
    end

    describe "#gemini_websearch_sub_call" do
      it "includes google_search tool in request" do
        response_json = {
          "candidates" => [{ "content" => { "parts" => [{ "text" => "Grounded result" }] } }]
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        expect(mock_http).to receive(:post) do |_url, **opts|
          body = opts[:json]
          expect(body["tools"]).to include({ "google_search" => {} })
          mock_response
        end

        app.gemini_websearch_sub_call(
          "https://generativelanguage.googleapis.com/v1beta", "key", "gemini-2.5-flash", "test", 120
        )
      end

      it "extracts text from Gemini response" do
        response_json = {
          "candidates" => [{ "content" => { "parts" => [{ "text" => "Grounded result" }] } }]
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        result = app.gemini_websearch_sub_call(
          "https://generativelanguage.googleapis.com/v1beta", "key", "gemini-2.5-flash", "test", 120
        )
        expect(result).to eq("Grounded result")
      end
    end

    describe "#anthropic_websearch_sub_call" do
      it "includes web_search_20250305 tool in request" do
        response_json = {
          "content" => [{ "type" => "text", "text" => "Web search result" }]
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        expect(mock_http).to receive(:post) do |_url, **opts|
          body = opts[:json]
          tool = body["tools"].find { |t| t["type"] == "web_search_20250305" }
          expect(tool).not_to be_nil
          expect(tool["name"]).to eq("web_search")
          expect(tool["max_uses"]).to eq(5)
          mock_response
        end

        app.anthropic_websearch_sub_call(
          "https://api.anthropic.com/v1/messages", "key", "claude-sonnet-4-6", "test", 120
        )
      end

      it "extracts only text blocks from mixed content response" do
        response_json = {
          "content" => [
            { "type" => "web_search_tool_result", "content" => "raw search data" },
            { "type" => "text", "text" => "Answer from Claude" },
            { "type" => "web_search_tool_result", "content" => "more data" },
            { "type" => "text", "text" => " with citations" }
          ]
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: response_json))
        allow(mock_response).to receive(:status).and_return(200)

        result = app.anthropic_websearch_sub_call(
          "https://api.anthropic.com/v1/messages", "key", "claude-sonnet-4-6", "test", 120
        )
        expect(result).to eq("Answer from Claude\n with citations")
      end
    end

    describe "#tavily_prefetch_and_inject" do
      it "injects search results into prompt when TAVILY_API_KEY is set" do
        tavily_response = {
          "results" => [
            { "title" => "Result 1", "url" => "https://example.com/1", "content" => "Content 1" },
            { "title" => "Result 2", "url" => "https://example.com/2", "content" => "Content 2" }
          ]
        }.to_json
        allow(mock_response).to receive(:body).and_return(double(to_s: tavily_response))
        allow(mock_response).to receive(:status).and_return(200)

        result = app.tavily_prefetch_and_inject("What is Ruby?")
        expect(result).to include("=== Web Search Results ===")
        expect(result).to include("Result 1")
        expect(result).to include("Content 1")
        expect(result).to include("What is Ruby?")
      end

      it "raises RuntimeError when TAVILY_API_KEY is not set" do
        original = CONFIG["TAVILY_API_KEY"]
        CONFIG.delete("TAVILY_API_KEY")
        begin
          expect {
            app.tavily_prefetch_and_inject("test query")
          }.to raise_error(RuntimeError, /TAVILY_API_KEY/)
        ensure
          CONFIG["TAVILY_API_KEY"] = original
        end
      end

      it "falls back to original prompt on Tavily API error" do
        allow(mock_response).to receive(:body).and_return(double(to_s: '{"error": "Bad request"}'))
        allow(mock_response).to receive(:status).and_return(400)

        result = app.tavily_prefetch_and_inject("fallback test")
        expect(result).to eq("fallback test")
      end
    end
  end

  describe "#sub_agent_api_call websearch routing" do
    let(:openai_cfg) { MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["OpenAIHelper"] }
    let(:grok_cfg) { MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["GrokHelper"] }
    let(:gemini_cfg) { MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["GeminiHelper"] }
    let(:claude_cfg) { MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["ClaudeHelper"] }
    let(:perplexity_cfg) { MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["PerplexityHelper"] }
    let(:mistral_cfg) { MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["MistralHelper"] }
    let(:deepseek_cfg) { MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["DeepSeekHelper"] }
    let(:cohere_cfg) { MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["CohereHelper"] }

    it "routes OpenAI to responses_api_sub_call when websearch: true" do
      expect(app).to receive(:responses_api_sub_call).and_return("result")
      app.sub_agent_api_call("gpt-4.1", "test", openai_cfg, 120, websearch: true)
    end

    it "routes Grok to responses_api_sub_call when websearch: true" do
      expect(app).to receive(:responses_api_sub_call).and_return("result")
      app.sub_agent_api_call("grok-3", "test", grok_cfg, 120, websearch: true)
    end

    it "routes Gemini to gemini_websearch_sub_call when websearch: true" do
      expect(app).to receive(:gemini_websearch_sub_call).and_return("result")
      app.sub_agent_api_call("gemini-2.5-flash", "test", gemini_cfg, 120, websearch: true)
    end

    it "routes Claude to anthropic_websearch_sub_call when websearch: true" do
      expect(app).to receive(:anthropic_websearch_sub_call).and_return("result")
      app.sub_agent_api_call("claude-sonnet-4-6", "test", claude_cfg, 120, websearch: true)
    end

    it "routes Perplexity to openai_compat_sub_call (native search) when websearch: true" do
      expect(app).to receive(:openai_compat_sub_call).and_return("result")
      app.sub_agent_api_call("sonar-pro", "test", perplexity_cfg, 120, websearch: true)
    end

    it "routes Mistral to tavily_prefetch + openai_compat when websearch: true" do
      expect(app).to receive(:tavily_prefetch_and_inject).with("test").and_return("enriched")
      expect(app).to receive(:openai_compat_sub_call).and_return("result")
      app.sub_agent_api_call("mistral-large", "test", mistral_cfg, 120, websearch: true)
    end

    it "routes DeepSeek to tavily_prefetch + openai_compat when websearch: true" do
      expect(app).to receive(:tavily_prefetch_and_inject).with("test").and_return("enriched")
      expect(app).to receive(:openai_compat_sub_call).and_return("result")
      app.sub_agent_api_call("deepseek-chat", "test", deepseek_cfg, 120, websearch: true)
    end

    it "routes Cohere to tavily_prefetch + cohere_sub_call when websearch: true" do
      expect(app).to receive(:tavily_prefetch_and_inject).with("test").and_return("enriched")
      expect(app).to receive(:cohere_sub_call).and_return("result")
      app.sub_agent_api_call("command-a-08-2025", "test", cohere_cfg, 120, websearch: true)
    end

    it "uses standard routing when websearch: false" do
      expect(app).not_to receive(:responses_api_sub_call)
      expect(app).to receive(:openai_compat_sub_call).and_return("result")
      app.sub_agent_api_call("gpt-4.1", "test", openai_cfg, 120, websearch: false)
    end

    it "raises RuntimeError for tavily providers when TAVILY_API_KEY missing" do
      original = CONFIG["TAVILY_API_KEY"]
      CONFIG.delete("TAVILY_API_KEY")
      begin
        expect {
          app.sub_agent_api_call("mistral-large", "test", mistral_cfg, 120, websearch: true)
        }.to raise_error(RuntimeError, /TAVILY_API_KEY/)
      ensure
        CONFIG["TAVILY_API_KEY"] = original
      end
    end
  end
end
