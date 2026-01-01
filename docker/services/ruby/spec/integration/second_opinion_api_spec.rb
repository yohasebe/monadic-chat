# frozen_string_literal: true

# Second Opinion Agent API Integration Tests
#
# Tests SecondOpinionAgent with real provider APIs to ensure:
# - max_tokens is correctly applied (responses are not truncated)
# - All providers return complete responses with validity scores
# - Cross-provider second opinions work correctly
#
# Run with:
#   RUN_API=true bundle exec rspec spec/integration/second_opinion_api_spec.rb
#
# Run specific provider:
#   PROVIDERS=gemini RUN_API=true bundle exec rspec spec/integration/second_opinion_api_spec.rb
#
# Run with debug output:
#   DEBUG=true RUN_API=true bundle exec rspec spec/integration/second_opinion_api_spec.rb

require 'spec_helper'
require_relative '../../lib/monadic/agents/second_opinion_agent'

RSpec.describe 'SecondOpinionAgent API Integration', :api, :integration do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include SecondOpinionAgent

      # Provide a default configure_reasoning_params for testing
      def configure_reasoning_params(parameters, model)
        parameters["temperature"] = 0.7
        parameters
      end
    end
  end

  let(:agent) { test_class.new }

  # Provider configuration
  PROVIDER_CONFIG = {
    'openai' => {
      api_key_env: 'OPENAI_API_KEY',
      model: 'gpt-4.1-mini',
      description: 'OpenAI GPT'
    },
    'anthropic' => {
      api_key_env: 'ANTHROPIC_API_KEY',
      model: 'claude-3-haiku-20240307',
      description: 'Anthropic Claude'
    },
    'gemini' => {
      api_key_env: 'GEMINI_API_KEY',
      model: 'gemini-2.0-flash',
      description: 'Google Gemini'
    },
    'xai' => {
      api_key_env: 'XAI_API_KEY',
      model: 'grok-3-fast',
      description: 'xAI Grok'
    },
    'mistral' => {
      api_key_env: 'MISTRAL_API_KEY',
      model: 'mistral-small-latest',
      description: 'Mistral AI'
    },
    'cohere' => {
      api_key_env: 'COHERE_API_KEY',
      model: 'command-a-03-2025',
      description: 'Cohere Command'
    },
    'deepseek' => {
      api_key_env: 'DEEPSEEK_API_KEY',
      model: 'deepseek-chat',
      description: 'DeepSeek'
    },
    'perplexity' => {
      api_key_env: 'PERPLEXITY_API_KEY',
      model: 'sonar',
      description: 'Perplexity Sonar'
    }
  }.freeze

  # Test case that requires detailed evaluation (to test max_tokens)
  # Uses a health/nutrition topic that requires nuanced analysis
  DETAILED_TEST_CASE = {
    user_query: <<~QUERY,
      I've been considering switching to a plant-based diet for health reasons.
      What are the key nutritional considerations I should be aware of?
      Please provide detailed guidance on maintaining proper nutrition.
    QUERY
    agent_response: <<~RESPONSE
      Switching to a plant-based diet can offer many health benefits when done properly.

      ## Key Nutritional Considerations
      1. Protein sources: Combine legumes, nuts, seeds, and whole grains for complete amino acids
      2. Vitamin B12: This is primarily found in animal products, so supplementation is often necessary
      3. Iron: Plant-based iron (non-heme) is less easily absorbed; pair with vitamin C for better absorption
      4. Omega-3 fatty acids: Consider algae-based supplements or include flaxseeds and walnuts

      ## Recommendations
      - Plan meals to include diverse protein sources
      - Consider regular blood tests to monitor nutrient levels
      - Consult with a registered dietitian for personalized guidance
      - Gradually transition rather than making sudden changes

      Research from major health organizations supports well-planned plant-based diets as nutritionally adequate.
    RESPONSE
  }.freeze

  def require_run_api!
    skip('RUN_API is not enabled') unless ENV['RUN_API'] == 'true'
  end

  def providers_from_env
    list = (ENV['PROVIDERS'] || '').split(',').map(&:strip).reject(&:empty?)
    return list unless list.empty?
    PROVIDER_CONFIG.keys
  end

  def api_key_available?(provider)
    config = PROVIDER_CONFIG[provider]
    return false unless config
    env_key = config[:api_key_env]
    key = ENV[env_key]
    key = CONFIG[env_key] if (key.nil? || key.empty?) && defined?(CONFIG)
    key && !key.to_s.empty?
  end

  describe 'Response Completeness (max_tokens validation)' do
    PROVIDER_CONFIG.each do |provider, config|
      context "with #{config[:description]} (#{provider})" do
        before(:each) do
          require_run_api!
          skip("Provider #{provider} not in PROVIDERS list") unless providers_from_env.include?(provider)
          skip("API key not available for #{provider}") unless api_key_available?(provider)
        end

        it "returns complete response with validity score (not truncated)" do
          result = agent.second_opinion_agent(
            user_query: DETAILED_TEST_CASE[:user_query],
            agent_response: DETAILED_TEST_CASE[:agent_response],
            provider: provider,
            model: config[:model]
          )

          # Basic structure validation
          expect(result).to be_a(Hash), "Expected Hash result from #{provider}"
          expect(result[:comments]).to be_a(String), "Expected String comments from #{provider}"
          expect(result[:comments].strip).not_to be_empty, "Expected non-empty comments from #{provider}"

          # Validate response is complete (not truncated)
          # "incomplete" validity indicates the response was cut off
          expect(result[:validity]).not_to eq("incomplete"),
            "#{provider} response was truncated (validity=incomplete). " \
            "This indicates max_tokens is too low. Comments: #{result[:comments][0..200]}..."

          # Validate validity score format (X/10 or error)
          validity = result[:validity]
          is_valid_format = validity.match?(/^\d+\/10$/) ||
                           validity == "error" ||
                           validity == "unknown"

          expect(is_valid_format).to be(true),
            "#{provider} validity should be 'X/10', 'error', or 'unknown', got: #{validity}"

          # Log results for debugging
          if ENV['DEBUG']
            puts "\n  [#{provider}] Second Opinion result:"
            puts "    validity: #{result[:validity]}"
            puts "    model: #{result[:model]}"
            puts "    comments length: #{result[:comments].length} chars"
            puts "    comments preview: #{result[:comments][0..100]}..."
          end
        end

        it "returns complete response for simple query" do
          result = agent.second_opinion_agent(
            user_query: "What is 2 + 2?",
            agent_response: "2 + 2 equals 4",
            provider: provider,
            model: config[:model]
          )

          expect(result[:comments]).to be_a(String)
          expect(result[:comments].strip).not_to be_empty
          expect(result[:validity]).not_to eq("incomplete"),
            "#{provider} response truncated even for simple query"

          # Model should be correctly reported (format: "provider:model")
          # Normalize provider name for comparison
          normalized_provider = case provider
                               when 'anthropic' then 'claude'
                               when 'xai' then 'grok'
                               else provider
                               end
          model_correctly_reported = result[:model].include?(normalized_provider) ||
                                     result[:model].include?(config[:model])
          expect(model_correctly_reported).to be(true),
            "#{provider} model should be reported correctly, got: #{result[:model]}"
        end
      end
    end
  end

  describe 'Cross-Provider Second Opinion' do
    # Test getting second opinion from a different provider
    context 'when requesting second opinion across providers' do
      before(:each) do
        require_run_api!
      end

      it "xAI app can get complete second opinion from Gemini" do
        skip("Gemini API key not available") unless api_key_available?('gemini')
        skip("Provider gemini not in PROVIDERS list") unless providers_from_env.include?('gemini')

        result = agent.second_opinion_agent(
          user_query: "Is water safe to drink in developing countries?",
          agent_response: "Generally, you should avoid tap water in developing countries.",
          provider: "gemini",
          model: "gemini-2.0-flash"
        )

        expect(result[:validity]).not_to eq("incomplete"),
          "Cross-provider Gemini response was truncated"
        expect(result[:model]).to include("gemini")

        if ENV['DEBUG']
          puts "\n  [Cross-provider: Gemini] Result:"
          puts "    validity: #{result[:validity]}"
          puts "    comments length: #{result[:comments].length} chars"
        end
      end

      it "can get complete second opinion from Cohere" do
        skip("Cohere API key not available") unless api_key_available?('cohere')
        skip("Provider cohere not in PROVIDERS list") unless providers_from_env.include?('cohere')

        result = agent.second_opinion_agent(
          user_query: "What programming language should I learn first?",
          agent_response: "Python is a great first programming language due to its simple syntax.",
          provider: "cohere",
          model: "command-a-03-2025"
        )

        # Cohere had very low default max_tokens (300), this test ensures fix works
        expect(result[:validity]).not_to eq("incomplete"),
          "Cohere response was truncated (previously had 300 token default)"
        expect(result[:model]).to include("cohere")
      end
    end
  end

  describe 'Error Handling' do
    # Note: Input validation (empty query/response) is handled by the app classes
    # (SecondOpinionGrok, SecondOpinionOpenAI, etc.), not by the module directly.
    # The module-level tests here focus on provider validation.

    it "raises error for unknown provider" do
      # Unknown provider raises RuntimeError in get_provider_helper
      expect {
        agent.second_opinion_agent(
          user_query: "Test query",
          agent_response: "Test response",
          provider: "unknown_provider_xyz",
          model: "some-model"
        )
      }.to raise_error(RuntimeError, /Unknown provider/)
    end
  end

  describe 'Provider Helper Validation' do
    it "all providers have helpers that respond to send_query" do
      PROVIDER_CONFIG.keys.each do |provider|
        # Normalize provider name as the agent would
        normalized = case provider
                     when 'anthropic' then 'claude'
                     when 'xai' then 'grok'
                     else provider
                     end

        helper = agent.send(:get_provider_helper, normalized)
        expect(helper).to respond_to(:send_query),
          "#{provider} helper should respond to send_query"
      end
    end
  end

  describe 'max_tokens Parameter Verification' do
    # This test verifies that the max_tokens parameter in SecondOpinionAgent
    # is actually being used by checking the parameters hash

    it "includes max_tokens in parameters" do
      # We can't easily intercept the API call, but we can verify
      # the agent module sets up parameters correctly
      # by checking that responses are complete

      require_run_api!
      skip("OpenAI API key not available") unless api_key_available?('openai')
      skip("Provider openai not in PROVIDERS list") unless providers_from_env.include?('openai')

      # Use a query that requires a detailed response
      result = agent.second_opinion_agent(
        user_query: DETAILED_TEST_CASE[:user_query],
        agent_response: DETAILED_TEST_CASE[:agent_response],
        provider: "openai",
        model: "gpt-4.1-mini"
      )

      # If max_tokens is working, we should get a complete response
      # The comments should be substantial (not cut off)
      expect(result[:comments].length).to be > 100,
        "OpenAI response too short, may indicate max_tokens issue"

      expect(result[:validity]).to match(/^\d+\/10$/),
        "OpenAI should return valid X/10 score, got: #{result[:validity]}"
    end
  end
end
