#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple unit test for monadic modules

require 'json'

# Add the lib path
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))

# Load only the monadic modules
require_relative '../../lib/monadic/core'
require_relative '../../lib/monadic/json_handler'
require_relative '../../lib/monadic/html_renderer'
require_relative '../../lib/monadic/app_extensions'

# Test class
class SimpleMonadicTest
  include Monadic::AppExtensions
  
  def initialize
    @context = { "test" => true, "count" => 0 }
    @settings = { "mathjax" => false }
  end
  
  def settings
    @settings
  end
  
  def run_tests
    puts "="*50
    puts "SIMPLE MONADIC MODULE TEST"
    puts "="*50
    
    test_core_functionality
    test_json_handling
    test_backward_compatibility
    
    puts "\nAll tests completed!"
  end
  
  private
  
  def test_core_functionality
    puts "\n1. Testing Core Functionality..."
    
    # Test wrap/unwrap
    wrapped = wrap("test value", { "meta" => "data" })
    puts "   - wrap: #{wrapped.value == 'test value' ? 'PASS' : 'FAIL'}"
    
    value = unwrap(wrapped)
    puts "   - unwrap: #{value == 'test value' ? 'PASS' : 'FAIL'}"
    
    # Test transform
    transformed = transform(wrapped) { |v| v.upcase }
    puts "   - transform: #{unwrap(transformed) == 'TEST VALUE' ? 'PASS' : 'FAIL'}"
  end
  
  def test_json_handling
    puts "\n2. Testing JSON Handling..."
    
    # Test wrap_as_json
    json = wrap_as_json("Hello", { "foo" => "bar" })
    parsed = JSON.parse(json)
    puts "   - wrap_as_json: #{parsed['message'] == 'Hello' ? 'PASS' : 'FAIL'}"
    
    # Test unwrap_from_json
    result = unwrap_from_json(json)
    puts "   - unwrap_from_json: #{result['context']['foo'] == 'bar' ? 'PASS' : 'FAIL'}"
    
    # Test transform_json
    transformed = transform_json(json) do |ctx|
      ctx["new_field"] = "added"
      ctx
    end
    parsed_transform = JSON.parse(transformed)
    puts "   - transform_json: #{parsed_transform['context']['new_field'] == 'added' ? 'PASS' : 'FAIL'}"
  end
  
  def test_backward_compatibility
    puts "\n3. Testing Backward Compatibility..."
    
    # Test monadic_unit
    unit_result = monadic_unit("Test message")
    parsed = JSON.parse(unit_result)
    puts "   - monadic_unit: #{parsed['message'] == 'Test message' ? 'PASS' : 'FAIL'}"
    
    # Test monadic_unwrap
    unwrapped = monadic_unwrap(unit_result)
    puts "   - monadic_unwrap: #{unwrapped['message'] == 'Test message' ? 'PASS' : 'FAIL'}"
    
    # Test monadic_map
    mapped = monadic_map(unit_result) do |ctx|
      ctx["count"] = 42
      ctx
    end
    parsed_map = JSON.parse(mapped)
    puts "   - monadic_map: #{parsed_map['context']['count'] == 42 ? 'PASS' : 'FAIL'}"
  end
end

# Run the test
if __FILE__ == $0
  test = SimpleMonadicTest.new
  test.run_tests
end