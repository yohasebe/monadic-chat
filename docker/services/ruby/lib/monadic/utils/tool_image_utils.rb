# frozen_string_literal: true

module Monadic
  module Utils
    module ToolImageUtils
      # Read an image file from the shared data directory and return base64-encoded data.
      # @param filename [String] image filename relative to data_path
      # @param max_base64_size [Integer] maximum allowed size of base64 string in bytes (default 5 MB)
      # @return [Hash, nil] { media_type: "image/png", base64_data: "..." } or nil
      def self.encode_image_for_api(filename, max_base64_size: 5 * 1024 * 1024)
        return nil unless filename.is_a?(String) && !filename.empty?

        image_path = File.join(Environment.data_path, filename)
        return nil unless File.exist?(image_path)

        ext = File.extname(filename).downcase.delete(".")
        media_type = case ext
                     when "png" then "image/png"
                     when "jpg", "jpeg" then "image/jpeg"
                     when "gif" then "image/gif"
                     when "webp" then "image/webp"
                     else "image/png"
                     end

        raw_data = File.binread(image_path)
        base64_data = Base64.strict_encode64(raw_data)
        return nil if base64_data.bytesize > max_base64_size

        { media_type: media_type, base64_data: base64_data }
      end
    end
  end
end
