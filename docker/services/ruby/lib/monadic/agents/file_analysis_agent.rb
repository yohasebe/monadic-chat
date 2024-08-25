module MonadicAgent
  def analyze_image(message: "", image_path: "", model: "gpt-4o-mini")
    message = message.gsub(/"/, '\"')
    model = ENV["VISION_MODEL"] || model == "gpt-4o-mini"
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
