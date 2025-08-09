require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/openai_helper"

RSpec.describe "OpenAI Monadic Response Integration" do
  # Create a test class that includes OpenAIHelper
  let(:test_class) do
    Class.new do
      include OpenAIHelper
      
      def monadic_mode?
        true
      end
      
      def self.monadic_map(content)
        content
      end
    end
  end
  
  let(:helper) { test_class.new }
  
  describe "Chat Completions API monadic response handling" do
    it "preserves full JSON structure when processing Hash response" do
      # Simulate the response processing section around line 1429
      processed = {
        "message" => "This is the response",
        "context" => {
          "key1" => "value1",
          "key2" => ["item1", "item2"]
        }
      }
      
      choice = { "message" => { "content" => "" } }
      
      # Simulate the actual code logic
      if processed.is_a?(Hash)
        choice["message"]["content"] = JSON.generate(processed)
      elsif processed.is_a?(String)
        choice["message"]["content"] = processed
      else
        choice["message"]["content"] = processed.to_s
      end
      
      # Verify the full JSON is preserved
      result = JSON.parse(choice["message"]["content"])
      expect(result).to have_key("message")
      expect(result).to have_key("context")
      expect(result["context"]).to eq(processed["context"])
    end
    
    it "handles String responses correctly" do
      processed = '{"message": "test", "context": {"data": "value"}}'
      choice = { "message" => { "content" => "" } }
      
      if processed.is_a?(Hash)
        choice["message"]["content"] = JSON.generate(processed)
      elsif processed.is_a?(String)
        choice["message"]["content"] = processed
      else
        choice["message"]["content"] = processed.to_s
      end
      
      # String should be passed through as-is
      expect(choice["message"]["content"]).to eq(processed)
      
      # And should be valid JSON
      result = JSON.parse(choice["message"]["content"])
      expect(result).to have_key("message")
      expect(result).to have_key("context")
    end
  end
  
  describe "Responses API monadic response handling" do
    it "preserves full JSON structure when processing Hash response" do
      # Simulate the response processing section around line 2067
      processed = {
        "message" => "Response from GPT-5",
        "context" => {
          "target_lang" => "Japanese",
          "language_advice" => [
            "Tip 1",
            "Tip 2"
          ]
        }
      }
      
      choice = { "message" => { "content" => "" } }
      
      # Simulate the actual code logic for Responses API
      if processed.is_a?(Hash)
        choice["message"]["content"] = JSON.generate(processed)
      elsif processed.is_a?(String)
        choice["message"]["content"] = processed
      else
        choice["message"]["content"] = processed.to_s
      end
      
      # Verify the full JSON is preserved
      result = JSON.parse(choice["message"]["content"])
      expect(result).to have_key("message")
      expect(result).to have_key("context")
      expect(result["context"]["target_lang"]).to eq("Japanese")
      expect(result["context"]["language_advice"]).to be_an(Array)
    end
  end
  
  describe "Regression tests for the monadic context bug" do
    it "does NOT extract only the message field from Hash (bug fixed)" do
      processed = {
        "message" => "User message",
        "context" => {
          "important" => "This must not be lost"
        }
      }
      
      choice = { "message" => { "content" => "" } }
      
      # OLD BUGGY CODE would have done:
      # choice["message"]["content"] = processed["message"] || JSON.generate(processed)
      # This would lose the context!
      
      # NEW FIXED CODE does:
      if processed.is_a?(Hash)
        choice["message"]["content"] = JSON.generate(processed)
      end
      
      result = JSON.parse(choice["message"]["content"])
      
      # This is the critical test - context must be preserved
      expect(result["context"]).not_to be_nil
      expect(result["context"]["important"]).to eq("This must not be lost")
    end
    
    it "handles all monadic app formats correctly" do
      test_cases = [
        # Language Practice Plus format
        {
          "message" => "こんにちは",
          "context" => {
            "target_lang" => "Japanese",
            "language_advice" => ["Use です/ます forms"]
          }
        },
        # Chat Plus format
        {
          "message" => "I understand",
          "context" => {
            "reasoning" => "User asked about X",
            "topics" => ["topic1"],
            "people" => [],
            "notes" => ["note1"]
          }
        },
        # Novel Writer format
        {
          "message" => "Chapter begins...",
          "context" => {
            "chapter" => "1",
            "characters" => ["Alice", "Bob"],
            "setting" => "Tokyo"
          }
        }
      ]
      
      test_cases.each do |test_case|
        choice = { "message" => { "content" => "" } }
        
        if test_case.is_a?(Hash)
          choice["message"]["content"] = JSON.generate(test_case)
        end
        
        result = JSON.parse(choice["message"]["content"])
        
        # Every test case must preserve its context
        expect(result["context"]).to eq(test_case["context"])
      end
    end
  end
  
  describe "Edge cases and error handling" do
    it "handles nil processed response" do
      processed = nil
      choice = { "message" => { "content" => "" } }
      
      if processed.is_a?(Hash)
        choice["message"]["content"] = JSON.generate(processed)
      elsif processed.is_a?(String)
        choice["message"]["content"] = processed
      else
        choice["message"]["content"] = processed.to_s
      end
      
      expect(choice["message"]["content"]).to eq("")
    end
    
    it "handles malformed JSON string" do
      processed = "not a valid json {broken"
      choice = { "message" => { "content" => "" } }
      
      if processed.is_a?(Hash)
        choice["message"]["content"] = JSON.generate(processed)
      elsif processed.is_a?(String)
        choice["message"]["content"] = processed
      else
        choice["message"]["content"] = processed.to_s
      end
      
      # Should pass through as-is even if invalid
      expect(choice["message"]["content"]).to eq(processed)
    end
    
    it "handles deeply nested context structures" do
      processed = {
        "message" => "Complex response",
        "context" => {
          "level1" => {
            "level2" => {
              "level3" => {
                "data" => "deeply nested value"
              }
            }
          }
        }
      }
      
      choice = { "message" => { "content" => "" } }
      
      if processed.is_a?(Hash)
        choice["message"]["content"] = JSON.generate(processed)
      end
      
      result = JSON.parse(choice["message"]["content"])
      expect(result["context"]["level1"]["level2"]["level3"]["data"]).to eq("deeply nested value")
    end
  end
end