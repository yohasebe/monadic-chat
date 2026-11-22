# frozen_string_literal: true

require 'json'

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
      # function_return: what the tool returned. When the tool the app names
      # (with its parameter) succeeded, the reply ends with it: the text is
      # the reply, and the model is not asked again (reply_ended).
      def extract_tts_text(app:, function_name:, argument_hash:, session:, function_return: nil)
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
        session[:tts_reply_ended] = true if target_tool && succeeded?(function_return)

        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[TtsTextExtractor] Extracted tts_text from #{function_name}.#{target_param}: #{tts_text.to_s[0..100]}"
        end

        tts_text.to_s
      end

      # The reply a tool ended (extract_tts_text), taken once: the results a
      # provider's request returns, with no text of the model's (the text
      # the tool was given is the reply), or nil. emit gets the reply's end.
      def reply_ended(session, &emit)
        return nil unless session.respond_to?(:delete) && session.delete(:tts_reply_ended)

        emit&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
        [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "" } }] }]
      end

      # Whether a tool's return says it succeeded: { success: true }, as a
      # Hash or as JSON.
      def succeeded?(function_return)
        value = function_return.is_a?(String) ? JSON.parse(function_return) : function_return
        value.is_a?(Hash) && (value["success"] == true || value[:success] == true)
      rescue JSON::ParserError
        false
      end
    end
  end
end
