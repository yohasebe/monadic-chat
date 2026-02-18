# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../lib/monadic/shared_tools/parallel_dispatch"

# Mock MonadicHelper if not loaded
module MonadicHelper
end unless defined?(MonadicHelper)

# Mock WebSocketHelper if not loaded
module WebSocketHelper
  def self.send_progress_fragment(fragment, session_id = nil)
  end
end unless defined?(WebSocketHelper)

# Integration tests for ParallelDispatch web search sub_call methods.
# Tests real API calls to verify request format and response parsing.
#
# Run with: RUN_API=true bundle exec rspec spec/integration/parallel_dispatch_websearch_spec.rb
RSpec.describe "ParallelDispatch Web Search Integration", :integration do
  include IntegrationRetryHelper

  let(:test_class) do
    Class.new do
      include MonadicSharedTools::ParallelDispatch

      public :responses_api_sub_call, :gemini_websearch_sub_call,
             :anthropic_websearch_sub_call, :tavily_prefetch_and_inject,
             :openai_compat_sub_call, :cohere_sub_call
    end
  end

  let(:app) { test_class.new }
  let(:timeout) { 60 }
  let(:query) { "What is the capital of France? Answer in one sentence." }

  before(:all) do
    @skip_api = ENV["RUN_API"] != "true"
  end

  # --- OpenAI Responses API ---
  describe "OpenAI responses_api_sub_call" do
    before do
      skip "RUN_API not set" if @skip_api
      skip "OPENAI_API_KEY not configured" unless CONFIG["OPENAI_API_KEY"] && !CONFIG["OPENAI_API_KEY"].empty?
    end

    it "returns web-search-augmented text from OpenAI" do
      with_api_retry(max_attempts: 2, wait: 3, backoff: :exponential) do
        result = app.responses_api_sub_call(
          "https://api.openai.com/v1/responses",
          CONFIG["OPENAI_API_KEY"],
          "gpt-4.1-mini",
          query,
          timeout
        )

        expect(result).to be_a(String)
        expect(result).not_to be_empty
        expect(result.downcase).to match(/paris/)
      end
    end
  end

  # --- Grok (xAI) Responses API ---
  describe "Grok responses_api_sub_call" do
    before do
      skip "RUN_API not set" if @skip_api
      skip "XAI_API_KEY not configured" unless CONFIG["XAI_API_KEY"] && !CONFIG["XAI_API_KEY"].empty?
    end

    it "returns web-search-augmented text from Grok" do
      with_api_retry(max_attempts: 2, wait: 3, backoff: :exponential) do
        result = app.responses_api_sub_call(
          "https://api.x.ai/v1/responses",
          CONFIG["XAI_API_KEY"],
          "grok-4-fast-non-reasoning",
          query,
          timeout
        )

        expect(result).to be_a(String)
        expect(result).not_to be_empty
        expect(result.downcase).to match(/paris/)
      end
    end
  end

  # --- Gemini grounding ---
  describe "Gemini gemini_websearch_sub_call" do
    before do
      skip "RUN_API not set" if @skip_api
      skip "GEMINI_API_KEY not configured" unless CONFIG["GEMINI_API_KEY"] && !CONFIG["GEMINI_API_KEY"].empty?
    end

    it "returns grounded text from Gemini" do
      with_api_retry(max_attempts: 2, wait: 3, backoff: :exponential) do
        result = app.gemini_websearch_sub_call(
          "https://generativelanguage.googleapis.com/v1beta",
          CONFIG["GEMINI_API_KEY"],
          "gemini-2.5-flash",
          query,
          timeout
        )

        expect(result).to be_a(String)
        expect(result).not_to be_empty
        expect(result.downcase).to match(/paris/)
      end
    end
  end

  # --- Claude native web search ---
  describe "Claude anthropic_websearch_sub_call" do
    before do
      skip "RUN_API not set" if @skip_api
      skip "ANTHROPIC_API_KEY not configured" unless CONFIG["ANTHROPIC_API_KEY"] && !CONFIG["ANTHROPIC_API_KEY"].empty?
    end

    it "returns web-search-augmented text from Claude" do
      with_api_retry(max_attempts: 2, wait: 3, backoff: :exponential) do
        result = app.anthropic_websearch_sub_call(
          "https://api.anthropic.com/v1/messages",
          CONFIG["ANTHROPIC_API_KEY"],
          "claude-sonnet-4-6",
          query,
          timeout
        )

        expect(result).to be_a(String)
        expect(result).not_to be_empty
        expect(result.downcase).to match(/paris/)
      end
    end
  end

  # --- Perplexity (native search, uses openai_compat_sub_call) ---
  describe "Perplexity openai_compat_sub_call" do
    before do
      skip "RUN_API not set" if @skip_api
      skip "PERPLEXITY_API_KEY not configured" unless CONFIG["PERPLEXITY_API_KEY"] && !CONFIG["PERPLEXITY_API_KEY"].empty?
    end

    it "returns search-augmented text from Perplexity" do
      with_api_retry(max_attempts: 2, wait: 3, backoff: :exponential) do
        result = app.openai_compat_sub_call(
          "https://api.perplexity.ai/chat/completions",
          CONFIG["PERPLEXITY_API_KEY"],
          "sonar",
          query,
          timeout
        )

        expect(result).to be_a(String)
        expect(result).not_to be_empty
        expect(result.downcase).to match(/paris/)
      end
    end
  end

  # --- Tavily prefetch ---
  describe "Tavily tavily_prefetch_and_inject" do
    before do
      skip "RUN_API not set" if @skip_api
      skip "TAVILY_API_KEY not configured" unless CONFIG["TAVILY_API_KEY"] && !CONFIG["TAVILY_API_KEY"].empty?
    end

    it "injects search results into prompt" do
      with_api_retry(max_attempts: 2, wait: 3, backoff: :exponential) do
        result = app.tavily_prefetch_and_inject("capital of France")

        expect(result).to be_a(String)
        expect(result).to include("=== Web Search Results ===")
        expect(result).to include("capital of France")
        # Should contain at least one search result with a URL
        expect(result).to match(%r{https?://})
      end
    end
  end

  # --- Mistral via Tavily + openai_compat ---
  describe "Mistral with Tavily prefetch" do
    before do
      skip "RUN_API not set" if @skip_api
      skip "MISTRAL_API_KEY not configured" unless CONFIG["MISTRAL_API_KEY"] && !CONFIG["MISTRAL_API_KEY"].empty?
      skip "TAVILY_API_KEY not configured" unless CONFIG["TAVILY_API_KEY"] && !CONFIG["TAVILY_API_KEY"].empty?
    end

    it "returns text after Tavily-enriched prompt" do
      with_api_retry(max_attempts: 2, wait: 3, backoff: :exponential) do
        enriched = app.tavily_prefetch_and_inject(query)
        result = app.openai_compat_sub_call(
          "https://api.mistral.ai/v1/chat/completions",
          CONFIG["MISTRAL_API_KEY"],
          "mistral-small-latest",
          enriched,
          timeout
        )

        expect(result).to be_a(String)
        expect(result).not_to be_empty
        expect(result.downcase).to match(/paris/)
      end
    end
  end

  # --- DeepSeek via Tavily + openai_compat ---
  describe "DeepSeek with Tavily prefetch" do
    before do
      skip "RUN_API not set" if @skip_api
      skip "DEEPSEEK_API_KEY not configured" unless CONFIG["DEEPSEEK_API_KEY"] && !CONFIG["DEEPSEEK_API_KEY"].empty?
      skip "TAVILY_API_KEY not configured" unless CONFIG["TAVILY_API_KEY"] && !CONFIG["TAVILY_API_KEY"].empty?
    end

    it "returns text after Tavily-enriched prompt" do
      with_api_retry(max_attempts: 2, wait: 3, backoff: :exponential) do
        enriched = app.tavily_prefetch_and_inject(query)
        result = app.openai_compat_sub_call(
          "https://api.deepseek.com/chat/completions",
          CONFIG["DEEPSEEK_API_KEY"],
          "deepseek-chat",
          enriched,
          timeout
        )

        expect(result).to be_a(String)
        expect(result).not_to be_empty
        expect(result.downcase).to match(/paris/)
      end
    end
  end

  # --- Cohere via Tavily + cohere_sub_call ---
  describe "Cohere with Tavily prefetch" do
    before do
      skip "RUN_API not set" if @skip_api
      skip "COHERE_API_KEY not configured" unless CONFIG["COHERE_API_KEY"] && !CONFIG["COHERE_API_KEY"].empty?
      skip "TAVILY_API_KEY not configured" unless CONFIG["TAVILY_API_KEY"] && !CONFIG["TAVILY_API_KEY"].empty?
    end

    it "returns text after Tavily-enriched prompt" do
      with_api_retry(max_attempts: 2, wait: 3, backoff: :exponential) do
        enriched = app.tavily_prefetch_and_inject(query)
        result = app.cohere_sub_call(
          "https://api.cohere.ai/v2/chat",
          CONFIG["COHERE_API_KEY"],
          "command-a-03-2025",
          enriched,
          timeout
        )

        expect(result).to be_a(String)
        expect(result).not_to be_empty
        expect(result.downcase).to match(/paris/)
      end
    end
  end
end
