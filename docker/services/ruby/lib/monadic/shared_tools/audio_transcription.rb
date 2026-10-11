# frozen_string_literal: true

module MonadicSharedTools
  module AudioTranscription
    # Available if any audio-capable provider API key is configured
    def self.available?
      %w[OPENAI_API_KEY GEMINI_API_KEY XAI_API_KEY].any? do |key|
        CONFIG && !CONFIG[key].to_s.strip.empty?
      end
    end

    TOOLS = [
      {
        type: "function",
        function: {
          name: "analyze_audio",
          description: "Transcribe the speech in an audio file in the shared folder. Each line of the " \
                       "transcript starts with the time in the recording of the speech it holds, and subtitle " \
                       "files are made from it. Recordings up to 50 minutes.",
          parameters: {
            type: "object",
            properties: {
              attachment_id: {
                type: "string",
                description: "The attachment_id of an audio file the user attached to this chat " \
                             "(given in the message as \"Attached audio: ... (attachment_id: ...)\"). Use this for attached files."
              },
              audio: {
                type: "string",
                description: "The file name of an audio file placed in the shared folder (mp3, m4a, wav, ogg, " \
                             "opus, flac, webm, aac). Only for files not attached."
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
