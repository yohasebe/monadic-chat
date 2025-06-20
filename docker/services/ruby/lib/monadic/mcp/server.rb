# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require 'securerandom'
require 'time'
require 'thin'
require 'eventmachine'

begin
  require_relative '../utils/debug_helper'
rescue LoadError
  # Fallback if DebugHelper is not available
  module DebugHelper
    def debug_log(message)
      puts "[MCP Debug] #{message}" if CONFIG["EXTRA_LOGGING"] == "true"
    end
  end
end

module Monadic
  module MCP
    class Server < Sinatra::Base
      include DebugHelper

      set :port, (CONFIG["MCP_SERVER_PORT"] || 3100).to_i
      set :bind, '127.0.0.1'  # localhost only for security
      set :server, 'thin'
      set :logging, true
      set :sessions, true
      set :show_exceptions, false

      # JSON-RPC version constant
      JSONRPC_VERSION = "2.0"

      # MCP protocol version
      MCP_PROTOCOL_VERSION = "2024-11-05"

      # Store active SSE connections
      @@connections = {}
      @@session_data = {}

      # CORS settings for local access only
      before do
        headers['Access-Control-Allow-Origin'] = 'http://localhost:*'
        headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        headers['Access-Control-Allow-Headers'] = 'Content-Type, Accept, Mcp-Session-Id, Last-Event-ID'
        
        # Handle preflight requests
        if request.request_method == 'OPTIONS'
          halt 200
        end
      end

      # Error classes
      class MCPError < StandardError
        attr_reader :code, :data

        def initialize(message, code = -32603, data = nil)
          super(message)
          @code = code
          @data = data
        end
      end

      # JSON-RPC error codes
      PARSE_ERROR = -32700
      INVALID_REQUEST = -32600
      METHOD_NOT_FOUND = -32601
      INVALID_PARAMS = -32602
      INTERNAL_ERROR = -32603

      # Health check endpoint
      get '/health' do
        content_type :json
        {
          status: 'ok',
          version: MCP_PROTOCOL_VERSION,
          timestamp: Time.now.iso8601,
          adapters: @adapters.keys
        }.to_json
      end

      # Main MCP endpoint
      post '/mcp' do
        begin
          content_type :json
          
          # Get session ID if provided
          session_id = request.env['HTTP_MCP_SESSION_ID']
          
          # Parse JSON-RPC request
          begin
            request_data = JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            return json_rpc_error(nil, "Parse error", PARSE_ERROR, e.message)
          end

          # Handle batch requests
          if request_data.is_a?(Array)
            responses = request_data.map { |req| process_request(req, session_id) }.compact
            responses.to_json
          else
            response = process_request(request_data, session_id)
            response ? response.to_json : ""
          end
        rescue MCPError => e
          json_rpc_error(nil, e.message, e.code, e.data)
        rescue => e
          puts "MCP Server Error: #{e.message}" if CONFIG["EXTRA_LOGGING"] == "true"
          puts e.backtrace.join("\n") if CONFIG["EXTRA_LOGGING"] == "true"
          json_rpc_error(nil, "Internal error", INTERNAL_ERROR, e.message)
        end
      end

      # SSE endpoint for server-to-client communication
      get '/mcp' do
        content_type 'text/event-stream'
        
        # Check Accept header
        unless request.accept?('text/event-stream')
          halt 405, "Method Not Allowed"
        end

        session_id = request.env['HTTP_MCP_SESSION_ID'] || SecureRandom.uuid
        last_event_id = request.env['HTTP_LAST_EVENT_ID']
        
        stream :keep_open do |out|
          @@connections[session_id] = out
          
          # Send initial connection event
          send_sse_event(out, {
            jsonrpc: JSONRPC_VERSION,
            method: "connection/established",
            params: {
              protocolVersion: MCP_PROTOCOL_VERSION,
              sessionId: session_id
            }
          }, "connection")

          # Replay missed events if Last-Event-ID is provided
          if last_event_id && @@session_data[session_id]
            replay_events(out, session_id, last_event_id)
          end

          # Keep connection alive
          out.callback { @@connections.delete(session_id) }
          out.errback { @@connections.delete(session_id) }
        end
      end

      private

      def process_request(request, session_id)
        # Validate JSON-RPC request
        unless request.is_a?(Hash) && request['jsonrpc'] == JSONRPC_VERSION
          return json_rpc_error(request['id'], "Invalid Request", INVALID_REQUEST)
        end

        method = request['method']
        params = request['params'] || {}
        id = request['id']

        # Notifications don't have an id and don't require a response
        if method.start_with?('notifications/')
          puts "Received notification: #{method}" if CONFIG["EXTRA_LOGGING"] == "true"
          return nil
        end

        # Route to appropriate handler
        case method
        when 'initialize'
          handle_initialize(params, id, session_id)
        when 'tools/list'
          handle_tools_list(params, id, session_id)
        when 'tools/call'
          handle_tool_call(params, id, session_id)
        when 'resources/list'
          handle_resources_list(params, id, session_id)
        when 'prompts/list'
          handle_prompts_list(params, id, session_id)
        else
          json_rpc_error(id, "Method not found", METHOD_NOT_FOUND)
        end
      end

      def handle_initialize(params, id, session_id)
        # Initialize session
        @@session_data[session_id] = {
          client_info: params['clientInfo'],
          initialized_at: Time.now.iso8601
        }

        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: {
            protocolVersion: MCP_PROTOCOL_VERSION,
            serverInfo: {
              name: "monadic-chat-mcp",
              version: "0.1.0"
            },
            capabilities: {
              tools: {},
              resources: {},
              prompts: {}
            }
          }
        }
      end

      def handle_tools_list(_params, id, _session_id)
        # Get enabled adapters
        adapters = load_enabled_adapters
        
        tools = adapters.flat_map(&:list_tools)

        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: {
            tools: tools
          }
        }
      end

      def handle_tool_call(params, id, session_id)
        tool_name = params['name']
        arguments = params['arguments'] || {}

        # Find the appropriate adapter
        adapter = find_adapter_for_tool(tool_name)
        
        unless adapter
          return json_rpc_error(id, "Tool not found: #{tool_name}", METHOD_NOT_FOUND)
        end

        # Execute the tool
        result = adapter.execute_tool(tool_name, arguments)

        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: result
        }
      end

      def handle_resources_list(_params, id, _session_id)
        # Return empty resources list for now
        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: {
            resources: []
          }
        }
      end

      def handle_prompts_list(_params, id, _session_id)
        # Return empty prompts list for now
        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: {
            prompts: []
          }
        }
      end

      def load_enabled_adapters
        enabled_apps = (CONFIG["MCP_ENABLED_APPS"] || "help").split(",").map(&:strip)
        
        adapters = []
        enabled_apps.each do |app|
          begin
            require_relative "adapters/#{app}_adapter"
            adapter_class = Object.const_get("Monadic::MCP::Adapters::#{app.capitalize}Adapter")
            adapters << adapter_class.new
          rescue LoadError => e
            puts "Failed to load MCP adapter for #{app}: #{e.message}"
            puts "Current directory: #{Dir.pwd}"
            puts "File exists?: #{File.exist?(File.join(__dir__, "adapters", "#{app}_adapter.rb"))}"
          rescue NameError => e
            puts "Failed to instantiate MCP adapter for #{app}: #{e.message}"
          rescue => e
            puts "Unexpected error loading MCP adapter for #{app}: #{e.class} - #{e.message}"
            puts e.backtrace.first(5).join("\n")
          end
        end
        
        adapters
      end

      def find_adapter_for_tool(tool_name)
        adapters = load_enabled_adapters
        adapters.find { |adapter| adapter.handles_tool?(tool_name) }
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

      def send_sse_event(out, data, event_type = "message", id = nil)
        id ||= SecureRandom.uuid
        
        out << "id: #{id}\n"
        out << "event: #{event_type}\n"
        out << "data: #{data.to_json}\n\n"
        out.flush
      rescue => e
        debug_log "SSE send error: #{e.message}"
      end

      def replay_events(out, session_id, last_event_id)
        # Implementation for replaying missed events
        # This would require storing events with IDs
      end

      # Class method to broadcast messages to connected clients
      def self.broadcast(method, params = {})
        message = {
          jsonrpc: JSONRPC_VERSION,
          method: method,
          params: params
        }
        
        @@connections.each do |session_id, out|
          begin
            out << "event: notification\n"
            out << "data: #{message.to_json}\n\n"
            out.flush
          rescue => e
            @@connections.delete(session_id)
          end
        end
      end

      # Start the MCP server
      def self.start!
        return unless CONFIG["MCP_SERVER_ENABLED"] == true || CONFIG["MCP_SERVER_ENABLED"] == "true"
        
        port = (CONFIG["MCP_SERVER_PORT"] || 3100).to_i
        
        # Check if port is already in use
        begin
          require 'socket'
          server = TCPServer.new('127.0.0.1', port)
          server.close
        rescue Errno::EADDRINUSE
          puts "MCP Server port #{port} is already in use. Skipping MCP server startup."
          return
        rescue => e
          puts "Error checking port availability: #{e.message}"
        end
        
        # Check if EventMachine is already running
        if EM.reactor_running?
          # If reactor is already running, start server in the existing reactor
          begin
            # Configure Thin server
            thin_server = Thin::Server.new('127.0.0.1', port, self, signals: false)
            thin_server.silent = true unless CONFIG["EXTRA_LOGGING"] == "true"
            
            # Start the server without blocking
            thin_server.start!
            puts "MCP Server started on port #{port} (using existing EventMachine reactor)"
            
            # Notify via WebSocket if available
            if defined?(WebSocketHelper)
              EM.next_tick do
                WebSocketHelper.broadcast_mcp_status({
                  enabled: true,
                  port: port,
                  apps: (CONFIG["MCP_ENABLED_APPS"] || "help").split(",").map(&:strip),
                  status: "running"
                })
              end
            end
          rescue => e
            puts "MCP Server failed to start: #{e.message}"
            puts e.backtrace.join("\n") if CONFIG["EXTRA_LOGGING"] == "true"
          end
        else
          # If no reactor is running, create one in a separate thread
          Thread.new do
            begin
              EM.run do
                # Configure Thin server
                thin_server = Thin::Server.new('127.0.0.1', port, self, signals: false)
                thin_server.silent = true unless CONFIG["EXTRA_LOGGING"] == "true"
                
                # Start the server
                thin_server.start
                puts "MCP Server running on port #{port} (new EventMachine reactor)"
              end
            rescue => e
              puts "MCP Server failed to start: #{e.message}"
              puts e.backtrace.join("\n") if CONFIG["EXTRA_LOGGING"] == "true"
            end
          end
          
          # Give the server time to start
          sleep 1
          
          # Check if server is running
          begin
            require 'net/http'
            uri = URI("http://localhost:#{port}/mcp")
            Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
              http.head(uri.path)
            end
            puts "MCP Server successfully verified on port #{port}"
          rescue => e
            puts "MCP Server verification failed: #{e.message}"
          end
          
          # Notify via WebSocket if available
          if defined?(WebSocketHelper)
            Thread.new do
              sleep 1 # Wait for server to start
              WebSocketHelper.broadcast_mcp_status({
                enabled: true,
                port: port,
                apps: (CONFIG["MCP_ENABLED_APPS"] || "help").split(",").map(&:strip),
                status: "running"
              })
            end
          end
        end
      end
      
      # Get server status
      def self.status
        {
          enabled: CONFIG["MCP_SERVER_ENABLED"] == true || CONFIG["MCP_SERVER_ENABLED"] == "true",
          port: (CONFIG["MCP_SERVER_PORT"] || 3100).to_i,
          apps: (CONFIG["MCP_ENABLED_APPS"] || "help").split(",").map(&:strip),
          running: @@connections.any?
        }
      end
    end
  end
end