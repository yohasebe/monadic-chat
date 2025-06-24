#!/usr/bin/env ruby
# frozen_string_literal: true

# Test TextEmbeddings API key issue

require 'bundler/setup'
require 'dotenv'

# Load configuration
CONFIG = {}
Dotenv.load(File.expand_path("~/monadic/config/env"))
ENV.each { |k, v| CONFIG[k] = v }

require_relative 'lib/monadic/utils/text_embeddings'

puts "=== TextEmbeddings API Key Test ==="

# Test 1: Check configuration
puts "\n1. Checking configuration..."
puts "CONFIG['OPENAI_API_KEY'] exists: #{!CONFIG['OPENAI_API_KEY'].nil?}"
puts "API key length: #{CONFIG['OPENAI_API_KEY']&.length}"

# Test 2: Create TextEmbeddings instance
puts "\n2. Creating TextEmbeddings instance..."
begin
  embeddings = TextEmbeddings.new("test_db", recreate_db: false)
  puts "TextEmbeddings created successfully"
rescue => e
  puts "Error creating TextEmbeddings: #{e.message}"
  embeddings = nil
end

# Test 3: Test get_embeddings directly
if CONFIG['OPENAI_API_KEY']
  puts "\n3. Testing get_embeddings..."
  begin
    # Create a minimal instance just for testing
    class TestEmbeddings
      include TextEmbeddings
      
      def get_embeddings(text, api_key: nil)
        require 'net/http'
        require 'json'
        
        puts "  - Text: '#{text}'"
        puts "  - API key provided: #{!api_key.nil?}"
        puts "  - API key length: #{api_key&.length}"
        
        uri = URI("https://api.openai.com/v1/embeddings")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{api_key}"
        
        body = {
          input: text,
          model: "text-embedding-3-large"
        }
        
        request.body = body.to_json
        
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        
        response = http.request(request)
        puts "  - Response code: #{response.code}"
        
        if response.code == "200"
          result = JSON.parse(response.body)
          result["data"][0]["embedding"]
        else
          puts "  - Error response: #{response.body}"
          nil
        end
      end
    end
    
    test = TestEmbeddings.new
    embedding = test.get_embeddings("test", api_key: CONFIG['OPENAI_API_KEY'])
    puts "  - Embedding received: #{!embedding.nil?}"
    puts "  - Embedding size: #{embedding&.size}"
  rescue => e
    puts "Error in get_embeddings: #{e.message}"
  end
end

puts "\n=== End of test ==="