# frozen_string_literal: true

module MonadicSharedTools
  module VideoAnalysis
    # Available if any vision-capable provider API key is configured
    def self.available?
      %w[OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY XAI_API_KEY].any? do |key|
        CONFIG && !CONFIG[key].to_s.strip.empty?
      end
    end

    TOOLS = [
      {
        type: "function",
        function: {
          name: "analyze_video",
          description: "Analyze video content and generate description using vision capabilities (image recognition + audio transcription)",
          parameters: {
            type: "object",
            properties: {
              attachment_id: {
                type: "string",
                description: "The attachment_id of a video the user attached to this chat (use this when one is given)"
              },
              file: {
                type: "string",
                description: "The name of a video file in the shared folder (only when no attachment_id is given)"
              },
              fps: {
                type: "integer",
                description: "Frames per second to extract (default: 1)"
              },
              query: {
                type: "string",
                description: "Query to guide the analysis"
              },
              detailed: {
                type: "boolean",
                description: "true only when the user asks for a detailed or thorough analysis: a video longer than " \
                             "ten minutes is then described in up to five parts (longer and costlier)"
              }
            },
            required: []
          }
        }
      }
    ].freeze

    def self.tools
      TOOLS
    end
  end
end
