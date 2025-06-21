#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark script to measure startup performance improvements

require 'benchmark'
require 'fileutils'

# Ensure script directory exists
script_dir = File.dirname(__FILE__)
results_dir = File.join(script_dir, 'benchmark_results')
FileUtils.mkdir_p(results_dir)

# Configuration
ITERATIONS = 5
WARMUP_ITERATIONS = 2

def measure_startup(version_name, command)
  times = []
  
  # Warmup
  WARMUP_ITERATIONS.times do
    time = Benchmark.realtime { system(command, out: '/dev/null', err: '/dev/null') }
  end
  
  # Actual measurements
  ITERATIONS.times do |i|
    time = Benchmark.realtime { system(command, out: '/dev/null', err: '/dev/null') }
    times << time
    puts "  Iteration #{i + 1}: #{(time * 1000).round(2)}ms"
  end
  
  # Calculate statistics
  avg_time = times.sum / times.length
  min_time = times.min
  max_time = times.max
  
  {
    version: version_name,
    average: avg_time,
    min: min_time,
    max: max_time,
    times: times
  }
end

puts "Monadic Chat Startup Performance Benchmark"
puts "=========================================="
puts ""

results = []

# Test current version
puts "Testing current version..."
current_cmd = "cd #{File.dirname(__FILE__)}/../docker/services/ruby && ruby -e 'require_relative \"lib/monadic\"'"
results << measure_startup("Current", current_cmd)

# Test optimized version (if available)
optimized_path = File.join(File.dirname(__FILE__), '../docker/services/ruby/lib/monadic_optimized.rb')
if File.exist?(optimized_path)
  puts "\nTesting optimized version..."
  optimized_cmd = "cd #{File.dirname(__FILE__)}/../docker/services/ruby && ruby -e 'require_relative \"lib/monadic_optimized\"'"
  results << measure_startup("Optimized", optimized_cmd)
end

# Generate report
puts "\n\nSummary Report"
puts "=============="
puts ""

results.each do |result|
  puts "#{result[:version]} Version:"
  puts "  Average: #{(result[:average] * 1000).round(2)}ms"
  puts "  Min: #{(result[:min] * 1000).round(2)}ms"
  puts "  Max: #{(result[:max] * 1000).round(2)}ms"
  puts ""
end

if results.length > 1
  improvement = ((results[0][:average] - results[1][:average]) / results[0][:average] * 100).round(2)
  puts "Performance Improvement: #{improvement}%"
end

# Save detailed results
timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
results_file = File.join(results_dir, "benchmark_#{timestamp}.json")
File.write(results_file, JSON.pretty_generate({
  timestamp: timestamp,
  iterations: ITERATIONS,
  results: results
}))

puts "\nDetailed results saved to: #{results_file}"