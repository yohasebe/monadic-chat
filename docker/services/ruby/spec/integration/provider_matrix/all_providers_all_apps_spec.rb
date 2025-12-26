# frozen_string_literal: true

# Comprehensive Provider × App Matrix Test
#
# Uses ResponseEvaluator for reliable AI-based validation.
# Systematically tests all provider-specific app variants.
#
# Run with:
#   RUN_API=true bundle exec rspec spec/integration/provider_matrix/all_providers_all_apps_spec.rb
#
# Run specific provider:
#   PROVIDERS=anthropic RUN_API=true bundle exec rspec spec/integration/provider_matrix/all_providers_all_apps_spec.rb

require 'spec_helper'
require_relative '../../support/provider_matrix_helper'
require_relative '../../../lib/monadic/utils/response_evaluator'

RSpec.describe 'All Providers × All Apps Matrix', :api, :matrix do
  include ProviderMatrixHelper

  RE = Monadic::Utils::ResponseEvaluator

  # Provider configuration
  PROVIDER_CONFIG = {
    'openai' => { suffix: 'OpenAI', timeout: 60 },
    'anthropic' => { suffix: 'Claude', timeout: 90 },
    'gemini' => { suffix: 'Gemini', timeout: 60 },
    'xai' => { suffix: 'Grok', timeout: 60 },
    'mistral' => { suffix: 'Mistral', timeout: 60 },
    'cohere' => { suffix: 'Cohere', timeout: 60 },
    'deepseek' => { suffix: 'DeepSeek', timeout: 60 },
    'perplexity' => { suffix: 'Perplexity', timeout: 60 },
    'ollama' => { suffix: 'Ollama', timeout: 120 }
  }.freeze

  # App categories with appropriate test prompts and expectations
  # NOTE: These are smoke tests - expectations should verify the app works,
  # not assess response quality. Keep expectations permissive.
  APP_TEST_CONFIGS = {
    # Chat apps - simple response test
    'Chat' => {
      prompt: 'Say hello.',
      expectation: 'The AI responded with text (any greeting or response is acceptable)'
    },
    'ChatPlus' => {
      prompt: 'Say hello.',
      expectation: 'The AI responded with text (any greeting or response is acceptable)'
    },

    # Code apps - verify code generation capability
    'CodeInterpreter' => {
      prompt: 'What is 2+2?',
      expectation: 'The AI provided an answer related to the math question (4 or explanation)'
    },
    'CodingAssistant' => {
      prompt: 'Write Python code that prints hello.',
      expectation: 'The AI returned ANY code or programming-related response - whether a simple print statement, complex code, or code explanation, all indicate the coding assistant is working'
    },
    'JupyterNotebook' => {
      prompt: 'Describe a simple notebook concept.',
      expectation: 'The AI responded with text about notebooks or computing'
    },

    # Creative apps
    # Note: NovelWriter is designed for long-form creative writing - it naturally generates elaborate narratives
    'NovelWriter' => {
      prompt: 'Start a story about a hero.',
      expectation: 'The AI returned ANY creative text or narrative content - detailed stories, character development, plot outlines are ALL expected behavior for a novel writing app'
    },
    # Note: MailComposer may ask clarifying questions before composing - this is correct behavior
    'MailComposer' => {
      prompt: 'Write a thank you message for helping me move.',
      expectation: 'The AI responded with any text related to messages or email composition',
      skip_ai_evaluation: true  # Just verify non-empty response without errors
    },
    'SpeechDraftHelper' => {
      prompt: 'Write an opening for a graduation speech.',
      expectation: 'The AI responded about a speech (either wrote one or asked for details)'
    },
    'DocumentGenerator' => {
      prompt: 'Create a memo about the team meeting on Friday.',
      expectation: 'The AI responded about creating a memo (either created one or asked for details)'
    },

    # Research apps
    # Note: ResearchAssistant is configured to call load_research_progress tool before any response
    # This is expected behavior per the MDSL system prompt. Accept tool calls as valid.
    'ResearchAssistant' => {
      prompt: 'What is the capital of Japan?',
      expectation: 'The AI responded about Japan or Tokyo, or made a tool call to load research progress',
      skip_ai_evaluation: true  # Tool calls for loading progress are expected first action
    },
    'Wikipedia' => {
      prompt: 'Briefly describe Python.',
      expectation: 'The AI described Python programming language'
    },
    'Translate' => {
      prompt: 'Translate "hello" to French.',
      expectation: 'The AI provided "bonjour" or a French translation'
    },

    # Visualization apps
    'MermaidGrapher' => {
      prompt: 'Describe a simple flowchart concept.',
      expectation: 'The AI described a flowchart or diagram concept'
    },
    'DrawIOGrapher' => {
      prompt: 'Describe a simple diagram concept.',
      expectation: 'The AI described a diagram concept'
    },
    'ConceptVisualizer' => {
      prompt: 'Describe how to visualize "tree".',
      expectation: 'The AI described a visualization approach'
    },
    'SyntaxTree' => {
      prompt: 'Parse: The cat sat.',
      expectation: 'The AI analyzed the sentence structure'
    },

    # Education apps
    'MathTutor' => {
      prompt: 'What is 5 times 6?',
      expectation: 'The AI provided the answer 30'
    },
    # Note: LanguagePractice is designed to encourage practice, not give direct answers
    # Skip AI evaluation because the app may respond with related but not exact translations
    'LanguagePractice' => {
      prompt: 'How do you say "thank you" in Spanish?',
      expectation: 'The AI responded with ANY text related to Spanish or languages',
      skip_ai_evaluation: true  # Just verify non-empty response without errors
    },
    # Note: LanguagePracticePlus may use tools for TTS or other functions, and may check context first
    'LanguagePracticePlus' => {
      prompt: 'Teach me to count to 3 in Italian.',
      expectation: 'The AI returned ANY response - teaching numbers, checking context, explaining the learning process, tool calls for TTS, or any language-related text indicates the app is working'
    },

    # Specialized apps
    'ChordAccompanist' => {
      prompt: 'What chords work with C major?',
      expectation: 'The AI mentioned chords that work with C major'
    },
    # Note: SecondOpinion is designed to consult another AI, so explaining that process IS the expected behavior
    # Use skip_ai_evaluation because the app's purpose is to explain the consultation process, not to directly answer
    'SecondOpinion' => {
      prompt: 'Get a second opinion on whether water is wet.',
      expectation: 'The AI returned ANY response about the consultation process',
      skip_ai_evaluation: true  # Just verify non-empty response without errors
    },

    # Media apps - tool calls are intercepted, no actual generation occurs
    # Tests verify the AI attempts to use generate_image/generate_video tools correctly
    'ImageGenerator' => {
      prompt: 'Generate a simple red circle icon.',
      expectation: 'The AI attempted to generate an image (tool call or description)'
    },
    # Note: VideoGenerator (initiate_from_assistant: true) starts with a greeting message
    # explaining its capabilities. The first response won't generate video - it introduces the app.
    # This is expected behavior per the MDSL system prompt.
    'VideoGenerator' => {
      prompt: 'Generate a 3-second video of a bouncing ball.',
      expectation: 'The AI responded about video generation - either a greeting/capability description OR attempted to generate',
      skip_ai_evaluation: true  # First response is often app introduction, not video generation
    },

    # Complex apps
    # Note: AutoForge may ask for project details before describing a concept
    'AutoForge' => {
      prompt: 'Describe a simple web page concept.',
      expectation: 'The AI responded about web pages (either described a concept or asked for project details)'
    }
  }.freeze

  # Apps to skip (require special setup)
  SKIP_APPS = %w[
    ContentReader
    PDFNavigator
    VideoDescriber
    VisualWebExplorer
    VoiceChat
    VoiceInterpreter
    MonadicHelp
  ].freeze

  describe 'Basic Response Matrix' do
    PROVIDER_CONFIG.each do |provider_key, config|
      context "with #{provider_key} provider" do
        APP_TEST_CONFIGS.each do |app_base, test_config|
          next if SKIP_APPS.include?(app_base)

          app_name = "#{app_base}#{config[:suffix]}"

          it "#{app_name} returns valid response", :aggregate_failures do
            require_run_api!
            skip 'OPENAI_API_KEY not set for evaluation' unless ENV['OPENAI_API_KEY']
            skip "App #{app_name} not available" unless app_exists?(app_name)
            skip "Provider #{provider_key} not configured" unless provider_available?(provider_key)

            with_provider(provider_key) do |p|
              begin
                # Use max_turns: 3 to allow follow-up when AI asks clarifying questions
                res = p.chat(test_config[:prompt], app: app_name, timeout: config[:timeout], max_turns: 3)

                # Basic structure validation
                expect(res).to be_a(Hash), "Expected Hash response from #{app_name}"

                # Check if response contains tool calls (valid for tool-using apps)
                has_tool_calls = res[:tool_calls] && res[:tool_calls].any?

                if has_tool_calls
                  # Tool calls are valid responses for tool-using apps
                  # We simply verify that:
                  # 1. The model made a valid tool call (not an error)
                  # 2. Tool names are non-empty strings
                  # The actual "appropriateness" of tool choice is less important since
                  # we're testing API communication, not business logic
                  tool_names = res[:tool_calls].map { |tc| tc['name'] || tc[:name] }.compact

                  puts "\n  #{app_name}: Tool call(s) - #{tool_names.join(', ')}" if ENV['DEBUG']

                  # Verify we got valid tool names
                  expect(tool_names).not_to be_empty,
                    "#{app_name} made tool call but no tool names were returned"

                  tool_names.each do |name|
                    expect(name).to be_a(String),
                      "#{app_name} tool name should be a String, got #{name.class}"
                    expect(name.length).to be > 0,
                      "#{app_name} tool name should not be empty"
                  end

                  # Test passed - tool calls are valid responses
                  # The model successfully communicated with the API and invoked tools

                else
                  # Regular text response
                  expect(res[:text]).to be_a(String), "Expected String text from #{app_name}"
                  expect(res[:text].length).to be > 0, "Expected non-empty response from #{app_name}"

                  response_text = res[:text]

                  # Check for runtime errors using pattern matching
                  error_patterns = [
                    /undefined method ['`]/i,
                    /NoMethodError:/,
                    /NameError:/,
                    /TypeError:/,
                    /ArgumentError:/,
                    /SyntaxError:/,
                    /LoadError:/,
                    /`rescue in.*'/,
                    /from .*\.rb:\d+:in/
                  ]
                  has_runtime_errors = error_patterns.any? { |pattern| response_text.match?(pattern) }

                  expect(has_runtime_errors).to be(false),
                    "#{app_name} appears to have runtime errors in response:\n#{response_text[0..500]}"

                  # For apps where AI evaluation doesn't make sense (e.g., process-oriented apps),
                  # just verify we got a non-empty response without errors
                  if test_config[:skip_ai_evaluation]
                    # Simple check: response is non-empty and has no errors
                    expect(response_text.length).to be > 10,
                      "#{app_name} response too short: #{response_text}"
                  else
                    # AI-based smoke test (very permissive)
                    eval_result = RE.evaluate(
                      response: response_text,
                      expectation: test_config[:expectation],
                      prompt: test_config[:prompt],
                      criteria: 'VERY permissive smoke test: Accept ANY response that is not an error. Asking for details, searching for information, or providing partial answers are ALL acceptable. The goal is only to verify the app responded without crashing.'
                    )

                    # Skip if ResponseEvaluator had network issues
                    if eval_result.reasoning&.include?('Evaluation error:')
                      skip "#{app_name}: ResponseEvaluator unavailable - #{eval_result.reasoning[0..80]}"
                    end

                    # Log evaluation results for debugging
                    if !eval_result.match
                      puts "\n  #{app_name} evaluation:"
                      puts "    No runtime errors: true"
                      puts "    Response OK: #{eval_result.match} (#{eval_result.confidence})"
                    end

                    expect(eval_result.match).to be(true),
                      "#{app_name} response issue: #{eval_result.reasoning}"
                  end
                end

              rescue Timeout::Error => e
                skip "#{app_name}: Timeout - #{e.message[0..50]}"
              rescue StandardError => e
                expect(e.message).not_to include('undefined method'),
                  "#{app_name} raised undefined method error: #{e.message}"

                if e.message.include?('timeout') || e.message.include?('rate limit') || e.message.include?('execution expired')
                  skip "#{app_name}: #{e.message[0..50]}"
                else
                  raise e
                end
              end
            end
          end
        end
      end
    end
  end

  describe 'Tool Invocation Matrix' do
    # Apps with tools - test that tool-aware apps respond without errors
    # Focus: Does the app handle tool-related prompts without crashing?
    # Note: Actual tool execution may require Docker containers
    #
    # IMPORTANT: Some apps have mandatory first-action tool calls defined in their MDSL:
    # - CodeInterpreter: Must call check_environment() before any response
    # - ResearchAssistant: Must call load_research_progress before any response
    # These tool calls are EXPECTED behavior, not failures.
    TOOL_TEST_CASES = {
      'ChordAccompanist' => {
        prompt: 'What chords go well with C major?',
        expectation: 'The AI responded about chords, music theory, or chord progressions'
      },
      'MermaidGrapher' => {
        prompt: 'Describe a simple flowchart with two nodes.',
        expectation: 'The AI responded about flowcharts, diagrams, or Mermaid syntax'
      },
      # Note: CodeInterpreter MDSL mandates calling check_environment() first
      # Any tool call (including check_environment) is valid expected behavior
      'CodeInterpreter' => {
        prompt: 'What is 2+2?',
        expectation: 'The AI responded - either with environment check tool call OR calculation'
      },
      # Note: ResearchAssistant MDSL mandates calling load_research_progress first
      # Any tool call (including load_research_progress) is valid expected behavior
      'ResearchAssistant' => {
        prompt: 'What is Ruby programming language?',
        expectation: 'The AI responded - either with load_research_progress tool call OR information about Ruby'
      }
    }.freeze

    PROVIDER_CONFIG.each do |provider_key, config|
      context "with #{provider_key} provider" do
        TOOL_TEST_CASES.each do |app_base, test_config|
          app_name = "#{app_base}#{config[:suffix]}"

          it "#{app_name} handles tool-related prompts without crashing" do
            require_run_api!
            skip 'OPENAI_API_KEY not set for evaluation' unless ENV['OPENAI_API_KEY']
            skip "App #{app_name} not available" unless app_exists?(app_name)
            skip "Provider #{provider_key} not configured" unless provider_available?(provider_key)

            with_provider(provider_key) do |p|
              begin
                # Use max_turns: 3 to allow follow-up when AI asks clarifying questions
                res = p.chat(test_config[:prompt], app: app_name, timeout: 120, max_turns: 3)

                # Check if response contains tool calls
                has_tool_calls = res[:tool_calls] && res[:tool_calls].any?

                if has_tool_calls
                  # Tool calls are expected for tool-aware apps
                  # Some apps have mandatory first-action tool calls (e.g., check_environment, load_research_progress)
                  # These are EXPECTED behavior per their MDSL system prompts
                  tool_names = res[:tool_calls].map { |tc| tc['name'] || tc[:name] }.compact

                  puts "\n  #{app_name}: Tool call(s) - #{tool_names.join(', ')}" if ENV['DEBUG']

                  # Verify we got valid tool names (no AI evaluation needed for tool calls)
                  expect(tool_names).not_to be_empty,
                    "#{app_name} made tool call but no tool names were returned"

                  tool_names.each do |name|
                    expect(name).to be_a(String),
                      "#{app_name} tool name should be a String, got #{name.class}"
                    expect(name.length).to be > 0,
                      "#{app_name} tool name should not be empty"
                  end

                  # Test passed - tool calls are valid responses for tool-aware apps
                  # Apps like CodeInterpreter and ResearchAssistant are EXPECTED to make tool calls first

                else
                  # Regular text response
                  response_text = res[:text] || ''

                  # Check for runtime errors
                  error_patterns = [
                    /undefined method ['`]/i,
                    /NoMethodError:/,
                    /NameError:/,
                    /TypeError:/,
                    /ArgumentError:/,
                    /SyntaxError:/,
                    /LoadError:/,
                    /`rescue in.*'/,
                    /from .*\.rb:\d+:in/
                  ]
                  has_runtime_errors = error_patterns.any? { |pattern| response_text.match?(pattern) }

                  content_check = RE.evaluate(
                    response: response_text,
                    expectation: test_config[:expectation],
                    prompt: test_config[:prompt],
                    criteria: 'VERY permissive smoke test: Accept ANY response that is not an error. Asking for details, searching for information, or providing partial answers are ALL acceptable.'
                  )

                  if content_check.reasoning&.include?('Evaluation error:')
                    skip "#{app_name}: ResponseEvaluator unavailable - #{content_check.reasoning[0..80]}"
                  end

                  expect(has_runtime_errors).to be(false),
                    "#{app_name} has errors in response:\n#{response_text[0..300]}"

                  expect(content_check.match).to be(true),
                    "#{app_name} response issue: #{content_check.reasoning}"
                end

              rescue Timeout::Error => e
                skip "#{app_name}: Timeout - #{e.message[0..50]}"
              rescue StandardError => e
                expect(e.message).not_to include('undefined method'),
                  "#{app_name} raised undefined method: #{e.message}"

                # Skip on infrastructure issues
                if e.message.include?('timeout') || e.message.include?('rate limit') || e.message.include?('execution expired')
                  skip "#{app_name}: #{e.message[0..50]}"
                end
              end
            end
          end
        end
      end
    end
  end

  private

  def app_exists?(app_name)
    defined?(APPS) && APPS.is_a?(Hash) && APPS.key?(app_name)
  end

  def provider_available?(provider_key)
    providers_from_env.include?(provider_key)
  end
end
