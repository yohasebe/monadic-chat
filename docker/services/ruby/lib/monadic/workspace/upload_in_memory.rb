# frozen_string_literal: true

require 'stringio'
require 'rack'

module Monadic
  module Workspace
    # Keeps the file parts of a request to these paths in memory instead of
    # temporary files. What they carry (a conversation to import, perhaps
    # one exported from a Private chat) is read whole anyway, and a
    # temporary file of it could outlive the request (a crash before it is
    # removed).
    class UploadInMemory
      # Rack hands each part it made to Rack::TempfileReaper, which calls
      # close! on it.
      class Part < StringIO
        def close!
          close
        end
      end

      FACTORY = ->(_filename, _content_type) { Part.new(+'') }

      def initialize(app, paths:)
        @app = app
        @paths = paths
      end

      def call(env)
        env[Rack::RACK_MULTIPART_TEMPFILE_FACTORY] = FACTORY if @paths.include?(env['PATH_INFO'])
        @app.call(env)
      end
    end
  end
end
