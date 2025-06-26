# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Voice CLI Tools", :integration do
  describe "stt_query.rb" do
    let(:stt_script) { "/monadic/scripts/cli_tools/stt_query.rb" }
    
    it "exists and is executable" do
      output = `docker exec monadic-chat-ruby-container ls -la #{stt_script} 2>&1`
      expect(output).to include("stt_query.rb")
      expect($?.success?).to be true
    end
    
    it "shows error when no audio file provided" do
      output = `docker exec monadic-chat-ruby-container ruby #{stt_script} 2>&1`
      expect(output).to include("ERROR: No audio file provided.")
      expect($?.success?).to be false
    end
    
    it "expects positional arguments" do
      # The tool expects: audiofile, outpath, response_format, lang_code, model
      # Just verify it fails properly with invalid file
      output = `docker exec monadic-chat-ruby-container ruby #{stt_script} /nonexistent/audio.mp3 2>&1`
      expect(output).to include("No such file")
      expect(output).to include("An error occurred:")
    end
  end
  
  describe "tts_query.rb" do
    let(:tts_script) { "/monadic/scripts/cli_tools/tts_query.rb" }
    
    it "exists and is executable" do
      output = `docker exec monadic-chat-ruby-container ls -la #{tts_script} 2>&1`
      expect(output).to include("tts_query.rb")
      expect($?.success?).to be true
    end
    
    it "shows help information when no text file provided" do
      output = `docker exec monadic-chat-ruby-container ruby #{tts_script} 2>&1`
      expect(output).to include("Usage:")
      expect(output).to include("--provider=")
      expect(output).to include("--voice=")
      expect(output).to include("--language=")
    end
    
    it "can list available voices" do
      output = `docker exec monadic-chat-ruby-container ruby #{tts_script} --list 2>&1`
      
      # Should output JSON with provider information
      expect(output).to include("openai")
      expect(output).to include("voices")
      expect(output).to include("alloy")  # OpenAI default voice
    end
    
    context "with text input" do
      it "expects text file as first argument" do
        # Create a test text file
        command = <<~BASH
          docker exec monadic-chat-ruby-container bash -c '
            echo "Test text" > /tmp/test.txt &&
            ruby #{tts_script} /tmp/test.txt --provider=openai --voice=alloy 2>&1 &&
            rm -f /tmp/test.txt
          '
        BASH
        output = `#{command}`
        
        # Should process the text file
        expect(output).to include("Text-to-speech audio")
      end
    end
  end
  
  describe "Audio format utilities" do
    it "can convert between audio formats using FFmpeg" do
      # Test if FFmpeg is available in Python container
      output = `docker exec monadic-chat-python-container ffmpeg -version 2>&1`
      expect(output).to include("ffmpeg version")
      expect($?.success?).to be true
    end
    
    it "can create test audio files" do
      # Create a simple test audio file
      command = <<~BASH
        docker exec monadic-chat-python-container bash -c "
          ffmpeg -f lavfi -i sine=frequency=440:duration=1 -ar 16000 -ac 1 -f wav -y /tmp/test_tone.wav &&
          ls -la /tmp/test_tone.wav
        "
      BASH
      
      output = `#{command} 2>&1`
      expect(output).to include("test_tone.wav")
    end
  end
end