#!/usr/bin/env ruby

# Test script to debug Wikipedia app loading

require_relative 'lib/monadic'

# Enable debug output
$DEBUG = true

# Clear any existing app definitions
Object.send(:remove_const, :Wikipedia) if defined?(Wikipedia)

# Load the Wikipedia MDSL file
puts "Loading Wikipedia MDSL file..."
app_file = File.join(Dir.pwd, "apps", "wikipedia", "wikipedia.mdsl")
state = MonadicDSL::Loader.load(app_file)

if state
  puts "\nApp state after loading:"
  puts "  name: #{state.name}"
  puts "  display_name: #{state.settings[:display_name]}"
  puts "  app_name: #{state.settings[:app_name]}"
  puts "  provider: #{state.settings[:provider]}"
  puts "  features: #{state.features.inspect}"
end

# Check the generated class
if defined?(Wikipedia)
  puts "\nWikipedia class settings:"
  puts "  @settings: #{Wikipedia.instance_variable_get(:@settings).inspect}"
end