#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# Test script for MCP server app integration
class MCPAppTester
  def initialize(base_url = 'http://localhost:3100/mcp')
    @base_url = base_url
    @id = 0
  end

  def next_id
    @id += 1
  end

  def make_request(method, params = {})
    uri = URI(@base_url)
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = {
      jsonrpc: "2.0",
      id: next_id,
      method: method,
      params: params
    }.to_json
    
    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    puts "Error: #{e.message}"
    nil
  end

  def run_tests
    puts "Testing MCP Server App Integration"
    puts "=" * 50
    
    # 1. Initialize
    puts "\n1. Initializing MCP session..."
    result = make_request("initialize")
    if result && result['result']
      puts "✓ Initialized successfully"
      puts "  Server name: #{result['result']['serverInfo']['name']}"
      puts "  Version: #{result['result']['serverInfo']['version']}"
    else
      puts "✗ Failed to initialize"
      return
    end
    
    # 2. List tools
    puts "\n2. Listing available tools..."
    result = make_request("tools/list")
    if result && result['result']
      tools = result['result']['tools']
      puts "✓ Found #{tools.length} tools"
      
      # Group tools by app
      app_tools = {}
      tools.each do |tool|
        if tool['name'].include?('__')
          app_name = tool['name'].split('__').first
          app_tools[app_name] ||= []
          app_tools[app_name] << tool
        end
      end
      
      # Display tools by app
      if app_tools.empty?
        puts "  No tools found. Make sure apps with tools are loaded."
      else
        app_tools.sort.each do |app, app_tool_list|
          puts "\n  App: #{app}"
          app_tool_list.each do |tool|
            tool_name = tool['name'].split('__', 2).last
            puts "    - #{tool_name}"
            puts "      #{tool['description']}"
          end
        end
      end
    else
      puts "✗ Failed to list tools"
      return
    end
    
    # 3. Test a specific tool if available
    puts "\n3. Testing tool execution..."
    
    # Try to find a simple tool to test (e.g., current_time)
    if tools.any? { |t| t['name'].include?('current_time') }
      tool_name = tools.find { |t| t['name'].include?('current_time') }['name']
      puts "  Testing tool: #{tool_name}"
      
      result = make_request("tools/call", {
        name: tool_name,
        arguments: {}
      })
      
      if result && result['result']
        puts "✓ Tool executed successfully"
        content = result['result']['content']
        if content && content.is_a?(Array)
          content.each do |item|
            puts "  Result: #{item['text']}" if item['type'] == 'text'
          end
        end
      else
        puts "✗ Failed to execute tool"
        puts "  Error: #{result['error']}" if result && result['error']
      end
    else
      puts "  No simple test tool found"
    end
    
    puts "\n" + "=" * 50
    puts "Test completed"
  end
end

# Run tests if executed directly
if __FILE__ == $0
  tester = MCPAppTester.new
  tester.run_tests
end