# frozen_string_literal: true

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
