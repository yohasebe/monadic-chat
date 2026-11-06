# frozen_string_literal: true

require 'digest'
require 'time'
require_relative '../workspace/ids'
require_relative '../workspace/folders'
require_relative '../workspace/ledger'
require_relative '../workspace/ledger_schema'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workbench
    # An image a chat's generator made: a file of the chat's folder in the
    # shared folder (conversations/<folder>/artifacts/<name>) and its record
    # in the ledger (kind image, with its size and sha256). The file is the
    # only copy: the user can open, move or delete it like any other file.
    #
    # Everything that uses the image (the work screen, an edit, a download)
    # reads it here: the record must be of the caller's chat, and the bytes
    # read must be those recorded. A file that changed or is gone is
    # reported (Changed, Missing), never replaced by another version.
    module Artifact
      class Error < StandardError; end
      # The record is not one this chat may read.
      class NotAllowed < Error; end
      # The file is not the one recorded.
      class Changed < Error; end
      # The file is not there.
      class Missing < Error; end
      # Placing failed. path: the file when one was made (left as it is).
      class NotPlaced < Error
        attr_reader :path

        def initialize(message, path: nil)
          super(message)
          @path = path
        end
      end

      # Names tried for a file before giving up (name, name-2, ...).
      NAME_TRIES = 20
      STEM_LIMIT = 60
      # One image is placed at a time, so a run is looked up and recorded
      # without another placing of it in between. Taken inside a board's
      # lock, never the other way round.
      PLACING = Mutex.new

      module_function

      # Places bytes (a checked image: {content_type:, width:, height:}) in
      # the chat's folder and records it. Never writes over a file: the name
      # gets -2, -3, ... while one has it. A run already recorded is not
      # placed again; its record is returned (recorded_run). Returns the
      # ledger's record.
      #
      # A file made and not recorded (the ledger failed, or the process
      # stopped) stays where it is, a file of the user's like any other; it
      # is never taken up later by its name.
      def place!(chat_id:, app_name:, bytes:, image:, name:, run:, request_id:, derived_from: nil,
                 ledger: Monadic::Workspace::Ledger.default, now: Time.now)
        PLACING.synchronize do
          place_new(chat_id: chat_id, app_name: app_name, bytes: bytes, image: image, name: name, run: run,
                    request_id: request_id, derived_from: derived_from, ledger: ledger, now: now)
        end
      end

      # The record of run when it was placed for this chat, reply and bytes,
      # or nil when it was not placed. NotPlaced (nothing placed) when it was
      # placed for another chat, reply or image.
      def recorded_run(run, chat_id:, request_id:, sha256:, ledger: Monadic::Workspace::Ledger.default)
        found = ledger.image_for_run(run)
        return nil unless found
        return found if found.values_at(:chat_id, :request_id, :sha256) == [chat_id, request_id, sha256]

        raise NotPlaced, 'this run placed another image'
      rescue Monadic::Workspace::Ledger::Unreadable => e
        raise NotPlaced, "the ledger could not be used (#{e.message})"
      end

      def place_new(chat_id:, app_name:, bytes:, image:, name:, run:, request_id:, derived_from:, ledger:, now:)
        sha256 = Digest::SHA256.hexdigest(bytes)
        found = recorded_run(run, chat_id: chat_id, request_id: request_id, sha256: sha256, ledger: ledger)
        return found if found

        folder = Monadic::Workspace::Folders.ensure_for_chat!(chat_id, app_name: app_name, ledger: ledger, now: now)
        raise NotPlaced, "the chat's folder is no longer in the shared folder" unless folder[:status] == :ready

        dir = File.join(shared_root, folder[:relative_dir], 'artifacts')
        guard.mkdir_p!(dir, strict: true)
        file = write_new(dir, file_name(name, image[:content_type], now), bytes)
        begin
          record, = ledger.register_image(
            artifact_id: Monadic::Workspace::Ids.generate(:artifact), chat_id: chat_id, name: File.basename(file),
            size: bytes.bytesize, sha256: sha256, content_type: image[:content_type],
            width: image[:width], height: image[:height], run: run, request_id: request_id,
            derived_from: derived_from, created_at: now
          )
          record
        rescue Monadic::Workspace::Ledger::Unsettled
          raise NotPlaced.new('the image was placed, but its record may not be on disk; restart Monadic Chat',
                              path: relative(file))
        rescue Monadic::Workspace::Ledger::Conflict, Monadic::Workspace::Ledger::Unreadable,
               Monadic::Workspace::Ledger::Full, SystemCallError, IOError => e
          raise NotPlaced.new("the image was placed, but it could not be recorded (#{e.class.name.split('::').last})",
                              path: relative(file))
        end
      rescue Monadic::Workspace::Folders::Unavailable, Monadic::Utils::SharedPathGuard::InvalidPath => e
        raise NotPlaced, e.message
      rescue Monadic::Workspace::Ledger::Unreadable, Monadic::Workspace::Ledger::Conflict => e
        raise NotPlaced, "the ledger could not be used (#{e.message})"
      rescue SystemCallError, IOError => e
        raise NotPlaced, "the image could not be written to the chat folder (#{e.class.name.split('::').last})"
      end
      private_class_method :place_new

      # The record and bytes of an image of chat_id: { record:, bytes: }.
      # chat_id is the caller's chat as the server knows it (a connection,
      # a reply, a token it gave), never one a request names.
      def read(artifact_id, chat_id:, ledger: Monadic::Workspace::Ledger.default)
        record = record_of(artifact_id, chat_id: chat_id, ledger: ledger)
        bytes = begin
          guard.read_bytes!(File.join(shared_root, record[:copy_path]), limit: record[:size], strict: true)
        rescue Errno::ENOENT, Errno::ENOTDIR
          raise Missing, 'the image is no longer in the shared folder'
        rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
          raise Changed, 'the image in the shared folder changed'
        end
        raise Changed, 'the image in the shared folder changed' unless bytes && Digest::SHA256.hexdigest(bytes) == record[:sha256]

        { record: record, bytes: bytes }
      end

      # :ok, :changed or :missing for an image of chat_id (as read). A
      # record this chat may not read, or a ledger that cannot be read, is
      # :missing.
      def status(artifact_id, chat_id:, ledger: Monadic::Workspace::Ledger.default)
        read(artifact_id, chat_id: chat_id, ledger: ledger)
        :ok
      rescue Missing, NotAllowed, Monadic::Workspace::Ledger::Unreadable
        :missing
      rescue Changed
        :changed
      end

      # The ledger's record of an image of chat_id. Raises NotAllowed for
      # anything else (no record, another kind, another chat, a workspace
      # that is not the chat's).
      def record_of(artifact_id, chat_id:, ledger: Monadic::Workspace::Ledger.default)
        raise NotAllowed, 'no such image' unless Monadic::Workspace::Ids.valid?(:artifact, artifact_id)
        raise NotAllowed, 'no such image' unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

        record = ledger.artifact(artifact_id)
        ok = record && record[:kind] == Monadic::Workspace::LedgerSchema::IMAGE_KIND && record[:owner] == 'chat' &&
             record[:chat_id] == chat_id && ledger.workspace_for_chat(chat_id)&.dig(:workspace_id) == record[:workspace_id]
        raise NotAllowed, 'no such image' unless ok

        record
      end

      # The record as a message keeps it (Record): no token, URL or local
      # path.
      def entry(record)
        derived = record[:derived_from]
        {
          'id' => record[:artifact_id], 'path' => record[:copy_path], 'name' => File.basename(record[:copy_path]),
          'sha256' => record[:sha256], 'content_type' => record[:content_type], 'created_at' => record[:created_at],
          'derived_from' => derived && (derived['artifact_id'] || derived[:artifact_id])
        }.compact
      end

      # <time>_<the generator's name, without its extension>.<ext of type>
      def file_name(name, content_type, now)
        stem = File.basename(name.to_s, '.*').gsub(/[^A-Za-z0-9_-]+/, '_').sub(/\A[^A-Za-z0-9]+/, '')[0, STEM_LIMIT]
        stem = 'image' if stem.empty?
        ext = Monadic::Workspace::LedgerSchema::IMAGE_TYPES.key(content_type) or raise NotPlaced, 'not an image type that is kept'
        "#{now.strftime('%Y%m%d-%H%M%S')}_#{stem}.#{ext}"
      end

      # Writes bytes as a new file in dir (synced, with the folder), under
      # name or, while a file has that name, name-2, name-3, ... Returns its
      # path.
      def write_new(dir, name, bytes)
        stem = File.basename(name, '.*')
        ext = File.extname(name)
        NAME_TRIES.times do |i|
          candidate = i.zero? ? name : "#{stem}-#{i + 1}#{ext}"
          begin
            return guard.write_file!(File.join(dir, candidate), bytes, mode: 'wb', replace: false, sync_dir: true,
                                                                       strict: true)
          rescue Errno::EEXIST
            next
          end
        end
        raise NotPlaced, 'no free name for the image in the chat folder'
      end

      def relative(path)
        path.delete_prefix("#{shared_root}/")
      end

      def shared_root
        File.realpath(Monadic::Utils::Environment.data_path)
      end

      def guard
        Monadic::Utils::SharedPathGuard
      end
    end
  end
end
