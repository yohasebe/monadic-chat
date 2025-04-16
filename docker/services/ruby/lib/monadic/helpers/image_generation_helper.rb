module MonadicHelper
  def generate_image(prompt: "", size: "1024x1024")
    command = <<~CMD
      bash -c 'simple_image_generation.rb -p "#{prompt}" -s "#{size}"'
    CMD
    send_command(command: command, container: "ruby")
  end

  def generate_image_with_imagen(prompt: "", aspect_ratio: "1:1", sample_count: 1, person_generation: "ALLOW_ADULT")

    sample_count = [[sample_count.to_i, 1].max, 4].min
    
    command = <<~CMD
      bash -c 'imagen_image_generator.rb -p "#{prompt}" -a "#{aspect_ratio}" -n #{sample_count} -g "#{person_generation}"'
    CMD
    
    # Simply pass the command output directly to the LLM
    # Let the LLM extract the filename(s) from the output text
    result = send_command(command: command, container: "ruby")
    
    # Just return the raw command output - LLM will extract filename
    return result
  end

  def generate_image_with_grok(prompt: "")

    command = <<~CMD
      bash -c 'grok_image_generator.rb -p "#{prompt}"'
    CMD
    
    # Simply pass the command output directly to the LLM
    # Let the LLM extract the filename(s) from the output text
    result = send_command(command: command, container: "ruby")
    
    # Just return the raw command output - LLM will extract filename
    return result
  end
end
