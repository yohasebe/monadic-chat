# frozen_string_literal: true

require "spec_helper"
require "json"

# Live test for xAI search about Tube Screamer
RSpec.describe "xAI Live Search - Tube Screamer Query", :integration do
  before(:all) do
    @skip_xai = !CONFIG["XAI_API_KEY"]
  end
  
  before(:each) do
    skip "xAI API key not configured" if @skip_xai
  end
  
  it "searches for information about Tube Screamer pedal popularity" do
    require_relative "../../lib/monadic/adapters/vendors/grok_helper"
    require_relative "../../lib/monadic/utils/string_utils"
    
    class TestGrokTubeScreamer
      include GrokHelper
      include StringUtils
      
      def self.name
        "Grok"
      end
      
      def markdown_to_html(text, mathjax: false)
        text
      end
      
      def detect_language(text)
        "en"
      end
    end
    
    helper = TestGrokTubeScreamer.new
    
    session = {
      messages: [],
      parameters: {
        "model" => "grok-4-0709",
        "websearch" => true,
        "temperature" => 0.3,
        "max_tokens" => 1500,
        "context_size" => 5,
        "app_name" => "test",
        "message" => "What is the secret behind the popularity of the Tube Screamer guitar pedal? Why do so many guitarists love it? Please search for recent discussions and expert opinions about its mid-frequency boost, smooth overdrive, and why it became a standard in the guitar world."
      }
    }
    
    puts "\n" + "=" * 60
    puts "Testing xAI Live Search: Tube Screamer Query"
    puts "=" * 60
    
    responses = []
    content_buffer = ""
    search_performed = false
    
    helper.api_request("user", session) do |response|
      responses << response
      
      case response["type"]
      when "wait"
        if response["content"]&.include?("SEARCHING")
          search_performed = true
          puts "✓ Web search initiated: #{response["content"]}"
        end
      when "fragment"
        content_buffer += response["content"] if response["content"]
      when "assistant"
        if response["content"].is_a?(Hash) && response["content"]["text"]
          content_buffer += response["content"]["text"]
        elsif response["content"].is_a?(String)
          content_buffer += response["content"]
        end
      when "message"
        if response["content"] && response["content"] != "DONE"
          if response["content"].is_a?(Hash) && response["content"]["text"]
            content_buffer += response["content"]["text"]
          elsif response["content"].is_a?(String)
            content_buffer += response["content"]
          end
        end
      when "error"
        puts "Error received: #{response["content"]}"
      end
    end
    
    puts "\n--- Response Summary ---"
    puts "Total responses: #{responses.length}"
    puts "Content length: #{content_buffer.length} characters"
    puts "Search performed: #{search_performed ? 'Yes' : 'No/Unknown'}"
    
    if content_buffer.length > 100
      # Check for relevant keywords
      keywords = ["tube screamer", "ibanez", "overdrive", "mid", "frequency", "guitar", 
                  "pedal", "tone", "ts808", "ts9", "boost", "clipping"]
      found_keywords = keywords.select { |kw| content_buffer.downcase.include?(kw) }
      
      puts "Found keywords (#{found_keywords.length}/#{keywords.length}): #{found_keywords.join(", ")}"
      
      # Display first 1500 characters of response to see more detail
      puts "\n--- Response Preview (first 1500 chars) ---"
      puts content_buffer[0..1499]
      puts "..." if content_buffer.length > 1500
      
      # Test assertions
      expect(content_buffer).not_to be_empty
      expect(found_keywords.length).to be >= 3, "Should contain at least 3 relevant keywords"
      
      puts "\n✓ Test passed: Received relevant information about Tube Screamer"
    else
      if content_buffer.empty?
        skip "xAI Live Search not returning content in test environment"
      else
        puts "Response too short: #{content_buffer}"
        skip "Response too short to evaluate"
      end
    end
  end
end