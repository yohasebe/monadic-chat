# frozen_string_literal: true

require 'fiddle'
require 'securerandom'

module Monadic
  module Utils
    # File operations in a folder that another program can change while the
    # server works in it (the shared folder: code run in the Python container
    # writes there and can put links in it). A path is never looked up again
    # once checked: the walk opens the trusted root, then each folder below
    # it without following a link (O_NOFOLLOW) and checks it is a folder, and
    # every create, rename and delete is made relative to the folder it holds
    # open (openat, renameat, linkat, unlinkat, mkdirat from libc, through
    # Fiddle). A folder swapped for a link after it was opened changes
    # nothing: the open folder is still the one operated on.
    #
    # The root is trusted: neither it nor a folder above it can be replaced by
    # the other program. This guards where the server writes, not what the
    # shared folder holds: its files may still be changed afterwards.
    module SharedFs
      class Unsafe < StandardError; end

      LIBC = Fiddle.dlopen(nil)
      INT = Fiddle::TYPE_INT
      PTR = Fiddle::TYPE_VOIDP
      FUNCS = {
        # openat takes its mode as a variadic argument, which some platforms
        # (arm64 macOS) pass differently from a fixed one.
        openat: Fiddle::Function.new(LIBC['openat'], [INT, PTR, INT, Fiddle::TYPE_VARIADIC], INT),
        mkdirat: Fiddle::Function.new(LIBC['mkdirat'], [INT, PTR, INT], INT),
        renameat: Fiddle::Function.new(LIBC['renameat'], [INT, PTR, INT, PTR], INT),
        linkat: Fiddle::Function.new(LIBC['linkat'], [INT, PTR, INT, PTR, INT], INT),
        unlinkat: Fiddle::Function.new(LIBC['unlinkat'], [INT, PTR, INT], INT)
      }.freeze

      # O_CLOEXEC, which Ruby does not name: every descriptor opened here is
      # closed in child processes from the moment it exists.
      CLOEXEC = case RUBY_PLATFORM
                when /linux/ then 0o2000000
                when /darwin/ then 0x01000000
                else raise LoadError, "SharedFs does not know O_CLOEXEC on #{RUBY_PLATFORM}"
                end

      # AT_REMOVEDIR for unlinkat (remove a folder).
      AT_REMOVEDIR = case RUBY_PLATFORM
                     when /linux/ then 0x200
                     when /darwin/ then 0x80
                     end
      # How deep remove_tree goes before it gives up.
      TREE_DEPTH = 64

      # Opened without following a link, and without waiting on a FIFO put in
      # a file's place.
      READ_FLAGS = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
      NAME = %r{\A[^/\0]+\z}

      module_function

      # Yields the folder at root/parts (each part one name), open. root is
      # trusted (the real path of the shared folder); none of the parts may be
      # a link. create: true makes missing folders (mode 0755) on the way.
      # skip_dirs: [dev, ino] pairs of folders the walk must not enter.
      def in_dir(root, parts, create: false, skip_dirs: [])
        dir = File.open(root, READ_FLAGS)
        raise Unsafe, 'the shared folder is not a folder' unless dir.stat.directory?

        parts.each do |part|
          check_name!(part)
          child = open_child_dir(dir, part, create: create)
          dir.close
          dir = child
          raise Unsafe, 'a folder the server may not write in' if skip_dirs.include?(identity(dir.stat))
        end
        yield dir
      ensure
        dir&.close unless dir&.closed?
      end

      # A new file written in dir under a temporary name and then put in
      # place under name: replacing what is there (replace: true; a link in
      # its place is replaced, never followed) or only when nothing is
      # (replace: false, Errno::EEXIST otherwise). The temporary file is
      # made new (O_EXCL), so no existing file is opened. perm is set on the
      # open file before it is synced; sync_dir: true syncs the folder after
      # the file is in place. Once the file is in place the call succeeds:
      # removing the temporary name is tidying, and its failure (or the name
      # already gone) never hides what happened.
      def write_new(dir, name, perm:, replace: true, sync_dir: false)
        check_name!(name)
        temp = ".#{name[0, 64]}.#{SecureRandom.hex(8)}.tmp"
        file = open_at(dir, temp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600)
        placed = false
        begin
          file.binmode
          yield file
          file.flush
          file.chmod(perm)
          file.fsync
          file.close
          if replace
            call!(:renameat, dir.fileno, temp, dir.fileno, name)
            placed = true
          else
            call!(:linkat, dir.fileno, temp, dir.fileno, name, 0)
            placed = true
            tidy(dir, temp)
          end
          dir.fsync if sync_dir
        ensure
          file.close unless file.closed?
          # The temporary name is in the folder held open: removing it there
          # cannot reach anything else.
          tidy(dir, temp) unless placed
        end
        nil
      end

      # An existing regular file of dir (or a new one unless create: false),
      # open for appending; nothing is written unless it is a plain file
      # with a single name.
      def open_append(dir, name, perm: 0o644, create: true)
        check_name!(name)
        flags = File::WRONLY | File::APPEND | File::NOFOLLOW | File::NONBLOCK | (create ? File::CREAT : 0)
        plain(open_at(dir, name, flags, perm), single_name: true)
      rescue Errno::ENXIO
        # A FIFO with no reader, opened to write without waiting.
        raise Unsafe, 'not a plain file'
      end

      # A regular file of dir, open for reading bytes as File.binread does
      # (never a link, a FIFO or a device).
      def open_read(dir, name)
        check_name!(name)
        plain(open_at(dir, name, READ_FLAGS)).tap(&:binmode)
      end

      # A new folder name in dir (Errno::EEXIST when anything has the name),
      # yielded open.
      def make_dir(dir, name)
        check_name!(name)
        call!(:mkdirat, dir.fileno, name, 0o755)
        child = open_child_dir(dir, name, create: false)
        begin
          yield child
        ensure
          child.close
        end
      end

      # The folder name in dir and everything in it, removed. Every removal is
      # made in a folder held open, never through a link (a link is removed
      # itself), and no folder in skip_dirs is entered or removed. The names
      # are listed by path (Ruby cannot list an open folder); a listing is
      # only a hint of what to try: a name that is not in the folder held
      # open is not found there, so a folder swapped meanwhile leaves things
      # behind and never removes anything elsewhere. listed_path is where
      # name is, to list it.
      def remove_tree(dir, name, listed_path, depth = 0, skip_dirs: [])
        check_name!(name)
        raise Unsafe, 'the folder is too deep' if depth > TREE_DEPTH

        found = entry(dir, name)
        return nil if found.nil?
        return unlink(dir, name) unless found.is_a?(File::Stat) && found.directory?

        child = open_child_dir(dir, name, create: false)
        begin
          raise Unsafe, 'a folder the server may not write in' if skip_dirs.include?(identity(child.stat))

          path = File.join(listed_path, name)
          names = File.lstat(path).then { |s| identity(s) == identity(child.stat) ? Dir.children(path) : [] }
          names.each { |inner| remove_tree(child, inner, path, depth + 1, skip_dirs: skip_dirs) }
        ensure
          child.close
        end
        call!(:unlinkat, dir.fileno, name, AT_REMOVEDIR)
        nil
      rescue Errno::ENOENT
        nil
      end

      # The file (or the link) name in dir, removed; never a folder.
      def unlink(dir, name)
        check_name!(name)
        call!(:unlinkat, dir.fileno, name, 0)
        nil
      end

      def rename(from_dir, from, to_dir, to)
        check_name!(from)
        check_name!(to)
        call!(:renameat, from_dir.fileno, from, to_dir.fileno, to)
        nil
      end

      # What name is in dir: nil (nothing), :link, or the File::Stat of what
      # is there (a plain file or not), looked at without following a link.
      def entry(dir, name)
        check_name!(name)
        file = open_at(dir, name, READ_FLAGS)
        begin
          file.stat
        ensure
          file.close
        end
      rescue Errno::ENOENT
        nil
      rescue Errno::ELOOP
        :link
      end

      def identity(stat)
        [stat.dev, stat.ino]
      end

      def open_child_dir(dir, part, create:)
        begin
          child = open_at(dir, part, READ_FLAGS)
        rescue Errno::ENOENT
          raise unless create

          begin
            call!(:mkdirat, dir.fileno, part, 0o755)
          rescue Errno::EEXIST
            nil
          end
          child = open_at(dir, part, READ_FLAGS)
        end
        unless child.stat.directory?
          child.close
          raise Unsafe, 'not a folder'
        end
        child
      rescue Errno::ELOOP
        raise Unsafe, 'a link is not followed'
      end

      # The file, if it is a plain one (and has one name, when asked);
      # closed otherwise.
      def plain(file, single_name: false)
        stat = file.stat
        return file if stat.file? && (!single_name || stat.nlink == 1)

        file.close
        raise Unsafe, 'not a plain file'
      rescue SystemCallError, IOError
        file.close unless file.closed?
        raise
      end

      # The descriptor openat gives, owned by a File from here on.
      def open_at(dir, name, flags, mode = 0)
        fd = FUNCS.fetch(:openat).call(dir.fileno, name, flags | CLOEXEC, :int, mode)
        raise SystemCallError.new('openat failed', Fiddle.last_error) if fd == -1

        file = File.for_fd(fd, autoclose: true)
        return file if file.close_on_exec?

        file.close
        raise Unsafe, 'a descriptor would be inherited by child processes'
      end

      def tidy(dir, name)
        call!(:unlinkat, dir.fileno, name, 0)
      rescue SystemCallError
        nil
      end

      def check_name!(name)
        raise Unsafe, 'not a single name' unless name.is_a?(String) && NAME.match?(name) && !%w[. ..].include?(name)
      end

      def call!(func, *args)
        result = FUNCS.fetch(func).call(*args)
        return result unless result == -1

        errno = Fiddle.last_error
        raise SystemCallError.new("#{func} failed", errno)
      end
      private_class_method :open_child_dir, :plain, :open_at, :tidy, :check_name!, :call!
    end
  end
end
