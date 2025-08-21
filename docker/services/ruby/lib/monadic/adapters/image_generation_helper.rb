module MonadicHelper
  # Adapter for OpenAI function generate_image
  # Accepts keyword args from function call: operation, model, prompt, images, mask, n, size, quality, output_format, background, output_compression
  def generate_image_with_openai(operation:, model:, prompt: nil, images: nil, mask: nil,
                     n: 1, size: "1024x1024", quality: nil,
                     output_format: nil, background: nil, output_compression: nil)
    # Build CLI command
    parts = []
    parts << "image_generator_openai.rb"
    parts << "-o #{operation}"
    parts << "-m #{model}"
    parts << "-p \"#{prompt}\"" if prompt
    parts << "-n #{n}"
    parts << "-s \"#{size}\"" if size
    parts << "-q #{quality}" if quality
    parts << "-f #{output_format}" if output_format
    parts << "-b #{background}" if background
    parts << "--compression #{output_compression}" if output_compression
    
    # Process image parameters
    if images
      Array(images).each do |img|
        parts << "-i \"#{img}\""
      end
    end
    
    # Handle mask parameter
    # If mask is explicitly provided, use it
    if mask
      # Get the mask filename to pass to the script for name preservation
      mask_filename = File.basename(mask.to_s)
      parts << "--mask \"#{mask}\""
      parts << "--original-name \"#{mask_filename}\""
    # For edit operation, check if there's a mask associated with the image in MonadicApp
    elsif operation == "edit" && images && images.size == 1
      # Get the original image filename
      original_image = File.basename(images.first.to_s)
      
      # Set shared folder path for mask images
      shared_folder = Monadic::Utils::Environment.shared_volume
      
      # Look for mask file directly in the shared folder with naming convention
      # Try all possible naming conventions for masks
      # 1. mask__ prefix (new clear naming)
      # 2. mask_for_ prefix (previous naming)
      # 3. mask_*_ wildcard pattern (older naming)
      mask_pattern1 = File.join(shared_folder, "mask__#{original_image}")
      mask_pattern2 = File.join(shared_folder, "mask_for_#{original_image.gsub(/\.[^.]+$/, '')}.png")
      mask_pattern3 = File.join(shared_folder, "mask_*_#{original_image.gsub(/\.[^.]+$/, '')}.png")
      mask_files = Dir.glob([mask_pattern1, mask_pattern2, mask_pattern3])
      
      if mask_files.any?
        # Use the most recent mask file (in case there are multiple)
        # Filter out directories just in case
        mask_files = mask_files.reject { |f| File.directory?(f) }
        mask_path = mask_files.sort_by { |f| File.mtime(f) }.last if mask_files.any?
        if mask_path && File.exist?(mask_path)
          # Pass the mask filename to preserve it in output
          mask_filename = File.basename(mask_path)
          parts << "--mask \"#{mask_path}\""
          parts << "--original-name \"#{mask_filename}\""
        end
      end
    end
    
    cmd = parts.join(' ')
    send_command(command: cmd, container: "ruby")
  end


  def generate_image_with_grok(prompt: "")
    require 'json'
    
    command = "image_generator_grok.rb -p \"#{prompt}\""
    
    # Get the command output with its standard prefix
    result = send_command(command: command, container: "ruby")
    
    # Extract JSON from the command output
    # The send_command adds a prefix "Command has been executed with the following output: \n"
    # We need to extract the actual JSON part
    begin
      # Remove the standard command prefix to get the clean JSON
      json_start = result.index('{')
      if json_start
        json_str = result[json_start..-1]
        parsed = JSON.parse(json_str)
        # Return the clean JSON string for the LLM to process
        return JSON.generate(parsed)
      else
        # No JSON found in output
        return JSON.generate({
          success: false,
          message: "No valid JSON response from image generator"
        })
      end
    rescue JSON::ParserError => e
      # Return error in expected format
      return JSON.generate({
        success: false,
        message: "Failed to parse image generator response: #{e.message}"
      })
    end
  end
end
