module MonadicHelper
  # Adapter for OpenAI function generate_image
  # Accepts keyword args from function call: operation, model, prompt, images, mask, n, size, quality, output_format, background, output_compression
  def generate_image_with_openai(operation:, model:, prompt: nil, images: nil, mask: nil,
                     n: 1, size: "1024x1024", quality: nil,
                     output_format: nil, background: nil, output_compression: nil, input_fidelity: nil)
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
    parts << "--compression #{output_compression}" if output_compression && output_compression.to_i > 0
    parts << "--fidelity #{input_fidelity}" if input_fidelity
    
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

    # Use block form to get detailed stdout/stderr/status for better error reporting
    stdout = ""
    stderr = ""
    status = nil

    send_command(command: command, container: "ruby") do |out, err, stat|
      stdout = out
      stderr = err
      status = stat
    end

    # Extract JSON from stdout
    begin
      json_start = stdout.index('{')
      if json_start
        json_str = stdout[json_start..-1]
        parsed = JSON.parse(json_str)
        return JSON.generate(parsed)
      else
        return JSON.generate({
          success: false,
          message: "No valid JSON response from image generator",
          raw_stdout: stdout,
          raw_stderr: stderr
        })
      end
    rescue JSON::ParserError => e
      return JSON.generate({
        success: false,
        message: "Failed to parse image generator response: #{e.message}",
        raw_stdout: stdout,
        raw_stderr: stderr
      })
    end
  end

  # Adapter for OpenAI Sora video generation
  # Accepts keyword args from function call: prompt, model, size, seconds, image_path, remix_video_id
  def generate_video_with_sora(prompt:, model: "sora-2", size: "1280x720", seconds: "8",
                                image_path: nil, remix_video_id: nil, max_wait: 420)
    require 'json'

    # Build CLI command
    parts = []
    parts << "video_generator_openai.rb"
    parts << "-p \"#{prompt}\""
    parts << "-m #{model}"
    parts << "-s \"#{size}\""
    parts << "-d #{seconds}"
    parts << "--max-wait #{max_wait}"

    # Handle image-to-video
    if image_path && !image_path.to_s.strip.empty?
      parts << "-i \"#{image_path}\""
    end

    # Handle remix
    if remix_video_id && !remix_video_id.to_s.strip.empty?
      parts << "-r \"#{remix_video_id}\""
    end

    cmd = parts.join(' ')

    # Use block form to get detailed stdout/stderr/status for better error reporting
    stdout = ""
    stderr = ""
    status = nil

    send_command(command: cmd, container: "ruby") do |out, err, stat|
      stdout = out
      stderr = err
      status = stat
    end

    # Extract JSON from stdout
    begin
      json_start = stdout.index('{')
      if json_start
        json_str = stdout[json_start..-1]
        parsed = JSON.parse(json_str)
        return JSON.generate(parsed)
      else
        return JSON.generate({
          success: false,
          error: "No valid JSON response from video generator",
          raw_stdout: stdout,
          raw_stderr: stderr
        })
      end
    rescue JSON::ParserError => e
      return JSON.generate({
        success: false,
        error: "Failed to parse video generator response: #{e.message}",
        raw_stdout: stdout,
        raw_stderr: stderr
      })
    end
  end
end
