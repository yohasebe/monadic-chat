#!/usr/bin/env ruby

# Test script to debug Wikipedia app loading

require_relative 'lib/monadic/dsl'

# Test the DSL directly
puts "Testing Wikipedia app definition..."

# Simulate what happens when loading wikipedia.mdsl
app_content = File.read("apps/wikipedia/wikipedia.mdsl")
puts "\nApp content (first 100 chars):"
puts app_content[0..100] + "..."

# Evaluate the DSL
state = eval(app_content, TOPLEVEL_BINDING, "wikipedia.mdsl")

if state
  puts "\nApp state after evaluation:"
  puts "  name: #{state.name}"
  puts "  display_name: #{state.settings[:display_name]}"
  puts "  app_name: #{state.settings[:app_name]}"
  puts "  features: #{state.features.keys.join(', ')}"
end

# Check if Wikipedia class was created
if defined?(Wikipedia)
  settings = Wikipedia.instance_variable_get(:@settings)
  puts "\nWikipedia class created with settings:"
  puts "  display_name: #{settings[:display_name]}"
  puts "  app_name: #{settings[:app_name]}"
  puts "  group: #{settings[:group]}"
end