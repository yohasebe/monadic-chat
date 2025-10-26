# Facade methods for Video Generator app
# Provides clear interface for video generation functionality

class VideoGeneratorGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  # This class doesn't need to define generate_video_with_veo
  # The method will be provided by GeminiHelper when included
  # We only define it here if we need to add validation or transformation

  private

  def validate_video_prompt(prompt)
    raise ArgumentError, "Prompt cannot be empty" if prompt.to_s.strip.empty?
    true
  end
end

class VideoGeneratorOpenAI < MonadicApp
  include MonadicHelper
  # The generate_video_with_sora method is provided by MonadicHelper
  # via media_generation_helper.rb

  private

  def validate_sora_params(prompt:, model:, size:, seconds:)
    raise ArgumentError, "Prompt cannot be empty" if prompt.to_s.strip.empty?

    valid_models = %w[sora-2 sora-2-pro]
    raise ArgumentError, "Invalid model: #{model}" unless valid_models.include?(model)

    valid_sizes = %w[1280x720 1920x1080 1080x1920 720x1280]
    raise ArgumentError, "Invalid size: #{size}" unless valid_sizes.include?(size)

    valid_seconds = %w[4 8 16]
    raise ArgumentError, "Invalid duration: #{seconds}" unless valid_seconds.include?(seconds.to_s)

    true
  end
end