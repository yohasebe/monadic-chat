#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark'
require 'json'

# Test data
test_message = "This is a test message for benchmarking"
test_context = {
  "items" => (1..100).map { |i| "item_#{i}" },
  "nested" => {
    "deep" => {
      "value" => "test"
    }
  },
  "count" => 42
}

# Simulate old implementation
module OldImplementation
  def self.monadic_unit(message, context)
    res = { "message": message, "context": context }
    res.to_json
  end
  
  def self.monadic_unwrap(monad)
    JSON.parse(monad)
  rescue JSON::ParserError
    { "message" => monad.to_s, "context" => {} }
  end
end

# Load new implementation
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require_relative '../../lib/monadic/json_handler'

class NewImplementation
  include MonadicChat::JsonHandler
  
  def initialize
    @context = {}
  end
end

# Benchmark
new_impl = NewImplementation.new
iterations = 10000

puts "Benchmarking #{iterations} iterations..."
puts "="*50

Benchmark.bm(20) do |x|
  # Test unit/wrap operation
  x.report("Old wrap:") do
    iterations.times do
      OldImplementation.monadic_unit(test_message, test_context)
    end
  end
  
  x.report("New wrap:") do
    iterations.times do
      new_impl.wrap_as_json(test_message, test_context)
    end
  end
  
  # Test unwrap operation with JSON string
  json_string = OldImplementation.monadic_unit(test_message, test_context)
  
  x.report("Old unwrap (JSON):") do
    iterations.times do
      OldImplementation.monadic_unwrap(json_string)
    end
  end
  
  x.report("New unwrap (JSON):") do
    iterations.times do
      new_impl.unwrap_from_json(json_string)
    end
  end
  
  # Test unwrap with Hash (new optimization)
  hash_data = { "message" => test_message, "context" => test_context }
  
  x.report("New unwrap (Hash):") do
    iterations.times do
      new_impl.unwrap_from_json(hash_data)
    end
  end
end

puts "\nNote: 'New unwrap (Hash)' shows the optimization when"
puts "data is already a Hash (no JSON parsing needed)"