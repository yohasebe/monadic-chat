# frozen_string_literal: true

require_relative 'conversation_record'
require_relative '../workbench/board'
require_relative '../workbench/put'
require_relative '../workspace/chats'
require_relative '../workspace/folders'
require_relative '../utils/shared_path_guard'
require_relative '../utils/privacy/words'

module Monadic
  module Library
    # A chat put on its work screen as a record to keep in the Library
    # (ConversationRecord): written into the chat's folder (workbench/) and
    # put on the board as a file that says which chat it records
    # ({ 'source_chat_id' => … }, kept on the item as it is edited). The
    # chat, its app and its messages are the server's, never the page's.
    module ConversationDraft
      class Refused < StandardError; end

      module_function

      # Whether the app lets its chats be kept in the Library (MDSL
      # `library_save false` does not).
      def app_allows?(app_name)
        name = app_name.to_s.strip
        return true if name.empty? || !defined?(MonadicApp) || !MonadicApp.respond_to?(:app_settings)

        app = MonadicApp.app_settings(name)
        !(app.respond_to?(:settings) && app.settings[:library_save] == false)
      end

      # Puts the record of this connection's chat on its board; returns the
      # item's id. Refused: not_allowed, hides_words, not_saved_by_app,
      # empty, or why the file could not be written or put.
      def put(session, tab:, generation:, live:)
        raise Refused, 'hides_words' if Monadic::Utils::Privacy::Words.marked?(session)
        raise Refused, 'not_allowed' unless live.call(tab) == generation

        chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
        raise Refused, 'not_allowed' unless chat_id

        params = session[:parameters] || {}
        raise Refused, 'not_saved_by_app' unless app_allows?(params['app_name'])

        record = ConversationRecord.of(session[:messages], app_name: params['app_name'], model: params['model'])
        raise Refused, 'empty' unless record

        epoch = Monadic::Workspace::Chats.epoch(chat_id)
        path = write(chat_id, params['app_name'].to_s, record)
        begin
          item, = Monadic::Workbench::Board.for(chat_id).add_file(
            path: path, origin: { actor: :user, source: :draft, tab: tab, generation: generation },
            epoch: epoch, wait: 0, draft: { source_chat_id: chat_id }
          )
        rescue StandardError
          # The record written for this request is not left behind.
          (Monadic::Utils::SharedPathGuard.delete_file!(File.join(Monadic::Workbench::Put.shared_root, path)) rescue nil)
          raise
        end
        item['id']
      rescue Monadic::Workbench::Board::Refused, Monadic::Workbench::Put::Refused => e
        raise Refused, e.message
      end

      def write(chat_id, app_name, record)
        folder = Monadic::Workspace::Folders.ensure_for_chat!(chat_id, app_name: app_name)
        raise Refused, 'unavailable' unless folder[:status] == :ready

        dir = File.join(Monadic::Workbench::Put.shared_root, folder[:relative_dir], Monadic::Workbench::Put::DIRNAME)
        Monadic::Utils::SharedPathGuard.mkdir_p!(dir, strict: true)
        written = Monadic::Workbench::Put.write_new(dir, record[:name], record[:content])
        File.join(folder[:relative_dir], Monadic::Workbench::Put::DIRNAME, File.basename(written))
      end
    end
  end
end
