#!/usr/bin/env ruby
# frozen_string_literal: true

# Test PDF Navigator API key issue

require 'bundler/setup'
require_relative 'lib/monadic'
require_relative 'lib/monadic/utils/text_embeddings'
require_relative 'apps/pdf_navigator/pdf_navigator_tools'

puts "=== PDF Navigator API Key Test ==="

# Test 1: Check if EMBEDDINGS_DB is initialized
puts "\n1. Checking EMBEDDINGS_DB..."
puts "EMBEDDINGS_DB defined: #{defined?(EMBEDDINGS_DB)}"
puts "EMBEDDINGS_DB class: #{EMBEDDINGS_DB.class}" if defined?(EMBEDDINGS_DB)

# Test 2: Create PDFNavigatorOpenAI instance
puts "\n2. Creating PDFNavigatorOpenAI instance..."
app = PDFNavigatorOpenAI.new
puts "Instance created: #{!app.nil?}"
puts "@api_key value: '#{app.instance_variable_get(:@api_key)}'"
puts "@embeddings_db value: #{app.instance_variable_get(:@embeddings_db).class}"

# Test 3: Test with direct API key setting
puts "\n3. Testing with manual API key..."
app.instance_variable_set(:@api_key, CONFIG["OPENAI_API_KEY"])
puts "@api_key after manual set: '#{app.instance_variable_get(:@api_key)}'"

# Test 4: Try to call find_closest_text
puts "\n4. Testing find_closest_text..."
begin
  result = app.find_closest_text(text: "machine learning", top_n: 1)
  puts "Result: #{result.inspect}"
rescue => e
  puts "Error: #{e.class} - #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
end

puts "\n=== End of test ==="