# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require 'securerandom'
require 'time'
require 'async'
require 'async/http/endpoint'
require 'async/http/server'
require 'protocol/rack'
require_relative '../utils/debug_helper'
require_relative '../utils/extra_logger'
require_relative '../utils/environment'
require_relative 'cache_invalidator'
require_relative 'conduit'

module Monadic
  module MCP
    class Server < Sinatra::Base
      include DebugHelper

      # Configuration
      set :bind, '127.0.0.1'
      set :public_folder, false
      set :logging, false  # Disable Sinatra logging to avoid Rack env issues with Falcon
      set :dump_errors, true
      set :show_exceptions, false
      set :raise_errors, false

      # Explicitly disable logger middleware to avoid Async::HTTP compatibility issues
      disable :logging
      set :logger, nil

      # Protocol constants
      JSONRPC_VERSION = "2.0"
      MCP_PROTOCOL_VERSION = "2025-06-18"

      # Standard JSON-RPC error codes
      PARSE_ERROR = -32700
      INVALID_REQUEST = -32600
      METHOD_NOT_FOUND = -32601
      INVALID_PARAMS = -32602
      INTERNAL_ERROR = -32603

      # Server status
      @@server_running = false
      @@server_thread = nil

      # CORS headers for HTTP transport
      before do
        headers['Access-Control-Allow-Origin'] = '*'
        headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        headers['Access-Control-Allow-Headers'] = 'Content-Type, Accept'

        if request.request_method == 'OPTIONS'
          halt 200
        end
      end

      # Health check endpoint
      get '/health' do
        content_type :json
        {
          status: 'ok',
          version: MCP_PROTOCOL_VERSION,
          timestamp: Time.now.iso8601
        }.to_json
      end

      # Main MCP endpoint
      post '/mcp' do
        begin
          content_type :json

          # Parse JSON-RPC request
          begin
            request_data = JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            return json_rpc_error(nil, "Parse error", PARSE_ERROR, e.message)
          end

          # Handle batch requests
          if request_data.is_a?(Array)
            results = request_data.map { |req| handle_single_request(req) }
            return results.to_json
          else
            handle_single_request(request_data)
          end
        rescue => e
          puts "[MCP] Server error: #{e.message}"
          Monadic::Utils::ExtraLogger.log { e.backtrace.join("\n") }
          json_rpc_error(nil, "Internal error", INTERNAL_ERROR, e.message)
        end
      end

      private

      def handle_single_request(request)
        # Validate request according to JSON-RPC 2.0
        unless request.is_a?(Hash) && request['jsonrpc'] == JSONRPC_VERSION
          return json_rpc_error(request['id'], "Invalid Request", INVALID_REQUEST)
        end

        # ID must be string or integer, not null
        id = request['id']
        unless id.is_a?(String) || id.is_a?(Integer)
          return json_rpc_error(nil, "Invalid Request", INVALID_REQUEST)
        end

        method = request['method']
        params = request['params'] || {}

        # Route to appropriate handler
        case method
        when 'initialize'
          handle_initialize(id, params)
        when 'tools/list'
          handle_tools_list(id, params)
        when 'tools/call'
          handle_tool_call(id, params)
        else
          json_rpc_error(id, "Method not found", METHOD_NOT_FOUND)
        end
      end

      def handle_initialize(id, params)
        client_info = params['clientInfo'] || {}

        result = {
          protocolVersion: MCP_PROTOCOL_VERSION,
          serverInfo: {
            name: "monadic-chat",
            version: Monadic::VERSION
          },
          capabilities: {
            tools: {}
          }
        }

        json_rpc_response(id, result)
      end

      def handle_tools_list(id, _params)
        # Conduit surface: a small, stable set of capability tools (monadic_*).
        # This deliberately replaces the former per-app `app__tool` surface —
        # see lib/monadic/mcp/conduit.rb for the design rationale.
        tools = Monadic::MCP::Conduit.tools

        Monadic::Utils::ExtraLogger.log { "[MCP] Listing #{tools.length} Conduit tools" }

        json_rpc_response(id, { tools: tools })
      end

      def handle_tool_call(id, params)
        tool_name = params['name']
        arguments = params['arguments'] || {}

        unless tool_name
          return json_rpc_error(id, "Missing tool name", INVALID_PARAMS)
        end

        unless Monadic::MCP::Conduit.tool?(tool_name)
          return json_rpc_error(id, "Unknown tool: #{tool_name}", INVALID_PARAMS)
        end

        begin
          result = Monadic::MCP::Conduit.call(tool_name, arguments)
          # MCP 2025-06-18 lets a tool return both human-readable text and a
          # machine-readable structuredContent object. Conduit handlers return
          # a Hash, so we surface both for calling agents.
          json_rpc_response(id, {
            content: [{ type: "text", text: JSON.pretty_generate(result) }],
            structuredContent: result
          })
        rescue => e
          Monadic::Utils::ExtraLogger.log { "[MCP] Error executing tool #{tool_name}: #{e.message}" }
          json_rpc_error(id, "Tool execution failed", INTERNAL_ERROR, e.message)
        end
      end

      def json_rpc_response(id, result)
        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: result
        }.to_json
      end

      def json_rpc_error(id, message, code, data = nil)
        error = {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          error: {
            code: code,
            message: message
          }
        }
        error[:error][:data] = data if data
        error.to_json
      end

      # Retained for CacheInvalidator, which clears the MCP tool cache on app
      # reloads. The Conduit surface is static (not derived from apps), so there
      # is nothing to invalidate — this is intentionally a no-op.
      def self.clear_cache
        nil
      end

      # Interface to bind the MCP HTTP server to. In the container we bind all
      # interfaces so Docker port publishing works; on the host we stay on
      # loopback. Host-side exposure is constrained to loopback by the compose
      # publish mapping regardless of this value.
      def self.mcp_bind_host
        if defined?(Monadic::Utils::Environment) &&
           Monadic::Utils::Environment.respond_to?(:in_container?) &&
           Monadic::Utils::Environment.in_container?
          "0.0.0.0"
        else
          "127.0.0.1"
        end
      end

      # Get server status
      def self.status
        {
          enabled: CONFIG["MCP_SERVER_ENABLED"] == true || CONFIG["MCP_SERVER_ENABLED"] == "true",
          port: (CONFIG["MCP_SERVER_PORT"] || 3100).to_i,
          running: defined?(@@server_running) && @@server_running
        }
      end

      # Stop the MCP server
      def self.stop!
        if defined?(@@server_thread) && @@server_thread
          @@server_thread.kill
          @@server_thread = nil
          @@server_running = false
          puts "[MCP] Server stopped"
        end
      end

      # Start the MCP server using Async (runs in current Falcon worker)
      def self.start!
        return unless CONFIG["MCP_SERVER_ENABLED"] == true || CONFIG["MCP_SERVER_ENABLED"] == "true"

        port = (CONFIG["MCP_SERVER_PORT"] || 3100).to_i

        # Inside the Ruby container we must bind all interfaces so Docker's
        # port publish (host 127.0.0.1 -> container) can reach us; the publish
        # mapping in compose keeps host exposure on loopback only. On the host
        # (dev mode) we bind loopback directly. See compose.yml MCP port note.
        bind_host = mcp_bind_host

        # Check if port is already in use
        begin
          require 'socket'
          server = TCPServer.new(bind_host, port)
          server.close
        rescue Errno::EADDRINUSE
          puts "[MCP] MCP Server port #{port} is already in use. Skipping MCP server startup."
          return
        rescue => e
          puts "[MCP] Error checking port availability: #{e.message}"
          return
        end

        # Start HTTP server as background task in current Async context
        # This runs within the Falcon worker process, sharing memory and APPS constant
        Async do |task|
          begin
            puts "[MCP] Starting MCP Server on port #{port} in worker process #{Process.pid}..."

            endpoint = Async::HTTP::Endpoint.parse("http://#{bind_host}:#{port}")

            # Create Rack app
            app = Rack::Builder.new do
              run Monadic::MCP::Server
            end

            # Wrap Rack app for Async::HTTP::Server
            middleware = Protocol::Rack::Adapter.new(app)

            # Create and bind the server
            server = Async::HTTP::Server.new(middleware, endpoint)

            @@server_running = true
            puts "[MCP] MCP Server started on port #{port}"

            # Notify via WebSocket if available
            if defined?(WebSocketHelper)
              WebSocketHelper.broadcast_mcp_status({
                enabled: true,
                port: port,
                status: "running"
              })
            end

            # Run the server (this blocks the task)
            server.run
          rescue => e
            puts "[MCP] Server error: #{e.message}"
            Monadic::Utils::ExtraLogger.log { e.backtrace.join("\n") }
            @@server_running = false
          ensure
            @@server_running = false
            Monadic::Utils::ExtraLogger.log { "[MCP] Server stopped" }
          end
        end
      end
    end
  end
end
