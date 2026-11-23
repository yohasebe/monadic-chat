# frozen_string_literal: true

require 'fileutils'
require_relative 'store'
require_relative 'board'
require_relative '../history'
require_relative '../history/store'
require_relative '../workspace/chats'
require_relative '../workspace/ids'

module Monadic
  module Workbench
    # How long a chat's workbench folder (its manifest, the pictures sent with
    # its messages, the runs going on) is kept: as long as the chat is. It is
    # removed with the chat from the history, and when the user leaves a chat
    # the history does not keep. At start, the folder of a chat the history
    # does not keep is removed once nothing was written in it for IDLE_DAYS
    # (a tab may still be in that chat, as when no history is kept).
    module Retention
      IDLE_DAYS = 7

      module_function

      # Removes the chat's workbench (nothing when it has none).
      def discard(chat_id, store: Store.default)
        return false unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

        Board.forget(chat_id)
        dir = store.chat_dir(chat_id)
        return false unless File.directory?(dir)

        FileUtils.rm_rf(dir)
        true
      end

      # Whether the history keeps the chat (to be continued from it).
      def kept?(chat_id, history: nil)
        return false unless Monadic::History.enabled?

        (history || Monadic::History::Store.default).resumable?(chat_id)
      rescue StandardError
        # The history cannot say: kept, so nothing is lost.
        true
      end

      # The user left the chat: its workbench goes unless the history keeps
      # the chat.
      def left(chat_id, store: Store.default, history: nil)
        return false if kept?(chat_id, history: history)

        discard(chat_id, store: store)
      end

      # At start: removes the folders of chats the history does not keep, idle
      # for IDLE_DAYS. Returns how many were removed.
      def sweep!(store: Store.default, history: nil, now: Time.now)
        return 0 unless File.directory?(store.root)

        Dir.children(store.root).count do |name|
          next false unless Monadic::Workspace::Ids.valid?(:chat, name)
          next false if kept?(name, history: history)
          next false if now - last_written(store.chat_dir(name)) < IDLE_DAYS * 86_400

          discard(name, store: store)
        end
      end

      # When the folder or what is in it (one level down) was last written.
      def last_written(dir)
        Dir.children(dir).map { |name| File.mtime(File.join(dir, name)) }.push(File.mtime(dir)).max
      rescue SystemCallError
        Time.at(0)
      end
    end
  end
end

# The user replaced the session's chat (Reset, another app, an import, a
# chat continued from the history): its workbench goes unless the history
# keeps the chat.
Monadic::Workspace::Chats.on_change do |event, session|
  next unless event == :replaced

  chat_id = session[Monadic::Workspace::Chats::SESSION_KEY] || session[Monadic::Workspace::Chats::SESSION_KEY.to_s]
  begin
    Monadic::Workbench::Retention.left(chat_id)
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Not removed: #{e.class}" } if defined?(Monadic::Utils::ExtraLogger)
  end
end
