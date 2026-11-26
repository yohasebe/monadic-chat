# frozen_string_literal: true

module Monadic
  module Library
    # Whether the AI may consult the Library in a chat: the setting
    # LIBRARY_IN_CHATS (Settings, Sources the AI can use; on unless
    # "false"), read when the server starts. Asked whenever a prompt or a
    # tool list is built, so it asks nothing of the Library itself: an empty
    # Library is said by its tools (library_list, library_search).
    module InChats
      KEY = 'LIBRARY_IN_CHATS'

      module_function

      def on?
        value = defined?(CONFIG) && CONFIG.is_a?(Hash) ? CONFIG[KEY] : nil
        value.to_s.strip.downcase != 'false'
      end
    end
  end
end
