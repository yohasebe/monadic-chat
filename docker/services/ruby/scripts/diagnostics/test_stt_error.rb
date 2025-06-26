#!/usr/bin/env ruby

# This script demonstrates the improved STT error handling
# It simulates different error scenarios to show how error messages are now more informative

require_relative '../../lib/monadic/utils/interaction_utils'
require 'json'

class STTErrorTester
  include InteractionUtils
  
  attr_accessor :api_key
  
  def settings
    OpenStruct.new(api_key: api_key)
  end
  
  def initialize
    @api_key = "invalid-test-key" # Using an invalid key to trigger an error
  end
  
  def test_stt_error_handling
    puts "Testing STT API error handling with invalid API key..."
    puts "=" * 60
    
    # Create a small test audio file (just some random data, won't be valid audio)
    test_audio = "This is not real audio data"
    
    begin
      result = stt_api_request(test_audio, "mp3", "en")
      
      if result["type"] == "error"
        puts "✓ Error detected as expected"
        puts "Error message: #{result["content"]}"
        puts ""
        puts "Analysis:"
        
        # Check if the error message now contains more detail
        if result["content"] == "Speech-to-Text API Error"
          puts "✗ Old behavior: Generic error message with no details"
        elsif result["content"].include?("Speech-to-Text API Error:")
          puts "✓ New behavior: Error message includes API response details"
          
          # Check what details are included
          if result["content"].include?("401") || result["content"].include?("Unauthorized")
            puts "  - Includes HTTP status code"
          end
          if result["content"].include?("Invalid API key") || result["content"].include?("invalid_api_key")
            puts "  - Includes specific error reason"
          end
          if result["content"].include?("[OPENAI]")
            puts "  - Includes provider context"
          end
        end
      else
        puts "✗ Unexpected: No error returned (this shouldn't happen with invalid key)"
      end
    rescue => e
      puts "Exception occurred: #{e.message}"
      puts "This might happen if the API endpoint is not reachable"
    end
    
    puts "=" * 60
    puts "Test complete!"
  end
end

# Run the test
tester = STTErrorTester.new
tester.test_stt_error_handling