module MonadicHelper
  def analyze_image(message: "", image_path: "", model: nil)
    message = message.gsub(/"/, '\"')
    image_analysis_agent(message: message, image_path: image_path)
  end

  def analyze_audio(audio: "", model: "gpt-4o-mini-transcribe-2025-12-15")
    # Get STT model from Web UI settings (stored in session by websocket handler)
    stt_model = settings["stt_model"] || settings[:stt_model] || model

    command = "stt_query.rb \"#{audio}\" \".\" \"json\" \"\" \"#{stt_model}\""
    send_command(command: command, container: "ruby")
  end
end
