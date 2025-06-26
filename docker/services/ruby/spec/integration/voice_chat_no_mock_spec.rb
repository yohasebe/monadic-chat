# frozen_string_literal: true

require "spec_helper"
require "base64"
require "net/http"
require "http"
require "tempfile"
require "ostruct"
require_relative "../../lib/monadic/utils/interaction_utils"
require_relative "../support/real_audio_test_helper"

RSpec.describe "Voice Chat Integration (No Mocks)", :integration do
  include InteractionUtils
  include RealAudioTestHelper
  
  before do
    skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
    
    # Ensure API key is available in environment for InteractionUtils
    ENV['OPENAI_API_KEY'] = CONFIG["OPENAI_API_KEY"]
  end
  
  after do
    # Clean up environment
    ENV.delete('OPENAI_API_KEY')
  end
  
  describe "Speech-to-Text Processing with Real API" do
    it "processes real audio through STT pipeline" do
      # Generate real audio using TTS
      audio_file = generate_real_audio_file("Hello, this is a test message.", format: "mp3")
      audio_blob = File.read(audio_file, mode: "rb")
      
      # Call real STT API
      result = stt_api_request(audio_blob, "mp3", "en", "whisper-1")
      
      # Handle error response
      if result["type"] == "error"
        skip "STT API error: #{result['content']}"
      end
      
      # Verify response structure
      expect(result).to be_a(Hash)
      expect(result["text"]).to be_a(String)
      expect(result["text"].downcase).to include("hello")
      expect(result["text"].downcase).to include("test")
      
      # Clean up
      File.delete(audio_file) if File.exist?(audio_file)
    end
    
    it "handles various audio formats with real conversion" do
      formats = %w[mp3 wav m4a]
      
      formats.each do |format|
        # Generate audio in specific format
        audio_file = generate_real_audio_file("Testing #{format} format", format: format)
        audio_blob = File.read(audio_file, mode: "rb")
        
        # Process through real STT
        result = stt_api_request(audio_blob, format, "en", "whisper-1")
        
        # Handle error response
        if result["type"] == "error"
          skip "STT API error: #{result['content']}"
        end
        
        expect(result).to be_a(Hash)
        expect(result["text"]).to be_a(String)
        # STT might not transcribe exactly, check for related words
        text = result["text"].downcase
        expect(text).to match(/test|format|audio|mp3|wav|m4a/)
        
        # Clean up
        File.delete(audio_file) if File.exist?(audio_file)
      end
    end
    
    it "calculates real confidence scores" do
      audio_file = generate_real_audio_file("Clear speech for confidence testing", format: "mp3")
      audio_blob = File.read(audio_file, mode: "rb")
      
      result = stt_api_request(audio_blob, "mp3", "en", "whisper-1")
      
      # Handle error response
      if result["type"] == "error"
        skip "STT API error: #{result['content']}"
      end
      
      if result["segments"] && result["segments"].any?
        avg_logprob = result["segments"][0]["avg_logprob"]
        confidence = Math.exp(avg_logprob)
        expect(confidence).to be_between(0, 1)
        # Real confidence is usually high for clear speech
        expect(confidence).to be > 0.5
      end
      
      File.delete(audio_file) if File.exist?(audio_file)
    end
  end
  
  describe "Text-to-Speech Processing with Real API" do
    it "generates real audio for text input" do
      result = tts_api_request(
        "Hello, this is a real TTS test.",
        provider: "openai-tts",
        voice: "alloy",
        response_format: "mp3",
        speed: 1.0
      )
      
      expect(result["type"]).to eq("audio")
      expect(result["content"]).to be_a(String)
      
      # Decode and verify it's real audio
      audio_data = Base64.strict_decode64(result["content"])
      expect(audio_data.bytesize).to be > 1000  # Real audio should be substantial
      
      # Check MP3 header
      expect(audio_data[0..2]).to eq("ID3").or(satisfy { |v| v.unpack1("H*").start_with?("fff") })
    end
    
    it "applies real TTS dictionary replacements" do
      # Set up TTS dictionary
      original_dict = CONFIG["TTS_DICT_DATA"]
      CONFIG["TTS_DICT_DATA"] = {
        "AI" => "artificial intelligence",
        "TTS" => "text to speech"
      }.to_json
      
      result = tts_api_request(
        "AI and TTS are useful technologies.",
        provider: "openai-tts",
        voice: "alloy",
        response_format: "mp3",
        speed: 1.0
      )
      
      expect(result["type"]).to eq("audio")
      
      # Generate audio without replacements for comparison
      CONFIG["TTS_DICT_DATA"] = nil
      result_no_dict = tts_api_request(
        "AI and TTS are useful technologies.",
        provider: "openai-tts",
        voice: "alloy",
        response_format: "mp3",
        speed: 1.0
      )
      
      # Audio should be different due to text replacement
      expect(result["content"]).not_to eq(result_no_dict["content"])
      
      # Restore original dictionary
      CONFIG["TTS_DICT_DATA"] = original_dict
    end
    
    it "handles different voices and speeds" do
      voices = %w[alloy echo fable onyx nova shimmer]
      speeds = [0.5, 1.0, 2.0]
      
      # Test a subset to avoid too many API calls
      test_voice = voices.sample
      test_speed = speeds.sample
      
      result = tts_api_request(
        "Testing voice #{test_voice} at speed #{test_speed}",
        provider: "openai-tts",
        voice: test_voice,
        response_format: "mp3",
        speed: test_speed
      )
      
      expect(result["type"]).to eq("audio")
      audio_data = Base64.strict_decode64(result["content"])
      expect(audio_data.bytesize).to be > 0
    end
  end
  
  describe "Complete Voice Pipeline with Real APIs" do
    it "completes full TTS -> STT cycle" do
      original_text = "The quick brown fox jumps over the lazy dog."
      
      # Generate audio from text
      tts_result = tts_api_request(
        original_text,
        provider: "openai-tts",
        voice: "alloy",
        response_format: "mp3",
        speed: 1.0
      )
      
      expect(tts_result["type"]).to eq("audio")
      
      # Decode audio
      audio_data = Base64.strict_decode64(tts_result["content"])
      
      # Transcribe back to text
      stt_result = stt_api_request(audio_data, "mp3", "en", "whisper-1")
      
      # Handle error response
      if stt_result["type"] == "error"
        skip "STT API error: #{stt_result['content']}"
      end
      
      expect(stt_result["text"]).to be_a(String)
      transcribed_text = stt_result["text"].downcase.strip
      
      # Check key words are present (exact match unlikely due to TTS/STT variations)
      %w[quick brown fox jumps lazy dog].each do |word|
        expect(transcribed_text).to include(word)
      end
    end
    
    it "maintains accuracy across multiple languages" do
      language_tests = {
        "en" => "Hello, how are you today?",
        "es" => "Hola, ¿cómo estás hoy?",
        "fr" => "Bonjour, comment allez-vous aujourd'hui?",
        "de" => "Hallo, wie geht es dir heute?",
        "ja" => "こんにちは、今日はどうですか？"
      }
      
      # Test subset to avoid too many API calls
      test_lang = language_tests.keys.sample
      test_text = language_tests[test_lang]
      
      # Generate audio
      tts_result = tts_api_request(
        test_text,
        provider: "openai-tts",
        voice: "alloy",
        response_format: "mp3",
        speed: 1.0
      )
      
      audio_data = Base64.strict_decode64(tts_result["content"])
      
      # Transcribe with language hint
      stt_result = stt_api_request(audio_data, "mp3", test_lang, "whisper-1")
      
      # Handle error response
      if stt_result["type"] == "error"
        skip "STT API error: #{stt_result['content']}"
      end
      
      expect(stt_result["text"]).to be_a(String)
      
      # Whisper API returns full language names, map them back
      if stt_result["language"]
        language_map = {
          "english" => "en",
          "spanish" => "es", 
          "french" => "fr",
          "german" => "de",
          "japanese" => "ja"
        }
        detected_lang = stt_result["language"].downcase
        expected_lang = language_map.key(test_lang) || test_lang
        expect(detected_lang).to eq(expected_lang)
      end
    end
  end
  
  describe "Error Handling with Real APIs" do
    it "handles invalid audio data gracefully" do
      # Send non-audio data
      invalid_audio = "This is not audio data"
      
      result = stt_api_request(invalid_audio, "mp3", "en", "whisper-1")
      
      expect(result["type"]).to eq("error")
      expect(result["content"]).to include("Error")
    end
    
    it "handles extremely long text for TTS" do
      # Generate very long text (but within API limits)
      long_text = "This is a test sentence. " * 100  # ~2500 characters
      
      result = tts_api_request(
        long_text,
        provider: "openai-tts",
        voice: "alloy",
        response_format: "mp3",
        speed: 1.0
      )
      
      # Should either succeed or return meaningful error
      if result["type"] == "audio"
        audio_data = Base64.strict_decode64(result["content"])
        expect(audio_data.bytesize).to be > 10000  # Long text = larger audio
      else
        expect(result["type"]).to eq("error")
        expect(result["content"]).to be_a(String)
      end
    end
  end
end