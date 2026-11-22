# frozen_string_literal: true

require_relative 'ids'
require_relative 'folders'
require_relative 'ledger'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workspace
    # Where a path a model gives to a file tool is, for the chat the reply
    # belongs to. The chat comes from the server (Workbench::Caller), never
    # from the path.
    #
    # Writes always land in the chat's work/ folder: a path at the top of
    # the shared folder or in a folder of it the user made (`notes.md`,
    # `/monadic/data/projects/x.py`) is placed there under the same relative
    # name, and the place says so. A path in the chat's own folder is kept
    # when it is under work/. Anything under conversations/ that is not
    # this chat's folder is refused, for reads and listings too: another
    # chat's files never go into this chat's requests.
    #
    # Reads and listings may also reach the user's own files outside
    # conversations/. Every place is checked again by SharedPathGuard when
    # the file is opened (no link on the way); this module only decides
    # where.
    module ChatFiles
      WORK = 'work'
      CONVERSATIONS = Folders::ROOT_DIRNAME
      # Names a model may use relative to the chat's folder, as the tools
      # return them (`work/x.py`, `inputs/<file>`).
      CHAT_SUBDIRS = Folders::SUBDIRS

      class Refused < StandardError; end

      # requested: the path as the model gave it. relative: the path in the
      # shared folder. moved: true when a write was placed in the chat's
      # folder instead of where it was asked for. source: :chat or :shared.
      Place = Struct.new(:requested, :relative, :moved, :source, keyword_init: true) do
        # The local path, for SharedPathGuard.
        def full
          File.join(Monadic::Utils::Environment.data_path, relative)
        end

        # The path code in the containers uses.
        def container_path
          File.join(Monadic::Utils::SharedPathGuard::CONTAINER_ROOT, relative)
        end
      end

      module_function

      # The chat's folder, relative to the shared folder, for the caller's
      # chat (made the first time). Raises Refused without a chat or when
      # its folder is gone; never falls back to another place.
      def chat_dir(caller, app_name:)
        chat_id = caller&.chat_id
        raise Refused, 'There is no chat to keep files in.' unless Ids.valid?(:chat, chat_id)

        folder = Folders.ensure_for_chat!(chat_id, app_name: app_name)
        raise Refused, "The chat's folder is no longer in the shared folder." unless folder[:status] == :ready

        folder[:relative_dir]
      rescue Folders::Unavailable, Ledger::Unreadable
        raise Refused, "The chat's folder could not be opened."
      end

      def work_dir(caller, app_name:)
        File.join(chat_dir(caller, app_name: app_name), WORK)
      end

      # Where a write of requested goes.
      def for_write(requested, caller:, app_name:)
        relative = shared_relative!(requested)
        chat = chat_dir(caller, app_name: app_name)
        work = File.join(chat, WORK)
        if inside?(relative, work)
          return Place.new(requested: requested, relative: own_spelling(relative, work), moved: false, source: :chat)
        end
        raise Refused, "Files of this chat are written in its work folder (#{work})." if inside?(relative, chat)
        raise Refused, "The folders of other chats cannot be written." if inside?(relative, CONVERSATIONS)
        raise Refused, 'A file name is needed.' if relative.empty?

        relative = relative.split('/').drop(1).join('/') if inside?(relative, WORK)
        raise Refused, 'A file name is needed.' if relative.empty?

        Place.new(requested: requested, relative: File.join(work, relative), moved: !in_chat_terms?(requested), source: :chat)
      end

      # Where a read of requested is: the chat's own folder, then (for a
      # name given relative to the shared folder) the chat's work/ before
      # the top of the shared folder.
      def for_read(requested, caller:, app_name:)
        relative = shared_relative!(requested)
        raise Refused, 'A file name is needed.' if relative.empty?

        chat = chat_dir(caller, app_name: app_name)
        if inside?(relative, chat)
          return Place.new(requested: requested, relative: own_spelling(relative, chat), moved: false, source: :chat)
        end
        raise Refused, "The folders of other chats cannot be read." if inside?(relative, CONVERSATIONS)
        if !absolute?(requested) && CHAT_SUBDIRS.any? { |sub| inside?(relative, sub) }
          in_chat = File.join(chat, relative)
          return Place.new(requested: requested, relative: in_chat, moved: false, source: :chat) if Folders.real_path(in_chat)
        end

        in_work = File.join(chat, WORK, relative)
        if !absolute?(requested) && Folders.real_path(in_work)
          return Place.new(requested: requested, relative: in_work, moved: false, source: :chat)
        end

        Place.new(requested: requested, relative: relative, moved: false, source: :shared)
      end

      # The folder a listing shows: the chat's work/ when none is named.
      def for_list(requested, caller:, app_name:)
        chat = chat_dir(caller, app_name: app_name)
        if requested.nil? || requested.to_s.strip.empty?
          return Place.new(requested: requested, relative: File.join(chat, WORK), moved: false, source: :chat)
        end

        relative = requested.to_s.strip == '/' ? '' : shared_relative!(requested)
        return Place.new(requested: requested, relative: '', moved: false, source: :shared) if relative.empty?
        if inside?(relative, chat)
          return Place.new(requested: requested, relative: own_spelling(relative, chat), moved: false, source: :chat)
        end
        raise Refused, "The folders of other chats cannot be listed." if inside?(relative, CONVERSATIONS)

        Place.new(requested: requested, relative: relative, moved: false, source: :shared)
      end

      # Whether a name at the top of the shared folder is conversations/,
      # whatever its case or Unicode form (for listings of the top).
      def conversations_name?(name)
        key(name) == key(CONVERSATIONS)
      end

      # The path relative to the shared folder, from a relative path, the
      # containers' /monadic/data/..., or the local shared folder path.
      # Raises Refused for anything else: another absolute path, `..`,
      # control characters, a backslash.
      def shared_relative!(requested)
        text = requested.to_s
        raise Refused, 'The path is not valid.' unless text.valid_encoding?

        text = text.strip.unicode_normalize(:nfc)
        raise Refused, 'The path is not valid.' if text.match?(/[\u0000-\u001f\u007f\\]/)

        container = Monadic::Utils::SharedPathGuard::CONTAINER_ROOT
        local = File.expand_path(Monadic::Utils::Environment.data_path).unicode_normalize(:nfc)
        rest = if under_prefix?(text, container)
                 text[container.length..]
               elsif under_prefix?(text, local)
                 text[local.length..]
               elsif text.start_with?('/', '~')
                 raise Refused, 'The path is outside the shared folder.'
               else
                 text
               end
        parts = rest.split('/').reject { |part| part.empty? || part == '.' }
        raise Refused, 'The path is not valid (".." is not allowed).' if parts.include?('..')

        parts.join('/')
      end

      # Compared as macOS compares names: Unicode composed, case folded.
      def key(path)
        path.to_s.unicode_normalize(:nfc).downcase(:fold)
      end

      def inside?(relative, dir)
        k = key(relative)
        d = key(dir)
        k == d || k.start_with?("#{d}/")
      end

      # relative with the folder part spelled as the ledger has it, so the
      # strict walk (no link on the way) goes through the real folder names.
      def own_spelling(relative, dir)
        rest = relative.split('/')[dir.split('/').size..] || []
        File.join(dir, *rest)
      end

      # Whether requested was already written as work/<name>.
      def in_chat_terms?(requested)
        !absolute?(requested) && inside?(shared_relative!(requested), WORK)
      end

      def absolute?(requested)
        requested.to_s.strip.start_with?('/')
      end

      def under_prefix?(text, prefix)
        text == prefix || text.start_with?("#{prefix}/")
      end
      private_class_method :under_prefix?
    end
  end
end
