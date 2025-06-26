# frozen_string_literal: true

module AudioTestHelper
  # Generate a simple test audio file using TTS
  def generate_test_audio(text, output_file)
    # Use the existing TTS functionality to create test audio
    tts_command = <<~BASH
      echo "#{text}" | docker exec -i monadic-chat-python-container python /monadic/scripts/cli_tools/tts_query.py --provider openai --model tts-1 --voice alloy
    BASH
    
    audio_data = `#{tts_command}`
    File.write(output_file, audio_data, mode: "wb")
  end
  
  # Create a WebM audio file with silence
  def create_silent_audio(duration_seconds, output_file)
    # Use FFmpeg to create silent audio
    ffmpeg_command = <<~BASH
      docker exec monadic-chat-python-container ffmpeg -f lavfi -i anullsrc=r=48000:cl=stereo -t #{duration_seconds} -acodec libopus -f webm -y /tmp/silence.webm && \
      docker exec monadic-chat-python-container cat /tmp/silence.webm
    BASH
    
    audio_data = `#{ffmpeg_command}`
    File.write(output_file, audio_data, mode: "wb")
  end
  
  # Simulate WebSocket audio message
  def send_audio_message(app_name, audio_file_or_text, options = {})
    audio_data = if File.exist?(audio_file_or_text)
                   File.read(audio_file_or_text, mode: "rb")
                 else
                   # Generate audio from text
                   temp_file = "/tmp/test_audio_#{Time.now.to_i}.mp3"
                   generate_test_audio(audio_file_or_text, temp_file)
                   data = File.read(temp_file, mode: "rb")
                   File.delete(temp_file)
                   data
                 end
    
    audio_base64 = Base64.strict_encode64(audio_data)
    
    message = {
      type: "AUDIO",
      content: audio_base64,
      format: options[:format] || "webm",
      lang: options[:lang] || "en-US"
    }
    
    send_websocket_message(app_name, message)
  end
  
  # Mock STT response for testing
  def mock_stt_response(transcription, confidence = 0.95)
    allow_any_instance_of(InteractionUtils).to receive(:stt_api_request).and_return({
      success: true,
      text: transcription,
      confidence: confidence,
      logprobs: [-0.05] * transcription.split.length
    })
  end
  
  # Mock TTS response for testing
  def mock_tts_response(audio_data = nil)
    audio_data ||= File.read("spec/fixtures/audio/sample_response.mp3", mode: "rb")
    
    allow_any_instance_of(InteractionUtils).to receive(:tts_api_request).and_return({
      success: true,
      audio: Base64.strict_encode64(audio_data),
      format: "mp3"
    })
  end
end