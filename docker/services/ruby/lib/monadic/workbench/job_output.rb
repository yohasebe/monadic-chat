# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require_relative 'store'
require_relative '../workspace/ids'
require_relative '../workspace/ledger'

module Monadic
  module Workbench
    # The folder a generator runs in for a chat's workbench
    # (workbench/<chat id>/jobs/<job id>/ in the state folder): made by the
    # server for one run, read by the server when the run ends, then
    # removed. What a generator writes there is not yet a candidate; the
    # server checks it first (ImageCheck).
    #
    # The server gives the run what it works from in in/ (put_input!), and
    # the generator writes what it makes in out/ (write!): each takes a
    # folder of this form that the server made (owned by this user, closed
    # to others, with no link on the way) and a plain name, and makes a new
    # file there (an existing name or a link in its place is refused). The
    # generator reads its input only through read_input.
    module JobOutput
      NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,150}\z/
      JOB = /\Aj_[a-f0-9]{20}\z/
      # A run's folder holds what it is given (in) apart from what it makes
      # (out): only what it made can become an image of the board.
      PARTS = %w[in out].freeze

      class Refused < StandardError; end

      module_function

      # A new folder for one run of a generator for the chat, with its in/
      # and out/ folders.
      def make(chat_id, store: Store.default)
        jobs = File.join(store.chat_dir(chat_id, make: true), 'jobs')
        make_dir(jobs)
        dir = File.join(jobs, "j_#{SecureRandom.hex(10)}")
        Dir.mkdir(dir, 0o700)
        PARTS.each { |part| Dir.mkdir(File.join(dir, part), 0o700) }
        dir
      end

      def out_dir(job)
        File.join(job, 'out')
      end

      # dir, when it is a job folder the server made (or, with part, its
      # in/ or out/ folder); raises Refused otherwise.
      def checked_dir!(dir, root: Store.default.root, part: nil)
        raise Refused, 'not an absolute path' unless dir.is_a?(String) && File.absolute_path(dir) == dir

        prefix = "#{root}/"
        raise Refused, 'not a job folder' unless dir.start_with?(prefix)

        chat, jobs, job, *rest = dir.delete_prefix(prefix).split('/')
        unless rest == Array(part) && Monadic::Workspace::Ids.valid?(:chat, chat) && jobs == 'jobs' && JOB.match?(job.to_s)
          raise Refused, 'not a job folder'
        end
        unless File.realpath(dir) == File.join(File.realpath(root), chat, jobs, job, *Array(part))
          raise Refused, 'a link on the way'
        end

        stat = File.lstat(dir)
        raise Refused, 'not a folder of this user' unless stat.directory? && stat.owned? && (stat.mode & 0o077).zero?

        dir
      rescue SystemCallError
        raise Refused, 'not a job folder'
      end

      # Writes a new file named name in a run's out/ folder (the generator).
      def write!(dir, name, bytes, root: Store.default.root)
        checked_dir!(dir, root: root, part: 'out')
        create(dir, name, bytes)
      end

      # Gives a run a file in its in/ folder (the server). Returns its path.
      def put_input!(job, name, bytes, root: Store.default.root)
        create(checked_dir!(File.join(job, 'in'), root: root, part: 'in'), name, bytes)
      end

      # The bytes of a file the server gave a run (path in its in/ folder;
      # with job, that run's), read without following a link; raises Refused
      # for any other path.
      def read_input(path, root: Store.default.root, job: nil)
        raise Refused, 'not an input file' unless path.is_a?(String) && NAME.match?(File.basename(path))
        raise Refused, 'an input of another run' if job && File.dirname(path, 2) != job

        checked_dir!(File.dirname(path), root: root, part: 'in')
        raise Refused, 'not an input file' unless File.lstat(path).file?

        File.open(path, File::RDONLY | File::NOFOLLOW, binmode: true, &:read)
      rescue SystemCallError
        raise Refused, 'not an input file'
      end

      # The plain files a run made (in its out/ folder), by name.
      def files(job)
        dir = out_dir(job)
        Dir.children(dir).sort.select { |name| NAME.match?(name) && File.lstat(File.join(dir, name)).file? }
      end

      # The bytes of a file the run made, read without following a link.
      def read(job, name)
        File.open(File.join(out_dir(job), name), File::RDONLY | File::NOFOLLOW, binmode: true, &:read)
      end

      # Removes a job folder and what is in it.
      def remove(dir, root: Store.default.root)
        FileUtils.rm_rf(checked_dir!(dir, root: root))
      rescue Refused
        nil
      end

      def create(dir, name, bytes)
        raise Refused, 'not a plain file name' unless NAME.match?(name.to_s)

        path = File.join(dir, name)
        Monadic::Workspace::Ledger::Disk.create_exclusive(path, bytes)
        path
      end

      def make_dir(dir)
        Dir.mkdir(dir, 0o700)
      rescue Errno::EEXIST
        raise Errno::ENOTDIR, dir unless File.directory?(dir) && !File.symlink?(dir)
      end
    end
  end
end
