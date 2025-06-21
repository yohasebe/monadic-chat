#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# Example MCP client for Monadic Chat
# Demonstrates standard JSON-RPC 2.0 communication with the MCP server
class MCPClient
  def initialize(base_url = "http://localhost:3100/mcp")
    @base_url = base_url
    @request_id = 0
  end

  # Send a JSON-RPC 2.0 request
  def call_method(method, params = {})
    @request_id += 1
    
    uri = URI.parse(@base_url)
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    
    body = {
      "jsonrpc" => "2.0",
      "id" => @request_id,
      "method" => method,
      "params" => params
    }
    
    request.body = body.to_json
    
    response = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 120) do |http|
      http.request(request)
    end
    
    JSON.parse(response.body)
  end

  # Initialize MCP session
  def initialize_session
    call_method("initialize", {
      "clientInfo" => {
        "name" => "mcp-client-example",
        "version" => "1.0.0"
      }
    })
  end

  # List all available tools
  def list_tools
    call_method("tools/list")
  end

  # Call a specific tool
  def call_tool(tool_name, arguments = {})
    call_method("tools/call", {
      "name" => tool_name,
      "arguments" => arguments
    })
  end
end

# Example usage
if __FILE__ == $0
  client = MCPClient.new
  
  puts "=== MCP Client Example ==="
  puts "Connecting to Monadic Chat MCP server..."
  
  # Initialize session
  init_result = client.initialize_session
  if init_result['error']
    puts "Error: #{init_result['error']['message']}"
    exit 1
  end
  
  server_info = init_result['result']['serverInfo']
  puts "Connected to: #{server_info['name']} v#{server_info['version']}"
  puts "Protocol version: #{init_result['result']['protocolVersion']}"
  
  # List available tools
  puts "\nFetching available tools..."
  tools_result = client.list_tools
  
  if tools_result['error']
    puts "Error: #{tools_result['error']['message']}"
    exit 1
  end
  
  tools = tools_result['result']['tools']
  puts "Found #{tools.length} tools"
  
  # Display some example tools
  puts "\nExample tools:"
  tools.first(5).each do |tool|
    puts "- #{tool['name']}"
    puts "  #{tool['description'][0..80]}..."
  end
  
  # Example: Call a tool
  if ARGV[0]
    query = ARGV.join(" ")
    puts "\n=== Example Tool Call ==="
    puts "Searching Monadic Help for: #{query}"
    
    # Find help tool
    help_tool = tools.find { |t| t['name'].include?('find_help_topics') }
    if help_tool
      result = client.call_tool(help_tool['name'], { "text" => query })
      
      if result['error']
        puts "Error: #{result['error']['message']}"
        puts "Details: #{result['error']['data']}" if result['error']['data']
      elsif result['result'] && result['result']['content']
        content = result['result']['content'][0]['text']
        puts "\nResults:"
        puts content
      end
    else
      puts "Help tool not found"
    end
  else
    puts "\nUsage: #{$0} <search query>"
    puts "Example: #{$0} voice chat"
  end
end