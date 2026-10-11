# frozen_string_literal: true

require_relative 'environment'

module Monadic
  module Utils
    # A copy of a file directly in the shared folder, where the page can load
    # it (/data/<name>), while the file itself stays in a chat's folder. A real
    # copy, not a link: code that writes to the public file must not change the
    # original. Made once (an existing copy of the same size is kept), written
    # under a temporary name and then renamed, so a half-written file is never
    # served.
    module PublicCopy
      module_function

      # Returns the /data address, or nil when the copy cannot be made.
      def publish(source, name)
        dest = File.join(Environment.data_path, name)
        unless File.file?(dest) && File.size(dest) == File.size(source)
          partial = "#{dest}.part-#{Process.pid}"
          File.open(source, "rb") { |src| File.open(partial, "wb") { |out| IO.copy_stream(src, out) } }
          File.rename(partial, dest)
        end
        "/data/#{name}"
      rescue SystemCallError, IOError
        nil
      ensure
        # A copy left half-written (failed, or stopped by Reset or Cancel).
        File.delete(partial) if partial && File.exist?(partial) rescue nil
      end
    end
  end
end
