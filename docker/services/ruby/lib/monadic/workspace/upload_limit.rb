# frozen_string_literal: true

require 'json'
require 'rack/multipart'

module Monadic
  module Workspace
    # Caps the request body of an upload before anything parses it. Rack
    # writes every file part of a multipart body to a temporary file while
    # building params, with no total limit, so a check inside the route runs
    # only after the whole body is on disk. This counts the bytes as the
    # server hands them over and stops reading once the cap is passed.
    class UploadLimit
      # Provisional: the attachment limit is set after measuring video
      # handling end to end.
      DEFAULT_MAX_BYTES = 2_000_000_000
      EXCEEDED_KEY = 'monadic.upload_limit.exceeded'

      class TooLarge < StandardError; end

      # Reads through to the server's input and raises once more than limit
      # bytes have come through.
      class LimitedInput
        def initialize(input, limit, env)
          @input = input
          @limit = limit
          @env = env
          @count = 0
        end

        def read(length = nil, buffer = nil)
          data = @input.read(length, buffer)
          count!(data)
          data
        end

        def gets
          count!(@input.gets)
        end

        def each
          while (chunk = read(16_384))
            yield chunk
          end
        end

        def rewind
          @input.rewind if @input.respond_to?(:rewind)
          @count = 0
        end

        def close
          @input.close if @input.respond_to?(:close)
        end

        private

        def count!(data)
          return data unless data

          @count += data.bytesize
          if @count > @limit
            @env[EXCEEDED_KEY] = true
            raise TooLarge, 'upload exceeds the size limit'
          end
          data
        end
      end

      def initialize(app, paths:, max_bytes: DEFAULT_MAX_BYTES)
        @app = app
        @paths = paths
        @max_bytes = max_bytes
      end

      def call(env)
        return @app.call(env) unless env['REQUEST_METHOD'] == 'POST' && @paths.include?(env['PATH_INFO'])

        declared = env['CONTENT_LENGTH']
        return too_large if declared && declared.to_i > @max_bytes

        env['rack.input'] = LimitedInput.new(env['rack.input'], @max_bytes, env) if env['rack.input']
        tempfiles = track_tempfiles(env)
        begin
          response = begin
            @app.call(env)
          rescue TooLarge
            nil
          end
          # The parser may have turned the interruption into an error page;
          # the flag says what really happened.
          env[EXCEEDED_KEY] ? too_large : response
        ensure
          # Rack lists its temporary files only after a parse succeeds, so a
          # cut-off upload would leave its partial file behind. Every one made
          # for this request is removed here; the route has copied what it
          # kept by now.
          tempfiles.each { |file| file.close! rescue nil }
        end
      end

      private

      def track_tempfiles(env)
        made = []
        factory = env['rack.multipart.tempfile_factory'] || Rack::Multipart::Parser::TEMPFILE_FACTORY
        env['rack.multipart.tempfile_factory'] = lambda do |filename, content_type|
          factory.call(filename, content_type).tap { |file| made << file }
        end
        made
      end

      def too_large
        limit_mb = @max_bytes / 1_000_000
        body = { error: "The file is larger than the #{limit_mb} MB limit for attachments.", reason: 'too_large' }.to_json
        [413, { 'content-type' => 'application/json', 'connection' => 'close' }, [body]]
      end
    end
  end
end
