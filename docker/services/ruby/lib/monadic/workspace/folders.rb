# frozen_string_literal: true

require_relative 'ids'
require_relative 'chats'
require_relative 'ledger'
require_relative '../utils/environment'

module Monadic
  module Workspace
    # Creates the folder a chat keeps its files in, the first time the chat
    # needs one:
    #
    #   <shared folder>/conversations/<time>_<app>_<workspace id>/
    #     inputs/     attachments as the user gave them
    #     work/       files tools work on
    #     artifacts/  files tools produce
    #
    # The time and app name are there for people browsing the folder. The
    # ledger, not the name, says which chat a folder belongs to: a renamed
    # folder is reported missing, never searched for.
    module Folders
      ROOT_DIRNAME = 'conversations'
      SUBDIRS = %w[inputs work artifacts].freeze
      SLUG_MAX = 32

      class Unavailable < StandardError; end

      @mutex = Mutex.new

      module_function

      # Returns { workspace_id:, relative_dir:, path:, status: } for the
      # session's chat, creating the folder when the chat has none yet.
      # status is :ready, or :missing when the ledger names a folder that is
      # no longer there (it is not recreated under the same record).
      def ensure!(session, app_name:, ledger: Ledger.default, now: Time.now)
        ensure_for_chat!(Chats.current(session), app_name: app_name, ledger: ledger, now: now)
      end

      # The same for a chat id fixed earlier, e.g. when an upload started.
      def ensure_for_chat!(chat_id, app_name:, ledger: Ledger.default, now: Time.now)
        raise ArgumentError, 'invalid chat id' unless Ids.valid?(:chat, chat_id)

        @mutex.synchronize do
          record = ledger.workspace_for_chat(chat_id)
          return describe(record) if record

          workspace_id = Ids.generate(:workspace)
          dirname = "#{now.strftime('%Y%m%d-%H%M%S')}_#{slug(app_name)}_#{workspace_id}"
          relative_dir = File.join(ROOT_DIRNAME, dirname)
          create_folder(relative_dir)
          describe(ledger.register_workspace(chat_id: chat_id, workspace_id: workspace_id,
                                             app_name: app_name, relative_dir: relative_dir,
                                             created_at: now))
        end
      end

      # The session's workspace if it has one; never creates a folder.
      def lookup(session, ledger: Ledger.default)
        chat_id = session[Chats::SESSION_KEY]
        return nil unless Ids.valid?(:chat, chat_id)

        record = ledger.workspace_for_chat(chat_id)
        record && describe(record)
      end

      def slug(app_name)
        text = app_name.to_s.gsub(/([a-z0-9])([A-Z])/, '\1-\2').downcase
        text = text.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')[0, SLUG_MAX].sub(/-+\z/, '')
        text.empty? ? 'chat' : text
      end

      def describe(record)
        path = File.join(Monadic::Utils::Environment.data_path, record[:relative_dir])
        status = File.directory?(path) && !File.symlink?(path) ? :ready : :missing
        { workspace_id: record[:workspace_id], relative_dir: record[:relative_dir], path: path, status: status }
      end

      # Each level is created exclusively and checked to be a real folder,
      # so a link planted at conversations/ cannot send files elsewhere.
      def create_folder(relative_dir)
        data_root = File.realpath(Monadic::Utils::Environment.data_path)
        root = File.join(data_root, ROOT_DIRNAME)
        begin
          Dir.mkdir(root)
        rescue Errno::EEXIST
          nil
        end
        if File.symlink?(root) || !File.directory?(root) || File.realpath(root) != root
          raise Unavailable, "#{ROOT_DIRNAME}/ in the shared folder is not a plain folder"
        end

        folder = File.join(data_root, relative_dir)
        Dir.mkdir(folder)
        SUBDIRS.each { |name| Dir.mkdir(File.join(folder, name)) }
        folder
      rescue Errno::ENOENT, Errno::EACCES, Errno::EEXIST, Errno::ENOTDIR => e
        raise Unavailable, "could not create the chat folder (#{e.class.name.split('::').last})"
      end
    end
  end
end
