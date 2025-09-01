#!/usr/bin/env ruby

# Debug script for ModelSpec module
require_relative "docker/services/ruby/lib/monadic/utils/model_spec"

puts "Debugging ModelSpec module..."
puts "=" * 50

# Try to load the spec directly
spec = Monadic::Utils::ModelSpec.load_spec
puts "Loaded spec keys (first 10):"
puts spec.keys.first(10).inspect

puts "\nGPT-5 spec:"
puts Monadic::Utils::ModelSpec.get_model_spec("gpt-5").inspect

puts "\nChecking file path..."
spec_path = File.join(
  File.dirname(__FILE__),
  "docker", "services", "ruby",
  "public", "js", "monadic", "model_spec.js"
)
puts "Path: #{spec_path}"
puts "Exists?: #{File.exist?(spec_path)}"

if File.exist?(spec_path)
  puts "\nFirst 20 lines of file:"
  puts File.readlines(spec_path).first(20).join
end