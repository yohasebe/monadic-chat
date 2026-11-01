# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/tts_utils"

# The request each TTS selector value builds, from the value to the URL and
# body sent: the model comes from ttsChoices, and how ElevenLabs models are
# sent from the model's entry (endpoint, latency option, previous_text).
RSpec.describe "TTS request shapes", :no_api do
  let(:host) do
    Class.new do
      include InteractionUtils
      def settings = Struct.new(:api_key).new("sk-test")
    end.new
  end
  let(:sent) { [] }

  before do
    stub_const("CONFIG", CONFIG.merge("ELEVENLABS_API_KEY" => "el-test", "OPENAI_API_KEY" => "sk-test"))
    chain = double("http")
    allow(HTTP).to receive(:headers).and_return(chain)
    allow(chain).to receive(:timeout).and_return(chain)
    allow(chain).to receive(:post) do |url, json:|
      sent << [url, json]
      double(status: double(success?: true), body: "ID3audio")
    end
  end

  def speak(provider, previous_text: nil)
    host.tts_api_request("Hello.", provider: provider, voice: "v1", response_format: "mp3", previous_text: previous_text)
    sent.last
  end

  it "sends Eleven v3 to the convert endpoint, without previous_text" do
    url, body = speak("elevenlabs-v3", previous_text: "Hi.")
    expect(url).to eq("https://api.elevenlabs.io/v1/text-to-speech/v1?output_format=mp3_44100_128")
    expect(body).to include("model_id" => "eleven_v3")
    expect(body).not_to have_key("previous_text")
  end

  it "streams the other ElevenLabs models with the latency option and previous_text" do
    { "elevenlabs-flash" => "eleven_flash_v2_5", "elevenlabs-multilingual" => "eleven_multilingual_v2",
      "elevenlabs" => "eleven_flash_v2_5" }.each do |label, model|
      url, body = speak(label, previous_text: "Hi.")
      expect(url).to eq("https://api.elevenlabs.io/v1/text-to-speech/v1/stream?output_format=mp3_44100_128&optimize_streaming_latency=3"), label
      expect(body).to include("model_id" => model, "previous_text" => "Hi."), label
    end
  end

  it "streams Eleven v4 and v4 Turbo without the latency option they refuse" do
    { "elevenlabs-v4" => "eleven_v4", "elevenlabs-v4-turbo" => "eleven_v4_turbo" }.each do |label, model|
      url, body = speak(label, previous_text: "Hi.")
      expect(url).to eq("https://api.elevenlabs.io/v1/text-to-speech/v1/stream?output_format=mp3_44100_128"), label
      expect(body).to include("model_id" => model, "previous_text" => "Hi."), label
    end
  end

  it "sends each OpenAI value its own model, and the saved value 'openai' the 4o model" do
    { "openai-tts-4o" => "gpt-4o-mini-tts-2025-12-15", "openai-tts-hd" => "tts-1-hd", "openai-tts" => "tts-1",
      "openai" => "gpt-4o-mini-tts-2025-12-15" }.each do |label, model|
      url, body = speak(label)
      expect(url).to end_with("/audio/speech"), label
      expect(body["model"] || body[:model]).to eq(model), label
    end
  end

  it "refuses a value it does not know instead of sending it elsewhere" do
    result = host.tts_api_request("Hello.", provider: "no-such-tts", voice: "v1", response_format: "mp3")
    expect(result).to include("type" => "error")
    expect(sent).to be_empty
  end
end
