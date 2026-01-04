# frozen_string_literal: true

module Monadic
  module Utils
    # Utility for extracting TTS text from tool parameters based on app settings.
    #
    # When an app has `tts_target` configured in its features, this module
    # extracts the specified parameter value from tool calls and stores it
    # in `session[:tts_text]` for use by the TTS system.
    #
    # tts_target formats:
    #   - [:tool_param, "param_name"] - Extract param_name from any tool call
    #   - [:tool_param, "tool_name", "param_name"] - Extract param_name only from specific tool
    #
    # Example MDSL configuration:
    #   features do
    #     auto_speech true
    #     tts_target :tool_param, "save_response", "message"
    #   end
    #
    module TtsTextExtractor
      module_function

      # Extract TTS text from tool parameters based on app's tts_target setting.
      #
      # @param app [String] App name (key in APPS hash)
      # @param function_name [String] Name of the executed function/tool
      # @param argument_hash [Hash] Arguments passed to the tool (with symbol keys)
      # @param session [Hash] Session hash to store tts_text
      # @return [String, nil] Extracted TTS text if found, nil otherwise
      def extract_tts_text(app:, function_name:, argument_hash:, session:)
        return nil unless defined?(APPS) && APPS[app]

        tts_target = APPS[app]&.settings&.[](:tts_target)
        return nil unless tts_target.is_a?(Array) && tts_target.first == :tool_param

        target_tool = tts_target.length == 3 ? tts_target[1] : nil
        target_param = tts_target.length == 3 ? tts_target[2] : tts_target[1]

        # Check if this tool matches (or no specific tool specified)
        return nil if target_tool && function_name != target_tool.to_s

        tts_text = argument_hash[target_param.to_sym]
        return nil if tts_text.nil? || tts_text.to_s.strip.empty?

        # Store in session for TTS processing
        session[:tts_text] = tts_text.to_s

        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[TtsTextExtractor] Extracted tts_text from #{function_name}.#{target_param}: #{tts_text.to_s[0..100]}"
        end

        tts_text.to_s
      end
    end
  end
end
