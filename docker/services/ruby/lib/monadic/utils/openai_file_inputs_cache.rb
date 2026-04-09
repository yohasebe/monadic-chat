# frozen_string_literal: true

require "digest"
require "net/http"
require "json"

module Monadic
  module Utils
    # Session-level cache for OpenAI File Inputs API file IDs.
    # Uploads files once via POST /v1/files and caches the file_id
    # so subsequent turns reuse it instead of re-sending base64 data.
    module OpenAIFileInputsCache
      MAX_FILE_SIZE = 50 * 1024 * 1024 # 50 MB

      module_function

      # Compute a cache key from already-decoded raw bytes.
      # Uses SHA256 + byte size to avoid collisions.
      def compute_hash(raw_bytes)
        digest = Digest::SHA256.hexdigest(raw_bytes)
        "#{digest}_#{raw_bytes.bytesize}"
      end

      # Look up cached file_id or upload to OpenAI Files API.
      # Returns file_id (String) on success, nil on failure.
      def resolve_or_upload(session, base64_data, filename, mime_type)
        return nil if base64_data.nil? || base64_data.empty?

        raw = Base64.decode64(base64_data)
        if raw.bytesize > MAX_FILE_SIZE
          puts "[FileInputsCache] File too large (#{raw.bytesize} bytes > #{MAX_FILE_SIZE})" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          return nil
        end

        session[:openai_file_inputs_cache] ||= {}
        cache = session[:openai_file_inputs_cache]
        hash_key = compute_hash(raw)

        # Cache hit
        if cache[hash_key]
          puts "[FileInputsCache] Cache hit for #{filename} (#{hash_key[0..15]}...)" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          return cache[hash_key][:file_id]
        end

        # Upload to OpenAI Files API
        file_id = upload_file(raw, filename, mime_type)
        return nil unless file_id

        cache[hash_key] = {
          file_id: file_id,
          filename: filename,
          uploaded_at: Time.now.to_i
        }

        puts "[FileInputsCache] Uploaded #{filename} → #{file_id}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        file_id
      rescue StandardError => e
        puts "[FileInputsCache] Error: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        nil
      end

      # Upload raw bytes to POST /v1/files with purpose "user_data".
      def upload_file(raw_bytes, filename, _mime_type)
        api_key = if defined?(CONFIG)
                     CONFIG["OPENAI_API_KEY"]
                   end
        return nil unless api_key

        uri = URI("https://api.openai.com/v1/files")
        boundary = "----MonadicChat#{SecureRandom.hex(16)}"

        body = build_multipart_body(boundary, raw_bytes, filename)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 30
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        request.body = body

        response = http.request(request)

        if response.code.to_i == 200
          parsed = JSON.parse(response.body)
          parsed["id"]
        else
          puts "[FileInputsCache] Upload failed (#{response.code}): #{response.body}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          nil
        end
      rescue StandardError => e
        puts "[FileInputsCache] Upload error: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        nil
      end

      # Build a multipart/form-data body for the Files API.
      def build_multipart_body(boundary, raw_bytes, filename)
        # Sanitize filename to prevent header injection
        safe_filename = filename.to_s.gsub(/[\r\n"]/, "_").gsub(/[^\w.\-]/, "_")
        safe_filename = "document" if safe_filename.empty?

        parts = []

        # purpose field
        parts << "--#{boundary}\r\n"
        parts << "Content-Disposition: form-data; name=\"purpose\"\r\n\r\n"
        parts << "user_data\r\n"

        # file field
        parts << "--#{boundary}\r\n"
        parts << "Content-Disposition: form-data; name=\"file\"; filename=\"#{safe_filename}\"\r\n"
        parts << "Content-Type: application/octet-stream\r\n\r\n"
        parts << raw_bytes
        parts << "\r\n"

        # closing boundary
        parts << "--#{boundary}--\r\n"

        parts.join
      end
    end
  end
end
