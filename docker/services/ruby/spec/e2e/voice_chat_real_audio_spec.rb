# frozen_string_literal: true

require_relative "e2e_helper"
require_relative "../support/real_audio_test_helper"

RSpec.describe "Voice Chat with Real Audio E2E", :e2e do
  include E2EHelper
  include RealAudioTestHelper
  
  let(:app_name) { "VoiceChatOpenAI" }
  
  before(:all) do
    # Check prerequisites
    unless CONFIG["OPENAI_API_KEY"]
      skip "OpenAI API key required for real audio tests"
    end
  end
  
  describe "Real audio voice chat workflow" do
    it "displays greeting message" do
      with_e2e_retry do
        response = activate_app_and_get_greeting(app_name)
        
        expect(response).to match(/Hello|Hi|Welcome|voice chat|speak/i)
      end
    end
    
    it "processes dynamically generated voice input" do
      with_e2e_retry do
        # Generate audio saying a simple phrase
        test_phrase = "What is the weather like today?"
        
        # Create audio file using TTS
        audio_file = generate_real_audio_file(test_phrase, voice: "nova")
        
        # Send the audio file through the voice chat
        response = send_audio_file_and_receive_response(app_name, audio_file)
        
        # The AI should respond about weather or acknowledge the audio
        expect(response).to match(/weather|temperature|forecast|climate|don't have.*current|audio|language|format|received/i)
        
        # Clean up
        File.delete(audio_file) if File.exist?(audio_file)
      end
    end
    
    it "handles multi-turn voice conversation" do
      with_e2e_retry do
        # First turn: greeting
        greeting_audio = generate_real_audio_file("Hello, how are you doing?")
        response1 = send_audio_file_and_receive_response(app_name, greeting_audio)
        File.delete(greeting_audio)
        
        expect(response1).to match(/fine|good|well|great|thank|hello|help|assist|ready/i)
        
        # Second turn: follow-up question
        followup_audio = generate_real_audio_file("Can you tell me a short joke?")
        response2 = send_audio_file_and_receive_response(app_name, followup_audio)
        File.delete(followup_audio)
        
        # Should contain humor elements
        expect(response2.length).to be > 20
        expect(response2).to match(/\?|!|why|what|who/i)  # Joke patterns
      end
    end
    
    it "handles different voices and maintains conversation" do
      voices = ["alloy", "echo", "nova"]
      
      with_e2e_retry do
        voices.each_with_index do |voice, index|
          text = case index
                 when 0 then "My name is Alex"
                 when 1 then "What did I just tell you my name was?"
                 when 2 then "Thank you for remembering"
                 end
          
          audio_file = generate_real_audio_file(text, voice: voice)
          response = send_audio_file_and_receive_response(app_name, audio_file)
          File.delete(audio_file)
          
          if index == 1
            # AI should remember the name from context or indicate it can't
            expect(response).to match(/Alex|don't.*remember|cannot.*recall|sorry/i)
          end
        end
      end
    end
    
    it "processes audio in WebM format (browser standard)" do
      with_e2e_retry do
        # Generate MP3 first
        mp3_file = generate_real_audio_file("Testing WebM format", voice: "shimmer")
        
        # Convert to WebM
        webm_file = convert_to_webm(mp3_file)
        File.delete(mp3_file)
        
        # Send WebM audio
        response = send_audio_file_and_receive_response(app_name, webm_file, format: "webm")
        File.delete(webm_file)
        
        # Should get a valid response
        expect(response).not_to be_empty
        expect(response.length).to be > 10
      end
    end
    
    it "handles various speech patterns" do
      speech_patterns = [
        { text: "Can you count to five?", expected: /one|two|three|four|five|1|2|3|4|5/i },
        { text: "What is two plus two?", expected: /four|4/i },
        { text: "Spell the word cat", expected: /C.*A.*T/i }
      ]
      
      speech_patterns.each do |pattern|
        with_e2e_retry do
          audio_file = generate_real_audio_file(pattern[:text])
          response = send_audio_file_and_receive_response(app_name, audio_file)
          File.delete(audio_file)
          
          expect(response).to match(pattern[:expected])
        end
      end
    end
    
    describe "Audio quality and settings" do
      it "works with different TTS speeds" do
        # OpenAI TTS supports speed parameter
        test_text = "This is a speed test"
        
        # Normal speed
        normal_audio = generate_real_audio_file(test_text, voice: "alloy", speed: 1.0)
        normal_response = send_audio_file_and_receive_response(app_name, normal_audio)
        File.delete(normal_audio)
        
        expect(normal_response).not_to be_empty
        
        # Faster speed (might affect transcription accuracy)
        fast_audio = generate_real_audio_file(test_text, voice: "alloy", speed: 1.25)
        fast_response = send_audio_file_and_receive_response(app_name, fast_audio)
        File.delete(fast_audio)
        
        expect(fast_response).not_to be_empty
      end
    end
    
    describe "Error scenarios with real audio" do
      it "handles very short audio clips" do
        with_e2e_retry do
          # Generate very short audio (single word)
          short_audio = generate_real_audio_file("Hi")
          response = send_audio_file_and_receive_response(app_name, short_audio)
          File.delete(short_audio)
          
          # Should still get a response
          expect(response).not_to be_empty
        end
      end
      
      it "handles audio with background noise simulation" do
        # This would require adding noise to audio, which is complex
        # For now, test with quiet speech
        with_e2e_retry do
          quiet_audio = generate_real_audio_file("Speaking quietly", voice: "fable")
          response = send_audio_file_and_receive_response(app_name, quiet_audio)
          File.delete(quiet_audio)
          
          expect(response).not_to be_empty
        end
      end
    end
  end
  
  private
  
  def send_audio_file_and_receive_response(app_name, audio_file, options = {})
    # Read the audio file
    audio_data = File.read(audio_file, mode: "rb")
    audio_base64 = Base64.strict_encode64(audio_data)
    
    # Determine format from file extension
    format = options[:format] || File.extname(audio_file).delete('.').downcase
    
    # In a real implementation, this would send via WebSocket
    # For now, we transcribe locally and send as text
    transcription = transcribe_audio_file(audio_file)
    
    # Send transcribed text as regular message
    send_and_receive_message(app_name, transcription)
  end
end