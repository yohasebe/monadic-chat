# Facade methods for Image Generator apps
# Provides clear interfaces for image generation functionality

require 'base64'
require_relative '../../lib/monadic/utils/shared_path_guard'
require 'cgi'
require 'fileutils'
require_relative "../../lib/monadic/utils/extra_logger"
require_relative "../../lib/monadic/shared_tools/monadic_session_state"
require_relative "../../lib/monadic/workbench/offer"
require_relative "../../lib/monadic/history/policy"

class ImageGeneratorOpenAI < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include OpenAIHelper if defined?(OpenAIHelper)

  # Initialize with special flag for conversation history management
  def initialize(*args)
    super
    # Prune old tool call history from orchestration model context to prevent
    # the model from seeing stale results and making duplicate calls.
    # Keep the last N rounds so iterative edit/variation chains have context.
    @clear_orchestration_history = true
    @orchestration_keep_rounds = 3
  end

  # Generate, edit, or create variations of images using OpenAI
  # @param operation [String] Type of operation: 'generate', 'edit', or 'variation'
  # @param model [String] Model to use for image generation
  # @param prompt [String] Text description of the desired image
  # @param images [Array<String>] Array of image filenames for editing/variation
  # @param mask [String] Mask image filename for precise editing
  # @param size [String] Image dimensions
  # @param quality [String, nil] Image quality level. The accepted values differ
  #   per model (gpt-image-2 takes auto/low/medium/high; the 2.5 models also
  #   take xhigh/max), so they are resolved from the catalog rather than fixed
  #   here. nil leaves the choice to the API's own default. The DALL-E terms
  #   'standard' and 'hd' have not been accepted since that model was removed.
  # @param output_format [String] Output format ('png', 'webp', 'jpeg')
  # @param background [String] Background color for transparent images
  # @param output_compression [Integer] Compression level for JPEG (1-100)
  # @param session [Object] Session object (automatically provided)
  # @param workbench [Monadic::Workbench::Caller, nil] The chat the reply runs
  #   for (given by the server, never by the model). The image is put on the
  #   chat's workbench, where the user may save it to the shared folder.
  # @return [Monadic::Workbench::Offered, String] The image on the
  #   workbench, or an error
  def generate_image_with_openai(operation:, model:, prompt: nil, images: nil,
                                mask: nil, size: "1024x1024",
                                quality: nil, output_format: "png",
                                background: nil, output_compression: nil, input_fidelity: nil,
                                session: nil, workbench: nil)
    # Input validation
    raise ArgumentError, "Invalid operation" unless %w[generate edit].include?(operation)
    raise ArgumentError, "Model is required" if model.to_s.strip.empty?
    raise ArgumentError, "Prompt is required for generate/edit" if %w[generate edit].include?(operation) && prompt.to_s.strip.empty?
    # Nothing is made without the chat to put it in: never saved elsewhere.
    return "❌ Image generation failed: the chat this reply is for could not be identified." unless workbench

    policy = Monadic::History::Policy
    if policy.private?(workbench.session) || policy.known_private?(workbench.chat_id)
      return "❌ Image generation is not available in a Private chat: nothing of it may be kept."
    end

    shared_folder = Monadic::Utils::Environment.shared_volume

    # Which image to edit is resolved below, in this order: the user's
    # upload in this turn, images of the shared folder the user named, the
    # image that came last on the workbench, an upload in the last user
    # message.
    mask_from_editor = false
    if images.is_a?(Array)
      images = images.filter_map do |img|
        next img unless img.is_a?(Hash)

        img["name"] || img["filename"] || img["title"]
      end
    end

    # A mask the user drew in the mask editor comes as an upload named
    # mask__<image>: the mask and the image it is for are the user's choice,
    # whatever the model passed.
    if operation == "edit" && session && session[:messages]
      last_user_msg = session[:messages].reverse.find { |m| m["role"] == "user" }
      mask_image = last_user_msg && Array(last_user_msg["images"]).find do |img|
        (img["name"] || img["filename"] || img["title"]).to_s.start_with?("mask__")
      end
      if mask_image
        mask = mask_image["name"] || mask_image["filename"] || mask_image["title"]
        images = [mask.delete_prefix("mask__")]
        mask_from_editor = true
      end
    end

    # Logic to resolve/validate images from session if needed (for edit/variation)
    board_input = nil
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
        
        # Written as a plain file of the shared folder, never through a link
        Monadic::Utils::SharedPathGuard.write_file!(file_path, Base64.decode64(base64_data))
        
        return filename
      }
      
      upload_name = ->(img) { img["name"] || img["filename"] || img["title"] }
      # An upload as a file of the shared folder (written there from its
      # data when it is not there yet), or nil.
      take_upload = lambda do |list|
        upload = Array(list).find { |img| (name = upload_name.call(img)) && !name.to_s.start_with?("mask__") }
        next nil unless upload

        name = upload_name.call(upload)
        if upload["data"].to_s.start_with?("data:image/")
          saved = save_base64_image.call(upload["data"], name)
          saved && File.basename(saved)
        elsif check_image_exists.call(name)
          name
        end
      end
      last_user_msg = session && Array(session[:messages]).reverse.find { |m| m["role"] == "user" }
      user_text = last_user_msg ? last_user_msg["text"].to_s : ""
      # Names the model gave count only when the user named those images in
      # their message (or the mask editor did): a name the model chose on
      # its own never takes the place of the image the user is working on.
      named = Array(images).map { |n| File.basename(n.to_s) }.reject(&:empty?)
      user_named = !named.empty? && (mask_from_editor || named.all? { |n| named_in_text?(user_text, n) })
      images = nil
      current_images_valid = false

      # 1. An upload in this turn
      if session && session[:parameters] && (upload = take_upload.call(session[:parameters]["images"]))
        images = [upload]
        current_images_valid = true
      end

      # 2. Images of the shared folder the user named (an upload of an
      # earlier turn with that name is written there first). Every one is
      # found, or the edit stops: another image is never edited instead.
      if !current_images_valid && user_named
        missing = named.reject do |name|
          next true if check_image_exists.call(name) && name

          entry = nil
          Array(session && session[:messages]).reverse_each do |msg|
            entry = Array(msg["images"]).find { |img| (n = upload_name.call(img)) && File.basename(n) == name }
            break if entry
          end
          entry && save_base64_image.call(entry["data"].to_s, name)
        end
        return "❌ The image you named was not found: #{missing.join(', ')}" unless missing.empty?

        images = named
        current_images_valid = true
      end

      # 3. The image that came last on the workbench (saved or not): its
      # bytes, checked, go to the generator through the run's input folder
      if !current_images_valid && workbench
        latest = Monadic::Workbench::Board.existing(workbench.chat_id)&.latest_image
        if latest
          board_input = Monadic::Workbench::Board.for(workbench.chat_id).candidate_input(latest["id"])
          current_images_valid = true
        end
      end

      # 4. An upload in the last user message
      if !current_images_valid && last_user_msg && (upload = take_upload.call(last_user_msg["images"]))
        images = [upload]
        current_images_valid = true
      end

      unless current_images_valid
        return "❌ No image to edit: there is no image in the work screen, and none was uploaded or named."
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
          
          return "❌ Mask file not found. (Target mask: '#{mask}'. #{debug_msg})"
        end
      end
    end
    
    # Validate images presence after resolution
    raise ArgumentError, "Images required for edit" if operation == "edit" && Array(images).empty? && board_input.nil?
    
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

    # One image, made in a job folder of the chat's workbench and offered
    # to the user as a candidate; nothing reaches the shared folder until
    # the user saves it.
    job_dir = Monadic::Workbench::JobOutput.make(workbench.chat_id)
    begin
      job_inputs = []
      if board_input
        ext = board_input[:content_type].split("/").last.sub("jpeg", "jpg")
        job_inputs << Monadic::Workbench::JobOutput.put_input!(job_dir, "input.#{ext}", board_input[:bytes])
      end
      result_json = super(operation: operation, model: model, prompt: prompt, images: images,
            mask: mask, n: 1, size: size, quality: quality, output_format: output_format,
            background: background, output_compression: output_compression, input_fidelity: input_fidelity,
            out_dir: Monadic::Workbench::JobOutput.out_dir(job_dir), job_inputs: job_inputs)
      return result_json if Monadic::Workbench::JobOutput.files(job_dir).empty?

      derived_from = board_input && { id: board_input[:id], sha256: board_input[:sha256] }
      return Monadic::Workbench::Offer.image(workbench, job_dir, derived_from: derived_from)
    rescue Monadic::Workbench::Board::Refused, Monadic::Workbench::ImageCheck::Refused,
           Monadic::Workbench::JobOutput::Refused => e
      return "❌ Image generation failed: #{e.message}"
    ensure
      Monadic::Workbench::JobOutput.remove(job_dir)
    end
  rescue StandardError => e
    "❌ Image generation failed: #{e.message}"
  end

  private

  # Whether text names the file name as a whole, alone or at the end of a
  # path (not as a part of a longer name, such as "cat.png" in "bobcat.png"
  # or "cat.png.bak").
  def named_in_text?(text, name)
    text.to_s.match?(/(?<![A-Za-z0-9_.\-])#{Regexp.escape(name)}(?![A-Za-z0-9_\-]|\.[A-Za-z0-9])/)
  end
end

class ImageGeneratorGrok < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include GrokHelper if defined?(GrokHelper)

  def initialize(*args)
    super
    @clear_orchestration_history = true
    @orchestration_keep_rounds = 3
  end

  # Generate or edit images using Grok/xAI
  # @param operation [String] Type of operation: 'generate' or 'edit'
  # @param prompt [String] Text description of the desired image or editing instructions
  # @param aspect_ratio [String] Aspect ratio from imageGenerationOptions.xai
  # @param images [Array<String>] Array of image filenames for editing (max 5)
  # @param session [Object] Session object (automatically provided)
  # @return [String] Generated image information from the script
  def generate_image_with_grok(operation: "generate", prompt:, aspect_ratio: nil, quality: nil, images: nil, image_model: nil, session: nil)
    # Input validation
    raise ArgumentError, "Invalid operation" unless %w[generate edit].include?(operation)
    raise ArgumentError, "Prompt is required" if prompt.to_s.strip.empty?

    # Image model choice (SSOT: providerDefaults.xai.image). An unknown name is
    # dropped rather than raised — losing the whole request over a stale name is
    # worse than using the default.
    if image_model && !image_model.to_s.strip.empty?
      known = begin
        Monadic::Utils::ModelSpec.get_provider_models("xai", "image") || []
      rescue StandardError
        []
      end
      unless known.include?(image_model.to_s)
        Monadic::Utils::ExtraLogger.log { "Grok Image: unknown image_model #{image_model.inspect}; using provider default" }
        image_model = nil
      end
    end

    # Early check: edit requires either images or session to resolve images from
    if operation == "edit" && (images.nil? || images.empty?) && session.nil?
      return "❌ Image file not found for editing. Please upload an image or generate one first."
    end

    %w[aspect_ratio quality].zip([aspect_ratio, quality]).each do |parameter, value|
      next unless value

      allowed = Monadic::Utils::ModelSpec.image_options("xai", parameter)
      unless allowed.include?(value)
        raise ArgumentError, "Invalid #{parameter}: #{value}. Must be one of: #{allowed.join(', ')}"
      end
    end
    if images.is_a?(Array) && images.size > 5
      return "❌ Maximum 5 images allowed for xAI edit API."
    end

    shared_folder = Monadic::Utils::Environment.shared_volume

    # Which image to edit when the model named none
    if operation == "edit" && (images.nil? || images.empty?) && session
      # The user's upload in this turn comes first: asking to edit "this"
      # photo must not edit the last image this app made instead.
      if (images.nil? || images.empty?) && session[:messages]
        last_user_msg = session[:messages].reverse.find { |m| m["role"] == "user" }
        if last_user_msg && last_user_msg["images"] && !last_user_msg["images"].empty?
          valid_upload = last_user_msg["images"].find { |img|
            name = img["name"] || img["filename"] || img["title"]
            name && !name.to_s.start_with?("mask__")
          }
          if valid_upload
            found_name = valid_upload["name"] || valid_upload["filename"] || valid_upload["title"]
            # Save base64 data to file if needed
            if valid_upload["data"] && valid_upload["data"].start_with?("data:image/")
              base64_data = valid_upload["data"].split(',').last
              file_path = File.join(shared_folder, File.basename(found_name))
              Monadic::Utils::SharedPathGuard.write_file!(file_path, Base64.decode64(base64_data))
              images = [File.basename(found_name)]
            elsif File.exist?(File.join(shared_folder, File.basename(found_name)))
              images = [File.basename(found_name)]
            end
          end
        end
      end

      # Otherwise the last image this app made, for iterative editing.
      if images.nil? || images.empty?
        app_key = session.dig(:parameters, "app_name") || "ImageGeneratorGrok"
        last_images = fetch_last_images_from_session(session, app_key, legacy_prefix: "grok")
        last_image_filename = last_images&.first

        Monadic::Utils::ExtraLogger.log { "Grok Image: Auto-attach check\n  operation: #{operation}\n  app_key: #{app_key}\n  last_images: #{last_images.inspect}" }

        if last_image_filename
          image_path = File.join(shared_folder, File.basename(last_image_filename))
          if File.exist?(image_path)
            images = [File.basename(last_image_filename)]
            Monadic::Utils::ExtraLogger.log { "Grok Image: Auto-attached last generated image: #{last_image_filename}" }
          else
            Monadic::Utils::ExtraLogger.log { "Grok Image: Last generated image file not found: #{image_path}" }
          end
        end
      end

      # Final check
      if images.nil? || images.empty?
        return "❌ Image file not found for editing. Please upload an image or generate one first."
      end
    end

    # Resolve image paths to full paths for the script
    resolved_images = nil
    if images.is_a?(Array) && !images.empty?
      resolved_images = images.map { |img| File.join(shared_folder, File.basename(img)) }
    end

    # Call the method from MediaGenerationHelper (via MonadicHelper)
    result_json = super(prompt: prompt, aspect_ratio: aspect_ratio, quality: quality, operation: operation,
                        images: resolved_images, image_model: image_model)

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

          Monadic::Utils::ExtraLogger.log { "Grok Image: Saved last generated image to session: #{filenames.first}" }

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
    "❌ Image generation failed: #{e.message}"
  end
end

class ImageGeneratorGemini < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include GeminiHelper if defined?(GeminiHelper)

  def initialize(*args)
    super
    @clear_orchestration_history = true
    @orchestration_keep_rounds = 3
  end

  # Generate or edit images using Gemini 3 Image (Nano Banana Flash / Pro)
  # @param prompt [String] Text description of the desired image or editing instructions
  # @param model [String] Image model id: "gemini-nano-banana-2.1" or "gemini-3-pro-image"
  # @param aspect_ratio [String] Optional aspect ratio (e.g., 16:9, 1:1, 4:5)
  # @param image_size [String] Optional resolution (1K, 2K, 4K)
  # @param session [Object] Session object (automatically provided, contains uploaded images)
  # @return [String] JSON response with success status and filename
  def generate_image_with_gemini(prompt:, model: nil, aspect_ratio: nil, image_size: nil, session: nil)
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

          Monadic::Utils::ExtraLogger.log { "Gemini3Preview Image: Saved last generated image to session: #{filenames.first}" }

          # Save to monadic state for follow-up edits (same pattern as OpenAI)
          app_key = session.dig(:parameters, "app_name") || "ImageGeneratorGemini"

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
    "❌ Image generation failed: #{e.message}"
  end
end
