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
              file: {
                type: "string",
                description: "The video file to analyze"
              },
              fps: {
                type: "integer",
                description: "Frames per second to extract (default: 1)"
              },
              query: {
                type: "string",
                description: "Query to guide the analysis"
              }
            },
            required: ["file"]
          }
        }
      }
    ].freeze

    def self.tools
      TOOLS
    end
  end
end
