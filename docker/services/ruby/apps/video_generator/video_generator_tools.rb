# Facade methods for Video Generator app
# Provides clear interface for video generation functionality

require_relative "../../lib/monadic/shared_tools/monadic_session_state"

class VideoGeneratorGemini < MonadicApp
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  include GeminiHelper if defined?(GeminiHelper)

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

  # Override to add monadic state saving for uploaded images
  def generate_video_with_sora(prompt:, model: "sora-2", size: "1280x720", seconds: "8", image_path: nil, remix_video_id: nil, session: nil)
    validate_sora_params(prompt: prompt, model: model, size: size, seconds: seconds)

    # Call the parent implementation
    result_json = super

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

    valid_models = %w[sora-2 sora-2-pro]
    raise ArgumentError, "Invalid model: #{model}" unless valid_models.include?(model)

    valid_sizes = %w[1280x720 1920x1080 1080x1920 720x1280 1792x1024 1024x1792]
    raise ArgumentError, "Invalid size: #{size}" unless valid_sizes.include?(size)

    valid_seconds = %w[4 8 12 16]
    raise ArgumentError, "Invalid duration: #{seconds}" unless valid_seconds.include?(seconds.to_s)

    true
  end
end