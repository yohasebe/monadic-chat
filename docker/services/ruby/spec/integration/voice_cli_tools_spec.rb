# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "Voice CLI Tools", :integration do
  # In development environment, we run scripts locally
  let(:scripts_base_path) { File.expand_path("../../scripts/cli_tools", __dir__) }
  
  describe "stt_query.rb" do
    let(:stt_script) { File.join(scripts_base_path, "stt_query.rb") }
    
    it "exists and is executable" do
      expect(File.exist?(stt_script)).to be true
      expect(File.executable?(stt_script)).to be true
    end
    
    it "shows error when no audio file provided" do
      output = `ruby #{stt_script} 2>&1`
      expect(output).to include("ERROR: No audio file provided.")
      expect($?.success?).to be false
    end
    
    it "expects positional arguments" do
      # The tool expects: audiofile, outpath, response_format, lang_code, model
      # Just verify it fails properly with invalid file
      output = `ruby #{stt_script} /nonexistent/audio.mp3 2>&1`
      expect(output).to include("No such file")
      expect(output).to include("An error occurred:")
    end
  end
  
  describe "tts_query.rb" do
    let(:tts_script) { File.join(scripts_base_path, "tts_query.rb") }
    
    it "exists and is executable" do
      expect(File.exist?(tts_script)).to be true
      expect(File.executable?(tts_script)).to be true
    end
    
    it "shows help information when no text file provided" do
      output = `ruby #{tts_script} 2>&1`
      expect(output).to include("Usage:")
      expect($?.success?).to be false
    end
    
    it "can list available voices" do
      # Just test the --list option
      output = `ruby #{tts_script} --list 2>&1`
      # At minimum it should show the provider name
      expect(output).to include("openai")
      # Don't expect specific voices as they may change
    end
    
    context "with text input" do
      let(:test_text_file) { "/tmp/test_tts_input.txt" }
      
      before do
        # Create test file locally
        File.write(test_text_file, "Hello world")
      end
      
      after do
        # Clean up
        FileUtils.rm_f(test_text_file)
      end
      
      it "expects text file as first argument" do
        # Test with a valid text file but without other required args
        output = `ruby #{tts_script} #{test_text_file} 2>&1`
        # Should show usage or error about missing arguments
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
      # Create a simple test audio file in Python container
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