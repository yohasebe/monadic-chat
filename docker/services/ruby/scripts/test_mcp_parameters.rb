#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# Test script to demonstrate correct parameter usage
class MCPParameterTester
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

  def test_parameter_errors
    puts "Testing MCP Parameter Error Handling"
    puts "=" * 50
    
    # Test 1: Wrong parameter name
    puts "\n1. Testing wrong parameter name (using 'query' instead of 'text'):"
    result = make_request("tools/call", {
      name: "MonadicHelpOpenAI__find_help_topics",
      arguments: {
        query: "syntax tree"  # Wrong: should be 'text'
      }
    })
    
    if result && result['error']
      puts "✓ Error correctly caught:"
      puts "  #{result['error']['message']}"
      puts "  #{result['error']['data']}" if result['error']['data']
    end
    
    # Test 2: Correct parameter name
    puts "\n2. Testing correct parameter name (using 'text'):"
    result = make_request("tools/call", {
      name: "MonadicHelpOpenAI__find_help_topics",
      arguments: {
        text: "syntax tree"  # Correct parameter name
      }
    })
    
    if result && result['result']
      puts "✓ Tool executed successfully"
      # Show first few lines of result
      if result['result']['content'] && result['result']['content'][0]
        text = result['result']['content'][0]['text']
        puts "  Result preview: #{text.lines.first(3).join.strip}..."
      end
    elsif result && result['error']
      puts "✗ Error occurred:"
      puts "  #{result['error']['message']}"
    end
    
    # Test 3: Missing required parameter
    puts "\n3. Testing missing required parameter:"
    result = make_request("tools/call", {
      name: "MonadicHelpOpenAI__find_help_topics",
      arguments: {
        top_n: 3  # Missing required 'text' parameter
      }
    })
    
    if result && result['error']
      puts "✓ Error correctly caught:"
      puts "  #{result['error']['message']}"
      puts "  #{result['error']['data']}" if result['error']['data']
    end
    
    puts "\n" + "=" * 50
    puts "Test completed"
  end
  
  def show_tool_parameters
    puts "\nFetching tool parameter information..."
    puts "=" * 50
    
    result = make_request("tools/list")
    
    if result && result['result'] && result['result']['tools']
      tools = result['result']['tools']
      
      # Show a few example tools with their parameters
      example_tools = [
        'MonadicHelpOpenAI__find_help_topics',
        'PDFNavigatorOpenAI__search_pdf',
        'CodeInterpreterOpenAI__run_code'
      ]
      
      example_tools.each do |tool_name|
        tool = tools.find { |t| t['name'] == tool_name }
        next unless tool
        
        puts "\nTool: #{tool['name']}"
        puts "Description: #{tool['description']}"
        
        if tool['inputSchema'] && tool['inputSchema']['properties']
          puts "Parameters:"
          tool['inputSchema']['properties'].each do |name, schema|
            required = tool['inputSchema']['required']&.include?(name) ? "REQUIRED" : "optional"
            puts "  - #{name} (#{schema['type']}, #{required}): #{schema['description']}"
          end
        end
      end
    end
  end
end

# Run tests if executed directly
if __FILE__ == $0
  tester = MCPParameterTester.new
  tester.show_tool_parameters
  puts "\n\n"
  tester.test_parameter_errors
end