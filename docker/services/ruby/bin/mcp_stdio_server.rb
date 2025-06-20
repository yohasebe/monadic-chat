#!/usr/bin/env ruby
# frozen_string_literal: true

# Stdio-based MCP server for direct Claude Desktop integration
# This runs as a subprocess and communicates via stdin/stdout

require 'json'
require 'bundler/setup'

# Set up paths
lib_path = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

# Load configuration
require 'dotenv'
config_path = File.expand_path("~/monadic/config/env")
Dotenv.load(config_path) if File.exist?(config_path)

# Initialize CONFIG
CONFIG = {}
ENV.each { |k, v| CONFIG[k] = v }

# Load dependencies
require_relative '../lib/monadic/mcp/adapters/help_adapter'
require_relative '../lib/monadic/utils/help_embeddings'

class MCPStdioServer
  def initialize
    @adapter = Monadic::MCP::Adapters::HelpAdapter.new
    STDERR.puts "MCP Stdio Server initialized" if ENV['MCP_DEBUG'] == 'true'
  end

  def run
    loop do
      begin
        # Read JSON-RPC request from stdin
        line = STDIN.gets
        break unless line
        
        # Skip empty lines
        next if line.strip.empty?
        
        request = JSON.parse(line.strip)
        debug_log("Received: #{request}")
        
        # Process request
        response = process_request(request)
        
        # Send response to stdout if not nil
        if response
          STDOUT.puts(response.to_json)
          STDOUT.flush
        end
        
      rescue JSON::ParserError => e
        error_response = {
          jsonrpc: "2.0",
          id: nil,
          error: {
            code: -32700,
            message: "Parse error",
            data: e.message
          }
        }
        STDOUT.puts(error_response.to_json)
        STDOUT.flush
      rescue => e
        debug_log("Error: #{e.message}")
        debug_log(e.backtrace.join("\n"))
        
        error_response = {
          jsonrpc: "2.0", 
          id: nil,
          error: {
            code: -32603,
            message: "Internal error",
            data: e.message
          }
        }
        STDOUT.puts(error_response.to_json)
        STDOUT.flush
      end
    end
  end

  private

  def process_request(request)
    method = request['method']
    params = request['params'] || {}
    id = request['id']
    
    # Handle notifications (no response needed)
    if method.start_with?('notifications/')
      debug_log("Notification received: #{method}")
      return nil
    end
    
    case method
    when 'initialize'
      {
        jsonrpc: "2.0",
        id: id,
        result: {
          protocolVersion: "2024-11-05",
          serverInfo: {
            name: "monadic-chat-mcp-stdio",
            version: "0.1.0"
          },
          capabilities: {
            tools: {},
            resources: {},
            prompts: {}
          }
        }
      }
    when 'tools/list'
      {
        jsonrpc: "2.0",
        id: id,
        result: {
          tools: @adapter.list_tools
        }
      }
    when 'tools/call'
      tool_name = params['name']
      arguments = params['arguments'] || {}
      
      if @adapter.handles_tool?(tool_name)
        result = @adapter.execute_tool(tool_name, arguments)
        {
          jsonrpc: "2.0",
          id: id,
          result: result
        }
      else
        {
          jsonrpc: "2.0",
          id: id,
          error: {
            code: -32601,
            message: "Tool not found: #{tool_name}"
          }
        }
      end
    when 'resources/list'
      {
        jsonrpc: "2.0",
        id: id,
        result: {
          resources: []
        }
      }
    when 'prompts/list'
      {
        jsonrpc: "2.0",
        id: id,
        result: {
          prompts: []
        }
      }
    else
      {
        jsonrpc: "2.0",
        id: id,
        error: {
          code: -32601,
          message: "Method not found: #{method}"
        }
      }
    end
  end
  
  def debug_log(message)
    STDERR.puts("[MCP Debug] #{message}") if ENV['MCP_DEBUG'] == 'true'
  end
end

# Run the server
if __FILE__ == $0
  server = MCPStdioServer.new
  server.run
end