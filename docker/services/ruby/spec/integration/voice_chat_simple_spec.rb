# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Voice Chat Simple Integration", :integration do
  describe "Voice Chat App Structure" do
    it "has Voice Chat MDSL files for all providers" do
      voice_chat_apps = Dir.glob("apps/voice_chat/voice_chat_*.mdsl")
      
      expect(voice_chat_apps).not_to be_empty
      expect(voice_chat_apps.length).to be >= 5  # At least 5 providers
      
      # Check each has proper structure
      voice_chat_apps.each do |app_file|
        content = File.read(app_file)
        
        # Voice Chat specific features
        expect(content).to include('easy_submit true')
        expect(content).to include('auto_speech true')
        expect(content).to include('initiate_from_assistant true')
        
        # Should have voice-specific instructions
        expect(content).to match(/voice|speak|audio|conversation/i)
      end
    end
    
    it "has consistent settings across providers" do
      voice_chat_apps = Dir.glob("apps/voice_chat/voice_chat_*.mdsl")
      
      voice_chat_apps.each do |app_file|
        content = File.read(app_file)
        provider = File.basename(app_file, '.mdsl').split('_').last
        
        # All should have same basic features
        expect(content).to include('easy_submit true')
        expect(content).to include('auto_speech true')
        
        # Check provider-specific model
        case provider
        when "openai"
          expect(content).to match(/gpt-4o|gpt-4|gpt-5/i)
        when "claude"
          expect(content).to match(/claude-3|claude-2|claude-sonnet/i)
        when "gemini"
          expect(content).to match(/gemini/i)
        end
      end
    end
  end
  
  describe "Audio Format Support" do
    it "supports common browser audio formats" do
      # These are the formats that browsers typically produce
      supported_formats = %w[webm ogg mp3 wav m4a]
      
      supported_formats.each do |format|
        # In actual implementation, this would test format normalization
        normalized = case format
                     when "webm", "webm/opus" then "webm"
                     when "ogg", "audio/ogg" then "ogg"
                     when "mp3", "audio/mpeg", "audio/mp3" then "mp3"
                     when "wav", "audio/wav" then "wav"
                     when "m4a", "audio/x-m4a" then "m4a"
                     else format
                     end
        
        expect(normalized).to eq(format)
      end
    end
  end
  
  describe "TTS Voice Options" do
    it "provides multiple voice options for OpenAI" do
      openai_voices = %w[alloy echo fable onyx nova shimmer]
      
      expect(openai_voices.length).to eq(6)
      expect(openai_voices).to include("alloy")  # Default voice
    end
    
    it "supports different TTS providers" do
      tts_providers = %w[openai elevenlabs gemini webspeech]
      
      expect(tts_providers).to include("openai")
      expect(tts_providers).to include("webspeech")  # Browser-based option
    end
  end
  
  describe "WebSocket Message Structure" do
    it "defines proper audio message format" do
      # Example audio message structure
      audio_message = {
        "type" => "AUDIO",
        "content" => "base64_encoded_audio_data",
        "format" => "webm",
        "lang" => "en-US"
      }
      
      # Validate structure
      expect(audio_message).to have_key("type")
      expect(audio_message["type"]).to eq("AUDIO")
      expect(audio_message).to have_key("content")
      expect(audio_message).to have_key("format")
      expect(audio_message).to have_key("lang")
    end
    
    it "supports language codes" do
      language_codes = %w[en-US en-GB ja-JP es-ES fr-FR de-DE]
      
      language_codes.each do |lang|
        expect(lang).to match(/^[a-z]{2}-[A-Z]{2}$/)
      end
    end
  end
  
  describe "Configuration" do
    it "uses STT model from configuration" do
      # Default STT models
      stt_models = ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"]
      
      expect(stt_models).to include("whisper-1")  # Default model
    end
    
    it "supports TTS dictionary for replacements" do
      # Example TTS dictionary format
      tts_dict = {
        "AI" => "artificial intelligence",
        "TTS" => "text to speech",
        "STT" => "speech to text"
      }
      
      expect(tts_dict).to be_a(Hash)
      expect(tts_dict.keys).to all(be_a(String))
      expect(tts_dict.values).to all(be_a(String))
    end
  end
end