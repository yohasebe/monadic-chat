# frozen_string_literal: true

require "spec_helper"
require "json"
require "tempfile"
require "stringio"
require "http"

# Save and clear ARGV to prevent option parsing
original_argv = ARGV.dup
ARGV.clear
ARGV.push("-p", "test") # Add required argument

# Load the script
script_path = File.expand_path("../../../../scripts/generators/image_generator_grok.rb", __dir__)
load script_path

# Restore ARGV
ARGV.clear
ARGV.concat(original_argv)

RSpec.describe "ImageGeneratorGrok" do
  let(:mock_api_key) { "test-xai-api-key-12345" }
  let(:test_prompt) { "A futuristic cityscape at sunset" }
  let(:mock_image_url) { "https://example.com/generated_image.png" }
  
  before do
    # Silence output during tests
    @original_stdout = $stdout
    @original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    
    # Mock API key reading
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with("/monadic/config/env").and_raise(Errno::ENOENT)
    allow(File).to receive(:read).with("#{Dir.home}/monadic/config/env").and_return("XAI_API_KEY=#{mock_api_key}\n")
    
    # Mock download directory
    allow(Dir).to receive(:exist?).and_call_original
    allow(Dir).to receive(:exist?).with("/monadic/data/").and_return(true)
  end
  
  after do
    # Restore output
    $stdout = @original_stdout if @original_stdout
    $stderr = @original_stderr if @original_stderr
  end
  
  describe "#generate_image" do
    context "with successful API response" do
      it "generates image and returns result" do
        # Mock HTTP response
        mock_response = double("HTTP::Response",
          status: double("HTTP::Status", success?: true),
          body: {
            created: Time.now.to_i,
            data: [
              {
                b64_json: Base64.encode64("fake image data"),
                revised_prompt: "A futuristic cityscape at sunset with neon lights"
              }
            ]
          }.to_json
        )
        
        allow(HTTP).to receive_message_chain(:headers, :post).and_return(mock_response)
        
        # Mock file writing
        allow(File).to receive(:open).and_call_original
        test_file = StringIO.new
        allow(File).to receive(:open).with(anything, "wb").and_yield(test_file)
        
        result = generate_image(test_prompt)
        
        expect(result[:success]).to be true
        expect(result[:filename]).to match(/\d+\.png/)
        expect(result[:revised_prompt]).to eq("A futuristic cityscape at sunset with neon lights")
      end
    end
    
    context "with API error" do
      it "returns error result" do
        # Mock HTTP error response
        mock_response = double("HTTP::Response",
          status: double("HTTP::Status", success?: false),
          body: {
            error: {
              message: "Invalid API key"
            }
          }.to_json
        )
        
        allow(HTTP).to receive_message_chain(:headers, :post).and_return(mock_response)
        
        result = generate_image(test_prompt)
        
        expect(result[:success]).to be false
        expect(result[:message]).to eq("Invalid API key")
      end
    end
    
    context "with network error" do
      it "retries and handles failure" do
        # Mock network error
        allow(HTTP).to receive_message_chain(:headers, :post).and_raise(HTTP::Error, "Network error")
        
        result = generate_image(test_prompt, num_retrials: 1)
        
        expect(result[:success]).to be false
        expect(result[:message]).to include("Network error")
      end
    end
    
    context "with missing API key" do
      it "handles missing API key gracefully" do
        # Mock missing API key - both paths return content without XAI_API_KEY
        allow(File).to receive(:read).with("/monadic/config/env").and_raise(Errno::ENOENT)
        allow(File).to receive(:read).with("#{Dir.home}/monadic/config/env").and_return("OTHER_KEY=value\n")
        
        # When API key is missing, find returns nil, causing NoMethodError on split
        result = generate_image(test_prompt)
        
        # The function should handle the error and return an error result
        expect(result[:success]).to be false
        expect(result[:message]).to include("Error:")
      end
    end
  end
  
  # Command line parsing test removed as it's tested by running the script
end