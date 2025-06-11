module MonadicHelper
  def analyze_image(message: "", image_path: "", model: "gpt-4.1")
    message = message.gsub(/"/, '\"')

    model = settings["model"] || settings[:model]
    model = check_vision_capability(model) || "gpt-4.1"

    command = "image_query.rb \"#{message}\" \"#{image_path}\" \"#{model}\""
    send_command(command: command, container: "ruby")
  end

  def analyze_audio(audio: "", model: "gpt-4o-transcribe")
    command = "stt_query.rb \"#{audio}\" \".\" \"json\" \"\" \"#{model}\""
    send_command(command: command, container: "ruby")
  end
end
