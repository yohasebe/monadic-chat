# frozen_string_literal: true

require 'base64'
require 'fileutils'
require_relative 'environment'

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

      # Max image size accepted for image-to-video (provider limit, e.g. Vertex AI).
      MAX_IMAGE_TO_VIDEO_BYTES = 20 * 1024 * 1024

      # Resolve the source image for an image-to-video request into a real file
      # in the shared data directory, returning its bare filename.
      #
      # Uploaded images live in the session as a data URL
      # (message["images"].first["data"] == "data:image/...;base64,...") and are
      # NOT yet written to disk; the video CLI generators need a file on the
      # shared volume. This materializes that data URL into
      # "video_gen_temp_<timestamp>_<rand>.<ext>" and returns the filename.
      #
      # Resolution order:
      #   1. The most recent uploaded image in the session (data URL → file).
      #   2. An explicit image_path argument (a real filename), ignoring the
      #      literal placeholder "image_path" that models sometimes emit.
      #   3. last_image_key in the session (a previously materialized filename).
      #
      # @param session [Hash] the WebSocket session (provides :messages and fallbacks)
      # @param image_path [String, nil] filename passed by the tool call, if any
      # @param last_image_key [Symbol, nil] session key holding a prior filename
      # @return [String, nil] the bare filename on the shared volume, or nil
      def self.materialize_session_image(session, image_path: nil, last_image_key: nil)
        require "base64"

        materialized = nil

        # A freshly uploaded image always wins. Resolve it first regardless of
        # image_path, because models sometimes pass a hallucinated filename
        # (e.g. "image.jpg" or the literal "image_path") that does not exist.
        if session && session[:messages]
          with_images = session[:messages].select do |m|
            m["role"] == "user" && m["images"] && m["images"].any?
          end
          first_image = with_images.last && with_images.last["images"].first
          if first_image
            data_url = first_image["data"]
            if data_url.is_a?(String) && data_url.start_with?("data:image/")
              materialized = write_data_url_to_shared(data_url, first_image["type"])
            elsif first_image["filename"]
              materialized = first_image["filename"]
            elsif first_image["title"]
              materialized = first_image["title"]
            end
          end
        end

        # Explicit filename, ignoring the literal "image_path" placeholder.
        if materialized.nil? && image_path && image_path != "image_path"
          materialized = image_path
        end

        # Fall back to a previously materialized image for this app.
        if materialized.nil? && last_image_key && session && session[last_image_key]
          materialized = session[last_image_key]
        end

        materialized
      end

      # Decode a "data:image/...;base64,..." URL and write it to the shared data
      # directory. Returns the bare filename, or nil on failure / oversize.
      def self.write_data_url_to_shared(data_url, declared_mime = nil)
        base64_data = data_url.split(",", 2).last
        binary = Base64.decode64(base64_data)
        return nil if binary.bytesize > MAX_IMAGE_TO_VIDEO_BYTES

        mime = declared_mime
        mime ||= data_url.split(";").first.split(":").last if data_url.include?("image/")
        ext = case mime
              when "image/jpeg", "image/jpg" then ".jpg"
              when "image/png" then ".png"
              when "image/gif" then ".gif"
              when "image/webp" then ".webp"
              else
                if data_url.include?("image/png") then ".png"
                elsif data_url.include?("image/gif") then ".gif"
                elsif data_url.include?("image/webp") then ".webp"
                else ".jpg"
                end
              end

        dir = Environment.data_path
        return nil unless dir

        require "fileutils"
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        filename = "video_gen_temp_#{Time.now.to_i}_#{rand(1000)}#{ext}"
        File.binwrite(File.join(dir, filename), binary)
        filename
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "[ToolImageUtils] write_data_url_to_shared failed: #{e.message}" }
        nil
      end
    end
  end
end
