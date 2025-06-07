# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "./spec_helper"
require_relative "../lib/monadic/adapters/wikipedia_helper"

RSpec.describe WikipediaHelper do
  # Create a test class that includes the WikipediaHelper module
  let(:test_class) do
    Class.new do
      include WikipediaHelper
    end
  end
  
  let(:helper) { test_class.new }
  
  # Sample Wikipedia API response
  let(:sample_response) do
    {
      "pages" => [
        {
          "id" => 123456,
          "key" => "Ruby_(programming_language)",
          "title" => "Ruby (programming language)",
          "excerpt" => "Ruby is a dynamic, interpreted programming language...",
          "description" => "programming language"
        },
        {
          "id" => 789012,
          "key" => "Ruby",
          "title" => "Ruby",
          "excerpt" => "A ruby is a pink to blood-red colored gemstone...",
          "description" => "gemstone"
        }
      ]
    }.to_json
  end

  describe "#search_wikipedia" do
    it "constructs correct API URL with parameters" do
      expect(helper).to receive(:perform_request_with_retries) do |uri|
        expect(uri.to_s).to include("https://api.wikimedia.org/core/v1/wikipedia/en/search/page")
        expect(uri.query).to include("q=ruby")
        expect(uri.query).to include("limit=10")
        sample_response
      end
      
      helper.search_wikipedia(search_query: "ruby", language_code: "en")
    end
    
    it "uses default language code when not provided" do
      expect(helper).to receive(:perform_request_with_retries) do |uri|
        expect(uri.to_s).to include("/wikipedia/en/search/page")
        sample_response
      end
      
      helper.search_wikipedia(search_query: "ruby")
    end
    
    it "uses different language codes correctly" do
      expect(helper).to receive(:perform_request_with_retries) do |uri|
        expect(uri.to_s).to include("/wikipedia/ja/search/page")
        sample_response
      end
      
      helper.search_wikipedia(search_query: "ruby", language_code: "ja")
    end
    
    it "handles empty search query" do
      expect(helper).to receive(:perform_request_with_retries) do |uri|
        expect(uri.query).to include("q=")
        sample_response
      end
      
      helper.search_wikipedia(search_query: "", language_code: "en")
    end
    
    it "encodes special characters in search query" do
      expect(helper).to receive(:perform_request_with_retries) do |uri|
        # The query should be properly URL encoded
        expect(uri.query).to include("q=ruby+%26+programming")
        sample_response
      end
      
      helper.search_wikipedia(search_query: "ruby & programming", language_code: "en")
    end
    
    it "returns formatted JSON response on success" do
      allow(helper).to receive(:perform_request_with_retries).and_return(sample_response)
      
      result = helper.search_wikipedia(search_query: "ruby")
      
      expect(result).to include("```json")
      expect(result).to include("Ruby (programming language)")
      expect(result).to include("```")
    end
    
    it "handles request errors gracefully" do
      allow(helper).to receive(:perform_request_with_retries).and_raise(StandardError.new("Network error"))
      
      result = helper.search_wikipedia(search_query: "ruby")
      
      expect(result).to start_with("Error: The search request could not be completed.")
      expect(result).to include("https://api.wikimedia.org/core/v1/wikipedia/en/search/page")
    end
    
    it "handles JSON parsing errors gracefully" do
      allow(helper).to receive(:perform_request_with_retries).and_return("invalid json response")
      
      result = helper.search_wikipedia(search_query: "ruby")
      
      expect(result).to start_with("Error: The search response could not be parsed.")
      expect(result).to include("invalid json response")
    end
    
    it "sets correct limit parameter" do
      expect(helper).to receive(:perform_request_with_retries) do |uri|
        expect(uri.query).to include("limit=10")
        sample_response
      end
      
      helper.search_wikipedia(search_query: "ruby")
    end
  end

  describe "#perform_request_with_retries" do
    let(:uri) { URI("https://api.wikimedia.org/core/v1/wikipedia/en/search/page?q=test") }
    let(:mock_response) { double("Net::HTTPResponse", body: sample_response) }
    
    it "performs HTTP GET request with SSL" do
      http_double = double("HTTP")
      expect(Net::HTTP).to receive(:start).with(
        uri.host, 
        uri.port, 
        use_ssl: true, 
        open_timeout: 5
      ) do |_, _, _, _, &block|
        block.call http_double
      end
      
      expect(http_double).to receive(:request).with(instance_of(Net::HTTP::Get)).and_return(mock_response)
      
      result = helper.perform_request_with_retries(uri)
      expect(result).to eq(sample_response)
    end
    
    it "creates GET request with correct URI" do
      http_double = double("HTTP")
      expect(Net::HTTP::Get).to receive(:new).with(uri).and_return(double("Request"))
      expect(http_double).to receive(:request).and_return(mock_response)
      allow(Net::HTTP).to receive(:start) do |_, _, _, _, &block|
        block.call http_double
      end
      
      helper.perform_request_with_retries(uri)
    end
    
    it "retries on timeout errors" do
      call_count = 0
      allow(Net::HTTP).to receive(:start) do |_, _, _, _, &block|
        call_count += 1
        if call_count <= 2
          raise Net::OpenTimeout.new("Timeout")
        else
          # Return a yielded double on successful call
          http_double = double("HTTP")
          allow(http_double).to receive(:request).and_return(mock_response)
          block.call http_double
        end
      end
      
      result = helper.perform_request_with_retries(uri)
      expect(result).to eq(sample_response)
      expect(call_count).to eq(3)  # Initial + 2 retries
    end
    
    it "returns error message after max retries exceeded" do
      allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout.new("Timeout"))
      
      result = helper.perform_request_with_retries(uri)
      expect(result).to eq("Error: The request timed out.")
    end
    
    it "handles HTTP errors other than timeout" do
      allow(Net::HTTP).to receive(:start).and_raise(SocketError.new("Connection refused"))
      
      # Should not catch SocketError, so it should propagate
      expect { helper.perform_request_with_retries(uri) }.to raise_error(SocketError)
    end
    
    it "returns response body on successful request" do
      http_double = double("HTTP")
      allow(http_double).to receive(:request).and_return(mock_response)
      allow(Net::HTTP).to receive(:start) do |_, _, _, _, &block|
        block.call http_double
      end
      
      result = helper.perform_request_with_retries(uri)
      expect(result).to eq(sample_response)
    end
  end
end