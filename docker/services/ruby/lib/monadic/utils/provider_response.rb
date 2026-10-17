# frozen_string_literal: true

require "json"
require_relative "model_spec"

module Monadic
  module Utils
    # Reading provider replies in the helper calls that talk to the APIs
    # directly (image and video description, parallel sub-agents, context
    # extraction), and shaping their short requests from the catalog.
    module ProviderResponse
      module_function

      # The error message in a failed reply, whichever shape the provider
      # uses: {"error": {"message": ...}}, {"error": "..."}, or a top-level
      # "message" / "detail". Falls back to the raw body.
      def error_message(body)
        parsed = body.is_a?(Hash) ? body : (JSON.parse(body.to_s) rescue nil)
        return body.to_s unless parsed.is_a?(Hash)

        error = parsed["error"]
        message = error.is_a?(Hash) ? error["message"] : error
        message ||= parsed["message"] || parsed["detail"]
        message.is_a?(String) && !message.empty? ? message : body.to_s
      end

      # The text of a Claude reply: every text block, in order. Thinking
      # blocks come first on models that think by default.
      def claude_text(content)
        return nil unless content.is_a?(Array)

        texts = content.select { |block| block.is_a?(Hash) && block["type"] == "text" }.map { |block| block["text"].to_s }
        texts.empty? ? nil : texts.join("\n")
      end

      # The text of a chat-completions message: a string, or (Mistral
      # reasoning models) an array of thinking and text parts.
      def message_text(content)
        return content unless content.is_a?(Array)

        texts = content.select { |part| part.is_a?(Hash) && part["type"] == "text" }.map { |part| part["text"].to_s }
        texts.empty? ? nil : texts.join
      end

      # Extra fields for a short Claude request (a description, a JSON
      # extraction) that should not spend its budget on reasoning. A model
      # that thinks when `thinking` is left out gets its lowest effort and
      # room for that thinking on top of the answer; others get nothing.
      def claude_light_request(model, max_tokens)
        return { max_tokens: max_tokens } unless ModelSpec.thinking_on_by_default?(model)

        fields = { max_tokens: [max_tokens * 4, 4000].max }
        lowest = ModelSpec.lowest_reasoning_effort(model)
        fields[:output_config] = { effort: lowest } if lowest && lowest != "none"
        fields
      end
    end
  end
end
