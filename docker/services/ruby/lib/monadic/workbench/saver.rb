# frozen_string_literal: true

require 'digest'
require 'time'
require_relative 'board'
require_relative '../workspace/ledger'
require_relative '../utils/environment'

module Monadic
  module Workbench
    # Saves an image of the workbench to the shared folder in steps, each
    # written down before the next begins, so an operation cut off anywhere
    # (a crash, a restart) is taken up again by running it once more, and
    # nothing is made twice:
    #
    #   accepted       what will be made was chosen and recorded (the
    #                  artifact id, where the original goes, the name it is
    #                  to have in the shared folder, the temporary name)
    #   original_kept  the original is kept in the chat's folder of the
    #                  state folder, its sha256 checked
    #   shared_copied  the shared folder has the copy under its final name:
    #                  written under the temporary name, then linked to the
    #                  final name (a link is refused when the name is taken,
    #                  so nothing is overwritten); the temporary file and the
    #                  final name being the same file shows the copy is this
    #                  operation's
    #   recorded       the message that asked has the saved artifact in its
    #                  record (the recorder; when the chat is not open it is
    #                  done when the chat is open again)
    #
    # A file the operation did not make is never changed.
    module Saver
      NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,150}\z/
      NAME_TRIES = 100

      class Failed < StandardError; end

      @running = Hash.new { |h, k| h[k] = Mutex.new }
      @running_lock = Mutex.new

      module_function

      # Takes the operation as far as it can go. recorder.call(board:,
      # operation:, artifact:) records the saved artifact in the message and
      # returns true, or false when the chat is not open (it stays at
      # shared_copied). Returns the operation as left.
      def run(board, operation_id, recorder:, shared_root: Monadic::Utils::Environment.data_path)
        lock_for(board.chat_id, operation_id).synchronize do
          operation = board.operation(operation_id) or raise Failed, 'no such operation'
          return operation unless operation['action'] == 'save'

          operation = keep_original(board, operation) if operation['state'] == 'accepted'
          operation = copy_to_shared(board, operation, shared_root) if operation['state'] == 'original_kept'
          operation = record(board, operation, recorder, shared_root) if operation['state'] == 'shared_copied'
          operation
        end
      end

      def keep_original(board, operation)
        candidate = board.item(operation['item_id'])&.dig('candidate') or raise Failed, 'the candidate is gone'
        path = board.path(operation['original'])
        if File.exist?(path)
          raise Failed, 'the kept original does not match' unless sha256_of(path) == operation['sha256']
        else
          bytes = File.binread(board.path(candidate['path']))
          raise Failed, 'the candidate changed' unless Digest::SHA256.hexdigest(bytes) == operation['sha256']

          board.write_new(operation['original'], bytes)
        end
        board.keep_artifact(operation['artifact_id'],
                            name: operation['reserved_name'], sha256: operation['sha256'], size: File.size(path),
                            content_type: candidate['content_type'], item_id: operation['item_id'],
                            derived_from: candidate.dig('derived_from', 'sha256'))
        board.advance(operation['id'], 'original_kept')
      end

      def copy_to_shared(board, operation, root)
        raise Failed, 'not a name the shared folder takes' unless NAME.match?(operation['reserved_name'].to_s)

        temp = File.join(root, operation['temp_name'])
        original = board.path(operation['original'])
        NAME_TRIES.times do
          target = File.join(root, operation['reserved_name'])
          return board.advance(operation['id'], 'shared_copied', final_name: operation['reserved_name']) if ours?(temp, target)

          unless make_temp(temp, original, operation['sha256'])
            # A file this operation did not write has the temporary name: it
            # is left alone, and another name is written down first.
            operation = board.advance(operation['id'], 'original_kept',
                                      temp_name: next_temp_name(root, operation))
            temp = File.join(root, operation['temp_name'])
            next
          end
          begin
            File.link(temp, target)
            Monadic::Workspace::Ledger::Disk.sync_dir(root)
            return board.advance(operation['id'], 'shared_copied', final_name: operation['reserved_name'])
          rescue Errno::EEXIST
            # The name was taken by a file this operation did not make:
            # another name is chosen and written down first.
            operation = board.advance(operation['id'], 'original_kept', reserved_name: next_name(root, operation['reserved_name']))
          end
        end
        raise Failed, 'no free name in the shared folder'
      end

      def record(board, operation, recorder, root)
        artifact = artifact_of(board, operation, saved_at: Time.now.utc.iso8601)
        return operation unless recorder.call(board: board, operation: operation, artifact: artifact)

        operation = board.advance(operation['id'], 'recorded', saved_at: artifact[:saved_at])
        temp = File.join(root, operation['temp_name'])
        # Only this operation's own copy (the same file as the saved one).
        File.unlink(temp) if ours?(temp, File.join(root, operation['final_name']))
        operation
      end

      # What the message's record says of the operation's saved image.
      def artifact_of(board, operation, saved_at: operation['saved_at'])
        kept = board.artifact(operation['artifact_id']) || {}
        { id: operation['artifact_id'], name: operation['final_name'], sha256: operation['sha256'],
          content_type: kept['content_type'], derived_from: kept['derived_from'], saved_at: saved_at }
      end

      # The temporary file of this operation, holding the original's bytes:
      # made new, or one an earlier run left with the right bytes. False when
      # something else has the name (a file with other bytes, a folder, a
      # link), which is not touched.
      def make_temp(temp, original, sha256)
        return false if File.symlink?(temp)
        return sha256_of(temp) == sha256 if File.file?(temp)
        return false if File.exist?(temp)

        # Readable as the shared folder's other files are.
        Monadic::Workspace::Ledger::Disk.create_exclusive(temp, File.binread(original), perm: 0o644)
        true
      rescue Errno::EEXIST
        false
      end

      def next_temp_name(root, operation)
        base = ".monadic-op-#{operation['artifact_id']}"
        (2..).each do |n|
          name = "#{base}-#{n}"
          path = File.join(root, name)
          return name unless File.exist?(path) || File.symlink?(path)
        end
      end

      def ours?(temp, target)
        File.file?(temp) && !File.symlink?(target) && File.exist?(target) && File.identical?(temp, target)
      end

      # name-2.ext, name-3.ext, ... the first that is free.
      def next_name(root, name)
        ext = File.extname(name)
        stem = File.basename(name, ext).sub(/-\d+\z/, '')
        (2..).each do |n|
          candidate = "#{stem}-#{n}#{ext}"
          return candidate unless File.exist?(File.join(root, candidate)) || File.symlink?(File.join(root, candidate))
        end
      end

      def sha256_of(path)
        Digest::SHA256.file(path).hexdigest
      end

      def lock_for(chat_id, operation_id)
        @running_lock.synchronize { @running["#{chat_id}/#{operation_id}"] }
      end
    end
  end
end
