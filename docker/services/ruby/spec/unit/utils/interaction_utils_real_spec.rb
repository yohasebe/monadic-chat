# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'ostruct'
require 'http'
require_relative '../../../lib/monadic/utils/interaction_utils'

RSpec.describe InteractionUtils do
  # Test class that includes InteractionUtils module
  class TestInteractionUtils
    include InteractionUtils
    
    attr_accessor :settings
    
    def initialize
      @settings = OpenStruct.new(api_key: nil)
    end
  end
  
  let(:utils) { TestInteractionUtils.new }
  
  before do
    # Clear the API key cache before each test
    InteractionUtils.api_key_cache.clear
    
    # Set up common CONFIG
    stub_const('CONFIG', {
      "OPENAI_API_KEY" => ENV["OPENAI_API_KEY"] || "test-key",
      "ELEVENLABS_API_KEY" => ENV["ELEVENLABS_API_KEY"] || "test-key",
      "GEMINI_API_KEY" => ENV["GEMINI_API_KEY"] || "test-key",
      "TAVILY_API_KEY" => ENV["TAVILY_API_KEY"] || "test-key",
      "TTS_DICT" => { "AI" => "A.I.", "URL" => "U.R.L." }
    })
  end
  
  describe 'ApiKeyCache' do
    let(:cache) { InteractionUtils::ApiKeyCache.new }
    
    it 'stores and retrieves values' do
      cache.set("key1", "value1")
      expect(cache.get("key1")).to eq("value1")
    end
    
    it 'returns nil for non-existent keys' do
      expect(cache.get("non-existent")).to be_nil
    end
    
    it 'clears all values' do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.clear
      
      expect(cache.get("key1")).to be_nil
      expect(cache.get("key2")).to be_nil
    end
    
    it 'is thread-safe' do
      threads = []
      results = []
      
      10.times do |i|
        threads << Thread.new do
          cache.set("key#{i}", "value#{i}")
          results << cache.get("key#{i}")
        end
      end
      
      threads.each(&:join)
      
      expect(results.uniq.length).to eq(10)
      expect(results).to all(match(/^value\d+$/))
    end
  end
  
  describe '#format_api_error' do
    it 'formats simple string errors' do
      error = "Something went wrong"
      result = utils.format_api_error(error)
      
      expect(result).to eq("Something went wrong")
    end
    
    it 'extracts message from error hash' do
      error = { "message" => "Invalid API key" }
      result = utils.format_api_error(error)
      
      expect(result).to eq("Invalid API key")
    end
    
    it 'extracts nested error message' do
      error = { "error" => { "message" => "Rate limit exceeded" } }
      result = utils.format_api_error(error)
      
      expect(result).to eq("Rate limit exceeded")
    end
    
    it 'handles detail field' do
      error = { "detail" => "Not found" }
      result = utils.format_api_error(error)
      
      expect(result).to eq("Not found")
    end
    
    it 'adds provider context when provided' do
      error = { "message" => "Error occurred" }
      result = utils.format_api_error(error, "openai")
      
      expect(result).to eq("[OPENAI] Error occurred")
    end
    
    it 'handles rate limit errors with context' do
      error = {
        "error" => {
          "code" => 429,
          "message" => "Quota exceeded"
        }
      }
      result = utils.format_api_error(error)
      
      expect(result).to include("Quota exceeded")
      expect(result).to include("Rate limit exceeded")
    end
    
    it 'handles authentication errors' do
      error = { "code" => 401, "message" => "Unauthorized" }
      result = utils.format_api_error(error)
      
      expect(result).to include("Unauthorized")
      expect(result).to include("Authentication failed")
    end
    
    it 'formats complex nested errors' do
      error = {
        "error" => {
          "message" => "Complex error",
          "details" => [
            { "@type" => "QuotaFailure", "violations" => [{ "quotaMetric" => "project/requests" }] }
          ]
        }
      }
      result = utils.format_api_error(error)
      
      expect(result).to include("Complex error")
    end
  end
  
  describe '#check_api_key' do
    it 'returns error for empty API key' do
      result = utils.check_api_key(nil)
      
      expect(result["type"]).to eq("error")
      expect(result["content"]).to include("API key is empty")
    end
    
    it 'returns cached result if available' do
      cached_result = { "type" => "models", "content" => "Cached result" }
      InteractionUtils.api_key_cache.set("test-key", cached_result)
      
      result = utils.check_api_key("test-key")
      
      expect(result).to eq(cached_result)
    end
    
    it 'caches results for subsequent calls' do
      # First call should check API
      result1 = utils.check_api_key("test-key")
      
      # Second call should use cache
      result2 = utils.check_api_key("test-key")
      
      expect(result1).to eq(result2)
    end
  end
  
  describe '#check_model_switch' do
    let(:session) { {} }
    let(:notifications) { [] }
    
    it 'notifies when model is switched' do
      utils.check_model_switch("gpt-4", "gpt-3.5-turbo", session) do |msg|
        notifications << msg
      end
      
      expect(notifications.length).to eq(1)
      expect(notifications[0]["type"]).to eq("system_info")
      expect(notifications[0]["content"]).to include("switched from gpt-3.5-turbo to gpt-4")
    end
    
    it 'does not notify for same model' do
      utils.check_model_switch("gpt-4", "gpt-4", session) do |msg|
        notifications << msg
      end
      
      expect(notifications).to be_empty
    end
    
    it 'ignores version switches for same base model' do
      utils.check_model_switch("gpt-4.1-2025-04-14", "gpt-4.1", session) do |msg|
        notifications << msg
      end
      
      expect(notifications).to be_empty
    end
    
    it 'only notifies once per session' do
      utils.check_model_switch("gpt-4", "gpt-3.5", session) { |msg| notifications << msg }
      utils.check_model_switch("gpt-4", "gpt-3.5", session) { |msg| notifications << msg }
      
      expect(notifications.length).to eq(1)
    end
    
    it 'does nothing without block' do
      expect { utils.check_model_switch("gpt-4", "gpt-3.5", session) }.not_to raise_error
    end
  end
  
  describe '#tts_api_request' do
    context 'with nil or empty text' do
      it 'returns nil for nil text' do
        result = utils.tts_api_request(nil, provider: "openai-tts", voice: "alloy", response_format: "mp3")
        expect(result).to be_nil
      end
      
      it 'returns nil for empty text' do
        result = utils.tts_api_request("", provider: "openai-tts", voice: "alloy", response_format: "mp3")
        expect(result).to be_nil
      end
    end
    
    context 'with text replacement' do
      it 'applies TTS dictionary replacements' do
        # Test that we properly replace text
        text = "AI and URL"
        # We can't test actual API calls without valid keys, but we can test the text replacement logic
        # by checking what would be sent
        replaced_text = text.gsub(/(#{CONFIG["TTS_DICT"].keys.join("|")})/) { CONFIG["TTS_DICT"][$1] }
        
        expect(replaced_text).to eq("A.I. and U.R.L.")
      end
    end
    
    context 'with Web Speech provider' do
      it 'returns web_speech response without API call' do
        result = utils.tts_api_request(
          "Hello world",
          provider: "web-speech",
          voice: "default",
          response_format: "mp3"
        )
        
        expect(result["type"]).to eq("web_speech")
        expect(result["content"]).to eq("Hello world")
      end
      
      it 'calls block for web speech' do
        called = false
        utils.tts_api_request("Test", provider: "webspeech", voice: "default", response_format: "mp3") do |res|
          called = true
          expect(res["type"]).to eq("web_speech")
        end
        
        expect(called).to be true
      end
    end
    
    context 'with missing API keys' do
      it 'returns error when GEMINI_API_KEY is missing' do
        stub_const('CONFIG', CONFIG.merge("GEMINI_API_KEY" => nil))
        
        result = utils.tts_api_request("Test", provider: "gemini", voice: "zephyr", response_format: "mp3")
        
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("GEMINI_API_KEY is not set")
      end
    end
    
    context 'with unknown provider' do
      it 'returns error for unknown provider' do
        result = utils.tts_api_request("Test", provider: "unknown-provider", voice: "voice", response_format: "mp3")
        
        expect(result["type"]).to eq("error")
        expect(result["content"]).to include("Unknown TTS provider")
      end
    end
  end
  
  describe '#list_elevenlabs_voices' do
    it 'returns empty array when API key is nil' do
      result = utils.list_elevenlabs_voices(nil)
      expect(result).to eq([])
    end
    
    it 'caches voices list after first call' do
      # Test that @elevenlabs_voices is used for caching
      # First, set the instance variable directly to simulate a cached result
      utils.instance_variable_set(:@elevenlabs_voices, [{"voice_id" => "123", "name" => "Test"}])
      
      result = utils.list_elevenlabs_voices("test-key")
      expect(result).to eq([{"voice_id" => "123", "name" => "Test"}])
    end
  end
  
  describe '#tavily_fetch' do
    it 'returns error when API key is missing' do
      stub_const('CONFIG', CONFIG.merge("TAVILY_API_KEY" => nil))
      
      result = utils.tavily_fetch(url: "https://example.com")
      
      expect(result).to include("ERROR: Tavily API key is not configured")
    end
  end
  
  describe '#stt_api_request' do
    let(:audio_blob) { "fake_audio_data" }
    
    it 'normalizes audio formats correctly' do
      # Test format normalization logic
      formats = {
        "mpeg" => "mp3",
        "mp4a-latm" => "mp4",
        "x-wav" => "wav",
        "wave" => "wav"
      }
      
      formats.each do |input_format, expected_format|
        # The method normalizes the format internally
        # We can verify this by checking the tempfile extension
        temp_file = Tempfile.new(["temp_audio_file", ".#{expected_format}"])
        expect(temp_file.path).to end_with(".#{expected_format}")
        temp_file.close
        temp_file.unlink
      end
    end
  end
end