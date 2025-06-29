# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require 'securerandom'
require 'time'
require 'eventmachine'
require 'thin'
require_relative '../utils/debug_helper'
require_relative 'cache_invalidator'

module Monadic
  module MCP
    class Server < Sinatra::Base
      include DebugHelper

      # Configuration
      set :server, 'thin'
      set :port, (CONFIG["MCP_SERVER_PORT"] || 3100).to_i
      set :bind, '127.0.0.1'
      set :public_folder, false
      set :logging, CONFIG["EXTRA_LOGGING"] == "true"
      set :dump_errors, true
      set :show_exceptions, false
      set :raise_errors, false

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
      
      # Tool cache
      @@tools_cache = nil
      @@tools_cache_time = nil
      CACHE_TTL = 300 # 5 minutes

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
          debug_log "MCP Server error: #{e.message}"
          debug_log e.backtrace.join("\n")
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
        when 'resources/list'
          handle_resources_list(id, params)
        when 'resources/read'
          handle_resource_read(id, params)
        when 'prompts/list'
          handle_prompts_list(id, params)
        when 'prompts/get'
          handle_prompt_get(id, params)
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
            tools: {},
            resources: {},
            prompts: {}
          }
        }
        
        json_rpc_response(id, result)
      end

      def handle_tools_list(id, params)
        # Use cached tools if available and not expired
        tools = get_cached_tools
        
        unless tools
          # Build tools list
          tools = []
          
          discover_apps.each do |app_name, app_info|
            next unless app_info[:tools]
            
            app_info[:tools].each do |tool|
              formatted_tool = format_tool_for_mcp(app_name, tool, app_info[:display_name])
              tools << formatted_tool if formatted_tool
            end
          end
          
          # Cache the tools
          cache_tools(tools)
          
          debug_log "MCP: Built and cached #{tools.length} tools"
        else
          debug_log "MCP: Using cached tools (#{tools.length} tools)"
        end
        
        json_rpc_response(id, { tools: tools })
      end

      def handle_tool_call(id, params)
        tool_name = params['name']
        arguments = params['arguments'] || {}
        
        unless tool_name
          return json_rpc_error(id, "Missing tool name", INVALID_PARAMS)
        end
        
        # Parse tool name to get app and tool names
        parts = tool_name.split('__', 2)
        if parts.length != 2
          return json_rpc_error(id, "Invalid tool name format", INVALID_PARAMS)
        end
        
        app_name = parts[0]
        actual_tool_name = parts[1]
        
        # Direct lookup from APPS instead of calling discover_apps
        app_instance = ::APPS[app_name] if defined?(::APPS)
        unless app_instance && app_instance.respond_to?(:settings) && !app_instance.settings['disabled']
          return json_rpc_error(id, "App not found or disabled: #{app_name}", INVALID_PARAMS)
        end
        
        # Execute tool
        begin
          result = execute_app_tool(app_instance, actual_tool_name, arguments)
          json_rpc_response(id, result)
        rescue => e
          debug_log "Error executing tool #{tool_name}: #{e.message}"
          json_rpc_error(id, "Tool execution failed", INTERNAL_ERROR, e.message)
        end
      end

      def handle_resources_list(id, params)
        # Resources could be files, databases, etc.
        # For now, return empty array
        json_rpc_response(id, { resources: [] })
      end

      def handle_resource_read(id, params)
        json_rpc_error(id, "No resources available", INVALID_PARAMS)
      end

      def handle_prompts_list(id, params)
        # Prompts could be pre-defined templates
        # For now, return empty array
        json_rpc_response(id, { prompts: [] })
      end

      def handle_prompt_get(id, params)
        json_rpc_error(id, "No prompts available", INVALID_PARAMS)
      end

      def discover_apps
        apps = {}
        
        return apps unless defined?(::APPS) && ::APPS.is_a?(Hash)
        
        ::APPS.each do |app_name, app_instance|
          next unless app_instance.respond_to?(:settings)
          
          settings = app_instance.settings
          next if settings['disabled']
          
          # Get tools from settings
          tools = settings['tools']
          next unless tools
          
          # Handle different tool formats
          tool_list = case tools
                     when Hash
                       # Gemini format with function_declarations
                       tools['function_declarations'] || []
                     when Array
                       # Standard format
                       tools
                     else
                       []
                     end
          
          next if tool_list.empty?
          
          apps[app_name] = {
            instance: app_instance,
            display_name: settings['display_name'] || app_name,
            tools: tool_list
          }
          
          debug_log "MCP: Found #{tool_list.length} tools in app #{app_name}"
        end
        
        apps
      end

      def format_tool_for_mcp(app_name, tool, display_name)
        # Convert tool format based on provider
        if tool.is_a?(Hash) && tool['function']
          # OpenAI/Mistral/Perplexity format
          tool_def = tool['function']
          {
            name: "#{app_name}__#{tool_def['name']}",
            description: "#{display_name}: #{tool_def['description']}",
            inputSchema: tool_def['parameters'] || { type: "object", properties: {} }
          }
        elsif tool.is_a?(Hash) && tool['name']
          # Claude/Gemini format
          {
            name: "#{app_name}__#{tool['name']}",
            description: "#{display_name}: #{tool['description']}",
            inputSchema: tool['input_schema'] || tool['parameters'] || { type: "object", properties: {} }
          }
        else
          nil
        end
      end

      def execute_app_tool(app_instance, tool_name, arguments)
        # Convert arguments to symbol keys for Ruby method calls
        ruby_args = arguments.transform_keys(&:to_sym)
        
        # Check if the app instance responds to the tool method
        unless app_instance.respond_to?(tool_name.to_sym)
          raise "Tool method not found: #{tool_name}"
        end
        
        # Execute the tool with better error handling
        begin
          result = if ruby_args.empty?
                    app_instance.send(tool_name.to_sym)
                  else
                    app_instance.send(tool_name.to_sym, **ruby_args)
                  end
          
          # Format the result for MCP
          format_tool_result(result)
        rescue ArgumentError => e
          # Provide helpful error message for parameter issues
          method = app_instance.method(tool_name.to_sym)
          params = method.parameters
          required_params = params.select { |type, _| type == :keyreq }.map(&:last)
          optional_params = params.select { |type, _| type == :key }.map(&:last)
          
          error_msg = "Parameter error: #{e.message}\n"
          error_msg += "Required parameters: #{required_params.join(', ')}\n"
          error_msg += "Optional parameters: #{optional_params.join(', ')}\n"
          error_msg += "Provided parameters: #{ruby_args.keys.join(', ')}"
          
          raise error_msg
        end
      end

      def format_tool_result(result)
        case result
        when String
          {
            content: [
              {
                type: "text",
                text: result
              }
            ]
          }
        when Hash
          if result[:error]
            raise result[:error]
          elsif result[:content]
            # Already formatted
            result
          else
            # Convert hash to formatted text
            {
              content: [
                {
                  type: "text",
                  text: format_hash_result(result)
                }
              ]
            }
          end
        when Array
          {
            content: [
              {
                type: "text",
                text: format_array_result(result)
              }
            ]
          }
        else
          {
            content: [
              {
                type: "text",
                text: result.to_s
              }
            ]
          }
        end
      end

      def format_hash_result(hash)
        # Format hash results nicely
        if hash[:success] == false && hash[:error]
          "Error: #{hash[:error]}"
        elsif hash[:filename] && hash[:url]
          "Generated file: #{hash[:filename]}\nURL: #{hash[:url]}"
        else
          # Generic hash formatting
          hash.map { |k, v| "#{k}: #{v}" }.join("\n")
        end
      end

      def format_array_result(array)
        if array.all? { |item| item.is_a?(Hash) && item[:title] }
          # Format as a list of items with titles
          array.map { |item| "• #{item[:title]}" }.join("\n")
        else
          # Generic array formatting
          array.map { |item| "• #{item}" }.join("\n")
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

      # Cache management methods
      def get_cached_tools
        return nil unless @@tools_cache && @@tools_cache_time
        
        # Check if cache is still valid
        if Time.now - @@tools_cache_time < CACHE_TTL
          @@tools_cache
        else
          # Cache expired
          @@tools_cache = nil
          @@tools_cache_time = nil
          nil
        end
      end

      def cache_tools(tools)
        @@tools_cache = tools
        @@tools_cache_time = Time.now
      end

      # Clear cache when apps might have changed
      def self.clear_cache
        @@tools_cache = nil
        @@tools_cache_time = nil
      end

      # Get server status
      def self.status
        {
          enabled: CONFIG["MCP_SERVER_ENABLED"] == true || CONFIG["MCP_SERVER_ENABLED"] == "true",
          port: (CONFIG["MCP_SERVER_PORT"] || 3100).to_i,
          running: defined?(@@server_running) && @@server_running
        }
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
            @@server_running = true
            puts "MCP Server started on port #{port} (using existing EventMachine reactor)"
            
            # Notify via WebSocket if available
            if defined?(WebSocketHelper)
              EM.next_tick do
                WebSocketHelper.broadcast_mcp_status({
                  enabled: true,
                  port: port,
                  status: "running"
                })
              end
            end
          rescue => e
            puts "Failed to start MCP server in existing reactor: #{e.message}"
            puts e.backtrace.join("\n") if CONFIG["EXTRA_LOGGING"] == "true"
          end
        else
          # Start EventMachine and the server
          Thread.new do
            begin
              EM.run do
                thin_server = Thin::Server.new('127.0.0.1', port, self, signals: false)
                thin_server.silent = true unless CONFIG["EXTRA_LOGGING"] == "true"
                thin_server.start!
                @@server_running = true
                puts "MCP Server started on port #{port} (new EventMachine reactor)"
                
                # Notify via WebSocket if available
                if defined?(WebSocketHelper)
                  EM.next_tick do
                    WebSocketHelper.broadcast_mcp_status({
                      enabled: true,
                      port: port,
                      status: "running"
                    })
                  end
                end
              end
            rescue => e
              puts "Failed to start MCP server: #{e.message}"
              puts e.backtrace.join("\n") if CONFIG["EXTRA_LOGGING"] == "true"
            end
          end
        end
      end
    end
  end
end