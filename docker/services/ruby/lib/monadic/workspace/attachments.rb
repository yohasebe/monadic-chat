# frozen_string_literal: true

require 'digest'
require_relative 'ids'
require_relative 'ledger'
require_relative 'folders'
require_relative 'file_types'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workspace
    # Files the user gives a chat. Each is copied into the chat's inputs/
    # folder under a new id, recorded in the ledger, and usable only once it
    # is ready and only from the chat it was given to.
    module Attachments
      NAME_MAX_BYTES = 120
      COPY_CHUNK = 1024 * 1024

      class Unusable < StandardError
        attr_reader :reason

        def initialize(reason, message)
          @reason = reason
          super(message)
        end
      end

      module_function

      # source is an IO positioned at the start (the upload's temporary file).
      # The chat is the one the upload was made for; it is fixed by the caller
      # before the body was read, so a Reset during the upload cannot move the
      # file to the new chat.
      def accept!(chat_id:, app_name:, purpose:, original_name:, source:, ledger: Ledger.default, now: Time.now)
        head = source.read(FileTypes::HEAD_BYTES).to_s
        FileTypes.check!(purpose, original_name, head)
        source.rewind

        workspace = Folders.ensure_for_chat!(chat_id, app_name: app_name, ledger: ledger, now: now)
        unless workspace[:status] == :ready
          raise Unusable.new(:workspace_missing, "This chat's folder is missing from the shared folder. Start a new chat to attach files.")
        end

        inputs = File.join(workspace[:relative_dir], 'inputs')
        unless Folders.real_path(inputs, :directory)
          raise Unusable.new(:workspace_missing, "This chat's folder in the shared folder was changed. Start a new chat to attach files.")
        end

        attachment_id = Ids.generate(:attachment)
        relative_path = File.join(inputs, "#{attachment_id}__#{stored_name(original_name)}")
        ledger.register_attachment(attachment_id: attachment_id, chat_id: chat_id, workspace_id: workspace[:workspace_id],
                                   purpose: purpose, original_name: display_name(original_name),
                                   relative_path: relative_path, created_at: now)
        dest = File.join(Monadic::Utils::Environment.data_path, relative_path)
        created = false
        begin
          size, digest = copy_exclusive(source, dest) { created = true }
          # Checked again after writing: a folder swapped for a link while the
          # file was being written means it may have gone elsewhere.
          raise Folders::Unavailable, 'the chat folder changed while saving' unless Folders.real_path(relative_path)

          ledger.update_attachment(attachment_id, status: 'ready', 'size' => size, 'sha256' => digest)
        rescue StandardError => e
          # Remove only a partial file this call created, never one it found.
          File.unlink(dest) if created && File.exist?(dest)
          ledger.update_attachment(attachment_id, status: 'failed', 'failure' => e.class.name.split('::').last)
          raise Unusable.new(:write_failed, 'The file could not be saved to the shared folder.')
        end
      end

      # The ready attachment with this id, if it belongs to this chat and its
      # file is still the one that was saved. Raises Unusable otherwise.
      def resolve!(chat_id:, attachment_id:, ledger: Ledger.default)
        record = Ids.valid?(:attachment, attachment_id) && ledger.attachment(attachment_id)
        raise Unusable.new(:unknown, 'No such attachment.') unless record && record[:chat_id] == chat_id
        raise Unusable.new(:not_ready, 'This attachment is not ready.') unless record[:status] == 'ready'

        path = Folders.real_path(record[:relative_path])
        unless path
          raise Unusable.new(:missing, "The attached file #{record[:original_name]} is no longer in the shared folder.")
        end
        raise Unusable.new(:changed, "The attached file #{record[:original_name]} was changed after it was attached.") unless unchanged?(path, record)

        record.merge(path: path)
      end

      def unchanged?(path, record)
        File.size(path) == record[:size] && Digest::SHA256.file(path).hexdigest == record[:sha256]
      end

      # The name kept for display: the base name the browser sent, as valid
      # UTF-8 without control characters.
      def display_name(name)
        text = name.to_s.dup.force_encoding(Encoding::UTF_8)
        text = text.scrub('?') unless text.valid_encoding?
        base = text.split(%r{[/\\]}).last.to_s
        base = base.unicode_normalize(:nfc).gsub(/[\p{Cc}\p{Cf}]/, '').strip
        base.empty? ? 'file' : base
      end

      # The name on disk: the display name with characters that file systems
      # or shells treat specially replaced, no leading dot, and short enough,
      # keeping the extension. It is never used to find the file again.
      def stored_name(name)
        base = display_name(name).gsub(%r{[<>:"|?*\s/\\]}, '_').sub(/\A[.\-_]+/, '')
        ext = File.extname(base).downcase
        stem = File.basename(base, File.extname(base))
        room = NAME_MAX_BYTES - ext.bytesize
        stem = stem.byteslice(0, room).scrub('') if stem.bytesize > room
        stem = 'file' if stem.empty?
        "#{stem}#{ext}"
      end

      def copy_exclusive(source, dest)
        digest = Digest::SHA256.new
        size = 0
        File.open(dest, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |out|
          yield if block_given?
          while (chunk = source.read(COPY_CHUNK))
            out.write(chunk)
            digest.update(chunk)
            size += chunk.bytesize
          end
          out.flush
          out.fsync
        end
        [size, digest.hexdigest]
      end
    end
  end
end
