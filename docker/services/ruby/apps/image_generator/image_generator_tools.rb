# Facade methods for Image Generator apps
# Provides clear interfaces for image generation functionality

class ImageGeneratorOpenAI < MonadicApp
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
  # @return [Hash] Generated image URLs and metadata
  def generate_image_with_openai(operation:, model:, prompt: nil, images: nil, 
                                mask: nil, n: 1, size: "1024x1024", 
                                quality: "standard", output_format: "png",
                                background: nil, output_compression: nil, input_fidelity: nil)
    # Input validation
    raise ArgumentError, "Invalid operation" unless %w[generate edit variation].include?(operation)
    raise ArgumentError, "Model is required" if model.to_s.strip.empty?
    raise ArgumentError, "Prompt is required for generate/edit" if %w[generate edit].include?(operation) && prompt.to_s.strip.empty?
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
    super
  rescue StandardError => e
    { error: "Image generation failed: #{e.message}" }
  end
end

class ImageGeneratorGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  # Generate images using Grok/xAI
  # @param prompt [String] Text description of the desired image
  # @return [String] Generated image information from the script
  def generate_image_with_grok(prompt:)
    # Input validation
    raise ArgumentError, "Prompt is required" if prompt.to_s.strip.empty?

    # Call the method from MediaGenerationHelper (via MonadicHelper)
    # Note: The actual implementation doesn't use model, n, size, or output_format parameters
    # It calls a Ruby script that handles these internally
    super
  rescue StandardError => e
    { error: "Image generation failed: #{e.message}" }
  end
end

class ImageGeneratorGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  # Generate or edit images using Google's AI models
  # @param prompt [String] Text description of the desired image or editing instructions
  # @param operation [String] Type of operation: 'generate' or 'edit'
  # @param model [String] Model to use: 'imagen4-fast' (default, fastest), 'imagen4' (standard), 'imagen4-ultra' (highest quality), 'imagen3' (legacy), 'gemini' (for editing)
  # @param session [Object] Session object (automatically provided)
  # @return [String] JSON response with success status and filename
  def generate_image_with_gemini(prompt:, operation: "generate", model: "gemini", session: nil)
    # Input validation
    raise ArgumentError, "Prompt is required" if prompt.to_s.strip.empty?
    
    # The actual implementation is in GeminiHelper module
    # which is included in MonadicApp via MonadicHelper
    super
  rescue StandardError => e
    { success: false, error: "Image generation failed: #{e.message}" }.to_json
  end
end