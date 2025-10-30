# frozen_string_literal: true

module Monadic
  module SharedTools
    module ContentAnalysisOpenAI
      # Check if OpenAI API key is available
      def self.available?
        CONFIG && !CONFIG["OPENAI_API_KEY"].to_s.strip.empty?
      end

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
        },
        {
          type: "function",
          function: {
            name: "analyze_image",
            description: "Analyze and describe the contents of an image file using OpenAI's vision capabilities",
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
        },
        {
          type: "function",
          function: {
            name: "analyze_audio",
            description: "Analyze and transcribe audio from an audio file using OpenAI's Whisper",
            parameters: {
              type: "object",
              properties: {
                audio: {
                  type: "string",
                  description: "The filename of the audio to analyze"
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
end
