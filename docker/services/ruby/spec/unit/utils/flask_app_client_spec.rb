# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/flask_app_client"

RSpec.describe FlaskAppClient do
  let(:client) { described_class.new }
  
  describe "#initialize" do
    it "creates a new instance with default model" do
      expect(client).to be_a(FlaskAppClient)
    end
    
    it "accepts a custom model name" do
      custom_client = described_class.new("gpt-4")
      expect(custom_client.instance_variable_get(:@model_name)).to eq("gpt-4")
    end
  end
  
  describe "#count_tokens" do
    context "when Python service is available" do
      before do
        allow(client).to receive(:post_request).and_return({
          "number_of_tokens" => 10
        })
      end
      
      it "returns the token count for text" do
        expect(client.count_tokens("Hello, world!")).to eq(10)
      end
      
      it "uses default encoding when not specified" do
        expect(client).to receive(:post_request).with(
          "count_tokens",
          { text: "test", encoding_name: "o200k_base" }
        ).and_return({ "number_of_tokens" => 1 })
        
        client.count_tokens("test")
      end
      
      it "allows custom encoding" do
        expect(client).to receive(:post_request).with(
          "count_tokens",
          { text: "test", encoding_name: "cl100k_base" }
        ).and_return({ "number_of_tokens" => 1 })
        
        client.count_tokens("test", "cl100k_base")
      end
      
      it "caches results for the same text and encoding" do
        # First call should make API request
        expect(client).to receive(:post_request).once.and_return({
          "number_of_tokens" => 5
        })
        
        # Multiple calls with same text should use cache
        3.times { expect(client.count_tokens("cached text")).to eq(5) }
      end
      
      it "does not cache results for different encodings" do
        expect(client).to receive(:post_request).twice.and_return({
          "number_of_tokens" => 5
        })
        
        client.count_tokens("same text", "o200k_base")
        client.count_tokens("same text", "cl100k_base")
      end
    end
    
    context "when Python service is unavailable" do
      before do
        allow(client).to receive(:post_request).and_return(nil)
      end
      
      it "returns nil" do
        expect(client.count_tokens("Hello, world!")).to be_nil
      end
      
      it "does not cache nil results" do
        expect(client).to receive(:post_request).twice.and_return(nil)
        
        2.times { client.count_tokens("test text") }
      end
    end
  end
  
  describe "#get_tokens_sequence" do
    context "when Python service is available" do
      before do
        allow(client).to receive(:post_request).and_return({
          "tokens_sequence" => "1234,5678,9012"
        })
      end
      
      it "returns an array of token IDs" do
        result = client.get_tokens_sequence("Hello, world!")
        expect(result).to eq([1234, 5678, 9012])
      end
    end
    
    context "when Python service is unavailable" do
      before do
        allow(client).to receive(:post_request).and_return(nil)
      end
      
      it "returns nil" do
        expect(client.get_tokens_sequence("Hello, world!")).to be_nil
      end
    end
  end
  
  describe "#decode_tokens" do
    context "when Python service is available" do
      before do
        allow(client).to receive(:post_request).and_return({
          "original_text" => "Hello, world!"
        })
      end
      
      it "returns the decoded text" do
        result = client.decode_tokens([1234, 5678, 9012])
        expect(result).to eq("Hello, world!")
      end
      
      it "converts token array to comma-separated string" do
        expect(client).to receive(:post_request).with(
          "decode_tokens",
          { tokens: "1234,5678,9012", model_name: "gpt-3.5-turbo" }
        ).and_return({ "original_text" => "test" })
        
        client.decode_tokens([1234, 5678, 9012])
      end
    end
    
    context "when Python service is unavailable" do
      before do
        allow(client).to receive(:post_request).and_return(nil)
      end
      
      it "returns nil" do
        expect(client.decode_tokens([1234, 5678])).to be_nil
      end
    end
  end
  
  describe "#service_available?" do
    it "returns a boolean value" do
      # Since we can't easily mock HTTP requests without WebMock,
      # we just check that the method returns a boolean
      result = client.service_available?
      expect([true, false]).to include(result)
    end
  end
  
  describe "caching behavior" do
    before do
      # Clear the cache before each test
      client.class.class_variable_set(:@@token_count_cache, {})
    end
    
    it "respects MAX_CACHE_SIZE limit" do
      max_size = client.class.class_variable_get(:@@MAX_CACHE_SIZE)
      
      # Mock responses for different texts
      allow(client).to receive(:post_request) do |_, body|
        { "number_of_tokens" => body[:text].length }
      end
      
      # Fill cache beyond max size
      (max_size + 10).times do |i|
        client.count_tokens("text_#{i}")
      end
      
      # Cache should not exceed max size
      cache = client.class.class_variable_get(:@@token_count_cache)
      expect(cache.size).to be <= max_size
    end
  end
end