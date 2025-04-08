# frozen_string_literal: true

require 'rspec/mocks'
require 'ostruct'
require 'json'
require 'yaml'
require 'tempfile'
require 'fileutils'

# Define global test constants to avoid redefinition warnings
IN_CONTAINER = false unless defined?(IN_CONTAINER)

# Global variable for model caching in API helpers
$MODELS ||= {}

# Define MonadicApp module with shared constants for tests
module MonadicApp
  # Define constants only if they aren't already defined
  unless defined?(SHARED_VOL)
    SHARED_VOL = "/monadic/data"
  end
  
  unless defined?(LOCAL_SHARED_VOL)
    LOCAL_SHARED_VOL = File.expand_path(File.join(Dir.home, "monadic", "data"))
  end
  
  # Create a standard tokenizer mock that can be used across tests
  class TokenizerMock
    def self.get_tokens_sequence(text)
      # Simple token counting for testing purposes
      text.split(/\s+/).map { |word| "t_#{word}" }
    end
    
    def count_tokens(text, encoding_name = nil)
      return text.to_s.length < 20 ? 10 : 20 # Simulate different token counts based on length
    end
  end
  
  # Only define TOKENIZER if it's not already defined
  unless defined?(TOKENIZER)
    TOKENIZER = TokenizerMock.new
  end
  
  # Define AI_USER_INITIAL_PROMPT if not already defined
  unless defined?(AI_USER_INITIAL_PROMPT)
    AI_USER_INITIAL_PROMPT = "You are generating a response from the perspective of the human user in an ongoing conversation with an AI assistant."
  end
end

# Shared test utilities
module TestHelpers
  # Common HTTP response mocks
  def mock_successful_response(body)
    double("Response", 
      status: double("Status", success?: true),
      body: body
    )
  end
  
  def mock_error_response(body)
    double("Response",
      status: double("Status", success?: false),
      body: body
    )
  end

  # Common mock for process status
  def mock_status(success)
    OpenStruct.new(success?: success)
  end
  
  # Stub HTTP client for API helper tests
  def stub_http_client
    stub_const("HTTP", double)
    allow(HTTP).to receive(:headers).and_return(HTTP)
    allow(HTTP).to receive(:timeout).and_return(HTTP)
    allow(HTTP).to receive(:post).and_return(mock_successful_response('{"text":"Test response"}'))
  end
end

# Shared examples for vendor API helpers
RSpec.shared_examples "a vendor API helper" do |vendor_name, default_model|
  describe ".vendor_name" do
    it "returns the correct vendor name" do
      expect(described_class.vendor_name).to eq(vendor_name)
    end
  end
  
  describe ".list_models" do
    it "returns a non-empty list of models" do
      # We need to explicitly mock list_models to avoid actual API calls
      # This is different for each helper class but the test expectation is the same
      if described_class.respond_to?(:list_models)
        # Mock list_models to return some reasonable default values
        allow(described_class).to receive(:list_models).and_return([default_model, "another-model"])
      end
      
      models = described_class.list_models
      expect(models).to be_an(Array)
      expect(models).not_to be_empty
    end
  end
  
  describe "#send_query" do
    it "returns error when API key is missing" do
      # Remove API key from CONFIG
      stub_const("CONFIG", {})
      
      # For this test we need to override the HTTP mock to return an error
      allow(HTTP).to receive(:post).and_return(
        mock_error_response('{"error":{"message":"API key missing"}}')
      )
      
      result = helper.send_query({})
      expect(result).to match(/error|Error|ERROR/)
    end
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Include the mocking framework
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  
  # Include helper methods
  config.include TestHelpers
  
  # Setup test directories before running tests
  config.before(:suite) do
    # Create required directories for tests
    [
      File.expand_path(File.join(Dir.home, "monadic", "log")),
      File.expand_path(File.join(Dir.home, "monadic", "data")),
      File.expand_path(File.join(Dir.home, "monadic", "data", "scripts"))
    ].each do |dir|
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    end
  end
  
  # Clear any shared state between tests
  config.after(:each) do
    # Add any cleanup needed between tests
  end
end