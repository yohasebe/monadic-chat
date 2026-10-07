# frozen_string_literal: true

module Monadic
  module Utils
    # Which file a /data/<name> URL may serve: a file at the top of the
    # shared folder, and nothing under a subfolder. The name must not climb out
    # of the folder, and the resolved real path (symlinks followed) must stay
    # inside it.
    module SharedFilePath
      module_function

      # The absolute path to serve, or nil.
      def resolve(requested, datadir)
        name = requested.to_s.dup
        name = name.force_encoding(Encoding::UTF_8) if name.encoding != Encoding::UTF_8
        return nil if name.empty? || !name.valid_encoding? || name.include?("\0")
        return nil if name.include?("/") || name.include?("\\") || %w[. ..].include?(name)

        file_path = File.join(datadir, name)
        return nil unless File.file?(file_path)

        real_datadir = File.realpath(datadir)
        real_datadir += File::SEPARATOR unless real_datadir.end_with?(File::SEPARATOR)
        File.realpath(file_path).start_with?(real_datadir) ? file_path : nil
      rescue SystemCallError, ArgumentError, EncodingError
        nil
      end
    end
  end
end
