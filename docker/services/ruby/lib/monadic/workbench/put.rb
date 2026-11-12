# frozen_string_literal: true

require 'digest'
require_relative 'board'
require_relative 'shown'
require_relative 'made'
require_relative '../workspace/chats'
require_relative '../workspace/folders'
require_relative '../workspace/shared_folder_preview'
require_relative '../render_formats'
require_relative '../utils/shared_path_guard'
require_relative '../utils/websocket/reply_handle'

module Monadic
  module Workbench
    # What put_on_workbench does: writes a text the reply made into the
    # chat's folder (workbench/ under it) as a new file, and shows it on the
    # work screen. The chat and the reply are the server's (Caller), never
    # the model's.
    #
    # The write is decided once, against a Cancel and against leaving the
    # chat: under the lock that ends the chat's epoch, the reply must still
    # be running and not cancelled (ReplyHandle#admit_write). From that
    # decision the file is written whole, with the stop held off, so a
    # Cancel that comes after leaves the finished file (never a part of it);
    # one that came before leaves nothing.
    #
    # The same name and text again in one reply give the file written
    # before (shown again if showing it failed), never a new one.
    module Put
      class Refused < StandardError; end

      LIMIT = 2 * 1024 * 1024
      NAME_BYTES = 100
      NAME_TRIES = 99
      DIRNAME = 'workbench'
      # The extensions the work screen draws (Monadic::RenderFormats), and
      # text shown as it is. Extensions of two parts are looked at first.
      COMPOUND = Monadic::RenderFormats.compound_extensions.map { |ext| ".#{ext}" }.freeze
      EXTENSIONS = (Monadic::RenderFormats.extensions + %w[json txt]).uniq.freeze

      # Replies ended, oldest first: a late call for one of them finds no
      # place to record what it wrote.
      ENDED_LIMIT = 1000

      @writes = {}
      @ended = {}
      @lock = Mutex.new

      module_function

      # Returns { path:, shown:, reason: } (reason: why it was not shown).
      def run(caller, name:, content:)
        raise Refused, 'this reply cannot put anything on the work screen' unless caller
        raise Refused, 'the chat changed' unless current?(caller)

        name = clean_name(name)
        bytes = checked_content(content)
        handle = WebSocketHelper::Replies.find(caller.request_id)
        slot = slot_for(handle, caller.request_id, name, Digest::SHA256.hexdigest(bytes))
        slot[:mutex].synchronize do
          unless slot[:path]
            slot[:path] = write(caller, handle, name, bytes)
            Made.add(caller.request_id, slot[:path], chat_id: caller.chat_id)
          end
          show(caller, handle, slot)
        end
      end

      # The reply ended: what it wrote is no longer looked up.
      def release(request_id)
        @lock.synchronize do
          @writes.delete(request_id)
          @ended[request_id] = true
          @ended.shift while @ended.size > ENDED_LIMIT
        end
        nil
      end

      def current?(caller)
        session = caller.session
        chat_id = session && (session[Monadic::Workspace::Chats::SESSION_KEY] || session[Monadic::Workspace::Chats::SESSION_KEY.to_s])
        chat_id == caller.chat_id && Monadic::Workspace::Chats.epoch(caller.chat_id) == caller.epoch
      end

      # A file name of one part, with an extension the work screen shows.
      def clean_name(name)
        raise Refused, 'name must be a file name' unless name.is_a?(String)

        name = name.dup.force_encoding('UTF-8')
        raise Refused, 'name must be UTF-8' unless name.valid_encoding?

        name = name.unicode_normalize(:nfc).strip
        raise Refused, 'name must be a file name without a folder' if name.match?(%r{[/\\\0]}) || name.match?(/[\p{Cc}\p{Cf}]/)
        raise Refused, 'name must not start with a dot' if name.start_with?('.')
        raise Refused, "name must be at most #{NAME_BYTES} bytes" if name.bytesize > NAME_BYTES

        stem, ext = split_name(name)
        raise Refused, "name must end with one of #{(COMPOUND + EXTENSIONS.map { |e| ".#{e}" }).join(', ')}" unless ext
        raise Refused, 'name must have a part before the extension' if stem.empty?

        name
      end

      # [stem, extension with its dot] or [name, nil].
      def split_name(name)
        lower = name.downcase
        compound = COMPOUND.find { |suffix| lower.end_with?(suffix) }
        return [name[0...-compound.size], name[-compound.size..]] if compound

        ext = File.extname(name)
        EXTENSIONS.include?(ext.delete_prefix('.').downcase) ? [name[0...-ext.size], ext] : [name, nil]
      end

      def checked_content(content)
        raise Refused, 'content must be text' unless content.is_a?(String)

        bytes = content.b
        raise Refused, "content must be at most #{LIMIT} bytes" if bytes.bytesize > LIMIT

        text = bytes.dup.force_encoding('UTF-8')
        raise Refused, 'content must be UTF-8 text' unless text.valid_encoding? && !text.include?("\0")

        bytes
      end

      # A place for what the reply writes, only while it runs (asked under
      # the lock release takes).
      def slot_for(handle, request_id, name, sha256)
        @lock.synchronize do
          raise Refused, 'the reply has ended' if @ended.key?(request_id)
          raise Refused, 'the reply has ended' unless handle && handle.phase == :running && !handle.cancelled?

          (@writes[request_id] ||= {})[[name, sha256]] ||= { mutex: Mutex.new, path: nil }
        end
      end

      # The path written (relative to the shared folder). The folder is
      # found or made first; the decision and the write go together, with
      # the stop held off.
      def write(caller, handle, name, bytes)
        folder = Monadic::Workspace::Folders.ensure_for_chat!(caller.chat_id, app_name: app_name(caller))
        raise Refused, "the chat's folder is no longer in the shared folder" unless folder[:status] == :ready

        dir = File.join(shared_root, folder[:relative_dir], DIRNAME)
        Thread.handle_interrupt(Object => :never) do
          admitted = Monadic::Workspace::Chats.admit_in_epoch(caller.chat_id, caller.epoch) { handle.admit_write }
          raise Refused, 'the reply was stopped or the chat changed' unless admitted

          guard.mkdir_p!(dir, strict: true)
          File.join(folder[:relative_dir], DIRNAME, File.basename(write_new(dir, name, bytes)))
        end
      rescue Monadic::Workspace::Folders::Unavailable, Monadic::Utils::SharedPathGuard::InvalidPath => e
        raise Refused, e.message
      rescue SystemCallError, IOError => e
        raise Refused, "the file could not be written (#{e.class.name.split('::').last})"
      end

      def write_new(dir, name, bytes)
        stem, ext = split_name(name)
        NAME_TRIES.times do |i|
          candidate = i.zero? ? name : "#{stem}-#{i + 1}#{ext}"
          begin
            return guard.write_file!(File.join(dir, candidate), bytes, mode: 'wb', replace: false, sync_dir: true,
                                                                       strict: true)
          rescue Errno::EEXIST
            next
          end
        end
        raise Refused, 'no free name for the file in the chat folder'
      end

      # Shows the written file (again, when showing it failed before).
      def show(caller, handle, slot)
        result = { path: slot[:path], shown: false, reason: nil }
        return result.merge(reason: 'the reply was stopped') if handle.cancelled?

        board = Board.for(caller.chat_id)
        item, = board.add_file(path: slot[:path], origin: caller.origin, epoch: caller.epoch)
        Shown.add(caller.request_id, item)
        result.merge(shown: true)
      rescue Board::Refused => e
        result.merge(reason: e.message)
      rescue FileItem::Busy
        result.merge(reason: 'the work screen is reading other files now; try again in a moment')
      end

      def app_name(caller)
        params = caller.session && caller.session[:parameters]
        (params && params['app_name']).to_s
      end

      def shared_root
        File.realpath(Monadic::Utils::Environment.data_path)
      end

      def guard
        Monadic::Utils::SharedPathGuard
      end

      # For tests.
      def reset!
        @lock.synchronize do
          @writes.clear
          @ended.clear
        end
      end
    end
  end
end
