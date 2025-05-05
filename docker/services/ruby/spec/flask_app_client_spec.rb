# frozen_string_literal: true

require "net/http"
require "json"
require_relative "./spec_helper"
require_relative "../lib/monadic/utils/flask_app_client"

RSpec.describe FlaskAppClient do
  let(:client) { FlaskAppClient.new("gpt-4-turbo") }

  # Create standard mock response
  let(:mock_response) do
    double("Net::HTTPResponse",
      body: '{"result": "success"}',
      is_a?: true
    )
  end

  before do
    # Mock Net::HTTP for all tests
    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)
  end

  describe "#initialize" do
    it "initializes with a model name" do
      custom_client = FlaskAppClient.new("custom-model")
      expect(custom_client.instance_variable_get(:@model_name)).to eq("custom-model")
    end

    it "uses a default model name if not provided" do
      default_client = FlaskAppClient.new
      expect(default_client.instance_variable_get(:@model_name)).to eq("gpt-3.5-turbo")
    end
  end

  describe "#get_encoding_name" do
    it "returns encoding name for a given model" do
      # Configure specific mock response for this test
      encoding_response = double("Net::HTTPResponse",
        body: '{"encoding_name": "o200k_base"}',
        is_a?: true
      )
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(encoding_response)
      
      result = client.get_encoding_name("gpt-4")
      expect(result).to eq("o200k_base")
    end

    it "uses the default model if none is provided" do
      # Ensure we're passing the right parameters
      expect_any_instance_of(Net::HTTP::Post).to receive(:body=) do |_, value|
        data = JSON.parse(value)
        expect(data["model_name"]).to eq("gpt-4-turbo")
        nil
      end
      
      client.get_encoding_name
    end

    it "returns nil when there's an error" do
      # Configure error response
      error_response = double("Net::HTTPResponse",
        body: '{"error": "Invalid model"}',
        is_a?: true
      )
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(error_response)
      
      result = client.get_encoding_name
      expect(result).to be_nil
    end
  end

  describe "#count_tokens" do
    # Reset the token count cache before each test
    before do
      # Access the class variable to reset it
      if FlaskAppClient.class_variable_defined?(:@@token_count_cache)
        FlaskAppClient.class_variable_set(:@@token_count_cache, {})
      end
    end

    it "returns token count for given text and encoding" do
      # Mock post_request directly
      allow(client).to receive(:post_request).with(
        "count_tokens", 
        {text: "Example text", encoding_name: "o200k_base"}
      ).and_return({"number_of_tokens" => 10})
      
      result = client.count_tokens("Example text", "o200k_base")
      expect(result).to eq(10)
    end

    it "uses default encoding if not specified" do
      # Verify the right parameters are passed to post_request
      expect(client).to receive(:post_request).with(
        "count_tokens", 
        {text: "Example text", encoding_name: "o200k_base"}
      ).and_return({"number_of_tokens" => 10})
      
      client.count_tokens("Example text")
    end

    it "returns nil on HTTP error" do
      # Mock post_request to return nil (simulating HTTP error)
      allow(client).to receive(:post_request).with(
        "count_tokens", 
        {text: "Example text", encoding_name: "o200k_base"}
      ).and_return(nil)
      
      result = client.count_tokens("Example text")
      expect(result).to be_nil
    end
  end

  describe "#get_tokens_sequence" do
    it "returns array of token IDs" do
      # Configure specific mock response
      sequence_response = double("Net::HTTPResponse",
        body: '{"tokens_sequence": "1,2,3,4,5"}',
        is_a?: true
      )
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(sequence_response)
      
      result = client.get_tokens_sequence("Example text")
      expect(result).to eq([1, 2, 3, 4, 5])
    end

    it "returns nil on error" do
      # Force HTTP failure
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
        double("Net::HTTPBadRequest", is_a?: false)
      )
      
      result = client.get_tokens_sequence("Example text")
      expect(result).to be_nil
    end
  end

  describe "#decode_tokens" do
    it "converts token IDs back to text" do
      # Configure specific mock response
      decode_response = double("Net::HTTPResponse",
        body: '{"original_text": "Example text"}',
        is_a?: true
      )
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(decode_response)
      
      result = client.decode_tokens([1, 2, 3, 4, 5])
      expect(result).to eq("Example text")
    end

    it "joins token array with commas" do
      expect_any_instance_of(Net::HTTP::Post).to receive(:body=) do |_, value|
        data = JSON.parse(value)
        expect(data["tokens"]).to eq("1,2,3,4,5")
        nil
      end
      
      client.decode_tokens([1, 2, 3, 4, 5])
    end

    it "returns nil on HTTP error" do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
        double("Net::HTTPBadRequest", is_a?: false)
      )
      
      result = client.decode_tokens([1, 2, 3])
      expect(result).to be_nil
    end
  end

  describe "#post_request" do
    it "sets the proper headers and timeout" do
      # Test the private method using send
      expect_any_instance_of(Net::HTTP).to receive(:read_timeout=).with(600)
      
      # Check that Net::HTTP::Post is initialized with the right parameters
      expect(Net::HTTP::Post).to receive(:new).with(
        anything, { "Content-Type": "application/json" }
      ).and_call_original
      
      # Mock the actual HTTP request
      allow_any_instance_of(Net::HTTP::Post).to receive(:body=)
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
        double("Net::HTTPSuccess", is_a?: true, body: '{"result": "success"}')
      )
      
      client.send(:post_request, "test_endpoint", {data: "test"})
    end

    it "constructs the correct URL" do
      # Check the URL is formed correctly
      expect(Net::HTTP::Post).to receive(:new) do |uri, _|
        expect(uri).to eq("/test_endpoint")
        double("Net::HTTP::Post").as_null_object
      end
      
      # Mock the HTTP request
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
        double("Net::HTTPSuccess", is_a?: true, body: '{"result": "success"}')
      )
      
      client.send(:post_request, "test_endpoint", {data: "test"})
    end
  end
end