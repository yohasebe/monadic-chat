# frozen_string_literal: true

module MonadicSharedTools
  module ImageAnalysis
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
          name: "analyze_image",
          description: "Analyze and describe the contents of an image file using vision capabilities",
          parameters: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "Question or instruction about the image"
              },
              image_path: {
                type: "string",
                description: "The filename of the image to analyze"
              }
            },
            required: ["message", "image_path"]
          }
        }
      }
    ].freeze

    def self.tools
      TOOLS
    end
  end
end
