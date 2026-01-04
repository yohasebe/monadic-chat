# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Gemini Internal Web Search Agent" do
  # Test the gemini_web_search internal agent that allows web search
  # to work alongside function declarations in Gemini 3

  let(:helper_instance) do
    Class.new do
      include GeminiHelper

      attr_accessor :settings

      def initialize
        @settings = {}
      end
    end.new
  end

  before do
    stub_const("CONFIG", { "GEMINI_API_KEY" => "test_api_key" })
  end

  describe "GeminiHelper.internal_web_search" do
    context "when API key is not configured" do
      before do
        stub_const("CONFIG", { "GEMINI_API_KEY" => nil })
      end

      it "returns an error when API key is missing" do
        result = GeminiHelper.internal_web_search(query: "test query")
        expect(result[:error]).to eq("GEMINI_API_KEY not configured")
      end
    end

    context "when API key is configured" do
      let(:mock_response_body) do
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => "Search results for your query..." }
                ]
              },
              "groundingMetadata" => {
                "webSearchQueries" => ["test query"],
                "groundingChunks" => [
                  {
                    "web" => {
                      "title" => "Example Source",
                      "uri" => "https://example.com/article"
                    }
                  }
                ]
              }
            }
          ]
        }.to_json
      end

      it "makes a request with google_search grounding only" do
        # Stub HTTP request
        http_double = instance_double(HTTP::Client)
        response_double = instance_double(HTTP::Response,
          status: instance_double(HTTP::Response::Status, success?: true),
          body: mock_response_body
        )

        allow(HTTP).to receive(:headers).and_return(http_double)
        allow(http_double).to receive(:timeout).and_return(http_double)
        allow(http_double).to receive(:post).and_return(response_double)

        result = GeminiHelper.internal_web_search(query: "test query")

        expect(result[:success]).to be true
        expect(result[:content]).to include("Search results")
        expect(result[:sources]).to be_an(Array)
        expect(result[:query]).to eq("test query")
      end

      it "extracts grounding metadata correctly" do
        http_double = instance_double(HTTP::Client)
        response_double = instance_double(HTTP::Response,
          status: instance_double(HTTP::Response::Status, success?: true),
          body: mock_response_body
        )

        allow(HTTP).to receive(:headers).and_return(http_double)
        allow(http_double).to receive(:timeout).and_return(http_double)
        allow(http_double).to receive(:post).and_return(response_double)

        result = GeminiHelper.internal_web_search(query: "test query")

        expect(result[:sources]).to include(
          hash_including("queries" => ["test query"])
        )
        expect(result[:sources]).to include(
          hash_including("title" => "Example Source", "uri" => "https://example.com/article")
        )
      end

      it "handles API errors gracefully" do
        error_response = { "error" => { "message" => "Rate limit exceeded" } }.to_json
        http_double = instance_double(HTTP::Client)
        response_double = instance_double(HTTP::Response,
          status: instance_double(HTTP::Response::Status, success?: false),
          body: error_response
        )

        allow(HTTP).to receive(:headers).and_return(http_double)
        allow(http_double).to receive(:timeout).and_return(http_double)
        allow(http_double).to receive(:post).and_return(response_double)

        result = GeminiHelper.internal_web_search(query: "test query")

        expect(result[:success]).to be false
        expect(result[:error]).to include("Rate limit exceeded")
      end

      it "handles network errors gracefully" do
        http_double = instance_double(HTTP::Client)

        allow(HTTP).to receive(:headers).and_return(http_double)
        allow(http_double).to receive(:timeout).and_return(http_double)
        allow(http_double).to receive(:post).and_raise(HTTP::TimeoutError.new("Connection timed out"))

        result = GeminiHelper.internal_web_search(query: "test query")

        expect(result[:success]).to be false
        expect(result[:error]).to include("Request failed")
      end
    end
  end

  describe "#gemini_web_search instance method" do
    let(:mock_internal_result) do
      {
        success: true,
        content: "Search results about Ruby programming...",
        sources: [
          { "queries" => ["ruby programming"] },
          { "title" => "Ruby Docs", "uri" => "https://ruby-doc.org" }
        ],
        query: "ruby programming"
      }
    end

    it "formats results for tool response" do
      allow(GeminiHelper).to receive(:internal_web_search).and_return(mock_internal_result)

      result = helper_instance.gemini_web_search(query: "ruby programming")

      expect(result).to be_a(Hash)
      expect(result["query"]).to eq("ruby programming")
      expect(result["answer"]).to eq("Search results about Ruby programming...")
      expect(result["results"]).to be_an(Array)
      expect(result["websearch_agent"]).to eq("gemini_internal")
    end

    it "handles errors from internal search" do
      error_result = { success: false, error: "API Error", query: "test" }
      allow(GeminiHelper).to receive(:internal_web_search).and_return(error_result)

      result = helper_instance.gemini_web_search(query: "test")

      expect(result["error"]).to eq("API Error")
      expect(result["query"]).to eq("test")
    end
  end
end
