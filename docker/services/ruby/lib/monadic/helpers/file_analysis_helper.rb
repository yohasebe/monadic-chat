module MonadicHelper
  def analyze_image(message: "", image_path: "", model: "gpt-4o")
    message = message.gsub(/"/, '\"')

    model = settings["model"] || settings[:model]
    model = check_vision_capability(model) || "gpt-4o"

    command = <<~CMD
      bash -c 'simple_image_query.rb "#{message}" "#{image_path}" "#{model}"'
    CMD
    send_command(command: command, container: "ruby")
  end

  def analyze_audio(audio: "")
    command = <<~CMD
      bash -c 'simple_whisper_query.rb "#{audio}"'
    CMD
    send_command(command: command, container: "ruby")
  end
end
