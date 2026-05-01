# frozen_string_literal: true

# Auto-load registry for Library importers. Each importer is a small
# module under Monadic::Library::Importers::* that converts some external
# format into a Hash conforming to the monadic-conversation v1 schema.
#
# To dispatch automatically against a known format, call
#   Monadic::Library::Importers.dispatch(input, options)
# which probes each registered importer's can_import? in registration
# order and returns the first successful import.

require_relative 'importers/base'
require_relative 'importers/chatml'
require_relative 'importers/anthropic_messages'
require_relative 'importers/gemini_contents'
require_relative 'importers/monadic_chat_export'
require_relative 'importers/ted_talk'
require_relative 'importers/plain_text'
require_relative 'importers/markdown'
require_relative 'importers/code'

module Monadic
  module Library
    module Importers
      module_function

      # Order matters when formats overlap. Most-specific first:
      #   - MonadicChatExport (requires both 'parameters' and 'messages')
      #   - AnthropicMessages (only 'user' / 'assistant' roles)
      #   - GeminiContents (uses 'contents' + 'parts')
      #   - TedTalk (segments with 'text' + 'start')
      #   - ChatML (catch-all for 'user/assistant/system/tool' role hashes)
      #   - PlainText (last resort, string input only)
      REGISTRY = [
        MonadicChatExport,
        GeminiContents,
        TedTalk,
        AnthropicMessages,
        ChatML,
        PlainText
      ].freeze

      # Probe each importer in registration order and return the first
      # one that handles the input. Returns nil when no match.
      def detect(input)
        REGISTRY.find { |importer| importer.can_import?(input) }
      end

      # Convenience wrapper: detect + import in one call. Raises when no
      # importer recognises the input.
      def dispatch(input, options = {})
        importer = detect(input)
        raise ArgumentError, 'No registered importer recognises the input shape' unless importer
        importer.import(input, options)
      end
    end
  end
end
