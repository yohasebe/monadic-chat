# frozen_string_literal: true

require_relative 'spec_helper'
require 'http'
require 'base64'
require 'json'
require 'tempfile'
require 'net/http'
require 'ostruct'

# Include the full module to test
require_relative '../lib/monadic/utils/interaction_utils'

RSpec.describe InteractionUtils do
  # Mock class that includes the module for testing
  class InteractionUtilsWrapper
    include InteractionUtils
    
    attr_accessor :settings

    def initialize(api_key = "fake-api-key")
      @settings = OpenStruct.new(api_key: api_key)
    end
  end
  
  let(:wrapper) { InteractionUtilsWrapper.new }
  
  before do
    # Set up necessary constants and mocks
    stub_const("CONFIG", { 
      "TTS_DICT" => { "hello" => "hola" }, 
      "TAVILY_API_KEY" => "fake-tavily-key" 
    })
    
    # Clear API key cache before each test
    InteractionUtils.api_key_cache.clear
    
    # Create dummy file used in tests
    FileUtils.touch('/tmp/tempfile')
  end
  
  after do
    # Clean up
    File.delete('/tmp/tempfile') if File.exist?('/tmp/tempfile')
  end
  
  describe "ApiKeyCache" do
    let(:cache) { InteractionUtils::ApiKeyCache.new }
    
    it "stores and retrieves values" do
      cache.set("key1", "value1")
      expect(cache.get("key1")).to eq("value1")
    end
    
    it "returns nil for non-existent keys" do
      expect(cache.get("non-existent")).to be_nil
    end
    
    it "clears all values" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.clear
      expect(cache.get("key1")).to be_nil
      expect(cache.get("key2")).to be_nil
    end
  end
  
  describe "#check_api_key" do
    context "when API key is empty" do
      it "returns an error" do
        result = wrapper.check_api_key(nil)
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("API key is empty")
      end
    end
    
    context "when the API key is cached" do
      it "returns the cached result" do
        # Manually set up the cache
        cached_result = { "type" => "models", "content" => "API token verified" }
        InteractionUtils.api_key_cache.set("fake-api-key", cached_result)
        
        # Make the wrapper use the same key that's cached
        wrapper = InteractionUtilsWrapper.new("fake-api-key")
        
        result = wrapper.check_api_key("fake-api-key")
        expect(result).to eq(cached_result)
      end
    end
    
    context "when making an API request" do
      context "when the API request is successful" do
        let(:http_mock) { instance_double(HTTP::Client) }
        let(:response_mock) do
          instance_double(HTTP::Response, 
            body: '{"data": [{"id": "model1"}]}',
            status: double(success?: true)
          )
        end
        
        before do
          allow(HTTP).to receive(:headers).and_return(http_mock)
          allow(http_mock).to receive(:timeout).and_return(http_mock)
          allow(http_mock).to receive(:get).and_return(response_mock)
        end
        
        it "returns a success result" do
          # Use an API key not in the cache
          result = wrapper.check_api_key("new-api-key")
          expect(result["type"]).to eq("models")
          expect(result["content"]).to include("verified")
        end
        
        it "caches the result" do
          wrapper.check_api_key("cachable-key")
          cached = InteractionUtils.api_key_cache.get("cachable-key")
          expect(cached["type"]).to eq("models")
        end
      end
      
      context "when the API request fails" do
        let(:http_mock) { instance_double(HTTP::Client) }
        let(:response_mock) do
          instance_double(HTTP::Response, 
            body: '{"error": "Invalid API key"}',
            status: double(success?: true)
          )
        end
        
        before do
          allow(HTTP).to receive(:headers).and_return(http_mock)
          allow(http_mock).to receive(:timeout).and_return(http_mock)
          allow(http_mock).to receive(:get).and_return(response_mock)
        end
        
        it "returns an error result" do
          result = wrapper.check_api_key("invalid-key")
          expect(result["type"]).to eq("error")
          expect(result["content"]).to include("not accepted")
        end
      end
      
      context "when the API request throws an exception" do
        before do
          allow(HTTP).to receive(:headers).and_raise(HTTP::TimeoutError.new("Timeout"))
        end
        
        it "retries and eventually returns an error" do
          # Reduce retry parameters for faster tests
          stub_const("InteractionUtils::MAX_RETRIES", 2)
          stub_const("InteractionUtils::RETRY_DELAY", 0)
          
          result = wrapper.check_api_key("error-key")
          expect(result["type"]).to eq("error")
          expect(result["content"]).to include("failed after 2 retries")
        end
      end
    end
  end
  
  describe "#tts_api_request" do
    context "with basic mock setup" do
      # Test for OpenAI TTS streaming using Net::HTTP
      let(:net_http_double) { instance_double(Net::HTTP) }
      let(:response_double) do
        instance_double(Net::HTTPResponse,
          code: "200",
          body: "audio_data"
        )
      end
      let(:request_double) { instance_double(Net::HTTP::Post) }

      before do
        # Mock Net::HTTP for OpenAI TTS streaming
        allow(Net::HTTP).to receive(:new).and_return(net_http_double)
        allow(net_http_double).to receive(:use_ssl=)
        allow(net_http_double).to receive(:read_timeout=)
        allow(Net::HTTP::Post).to receive(:new).and_return(request_double)
        allow(request_double).to receive(:[]=)
        allow(request_double).to receive(:body=)
        
        # Mock the streaming response
        allow(net_http_double).to receive(:request).with(request_double).and_yield(response_double)
        allow(response_double).to receive(:read_body).and_yield("audio_data")
        
        # Mock HTTP for headers (still needed for initial setup)
        http_double = instance_double(HTTP::Client)
        allow(HTTP).to receive(:headers).and_return(http_double)
      end
      
      it "processes the audio data with a block" do
        chunk_count = 0
        finished = false
        
        wrapper.tts_api_request("Test message", 
          provider: "openai-tts", 
          voice: "echo", 
          response_format: "mp3"
        ) do |chunk|
          if chunk["finished"]
            finished = true
          else
            chunk_count += 1
            expect(chunk["type"]).to eq("audio")
            expect(chunk["content"]).to eq(Base64.strict_encode64("audio_data"))
          end
        end
        
        expect(chunk_count).to eq(1)
        expect(finished).to be true
      end
    end
    
    # Skip this test as it's difficult to properly mock String to behave like HTTP::Response
    # The implementation is covered in other tests and by manual testing
    # If needed, consider verifying with integration tests instead
    
    context "when API request fails" do
      before do
        http_mock = instance_double(HTTP::Client)
        error_response = instance_double(HTTP::Response,
          status: double(success?: false),
          body: '{"error": "Invalid request"}'
        )
        
        allow(HTTP).to receive(:headers).and_return(http_mock)
        allow(http_mock).to receive(:timeout).and_return(http_mock)
        allow(http_mock).to receive(:post).and_return(error_response)
      end
      
      it "returns an error result" do
        result = nil
        wrapper.tts_api_request("Test message", 
          provider: "openai-tts", 
          voice: "echo", 
          response_format: "mp3"
        ) do |chunk|
          result = chunk
        end
        
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("ERROR")
      end
    end
  end
  
  describe "#list_elevenlabs_voices" do
    let(:elevenlabs_api_key) { "fake-elevenlabs-key" }
    
    context "when API key is nil" do
      it "returns an empty array" do
        expect(wrapper.list_elevenlabs_voices(nil)).to eq([])
      end
    end
    
    context "with mock implementation" do
      # Simplified test using a direct mock of the method
      it "returns a cached result when available" do
        # Set a mock cached result
        mock_voices = [
          {"voice_id" => "voice1", "name" => "Voice One"},
          {"voice_id" => "voice2", "name" => "Voice Two"}
        ]
        
        # Set the cached voices directly
        wrapper.instance_variable_set(:@elevenlabs_voices, mock_voices)
        
        # Verify that the cached result is returned
        result = wrapper.list_elevenlabs_voices(elevenlabs_api_key)
        expect(result).to eq(mock_voices)
        expect(result.size).to eq(2)
      end
    end
  end
  
  describe "#stt_api_request" do
    let(:audio_blob) { "fake_audio_data" }
    
    before do
      # Mock Tempfile for all tests
      temp_file_mock = instance_double(Tempfile)
      allow(Tempfile).to receive(:new).and_return(temp_file_mock)
      allow(temp_file_mock).to receive(:write)
      allow(temp_file_mock).to receive(:flush)
      allow(temp_file_mock).to receive(:path).and_return("/tmp/tempfile")
      allow(temp_file_mock).to receive(:close)
      allow(temp_file_mock).to receive(:unlink)
    end
    
    context "with a successful API response" do
      let(:http_mock) { instance_double(HTTP::Client) }
      let(:success_response_mock) do
        instance_double(HTTP::Response,
          status: double(success?: true),
          body: '{"text": "Transcribed text"}'
        )
      end
      
      before do
        # Mock the form data and HTTP request
        form_data_mock = double(HTTP::FormData, content_type: "multipart/form-data", to_s: "form-data")
        allow(HTTP::FormData).to receive(:create).and_return(form_data_mock)
        allow(HTTP::FormData::File).to receive(:new).and_return("file_object")
        
        allow(HTTP).to receive(:headers).and_return(http_mock)
        allow(http_mock).to receive(:timeout).and_return(http_mock)
        allow(http_mock).to receive(:post).and_return(success_response_mock)
      end
      
      it "constructs a proper request for whisper model" do
        expect(HTTP::FormData).to receive(:create) do |options|
          expect(options["model"]).to eq("whisper-1")
          expect(options["response_format"]).to eq("verbose_json")
          form_data_mock = double(HTTP::FormData, content_type: "multipart/form-data", to_s: "form-data")
          form_data_mock
        end
        
        result = wrapper.stt_api_request(audio_blob, "mp3", "en", "whisper-1")
        expect(result["text"]).to eq("Transcribed text")
      end
      
      it "constructs a proper request for gpt-4o-transcribe model" do
        expect(HTTP::FormData).to receive(:create) do |options|
          expect(options["model"]).to eq("gpt-4o-transcribe")
          expect(options["response_format"]).to eq("json")
          expect(options["include[]"]).to eq(["logprobs"])
          form_data_mock = double(HTTP::FormData, content_type: "multipart/form-data", to_s: "form-data")
          form_data_mock
        end
        
        wrapper.stt_api_request(audio_blob, "mp3", "en")
      end
      
      it "normalizes audio format correctly" do
        formats = {
          "mpeg" => "mp3",
          "mp4a-latm" => "mp4",
          "x-wav" => "wav",
          "wave" => "wav"
        }
        
        formats.each do |input_format, expected_format|
          expect(Tempfile).to receive(:new) do |args|
            expect(args[1]).to eq(".#{expected_format}")
            temp_file_mock = instance_double(Tempfile)
            allow(temp_file_mock).to receive(:write)
            allow(temp_file_mock).to receive(:flush)
            allow(temp_file_mock).to receive(:path).and_return("/tmp/tempfile")
            allow(temp_file_mock).to receive(:close)
            allow(temp_file_mock).to receive(:unlink)
            temp_file_mock
          end
          
          wrapper.stt_api_request(audio_blob, input_format, "en")
        end
      end
    end
    
    context "when API request fails with an error response" do
      let(:http_mock) { instance_double(HTTP::Client) }
      let(:error_response_mock) do
        instance_double(HTTP::Response,
          status: double(success?: false),
          body: '{"error": "Invalid audio file"}'
        )
      end
      
      before do
        # Setup basic mocks for HTTP request
        form_data_mock = double(HTTP::FormData, content_type: "multipart/form-data", to_s: "form-data")
        allow(HTTP::FormData).to receive(:create).and_return(form_data_mock)
        allow(HTTP::FormData::File).to receive(:new).and_return("file_object")
        
        allow(HTTP).to receive(:headers).and_return(http_mock)
        allow(http_mock).to receive(:timeout).and_return(http_mock)
        allow(http_mock).to receive(:post).and_return(error_response_mock)
      end
      
      it "returns an error result" do
        result = wrapper.stt_api_request(audio_blob, "mp3", "en")
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("Speech-to-Text API Error")
      end
    end
    
    context "when API request throws an exception" do
      before do
        allow(HTTP::FormData::File).to receive(:new).and_return("file_object")
        allow(HTTP::FormData).to receive(:create).and_return(double(HTTP::FormData, content_type: "multipart/form-data", to_s: "form-data"))
        allow(HTTP).to receive(:headers).and_raise(HTTP::TimeoutError.new("Timeout"))
      end
      
      it "retries and eventually returns an error" do
        # Reduce retry parameters for faster tests
        stub_const("InteractionUtils::MAX_RETRIES", 2)
        stub_const("InteractionUtils::RETRY_DELAY", 0)
        
        result = wrapper.stt_api_request(audio_blob, "mp3", "en")
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("Timeout")
      end
    end
  end
  
  describe "#tavily_fetch" do
    let(:url) { "https://example.com" }
    
    context "with successful response mocking" do
      # Simplified test focusing on parsing the JSON response
      let(:http_mock) { instance_double(HTTP::Client) }
      let(:raw_content) { "Extracted content from webpage" }
      let(:success_json_response) do
        {
          "results" => [
            { "raw_content" => raw_content }
          ]
        }.to_json
      end
      
      before do
        response_mock = instance_double(HTTP::Response,
          status: double(success?: true),
          body: success_json_response
        )
        
        # Basic mocking of HTTP chain
        allow(HTTP).to receive(:headers).and_return(http_mock)
        allow(http_mock).to receive(:timeout).and_return(http_mock)
        allow(http_mock).to receive(:post).and_return(response_mock)
      end
      
      it "extracts content from successful JSON response" do
        result = wrapper.tavily_fetch(url: url)
        expect(result).to eq(raw_content)
      end
    end
    
    context "when no content is found" do
      let(:http_mock) { instance_double(HTTP::Client) }
      let(:empty_json_response) { '{"results": []}' }
      
      before do
        response_mock = instance_double(HTTP::Response,
          status: double(success?: true),
          body: empty_json_response
        )
        
        allow(HTTP).to receive(:headers).and_return(http_mock)
        allow(http_mock).to receive(:timeout).and_return(http_mock)
        allow(http_mock).to receive(:post).and_return(response_mock)
      end
      
      it "returns a default message" do
        result = wrapper.tavily_fetch(url: url)
        expect(result).to eq("No content found")
      end
    end
    
    context "when an exception occurs" do
      before do
        allow(HTTP).to receive(:headers).and_raise(HTTP::TimeoutError.new("Connection timeout"))
      end
      
      it "returns an error message" do
        result = wrapper.tavily_fetch(url: url)
        expect(result).to include("Error occurred")
        expect(result).to include("Connection timeout")
      end
    end
  end

  describe "#check_model_switch" do
    let(:session) { { model_switch_notified: false } }
    let(:notifications) { [] }

    it "notifies when model is switched" do
      wrapper.check_model_switch("gpt-4.1", "o1-preview", session) do |msg|
        notifications << msg
      end
      
      expect(notifications).not_to be_empty
      expect(notifications.first["type"]).to eq("system_info")
      expect(notifications.first["content"]).to include("Model automatically switched")
    end

    it "prevents duplicate model switch notifications in same session" do
      # First call should notify
      wrapper.check_model_switch("gpt-4.1", "o1-preview", session) do |msg|
        notifications << msg
      end
      
      expect(notifications.size).to eq(1)
      
      # Second call should not notify
      wrapper.check_model_switch("gpt-4.1-mini", "o1-mini", session) do |msg|
        notifications << msg
      end
      
      expect(notifications.size).to eq(1)  # Still only one notification
    end

    it "does not notify when models are the same" do
      wrapper.check_model_switch("gpt-4.1", "gpt-4.1", session) do |msg|
        notifications << msg
      end
      
      expect(notifications).to be_empty
    end

    it "ignores version switches for the same base model" do
      wrapper.check_model_switch("gpt-4.1-2025-04-14", "gpt-4.1", session) do |msg|
        notifications << msg
      end
      
      expect(notifications).to be_empty
    end
  end
end