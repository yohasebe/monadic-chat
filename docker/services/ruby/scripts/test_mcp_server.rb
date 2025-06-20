#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# Test MCP server functionality
class MCPServerTester
  def initialize(port = 3100)
    @base_url = "http://localhost:#{port}/mcp"
  end

  def test_initialize
    puts "Testing initialize..."
    request = {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        clientInfo: {
          name: "test-client",
          version: "1.0.0"
        }
      }
    }
    
    response = send_request(request)
    puts "Response: #{JSON.pretty_generate(response)}"
    puts "✅ Initialize test passed" if response["result"]
    puts
  end

  def test_tools_list
    puts "Testing tools/list..."
    request = {
      jsonrpc: "2.0",
      id: 2,
      method: "tools/list",
      params: {}
    }
    
    response = send_request(request)
    puts "Response: #{JSON.pretty_generate(response)}"
    puts "✅ Tools list test passed - found #{response.dig("result", "tools")&.length || 0} tools" if response["result"]
    puts
  end

  def test_help_search
    puts "Testing monadic_help.search..."
    request = {
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: {
        name: "monadic_help.search",
        arguments: {
          query: "how to use Monadic Chat"
        }
      }
    }
    
    response = send_request(request)
    puts "Response: #{JSON.pretty_generate(response)}"
    puts "✅ Help search test passed" if response["result"]
    puts
  end

  private

  def send_request(body)
    uri = URI(@base_url)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request.body = body.to_json
    
    begin
      response = http.request(request)
      JSON.parse(response.body)
    rescue => e
      { error: e.message }
    end
  end
end

# Run tests
if __FILE__ == $0
  puts "MCP Server Test Script"
  puts "====================="
  puts
  
  tester = MCPServerTester.new
  tester.test_initialize
  tester.test_tools_list
  tester.test_help_search
  
  puts "All tests completed!"
end