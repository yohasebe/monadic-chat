# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'open3'
require 'securerandom'
require_relative 'ids'
require_relative 'folders'
require_relative 'ledger'
require_relative 'ledger_schema'
require_relative 'artifacts'
require_relative 'server_owner'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'
require_relative '../utils/shared_file_path'

module Monadic
  module Workspace
    # What the page loads by a name of its own (/data/pub_<id>.<ext>): a
    # copy of an attachment or an artifact of a chat, kept where only the
    # server can change it (state/publications/<publication id>/<name>) and
    # recorded in the ledger. The copy is made from the bytes read once from
    # the source and becomes servable only when those bytes have the size and
    # sha256 the ledger recorded for the source. Every pub_ name is answered
    # from the ledger alone: nothing in the shared folder is served under it.
    module Publications
      DIRNAME = 'publications'
      # The copies (ready and being made) take at most this much, and none is
      # made when the disk would be left with less free space than this.
      CAP_BYTES = 10 * 1024**3
      FREE_FLOOR_BYTES = 2 * 1024**3
      CHUNK = 64 * 1024
      # Copies whose bytes were checked against the ledger before they were
      # served, by what would change if a copy were written: its id, file,
      # size and times. A copy is hashed again when any of them changes.
      VERIFIED_MAX = 256
      @verified = {}
      @verified_mutex = Mutex.new
      # One copy at a time in this process, so the free space checked before
      # a copy is not counted again by another copy made at the same time.
      @copy_mutex = Mutex.new
      # The ready publications by name, read once per version of the ledger
      # file (a save puts a new file in place, so a change is always seen).
      @served = { key: nil, index: {} }
      @served_mutex = Mutex.new

      # Cannot be published now (being published, no room, cannot be read).
      class Unavailable < StandardError; end
      # The source's bytes are not the ones the ledger recorded.
      class Changed < StandardError; end

      module_function

      # The publication of a ready source of a chat (kind 'attachment' or
      # 'artifact'): the ready one when its copy is there, or a new one.
      # Returns its record (with :name). Nothing is made while the ledger is
      # no longer written (Unsettled) or the server is stopping.
      def create!(kind:, id:, ledger: Ledger.default)
        ServerOwner.writing do
          raise Ledger::Unsettled, 'the ledger is no longer written; restart Monadic Chat' if Ledger.unsettled?(ledger.path)

          existing = ledger.live_publication(kind, id)
          if existing&.dig(:status) == 'ready'
            return existing if copy_present?(existing, ledger)

            remove_copy(existing, ledger) if ledger.mark_publication(existing[:publication_id], status: 'missing', from: %w[ready])
          elsif existing
            raise Unavailable, 'this file is being published'
          end

          make(kind, id, ledger)
        end
      end

      # Whether a /data/ name is answered here: any name starting with pub_,
      # in any case (on a file system that ignores case, PUB_x would open
      # pub_x), compared as bytes so a name that is not UTF-8 is not an error.
      def public_name?(name)
        name.to_s.b[0, 4].downcase == 'pub_'
      end

      # The Rack response for a pub_ name: the ready publication's copy, while
      # its chat's folder is there, or 404. Never anything in the shared folder.
      def response(requested, env, extra_headers: ->(_type) { {} }, ledger: Ledger.default)
        name = requested.to_s
        return Monadic::Utils::SharedFilePath::NOT_FOUND.dup unless LedgerSchema::PUBLICATION_NAME.match?(name)

        record = ready_publications(ledger)[name]
        return Monadic::Utils::SharedFilePath::NOT_FOUND.dup unless record && record[:status] == 'ready' && chat_folder?(record)

        file = open_copy(record, ledger)
        return Monadic::Utils::SharedFilePath::NOT_FOUND.dup unless file

        unless verified?(file, record)
          file.close
          return Monadic::Utils::SharedFilePath::NOT_FOUND.dup
        end

        Monadic::Utils::SharedFilePath.respond(file, record[:content_type], env, extra_headers: extra_headers)
      rescue Ledger::Unreadable, SystemCallError, IOError
        Monadic::Utils::SharedFilePath::NOT_FOUND.dup
      end

      # At start, after the server holds the state folder and before it takes
      # requests: removes what servers that stopped left pending, revokes the
      # publications whose chat's folder is gone (removed, not just unreadable),
      # and removes the copies of revoked ones. Nothing is removed when the
      # ledger cannot be read. Returns the ids revoked.
      def reconcile!(ledger: Ledger.default)
        return [] unless File.exist?(ledger.path)

        revoked = []
        ledger.publications.each do |record|
          case record[:status]
          when 'pending'
            # The record goes only once its copy is known to be gone, so a
            # copy that could not be removed is found again next time.
            ledger.drop_publication(record[:publication_id]) if remove_copy(record, ledger)
          when 'ready', 'missing'
            next unless chat_folder_gone?(record, ledger)

            if ledger.mark_publication(record[:publication_id], status: 'revoked', from: %w[ready missing])
              revoked << record[:publication_id]
              remove_copy(record, ledger)
            end
          when 'revoked'
            remove_copy(record, ledger)
          end
        end
        revoked
      rescue Ledger::Unreadable
        []
      end

      def make(kind, id, ledger)
        source = source_of(kind, id, ledger)
        @copy_mutex.synchronize do
          room!(source[:size], ledger)
          publication_id = Ids.generate(:publication)
          token = SecureRandom.hex(8)
          name = "pub_#{publication_id.delete_prefix('p_')}.#{source[:ext]}"
          record = begin
            ledger.reserve_publication(publication_id: publication_id, name: name, token: token, kind: kind, id: id, cap_bytes: CAP_BYTES)
          rescue Ledger::Conflict
            raise Unavailable, 'this file is being published'
          rescue Ledger::Full => e
            raise Unavailable, e.message
          end

          dir = nil
          begin
            dir = make_dir!(record, ledger)
            copy!(dir, record, source)
            ledger.settle_publication(publication_id, token)
          rescue Ledger::Unsettled
            raise
          rescue StandardError => e
            # Only a folder this call made is removed, and the pending record
            # goes only once nothing of it is left (else the next start does).
            gone = dir.nil? || remove_dir(dir)
            begin
              ledger.drop_publication(publication_id, token) if gone
            rescue StandardError
              nil
            end
            raise Unavailable, 'the publication was revoked while it was made' if e.is_a?(Ledger::Conflict)

            raise
          end
        end
      end
      private_class_method :make

      # What is published from a source: its path, size, sha256 and the
      # extension of the public name. Only ready records of a chat.
      def source_of(kind, id, ledger)
        case kind
        when 'attachment'
          record = ledger.attachment(id)
          raise Unavailable, 'the attachment is not ready' unless record && record[:status] == 'ready'

          ext = File.extname(record[:original_name].to_s).delete_prefix('.').downcase
          path = Folders.real_path(record[:relative_path])
          raise Changed, 'the attached file is no longer in its chat folder' unless path
        when 'artifact'
          record = ledger.artifact(id)
          raise Unavailable, 'the artifact is not ready' unless record && record[:status] == 'ready'
          raise Unavailable, 'only what a chat made is published' unless record[:owner] == 'chat'

          ext = File.extname(LedgerSchema::ARTIFACT_KINDS.fetch(record[:kind])).delete_prefix('.')
          path = Artifacts.path(id, record[:kind], ledger: ledger)
        else
          raise ArgumentError, "unknown source kind #{kind}"
        end
        raise Unavailable, 'this kind of file is not published' unless LedgerSchema::PUBLICATION_TYPES.key?(ext)

        { kind: kind, path: path, size: record[:size], sha256: record[:sha256], ext: ext }
      end
      private_class_method :source_of

      # The publication's own folder, made new (an existing entry of that
      # name is left as it is and the call fails); returns it.
      def make_dir!(record, ledger)
        root = File.join(File.dirname(ledger.path), DIRNAME)
        made_root = make_root(root)
        Ledger::Disk.sync_dir(File.dirname(root)) if made_root
        dir = File.join(root, record[:publication_id])
        Dir.mkdir(dir, 0o700)
        dir
      end
      private_class_method :make_dir!

      # The copy, written in dir from the bytes read once from the source and
      # hashed as they are written. Raises Changed when they are not the
      # recorded ones (more bytes than recorded stop it early).
      def copy!(dir, record, source)
        digest = Digest::SHA256.new
        written = 0
        File.open(File.join(dir, record[:name]), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |out|
          read_source(source) do |io|
            while (chunk = io.read(CHUNK))
              written += chunk.bytesize
              raise Changed, 'the file has more bytes than were recorded' if written > record[:size]

              digest << chunk
              out.write(chunk)
            end
          end
          out.flush
          out.fsync
        end
        raise Changed, 'the file is not the one recorded' unless written == record[:size] && digest.hexdigest == record[:sha256]

        Ledger::Disk.sync_dir(dir)
        Ledger::Disk.sync_dir(File.dirname(dir))
      end
      private_class_method :copy!

      # An attachment is read as a plain file of the shared folder (never
      # through a link); an artifact from the state folder, which only the
      # server writes, as a plain file.
      def read_source(source, &block)
        if source[:kind] == 'attachment'
          Monadic::Utils::SharedPathGuard.read_file!(source[:path], &block)
        else
          File.open(source[:path], File::RDONLY | File::NOFOLLOW) do |io|
            raise Changed, 'the artifact is not a plain file' unless io.stat.file?

            yield io
          end
        end
      end
      private_class_method :read_source

      # Refuses (Unavailable) when the disk would be left with less free
      # space than FREE_FLOOR_BYTES. The total of the copies is checked when
      # the publication is recorded.
      def room!(size, ledger)
        free = free_bytes(File.dirname(ledger.path))
        raise Unavailable, 'the free space on the disk cannot be found out' unless free
        raise Unavailable, 'there is not enough free space on the disk for a copy for the page' if free - size < FREE_FLOOR_BYTES
      end
      private_class_method :room!

      def free_bytes(dir)
        out, status = Open3.capture2('df', '-Pk', dir)
        return nil unless status.success?

        available = out.lines.last.to_s.split[3]
        available&.match?(/\A\d+\z/) ? available.to_i * 1024 : nil
      rescue SystemCallError
        nil
      end
      private_class_method :free_bytes

      # Whether the ready copy is there with the recorded size and sha256 (as
      # it is checked before it is served). A copy that is gone, of another
      # size or of other bytes is not; a copy that cannot be read now raises
      # Unavailable (it is not taken for gone).
      def copy_present?(record, ledger)
        file = open_copy(record, ledger, strict: true)
        return false unless file

        verified?(file, record)
      rescue SystemCallError, IOError => e
        raise Unavailable, "the copy for the page cannot be read (#{e.class.name.split('::').last})"
      ensure
        file&.close
      end
      private_class_method :copy_present?

      # The copy, open, when it is a plain file of the recorded size; nil
      # otherwise. strict: an error other than "not there" raises.
      def open_copy(record, ledger, strict: false)
        file = File.open(copy_path(record, ledger), File::RDONLY | File::NOFOLLOW)
        stat = file.stat
        return file if stat.file? && stat.size == record[:size]

        file.close
        nil
      rescue Errno::ENOENT, Errno::ENOTDIR, Errno::ELOOP
        nil
      rescue SystemCallError => e
        raise Unavailable, "the copy for the page cannot be read (#{e.class.name.split('::').last})" if strict

        nil
      end
      private_class_method :open_copy

      def copy_path(record, ledger)
        raise ArgumentError, 'invalid publication id' unless Ids.valid?(:publication, record[:publication_id])
        raise ArgumentError, 'invalid publication name' unless LedgerSchema::PUBLICATION_NAME.match?(record[:name].to_s)

        File.join(File.dirname(ledger.path), DIRNAME, record[:publication_id], record[:name])
      end
      private_class_method :copy_path

      # Served only while the chat's folder is there as a folder, reached
      # from the shared folder with no link on the way or at its name
      # (SharedPathGuard.directory_stat); a folder that cannot be checked
      # counts as not there (nothing is removed for that).
      def chat_folder?(record)
        return false unless record[:relative_dir]

        !Monadic::Utils::SharedPathGuard.directory_stat(File.join(Monadic::Utils::Environment.data_path, record[:relative_dir])).nil?
      end
      private_class_method :chat_folder?

      def ready_publications(ledger)
        stat = File.stat(ledger.path)
        key = [ledger.path, stat.dev, stat.ino, stat.size, stat.mtime.to_r]
        cached = @served_mutex.synchronize { @served[:key] == key ? @served[:index] : nil }
        return cached if cached

        index = ledger.ready_publications
        @served_mutex.synchronize { @served = { key: key, index: index } }
        index
      end
      private_class_method :ready_publications

      # Whether the open copy's bytes have the sha256 the ledger recorded,
      # read from the file that is served. Remembered while the copy stays
      # the same file of the same size and times, so ranges of one video are
      # not hashed again; the file is left at its start.
      def verified?(file, record)
        stat = file.stat
        key = [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r]
        return true if @verified_mutex.synchronize { @verified[record[:publication_id]] == key }

        digest = Digest::SHA256.new
        file.rewind
        while (chunk = file.read(CHUNK))
          digest << chunk
        end
        file.rewind
        return false unless digest.hexdigest == record[:sha256]

        @verified_mutex.synchronize do
          @verified.shift if @verified.size >= VERIFIED_MAX
          @verified[record[:publication_id]] = key
        end
        true
      end
      private_class_method :verified?

      # Whether the chat's folder is known to be gone: not there at all
      # (ENOENT, ENOTDIR). A folder that cannot be read is not gone.
      def chat_folder_gone?(record, ledger)
        workspace = ledger.workspace_for_chat(record[:chat_id])
        return false unless workspace

        File.lstat(File.join(File.realpath(Monadic::Utils::Environment.data_path), workspace[:relative_dir]))
        false
      rescue Errno::ENOENT, Errno::ENOTDIR
        true
      rescue SystemCallError
        false
      end
      private_class_method :chat_folder_gone?

      # Removes a publication's folder; true when nothing of it is left.
      def remove_copy(record, ledger)
        remove_dir(File.dirname(copy_path(record, ledger)))
      rescue ArgumentError
        false
      end
      private_class_method :remove_copy

      # Gone only when lstat says there is nothing (ENOENT, ENOTDIR); a folder
      # whose parent cannot be searched is not taken for gone.
      def remove_dir(dir)
        FileUtils.rm_r(dir, secure: true) if entry?(dir)
        !entry?(dir)
      rescue SystemCallError
        false
      end
      private_class_method :remove_dir

      def entry?(path)
        File.lstat(path)
        true
      rescue Errno::ENOENT, Errno::ENOTDIR
        false
      end
      private_class_method :entry?

      # Makes the folder of all publications; true when this call made it.
      def make_root(root)
        Dir.mkdir(root, 0o700)
        true
      rescue Errno::EEXIST
        raise Errno::ENOTDIR, root unless File.directory?(root) && !File.symlink?(root)

        false
      end
      private_class_method :make_root
    end
  end
end
