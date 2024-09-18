module MonadicHelper
  def generate_image(prompt: "", size: "1024x1024")
    command = <<~CMD
      bash -c 'simple_image_generation.rb -p "#{prompt}" -s "#{size}"'
    CMD
    send_command(command: command, container: "ruby")
  end
end
