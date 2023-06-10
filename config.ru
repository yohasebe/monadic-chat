# frozen_string_literal: false

require "sinatra"
require "rack/session/pool"

require_relative "lib/monadic"

set :logging, true
set :bind, "0.0.0.0"

Faye::WebSocket.load_adapter("thin")

run Sinatra::Application
