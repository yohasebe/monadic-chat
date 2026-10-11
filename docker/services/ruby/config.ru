# frozen_string_literal: false

require "sinatra"
require "rack/session/pool"
require "rack/tempfile_reaper"
require "async/websocket/adapters/rack"

require_relative "lib/monadic"
require_relative "lib/monadic/utils/unlimited_session_store"
require_relative "lib/monadic/utils/auth_middleware"
require_relative "lib/monadic/utils/local_origin_guard"

set :logging, true
set :bind, "0.0.0.0"

# First of all: only this computer's own pages and programs may use the
# server. See lib/monadic/utils/local_origin_guard.rb.
use Monadic::Utils::LocalOriginGuard

# Remove the temporary files Rack writes for multipart uploads once the
# response is sent; left alone they stay until garbage collection.
use Rack::TempfileReaper

# Attachments: the chat fixed from the tab, then the size cap, both before
# anything reads the request body.
use Monadic::Workspace::UploadContext,
    paths: [Monadic::Routes::AttachmentRoutes::PATH],
    state_lookup: ->(tab_id) { WebSocketHelper.fetch_session_state(tab_id) }
# Every upload, likewise capped before anything reads the body: Rack writes
# file parts to disk while parsing, with no total limit of its own.
use Monadic::Workspace::UploadLimit, limits: {
  Monadic::Routes::AttachmentRoutes::PATH => Monadic::Workspace::UploadLimit::DEFAULT_MAX_BYTES,
  "/pdf" => PDF_UPLOAD_MAX_BYTES,
  "/document" => DOCUMENT_UPLOAD_MAX_BYTES,
  "/upload_audio" => AUDIO_UPLOAD_MAX_BYTES,
  "/load" => SESSION_LOAD_MAX_BYTES,
  # The route checks the file itself; this stops the body first, with room
  # for the multipart framing around the file.
  "/library/import" => LIBRARY_IMPORT_MAX_BYTES + 1_000_000
}

# Use unlimited in-memory sessions to handle large message imports
# Rack::Session::Pool has size limits that cause "Content dropped" warnings
# Use a capped pool to avoid unbounded memory growth while allowing larger payloads
use Rack::Session::CappedPool, key: 'monadic.session',
                               expire_after: 86400,  # 24 hours
                               max_sessions: (ENV['SESSION_MAX_COUNT'] || 50).to_i,
                               max_session_bytes: (ENV['SESSION_MAX_BYTES'] || 16 * 1024 * 1024).to_i

# Middleware to start MCP server once Async reactor is running
class MCPServerStarter
  def initialize(app)
    @app = app
    @started = false
    @mutex = Mutex.new
  end

  def call(env)
    # Start MCP server on first request (Async reactor is now running)
    @mutex.synchronize do
      unless @started
        if defined?(Monadic::MCP::Server)
          Monadic::MCP::Server.start!
        end
        @started = true
      end
    end

    @app.call(env)
  end
end

# The ports are published to this machine only. The auth middleware asks
# for MONADIC_AUTH_TOKEN only when DISTRIBUTED_MODE is "server", which
# Monadic::Utils::ServerMode.normalize! never leaves set, so it passes every
# request through. See lib/monadic/utils/auth_middleware.rb.
use Monadic::Utils::AuthMiddleware
use MCPServerStarter
run Sinatra::Application
