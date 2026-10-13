# frozen_string_literal: true

require 'etc'
require_relative 'environment'
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
      # outside the folders above, never through a link: the folder it goes
      # in is checked where it really is, and the file is opened without
      # following a link in its place (one could be made to point at a file
      # the server loads). Raises InvalidPath otherwise.
      def write_file!(path, content, mode: "w")
        # Looked at before links are followed: resolving would turn a link
        # in the file's place into the file it points to.
        raise InvalidPath, "A link is not written through" if File.symlink?(lexical_path(path))

        real = resolve_in_shared!(path, must_exist: false)
        raise InvalidPath, "Files are not written to the apps, helpers, scripts or services folders" unless tool_writable?(real)
        raise InvalidPath, "A link is not written through" if File.symlink?(real)

        flags = File::WRONLY | File::CREAT | File::NOFOLLOW | (mode.start_with?("a") ? File::APPEND : File::TRUNC)
        File.open(real, flags, 0o644) do |f|
          f.binmode if mode.include?("b")
          # An IO (an upload) is copied as it streams, not read whole first.
          content.respond_to?(:read) ? IO.copy_stream(content, f) : f.write(content)
        end
        real
      rescue Errno::ELOOP
        raise InvalidPath, "A link is not written through"
      end

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
          missing.unshift(File.basename(path))
          path = File.dirname(path)
        end
        File.join(File.realpath(path), *missing)
      end
      private_class_method :canonical_path
    end
  end
end
