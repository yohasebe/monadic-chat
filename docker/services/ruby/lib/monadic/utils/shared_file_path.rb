# frozen_string_literal: true

require 'rack'
require 'time'
require_relative 'shared_path_guard'

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

      # The file a /data/<name> URL serves, open, or nil: the same name
      # checks, then opened as a plain file of the shared folder through
      # SharedPathGuard (never through a link, even one put there after a
      # check), so what is served is what was opened. The caller closes it
      # (Body does).
      def open(requested, datadir)
        return nil unless valid_name?(requested)

        SharedPathGuard.open_file!(File.join(datadir, requested.to_s))
      rescue SharedPathGuard::InvalidPath, SystemCallError, ArgumentError, EncodingError
        nil
      end

      def valid_name?(requested)
        name = requested.to_s.dup
        name = name.force_encoding(Encoding::UTF_8) if name.encoding != Encoding::UTF_8
        !(name.empty? || !name.valid_encoding? || name.include?("\0") ||
          name.include?("/") || name.include?("\\") || %w[. ..].include?(name))
      end

      NOT_FOUND = [404, { 'content-type' => 'text/plain' }, ['Sorry, the file you are looking for is unavailable.']].freeze

      # The Rack response for GET or HEAD /data/<name>: the whole file, one
      # byte range of it (206; 416 when the range is outside it), or 304 when
      # the browser's copy is current, all from the one file opened by open.
      # extra_headers are added to a served file (by its content type).
      def response(requested, datadir, env, extra_headers: ->(_type) { {} })
        file = SharedFilePath.open(requested, datadir)
        return NOT_FOUND.dup unless file

        respond(file, Rack::Mime.mime_type(File.extname(requested.to_s), 'application/octet-stream'), env,
                extra_headers: extra_headers)
      end

      # The response from a file already open (the one checked), served as
      # type; it is closed here unless the body takes it.
      def respond(file, type, env, extra_headers: ->(_type) { {} })
        handed_over = false
        begin
          stat = file.stat
          headers = { 'content-type' => type, 'last-modified' => stat.mtime.httpdate, 'accept-ranges' => 'bytes',
                      'x-content-type-options' => 'nosniff' }.merge(extra_headers.call(type))
          return [304, headers.slice('last-modified', 'x-content-type-options'), []] if not_modified?(env, stat.mtime)

          size = stat.size
          ranges = Rack::Utils.get_byte_ranges(env['HTTP_RANGE'], size)
          return [416, headers.merge('content-range' => "bytes */#{size}", 'content-length' => '0'), []] if ranges&.empty?

          status, offset, length = 200, 0, size
          if ranges&.size == 1
            range = ranges.first
            status, offset, length = 206, range.begin, range.size
            headers['content-range'] = "bytes #{range.begin}-#{range.end}/#{size}"
          end
          headers['content-length'] = length.to_s
          handed_over = true
          [status, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : Body.new(file, offset, length)]
        ensure
          # Unless a body took it, the file is closed now (also for HEAD).
          file.close if (!handed_over || env['REQUEST_METHOD'] == 'HEAD') && !file.closed?
        end
      rescue StandardError
        NOT_FOUND.dup
      end

      def not_modified?(env, mtime)
        since = env['HTTP_IF_MODIFIED_SINCE']
        return false unless since && !env['HTTP_RANGE']

        Time.httpdate(since).to_i >= mtime.to_i
      rescue ArgumentError
        false
      end

      # A response body of bytes offset...offset+length of an open file,
      # read in pieces; closing it closes the file. It has no to_path, so the
      # server never reopens the file by its name.
      class Body
        CHUNK = 64 * 1024

        def initialize(file, offset, length)
          @file = file
          @offset = offset
          @length = length
        end

        def each
          @file.seek(@offset)
          remaining = @length
          while remaining.positive?
            chunk = @file.read([CHUNK, remaining].min)
            break unless chunk

            remaining -= chunk.bytesize
            yield chunk
          end
        end

        def close
          @file.close unless @file.closed?
        end
      end
    end
  end
end
