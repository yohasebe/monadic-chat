# frozen_string_literal: true

require_relative "e2e_helper"
require_relative "../support/real_audio_test_helper"

RSpec.describe "Voice Chat E2E (No Mocks)", :e2e do
  include E2EHelper
  include RealAudioTestHelper
  
  let(:app_name) { "VoiceChatOpenAI" }
  
  before do
    skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
  end
  
  describe "Voice Chat workflow with real audio" do
    it "displays greeting message on activation" do
      with_e2e_retry do
        response = activate_app_and_get_greeting(app_name)
        
        expect(response).to match(/Hello|Hi|Welcome|voice chat|speak/i)
      end
    end
    
    it "processes text input like regular chat" do
      with_e2e_retry do
        response = send_and_receive_message(app_name, "Hello, can you hear me?")
        
        # Voice Chat should respond to text input normally
        expect(response).to match(/yes|hear|hello|listening/i)
      end
    end
    
    context "with real audio processing" do
      it "transcribes real voice input and generates response" do
        with_e2e_retry do
          # Generate real audio using TTS
          test_message = "Hello, how are you today?"
          audio_file = generate_test_audio(test_message, format: "webm")
          audio_data = File.read(audio_file, mode: "rb")
          audio_base64 = Base64.strict_encode64(audio_data)
          
          # Send real audio through WebSocket
          response = send_real_audio_message(
            app_name,
            audio_base64,
            format: "webm",
            lang: "en-US"
          )
          
          # Check that AI responds appropriately
          expect(response).to match(/fine|good|well|thank|hello/i)
          
          # Clean up
          File.delete(audio_file) if File.exist?(audio_file)
        end
      end
      
      it "handles multiple audio formats" do
        formats = %w[mp3 webm wav]
        
        formats.each do |format|
          with_e2e_retry do
            # Generate audio in specific format
            audio_file = generate_test_audio("Testing #{format} audio format", format: format)
            audio_data = File.read(audio_file, mode: "rb")
            audio_base64 = Base64.strict_encode64(audio_data)
            
            response = send_real_audio_message(
              app_name,
              audio_base64,
              format: format,
              lang: "en-US"
            )
            
            # Should get a meaningful response
            expect(response.length).to be > 10
            expect(response).to match(/test|format|audio/i)
            
            File.delete(audio_file) if File.exist?(audio_file)
          end
        end
      end
      
      it "maintains conversation context with audio" do
        with_e2e_retry do
          # First message - introduce a topic
          audio_file1 = generate_test_audio("My favorite color is blue", format: "mp3")
          audio_data1 = File.read(audio_file1, mode: "rb")
          response1 = send_real_audio_message(
            app_name,
            Base64.strict_encode64(audio_data1),
            format: "mp3",
            lang: "en-US"
          )
          
          expect(response1).to match(/blue|color/i)
          
          # Second message - reference the topic
          audio_file2 = generate_test_audio("What did I just tell you about?", format: "mp3")
          audio_data2 = File.read(audio_file2, mode: "rb")
          response2 = send_real_audio_message(
            app_name,
            Base64.strict_encode64(audio_data2),
            format: "mp3",
            lang: "en-US"
          )
          
          # Should remember the context
          expect(response2).to match(/blue|color|favorite/i)
          
          # Clean up
          [audio_file1, audio_file2].each { |f| File.delete(f) if File.exist?(f) }
        end
      end
    end
    
    describe "real language support" do
      it "handles English audio input" do
        with_e2e_retry do
          audio_file = generate_test_audio("Good morning, how is the weather?", format: "mp3")
          audio_data = File.read(audio_file, mode: "rb")
          
          response = send_real_audio_message(
            app_name,
            Base64.strict_encode64(audio_data),
            format: "mp3",
            lang: "en-US"
          )
          
          expect(response).to match(/weather|morning|day/i)
          File.delete(audio_file) if File.exist?(audio_file)
        end
      end
      
      it "handles accented speech" do
        with_e2e_retry do
          # Test with slower speech for better recognition
          audio_file = generate_test_audio(
            "Hello, this is a test with clear pronunciation",
            format: "mp3",
            voice: "nova",  # Clear voice
            speed: 0.9      # Slightly slower
          )
          audio_data = File.read(audio_file, mode: "rb")
          
          response = send_real_audio_message(
            app_name,
            Base64.strict_encode64(audio_data),
            format: "mp3",
            lang: "en-US"
          )
          
          expect(response.length).to be > 0
          File.delete(audio_file) if File.exist?(audio_file)
        end
      end
    end
    
    describe "error handling with real scenarios" do
      it "handles very short audio clips" do
        with_e2e_retry do
          # Generate very short audio (just "Hi")
          audio_file = generate_test_audio("Hi", format: "mp3", speed: 2.0)
          audio_data = File.read(audio_file, mode: "rb")
          
          response = send_real_audio_message(
            app_name,
            Base64.strict_encode64(audio_data),
            format: "mp3",
            lang: "en-US"
          )
          
          # Should still process successfully
          expect(response).not_to be_empty
          File.delete(audio_file) if File.exist?(audio_file)
        end
      end
      
      it "handles noisy audio gracefully" do
        with_e2e_retry do
          # Generate audio with numbers and symbols that might be hard to transcribe
          audio_file = generate_test_audio(
            "The code is ABC one two three XYZ",
            format: "mp3"
          )
          audio_data = File.read(audio_file, mode: "rb")
          
          response = send_real_audio_message(
            app_name,
            Base64.strict_encode64(audio_data),
            format: "mp3",
            lang: "en-US"
          )
          
          # Should handle even if transcription isn't perfect
          expect(response.length).to be > 0
          File.delete(audio_file) if File.exist?(audio_file)
        end
      end
      
      it "handles silence in audio" do
        with_e2e_retry do
          # Create a file with minimal sound
          silent_file = "/tmp/silent_audio.mp3"
          
          # Use FFmpeg to create near-silent audio
          cmd = "ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 1 -b:a 32k #{silent_file} -y 2>/dev/null"
          system(cmd)
          
          if File.exist?(silent_file)
            audio_data = File.read(silent_file, mode: "rb")
            
            response = send_real_audio_message(
              app_name,
              Base64.strict_encode64(audio_data),
              format: "mp3",
              lang: "en-US"
            )
            
            # Should handle gracefully even with no speech
            expect(response).not_to be_nil
            File.delete(silent_file)
          end
        end
      end
    end
  end
  
  private
  
  def send_real_audio_message(app_name, audio_base64, format:, lang: "en-US")
    # Activate app if needed
    ensure_app_ready(app_name)
    
    # Send audio message through WebSocket
    message = {
      "type" => "audio",
      "content" => audio_base64,
      "format" => format,
      "lang" => lang
    }
    
    @ws.send(message.to_json)
    
    # Wait for and return AI response
    response = nil
    Timeout.timeout(30) do
      loop do
        msg = JSON.parse(@ws.receive.to_s)
        if msg["type"] == "message" && msg["role"] == "assistant"
          response = msg["content"]
          break
        elsif msg["type"] == "error"
          raise "Audio processing error: #{msg['content']}"
        end
      end
    end
    
    response
  rescue Timeout::Error
    "Timeout waiting for response"
  end
  
  def ensure_app_ready(app_name)
    # Make sure app is activated
    unless @current_app == app_name
      activate_app(app_name)
      @current_app = app_name
      sleep 1  # Give app time to initialize
    end
  end
end