module MonadicHelper
  def analyze_image(message: "", image_path: "", model: nil)
    message = message.gsub(/"/, '\"')
    image_analysis_agent(message: message, image_path: image_path)
  end

  def analyze_audio(audio: "", model: nil)
    # Get STT model from Web UI settings (stored in session by websocket handler)
    stt_model = settings["stt_model"] || settings[:stt_model] || model
    audio_transcription_agent(audio_path: audio, model: stt_model)
  end
end
