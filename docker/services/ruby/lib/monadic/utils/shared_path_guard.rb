# frozen_string_literal: true

require 'etc'
require_relative 'environment'
require_relative 'shared_fs'
require_relative '../shell'

module Monadic
  module Utils
    # Files used by tools belong to the active shared volume, never the CWD.
    # Unlike SharedFilePath (/data downloads), tools may use subdirectories.
    module SharedPathGuard
      CONTAINER_ROOT = Monadic::Shell::SHARED_VOLUME
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze
      AUDIO_EXTENSIONS = %w[.mp3 .mp4 .mpeg .mpga .m4a .wav .webm .ogg .flac].freeze

      class InvalidPath < ArgumentError; end

      USER_CODE_FLAG = "MONADIC_LOAD_USER_CODE"

      module_function

      # Returns the canonical path, or nil. For output files, resolve the
      # nearest existing ancestor, including symlinks; dangling links fail.
      def resolve_in_shared(name, extensions: nil, must_exist: true)
        resolve_in_shared!(name, extensions: extensions, must_exist: must_exist)
      rescue InvalidPath
        nil
      end

      # Same boundary with actionable, value-free diagnostics for tool callers.
      def resolve_in_shared!(name, extensions: nil, must_exist: true, kind: "file")
        unless name.is_a?(String) && name.valid_encoding? && !name.empty? && !name.include?("\0") && !name.include?('\\')
          raise InvalidPath, "Invalid file path"
        end
        raise InvalidPath, "Invalid file path (path traversal not allowed)" if name.split('/').include?('..')

        allowed = extensions&.map(&:downcase)
        if allowed && !allowed.include?(File.extname(name).downcase)
          raise InvalidPath, "Unsupported #{kind} format: path must point to a #{allowed.join(', ')} file"
        end

        root = File.expand_path(Environment.data_path)
        candidate = if name == CONTAINER_ROOT || name.start_with?("#{CONTAINER_ROOT}/")
                      root + name.delete_prefix(CONTAINER_ROOT)
                    elsif name.start_with?('/')
                      name
                    else
                      File.join(root, name)
                    end
        real_root = canonical_path(root)
        real_path = canonical_path(candidate)
        raise InvalidPath, "path must be within the shared volume" unless real_path.start_with?("#{real_root}/")
        raise InvalidPath, "File not found or not a regular file" if must_exist && !File.file?(real_path)
        if allowed && !allowed.include?(File.extname(real_path).downcase)
          raise InvalidPath, "Unsupported #{kind} format: path must point to a #{allowed.join(', ')} file"
        end

        real_path
      rescue SystemCallError, EncodingError
        raise InvalidPath, "Invalid file path or file not found"
      end

      def inside_shared?(path)
        !resolve_in_shared(path, must_exist: false).nil?
      end

      # The folders of the shared volume whose code the Ruby side loads or
      # runs (custom apps, helpers, scripts, container definitions). A file a tool writes for the
      # model never goes there: the model's input can be steered by what it
      # reads, and code there would run with the Ruby side's access.
      TRUSTED_CODE_DIRS = %w[apps helpers scripts services].freeze

      # Whether a resolved path (from resolve_in_shared) is outside those
      # folders: by name (compared without case, for a case-insensitive
      # disk where `Apps/` is `apps/`), and by where they really are (one of
      # them may be a link to an ordinary folder, whose files it then loads).
      def tool_writable?(real_path)
        real_root = canonical_path(File.expand_path(Environment.data_path))
        return false unless real_path.to_s.start_with?("#{real_root}/")

        first = real_path.delete_prefix("#{real_root}/").split("/").first.to_s.downcase
        return false if TRUSTED_CODE_DIRS.include?(first)

        trusted_real_dirs(real_root).none? { |dir| real_path == dir || real_path.start_with?("#{dir}/") }
      end

      # Writes content for a tool or a route at a path in the shared folder,
      # outside the folders above, never through a link (SharedFs): the
      # folders on the way are opened one by one without following a link,
      # and the file is written new under a temporary name in the folder held
      # open, then put in place. A link in the file's place is refused (one
      # put there afterwards is replaced, not followed), and so is a folder;
      # an existing file keeps its permissions unless perm is given. mode "a" appends to a plain file instead (nothing is written
      # to a link, a FIFO or a file with another name). replace: false puts
      # it in place only when nothing has that name (Errno::EEXIST). content
      # is a String or an IO (an upload, copied as it streams); with a block
      # and no content, the block writes to the file. Returns the file's
      # path. Raises InvalidPath when the path is not one the server
      # may write.
      def write_file!(path, content = nil, mode: "w", perm: nil, replace: true, sync_dir: false, &writer)
        raise ArgumentError, "mode must be one of #{WRITE_MODES.join(', ')}" unless WRITE_MODES.include?(mode)
        raise ArgumentError, "an append always goes to the file that is there" if mode.start_with?("a") && !replace
        writer ||= ->(file) { content.respond_to?(:read) ? IO.copy_stream(content, file) : file.write(content) }
        in_parent!(path) do |dir, name, full|
          if mode.start_with?("a")
            file = SharedFs.open_append(dir, name, perm: perm || 0o644)
            begin
              file.binmode if mode.include?("b")
              writer.call(file)
            ensure
              file.close
            end
          else
            kept = SharedFs.entry(dir, name)
            # A link left in the file's place is refused (one made after this
            # look is replaced, never followed); so is a folder.
            raise InvalidPath, "A link is not written through" if kept == :link
            raise InvalidPath, "Only a plain file is written" if kept && !kept.file?

            SharedFs.write_new(dir, name, perm: perm || (kept ? kept.mode & 0o777 : 0o644), replace: replace,
                                          sync_dir: sync_dir, &writer)
          end
          full
        end
      end

      # The File::Stat of a plain file of the shared folder, or nil (nothing
      # there, a link, a folder, or a path the server does not write).
      def file_stat(path)
        in_parent!(path) do |dir, name, _full|
          stat = SharedFs.entry(dir, name)
          stat.is_a?(File::Stat) && stat.file? ? stat : nil
        end
      rescue InvalidPath, SystemCallError
        nil
      end

      # Copies a file of the shared folder (read as write_file! writes: never
      # through a link) to another path there.
      def copy_file!(source, dest, perm: nil, replace: true)
        read_file!(source) { |io| write_file!(dest, io, perm: perm, replace: replace) }
      end

      # Yields a plain file of the shared folder open for reading, never
      # through a link and never a FIFO or a device; returns what the block
      # returns.
      def read_file!(path)
        in_parent!(path) do |dir, name, _full|
          file = SharedFs.open_read(dir, name)
          begin
            yield file
          ensure
            file.close
          end
        end
      end

      # The bytes of a plain file of the shared folder (read_file!), or nil
      # when it is larger than limit. With a limit no more than limit + 1
      # bytes are read, so a file that grows after the size check is refused
      # too.
      def read_bytes!(path, limit: nil)
        read_file!(path) do |file|
          next file.read unless limit
          next nil if file.stat.size > limit

          bytes = file.read(limit + 1) || ''.b
          bytes.bytesize > limit ? nil : bytes
        end
      end

      # The text of a plain file of the shared folder (read_file!), or nil
      # when there is none there: nothing, a folder or a link. A file that is
      # there but cannot be read (permission, I/O) raises, so a caller never
      # takes it for one that is not there.
      def read_text(path, limit: nil)
        read_bytes!(path, limit: limit)&.force_encoding(Encoding::UTF_8)
      rescue InvalidPath, Errno::ENOENT, Errno::ENOTDIR
        nil
      end

      # Yields the path of a copy of a plain file of the shared folder, made
      # in a folder of its own in the system's temporary folder, for a
      # program or library that opens files by path (ffmpeg, an HTTP form):
      # it never opens a path in the shared folder. The copy is removed after.
      def with_local_copy!(path)
        require "tmpdir"
        Dir.mktmpdir("shared-copy") do |dir|
          copy = File.join(dir, "copy#{File.extname(path.to_s)[0, 16]}")
          read_file!(path) { |source| File.open(copy, "wb", 0o600) { |out| IO.copy_stream(source, out) } }
          yield copy
        end
      end

      # A plain file of the shared folder, open for reading bytes and never
      # through a link, for a caller that keeps it open past a block (a
      # response body); the caller closes it.
      def open_file!(path)
        in_parent!(path) { |dir, name, _full| SharedFs.open_read(dir, name) }
      end

      # Removes a file (or a link, itself) of the shared folder, never a
      # folder and never through a link on the way. Returns whether it was
      # there.
      def delete_file!(path)
        in_parent!(path) do |dir, name, _full|
          SharedFs.unlink(dir, name)
          true
        rescue Errno::ENOENT
          false
        end
      end

      # Removes a folder of the shared folder and everything in it, never
      # through a link (SharedFs.remove_tree). A plain file is removed too.
      def remove_tree!(path)
        in_parent!(path) do |dir, name, full|
          SharedFs.remove_tree(dir, name, File.dirname(full), skip_dirs: trusted_dir_ids)
          true
        end
      end

      # Makes a folder of the shared folder and the folders on the way to it,
      # never through a link. Returns its path.
      def mkdir_p!(path, strict: false)
        parts = shared_parts!(lexical_path(checked_name!(path)), strict: strict)
        SharedFs.in_dir(shared_root, parts, create: true, skip_dirs: trusted_dir_ids) { nil }
        File.join(shared_root, *parts)
      rescue SharedFs::Unsafe, Errno::ELOOP => e
        raise InvalidPath, refusal(e)
      end

      # Makes a new folder of the shared folder (Errno::EEXIST when anything
      # has its name) and the folders children in it, never through a link.
      # Returns its path.
      def make_dir!(path, children: [], strict: false)
        in_parent!(path, strict: strict) do |dir, name, full|
          SharedFs.make_dir(dir, name) do |made|
            children.each { |child| SharedFs.make_dir(made, child) { nil } }
          end
          full
        end
      end

      # Renames a plain file of the shared folder to another path there
      # (replacing what has that name; a link there is replaced, not
      # followed). Folders are not moved.
      def rename_file!(source, dest)
        in_parent!(source) do |from_dir, from, _|
          stat = SharedFs.entry(from_dir, from)
          raise InvalidPath, "Only a plain file is moved" unless stat.is_a?(File::Stat) && stat.file?

          in_parent!(dest) do |to_dir, to, full|
            SharedFs.rename(from_dir, from, to_dir, to)
            full
          end
        end
      end

      # The folder holding path, open (SharedFs.in_dir), with the file's name
      # and full path. Folders reached through a link inside the shared folder
      # are taken where they really are; from there each folder is opened
      # without following a link.
      def in_parent!(path, strict: false)
        lexical = lexical_path(checked_name!(path))
        name = File.basename(lexical)
        parts = shared_parts!(File.dirname(lexical), strict: strict)
        trusted = trusted_dir_ids
        SharedFs.in_dir(shared_root, parts, skip_dirs: trusted) do |dir|
          # The name itself may not be one of the code folders either: not
          # by its name at the top, and not where one of them really is.
          if parts.empty? && TRUSTED_CODE_DIRS.include?(name.downcase)
            raise InvalidPath, "Files are not written to the apps, helpers, scripts or services folders"
          end
          found = SharedFs.entry(dir, name)
          if found.is_a?(File::Stat) && trusted.include?(SharedFs.identity(found))
            raise InvalidPath, "Files are not written to the apps, helpers, scripts or services folders"
          end

          yield dir, name, File.join(shared_root, *parts, name)
        end
      rescue SharedFs::Unsafe => e
        raise InvalidPath, refusal(e)
      rescue Errno::ELOOP
        raise InvalidPath, "A link is not written through"
      end
      private_class_method :in_parent!

      # The same checks of a given name as resolve_in_shared!.
      def checked_name!(name)
        unless name.is_a?(String) && name.valid_encoding? && !name.empty? && !name.include?("\0") && !name.include?('\\')
          raise InvalidPath, "Invalid file path"
        end
        raise InvalidPath, "Invalid file path (path traversal not allowed)" if name.split('/').include?('..')

        name
      end
      private_class_method :checked_name!

      # The names from the real shared folder down to the folder dir (which
      # must be in it, and not under one of TRUSTED_CODE_DIRS).
      # strict: true takes the folders as written, so a link on the way
      # (even to a folder inside the shared folder) is refused by the walk:
      # for folders whose path the ledger records.
      def shared_parts!(dir, strict: false)
        root = shared_root
        real = if strict
                 lexical = File.expand_path(dir)
                 given_root = File.expand_path(Environment.data_path)
                 lexical == given_root || lexical.start_with?("#{given_root}/") ? root + lexical.delete_prefix(given_root) : lexical
               else
                 canonical_path(dir)
               end
        raise InvalidPath, "path must be within the shared volume" unless real == root || real.start_with?("#{root}/")

        parts = real.delete_prefix(root).split("/").reject(&:empty?)
        if TRUSTED_CODE_DIRS.include?(parts.first.to_s.downcase)
          raise InvalidPath, "Files are not written to the apps, helpers, scripts or services folders"
        end

        parts
      end
      private_class_method :shared_parts!

      def shared_root
        canonical_path(File.expand_path(Environment.data_path))
      end
      private_class_method :shared_root

      # The folders whose code the server loads, as [dev, ino], wherever they
      # really are (one may be a link to an ordinary folder).
      def trusted_dir_ids
        trusted_real_dirs(shared_root).filter_map do |dir|
          stat = File.stat(dir)
          [stat.dev, stat.ino]
        rescue SystemCallError
          nil
        end
      end
      private_class_method :trusted_dir_ids

      def refusal(error)
        return "A link is not written through" if error.is_a?(Errno::ELOOP) || error.message.include?("link")
        return "Files are not written to the apps, helpers, scripts or services folders" if error.message.include?("may not write")

        "The path is not one the server writes (#{error.class.name.split('::').last})"
      end
      private_class_method :refusal

      WRITE_MODES = %w[w wb a ab].freeze

      # The custom app and helper files the server loads: code_files, and in
      # development mode none unless the shell that started the server set
      # MONADIC_LOAD_USER_CODE=true. On the host the server runs outside the
      # containers whose mounts keep apps and helpers read-only.
      def user_code_files(dir, pattern)
        files = code_files(dir, pattern)
        return files if File.file?("/.dockerenv") || user_code_asked_for_on_host?

        unless files.empty? || @told_user_code_skipped
          @told_user_code_skipped = true
          puts "[Monadic] Custom apps and helpers in the shared folder are not loaded in development mode; " \
               "start with #{USER_CODE_FLAG}=true in the shell to load them"
        end
        []
      end

      # Only the shell may ask. Some entry points read the config env file
      # into ENV before the server starts (rake server:debug does), where the
      # value cannot be told from the shell's, and the server itself writes
      # that file; so the flag counts only when the file does not mention it
      # at all (in any form Dotenv might read: `NAME: v`, a BOM, CR lines).
      def user_code_asked_for_on_host?
        return false unless ENV[USER_CODE_FLAG] == "true"
        return true unless config_env_mentions?(USER_CODE_FLAG)

        unless @told_user_code_flag_ignored
          @told_user_code_flag_ignored = true
          puts "[Monadic] #{USER_CODE_FLAG} is in the config env file, so it is ignored; " \
               "remove it from that file and set it in the shell"
        end
        false
      end

      # Whether the host's config env file names this, anywhere in it. The
      # bytes are searched, never parsed or shown. Both homes are looked at:
      # the account's, and HOME, which an entry point may have used.
      def config_env_mentions?(name)
        homes = [Etc.getpwuid(Process.uid).dir, ENV.fetch("HOME", nil)].compact.uniq
        homes.any? do |home|
          file = File.join(home, "monadic", "config", "env")
          File.file?(file) && File.binread(file).include?(name)
        rescue SystemCallError
          false
        end
      end

      # Whether file, found under dir, may be loaded as code: a real file, not
      # a link, really inside dir, and not a hard link (the same file may be
      # reachable, and writable, from elsewhere in the shared folder).
      def code_file?(file, dir)
        return false if File.symlink?(file) || !File.file?(file)
        return false if File.lstat(file).nlink > 1

        File.realpath(file).start_with?("#{File.realpath(dir)}/")
      rescue SystemCallError
        false
      end

      # The files matching pattern under dir that the server may load as code
      # (custom apps and helpers): none when dir is itself a link, and only
      # the files code_file? accepts.
      def code_files(dir, pattern)
        return [] unless File.directory?(dir) && !File.symlink?(dir)

        Dir.glob(File.join(dir, pattern)).sort.select { |file| code_file?(file, dir) }
      rescue SystemCallError
        []
      end

      # Where a name points in the shared folder, nothing resolved.
      def lexical_path(name)
        root = File.expand_path(Environment.data_path)
        name = name.to_s
        if name == CONTAINER_ROOT || name.start_with?("#{CONTAINER_ROOT}/")
          root + name.delete_prefix(CONTAINER_ROOT)
        elsif name.start_with?("/")
          name
        else
          File.join(root, name)
        end
      end
      private_class_method :lexical_path

      def trusted_real_dirs(real_root)
        TRUSTED_CODE_DIRS.filter_map do |name|
          dir = File.join(real_root, name)
          File.realpath(dir) if File.exist?(dir)
        rescue SystemCallError
          nil
        end
      end
      private_class_method :trusted_real_dirs

      # Python always runs in its container; Ruby may run on the host.
      def command_path(path, container:, must_exist: true)
        resolved = resolve_in_shared(path, must_exist: must_exist)
        return nil unless resolved
        return resolved unless container.to_s == 'python'

        CONTAINER_ROOT + resolved.delete_prefix(canonical_path(Environment.data_path))
      end

      def canonical_path(path)
        path = File.expand_path(path)
        missing = []
        until File.exist?(path) || File.symlink?(path)
          parent = File.dirname(path)
          break if parent == path # the root

          missing.unshift(File.basename(path))
          path = parent
        end
        File.join(File.realpath(path), *missing)
      end
      private_class_method :canonical_path
    end
  end
end
