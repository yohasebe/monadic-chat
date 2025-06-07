# Facade methods for Video Describer app
# Provides clear interface for VideoAnalyzeAgent functionality

class VideoDescriberApp < MonadicApp
  # Analyzes video content and generates description
  # @param filename [String] The video file to analyze
  # @param fps [Integer] Frames per second to extract (default: 1)
  # @param query [String] Query to guide the analysis (default: "What is happening in the video?")
  # @return [Hash] Analysis results including description and transcription
  def analyze_video(filename:, fps: 1, query: "What is happening in the video?")
    # Input validation
    raise ArgumentError, "Filename cannot be empty" if filename.to_s.strip.empty?
    raise ArgumentError, "FPS must be positive" unless fps.to_i > 0
    
    # Call the method from VideoAnalyzeAgent module with correct parameter name
    super(file: filename, fps: fps, query: query)
  rescue StandardError => e
    { 
      error: "Video analysis failed: #{e.message}",
      description: "Error occurred during video analysis",
      transcription: ""
    }
  end
end