#!/usr/bin/env ruby

# Test script to check Visual Web Explorer app loading

require 'bundler/setup'
require 'active_support'
require 'active_support/core_ext/hash/indifferent_access'

# Set up minimal environment
$MODELS = ActiveSupport::HashWithIndifferentAccess.new
IN_CONTAINER = false
CONFIG = { "EXTRA_LOGGING" => true }

# Mock the MonadicApp base class
class MonadicApp
  def self.subclasses
    @subclasses ||= []
  end
  
  def self.inherited(subclass)
    subclasses << subclass
  end
  
  def self.register_models(vendor, models)
    # Mock implementation
  end
  
  def self.register_app_settings(app_name, app)
    # Mock implementation
  end
  
  attr_accessor :settings
end

# Mock helper modules
module OpenAIHelper
  def self.included(base)
    puts "OpenAIHelper included in #{base}"
  end
end

# Load the DSL
require_relative '../../lib/monadic/dsl'

# Now try to load the app
puts "Testing Visual Web Explorer app loading..."
puts "-" * 50

mdsl_file = File.join(__dir__, '../../apps/visual_web_explorer/visual_web_explorer_openai.mdsl')
rb_file = File.join(__dir__, '../../apps/visual_web_explorer/visual_web_explorer_openai.rb')

puts "MDSL file exists: #{File.exist?(mdsl_file)}"
puts "Ruby file exists: #{File.exist?(rb_file)}"

# First load the Ruby file
if File.exist?(rb_file)
  begin
    load rb_file
    puts "Ruby file loaded successfully"
  rescue => e
    puts "Error loading Ruby file: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
end

# Then load the MDSL
if File.exist?(mdsl_file)
  begin
    result = MonadicDSL::Loader.load(mdsl_file)
    puts "MDSL loaded: #{result.inspect}"
  rescue => e
    puts "Error loading MDSL: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
end

# Check if the app was registered
puts "\nRegistered app classes:"
MonadicApp.subclasses.each do |klass|
  puts "  - #{klass.name}"
end

puts "\nLoading errors:"
if defined?($MONADIC_LOADING_ERRORS) && $MONADIC_LOADING_ERRORS
  $MONADIC_LOADING_ERRORS.each do |error|
    puts "  - #{error[:app]}: #{error[:error]}"
  end
else
  puts "  None"
end