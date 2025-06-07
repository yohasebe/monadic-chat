# Facade methods for Video Generator app
# Provides clear interface for Google Veo video generation functionality

class VideoGeneratorGemini < MonadicApp
  # This class doesn't need to define generate_video_with_veo
  # The method will be provided by GeminiHelper when included
  # We only define it here if we need to add validation or transformation
end