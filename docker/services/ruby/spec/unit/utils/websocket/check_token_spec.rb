# frozen_string_literal: true

require "spec_helper"
require "json"
require "securerandom"
require_relative "../../../../lib/monadic/utils/secret_references"
require_relative "../../../../lib/monadic/utils/websocket"

# CHECK_TOKEN tells the page which keys were left unset because their
# 1Password references could not be read, by name only.
RSpec.describe "handle_ws_check_token" do
  let(:host) do
    Class.new do
      include WebSocketHelper
      attr_reader :sent

      def send_to_client(_connection, message)
        (@sent ||= []) << message
      end

      def check_api_key(_token)
        { "type" => "success", "content" => "ok" }
      end
    end.new
  end

  after { Monadic::Utils::SecretReferences.reset! }

  def check_token
    stub_const("CONFIG", CONFIG.merge("OPENAI_API_KEY" => nil, "ERROR" => nil))
    host.send(:handle_ws_check_token, nil, {}, {})
    host.sent
  end

  it "names the keys whose references could not be read" do
    Monadic::Utils::SecretReferences.record_unresolved(%w[OPENAI_API_KEY XAI_API_KEY])
    notice = check_token.find { |m| m["type"] == "secret_references_unresolved" }
    expect(notice).to eq("type" => "secret_references_unresolved", "keys" => %w[OPENAI_API_KEY XAI_API_KEY])
  end

  it "says nothing about references when all were read" do
    expect(check_token.map { |m| m["type"] }).not_to include("secret_references_unresolved")
  end

  describe "the key itself" do
    let(:key) { "sk-test-MARKER-#{SecureRandom.hex(8)}" }

    def verify(obj = {})
      checked = []
      host.define_singleton_method(:check_api_key) do |token|
        checked << token
        { "type" => "models", "content" => "API token verified" }
      end
      stub_const("CONFIG", CONFIG.merge("OPENAI_API_KEY" => key, "ERROR" => nil))
      host.send(:handle_ws_check_token, nil, obj, {})
      [host.sent, checked]
    end

    it "is never sent to the page, neither whole nor its tail" do
      sent, = verify
      expect(sent.map { |m| m["type"] }).to include("token_verified")
      everything = JSON.generate(sent)
      expect(everything).not_to include(key)
      expect(everything).not_to include(key[-8..]) # nor its tail
    end

    it "is the server's own: a key sent by the page is not used or echoed" do
      sent, checked = verify("contents" => "sk-from-the-page", "ui_language" => "en")
      expect(checked).to eq([key])
      expect(JSON.generate(sent)).not_to include("sk-from-the-page")
    end
  end
end
