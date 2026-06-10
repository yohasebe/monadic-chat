# Facade methods for Video Generator app
# Provides clear interface for video generation functionality

require_relative "../../lib/monadic/shared_tools/monadic_session_state"

class VideoGeneratorGemini < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include GeminiHelper if defined?(GeminiHelper)

  def initialize(*args)
    super
    @clear_orchestration_history = true
    @orchestration_keep_rounds = 3
  end

  # Override to add monadic state saving for uploaded images
  def generate_video_with_veo(prompt:, image_path: nil, aspect_ratio: nil, person_generation: nil, negative_prompt: nil, veo_model: nil, session: nil)
    validate_video_prompt(prompt)

    # Call the parent implementation
    result_json = super

    # Save uploaded image filename to monadic state for later reuse
    if session && image_path && !image_path.to_s.strip.empty?
      begin
        app_key = session.dig(:parameters, "app_name") || "VideoGeneratorGemini"

        if respond_to?(:monadic_save_state)
          monadic_save_state(app: app_key, key: "last_images", payload: [image_path], session: session)
        end

        # Legacy compatibility
        session[:veo_last_image] = image_path
      rescue => e
        # Ignore state saving errors
      end
    end

    result_json
  end

  private

  def validate_video_prompt(prompt)
    raise ArgumentError, "Prompt cannot be empty" if prompt.to_s.strip.empty?
    true
  end
end

class VideoGeneratorGrok < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include GrokHelper if defined?(GrokHelper)

  def initialize(*args)
    super
    @clear_orchestration_history = true
    @orchestration_keep_rounds = 3
  end

  def generate_video_with_grok_imagine(prompt:, duration: nil, aspect_ratio: nil, resolution: nil, image_path: nil, session: nil)
    validate_grok_video_params(prompt: prompt, duration: duration, aspect_ratio: aspect_ratio, resolution: resolution)

    result_json = super

    # Save uploaded image filename to monadic state for later reuse
    if session && image_path && !image_path.to_s.strip.empty?
      begin
        app_key = session.dig(:parameters, "app_name") || "VideoGeneratorGrok"

        if respond_to?(:monadic_save_state)
          monadic_save_state(app: app_key, key: "last_images", payload: [image_path], session: session)
        end

        session[:grok_last_video_image] = image_path
      rescue => e
        # Ignore state saving errors
      end
    end

    result_json
  end

  private

  def validate_grok_video_params(prompt:, duration: nil, aspect_ratio: nil, resolution: nil)
    raise ArgumentError, "Prompt cannot be empty" if prompt.to_s.strip.empty?

    if duration
      d = duration.to_i
      raise ArgumentError, "Invalid duration: #{duration}. Must be between 1 and 15" unless d >= 1 && d <= 15
    end

    if aspect_ratio
      valid_ratios = %w[16:9 9:16 1:1]
      raise ArgumentError, "Invalid aspect_ratio: #{aspect_ratio}. Must be one of: #{valid_ratios.join(', ')}" unless valid_ratios.include?(aspect_ratio)
    end

    if resolution
      valid_resolutions = %w[480p 720p]
      raise ArgumentError, "Invalid resolution: #{resolution}. Must be one of: #{valid_resolutions.join(', ')}" unless valid_resolutions.include?(resolution)
    end

    true
  end
end