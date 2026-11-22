# frozen_string_literal: true

require 'json'
require_relative 'ids'
require_relative 'folders'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workspace
    # The notebooks of a chat, named by their path in the shared folder:
    # new ones go in the work/ folder of the chat's folder, and a name the
    # model gives is read as one of the chat's notebooks, never as a file of
    # another chat. A chat's notebooks are those in its work/ folder and
    # those on its work screen (a notebook made before chats had folders).
    # A notebook at the top of the shared folder is taken when it is named
    # with "./" before it.
    module Notebooks
      class Refused < StandardError; end

      EXTENSION = '.ipynb'
      NAME_MAX = 80
      NAME_TRIES = 100
      # What nbformat makes for a new notebook.
      EMPTY = JSON.generate('cells' => [], 'metadata' => {}, 'nbformat' => 4, 'nbformat_minor' => 5)

      module_function

      # Makes an empty notebook in the chat's work/ folder and returns its
      # path. A name already taken gets a number (analysis-2.ipynb).
      def create(chat_id, app_name:, name:)
        work = work_dir(chat_id, app_name: app_name, create: true)
        stem = safe_stem(name)
        guard = Monadic::Utils::SharedPathGuard
        dir = File.join(root, work)
        guard.mkdir_p!(dir, strict: true)
        NAME_TRIES.times do |i|
          file = "#{i.zero? ? stem : "#{stem}-#{i + 1}"}#{EXTENSION}"
          begin
            guard.write_file!(File.join(dir, file), EMPTY, replace: false, sync_dir: true, strict: true)
            return File.join(work, file)
          rescue Errno::EEXIST
            next
          end
        end
        raise Refused, 'no free name for the notebook in the chat folder'
      rescue Folders::Unavailable, Monadic::Utils::SharedPathGuard::InvalidPath => e
        raise Refused, e.message
      end

      # The chat's notebook a name stands for: its path, or Refused saying
      # which notebooks the chat has. current: the path to take for no name.
      def resolve(chat_id, name, current: nil)
        text = name.to_s.strip
        text = current.to_s if text.empty?
        raise Refused, 'Name the notebook: this chat has none yet.' if text.empty?

        text = "#{text}#{EXTENSION}" unless text.downcase.end_with?(EXTENSION)
        return top_level(text.delete_prefix('./')) if text.start_with?('./')

        own = known(chat_id)
        return text if text.include?('/') && own.include?(text)

        by_name = text.include?('/') ? [] : own.select { |path| File.basename(path) == text }
        return by_name.first if by_name.length == 1
        raise Refused, ambiguous(text, by_name) if by_name.length > 1

        raise Refused, not_found(text, own)
      end

      # How a notebook is named to the model: its path, with ./ before one
      # at the top of the shared folder.
      def named(path)
        path.include?('/') ? path : "./#{path}"
      end

      # The chat's notebooks, the latest changed first.
      def known(chat_id)
        paths = in_work_dir(chat_id) + on_board(chat_id)
        paths.uniq.select { |path| Folders.real_path(path) }
             .sort_by { |path| -File.mtime(File.join(root, path)).to_f }
      end

      # The work/ folder of the chat's folder, relative to the shared folder.
      def work_dir(chat_id, app_name: nil, create: false)
        raise Refused, 'There is no chat to keep the notebook in.' unless Ids.valid?(:chat, chat_id)

        folder = if create
                   Folders.ensure_for_chat!(chat_id, app_name: app_name)
                 else
                   record = Ledger.default.workspace_for_chat(chat_id)
                   record && Folders.describe(record)
                 end
        return nil unless folder
        raise Refused, "The chat's folder is no longer in the shared folder." unless folder[:status] == :ready

        File.join(folder[:relative_dir], 'work')
      end

      def in_work_dir(chat_id)
        work = work_dir(chat_id)
        dir = work && Folders.real_path(work, :directory)
        return [] unless dir

        Dir.children(dir).select { |name| name.downcase.end_with?(EXTENSION) }.map { |name| File.join(work, name) }
      rescue Refused, SystemCallError, Ledger::Unreadable
        []
      end

      def on_board(chat_id)
        board = Monadic::Workbench::Board.existing(chat_id) if defined?(Monadic::Workbench::Board)
        return [] unless board

        board.snapshot[:items].filter_map do |item|
          path = item[:path].to_s
          path if item[:kind] == 'file' && path.downcase.end_with?(EXTENSION)
        end
      rescue StandardError
        []
      end

      def top_level(name)
        unless !name.include?('/') && Folders.real_path(name)
          raise Refused, "There is no notebook #{name} at the top of the shared folder."
        end

        name
      end

      def safe_stem(name)
        stem = File.basename(name.to_s.strip)
        stem = stem[0...-EXTENSION.length] if stem.downcase.end_with?(EXTENSION)
        stem = stem.gsub(/[^\p{L}\p{N}_-]+/, '_').gsub(/\A[_-]+|[_-]+\z/, '')[0, NAME_MAX]
        stem.nil? || stem.empty? ? 'notebook' : stem
      end

      def ambiguous(text, paths)
        "More than one notebook of this chat is named #{text}: #{paths.map { |path| named(path) }.join(', ')}. Give its path."
      end

      def not_found(text, own)
        said = "#{text} is not a notebook of this chat."
        said += " Its notebooks: #{own.map { |path| named(path) }.join(', ')}." unless own.empty?
        top = File.basename(text)
        if Folders.real_path(top)
          said += " A notebook #{top} is at the top of the shared folder; to use it, name it ./#{top}."
        end
        said
      end

      def root
        File.realpath(Monadic::Utils::Environment.data_path)
      end
    end
  end
end
