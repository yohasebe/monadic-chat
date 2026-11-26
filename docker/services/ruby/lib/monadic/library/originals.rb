# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'monitor'
require 'securerandom'
require_relative '../utils/environment'

module Monadic
  module Library
    # The files imported into the Knowledge Base, each kept once, named by
    # the SHA-256 of its bytes, in originals/ of the Library's own folder
    # (Environment.library_path). Only this server mounts that folder: the
    # other containers, where code a model writes runs, cannot read or
    # change it, so a file is reached through the Library only.
    #
    # An import holds the original it keeps (keep) until it ends (release);
    # an original is removed (remove_if_unused) only when no import holds it
    # and no entry names it. These run one at a time.
    module Originals
      class Missing < StandardError; end
      class Changed < StandardError; end

      SHA256 = /\A\h{64}\z/
      LOCK = Monitor.new
      @held = Hash.new(0)

      module_function

      def dir
        File.join(Monadic::Utils::Environment.library_path, 'originals')
      end

      # Keeps the bytes of the file at path and holds them for the caller.
      # Returns { sha256:, bytes: }. The same bytes kept before are used as
      # they are; a file of that name with other bytes raises Changed.
      def keep(path)
        sha256 = Digest::SHA256.file(path).hexdigest
        bytes = File.size(path)
        LOCK.synchronize do
          target = path_of(sha256)
          if File.exist?(target) || File.symlink?(target)
            raise Changed, 'the kept file is not the one named' unless intact?(target, sha256)
          else
            write(path, target, sha256)
          end
          @held[sha256] += 1
        end
        { sha256: sha256, bytes: bytes }
      end

      def release(sha256)
        LOCK.synchronize do
          @held[sha256] -= 1
          @held.delete(sha256) unless @held[sha256].positive?
        end
      end

      # Removes the original when no import holds it and the block (the
      # number of entries naming it) returns 0. Kept when the count cannot
      # be had. True when it was removed.
      def remove_if_unused(sha256)
        LOCK.synchronize do
          return false if @held[sha256].positive?

          count = begin
            yield(sha256)
          rescue StandardError
            nil
          end
          return false unless count.is_a?(Integer) && count.zero?

          target = path_of(sha256)
          File.delete(target) if File.file?(target) && !File.symlink?(target)
          true
        end
      end

      # The bytes of the original, as kept: Missing when it is not there,
      # Changed when its bytes are not the ones named.
      def read(sha256)
        target = path_of(sha256)
        raise Missing, 'the original is not kept' unless File.file?(target) && !File.symlink?(target)

        bytes = File.binread(target)
        raise Changed, 'the original was changed' unless Digest::SHA256.hexdigest(bytes) == sha256

        bytes
      end

      def held?(sha256)
        LOCK.synchronize { @held[sha256].positive? }
      end

      def path_of(sha256)
        raise ArgumentError, 'not a SHA-256' unless sha256.to_s.match?(SHA256)

        File.join(dir, sha256)
      end

      # Written beside the target and renamed onto it once the bytes are
      # the ones named.
      def write(path, target, sha256)
        FileUtils.mkdir_p(dir, mode: 0o700)
        part = "#{target}.#{SecureRandom.hex(4)}.part"
        begin
          File.open(part, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |out|
            File.open(path, 'rb') { |src| IO.copy_stream(src, out) }
          end
          raise Changed, 'the file changed while it was kept' unless intact?(part, sha256)

          File.rename(part, target)
        ensure
          File.delete(part) if File.exist?(part)
        end
      end

      def intact?(file, sha256)
        File.file?(file) && !File.symlink?(file) && Digest::SHA256.file(file).hexdigest == sha256
      end
    end
  end
end
