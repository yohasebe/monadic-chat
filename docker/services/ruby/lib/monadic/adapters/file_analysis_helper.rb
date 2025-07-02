require 'shellwords'

module MonadicHelper
  def analyze_image(message: "", image_path: "", model: "gpt-4.1")
    # Safely escape all parameters
    escaped_message = Shellwords.escape(message)
    escaped_image_path = Shellwords.escape(image_path)

    model = settings["model"] || settings[:model]
    model = check_vision_capability(model) || "gpt-4.1"
    escaped_model = Shellwords.escape(model)

    command = "image_query.rb #{escaped_message} #{escaped_image_path} #{escaped_model}"
    send_command(command: command, container: "ruby")
  end

  def analyze_audio(audio: "", model: "gpt-4o-transcribe")
    # Safely escape all parameters
    escaped_audio = Shellwords.escape(audio)
    escaped_model = Shellwords.escape(model)
    
    command = "stt_query.rb #{escaped_audio} . json \"\" #{escaped_model}"
    send_command(command: command, container: "ruby")
  end
end
