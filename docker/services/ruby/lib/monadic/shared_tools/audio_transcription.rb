# frozen_string_literal: true

module MonadicSharedTools
  module AudioTranscription
    # Available if any audio-capable provider API key is configured
    def self.available?
      %w[OPENAI_API_KEY GEMINI_API_KEY].any? do |key|
        CONFIG && !CONFIG[key].to_s.strip.empty?
      end
    end

    TOOLS = [
      {
        type: "function",
        function: {
          name: "analyze_audio",
          description: "Transcribe audio from an audio file using speech-to-text capabilities",
          parameters: {
            type: "object",
            properties: {
              audio: {
                type: "string",
                description: "The filename of the audio to transcribe"
              }
            },
            required: ["audio"]
          }
        }
      }
    ].freeze

    def self.tools
      TOOLS
    end
  end
end
