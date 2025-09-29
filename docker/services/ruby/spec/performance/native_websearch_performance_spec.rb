# frozen_string_literal: true

require "spec_helper"
require "benchmark"

# Performance tests for native web search implementations
RSpec.describe "Native Web Search Performance", :performance do
  before(:all) do
    @results = {}
  end
  
  after(:all) do
    # Print performance summary
    puts "\n" + "=" * 60
    puts "Native Web Search Performance Summary"
    puts "=" * 60
    
    @results.each do |provider, metrics|
      puts "\n#{provider}:"
      metrics.each do |metric, value|
        case metric
        when :response_time
          puts "  Response Time: #{'%.2f' % value}s"
        when :tokens_used
          puts "  Tokens Used: #{value}"
        when :search_latency
          puts "  Search Latency: #{'%.2f' % value}s"
        when :success_rate
          puts "  Success Rate: #{'%.1f' % (value * 100)}%"
        end
      end
    end
    puts "=" * 60
  end

  describe "Response Time Comparison" do
    let(:test_queries) do
      [
        "What is the current weather in New York?",
        "Latest news about artificial intelligence",
        "Stock price of Apple Inc today",
        "Recent scientific discoveries in 2025",
        "Current events in technology"
      ]
    end
    
    it "measures OpenAI web search performance" do
      skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
      
      require_relative "../../lib/monadic/adapters/vendors/openai_helper"
      
      class PerfTestOpenAI
        include OpenAIHelper
        def self.name; "OpenAI"; end
      end
      
      helper = PerfTestOpenAI.new
      times = []
      successes = 0
      
      test_queries.first(3).each do |query|
        session = create_test_session("gpt-4.1-mini", query, websearch: true)
        
        time = Benchmark.realtime do
          responses = []
          helper.api_request("user", session) do |response|
            responses << response
          end
          successes += 1 if responses.any? { |r| r["type"] == "assistant" }
        end
        
        times << time
        sleep 1  # Rate limiting
      end
      
      @results["OpenAI"] = {
        response_time: times.sum / times.length,
        success_rate: successes.to_f / test_queries.first(3).length
      }
      
      expect(times.sum / times.length).to be < 15  # Average under 15 seconds
    end
    
    it "measures Claude web search performance" do
      skip "Claude API key not configured" unless CONFIG["ANTHROPIC_API_KEY"]
      
      require_relative "../../lib/monadic/adapters/vendors/claude_helper"
      
      class PerfTestClaude
        include ClaudeHelper
        def self.name; "Claude"; end
      end
      
      helper = PerfTestClaude.new
      times = []
      successes = 0
      
      test_queries.first(3).each do |query|
        session = create_test_session("claude-sonnet-4-5-20250929", query, websearch: true)
        
        time = Benchmark.realtime do
          responses = []
          helper.api_request("user", session) do |response|
            responses << response
          end
          successes += 1 if responses.any? { |r| r["type"] == "assistant" }
        end
        
        times << time
        sleep 1  # Rate limiting
      end
      
      @results["Claude"] = {
        response_time: times.sum / times.length,
        success_rate: successes.to_f / test_queries.first(3).length
      }
      
      expect(times.sum / times.length).to be < 20  # Average under 20 seconds
    end
    
    it "measures xAI Live Search performance" do
      skip "xAI API key not configured" unless CONFIG["XAI_API_KEY"]
      
      require_relative "../../lib/monadic/adapters/vendors/grok_helper"
      
      class PerfTestGrok
        include GrokHelper
        def self.name; "Grok"; end
      end
      
      helper = PerfTestGrok.new
      times = []
      successes = 0
      
      test_queries.first(3).each do |query|
        session = create_test_session("grok-4-fast-reasoning", query, websearch: true)
        
        time = Benchmark.realtime do
          responses = []
          helper.api_request("user", session) do |response|
            responses << response
          end
          successes += 1 if responses.any? { |r| r["type"] == "assistant" }
        end
        
        times << time
        sleep 1  # Rate limiting
      end
      
      @results["xAI"] = {
        response_time: times.sum / times.length,
        success_rate: successes.to_f / test_queries.first(3).length
      }
      
      expect(times.sum / times.length).to be < 25  # Average under 25 seconds
    end
    
    it "measures Gemini URL Context performance" do
      skip "Gemini API key not configured" unless CONFIG["GEMINI_API_KEY"]
      
      require_relative "../../lib/monadic/adapters/vendors/gemini_helper"
      
      class PerfTestGemini
        include GeminiHelper
        def self.name; "Gemini"; end
      end
      
      helper = PerfTestGemini.new
      times = []
      successes = 0
      
      test_queries.first(3).each do |query|
        session = create_test_session("gemini-2.5-flash", query, 
                                     websearch: true, 
                                     reasoning_effort: "minimal")
        
        time = Benchmark.realtime do
          responses = []
          helper.api_request("user", session) do |response|
            responses << response
          end
          successes += 1 if responses.any? { |r| r["type"] == "assistant" }
        end
        
        times << time
        sleep 1  # Rate limiting
      end
      
      @results["Gemini"] = {
        response_time: times.sum / times.length,
        success_rate: successes.to_f / test_queries.first(3).length
      }
      
      expect(times.sum / times.length).to be < 20  # Average under 20 seconds
    end
  end
  
  describe "Search Quality Metrics" do
    it "evaluates search result relevance" do
      skip "Skipping quality metrics in CI" if ENV["CI"]
      
      query = "Current CEO of Microsoft"
      expected_content = ["satya", "nadella", "microsoft", "ceo"]
      
      providers = []
      
      if CONFIG["OPENAI_API_KEY"]
        providers << { name: "OpenAI", model: "gpt-4.1-mini", helper_class: "OpenAIHelper" }
      end
      
      if CONFIG["ANTHROPIC_API_KEY"]
        providers << { name: "Claude", model: "claude-sonnet-4-5-20250929", helper_class: "ClaudeHelper" }
      end
      
      if CONFIG["GEMINI_API_KEY"]
        providers << { name: "Gemini", model: "gemini-2.5-flash", helper_class: "GeminiHelper" }
      end
      
      providers.each do |provider|
        require_relative "../../lib/monadic/adapters/vendors/#{provider[:helper_class].downcase.sub('helper', '_helper')}"
        
        helper_module = Object.const_get(provider[:helper_class])
        test_class = Class.new do
          include helper_module
          define_singleton_method(:name) { provider[:name] }
        end
        
        helper = test_class.new
        session = create_test_session(provider[:model], query, websearch: true)
        
        responses = []
        helper.api_request("user", session) do |response|
          responses << response
        end
        
        final_response = responses.find { |r| r["type"] == "assistant" }
        
        if final_response
          content = final_response["content"]["text"].downcase
          matches = expected_content.count { |term| content.include?(term) }
          relevance = matches.to_f / expected_content.length
          
          @results["#{provider[:name]}_quality"] = {
            relevance_score: relevance
          }
          
          expect(relevance).to be >= 0.5  # At least 50% of expected terms
        end
      end
    end
  end
  
  describe "Concurrent Request Handling" do
    it "handles multiple simultaneous search requests" do
      skip "OpenAI API key not configured" unless CONFIG["OPENAI_API_KEY"]
      skip "Skipping concurrent tests in CI" if ENV["CI"]
      
      require_relative "../../lib/monadic/adapters/vendors/openai_helper"
      
      class ConcurrentTestOpenAI
        include OpenAIHelper
        def self.name; "OpenAI"; end
      end
      
      queries = [
        "Weather in London",
        "Latest sports news",
        "Technology trends 2025"
      ]
      
      threads = []
      results = []
      mutex = Mutex.new
      
      start_time = Time.now
      
      queries.each do |query|
        threads << Thread.new do
          helper = ConcurrentTestOpenAI.new
          session = create_test_session("gpt-4.1-mini", query, websearch: true)
          
          responses = []
          helper.api_request("user", session) do |response|
            responses << response
          end
          
          mutex.synchronize do
            results << {
              query: query,
              success: responses.any? { |r| r["type"] == "assistant" },
              response_count: responses.length
            }
          end
        end
      end
      
      threads.each(&:join)
      total_time = Time.now - start_time
      
      successful = results.count { |r| r[:success] }
      
      @results["OpenAI_concurrent"] = {
        total_time: total_time,
        success_rate: successful.to_f / queries.length,
        queries_per_second: queries.length / total_time
      }
      
      expect(successful).to eq(queries.length)  # All should succeed
      expect(total_time).to be < 30  # Should complete within 30 seconds
    end
  end
  
  describe "Resource Usage" do
    it "monitors memory usage during search operations" do
      skip "Gemini API key not configured" unless CONFIG["GEMINI_API_KEY"]
      skip "Skipping resource monitoring in CI" if ENV["CI"]
      
      require_relative "../../lib/monadic/adapters/vendors/gemini_helper"
      
      class ResourceTestGemini
        include GeminiHelper
        def self.name; "Gemini"; end
      end
      
      helper = ResourceTestGemini.new
      
      # Measure memory before
      GC.start
      memory_before = `ps -o rss= -p #{Process.pid}`.to_i
      
      # Perform searches
      5.times do |i|
        session = create_test_session(
          "gemini-2.5-flash",
          "Search query #{i}: Latest news",
          websearch: true,
          reasoning_effort: "minimal"
        )
        
        helper.api_request("user", session) do |response|
          # Process response
        end
        
        sleep 0.5
      end
      
      # Measure memory after
      GC.start
      memory_after = `ps -o rss= -p #{Process.pid}`.to_i
      
      memory_increase = memory_after - memory_before
      
      @results["Gemini_resources"] = {
        memory_increase_kb: memory_increase,
        memory_increase_mb: memory_increase / 1024.0
      }
      
      # Memory increase should be reasonable (less than 100MB)
      expect(memory_increase / 1024.0).to be < 100
    end
  end
  
  private
  
  def create_test_session(model, message, websearch: true, **extra_params)
    {
      messages: [],
      parameters: {
        "model" => model,
        "message" => message,
        "websearch" => websearch,
        "temperature" => 0.0,
        "max_tokens" => 500,
        "context_size" => 5,
        "app_name" => "test"
      }.merge(extra_params.transform_keys(&:to_s))
    }
  end
end
