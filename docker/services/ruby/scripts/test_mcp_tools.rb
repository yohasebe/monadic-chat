#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'

# Test the MCP server tools/list endpoint
uri = URI.parse("http://localhost:3100/mcp")
request = Net::HTTP::Post.new(uri)
request.content_type = "application/json"

# First, initialize
init_request = {
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "initialize",
  "params" => {
    "clientInfo" => {
      "name" => "test-client",
      "version" => "1.0.0"
    }
  }
}

request.body = init_request.to_json

begin
  response = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(request)
  end
  
  puts "Initialize response: #{response.code}"
  init_result = JSON.parse(response.body)
  puts JSON.pretty_generate(init_result)
rescue => e
  puts "Error initializing: #{e.message}"
  exit 1
end

# Now list tools
tools_request = {
  "jsonrpc" => "2.0",
  "id" => 2,
  "method" => "tools/list",
  "params" => {}
}

request.body = tools_request.to_json

begin
  response = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(request)
  end
  
  puts "\n\nTools list response: #{response.code}"
  result = JSON.parse(response.body)
  
  if result["result"] && result["result"]["tools"]
    tools = result["result"]["tools"]
    puts "Total tools: #{tools.length}"
    
    # Show all tools with their indices and name lengths
    puts "\n=== All Tools ==="
    tools.each_with_index do |tool, idx|
      puts "#{idx}: #{tool['name']} (#{tool['name'].length} chars)"
    end
    
    # Check for tools with names > 64 chars
    long_tools = tools.select { |t| t['name'].length > 64 }
    if long_tools.any?
      puts "\n=== Tools with names > 64 characters ==="
      long_tools.each do |tool|
        idx = tools.index(tool)
        puts "Tool #{idx}: #{tool['name']} (#{tool['name'].length} chars)"
      end
    else
      puts "\n=== All tool names are 64 characters or less ==="
    end
    
    # Check tool 22 specifically
    if tools.length > 22
      puts "\n=== Tool 22 Details ==="
      tool_22 = tools[22]
      puts "Name: #{tool_22['name']}"
      puts "Length: #{tool_22['name'].length}"
      puts "Description: #{tool_22['description'][0..100]}..."
      puts "Full tool 22 JSON:"
      puts JSON.pretty_generate(tool_22)
    end
    
    # Save the full response for analysis
    File.write("/tmp/mcp_tools_response.json", JSON.pretty_generate(result))
    puts "\nFull response saved to /tmp/mcp_tools_response.json"
  else
    puts "Error: No tools in response"
    puts JSON.pretty_generate(result)
  end
rescue => e
  puts "Error listing tools: #{e.message}"
  puts e.backtrace.join("\n")
end