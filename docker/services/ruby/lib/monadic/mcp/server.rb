# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require 'securerandom'
require 'time'
require 'digest'
require_relative '../utils/debug_helper'

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
      MCP_PROTOCOL_VERSION = "2024-11-05"

      # JSON-RPC error codes
      PARSE_ERROR = -32700
      INVALID_REQUEST = -32600
      METHOD_NOT_FOUND = -32601
      INVALID_PARAMS = -32602
      INTERNAL_ERROR = -32603

      # Connection tracking for SSE
      @@connections = {}
      
      # Server status
      @@server_running = false
      
      # Tool name mapping (shortened -> original)
      @@tool_name_map = {}

      # CORS headers
      before do
        headers['Access-Control-Allow-Origin'] = '*'
        headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        headers['Access-Control-Allow-Headers'] = 'Content-Type, Accept, MCP-Session-ID'
        
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
          timestamp: Time.now.iso8601,
          apps: discover_apps.keys
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
          puts "MCP Server error: #{e.message}" if CONFIG["EXTRA_LOGGING"] == "true"
          puts e.backtrace.join("\n") if CONFIG["EXTRA_LOGGING"] == "true"
          json_rpc_error(nil, "Internal error", INTERNAL_ERROR, e.message)
        end
      end

      # SSE endpoint for server-sent events
      get '/mcp' do
        content_type 'text/event-stream'
        cache_control :no_cache
        
        session_id = SecureRandom.uuid
        last_event_id = request.env['HTTP_LAST_EVENT_ID']
        
        stream(:keep_open) do |out|
          @@connections[session_id] = out
          
          # Send initial connection event
          send_sse_event(out, { connected: true, sessionId: session_id }, "connection")
          
          # Replay missed events if requested
          replay_events(out, session_id, last_event_id) if last_event_id
          
          # Keep connection alive
          EM.add_periodic_timer(30) do
            send_sse_event(out, { type: "ping" }, "ping")
          end
          
          # Handle client disconnect
          out.callback { @@connections.delete(session_id) }
          out.errback { @@connections.delete(session_id) }
        end
      end

      private

      def handle_single_request(request)
        # Validate request
        unless request.is_a?(Hash) && request['jsonrpc'] == JSONRPC_VERSION
          return json_rpc_error(request['id'], "Invalid Request", INVALID_REQUEST)
        end

        method = request['method']
        params = request['params'] || {}
        id = request['id']

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
            name: "monadic-chat-mcp",
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
        tools = []
        
        # Clear the tool name mapping for fresh start
        @@tool_name_map.clear
        
        discover_apps.each do |app_name, app_info|
          next unless app_info[:tools]
          
          app_info[:tools].each do |tool|
            formatted_tool = format_tool_for_mcp(app_name, tool, app_info[:display_name])
            tools << formatted_tool if formatted_tool
          end
        end
        
        # Debug logging - show all tools with their indices and name lengths
        puts "\n=== MCP Tools Debug Information ===" if CONFIG["EXTRA_LOGGING"] == "true"
        puts "Total tools: #{tools.length}" if CONFIG["EXTRA_LOGGING"] == "true"
        tools.each_with_index do |tool, idx|
          puts "Tool #{idx}: #{tool[:name]} (length: #{tool[:name].length})" if CONFIG["EXTRA_LOGGING"] == "true"
        end
        
        # Check for any tools with names longer than 64 characters
        long_tools = tools.select { |t| t[:name].length > 64 }
        if long_tools.any?
          puts "\n=== WARNING: Tools with names > 64 characters ===" if CONFIG["EXTRA_LOGGING"] == "true"
          long_tools.each_with_index do |tool, idx|
            tool_idx = tools.index(tool)
            puts "Tool #{tool_idx}: #{tool[:name]} (length: #{tool[:name].length})" if CONFIG["EXTRA_LOGGING"] == "true"
          end
        else
          puts "\n=== All tool names are 64 characters or less ===" if CONFIG["EXTRA_LOGGING"] == "true"
        end
        
        # Check specifically for tool 22 (0-based indexing)
        if tools.length > 22
          tool_22 = tools[22]
          puts "\n=== Tool 22 Details (0-based index) ===" if CONFIG["EXTRA_LOGGING"] == "true"
          puts "Name: #{tool_22[:name]}" if CONFIG["EXTRA_LOGGING"] == "true"
          puts "Length: #{tool_22[:name].length}" if CONFIG["EXTRA_LOGGING"] == "true"
          puts "Description: #{tool_22[:description]}" if CONFIG["EXTRA_LOGGING"] == "true"
        end
        
        # Also check tool 21 in case Claude Code uses 1-based indexing
        if tools.length > 21
          tool_21 = tools[21]
          puts "\n=== Tool 21 Details (in case of 1-based index) ===" if CONFIG["EXTRA_LOGGING"] == "true"
          puts "Name: #{tool_21[:name]}" if CONFIG["EXTRA_LOGGING"] == "true"
          puts "Length: #{tool_21[:name].length}" if CONFIG["EXTRA_LOGGING"] == "true"
        end
        
        puts "\nMCP: Found #{tools.length} tools across #{discover_apps.keys.length} apps" if CONFIG["EXTRA_LOGGING"] == "true"
        
        # Log the actual JSON response being sent
        response = { tools: tools }
        if CONFIG["EXTRA_LOGGING"] == "true"
          puts "\n=== JSON Response Preview ==="
          puts "First 3 tools in response:"
          response[:tools][0..2].each_with_index do |tool, idx|
            puts "#{idx}: #{tool[:name]} (#{tool[:name].length} chars)"
          end
          if response[:tools].length > 22
            puts "..."
            puts "Tool 21: #{response[:tools][21][:name]} (#{response[:tools][21][:name].length} chars)"
            puts "Tool 22: #{response[:tools][22][:name]} (#{response[:tools][22][:name].length} chars)"
            puts "Tool 23: #{response[:tools][23][:name]} (#{response[:tools][23][:name].length} chars)" if response[:tools].length > 23
          end
        end
        
        json_rpc_response(id, response)
      end

      def handle_tool_call(id, params)
        tool_name = params['name']
        arguments = params['arguments'] || {}
        
        unless tool_name
          return json_rpc_error(id, "Missing tool name", INVALID_PARAMS)
        end
        
        # Check if we have a mapping for this tool name
        if @@tool_name_map[tool_name]
          # Use the original names from the mapping
          app_name = @@tool_name_map[tool_name][:app_name]
          actual_tool_name = @@tool_name_map[tool_name][:tool_name]
        else
          # Fall back to parsing (for non-shortened names)
          parts = tool_name.split('__', 2)
          if parts.length != 2
            return json_rpc_error(id, "Invalid tool name format", INVALID_PARAMS)
          end
          
          app_name = parts[0]
          actual_tool_name = parts[1]
        end
        
        # Find app
        apps = discover_apps
        app_info = apps[app_name]
        unless app_info
          return json_rpc_error(id, "App not found: #{app_name}", INVALID_PARAMS)
        end
        
        # Execute tool
        begin
          result = execute_app_tool(app_info[:instance], actual_tool_name, arguments)
          json_rpc_response(id, result)
        rescue => e
          puts "Error executing tool #{tool_name}: #{e.message}" if CONFIG["EXTRA_LOGGING"] == "true"
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
          
          puts "MCP: Found #{tool_list.length} tools in app #{app_name}" if CONFIG["EXTRA_LOGGING"] == "true"
        end
        
        apps
      end

      def format_tool_for_mcp(app_name, tool, display_name)
        # Convert tool format based on provider
        if tool.is_a?(Hash) && tool['function']
          # OpenAI/Mistral/Perplexity format
          tool_def = tool['function']
          tool_name = create_short_tool_name(app_name, tool_def['name'])
          {
            name: tool_name,
            description: "#{display_name}: #{tool_def['description']}",
            inputSchema: tool_def['parameters'] || { type: "object", properties: {} }
          }
        elsif tool.is_a?(Hash) && tool['name']
          # Claude/Gemini format
          tool_name = create_short_tool_name(app_name, tool['name'])
          {
            name: tool_name,
            description: "#{display_name}: #{tool['description']}",
            inputSchema: tool['input_schema'] || tool['parameters'] || { type: "object", properties: {} }
          }
        else
          nil
        end
      end
      
      def create_short_tool_name(app_name, tool_name)
        # Create shortened version if name would be too long
        full_name = "#{app_name}__#{tool_name}"
        
        # Debug logging for long names
        if full_name.length > 64
          puts "WARNING: Tool name too long before shortening: #{full_name} (#{full_name.length} chars)" if CONFIG["EXTRA_LOGGING"] == "true"
        end
        
        # Be extremely aggressive with shortening to avoid Claude Code issues
        # Always shorten names longer than 30 characters
        if full_name.length <= 30
          @@tool_name_map[full_name] = { app_name: app_name, tool_name: tool_name }
          return full_name
        end
        
        # Generate a short unique identifier (4 chars)
        # Use a hash of the full name to ensure consistency across restarts
        unique_id = Digest::MD5.hexdigest(full_name)[0...4].upcase
        
        # Strategy: Use app initials + provider initial + unique ID
        providers = ['OpenAI', 'Claude', 'Gemini', 'Mistral', 'Cohere', 'Perplexity', 'DeepSeek', 'Grok', 'Ollama']
        provider = providers.find { |p| app_name.end_with?(p) }
        
        if provider
          base_app = app_name.gsub(/#{provider}$/, '')
          initials = base_app.scan(/[A-Z]/).join
          provider_initial = provider[0]
          
          # Create short app identifier with unique ID
          short_app = "#{initials}#{provider_initial}#{unique_id}"
        else
          # No provider suffix
          initials = app_name.scan(/[A-Z]/).join
          short_app = "#{initials}#{unique_id}"
        end
        
        # Build the shortened name
        shortened = "#{short_app}__#{tool_name}"
        
        # If still too long, truncate the tool name more aggressively
        if shortened.length > 40  # Use 40 as max to be extra safe
          max_tool_length = 40 - short_app.length - 2  # 2 for "__"
          shortened = "#{short_app}__#{tool_name[0...max_tool_length]}"
        end
        
        # Check for collisions (very unlikely with hash-based ID)
        counter = 0
        final_name = shortened
        while @@tool_name_map[final_name] && 
              (@@tool_name_map[final_name][:app_name] != app_name || 
               @@tool_name_map[final_name][:tool_name] != tool_name)
          counter += 1
          # Add counter to make it unique
          base_name = shortened[0...-1]  # Remove last char to make room
          final_name = "#{base_name}#{counter}"
        end
        
        # Store mapping
        @@tool_name_map[final_name] = { app_name: app_name, tool_name: tool_name }
        final_name
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
        response = {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: result
        }
        
        # Debug logging for tools/list responses
        if result.is_a?(Hash) && result[:tools] && CONFIG["EXTRA_LOGGING"] == "true"
          puts "\n=== Final JSON-RPC Response Debug ==="
          puts "Total tools in response: #{result[:tools].length}"
          
          # Check the actual JSON string for tool 22
          json_str = response.to_json
          if result[:tools].length > 22
            # Extract tool 22 from the JSON string
            tools_match = json_str.match(/"tools":\[(.*)\]/)
            if tools_match
              tools_json = "[#{tools_match[1]}]"
              begin
                parsed_tools = JSON.parse(tools_json)
                if parsed_tools.length > 22
                  tool_22_json = parsed_tools[22].to_json
                  puts "Tool 22 JSON: #{tool_22_json[0..200]}..." if tool_22_json.length > 200
                  puts "Tool 22 name from JSON: #{parsed_tools[22]['name']} (#{parsed_tools[22]['name'].length} chars)"
                end
              rescue => e
                puts "Error parsing tools JSON: #{e.message}"
              end
            end
          end
        end
        
        response.to_json
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
        puts "SSE send error: #{e.message}" if CONFIG["EXTRA_LOGGING"] == "true"
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