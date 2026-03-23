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

class VideoGeneratorOpenAI < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include MonadicHelper

  def initialize(*args)
    super
    @clear_orchestration_history = true
    @orchestration_keep_rounds = 3
  end

  # Compute dynamic max_wait based on video duration
  # Base: 600s (10 min) + 30s per video second
  def self.compute_max_wait(seconds)
    base = 600
    duration = seconds.to_i
    return base if duration <= 0

    base + (duration * 30)
  end

  # Override to add monadic state saving for uploaded images
  def generate_video_with_sora(prompt:, model: nil, size: "1280x720", seconds: "8", image_path: nil, remix_video_id: nil, session: nil)
    # Resolve model via SSOT before validation
    model ||= if defined?(Monadic::Utils::ModelSpec)
                 Monadic::Utils::ModelSpec.default_video_model("openai")
               end

    validate_sora_params(prompt: prompt, model: model, size: size, seconds: seconds)

    # Call the parent implementation with dynamic timeout
    result_json = super(prompt: prompt, model: model, size: size, seconds: seconds,
                        image_path: image_path, remix_video_id: remix_video_id,
                        max_wait: self.class.compute_max_wait(seconds), session: session)

    # Save uploaded image filename to monadic state for later reuse
    if session && image_path && !image_path.to_s.strip.empty?
      begin
        app_key = session.dig(:parameters, "app_name") || "VideoGeneratorOpenAI"

        if respond_to?(:monadic_save_state)
          monadic_save_state(app: app_key, key: "last_images", payload: [image_path], session: session)
        end

        # Legacy compatibility
        session[:sora_last_image] = image_path
      rescue => e
        # Ignore state saving errors
      end
    end

    result_json
  end

  private

  def validate_sora_params(prompt:, model:, size:, seconds:)
    raise ArgumentError, "Prompt cannot be empty" if prompt.to_s.strip.empty?

    valid_models = if defined?(Monadic::Utils::ModelSpec)
                     Monadic::Utils::ModelSpec.get_provider_models("openai", "video") || %w[sora-2 sora-2-pro]
                   else
                     %w[sora-2 sora-2-pro]
                   end
    raise ArgumentError, "Invalid model: #{model}" unless valid_models.include?(model)

    valid_sizes = %w[1280x720 1920x1080 1080x1920 720x1280 1792x1024 1024x1792]
    raise ArgumentError, "Invalid size: #{size}" unless valid_sizes.include?(size)

    valid_seconds = %w[4 8 12 16 20]
    raise ArgumentError, "Invalid duration: #{seconds}" unless valid_seconds.include?(seconds.to_s)

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