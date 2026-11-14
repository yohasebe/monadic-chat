# frozen_string_literal: true

require_relative "../../../spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"
require_relative "../../../../lib/monadic/adapters/vendors/cohere_helper"
require_relative "../../../../lib/monadic/adapters/vendors/deepseek_helper"
require_relative "../../../../lib/monadic/adapters/vendors/ollama_helper"
require_relative "../../../../lib/monadic/adapters/vendors/grok_helper"
require_relative "../../../../lib/monadic/adapters/vendors/gemini_helper"
require_relative "../../../../lib/monadic/utils/tts_text_extractor"

# A reply whose tool took the reply's text (tts_target) ends with that tool:
# the provider is not asked again.
RSpec.describe "A reply ended by the tool that takes its text" do
  let(:session) { { parameters: { "app_name" => "Speaker" }, messages: [] } }
  let(:events) { [] }
  let(:ended) { [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "" } }] }] }

  def helper(mod)
    Class.new { include mod }.new.tap do |h|
      allow(h).to receive(:api_request).and_return([{ "choices" => [{ "message" => { "content" => "asked again" } }] }])
      allow(h).to receive(:record_tool_call)
      allow(h).to receive(:should_stop_for_errors?).and_return(false)
    end
  end

  # The tool ran and, when it is the one that takes the text, left its mark.
  def tool_ran(session, ends:)
    session[:tts_reply_ended] = true if ends
  end

  describe OpenAIHelper do
    def run(ends:)
      h = helper(OpenAIHelper)
      allow(h).to receive(:invoke_openai_tool_function) do
        tool_ran(session, ends: ends)
        ['{"success":true}', "save_response", {}, nil]
      end
      allow(h).to receive(:inject_openai_vision_images)
      allow(h).to receive(:intercept_openai_media_generation).and_return(nil)
      call = { "id" => "c1", "function" => { "name" => "save_response", "arguments" => "{}" } }
      [h, h.process_functions("Speaker", session, [call], [], 1) { |event| events << event }]
    end

    it "ends the reply without asking again" do
      h, results = run(ends: true)

      expect(results).to eq(ended)
      expect(h).not_to have_received(:api_request)
      expect(events.last).to include("type" => "message", "content" => "DONE")
    end

    it "asks again after any other tool" do
      h, = run(ends: false)

      expect(h).to have_received(:api_request).once
    end
  end

  describe ClaudeHelper do
    def run(ends:)
      h = helper(ClaudeHelper)
      allow(h).to receive(:handle_claude_server_tool).and_return(false)
      allow(h).to receive(:invoke_claude_tool_function) do
        tool_ran(session, ends: ends)
        [{ type: "tool_result", tool_use_id: "t1", content: '{"success":true}' }, false]
      end
      call = { "id" => "t1", "name" => "save_response", "input" => {} }
      [h, h.process_functions("Speaker", session, [call], [], 1) { |event| events << event }]
    end

    it "ends the reply without asking again" do
      h, results = run(ends: true)

      expect(results).to eq(ended)
      expect(h).not_to have_received(:api_request)
    end

    it "asks again after any other tool" do
      h, = run(ends: false)

      expect(h).to have_received(:api_request).once
    end
  end

  describe CohereHelper do
    def run(ends:)
      h = helper(CohereHelper)
      allow(h).to receive(:invoke_cohere_tool_function) do
        tool_ran(session, ends: ends)
        [{ "role" => "tool", "tool_call_id" => "c1", "content" => [] }, false]
      end
      call = { "id" => "c1", "function" => { "name" => "save_translation", "arguments" => "{}" } }
      [h, h.process_functions("Speaker", session, [call], [], 1) { |event| events << event }]
    end

    it "ends the reply without asking again" do
      h, results = run(ends: true)

      expect(results).to eq(ended)
      expect(h).not_to have_received(:api_request)
    end

    it "asks again after any other tool" do
      h, = run(ends: false)

      expect(h).to have_received(:api_request).once
    end
  end

  describe DeepSeekHelper do
    def run(ends:)
      h = helper(DeepSeekHelper)
      stub_const("DeepSeekHelper::RETRY_DELAY", 0)
      allow(h).to receive(:invoke_deepseek_tool_function) do
        tool_ran(session, ends: ends)
        [{ "role" => "tool", "tool_call_id" => "c1", "name" => "save_response", "content" => "{}" }, false]
      end
      call = { "id" => "c1", "function" => { "name" => "save_response", "arguments" => "{}" } }
      [h, h.send(:process_functions, "Speaker", session, [call], [], 1) { |event| events << event }]
    end

    it "ends the reply without asking again" do
      h, results = run(ends: true)

      expect(results).to eq(ended)
      expect(h).not_to have_received(:api_request)
      expect(events.last).to include("type" => "message", "content" => "DONE")
    end

    it "asks again after any other tool" do
      h, = run(ends: false)

      expect(h).to have_received(:api_request).once
    end
  end

  describe OllamaHelper do
    def run(ends:)
      h = helper(OllamaHelper)
      stub_const("OllamaHelper::RETRY_DELAY", 0)
      allow(h).to receive(:run_tool_call) do
        tool_ran(session, ends: ends)
        ToolRun::Result.new(name: "save_response", value: '{"success":true}', images: nil, stop: false)
      end
      call = { "function" => { "name" => "save_response", "arguments" => {} } }
      [h, h.process_functions("Speaker", session, [call], [], 1) { |event| events << event }]
    end

    it "ends the reply without asking again" do
      h, results = run(ends: true)

      expect(results).to eq(ended)
      expect(h).not_to have_received(:api_request)
    end

    it "asks again after any other tool" do
      h, = run(ends: false)

      expect(h).to have_received(:api_request).once
    end
  end

  describe GrokHelper do
    def run(ends:)
      h = helper(GrokHelper)
      allow(h).to receive(:invoke_grok_tool_function) do
        tool_ran(session, ends: ends)
        [{ "call_id" => "c1", "name" => "save_response", "content" => '{"success":true}' }, false, '{"success":true}']
      end
      call = { "id" => "c1", "function" => { "name" => "save_response", "arguments" => "{}" } }
      [h, h.process_functions("Speaker", session, [call], [], 1) { |event| events << event }]
    end

    it "ends the reply without asking again" do
      h, results = run(ends: true)

      expect(results).to eq(ended)
      expect(h).not_to have_received(:api_request)
    end

    it "asks again after any other tool" do
      h, = run(ends: false)

      expect(h).to have_received(:api_request).once
    end
  end

  describe GeminiHelper do
    def run(ends:)
      h = helper(GeminiHelper)
      allow(h).to receive(:run_tool_call) do
        tool_ran(session, ends: ends)
        ToolRun::Result.new(name: "save_response", value: '{"success":true}', images: nil, stop: false)
      end
      call = { "name" => "save_response", "args" => {} }
      [h, h.process_functions("Speaker", session, [call], [], 1) { |event| events << event }]
    end

    it "ends the reply without asking again" do
      h, results = run(ends: true)

      expect(results).to eq(ended)
      expect(h).not_to have_received(:api_request)
    end

    it "asks again after any other tool" do
      h, = run(ends: false)

      expect(h).to have_received(:api_request).once
    end
  end
end
