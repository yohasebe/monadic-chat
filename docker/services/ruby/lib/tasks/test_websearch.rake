# frozen_string_literal: true

namespace :test do
  namespace :websearch do
    desc "Run all native web search tests"
    task :all do
      puts "Running Native Web Search Tests..."
      puts "=" * 60
      
      # Check for required API keys
      providers = {
        "OpenAI" => ENV["OPENAI_API_KEY"] || CONFIG["OPENAI_API_KEY"],
        "Claude" => ENV["ANTHROPIC_API_KEY"] || CONFIG["ANTHROPIC_API_KEY"],
        "Gemini" => ENV["GEMINI_API_KEY"] || CONFIG["GEMINI_API_KEY"],
        "xAI" => ENV["XAI_API_KEY"] || CONFIG["XAI_API_KEY"],
        "Perplexity" => ENV["PERPLEXITY_API_KEY"] || CONFIG["PERPLEXITY_API_KEY"]
      }
      
      puts "\nProvider API Key Status:"
      providers.each do |name, key|
        status = key ? "✓ Configured" : "✗ Not configured"
        puts "  #{name}: #{status}"
      end
      
      configured_count = providers.values.count { |v| v }
      
      if configured_count == 0
        puts "\n⚠️  No API keys configured. Please set at least one provider's API key."
        exit 1
      end
      
      puts "\n#{configured_count} provider(s) configured for testing.\n"
      puts "=" * 60
      
      # Run tests
      sh "bundle exec rspec spec/integration/native_websearch_integration_spec.rb --format documentation"
    end
    
    desc "Run native web search integration tests"
    task :integration do
      puts "Running Integration Tests..."
      sh "bundle exec rspec spec/integration/native_websearch_integration_spec.rb --format documentation"
    end
    
    desc "Run native web search E2E tests (requires running server)"
    task :e2e do
      puts "Running E2E Tests..."
      puts "Note: Server must be running at http://localhost:3000"
      sh "bundle exec rspec spec/e2e/native_websearch_e2e_spec.rb --format documentation"
    end
    
    desc "Run native web search performance tests"
    task :performance do
      puts "Running Performance Tests..."
      sh "bundle exec rspec spec/performance/native_websearch_performance_spec.rb --format documentation"
    end
    
    desc "Run quick smoke test for each provider"
    task :smoke do
      require_relative "../monadic"
      
      puts "\nRunning Native Web Search Smoke Tests"
      puts "=" * 60
      
      test_query = "What is 2+2 and what's the weather like today?"
      
      # Test OpenAI
      if CONFIG["OPENAI_API_KEY"]
        print "Testing OpenAI gpt-4.1-mini... "
        begin
          require_relative "../monadic/adapters/vendors/openai_helper"
          class SmokeOpenAI
            include OpenAIHelper
            def self.name; "OpenAI"; end
          end
          
          helper = SmokeOpenAI.new
          session = {
            messages: [],
            parameters: {
              "model" => "gpt-4.1-mini",
              "message" => test_query,
              "websearch" => true,
              "temperature" => 0.0,
              "max_tokens" => 100,
              "context_size" => 1,
              "app_name" => "test"
            }
          }
          
          responses = []
          helper.api_request("user", session) { |r| responses << r }
          
          if responses.any? { |r| r["type"] == "assistant" }
            puts "✓ Success"
          else
            puts "✗ Failed"
          end
        rescue => e
          puts "✗ Error: #{e.message}"
        end
      end
      
      # Test Claude
      if CONFIG["ANTHROPIC_API_KEY"]
        print "Testing Claude 3.5 Sonnet... "
        begin
          require_relative "../monadic/adapters/vendors/claude_helper"
          class SmokeClaude
            include ClaudeHelper
            def self.name; "Claude"; end
          end
          
          helper = SmokeClaude.new
          session = {
            messages: [],
            parameters: {
              "model" => "claude-sonnet-4-5-20250929",
              "message" => test_query,
              "websearch" => true,
              "temperature" => 0.0,
              "max_tokens" => 100,
              "context_size" => 1,
              "app_name" => "test"
            }
          }
          
          responses = []
          helper.api_request("user", session) { |r| responses << r }
          
          if responses.any? { |r| r["type"] == "assistant" }
            puts "✓ Success"
          else
            puts "✗ Failed"
          end
        rescue => e
          puts "✗ Error: #{e.message}"
        end
      end
      
      # Test Gemini
      if CONFIG["GEMINI_API_KEY"]
        print "Testing Gemini 2.5 Flash... "
        begin
          require_relative "../monadic/adapters/vendors/gemini_helper"
          class SmokeGemini
            include GeminiHelper
            def self.name; "Gemini"; end
          end
          
          helper = SmokeGemini.new
          session = {
            messages: [],
            parameters: {
              "model" => "gemini-2.5-flash",
              "message" => test_query,
              "websearch" => true,
              "temperature" => 0.0,
              "max_tokens" => 100,
              "context_size" => 1,
              "app_name" => "test",
              "reasoning_effort" => "minimal"
            }
          }
          
          responses = []
          helper.api_request("user", session) { |r| responses << r }
          
          if responses.any? { |r| r["type"] == "assistant" }
            puts "✓ Success"
          else
            puts "✗ Failed"
          end
        rescue => e
          puts "✗ Error: #{e.message}"
        end
      end
      
      # Test xAI
      if CONFIG["XAI_API_KEY"]
        print "Testing xAI Grok... "
        begin
          require_relative "../monadic/adapters/vendors/grok_helper"
          class SmokeGrok
            include GrokHelper
            def self.name; "Grok"; end
          end
          
          helper = SmokeGrok.new
          session = {
            messages: [],
            parameters: {
              "model" => "grok-4-fast-reasoning",
              "message" => test_query,
              "websearch" => true,
              "temperature" => 0.0,
              "max_tokens" => 100,
              "context_size" => 1,
              "app_name" => "test"
            }
          }
          
          responses = []
          helper.api_request("user", session) { |r| responses << r }
          
          if responses.any? { |r| r["type"] == "assistant" }
            puts "✓ Success"
          else
            puts "✗ Failed"
          end
        rescue => e
          puts "✗ Error: #{e.message}"
        end
      end
      
      puts "=" * 60
      puts "Smoke tests complete!"
    end
    
    desc "Generate web search test report"
    task :report do
      puts "\nGenerating Native Web Search Test Report"
      puts "=" * 60
      
      # Run tests with JSON formatter for parsing
      results = {}
      
      ["integration", "e2e", "performance"].each do |test_type|
        spec_file = "spec/#{test_type}/native_websearch_#{test_type}_spec.rb"
        next unless File.exist?(spec_file)
        
        json_output = `bundle exec rspec #{spec_file} --format json 2>/dev/null`
        begin
          results[test_type] = JSON.parse(json_output)
        rescue
          results[test_type] = { "summary" => { "example_count" => 0, "failure_count" => 0 } }
        end
      end
      
      # Generate report
      puts "\nTest Results Summary:"
      puts "-" * 40
      
      total_examples = 0
      total_failures = 0
      
      results.each do |test_type, data|
        summary = data["summary"] || {}
        examples = summary["example_count"] || 0
        failures = summary["failure_count"] || 0
        
        total_examples += examples
        total_failures += failures
        
        status = failures == 0 ? "✓" : "✗"
        puts "#{test_type.capitalize}: #{status} #{examples} tests, #{failures} failures"
      end
      
      puts "-" * 40
      puts "Total: #{total_examples} tests, #{total_failures} failures"
      
      success_rate = total_examples > 0 ? ((total_examples - total_failures).to_f / total_examples * 100) : 0
      puts "Success Rate: #{'%.1f' % success_rate}%"
      
      puts "\nProvider Coverage:"
      puts "-" * 40
      
      providers = ["OpenAI", "Claude", "Gemini", "xAI", "Perplexity"]
      providers.each do |provider|
        key_var = case provider
                  when "OpenAI" then "OPENAI_API_KEY"
                  when "Claude" then "ANTHROPIC_API_KEY"
                  when "Gemini" then "GEMINI_API_KEY"
                  when "xAI" then "XAI_API_KEY"
                  when "Perplexity" then "PERPLEXITY_API_KEY"
                  end
        
        configured = CONFIG[key_var] ? "✓" : "✗"
        search_type = case provider
                     when "OpenAI" then "web_search_preview"
                     when "Claude" then "web_search_20250305"
                     when "Gemini" then "url_context"
                     when "xAI" then "live_search"
                     when "Perplexity" then "built_in"
                     end
        
        puts "#{provider}: #{configured} (#{search_type})"
      end
      
      puts "=" * 60
    end
  end
end

desc "Run native web search tests (alias for test:websearch:all)"
task test_websearch: "test:websearch:all"
