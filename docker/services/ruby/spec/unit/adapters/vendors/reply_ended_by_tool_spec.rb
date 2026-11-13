# frozen_string_literal: true

require_relative "../../../spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"
require_relative "../../../../lib/monadic/adapters/vendors/cohere_helper"
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
end
