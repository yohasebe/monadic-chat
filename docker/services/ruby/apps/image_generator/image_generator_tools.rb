# Facade methods for Image Generator apps
# Provides clear interfaces for image generation functionality

require 'base64'
require 'fileutils'
require_relative "../../lib/monadic/shared_tools/monadic_session_state"

class ImageGeneratorOpenAI < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include OpenAIHelper if defined?(OpenAIHelper)
  # Generate, edit, or create variations of images using OpenAI
  # @param operation [String] Type of operation: 'generate', 'edit', or 'variation'
  # @param model [String] Model to use for image generation
  # @param prompt [String] Text description of the desired image
  # @param images [Array<String>] Array of image filenames for editing/variation
  # @param mask [String] Mask image filename for precise editing
  # @param n [Integer] Number of images to generate (1-4)
  # @param size [String] Image dimensions
  # @param quality [String] Image quality level ('standard' or 'hd')
  # @param output_format [String] Output format ('png', 'webp', 'jpeg')
  # @param background [String] Background color for transparent images
  # @param output_compression [Integer] Compression level for JPEG (1-100)
  # @param session [Object] Session object (automatically provided)
  # @return [Hash] Generated image URLs and metadata
  def generate_image_with_openai(operation:, model:, prompt: nil, images: nil,
                                mask: nil, n: 1, size: "1024x1024",
                                quality: "standard", output_format: "png",
                                background: nil, output_compression: nil, input_fidelity: nil,
                                session: nil)
    # Input validation
    raise ArgumentError, "Invalid operation" unless %w[generate edit variation].include?(operation)
    raise ArgumentError, "Model is required" if model.to_s.strip.empty?
    raise ArgumentError, "Prompt is required for generate/edit" if %w[generate edit].include?(operation) && prompt.to_s.strip.empty?

    shared_folder = Monadic::Utils::Environment.shared_volume

    # Auto-attach last generated image for iterative editing (same pattern as Gemini3Preview)
    # ONLY if user hasn't provided explicit images and there's a previous image
    if %w[edit variation].include?(operation) && (images.nil? || images.empty?) && session
      app_key = session.dig(:parameters, "app_name") || "ImageGeneratorOpenAI"
      last_images = fetch_last_images_from_session(session, app_key)
      last_image_filename = last_images&.first

      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts "[#{Time.now}] OpenAI Image: Auto-attach check"
        extra_log.puts "  operation: #{operation}"
        extra_log.puts "  app_key: #{app_key}"
        extra_log.puts "  last_images: #{last_images.inspect}"
        extra_log.close
      end

      if last_image_filename
        image_path = File.join(shared_folder, File.basename(last_image_filename))
        if File.exist?(image_path)
          # Load and encode the last generated image
          image_data = File.read(image_path)
          image_b64 = Base64.strict_encode64(image_data)

          # Add to images parameter (same format as uploaded images)
          images = [{
            "data" => "data:image/png;base64,#{image_b64}",
            "name" => File.basename(last_image_filename)
          }]

          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts "[#{Time.now}] OpenAI Image: Auto-attached last generated image: #{last_image_filename}"
            extra_log.puts "  This makes iterative editing work like 'editing uploaded image'"
            extra_log.close
          end
        else
          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts "[#{Time.now}] OpenAI Image: Last generated image file not found: #{image_path}"
            extra_log.close
          end
        end
      end
    end

    # Auto-detect mask from session if not provided for edit operation
    if operation == "edit" && mask.nil? && session && session[:messages]
      last_user_msg = session[:messages].reverse.find { |m| m["role"] == "user" }
      if last_user_msg && last_user_msg["images"]
        # Find a mask image in the uploaded images
        mask_image = last_user_msg["images"].find { |img| 
          name = img["name"] || img["filename"] || img["title"]
          name && name.to_s.start_with?("mask__")
        }
        
        if mask_image
          mask_filename = mask_image["name"] || mask_image["filename"] || mask_image["title"]
          # Set mask parameter
          mask = mask_filename
          
          # If images param is also missing or invalid, set it to the original image derived from mask name
          # mask__filename.png -> filename.png
          original_filename = mask_filename.sub(/^mask__/, "")
          
          # Only override images if not provided or if we're falling back
          if images.nil? || images.empty?
             images = [original_filename]
          end
        end
      end
    end

    # Logic to resolve/validate images from session if needed (for edit/variation)
    if %w[edit variation].include?(operation)
      shared_folder = Monadic::Utils::Environment.shared_volume
      
      # Helper to check image existence
      check_image_exists = ->(name) {
        return false if name.nil? || name.empty?
        File.exist?(File.join(shared_folder, File.basename(name)))
      }

      # Helper to save base64 image to file
      save_base64_image = ->(image_data, filename) {
        return nil unless image_data && image_data.start_with?("data:image/")
        
        require 'base64'
        # Extract base64 part
        base64_data = image_data.split(',').last
        
        # Determine path
        file_path = File.join(shared_folder, File.basename(filename))
        
        # Write to file
        File.open(file_path, 'wb') do |f|
          f.write(Base64.decode64(base64_data))
        end
        
        return filename
      }
      
      # Check if provided images exist locally
      current_images_valid = images && !images.empty? && check_image_exists.call(images.first)

      # If we have a target filename but no file, try to find its data in session history and save it
      # This handles cases where the image was uploaded in a previous turn or just resolved from mask name
      if !current_images_valid && images && !images.empty? && session && session[:messages]
        target_filename = File.basename(images.first)
        
        found_image_data = nil
        # Search backwards through history
        session[:messages].reverse_each do |msg|
          next unless msg["images"]
          image_entry = msg["images"].find { |img| 
            name = img["name"] || img["filename"] || img["title"]
            # Robust comparison using basenames
            name && File.basename(name) == target_filename
          }
          if image_entry
            found_image_data = image_entry["data"]
            break
          end
        end
        
        if found_image_data && found_image_data.start_with?("data:image/")
          saved_name = save_base64_image.call(found_image_data, target_filename)
          if saved_name
            # Update images array with the local filename (without path) as save_base64_image returns
            images = [File.basename(saved_name)]
            current_images_valid = true
          end
        end
      end

      # If no valid images provided, try to auto-resolve from session
      if !current_images_valid
        # Strategy A: Check session[:parameters]["images"] (Current turn upload)
        if session && session[:parameters] && session[:parameters]["images"] && !session[:parameters]["images"].empty?
          valid_upload = session[:parameters]["images"].find { |img| 
            name = img["name"] || img["filename"] || img["title"]
            name && !name.to_s.start_with?("mask__")
          }
          
          if valid_upload
            found_name = valid_upload["name"] || valid_upload["filename"] || valid_upload["title"]
            
            if valid_upload["data"] && valid_upload["data"].start_with?("data:image/")
              saved_name = save_base64_image.call(valid_upload["data"], found_name)
              if saved_name
                images = [File.basename(saved_name)]
                current_images_valid = true
              end
            elsif check_image_exists.call(found_name)
              images = [found_name]
              current_images_valid = true
            end
          end
        end

        # Strategy B: Check session[:messages] history (Previous turns)
        if !current_images_valid && session && session[:messages]
          last_user_msg = session[:messages].reverse.find { |m| m["role"] == "user" }
          if last_user_msg && last_user_msg["images"] && !last_user_msg["images"].empty?
            # Filter for valid non-mask images
            valid_upload = last_user_msg["images"].find { |img| 
              name = img["name"] || img["filename"] || img["title"]
              name && !name.to_s.start_with?("mask__")
            }
            
            if valid_upload
              found_name = valid_upload["name"] || valid_upload["filename"] || valid_upload["title"]
              
              # Check if it has base64 data that needs saving
              if valid_upload["data"] && valid_upload["data"].start_with?("data:image/")
                saved_name = save_base64_image.call(valid_upload["data"], found_name)
                if saved_name
                  images = [File.basename(saved_name)]
                  current_images_valid = true
                end
              elsif check_image_exists.call(found_name)
                images = [found_name]
                current_images_valid = true
              end
            end
          end
        end

        # 2. Check for last generated image if still no valid images found
        if !current_images_valid && session
          app_key = session.dig(:parameters, "app_name") || "ImageGeneratorOpenAI"
          last_images = fetch_last_images_from_session(session, app_key)

          if last_images && !last_images.empty? && check_image_exists.call(last_images.first)
            images = [last_images.first]
            current_images_valid = true
          end
        end
        
        # 3. Final check: if we still don't have valid images, return error JSON
        unless current_images_valid
          # Gather debug info about available images in session
          available_images = []
          if session && session[:messages]
            session[:messages].each do |m|
              if m["images"]
                m["images"].each do |i|
                  available_images << (i["name"] || i["filename"] || i["title"] || "unknown")
                end
              end
            end
          end
          
          debug_msg = available_images.empty? ? "No images found in session." : "Available images in session: #{available_images.join(', ')}"
          target_info = images ? images.first : "none"
          
          return { 
            success: false, 
            error: "Image file not found for editing. Please upload an image or generate one first.",
            debug_info: "Target: '#{target_info}'. #{debug_msg}"
          }.to_json
        end
      end
      
      # Validate mask if present
      if mask
        mask_exists = check_image_exists.call(mask)
        
        # If mask file doesn't exist, check session for base64 mask data
        if !mask_exists && session && session[:messages]
          # Search all messages for the mask, not just the last one
          found_mask_data = nil
          target_mask_name = File.basename(mask)
          
          session[:messages].reverse_each do |msg|
            next unless msg["images"]
            mask_entry = msg["images"].find { |img| 
              name = img["name"] || img["filename"] || img["title"]
              name && File.basename(name) == target_mask_name
            }
            if mask_entry
              found_mask_data = mask_entry["data"]
              break
            end
          end
            
          if found_mask_data && found_mask_data.start_with?("data:image/")
            save_base64_image.call(found_mask_data, mask)
            mask_exists = true
          end
        end

        unless mask_exists
          # Gather debug info about available images in session
          available_images = []
          if session && session[:messages]
            session[:messages].each do |m|
              if m["images"]
                m["images"].each do |i|
                  available_images << (i["name"] || i["filename"] || i["title"] || "unknown")
                end
              end
            end
          end
          debug_msg = available_images.empty? ? "No images found." : "Available: #{available_images.join(', ')}"
          
          return { 
            success: false, 
            error: "Mask file not found.",
            debug_info: "Target mask: '#{mask}'. #{debug_msg}"
          }.to_json
        end
      end
    end
    
    # Validate images presence after resolution
    raise ArgumentError, "Images required for edit/variation" if %w[edit variation].include?(operation) && (images.nil? || images.empty?)
    
    # Validate background parameter if provided
    if background && !%w[transparent opaque auto].include?(background.to_s)
      raise ArgumentError, "Invalid background value: '#{background}'. Must be 'transparent', 'opaque', or 'auto'"
    end

    # Validate output_compression parameter if provided
    if output_compression && output_compression.to_i != 0
      if output_compression.to_i < 1 || output_compression.to_i > 100
        raise ArgumentError, "Invalid output_compression value: #{output_compression}. Must be between 1 and 100"
      end

      # PNG does not support compression parameter
      if output_format == "png"
        raise ArgumentError, "PNG format does not support compression. Remove output_compression parameter or use JPEG/WEBP format"
      end
    end

    # For edit operation with mask, ensure mask parameter is provided
    if operation == "edit" && mask.nil? && images
      # Check if a mask file exists for the image
      puts "Warning: No mask parameter provided for edit operation. Mask may not be applied correctly."
    end

    # Call the method from MediaGenerationHelper (via MonadicHelper)
    result_json = super(operation: operation, model: model, prompt: prompt, images: images,
          mask: mask, n: n, size: size, quality: quality, output_format: output_format,
          background: background, output_compression: output_compression, input_fidelity: input_fidelity)

    # Parse result and store filename if successful (for continuous editing)
    if session
      begin
        # Extract JSON from result_json (may have prefix and suffix text like "Command has been executed...")
        json_str = result_json.to_s
        if json_str.include?("{") && json_str.include?("}")
          start_idx = json_str.index("{")
          end_idx = json_str.rindex("}")
          json_str = json_str[start_idx..end_idx] if start_idx && end_idx
        end

        parsed = json_str.is_a?(String) ? JSON.parse(json_str) : json_str
        filenames = []

        if parsed.is_a?(Hash)
          if parsed["data"].is_a?(Array) && parsed["data"].first
            file_path = parsed["data"].first["url"] || parsed["data"].first["b64_json"]
            if file_path && file_path.include?("/data/")
              filenames << File.basename(file_path)
            elsif file_path && !file_path.start_with?("http") && !file_path.start_with?("data:")
              filenames << File.basename(file_path)
            end
          end

          filenames << parsed["filename"] if parsed["filename"]

          if parsed["images"].is_a?(Array)
            parsed["images"].each do |img|
              path = img["path"] || img[:path]
              filenames << File.basename(path.to_s) if path
            end
          end
        end

        filenames.compact!
        filenames.uniq!

        unless filenames.empty?
          shared_folder = Monadic::Utils::Environment.shared_volume
          filenames.each do |fname|
            next if fname.to_s.empty?
            dest = File.join(shared_folder, File.basename(fname))
            src_candidates = [
              fname,
              File.join(shared_folder, File.basename(fname))
            ]
            unless File.exist?(dest)
              src = src_candidates.find { |p| File.exist?(p) }
              FileUtils.cp(src, dest) if src && src != dest
            end
          end

          session[:openai_last_image] = filenames.first

          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts "[#{Time.now}] OpenAI Image: Saved last generated image to session: #{filenames.first}"
            extra_log.puts "  All filenames: #{filenames.inspect}"
            extra_log.close
          end

          # Save to monadic state for follow-up edits
          app_key = session.dig(:parameters, "app_name") || "ImageGeneratorOpenAI"

          if respond_to?(:monadic_save_state)
            monadic_save_state(app: app_key, key: "last_images", payload: filenames, session: session)
          end

          # Legacy compatibility for other code paths
          session[:openai_last_image_generation] = { images: filenames }
        end
      rescue JSON::ParserError
        # Ignore JSON parsing errors, just return original result
      end
    end

    result_json
  rescue StandardError => e
    { error: "Image generation failed: #{e.message}" }
  end

  private

  # Fetch last images from monadic state or legacy session keys, tolerant to symbol/string keys.
  def fetch_last_images_from_session(session, app_key)
    # monadic_state lookup (symbol and string keys)
    monadic_state = session[:monadic_state] || session["monadic_state"] || {}
    app_state = monadic_state[app_key] || monadic_state[app_key.to_s] || {}
    last_images_entry = app_state[:last_images] || app_state["last_images"]
    data = last_images_entry && (last_images_entry[:data] || last_images_entry["data"])
    return data if data.is_a?(Array) && !data.empty?

    # legacy openai_last_image_generation
    legacy = session[:openai_last_image_generation] || session["openai_last_image_generation"]
    if legacy && legacy[:images].is_a?(Array) && !legacy[:images].empty?
      return legacy[:images]
    elsif legacy && legacy["images"].is_a?(Array) && !legacy["images"].empty?
      return legacy["images"]
    end

    # single last image fallback
    last_image = session[:openai_last_image] || session["openai_last_image"]
    return [last_image] if last_image

    nil
  end
end

class ImageGeneratorGrok < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include GrokHelper if defined?(GrokHelper)

  # Generate images using Grok/xAI
  # @param prompt [String] Text description of the desired image
  # @param session [Object] Session object (automatically provided)
  # @return [String] Generated image information from the script
  def generate_image_with_grok(prompt:, session: nil)
    # Input validation
    raise ArgumentError, "Prompt is required" if prompt.to_s.strip.empty?

    # Call the method from MediaGenerationHelper (via MonadicHelper)
    # Note: The actual implementation doesn't use model, n, size, or output_format parameters
    # It calls a Ruby script that handles these internally
    result_json = super(prompt: prompt)

    # Parse result and store filename if successful (for continuous reference)
    if session
      begin
        # Extract JSON from result_json (may have prefix and suffix text like "Command has been executed...")
        json_str = result_json.to_s
        if json_str.include?("{") && json_str.include?("}")
          start_idx = json_str.index("{")
          end_idx = json_str.rindex("}")
          json_str = json_str[start_idx..end_idx] if start_idx && end_idx
        end

        parsed = json_str.is_a?(String) ? JSON.parse(json_str) : json_str
        filenames = []

        if parsed.is_a?(Hash)
          # Extract filename from result
          filenames << parsed["filename"] if parsed["filename"]
        end

        filenames.compact!
        filenames.uniq!

        unless filenames.empty?
          # Legacy compatibility
          session[:grok_last_image] = filenames.first

          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts "[#{Time.now}] Grok Image: Saved last generated image to session: #{filenames.first}"
            extra_log.close
          end

          # Save to monadic state for follow-up reference (same pattern as OpenAI)
          app_key = session.dig(:parameters, "app_name") || "ImageGeneratorGrok"

          if respond_to?(:monadic_save_state)
            monadic_save_state(app: app_key, key: "last_images", payload: filenames, session: session)
          end

          # Legacy compatibility for other code paths
          session[:grok_last_image_generation] = { images: filenames }
        end
      rescue JSON::ParserError
        # Ignore JSON parsing errors, just return original result
      end
    end

    result_json
  rescue StandardError => e
    { error: "Image generation failed: #{e.message}" }
  end

  private

  # Fetch last images from monadic state or legacy session keys, tolerant to symbol/string keys.
  def fetch_last_images_from_session(session, app_key)
    # monadic_state lookup (symbol and string keys)
    monadic_state = session[:monadic_state] || session["monadic_state"] || {}
    app_state = monadic_state[app_key] || monadic_state[app_key.to_s] || {}
    last_images_entry = app_state[:last_images] || app_state["last_images"]
    data = last_images_entry && (last_images_entry[:data] || last_images_entry["data"])
    return data if data.is_a?(Array) && !data.empty?

    # legacy grok_last_image_generation
    legacy = session[:grok_last_image_generation] || session["grok_last_image_generation"]
    if legacy && legacy[:images].is_a?(Array) && !legacy[:images].empty?
      return legacy[:images]
    elsif legacy && legacy["images"].is_a?(Array) && !legacy["images"].empty?
      return legacy["images"]
    end

    # single last image fallback
    last_image = session[:grok_last_image] || session["grok_last_image"]
    return [last_image] if last_image

    nil
  end
end

class ImageGeneratorGemini3Preview < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include GeminiHelper if defined?(GeminiHelper)

  # Initialize with special flag for conversation history management
  def initialize(*args)
    super
    # Flag to clear tool call history from orchestration model context
    # This prevents the model from seeing previous tool calls and results
    # which would cause it to repeatedly call the same tool
    @clear_orchestration_history = true
  end

  # Generate or edit images using Gemini 3 Pro Image Preview
  # @param prompt [String] Text description of the desired image or editing instructions
  # @param aspect_ratio [String] Optional aspect ratio (e.g., 16:9, 1:1, 4:5)
  # @param image_size [String] Optional resolution (1K, 2K, 4K)
  # @param session [Object] Session object (automatically provided, contains uploaded images)
  # @return [String] JSON response with success status and filename
  def generate_image_with_gemini3_preview(prompt:, aspect_ratio: nil, image_size: nil, session: nil)
    # Input validation
    raise ArgumentError, "Prompt is required" if prompt.to_s.strip.empty?

    # The actual implementation is in GeminiHelper module
    # which is included in MonadicApp via MonadicHelper
    result_json = super

    # Parse result and store filename if successful (for continuous editing)
    if session
      begin
        # Extract JSON from result_json (may have prefix and suffix text like "Command has been executed...")
        json_str = result_json.to_s
        if json_str.include?("{") && json_str.include?("}")
          start_idx = json_str.index("{")
          end_idx = json_str.rindex("}")
          json_str = json_str[start_idx..end_idx] if start_idx && end_idx
        end

        parsed = json_str.is_a?(String) ? JSON.parse(json_str) : json_str
        filenames = []

        if parsed.is_a?(Hash)
          # Extract filename from result
          filenames << parsed["filename"] if parsed["filename"]
        end

        filenames.compact!
        filenames.uniq!

        unless filenames.empty?
          # Legacy compatibility
          session[:gemini3_last_image] = filenames.first

          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts "[#{Time.now}] Gemini3Preview Image: Saved last generated image to session: #{filenames.first}"
            extra_log.close
          end

          # Save to monadic state for follow-up edits (same pattern as OpenAI)
          app_key = session.dig(:parameters, "app_name") || "ImageGeneratorGemini3Preview"

          if respond_to?(:monadic_save_state)
            monadic_save_state(app: app_key, key: "last_images", payload: filenames, session: session)
          end

          # Legacy compatibility for other code paths
          session[:gemini3_last_image_generation] = { images: filenames }
        end
      rescue JSON::ParserError
        # Ignore JSON parsing errors, just return original result
      end
    end

    result_json
  rescue StandardError => e
    { success: false, error: "Image generation failed: #{e.message}" }.to_json
  end

  private

  # Fetch last images from monadic state or legacy session keys, tolerant to symbol/string keys.
  def fetch_last_images_from_session(session, app_key)
    # monadic_state lookup (symbol and string keys)
    monadic_state = session[:monadic_state] || session["monadic_state"] || {}
    app_state = monadic_state[app_key] || monadic_state[app_key.to_s] || {}
    last_images_entry = app_state[:last_images] || app_state["last_images"]
    data = last_images_entry && (last_images_entry[:data] || last_images_entry["data"])
    return data if data.is_a?(Array) && !data.empty?

    # legacy gemini3_last_image_generation
    legacy = session[:gemini3_last_image_generation] || session["gemini3_last_image_generation"]
    if legacy && legacy[:images].is_a?(Array) && !legacy[:images].empty?
      return legacy[:images]
    elsif legacy && legacy["images"].is_a?(Array) && !legacy["images"].empty?
      return legacy["images"]
    end

    # single last image fallback
    last_image = session[:gemini3_last_image] || session["gemini3_last_image"]
    return [last_image] if last_image

    nil
  end
end
