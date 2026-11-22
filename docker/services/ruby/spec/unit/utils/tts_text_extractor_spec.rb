# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/utils/tts_text_extractor"

# The text an app speaks from a tool's parameter (tts_target), and the reply
# that tool ends.
RSpec.describe Monadic::Utils::TtsTextExtractor do
  let(:session) { {} }
  let(:events) { [] }

  before do
    stub_const("APPS", { "Speaker" => double(settings: { tts_target: [:tool_param, "save_response", "message"] }),
                         "Plain" => double(settings: {}) })
  end

  def extract(function_name: "save_response", function_return: '{"success":true}', app: "Speaker", arguments: { message: "Hello" })
    described_class.extract_tts_text(app: app, function_name: function_name, argument_hash: arguments,
                                     session: session, function_return: function_return)
  end

  it "keeps the parameter's text to speak" do
    expect(extract).to eq("Hello")
    expect(session[:tts_text]).to eq("Hello")
  end

  it "keeps nothing for another tool, an app without a target, or an empty text" do
    extract(function_name: "load_context")
    extract(app: "Plain")
    extract(arguments: { message: " " })

    expect(session).to be_empty
  end

  describe "the reply the tool ends" do
    it "is ended once when the tool succeeded, with no text of the model's" do
      extract
      results = described_class.reply_ended(session) { |event| events << event }

      expect(results).to eq([{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "" } }] }])
      expect(events).to eq([{ "type" => "message", "content" => "DONE", "finish_reason" => "stop" }])
      expect(described_class.reply_ended(session)).to be_nil
    end

    it "is ended when the tool returns a Hash that says it succeeded" do
      extract(function_return: { success: true })

      expect(described_class.reply_ended(session)).not_to be_nil
    end

    it "goes on when the tool failed, returned something else, or was another tool" do
      extract(function_return: '{"success":false,"error":"Nothing was changed"}')
      extract(function_return: "Tool Execution Error: missing keyword: :message")
      extract(function_return: nil)
      extract(function_name: "load_context")

      expect(described_class.reply_ended(session) { |event| events << event }).to be_nil
      expect(events).to be_empty
    end
  end
end
