# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/error_formatter"

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
RSpec.describe Monadic::Utils::ErrorFormatter, 'credential redaction' do
  let(:fake_google) { 'AIza_NOT_A_REAL_KEY_REDACTION_TEST_0000' }

  it 'redacts Google, OpenAI and xAI key shapes without requiring a label' do
    [fake_google, 'sk-proj-NOT_A_REAL_KEY_TEST_ONLY_0000', 'xai-NOT_A_REAL_KEY_TEST_ONLY_0000'].each do |key|
      expect(described_class.scrub_identifiers("Denied #{key}; retry")).to eq('Denied [redacted]; retry')
    end
  end

  it 'redacts first and later URL query key values, preserving other parameters' do
    ['https://example.invalid/?key=short&alt=media',
     'https://example.invalid/?alt=media&key=short',
     'https://example.invalid/?api_key=short#section'].each do |text|
      expect(described_class.scrub_identifiers(text)).to eq(text.sub('short', '[redacted]'))
    end
  end

  it 'redacts URL-encoded credentials and bearer token syntax' do
    expect(described_class.scrub_identifiers('https://example.invalid/?key=fake%2Bencoded%3D&alt=media'))
      .to eq('https://example.invalid/?key=[redacted]&alt=media')
    expect(described_class.scrub_identifiers('Bearer NOT_A_REAL_BEARER_TOKEN_0000'))
      .to eq('Bearer [redacted]')
  end

  it 'redacts header values in HTTP, JSON and Ruby hash renderings' do
    ['x-goog-api-key: short', 'X-Goog-Api-Key=short',
     '{"x-goog-api-key":"short"}', '{"Authorization"=>"Bearer short"}',
     'Authorization: Bearer short'].each do |text|
      expect(described_class.scrub_identifiers(text)).to eq(text.sub('short', '[redacted]'))
    end
  end

  it 'does not redact ordinary messages, provider names or configuration names' do
    ['API key is missing. Set GEMINI_API_KEY.', 'Rate limit exceeded. Retry in 20 seconds.',
     'Bearer tokens authenticate requests.', 'Use the x-goog-api-key header.',
     'A key=value pair is required.', 'Use sk-learn to process data.',
     'https://example.invalid/?monkey=banana&keyboard=enabled'].each do |text|
      expect(described_class.scrub_identifiers(text)).to eq(text)
    end
  end

  it 'is idempotent and keeps nil unchanged' do
    expect(described_class.scrub_identifiers(nil)).to be_nil
    text = "Authorization: Bearer #{fake_google}"
    once = described_class.scrub_identifiers(text)
    expect(described_class.scrub_identifiers(once)).to eq(once)
  end
end
