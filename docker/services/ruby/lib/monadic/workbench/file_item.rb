# frozen_string_literal: true

require 'digest'
require_relative 'artifact'
require_relative '../workspace/shared_folder'
require_relative '../workspace/shared_folder_preview'

module Monadic
  module Workbench
    # A file of the shared folder shown on the workbench: a reference to it
    # (its path, as the Shared Folder panel names it) and the version it
    # had when it was opened (sha256, size). The bytes are never copied:
    # each use reads the file again, without following links
    # (SharedFolderPreview.open_file), and goes on only when what was read
    # is that version. A file that changed or is gone is reported
    # (Artifact::Changed, Artifact::Missing), never shown in its new form;
    # the user opens it again for that.
    module FileItem
      class Refused < StandardError; end
      # Too many files are being read now; try again.
      class Busy < StandardError; end

      # The kinds the work screen shows (SharedFolderPreview.kind_for). A PDF
      # is served whole to the page, which draws it with pdf.js.
      KINDS = %w[image text audio video pdf].freeze
      # A file larger than this is not opened on the workbench (each use
      # reads it whole to check its version).
      LIMIT = 64 * 1024 * 1024
      # What a text item serves of the file: its beginning, as the panel.
      TEXT_LIMIT = Monadic::Workspace::SharedFolderPreview::TEXT_LIMIT
      # Files read and hashed at once, how long a read waits for its turn
      # (by default), and how many may wait.
      READS = 2
      READ_WAIT = 15
      WAITING = 8

      @reading = 0
      @waiting = 0
      @reading_lock = Mutex.new
      @reading_done = ConditionVariable.new

      class << self
        # Runs the block as one of READS at most. Busy at once when WAITING
        # are waiting already, or after wait seconds without a turn. A turn
        # (or a place in the wait) is given back however the block ends.
        def turn(wait: READ_WAIT)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
          @reading_lock.synchronize do
            if @reading >= READS
              raise Busy, 'the work screen is reading other files; try again' if @waiting >= WAITING

              @waiting += 1
              begin
                while @reading >= READS
                  left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
                  raise Busy, 'the work screen is reading other files; try again' if left <= 0

                  @reading_done.wait(@reading_lock, left)
                end
              ensure
                @waiting -= 1
              end
            end
            @reading += 1
          end
          begin
            yield
          ensure
            @reading_lock.synchronize do
              @reading -= 1
              @reading_done.signal
            end
          end
        end
      end

      module_function

      # Opens the file at path (relative to the shared folder) and returns
      # its entry for an item: path (normalized), name, preview kind,
      # content type, sha256, size and the stat seen (to tell a change
      # cheaply in a view). Refused for anything the work screen does not
      # show; Busy when no turn to read it came within wait seconds.
      def entry_for(path, wait: READ_WAIT)
        relative = normalize(path)
        read = read_whole(relative, wait: wait)
        {
          'path' => relative, 'name' => File.basename(relative), 'preview' => read[:kind],
          'content_type' => content_type(relative, read[:kind]), 'sha256' => read[:sha256],
          'size' => read[:bytes].bytesize, 'mtime_ns' => nanoseconds(read[:stat].mtime), 'ino' => read[:stat].ino
        }
      rescue Monadic::Workspace::SharedFolderPreview::Invalid,
             Monadic::Workspace::SharedFolderPreview::Unavailable => e
        raise Refused, e.message
      end

      # The bytes of the item's file, read now and checked against entry's
      # version.
      def read(entry)
        read = read_whole(entry['path'])
        raise Artifact::Changed, 'the file changed after it was opened' unless read[:sha256] == entry['sha256']

        read[:bytes]
      rescue Monadic::Workspace::SharedFolderPreview::Invalid => e
        raise Artifact::Missing, 'the file is no longer in the shared folder' if e.message == 'the file is not there'

        raise Artifact::Changed, 'the file changed after it was opened'
      rescue Refused, Monadic::Workspace::SharedFolderPreview::Unavailable, SystemCallError, IOError
        # Grown past the limit, or no longer a file that can be shown: not
        # the version opened.
        raise Artifact::Changed, 'the file changed after it was opened'
      end

      # ok, changed or missing, from the file's stat only (a view shows it
      # for every item; a use reads the file and checks it, read).
      def status(entry)
        stat = File.stat(File.join(Monadic::Workspace::SharedFolder.data_root, entry['path']))
        return 'changed' unless stat.file? && stat.size == entry['size'] && stat.ino == entry['ino'] &&
                                nanoseconds(stat.mtime) == entry['mtime_ns']

        'ok'
      rescue Errno::ENOENT, Errno::ENOTDIR
        'missing'
      rescue SystemCallError
        'changed'
      end

      # The path as the panel names it: parts joined by "/", no "." or
      # "..", no empty part. Anything else is refused here, before the file
      # is looked for.
      def normalize(path)
        parts = Monadic::Workspace::SharedFolder.parts_of(path.to_s)
        raise Refused, 'no file named' if parts.empty?

        parts.join('/')
      rescue Monadic::Workspace::SharedFolder::Invalid => e
        raise Refused, e.message
      end

      def nanoseconds(time)
        (time.to_i * 1_000_000_000) + time.nsec
      end

      def content_type(relative, kind)
        kind == 'text' ? 'text/plain; charset=utf-8' : Monadic::Workspace::SharedFolderPreview.mime_for(relative)
      end

      # The whole file (up to LIMIT) with its kind, stat and sha256, read
      # and hashed in one turn.
      def read_whole(relative, wait: READ_WAIT)
        turn(wait: wait) do
          read = read_now(relative)
          read.merge(sha256: Digest::SHA256.hexdigest(read[:bytes]))
        end
      end

      def read_now(relative)
        io, stat, kind = Monadic::Workspace::SharedFolderPreview.open_file(relative, kinds: KINDS)
        begin
          raise Refused, 'the file is too large for the work screen' if stat.size > LIMIT

          bytes = io.read(LIMIT + 1) || +''
          raise Refused, 'the file is too large for the work screen' if bytes.bytesize > LIMIT
        ensure
          io.close
        end
        { bytes: bytes, kind: kind, stat: stat }
      end
    end
  end
end
