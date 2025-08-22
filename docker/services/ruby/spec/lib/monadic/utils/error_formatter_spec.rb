# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/utils/error_formatter"

RSpec.describe Monadic::Utils::ErrorFormatter do
  describe ".format" do
    it "formats basic error message" do
      result = described_class.format(
        category: "Test Error",
        message: "Something went wrong",
        details: { provider: "TestProvider" }
      )
      
      expect(result).to eq("[TestProvider] Test Error: Something went wrong")
    end
    
    it "includes suggestion when provided" do
      result = described_class.format(
        category: "Test Error",
        message: "Something went wrong",
        details: {
          provider: "TestProvider",
          suggestion: "Try again"
        }
      )
      
      expect(result).to eq("[TestProvider] Test Error: Something went wrong Suggestion: Try again")
    end
    
    it "includes error code when provided" do
      result = described_class.format(
        category: "Test Error",
        message: "Something went wrong",
        details: {
          provider: "TestProvider",
          code: 500
        }
      )
      
      expect(result).to eq("[TestProvider] Test Error: Something went wrong (Code: 500)")
    end
  end
  
  describe ".api_key_error" do
    it "formats API key error with suggestion" do
      result = described_class.api_key_error(
        provider: "DeepSeek",
        env_var: "DEEPSEEK_API_KEY"
      )
      
      expect(result).to include("[DeepSeek]")
      expect(result).to include("Configuration Error")
      expect(result).to include("DEEPSEEK_API_KEY not found")
      expect(result).to include("Suggestion:")
      expect(result).to include("~/monadic/config/env")
    end
  end
  
  describe ".api_error" do
    it "formats API error with code" do
      result = described_class.api_error(
        provider: "DeepSeek",
        message: "Rate limit exceeded",
        code: 429
      )
      
      expect(result).to eq("[DeepSeek] API Error: Rate limit exceeded (Code: 429)")
    end
  end
  
  describe ".network_error" do
    it "formats network error" do
      result = described_class.network_error(
        provider: "Claude",
        message: "Connection refused"
      )
      
      expect(result).to include("[Claude]")
      expect(result).to include("Network Error")
      expect(result).to include("Check network connection")
    end
    
    it "formats timeout error" do
      result = described_class.network_error(
        provider: "Claude",
        message: "Request timed out",
        timeout: true
      )
      
      expect(result).to include("Timeout Error")
      expect(result).to include("Try increasing timeout")
    end
  end
  
  describe ".parsing_error" do
    it "formats parsing error" do
      result = described_class.parsing_error(
        provider: "Gemini",
        message: "Invalid JSON"
      )
      
      expect(result).to include("[Gemini]")
      expect(result).to include("Parsing Error")
      expect(result).to include("Check API response format")
    end
  end
  
  describe ".tool_error" do
    it "formats tool execution error" do
      result = described_class.tool_error(
        provider: "OpenAI",
        tool_name: "run_code",
        message: "Execution failed"
      )
      
      expect(result).to include("[OpenAI]")
      expect(result).to include("Tool Execution Error")
      expect(result).to include("run_code: Execution failed")
    end
  end
end