# frozen_string_literal: true

# Context Extractor API Integration Tests
#
# Tests ContextExtractorAgent with real provider APIs to ensure:
# - Context extraction works across all supported providers
# - Reasoning models are handled correctly (Cohere, DeepSeek, Gemini thinking)
# - Response parsing works with actual API responses
#
# Run with:
#   RUN_API=true bundle exec rspec spec/integration/context_extractor_api_spec.rb
#
# Run specific provider:
#   PROVIDERS=cohere RUN_API=true bundle exec rspec spec/integration/context_extractor_api_spec.rb
#
# Run with debug output:
#   DEBUG=true PROVIDERS=anthropic RUN_API=true bundle exec rspec spec/integration/context_extractor_api_spec.rb

require 'spec_helper'
require_relative '../../lib/monadic/agents/context_extractor_agent'
require_relative '../../lib/monadic/utils/system_defaults'

RSpec.describe 'ContextExtractorAgent API Integration', :api, :integration do
  include ContextExtractorAgent

  # Provider configuration with expected default models
  PROVIDER_CONFIG = {
    'openai' => { api_key_env: 'OPENAI_API_KEY' },
    'anthropic' => { api_key_env: 'ANTHROPIC_API_KEY' },
    'gemini' => { api_key_env: 'GEMINI_API_KEY' },
    'xai' => { api_key_env: 'XAI_API_KEY' },
    'mistral' => { api_key_env: 'MISTRAL_API_KEY' },
    'cohere' => { api_key_env: 'COHERE_API_KEY' },
    'deepseek' => { api_key_env: 'DEEPSEEK_API_KEY' }
    # Ollama excluded - requires local setup
  }.freeze

  # Test conversations for context extraction
  TEST_CONVERSATIONS = {
    simple: {
      user_message: "I'm learning Python programming. My friend Alice recommended a book about machine learning.",
      assistant_response: "That's great! Python is an excellent choice for machine learning. Alice gave you good advice. I'd suggest starting with NumPy and Pandas for data manipulation.",
      expected_fields: {
        topics: ['Python', 'machine learning'],
        people: ['Alice'],
        notes: []
      }
    },
    japanese: {
      user_message: "東京に住んでいる田中さんと来週会議があります。",
      assistant_response: "田中さんとの会議ですね。東京でのミーティングの準備をお手伝いしましょうか？",
      expected_fields: {
        topics: ['会議', 'ミーティング'],
        people: ['田中'],
        notes: []
      }
    }
  }.freeze

  def require_run_api!
    skip('RUN_API is not enabled') unless ENV['RUN_API'] == 'true'
  end

  def providers_from_env
    list = (ENV['PROVIDERS'] || '').split(',').map(&:strip).reject(&:empty?)
    return list unless list.empty?
    # Default: test all providers with API keys
    PROVIDER_CONFIG.keys
  end

  def api_key_available?(provider)
    config = PROVIDER_CONFIG[provider]
    return false unless config
    env_key = config[:api_key_env]
    # Check both ENV and CONFIG (CONFIG is loaded from ~/monadic/config/env)
    key = ENV[env_key]
    key = CONFIG[env_key] if (key.nil? || key.empty?) && defined?(CONFIG)
    key && !key.to_s.empty?
  end

  describe 'Context Extraction API Calls' do
    PROVIDER_CONFIG.each do |provider, _config|
      context "with #{provider} provider" do
        before(:each) do
          require_run_api!
          skip("Provider #{provider} not in PROVIDERS list") unless providers_from_env.include?(provider)
          skip("API key not available for #{provider}") unless api_key_available?(provider)
        end

        it "extracts context from simple English conversation" do
          test_data = TEST_CONVERSATIONS[:simple]
          session = { messages: [], runtime_settings: { language: 'en' } }

          result = extract_context(
            session,
            test_data[:user_message],
            test_data[:assistant_response],
            provider
          )

          # Basic validation - should return a hash with expected fields
          expect(result).to be_a(Hash), "Expected Hash result from #{provider}, got #{result.class}"

          # Check that expected field keys exist (support both string and symbol keys)
          has_topics = result.key?('topics') || result.key?(:topics)
          has_people = result.key?('people') || result.key?(:people)
          has_notes = result.key?('notes') || result.key?(:notes)

          expect(has_topics).to be(true),
            "#{provider} result should have topics field: #{result.inspect}"
          expect(has_people).to be(true),
            "#{provider} result should have people field: #{result.inspect}"
          expect(has_notes).to be(true),
            "#{provider} result should have notes field: #{result.inspect}"

          # Log results for debugging
          if ENV['DEBUG']
            puts "\n  [#{provider}] Context extraction result:"
            puts "    topics: #{result['topics'] || result[:topics]}"
            puts "    people: #{result['people'] || result[:people]}"
            puts "    notes: #{result['notes'] || result[:notes]}"
          end

          # Verify at least one field has content (extraction worked)
          topics = result['topics'] || result[:topics] || []
          people = result['people'] || result[:people] || []
          notes = result['notes'] || result[:notes] || []

          has_content = topics.any? || people.any? || notes.any?
          expect(has_content).to be(true),
            "#{provider} should extract at least some context from the conversation"
        end

        it "extracts context from Japanese conversation" do
          test_data = TEST_CONVERSATIONS[:japanese]
          session = { messages: [], runtime_settings: { language: 'ja' } }

          result = extract_context(
            session,
            test_data[:user_message],
            test_data[:assistant_response],
            provider
          )

          expect(result).to be_a(Hash), "Expected Hash result from #{provider} for Japanese"

          # Check structure
          has_topics = result.key?('topics') || result.key?(:topics)
          has_people = result.key?('people') || result.key?(:people)
          expect(has_topics).to be(true), "#{provider} Japanese result should have topics field"
          expect(has_people).to be(true), "#{provider} Japanese result should have people field"

          if ENV['DEBUG']
            puts "\n  [#{provider}] Japanese context extraction:"
            puts "    topics: #{result['topics'] || result[:topics]}"
            puts "    people: #{result['people'] || result[:people]}"
          end
        end

        it "handles custom context schema" do
          custom_schema = {
            fields: [
              { name: 'keywords', icon: 'fa-key', label: 'Keywords', description: 'Important keywords from the conversation' },
              { name: 'actions', icon: 'fa-tasks', label: 'Actions', description: 'Action items or tasks mentioned' }
            ]
          }

          session = { messages: [], runtime_settings: { language: 'en' } }
          user_msg = "Please schedule a meeting with the design team next Tuesday to discuss the new logo."
          assistant_msg = "I'll help you schedule that meeting. The design team meeting for the logo discussion is noted for next Tuesday."

          result = extract_context(
            session,
            user_msg,
            assistant_msg,
            provider,
            custom_schema
          )

          expect(result).to be_a(Hash), "Expected Hash result from #{provider} with custom schema"

          # Should have custom schema fields
          has_keywords = result.key?('keywords') || result.key?(:keywords)
          has_actions = result.key?('actions') || result.key?(:actions)
          expect(has_keywords).to be(true),
            "#{provider} should extract keywords with custom schema: #{result.inspect}"
          expect(has_actions).to be(true),
            "#{provider} should extract actions with custom schema: #{result.inspect}"

          if ENV['DEBUG']
            puts "\n  [#{provider}] Custom schema result:"
            puts "    keywords: #{result['keywords'] || result[:keywords]}"
            puts "    actions: #{result['actions'] || result[:actions]}"
          end
        end
      end
    end
  end

  describe 'Reasoning Model Handling' do
    # Test providers with reasoning models
    REASONING_PROVIDERS = {
      'cohere' => { description: 'Cohere command-a-reasoning models' },
      'deepseek' => { description: 'DeepSeek reasoner models' }
    }.freeze

    REASONING_PROVIDERS.each do |provider, info|
      context "with #{provider} (#{info[:description]})" do
        before(:each) do
          require_run_api!
          skip("Provider #{provider} not in PROVIDERS list") unless providers_from_env.include?(provider)
          skip("API key not available for #{provider}") unless api_key_available?(provider)
        end

        it "successfully extracts context using provider's default model" do
          test_data = TEST_CONVERSATIONS[:simple]
          session = { messages: [], runtime_settings: { language: 'en' } }

          # Get the default model for this provider
          model = SystemDefaults.get_default_model(provider)
          puts "\n  [#{provider}] Using default model: #{model}" if ENV['DEBUG']

          result = extract_context(
            session,
            test_data[:user_message],
            test_data[:assistant_response],
            provider
          )

          # Should successfully parse response from reasoning model
          expect(result).to be_a(Hash),
            "#{provider} should return valid context even with reasoning model"

          # Verify structure
          topics = result['topics'] || result[:topics] || []
          expect(topics).to be_an(Array),
            "#{provider} topics should be an Array, got #{topics.class}"

          if ENV['DEBUG']
            puts "  Result: #{result.inspect}"
          end
        end
      end
    end
  end

  describe 'Error Handling' do
    context 'with invalid API key' do
      it 'returns nil for missing API key' do
        # Temporarily clear API key from both ENV and CONFIG
        original_env_key = ENV['OPENAI_API_KEY']
        original_config_key = CONFIG['OPENAI_API_KEY'] if defined?(CONFIG)

        ENV['OPENAI_API_KEY'] = nil
        CONFIG['OPENAI_API_KEY'] = nil if defined?(CONFIG)

        session = { messages: [], runtime_settings: {} }
        result = extract_context(session, 'test', 'test', 'openai')

        expect(result).to be_nil

        # Restore
        ENV['OPENAI_API_KEY'] = original_env_key
        CONFIG['OPENAI_API_KEY'] = original_config_key if defined?(CONFIG) && original_config_key
      end
    end

    context 'with unknown provider' do
      it 'handles unknown provider gracefully' do
        session = { messages: [], runtime_settings: {} }
        result = extract_context(session, 'test', 'test', 'unknown_provider')

        # Should return nil for unknown provider (no model configured)
        expect(result).to be_nil
      end
    end
  end

  describe 'Provider Normalization' do
    it 'normalizes claude to anthropic' do
      result = normalize_provider('claude')
      expect(result).to eq('anthropic')
    end

    it 'normalizes grok to xai' do
      result = normalize_provider('grok')
      expect(result).to eq('xai')
    end

    it 'normalizes google to gemini' do
      result = normalize_provider('google')
      expect(result).to eq('gemini')
    end

    it 'passes through standard provider names' do
      %w[openai cohere deepseek mistral].each do |provider|
        expect(normalize_provider(provider)).to eq(provider)
      end
    end
  end

  describe 'Language Detection' do
    it 'detects English text' do
      text = "Hello, how are you today? The weather is nice."
      result = detect_conversation_language(text)
      expect(result).to eq('en')
    end

    it 'detects Japanese text' do
      text = "こんにちは、今日はいい天気ですね。"
      result = detect_conversation_language(text)
      expect(result).to eq('ja')
    end

    it 'handles empty text' do
      result = detect_conversation_language('')
      expect(result).to eq('en')  # Default fallback
    end
  end
end
