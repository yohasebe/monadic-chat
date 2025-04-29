module MonadicHelper
  # Adapter for OpenAI function generate_image
  # Accepts keyword args from function call: operation, model, prompt, images, mask, n, size, quality, output_format, background, output_compression
  def generate_image(operation:, model:, prompt: nil, images: nil, mask: nil,
                     n: 1, size: "1024x1024", quality: nil,
                     output_format: nil, background: nil, output_compression: nil)
    # Build CLI command
    parts = []
    parts << "simple_image_generation.rb"
    parts << "-o #{operation}"
    parts << "-m #{model}"
    parts << "-p \"#{prompt}\"" if prompt
    parts << "-n #{n}"
    parts << "-s \"#{size}\"" if size
    parts << "-q #{quality}" if quality
    parts << "-f #{output_format}" if output_format
    parts << "-b #{background}" if background
    parts << "--compression #{output_compression}" if output_compression
    if images
      Array(images).each do |img|
        parts << "-i \"#{img}\""
      end
    end
    parts << "--mask \"#{mask}\"" if mask
    cmd = "bash -c '#{parts.join(' ')}'"
    send_command(command: cmd, container: "ruby")
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
