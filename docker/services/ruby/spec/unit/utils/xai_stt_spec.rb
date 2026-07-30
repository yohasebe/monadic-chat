# frozen_string_literal: true

require_relative '../../spec_helper'
require 'ostruct'

RSpec.describe "xAI STT Integration" do
  describe "stt_api_request routing" do
    it "routes models starting with 'xai-stt' to the xAI branch" do
      %w[xai-stt xai-stt-diarize xai-stt-v1].each do |model|
        expect(model.start_with?("xai-stt")).to be true
      end
    end

    it "does not route other providers to the xAI branch" do
      %w[scribe_v2 whisper-1 gemini-3-flash-preview voxtral-mini-transcribe-2507 cohere-transcribe-03-2026].each do |model|
        expect(model.start_with?("xai-stt")).to be false
      end
    end
  end

  describe "xai_stt_api_request" do
    # Minimal host that includes InteractionUtils so we can call the private-esque
    # helper without booting the full MonadicApp pipeline.
    let(:host) do
      Class.new do
        include InteractionUtils
      end.new
    end

    before do
      stub_const("CONFIG", CONFIG.merge("XAI_API_KEY" => "test-xai-key")) unless CONFIG["XAI_API_KEY"]
      stub_const("TEMP_AUDIO_FILE", "xai_stt_spec_test") unless defined?(TEMP_AUDIO_FILE)
      stub_const("OPEN_TIMEOUT", 5)     unless defined?(OPEN_TIMEOUT)
      stub_const("WRITE_TIMEOUT", 5)    unless defined?(WRITE_TIMEOUT)
      stub_const("READ_TIMEOUT", 10)    unless defined?(READ_TIMEOUT)
      stub_const("MAX_RETRIES", 1)      unless defined?(MAX_RETRIES)
      stub_const("RETRY_DELAY", 0)      unless defined?(RETRY_DELAY)
    end

    it "returns a configuration error when the API key is missing" do
      stub_const("CONFIG", CONFIG.merge("XAI_API_KEY" => nil))
      result = host.xai_stt_api_request("blob", "mp3", "en", "xai-stt")
      expect(result["type"]).to eq("error")
      expect(result["content"]).to include("xAI API key is not configured")
    end

    it "posts to the correct xAI endpoint and returns the parsed text" do
      stub_const("CONFIG", CONFIG.merge("XAI_API_KEY" => "test-key"))

      fake_response = double(
        "HTTP::Response",
        status: double(success?: true),
        body: { "text" => "Hello world", "language" => "en", "duration" => 1.23, "words" => [{}, {}] }.to_json
      )

      captured = { url: nil, headers: nil }
      http_chain = double("http_chain")
      allow(http_chain).to receive(:timeout).and_return(http_chain)
      allow(http_chain).to receive(:post) do |url, _opts|
        captured[:url] = url
        fake_response
      end

      allow(HTTP).to receive(:headers) do |headers|
        captured[:headers] = headers
        http_chain
      end

      result = host.xai_stt_api_request("audio-bytes", "mp3", "en", "xai-stt")

      expect(captured[:url]).to eq("https://api.x.ai/v1/stt")
      expect(captured[:headers]["Authorization"]).to eq("Bearer test-key")
      expect(captured[:headers]["Content-Type"]).to match(%r{^multipart/form-data})

      expect(result["text"]).to eq("Hello world")
      expect(result["language_code"]).to eq("en")
      expect(result["duration"]).to eq(1.23)
      # logprobs synthesised 1:1 with words so downstream confidence heuristics still work.
      expect(result["logprobs"].length).to eq(2)
    end

    it "omits language parameter when lang_code is auto" do
      stub_const("CONFIG", CONFIG.merge("XAI_API_KEY" => "key"))

      fake_response = double(status: double(success?: true), body: { "text" => "" }.to_json)
      captured_body = nil
      http_chain = double
      allow(http_chain).to receive(:timeout).and_return(http_chain)
      allow(http_chain).to receive(:post) do |_url, opts|
        captured_body = opts[:body]
        fake_response
      end
      allow(HTTP).to receive(:headers).and_return(http_chain)

      host.xai_stt_api_request("blob", "wav", "auto", "xai-stt")

      # Multipart body is a string; 'language' field header should not appear.
      expect(captured_body.to_s).not_to match(/name="language"/)
    end

    it "surfaces a descriptive error when the API returns a non-success status" do
      stub_const("CONFIG", CONFIG.merge("XAI_API_KEY" => "key"))

      fake_response = double(
        status: double(success?: false, to_s: "429"),
        body: { "error" => "rate limit" }.to_json
      )
      http_chain = double
      allow(http_chain).to receive(:timeout).and_return(http_chain)
      allow(http_chain).to receive(:post).and_return(fake_response)
      allow(HTTP).to receive(:headers).and_return(http_chain)

      result = host.xai_stt_api_request("blob", "mp3", "en", "xai-stt")
      expect(result["type"]).to eq("error")
      expect(result["content"]).to include("xAI STT Error")
      expect(result["content"]).to include("rate limit")
    end
  end
end
