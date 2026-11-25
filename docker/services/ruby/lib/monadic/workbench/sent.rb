# frozen_string_literal: true

require 'base64'
require 'digest'
require_relative 'image_check'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'
require_relative '../utils/tool_image_utils'
require_relative '../workspace/folders'
require_relative '../workspace/ids'

module Monadic
  module Workbench
    # The images of the work screen that left for a provider (a look's
    # image), kept in the chat's folder as sent/<sha256>.<ext> so that the
    # chat's export can hold them. One file for an image however often it
    # went. A file is taken only as it was kept: one that is not the image
    # its name says (the user changed it) is read as gone, never written
    # over and never removed. A file no message of the chat names any more
    # is removed (release), unless a reply still running sent it (pending).
    module Sent
      DIRNAME = 'sent'
      EXTENSIONS = { 'image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp', 'image/gif' => 'gif' }.freeze
      NAME = /\A(\h{64})\.(png|jpg|webp|gif)\z/
      # What a chat keeps, at most (its export holds it all).
      LIMIT_BYTES = 150 * 1024 * 1024

      # The image is not kept: the chat keeps too much (Full: what holds it
      # should not go), or it has no folder that can take it (Unavailable).
      class Refused < StandardError; end
      class Full < Refused; end
      class Unavailable < Refused; end
      # An export would hold more than EXPORT_LIMIT (the message: how much).
      class ExportTooLarge < StandardError; end
      # A file holds an image that is not what it says.
      class BadFile < StandardError; end

      # What an export holds of the images, at most (base64).
      EXPORT_LIMIT = 200 * 1024 * 1024
      # How many images a file may hold.
      IMPORT_COUNT_LIMIT = 2000

      # The images sent by replies still running, by chat: kept but not yet
      # named by a message.
      PENDING = Hash.new { |h, k| h[k] = Hash.new(0) }
      PENDING_LOCK = Mutex.new
      # One keeping or release of a chat's images at a time.
      LOCK = Mutex.new

      module_function

      # Keeps bytes (content_type) as an image the chat sent, pending until
      # done. Returns its sha256. Unavailable when the chat has no folder
      # that can take it, Full when it would keep more than LIMIT_BYTES.
      def keep!(chat_id, bytes, content_type, app_name: nil)
        ext = EXTENSIONS[content_type.to_s] or raise Unavailable, 'an image of a kind that is not kept'
        bytes = bytes.to_s.b
        sha256 = Digest::SHA256.hexdigest(bytes)
        LOCK.synchronize do
          dir = dir_for(chat_id, app_name: app_name, make: true) or raise Unavailable, "the chat's folder is not there"
          path = File.join(dir, "#{sha256}.#{ext}")
          unless held?(path, sha256)
            # Something else at its name (the user changed the file) stays.
            raise Unavailable, 'another file is at its name' if File.exist?(path) || File.symlink?(path)
            raise Full, 'the images this chat sent are too large to keep' if total(dir) + bytes.bytesize > LIMIT_BYTES

            Monadic::Utils::SharedPathGuard.write_file!(path, bytes, mode: 'wb', replace: false, strict: true)
          end
        end
        PENDING_LOCK.synchronize { PENDING[chat_id.to_s][sha256] += 1 }
        sha256
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
        raise Unavailable, 'the image could not be kept'
      end

      # Full when the chat could not keep bytes more (checked before what
      # would send them goes); a chat without a folder yet has room.
      def check_room!(chat_id, bytes)
        return if bytes.zero?

        dir = dir_for(chat_id) or return
        raise Full, 'the images this chat sent are too large to keep' if total(dir) + bytes > LIMIT_BYTES
      end

      # The images of shas256 a reply sent are named by its message now, or
      # will not be: they are no longer pending.
      def done(chat_id, shas256)
        PENDING_LOCK.synchronize do
          pending = PENDING[chat_id.to_s]
          Array(shas256).each do |sha|
            pending[sha] -= 1
            pending.delete(sha) unless pending[sha].positive?
          end
          PENDING.delete(chat_id.to_s) if pending.empty?
        end
      end

      # The bytes of the image sha256 the chat sent, as kept: nil when it is
      # gone or is no longer that image.
      def read(chat_id, sha256)
        dir = dir_for(chat_id) or return nil
        file = Dir.children(dir).find { |name| name.match(NAME)&.[](1) == sha256.to_s } or return nil
        bytes = Monadic::Utils::SharedPathGuard.read_bytes!(File.join(dir, file), limit: ImageCheck::MAX_BYTES, strict: true)
        bytes && Digest::SHA256.hexdigest(bytes) == sha256 ? bytes : nil
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
        nil
      end

      # The sha256 of every image the messages name as sent (a look's image
      # that left, whatever came back; the picture of the work screen a
      # message went with).
      def named_by(messages)
        Array(messages).flat_map do |message|
          next [] unless message.is_a?(Hash)

          looks = Array(message['workbench_looks']).filter_map do |look|
            look['image_sha256'] if look.is_a?(Hash) && %w[sent refused unknown].include?(look['state'])
          end
          picture = message['workbench_picture']
          edits = Array(message['workbench_edit_inputs']).filter_map { |e| e['sha256'] if e.is_a?(Hash) }
          looks + edits + [picture.is_a?(Hash) ? picture['sha256'] : nil].compact
        end.uniq
      end

      # Removes the images of the chat that messages no longer name and no
      # running reply sent; with messages nil, every one (the chat is gone).
      # Only a file that is still the image its name says is removed.
      # Returns how many were.
      def release(chat_id, messages)
        keep = messages.nil? ? [] : named_by(messages)
        LOCK.synchronize do
          dir = dir_for(chat_id) or return 0
          pending = PENDING_LOCK.synchronize { PENDING.fetch(chat_id.to_s, {}).keys }
          Dir.children(dir).count do |name|
            sha256 = name.match(NAME)&.[](1)
            next false if sha256.nil? || keep.include?(sha256) || pending.include?(sha256)

            path = File.join(dir, name)
            next false unless held?(path, sha256)

            Monadic::Utils::SharedPathGuard.delete_file!(path)
            true
          end
        end
      rescue SystemCallError
        0
      end

      # The images the messages name as sent, as an export holds them:
      # [{ sha256 => { content_type, data (base64) } }, the sha256 of those
      # gone or changed]. ExportTooLarge when they are more than EXPORT_LIMIT.
      def export_table(chat_id, messages)
        table = {}
        missing = []
        size = 0
        named_by(messages).each do |sha256|
          bytes = chat_id && read(chat_id, sha256)
          next missing << sha256 unless bytes

          data = Base64.strict_encode64(bytes)
          size += data.bytesize
          raise ExportTooLarge, size.to_s if size > EXPORT_LIMIT

          table[sha256] = { 'content_type' => Monadic::Utils::ToolImageUtils.image_media_type(bytes), 'data' => data }
        end
        [table, missing]
      end

      # The images a file holds (table: as export_table made it) for what
      # its messages name as sent: only those, each the image its sha256
      # says, of the type it says, within ImageCheck's limits. { sha256 =>
      # { bytes:, content_type: } }. An image that is not what it says
      # refuses the file (BadFile); one the file does not hold is left out.
      def import_table(table, messages)
        return {} unless table.is_a?(Hash)
        raise BadFile, 'the file holds too many images' if table.size > IMPORT_COUNT_LIMIT

        limit = (ImageCheck::MAX_BYTES * 4 / 3) + 4
        named_by(messages).each_with_object({}) do |sha256, out|
          entry = table[sha256] or next
          data = entry.is_a?(Hash) ? entry['data'] : nil
          raise BadFile, 'an image of the file is not one' unless data.is_a?(String) && data.bytesize <= limit

          bytes = decoded(data)
          raise BadFile, 'an image of the file is not the one it names' unless Digest::SHA256.hexdigest(bytes) == sha256

          type = checked_type(bytes)
          raise BadFile, 'an image of the file is not of its type' unless type == entry['content_type']

          out[sha256] = { bytes: bytes, content_type: type }
        end
      end

      def decoded(data)
        Base64.strict_decode64(data)
      rescue ArgumentError
        raise BadFile, 'an image of the file is not one'
      end

      def checked_type(bytes)
        ImageCheck.check!(bytes)[:content_type]
      rescue ImageCheck::Refused
        raise BadFile, 'an image of the file is not one'
      end

      # The size of what the chat keeps.
      def total(dir)
        Dir.children(dir).sum { |name| name.match?(NAME) ? File.size(File.join(dir, name)) : 0 }
      end

      # Whether path is a plain file holding the image sha256.
      def held?(path, sha256)
        stat = Monadic::Utils::SharedPathGuard.file_stat(path) or return false
        stat.size <= ImageCheck::MAX_BYTES &&
          Digest::SHA256.hexdigest(Monadic::Utils::SharedPathGuard.read_bytes!(path, strict: true).to_s) == sha256
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
        false
      end

      # The chat's sent folder (a real path), or nil: the folder the ledger
      # names for the chat (made when make and the chat has none yet, with
      # app_name).
      def dir_for(chat_id, app_name: nil, make: false)
        return nil unless Monadic::Workspace::Ids.valid?(:chat, chat_id.to_s)

        folders = Monadic::Workspace::Folders
        record = if make && app_name
                   folders.ensure_for_chat!(chat_id.to_s, app_name: app_name)
                 else
                   ledger = Monadic::Workspace::Ledger.default.workspace_for_chat(chat_id.to_s)
                   ledger && folders.describe(ledger)
                 end
        return nil unless record && record[:status] == :ready

        root = File.realpath(Monadic::Utils::Environment.data_path)
        dir = File.join(root, record[:relative_dir], DIRNAME)
        return nil unless make || File.directory?(dir)

        Monadic::Utils::SharedPathGuard.mkdir_p!(dir, strict: true) if make
        dir
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
        nil
      end
    end
  end
end
