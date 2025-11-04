# frozen_string_literal: false

require "sinatra"
require "rack/session/pool"
require "async/websocket/adapters/rack"

require_relative "lib/monadic"

set :logging, true
set :bind, "0.0.0.0"

run Sinatra::Application
