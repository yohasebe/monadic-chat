# frozen_string_literal: true

require "spec_helper"
require "ostruct"
require_relative "../../../lib/monadic/utils/interaction_utils"

# A failed OpenAI speech-to-text request returns an error whose text carries
# the provider's reason, not a bare "Speech-to-Text API Error".
RSpec.describe "stt_api_request error messages" do
  let(:host) do
    Class.new do
      include InteractionUtils

      def settings
        OpenStruct.new(api_key: "test-key")
      end
    end.new
  end

  def respond_with(status:, body:)
    response = double("response", status: double("status", success?: false, to_s: status.to_s), body: body)
    chain = double("http")
    allow(chain).to receive(:timeout).and_return(chain)
    allow(chain).to receive(:post).and_return(response)
    allow(HTTP).to receive(:headers).and_return(chain)
  end

  before do
    allow(Monadic::Utils::ModelSpec).to receive(:resolve_deprecated_model) { |m| m }
    allow(Monadic::Utils::ModelSpec).to receive(:stt_provider).and_return(nil)
  end

  it "includes the provider's error details from a JSON body" do
    respond_with(status: 401, body: { "error" => { "message" => "Incorrect API key provided", "code" => "invalid_api_key" } }.to_json)
    result = host.stt_api_request("not audio", "mp3", "en", "spec-stt-model")
    expect(result["type"]).to eq("error")
    expect(result["content"]).to start_with("Speech-to-Text API Error: ")
    expect(result["content"]).to include("Incorrect API key provided")
  end

  it "falls back to the status and body when the body is not JSON" do
    respond_with(status: 502, body: "Bad Gateway")
    result = host.stt_api_request("not audio", "mp3", "en", "spec-stt-model")
    expect(result["content"]).to eq("Speech-to-Text API Error: 502 - Bad Gateway")
  end
end
