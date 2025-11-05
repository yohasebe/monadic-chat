# frozen_string_literal: false

require "sinatra"
require "rack/session/pool"
require "async/websocket/adapters/rack"

require_relative "lib/monadic"

set :logging, true
set :bind, "0.0.0.0"

# Use in-memory sessions (Pool) for normal operation
# For import functionality, we'll save/load session data to/from files
use Rack::Session::Pool, key: 'monadic.session',
                         expire_after: 86400  # 24 hours

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

use MCPServerStarter
run Sinatra::Application
