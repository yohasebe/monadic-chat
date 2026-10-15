# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../lib/monadic/utils/tool_dispatch_guard"
require_relative "../../../lib/monadic/utils/tts_text_extractor"
%w[openai claude gemini grok mistral cohere deepseek ollama].each do |p|
  require_relative "../../../lib/monadic/adapters/vendors/#{p}_helper"
end

RSpec.describe Monadic::Utils::ToolDispatchGuard do
  describe ".offered_names" do
    it "reads every provider's tool shape and skips entries without a name" do
      tools = [
        { "type" => "function", "function" => { "name" => "chat_style" } },
        { "type" => "function", "name" => "responses_style" },
        { "name" => "claude_style", "input_schema" => {} },
        { "function_declarations" => [{ "name" => "gemini_style" }] },
        { "google_search" => {} },
        { "type" => "web_search" }
      ]
      expect(described_class.offered_names(tools).to_a)
        .to contain_exactly("chat_style", "responses_style", "claude_style", "gemini_style")
    end

    it "accepts a single Gemini-style hash" do
      expect(described_class.offered_names({ "function_declarations" => [{ name: "x" }] }).to_a).to eq(["x"])
    end
  end

  describe ".refusal" do
    let(:session) { {} }

    after { Thread.current[described_class::STORE_KEY] = nil }

    it "refuses everything before anything is recorded" do
      expect(described_class.refusal(session, "App", "anything")).to include("Unknown tool")
    end

    it "allows only the names of the latest request for the app" do
      described_class.record!(session, "App", [{ "name" => "a" }])
      expect(described_class.refusal(session, "App", "a")).to be_nil
      expect(described_class.refusal(session, "App", "send_command")).to include("Unknown tool: send_command")
      expect(described_class.refusal(session, "Other", "a")).to include("Unknown tool")

      described_class.record!(session, "App", [{ "name" => "b" }])
      expect(described_class.refusal(session, "App", "a")).to include("Unknown tool")
      expect(described_class.refusal(session, "App", "b")).to be_nil
    end

    it "keeps the record of a request apart from an overlapping one in the same session" do
      shared_session = {}
      ready = Queue.new
      proceed = Queue.new
      a_result = nil
      a = Thread.new do
        described_class.record!(shared_session, "App", [{ "name" => "tool_a" }])
        ready << true
        proceed.pop
        a_result = [described_class.refusal(shared_session, "App", "tool_a"),
                    described_class.refusal(shared_session, "App", "tool_b")]
      end
      ready.pop
      Thread.new { described_class.record!(shared_session, "App", [{ "name" => "tool_b" }]) }.join
      proceed << true
      a.join
      expect(a_result[0]).to be_nil
      expect(a_result[1]).to include("Unknown tool: tool_b")
    end

    it "keeps the outer record when a tool sends a request of its own with a new session" do
      described_class.record!(session, "App", [{ "name" => "outer_tool" }, { "name" => "next_tool" }])
      # A code agent builds its own session and runs the same helper inside the tool.
      inner_session = {}
      described_class.record!(inner_session, "App", [{ "name" => "inner_tool" }])
      expect(described_class.refusal(inner_session, "App", "inner_tool")).to be_nil
      expect(described_class.refusal(inner_session, "App", "next_tool")).to include("Unknown tool")
      expect(described_class.refusal(session, "App", "next_tool")).to be_nil
      expect(described_class.refusal(session, "App", "inner_tool")).to include("Unknown tool")
    end

    it "keeps a bounded number of records and refuses calls checked against a dropped one" do
      first = {}
      described_class.record!(first, "App", [{ "name" => "a" }])
      sessions = Array.new(described_class::MAX_RECORDS) { {} }
      sessions.each { |s| described_class.record!(s, "App", [{ "name" => "a" }]) }
      expect(Thread.current[described_class::STORE_KEY].size).to eq(described_class::MAX_RECORDS)
      expect(described_class.refusal(first, "App", "a")).to include("Unknown tool")
      expect(described_class.refusal(sessions.last, "App", "a")).to be_nil
    end

    it "keeps a record that is used again from being dropped first" do
      described_class.record!(session, "App", [{ "name" => "a" }])
      others = Array.new(described_class::MAX_RECORDS - 1) { {} }
      others.each { |s| described_class.record!(s, "App", [{ "name" => "x" }]) }
      described_class.record!(session, "App", [{ "name" => "a" }])
      described_class.record!({}, "App", [{ "name" => "x" }])
      expect(described_class.refusal(session, "App", "a")).to be_nil
      expect(described_class.refusal(others.first, "App", "x")).to include("Unknown tool")
    end

    it "does not use another session's record" do
      described_class.record!({}, "App", [{ "name" => "a" }])
      expect(described_class.refusal({}, "App", "a")).to include("Unknown tool")
    end

    it "refuses every call after a request without tools" do
      described_class.record!(session, "App", nil)
      expect(described_class.refusal(session, "App", "a")).to include("Unknown tool")
    end
  end
end

# Every provider helper runs only offered tools, and with public_send.
RSpec.describe "Tool dispatch in the provider helpers" do
  let(:target_class) do
    Class.new(MonadicApp) do
      attr_reader :calls

      def declared_tool(value: nil)
        (@calls ||= []) << [:declared_tool, value]
        "declared ran"
      end

      private

      def private_tool
        (@calls ||= []) << [:private_tool]
        "private ran"
      end
    end
  end
  let(:target) { target_class.new }
  let(:session) { { parameters: { "app_name" => "SpecDispatchApp" }, messages: [] } }

  before do
    stub_const("APPS", { "SpecDispatchApp" => target })
    stub_const("CONFIG", {})
    allow(target).to receive(:send_command).and_call_original
    allow(target).to receive(:run_code).and_call_original
  end

  def host_for(helper_module)
    host = Class.new(MonadicApp) { include helper_module }.new
    allow(host).to receive(:api_request).and_return([])
    host
  end

  def offer(names)
    Monadic::Utils::ToolDispatchGuard.record!(session, "SpecDispatchApp", names.map { |n| { "name" => n } })
  end

  # name => lambda(host, function_name, args) that runs one tool call
  RUNNERS = {
    "OpenAI" => [OpenAIHelper, lambda { |h, s, name, args|
      h.send(:invoke_openai_tool_function, "SpecDispatchApp", s, s[:parameters],
             { "id" => "c1", "function" => { "name" => name, "arguments" => args.to_json } }, [], [])
    }],
    "Claude" => [ClaudeHelper, lambda { |h, s, name, args|
      h.send(:invoke_claude_tool_function, "SpecDispatchApp", s, { "id" => "c1", "name" => name, "input" => args }, name)
    }],
    "Gemini" => [GeminiHelper, lambda { |h, s, name, args|
      h.send(:process_functions, "SpecDispatchApp", s, [{ "name" => name, "args" => args }], [], 0)
    }],
    "Grok" => [GrokHelper, lambda { |h, s, name, args|
      h.send(:invoke_grok_tool_function, "SpecDispatchApp", s,
             { "id" => "c1", "function" => { "name" => name, "arguments" => args.to_json } }, name)
    }],
    "Mistral" => [MistralHelper, lambda { |h, s, name, args|
      h.send(:invoke_mistral_tool_function, "SpecDispatchApp", s,
                                     { "id" => "c1", "function" => { "name" => name, "arguments" => args.to_json } }, name)
    }],
    "Cohere" => [CohereHelper, lambda { |h, s, name, args|
      h.send(:invoke_cohere_tool_function, "SpecDispatchApp", s,
             { "id" => "c1", "function" => { "name" => name, "arguments" => args.to_json } }, name)
    }],
    "DeepSeek" => [DeepSeekHelper, lambda { |h, s, name, args|
      h.send(:invoke_deepseek_tool_function, "SpecDispatchApp", s,
                                      { "id" => "c1", "function" => { "name" => name, "arguments" => args.to_json } }, name)
    }],
    "Ollama" => [OllamaHelper, lambda { |h, s, name, args|
      h.send(:process_functions, "SpecDispatchApp", s,
             [{ "function" => { "name" => name, "arguments" => args } }], [], 0)
    }]
  }.freeze

  RUNNERS.each do |provider, (helper_module, run)|
    context provider do
      it "refuses undeclared names and does not call them" do
        offer(["declared_tool"])
        host = host_for(helper_module)
        expect(target).not_to receive(:send_command)
        expect(target).not_to receive(:run_code)
        %w[send_command exit instance_eval run_code private_tool].each do |name|
          args = name == "send_command" ? { "command" => "true", "container" => "ruby" } : {}
          expect { run.call(host, session, name, args) }.not_to raise_error
        end
        expect(Array(target.calls)).to be_empty
      end

      it "runs a declared tool" do
        offer(["declared_tool"])
        host = host_for(helper_module)
        expect { run.call(host, session, "declared_tool", { "value" => "v" }) }.not_to raise_error
        expect(target.calls).to include([:declared_tool, "v"])
      end

      it "does not reach a private method even when its name was offered" do
        offer(["private_tool"])
        host = host_for(helper_module)
        expect { run.call(host, session, "private_tool", {}) }.not_to raise_error
        expect(Array(target.calls)).to be_empty
      end
    end
  end
end
