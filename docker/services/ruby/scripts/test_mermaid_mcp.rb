#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# Test the Mermaid MCP adapter
def test_mcp_request(method, params = {})
  uri = URI.parse("http://localhost:3100/mcp")
  
  request = Net::HTTP::Post.new(uri)
  request.content_type = "application/json"
  
  payload = {
    jsonrpc: "2.0",
    id: rand(1000),
    method: method,
    params: params
  }
  
  request.body = payload.to_json
  
  begin
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 5) do |http|
      http.request(request)
    end
    
    puts "Request: #{method}"
    puts "Response: #{response.body}"
    puts "-" * 50
    
    JSON.parse(response.body)
  rescue => e
    puts "Error: #{e.message}"
    nil
  end
end

puts "Testing MCP Mermaid Adapter"
puts "=" * 50

# Initialize
test_mcp_request("initialize", { clientInfo: { name: "test-client" } })

# List tools
tools_response = test_mcp_request("tools/list")

if tools_response && tools_response["result"]
  tools = tools_response["result"]["tools"]
  mermaid_tools = tools.select { |t| t["name"].start_with?("mermaid_") }
  
  puts "Found #{mermaid_tools.length} Mermaid tools:"
  mermaid_tools.each do |tool|
    puts "  - #{tool['name']}: #{tool['description']}"
  end
  puts "-" * 50
  
  # Test validate syntax
  if mermaid_tools.any? { |t| t["name"] == "mermaid_validate_syntax" }
    puts "\nTesting mermaid_validate_syntax with valid diagram:"
    test_mcp_request("tools/call", {
      name: "mermaid_validate_syntax",
      arguments: {
        code: "graph TD\n    A[Start] --> B[Process]\n    B --> C[End]"
      }
    })
    
    puts "\nTesting mermaid_validate_syntax with invalid diagram:"
    test_mcp_request("tools/call", {
      name: "mermaid_validate_syntax",
      arguments: {
        code: "invalid mermaid code -->"
      }
    })
  end
  
  # Test analyze error
  if mermaid_tools.any? { |t| t["name"] == "mermaid_analyze_error" }
    puts "\nTesting mermaid_analyze_error:"
    test_mcp_request("tools/call", {
      name: "mermaid_analyze_error",
      arguments: {
        code: "sankey-beta\nJapan --> USA 100",
        error: "Parse error: Arrow notation not allowed in Sankey diagrams"
      }
    })
  end
end