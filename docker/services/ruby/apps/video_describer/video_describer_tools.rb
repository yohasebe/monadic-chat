# Facade methods for Video Describer app
# Provides clear interface for VideoAnalyzeAgent functionality

class VideoDescriberApp < MonadicApp
  # Analyzes video content and generates description
  # @param file [String] The video file to analyze
  # @param fps [Integer] Frames per second to extract (default: 1)
  # @param query [String] Query to guide the analysis (default: "What is happening in the video?")
  # @return [String] Analysis results including description and transcription
  def analyze_video(file:, fps: 1, query: "What is happening in the video?")
    raise ArgumentError, "Filename cannot be empty" if file.to_s.strip.empty?
    raise ArgumentError, "FPS must be positive" unless fps.to_i > 0

    super(file: file, fps: fps, query: query)
  rescue StandardError => e
    "Video analysis failed: #{e.message}"
  end
end
