# frozen_string_literal: true

require "spec_helper"
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
end
