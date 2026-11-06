# Facade methods for Image Generator apps
# Provides clear interfaces for image generation functionality

require 'base64'
require_relative '../../lib/monadic/utils/shared_path_guard'
require 'cgi'
require 'fileutils'
require_relative "../../lib/monadic/utils/extra_logger"
require_relative "../../lib/monadic/shared_tools/monadic_session_state"
require_relative "../../lib/monadic/workbench/image_tool"

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
  #   for (given by the server, never by the model). The image is placed in
  #   the chat's folder of the shared folder and shown on its workbench.
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
    if (refused = Monadic::Workbench::ImageTool.refusal(workbench))
      return refused
    end

    # Which image an edit starts from (Monadic::Workbench::ImageTool)
    board_input = nil
    if operation == "edit"
      begin
        source = Monadic::Workbench::ImageTool.edit_source(session: session, workbench: workbench, images: images, mask: mask)
      rescue Monadic::Workbench::ImageTool::NoSource => e
        return e.message
      end
      images = source.images
      mask = source.mask
      board_input = source.board_input
      # The mask is a file of the shared folder (an upload of an earlier
      # turn with its name is written there first).
      if mask && !Monadic::Workbench::ImageTool.shared_image?(mask) &&
         !Monadic::Workbench::ImageTool.restore_upload(session, File.basename(mask))
        return "❌ Mask file not found. (Target mask: '#{mask}')"
      end
    end

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

    # One image, made in a job folder of the chat's workbench, then placed
    # in the chat's folder of the shared folder.
    Monadic::Workbench::ImageTool.run_job(workbench, board_input: board_input) do |out_dir, inputs|
      super(operation: operation, model: model, prompt: prompt, images: images,
            mask: mask, n: 1, size: size, quality: quality, output_format: output_format,
            background: background, output_compression: output_compression, input_fidelity: input_fidelity,
            out_dir: out_dir, job_inputs: inputs)
    end
  rescue StandardError => e
    "❌ Image generation failed: #{e.message}"
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
  # @param workbench [Monadic::Workbench::Caller, nil] The chat the reply runs
  #   for (given by the server, never by the model). The image is placed in
  #   the chat's folder of the shared folder and shown on its workbench.
  # @return [Monadic::Workbench::Offered, String] The image on the
  #   workbench, or an error
  def generate_image_with_grok(operation: "generate", prompt:, aspect_ratio: nil, quality: nil, images: nil, image_model: nil,
                              session: nil, workbench: nil)
    # Input validation
    raise ArgumentError, "Invalid operation" unless %w[generate edit].include?(operation)
    raise ArgumentError, "Prompt is required" if prompt.to_s.strip.empty?

    if (refused = Monadic::Workbench::ImageTool.refusal(workbench))
      return refused
    end

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

    %w[aspect_ratio quality].zip([aspect_ratio, quality]).each do |parameter, value|
      next unless value

      allowed = Monadic::Utils::ModelSpec.image_options("xai", parameter)
      unless allowed.include?(value)
        raise ArgumentError, "Invalid #{parameter}: #{value}. Must be one of: #{allowed.join(', ')}"
      end
    end
    # Which image an edit starts from (Monadic::Workbench::ImageTool)
    board_input = nil
    if operation == "edit"
      begin
        source = Monadic::Workbench::ImageTool.edit_source(session: session, workbench: workbench, images: images)
      rescue Monadic::Workbench::ImageTool::NoSource => e
        return e.message
      end
      return "❌ xAI image editing does not take a mask: describe the change in words instead." if source.mask

      images = source.images
      board_input = source.board_input
      return "❌ Maximum 5 images allowed for xAI edit API." if Array(images).size > 5
    end

    shared_folder = Monadic::Utils::Environment.shared_volume
    resolved_images = Array(images).map { |img| File.join(shared_folder, Monadic::Workbench::ImageTool.shared_name(img)) }

    # One image, made in a job folder of the chat's workbench, then placed
    # in the chat's folder of the shared folder.
    Monadic::Workbench::ImageTool.run_job(workbench, board_input: board_input) do |out_dir, inputs|
      super(prompt: prompt, aspect_ratio: aspect_ratio, quality: quality, operation: operation,
            images: resolved_images.empty? ? nil : resolved_images, image_model: image_model,
            out_dir: out_dir, job_inputs: inputs)
    end
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

  # Generate or edit images using Gemini 3 Image (Nano Banana Flash / Pro).
  # The image is placed in the chat's folder of the shared folder and shown
  # on its workbench (Monadic::Workbench::ImageTool).
  # @param operation [String] "generate" or "edit"
  # @param prompt [String] Text description of the desired image or editing instructions
  # @param model [String] Image model id: "gemini-nano-banana-2.1" or "gemini-3-pro-image"
  # @param aspect_ratio [String] Optional aspect ratio (e.g., 16:9, 1:1, 4:5)
  # @param image_size [String] Optional resolution (1K, 2K, 4K)
  # @param images [Array<String>] Shared-folder paths the user named for an edit
  # @param session [Object] Session object (automatically provided)
  # @param workbench [Monadic::Workbench::Caller] The reply's chat (given by the server)
  # @return [Monadic::Workbench::Offered, String] The image on the workbench, or why there is none
  def generate_image_with_gemini(prompt:, operation: "generate", model: nil, aspect_ratio: nil, image_size: nil, images: nil,
                                 session: nil, workbench: nil)
    raise ArgumentError, "Invalid operation" unless %w[generate edit].include?(operation)
    raise ArgumentError, "Prompt is required" if prompt.to_s.strip.empty?

    if (refused = Monadic::Workbench::ImageTool.refusal(workbench))
      return refused
    end

    models = Monadic::Utils::ModelSpec.image_options("gemini", "model")
    model = models.first if model.to_s.strip.empty?
    return "❌ Unknown image model: #{model}. Use one of: #{models.join(', ')}" unless models.include?(model)

    # Which images an edit starts from (Monadic::Workbench::ImageTool)
    inputs = []
    board_input = nil
    if operation == "edit"
      source = Monadic::Workbench::ImageTool.edit_source(session: session, workbench: workbench, images: images)
      return "❌ Gemini image editing does not take a mask: describe the change in words instead." if source.mask

      board_input = source.board_input
      names = Array(source.images)
      return "❌ Maximum #{GEMINI_MAX_INPUTS} images allowed for Gemini image editing." if names.size > GEMINI_MAX_INPUTS

      inputs = names.map { |name| Monadic::Workbench::ImageTool.shared_input(name) }
    end

    Monadic::Workbench::ImageTool.run_job(workbench, board_input: board_input) do |out_dir, job_inputs|
      inputs += job_inputs.map { |path| Monadic::Workbench::ImageTool.job_input(path) }
      inline = inputs.map { |input| { "data" => "data:#{input[:content_type]};base64,#{Base64.strict_encode64(input[:bytes])}" } }
      generate_image_with_gemini_native(prompt: prompt, model: model, aspect_ratio: aspect_ratio, image_size: image_size,
                                        images: inline, out_dir: out_dir)
    end
  rescue Monadic::Workbench::ImageTool::NoSource => e
    e.message
  rescue StandardError => e
    "❌ Image generation failed: #{e.message}"
  end

  GEMINI_MAX_INPUTS = 14
end
