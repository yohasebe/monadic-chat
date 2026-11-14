# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/workspace"

# With Show Thinking off (the user's toggle, or the app's default for a
# model that has no toggle), the model's thinking does not reach the page
# while the reply streams. The real streaming handler; only the provider
# call is played by a fake app.
RSpec.describe "Streaming a reply with Show Thinking off" do
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:broadcasts) { [] }
  let(:queue) { Queue.new }
  let(:session) { { parameters: {}, messages: [], chat_id: Monadic::Workspace::Ids.generate(:chat) } }

  def streamed(show_thinking)
    app = Object.new
    app.define_singleton_method(:api_request) do |_role, _session, &block|
      block.call({ "type" => "thinking", "content" => "PONDERING" })
      block.call({ "type" => "reasoning", "content" => "WEIGHING" })
      block.call({ "type" => "fragment", "content" => "ANSWER" })
      [{ "choices" => [{ "message" => { "content" => "ANSWER" }, "finish_reason" => "stop" }] }]
    end
    app.define_singleton_method(:settings) { {} }
    stub_const("APPS", { "FakeApp" => app })
    allow(host).to receive(:send_or_broadcast) { |msg, *_| broadcasts << msg }
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    message = { "message" => "hello", "app_name" => "FakeApp" }
    message["show_thinking"] = show_thinking unless show_thinking.nil?
    wait_for_answer_made(host.send(:handle_ws_streaming, nil, message, session, queue))
    broadcasts.join("\n")
  end

  it "sends the reply and leaves the thinking out" do
    [false, "false"].each do |off|
      broadcasts.clear
      sent = streamed(off)
      expect(sent).to include("ANSWER")
      expect(sent).not_to include("PONDERING")
      expect(sent).not_to include("WEIGHING")
    end
  end

  it "sends the thinking when the setting is on or not given" do
    [true, nil].each do |on|
      broadcasts.clear
      expect(streamed(on)).to include("PONDERING", "WEIGHING", "ANSWER")
    end
  end

  describe "the app's default" do
    it "reaches the page as false, not as nothing" do
      app = double("app", settings: { "app_name" => "Quick", "show_thinking" => false, "auto_speech" => true })
      stub_const("APPS", { "Quick" => app })
      allow(Monadic::Substitution::Vocabulary).to receive(:describe_for).and_return([])

      data = host.send(:prepare_apps_data, "en")

      expect(data["Quick"]["show_thinking"]).to be(false)
    end

    it "is declared off by the apps that answer by voice" do
      root = File.expand_path("../../../../apps", __dir__)
      files = %w[voice_interpreter voice_chat language_practice language_practice_plus]
              .flat_map { |dir| Dir[File.join(root, dir, "*.mdsl")] }

      expect(files).not_to be_empty
      missing = files.reject { |file| File.read(file).match?(/^\s*show_thinking false$/) }
      expect(missing.map { |file| File.basename(file) }).to eq([])
    end
  end
end
