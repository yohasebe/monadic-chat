# Facade methods for Video Generator app
# Provides clear interface for Google Veo video generation functionality

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