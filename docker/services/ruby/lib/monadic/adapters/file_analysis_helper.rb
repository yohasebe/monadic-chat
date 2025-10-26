module MonadicHelper
  def analyze_image(message: "", image_path: "", model: "gpt-5")
    message = message.gsub(/"/, '\"')

    model = settings["model"] || settings[:model]
    model = check_vision_capability(model) || "gpt-5"

    command = "image_query.rb \"#{message}\" \"#{image_path}\" \"#{model}\""
    send_command(command: command, container: "ruby")
  end

  def analyze_audio(audio: "", model: "gpt-4o-mini-transcribe")
    # Get STT model from Web UI settings (stored in session by websocket handler)
    stt_model = settings["stt_model"] || settings[:stt_model] || model

    command = "stt_query.rb \"#{audio}\" \".\" \"json\" \"\" \"#{stt_model}\""
    send_command(command: command, container: "ruby")
  end
end
