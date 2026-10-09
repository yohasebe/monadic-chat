# Facade methods for Video Describer app
# Provides clear interface for VideoAnalyzeAgent functionality

class VideoDescriberApp < MonadicApp
  # Analyzes video content and generates description
  # @param attachment_id [String] A video the user attached to this chat (preferred)
  # @param file [String] A video placed in the shared folder by name
  # @param fps [Integer] Frames per second to extract (default: 1)
  # @param query [String] Query to guide the analysis (default: "What is happening in the video?")
  # @param session [Hash] Injected by the tool runner; names the chat the attachment must belong to
  # @return [String] Analysis results including description and transcription
  def analyze_video(file: nil, attachment_id: nil, fps: 1, query: "What is happening in the video?", session: nil)
    if attachment_id.to_s.strip.empty? && file.to_s.strip.empty?
      raise ArgumentError, "Give the attachment_id of an attached video, or a file name"
    end
    raise ArgumentError, "FPS must be positive" unless fps.to_i > 0

    super(file: file, attachment_id: attachment_id, fps: fps, query: query, session: session)
  rescue StandardError => e
    "Video analysis failed: #{e.message}"
  end
end
