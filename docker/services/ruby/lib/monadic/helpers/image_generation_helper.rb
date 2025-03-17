module MonadicHelper
  def generate_image(prompt: "", size: "1024x1024")
    command = <<~CMD
      bash -c 'simple_image_generation.rb -p "#{prompt}" -s "#{size}"'
    CMD
    send_command(command: command, container: "ruby")
  end

  def generate_image_with_imagen(prompt: "", size: "1024x1024", sample_count: 1, safety_level: "BLOCK_MEDIUM_AND_ABOVE", person_mode: "ALLOW_ADULT")
    # Convert size to Imagen API's aspect_ratio

    aspect_ratio = case size
                   when "1024x1024" then "1:1"  # Square
                   when "1024x1792" then "9:16" # Portrait
                   when "1792x1024" then "16:9" # Landscape
                   else "1:1" # Default
                   end
    
    # Validate sample_count range (1-4)

    sample_count = [[sample_count.to_i, 1].max, 4].min
    
    command = <<~CMD
      bash -c 'imagen_image_generator.rb -p "#{prompt}" -a "#{aspect_ratio}" -n #{sample_count} -s "#{safety_level}" -g "#{person_mode}"'
    CMD
    
    # Simply pass the command output directly to the LLM
    # Let the LLM extract the filename(s) from the output text
    result = send_command(command: command, container: "ruby")
    
    # Just return the raw command output - LLM will extract filename
    return result
  end
end
