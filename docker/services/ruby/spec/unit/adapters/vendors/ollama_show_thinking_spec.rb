# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/ollama_helper'

# The Show Thinking toggle is the one control of an Ollama model's thinking,
# and it is off unless the user turned it on.
RSpec.describe 'OllamaHelper and the Show Thinking toggle' do
  subject(:helper) do
    Class.new do
      include OllamaHelper
    end.new
  end

  def capabilities(*names)
    allow(OllamaHelper).to receive(:fetch_model_capabilities)
      .and_return({ capabilities: names, context_length: 8192, fetched_at: Time.now })
  end

  def turn(given)
    Monadic::TurnSettings.of({ "model" => "m" }.merge(given))
  end

  describe 'the think value of a request' do
    it 'tells a model that can think either way, and is on only when the toggle says so' do
      capabilities("completion", "thinking")
      expect(helper.send(:think_parameter, turn("show_thinking" => true))).to be(true)
      expect(helper.send(:think_parameter, turn("show_thinking" => "true"))).to be(true)
      expect(helper.send(:think_parameter, turn("show_thinking" => false))).to be(false)
      expect(helper.send(:think_parameter, turn("show_thinking" => "false"))).to be(false)
      expect(helper.send(:think_parameter, turn({}))).to be(false)
    end

    it 'is not sent to a model that cannot think' do
      capabilities("completion", "tools")
      expect(helper.send(:think_parameter, turn("show_thinking" => true))).to be_nil
    end
  end

  describe 'a reply from a model that thinks whatever it is told' do
    let(:chunks) do
      [{ "message" => { "thinking" => "Plan the greeting." } }, { "message" => { "content" => "Hello!" } },
       { "message" => { "content" => "" }, "done" => true }].map { |r| "#{JSON.generate(r)}\n" }
    end

    def read(parameters)
      sent = []
      res = helper.send(:process_json_data, "ChatOllama", { parameters: parameters, messages: [] }, chunks, 0) { |r| sent << r }
      [res.dig(0, "choices", 0, "message"), sent.map { |r| r["type"] }]
    end

    it 'shows the thinking as it comes and with the reply when the toggle is on' do
      message, types = read({ "show_thinking" => true })
      expect(types).to include("thinking")
      expect(message).to include("content" => "Hello!", "reasoning_content" => "Plan the greeting.")
    end

    it 'keeps the thinking off the page when the toggle is off or no setting came' do
      [{ "show_thinking" => false }, {}].each do |parameters|
        message, types = read(parameters)
        expect(types).not_to include("thinking")
        expect(message["content"]).to eq("Hello!")
        expect(message).not_to have_key("reasoning_content")
      end
    end
  end
end
