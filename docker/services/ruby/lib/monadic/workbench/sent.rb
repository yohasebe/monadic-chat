# frozen_string_literal: true

require 'digest'
require_relative 'image_check'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'
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
      # that left, whatever came back).
      def named_by(messages)
        Array(messages).flat_map do |message|
          next [] unless message.is_a?(Hash)

          Array(message['workbench_looks']).filter_map do |look|
            look['image_sha256'] if look.is_a?(Hash) && %w[sent refused unknown].include?(look['state'])
          end
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
