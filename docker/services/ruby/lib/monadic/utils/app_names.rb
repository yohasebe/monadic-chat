# frozen_string_literal: true

module Monadic
  module Utils
    # The names apps had before they were merged into another app, and the
    # app each one is now. A saved chat, the state it keeps and a knowledge
    # base entry carry the name of the app they were made with; what reads
    # them asks here, so an old name finds the app that took its place.
    # Only the names listed are changed.
    module AppNames
      RENAMED = %w[OpenAI Claude Gemini Grok Mistral DeepSeek Cohere].to_h do |provider|
        ["ChatPlus#{provider}", "Chat#{provider}"]
      end.freeze

      FORMER = RENAMED.each_with_object({}) { |(old, now), out| (out[now] ||= []) << old }
                      .transform_values(&:freeze).freeze

      module_function

      # The app a name stands for now; any other value is returned as given.
      def current(name)
        RENAMED.fetch(name.to_s, name)
      end

      # The name of an app with the names it took the place of.
      def with_former(name)
        [name.to_s, *FORMER.fetch(name.to_s, [])]
      end
    end
  end
end
