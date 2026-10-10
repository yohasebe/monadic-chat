# Facade methods for the Video Describer apps
# Provides clear interface for VideoAnalyzeAgent functionality
#
# One class per provider. Each defines analyze_video in its own body, so that
# it comes before the modules the MDSL includes (VideoAnalyzeAgent among them)
# and `super` reaches the agent. The OpenAI app keeps its original name so
# that saved settings and sessions still find it.

module VideoDescriberChecks
  def self.check!(file, attachment_id, fps)
    if attachment_id.to_s.strip.empty? && file.to_s.strip.empty?
      raise ArgumentError, "Give the attachment_id of an attached video, or a file name"
    end
    raise ArgumentError, "FPS must be positive" unless fps.to_i > 0
  end
end

class VideoDescriberApp < MonadicApp
  # Analyzes video content and generates description
  # @param attachment_id [String] A video the user attached to this chat (preferred)
  # @param file [String] A video placed in the shared folder by name
  # @param fps [Integer] Frames per second to extract (default: 1)
  # @param query [String] Query to guide the analysis (default: "What is happening in the video?")
  # @param session [Hash] Injected by the tool runner; names the chat the attachment must belong to
  # @return [String] Analysis results including description and transcription
  def analyze_video(file: nil, attachment_id: nil, fps: 1, query: "What is happening in the video?", session: nil)
    VideoDescriberChecks.check!(file, attachment_id, fps)
    super(file: file, attachment_id: attachment_id, fps: fps, query: query, session: session)
  rescue StandardError => e
    "Video analysis failed: #{e.message}"
  end
end

class VideoDescriberGemini < MonadicApp
  def analyze_video(file: nil, attachment_id: nil, fps: 1, query: "What is happening in the video?", session: nil)
    VideoDescriberChecks.check!(file, attachment_id, fps)
    super(file: file, attachment_id: attachment_id, fps: fps, query: query, session: session)
  rescue StandardError => e
    "Video analysis failed: #{e.message}"
  end
end

class VideoDescriberGrok < MonadicApp
  def analyze_video(file: nil, attachment_id: nil, fps: 1, query: "What is happening in the video?", session: nil)
    VideoDescriberChecks.check!(file, attachment_id, fps)
    super(file: file, attachment_id: attachment_id, fps: fps, query: query, session: session)
  rescue StandardError => e
    "Video analysis failed: #{e.message}"
  end
end
