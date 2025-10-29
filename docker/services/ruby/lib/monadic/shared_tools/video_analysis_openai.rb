# frozen_string_literal: true

module Monadic
  module SharedTools
    module VideoAnalysisOpenAI
      TOOLS = [
        {
          type: "function",
          function: {
            name: "analyze_video",
            description: "Analyze video content and generate description using OpenAI's multimodal capabilities (image recognition + audio transcription)",
            parameters: {
              type: "object",
              properties: {
                filename: {
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
              required: ["filename"]
            }
          }
        }
      ].freeze

      def self.tools
        TOOLS
      end
    end
  end
end
