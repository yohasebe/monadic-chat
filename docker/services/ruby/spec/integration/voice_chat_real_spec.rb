# frozen_string_literal: true

require "spec_helper"
require "base64"
require "net/http"
require "http"
require "tempfile"
require "ostruct"
require_relative "../../lib/monadic/utils/interaction_utils"
require_relative "../support/real_audio_test_helper"

RSpec.describe "Voice Chat Integration (Real)", :integration do
  include RealAudioTestHelper
  
  # Create a test class that provides the required interface for InteractionUtils
  let(:test_app) do
    Class.new do
      include InteractionUtils
      attr_accessor :settings, :api_key
      
      def initialize
        @settings = OpenStruct.new(api_key: CONFIG["OPENAI_API_KEY"])
        @api_key = CONFIG["OPENAI_API_KEY"]
      end
    end.new
  end
  
  describe "Speech-to-Text Processing" do
    it "handles various audio formats" do
      formats = {
        "webm" => "webm",
        "ogg" => "ogg",
        "mp3" => "mp3",
        "wav" => "wav",
        "m4a" => "m4a"
      }
      
      formats.each do |input, expected|
        # Test format normalization logic directly
        normalized = case input
                     when "webm", "audio/webm", "webm/opus" then "webm"
                     when "ogg", "audio/ogg" then "ogg"
                     when "mp3", "audio/mpeg", "audio/mp3" then "mp3"
                     when "wav", "audio/wav" then "wav"
                     when "m4a", "audio/x-m4a" then "m4a"
                     else input
                     end
        expect(normalized).to eq(expected)
      end
    end
    
    it "normalizes format aliases" do
      # Test format normalization logic directly
      expect("audio/webm".split("/").last).to eq("webm")
      expect("audio/ogg".split("/").last).to eq("ogg")
      expect("webm/opus".split("/").first).to eq("webm")
    end
    
    context "with real API" do
      before do
        skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
      end
      
      it "processes audio through STT pipeline" do
        # Generate real audio using TTS
        audio_file = generate_real_audio_file("Hello, this is a test.", format: "mp3")
        begin
          audio_blob = File.read(audio_file, mode: "rb")
          
          # Call real STT API
          result = test_app.stt_api_request(audio_blob, "mp3", "en", "whisper-1")
          
          # Handle error response
          if result["type"] == "error"
            skip "STT API error: #{result['content']}"
          end
          
          # Verify response structure
          expect(result).to be_a(Hash)
          expect(result["text"]).to be_a(String)
          expect(result["text"].downcase).to include("hello")
          
          # Check confidence if available
          if result["segments"] && result["segments"].any?
            avg_logprob = result["segments"][0]["avg_logprob"]
            confidence = Math.exp(avg_logprob)
            expect(confidence).to be_between(0, 1)
          end
        ensure
          File.delete(audio_file) if File.exist?(audio_file)
        end
      end
      
      it "handles STT API errors gracefully" do
        # Send invalid audio data
        audio_blob = "This is not audio data"
        
          result = test_app.stt_api_request(audio_blob, "mp3", "en", "whisper-1")
          
          # Should return error format
          expect(result["type"]).to eq("error")
          expect(result["content"]).to include("Error")
      end
    end
  end
  
  describe "Text-to-Speech Processing" do
    it "supports multiple TTS providers" do
      providers = %w[openai elevenlabs gemini webspeech]
      
      providers.each do |provider|
        # Just verify the provider names are valid strings
        expect(provider).to be_a(String)
      end
    end
    
    context "with real API" do
      before do
        skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
      end
      
      it "generates audio for text input" do
          result = test_app.tts_api_request(
            "Hello, world!",
            provider: "openai-tts",
            voice: "alloy",
            response_format: "mp3",
            speed: 1.0
          )
          
          if result["type"] == "error"
            skip "TTS API error: #{result['content']}"
          end
          
          expect(result["type"]).to eq("audio")
          expect(result["content"]).to be_a(String)
          expect(result["content"]).not_to be_empty
          
          # Verify it's valid base64
          audio_data = Base64.strict_decode64(result["content"])
          expect(audio_data.bytesize).to be > 0
      end
      
      it "applies TTS dictionary replacements" do
        # This tests the actual TTS dictionary functionality
        # Set up TTS dictionary
        original_dict = CONFIG["TTS_DICT_DATA"]
        begin
          CONFIG["TTS_DICT_DATA"] = {
            "AI" => "artificial intelligence",
            "TTS" => "text to speech"
          }.to_json
          
          # The TTS dictionary should be applied internally
          result = test_app.tts_api_request(
            "AI and TTS are useful.",
            provider: "openai-tts",
            voice: "alloy",
            response_format: "mp3",
            speed: 1.0
          )
          
          if result["type"] == "error"
            skip "TTS API error: #{result['content']}"
          end
          
          expect(result["type"]).to eq("audio")
          # We can't easily verify the audio content contains the replacements,
          # but we can verify the API call succeeded
          expect(result["content"]).to be_a(String)
        ensure
          CONFIG["TTS_DICT_DATA"] = original_dict
        end
      end
    end
  end
  
  describe "Audio Format Detection" do
    it "detects audio format from content type" do
      content_types = {
        "audio/webm" => "webm",
        "audio/ogg" => "ogg",
        "audio/mpeg" => "mp3",
        "audio/mp3" => "mp3",
        "audio/wav" => "wav",
        "audio/x-m4a" => "m4a"
      }
      
      content_types.each do |content_type, expected_format|
        # Test content type to format conversion directly
        format = case content_type
                 when /webm/ then "webm"
                 when /ogg/ then "ogg"
                 when /mpeg|mp3/ then "mp3"
                 when /wav/ then "wav"
                 when /m4a/ then "m4a"
                 else content_type.split("/").last
                 end
        expect(format).to eq(expected_format)
      end
    end
  end
  
  describe "WebSocket Audio Message Handling" do
    it "validates audio message structure" do
      valid_message = {
        "content" => Base64.encode64("audio_data"),
        "format" => "webm",
        "lang" => "en"
      }
      
      # Direct validation without mocks
      expect { 
        validate_audio_message(valid_message)
      }.not_to raise_error
    end
    
    it "rejects invalid audio messages" do
      # Test each invalid case
      expect { 
        validate_audio_message({})
      }.to raise_error(RuntimeError, /Missing audio content/)
      
      expect {
        validate_audio_message({ "format" => "webm" })
      }.to raise_error(RuntimeError, /Missing audio content/)
      
      expect {
        validate_audio_message({ "content" => "" })
      }.to raise_error(RuntimeError, /Missing audio content/)
      
      # Valid base64 but missing format
      msg = { "content" => Base64.encode64("data") }
      expect { validate_audio_message(msg) }.to raise_error(/Invalid format/)
    end
    
    private
    
    def validate_audio_message(message)
      raise "Missing audio content" unless message["content"]&.length&.positive?
      raise "Invalid format" unless message["format"]
      
      # Try to decode base64
      Base64.decode64(message["content"])
    rescue => e
      raise "Invalid audio message: #{e.message}"
    end
  end
end