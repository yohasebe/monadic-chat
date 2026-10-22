# frozen_string_literal: true

require_relative 'environment'
require_relative 'shared_path_guard'

module Monadic
  module Utils
    # A copy of a file directly in the shared folder, where the page can load
    # it (/data/<name>), while the file itself stays in a chat's folder. A real
    # copy, not a link: code that writes to the public file must not change the
    # original. Made once (an existing plain file of the same size is kept);
    # both the original and the copy are reached only through
    # SharedPathGuard, never through a link, and the copy is written new and
    # then put in place, so a half-written file is never served.
    module PublicCopy
      module_function

      # Returns the /data address, or nil when the copy cannot be made.
      def publish(source, name)
        dest = File.join(Environment.data_path, name)
        existing = SharedPathGuard.file_stat(dest)
        SharedPathGuard.read_file!(source) do |original|
          SharedPathGuard.write_file!(dest, original) unless existing&.size == original.stat.size
        end
        "/data/#{name}"
      rescue SharedPathGuard::InvalidPath, SystemCallError, IOError
        nil
      end

      # The same from bytes in hand (what was kept as an artifact), so the
      # copy is made from them and not from a file another program can change.
      def publish_bytes(bytes, name)
        dest = File.join(Environment.data_path, name)
        existing = SharedPathGuard.file_stat(dest)
        SharedPathGuard.write_file!(dest, bytes) unless existing&.size == bytes.bytesize
        "/data/#{name}"
      rescue SharedPathGuard::InvalidPath, SystemCallError, IOError
        nil
      end
    end
  end
end
