#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# Test the Syntax Tree MCP adapter
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

puts "Testing MCP Syntax Tree Adapter"
puts "=" * 50

# Initialize
test_mcp_request("initialize", { clientInfo: { name: "test-client" } })

# List tools
tools_response = test_mcp_request("tools/list")

if tools_response && tools_response["result"]
  tools = tools_response["result"]["tools"]
  syntax_tools = tools.select { |t| t["name"].start_with?("syntax_tree_") }
  
  puts "Found #{syntax_tools.length} Syntax Tree tools:"
  syntax_tools.each do |tool|
    puts "  - #{tool['name']}: #{tool['description']}"
  end
  puts "-" * 50
  
  # Test validate
  if syntax_tools.any? { |t| t["name"] == "syntax_tree_validate" }
    puts "\nTesting syntax_tree_validate with valid notation:"
    test_mcp_request("tools/call", {
      name: "syntax_tree_validate",
      arguments: {
        notation: "[S [NP [Det The] [N cat]] [VP [V sits]]]"
      }
    })
    
    puts "\nTesting syntax_tree_validate with invalid notation:"
    test_mcp_request("tools/call", {
      name: "syntax_tree_validate",
      arguments: {
        notation: "[S [NP [Det The] [N cat]"  # Missing closing brackets
      }
    })
  end
  
  # Test convert
  if syntax_tools.any? { |t| t["name"] == "syntax_tree_convert" }
    puts "\nTesting syntax_tree_convert:"
    test_mcp_request("tools/call", {
      name: "syntax_tree_convert",
      arguments: {
        notation: "[S [NP [Det The] [N cat]] [VP [V sits] [PP [P on] [NP [Det the] [N mat]]]]]",
        language: "english"
      }
    })
  end
  
  # Test examples
  if syntax_tools.any? { |t| t["name"] == "syntax_tree_examples" }
    puts "\nTesting syntax_tree_examples:"
    test_mcp_request("tools/call", {
      name: "syntax_tree_examples",
      arguments: {
        language: "japanese"
      }
    })
  end
end