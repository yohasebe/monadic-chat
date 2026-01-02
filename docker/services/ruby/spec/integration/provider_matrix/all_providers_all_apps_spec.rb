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
require_relative '../../support/response_evaluator'

RSpec.describe 'All Providers × All Apps Matrix', :api, :matrix do
  include ProviderMatrixHelper

  # Provider configuration
  PROVIDER_CONFIG = {
    'openai' => { suffix: 'OpenAI', file_suffix: 'openai', timeout: 60 },
    'anthropic' => { suffix: 'Claude', file_suffix: 'claude', timeout: 90 },
    'gemini' => { suffix: 'Gemini', file_suffix: 'gemini', timeout: 60 },
    'xai' => { suffix: 'Grok', file_suffix: 'grok', timeout: 60 },
    'mistral' => { suffix: 'Mistral', file_suffix: 'mistral', timeout: 60 },
    'cohere' => { suffix: 'Cohere', file_suffix: 'cohere', timeout: 60 },
    'deepseek' => { suffix: 'DeepSeek', file_suffix: 'deepseek', timeout: 60 },
    'perplexity' => { suffix: 'Perplexity', file_suffix: 'perplexity', timeout: 60 },
    'ollama' => { suffix: 'Ollama', file_suffix: 'ollama', timeout: 120 }
  }.freeze

  # Scan filesystem to find which apps exist for which providers
  # This avoids generating tests for non-existent app/provider combinations
  APPS_DIR = File.expand_path('../../../apps', __dir__)

  def self.app_exists_for_provider?(app_base, provider_key)
    config = PROVIDER_CONFIG[provider_key]
    return false unless config

    file_suffix = config[:file_suffix]
    app_dir_name = app_base.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')

    app_dir = File.join(APPS_DIR, app_dir_name)
    return false unless File.directory?(app_dir)

    # Check for provider-specific MDSL file
    provider_mdsl = File.join(app_dir, "#{app_dir_name}_#{file_suffix}.mdsl")
    return true if File.exist?(provider_mdsl)

    # Check for generic MDSL file (usually means OpenAI-only)
    generic_mdsl = File.join(app_dir, "#{app_dir_name}.mdsl")
    return provider_key == 'openai' && File.exist?(generic_mdsl)
  end

  # Detect if an app has initiate_from_assistant: true in its MDSL
  # These apps should generate an initial message without user prompt
  def self.initiate_from_assistant?(app_base, provider_key)
    config = PROVIDER_CONFIG[provider_key]
    return false unless config

    file_suffix = config[:file_suffix]
    app_dir_name = app_base.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
    app_dir = File.join(APPS_DIR, app_dir_name)
    return false unless File.directory?(app_dir)

    # Find the appropriate MDSL file
    provider_mdsl = File.join(app_dir, "#{app_dir_name}_#{file_suffix}.mdsl")
    mdsl_file = if File.exist?(provider_mdsl)
                  provider_mdsl
                elsif provider_key == 'openai'
                  generic_mdsl = File.join(app_dir, "#{app_dir_name}.mdsl")
                  File.exist?(generic_mdsl) ? generic_mdsl : nil
                end

    return false unless mdsl_file

    # Check if initiate_from_assistant true is in the file
    content = File.read(mdsl_file)
    content.match?(/initiate_from_assistant\s+true/)
  rescue StandardError
    false
  end

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
    },

    # Help app
    'MonadicHelp' => {
      prompt: 'What can you do?',
      expectation: 'The AI explained its capabilities or Monadic Chat features'
    }
  }.freeze

  # Apps that require special runtime environment (Docker containers, media devices, etc.)
  # These are skipped only if the required environment is not available
  SPECIAL_SETUP_APPS = %w[
    ContentReader
    PDFNavigator
    VideoDescriber
    VisualWebExplorer
    VoiceChat
    VoiceInterpreter
  ].freeze

  # Get enabled providers from environment at test generation time
  ENABLED_PROVIDERS = begin
    list = (ENV['PROVIDERS'] || '').split(',').map(&:strip).reject(&:empty?)
    if list.empty?
      # Default providers when PROVIDERS is not set
      defaults = %w[openai anthropic gemini mistral cohere perplexity deepseek xai]
      defaults << 'ollama' if ENV['INCLUDE_OLLAMA'] == 'true'
      defaults
    else
      list
    end
  end.freeze

  describe 'Basic Response Matrix' do
    PROVIDER_CONFIG.each do |provider_key, config|
      # Skip generating tests for providers not in ENABLED_PROVIDERS
      next unless ENABLED_PROVIDERS.include?(provider_key)

      context "with #{provider_key} provider" do
        APP_TEST_CONFIGS.each do |app_base, test_config|
          next if SPECIAL_SETUP_APPS.include?(app_base)
          # Skip generating test if app doesn't exist for this provider
          next unless app_exists_for_provider?(app_base, provider_key)
          # Skip initiate_from_assistant apps - they are tested in the Initial Message Matrix
          next if initiate_from_assistant?(app_base, provider_key)

          app_name = "#{app_base}#{config[:suffix]}"

          it "#{app_name} returns valid response", :aggregate_failures do
            require_run_api!
            skip 'OPENAI_API_KEY not set for evaluation' unless ENV['OPENAI_API_KEY']
            skip "Provider #{provider_key} not configured" unless provider_available?(provider_key)

            with_provider(provider_key) do |p|
              begin
                # Use max_turns: 3 to allow follow-up when AI asks clarifying questions
                res = p.chat(test_config[:prompt], app: app_name, timeout: config[:timeout], max_turns: 3)

                # Basic structure validation
                expect(res).to be_a(Hash), "Expected Hash response from #{app_name}"

                # Use two-stage evaluation
                evaluation_context = {
                  purpose: test_config[:expectation],
                  provider: provider_key
                }

                result = ResponseEvaluator.evaluate(
                  res,
                  app_name,
                  test_config[:prompt],
                  evaluation_context
                )

                # Log evaluation result
                if ENV['DEBUG']
                  response_text = res[:text] || res['text']
                  tool_calls = res[:tool_calls] || res['tool_calls'] || []
                  if tool_calls.any?
                    tool_names = tool_calls.map { |tc| tc['name'] || tc[:name] }.compact
                    puts "\n  #{app_name}: #{result} (tools: #{tool_names.join(', ')})"
                  else
                    puts "\n  #{app_name}: #{result} (#{response_text.to_s.length} chars)"
                  end
                end

                # Assert evaluation passed
                expect(result.pass?).to be(true),
                  "#{app_name} evaluation failed: #{result.reason}\n" \
                  "Response: #{(res[:text] || res['text']).to_s[0..300]}"

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
      # Skip generating tests for providers not in ENABLED_PROVIDERS
      next unless ENABLED_PROVIDERS.include?(provider_key)

      context "with #{provider_key} provider" do
        TOOL_TEST_CASES.each do |app_base, test_config|
          # Skip generating test if app doesn't exist for this provider
          next unless app_exists_for_provider?(app_base, provider_key)
          # Skip initiate_from_assistant apps - they are tested in the Initial Message Matrix
          next if initiate_from_assistant?(app_base, provider_key)

          app_name = "#{app_base}#{config[:suffix]}"

          it "#{app_name} handles tool-related prompts without crashing" do
            require_run_api!
            skip 'OPENAI_API_KEY not set for evaluation' unless ENV['OPENAI_API_KEY']
            skip "Provider #{provider_key} not configured" unless provider_available?(provider_key)

            with_provider(provider_key) do |p|
              begin
                # Use max_turns: 3 to allow follow-up when AI asks clarifying questions
                res = p.chat(test_config[:prompt], app: app_name, timeout: 120, max_turns: 3)

                # Basic structure validation
                expect(res).to be_a(Hash), "Expected Hash response from #{app_name}"

                # Use two-stage evaluation
                evaluation_context = {
                  purpose: test_config[:expectation],
                  provider: provider_key
                }

                result = ResponseEvaluator.evaluate(
                  res,
                  app_name,
                  test_config[:prompt],
                  evaluation_context
                )

                # Log evaluation result
                if ENV['DEBUG']
                  response_text = res[:text] || res['text']
                  tool_calls = res[:tool_calls] || res['tool_calls'] || []
                  if tool_calls.any?
                    tool_names = tool_calls.map { |tc| tc['name'] || tc[:name] }.compact
                    puts "\n  #{app_name} (tool): #{result} (tools: #{tool_names.join(', ')})"
                  else
                    puts "\n  #{app_name} (tool): #{result} (#{response_text.to_s.length} chars)"
                  end
                end

                # Assert evaluation passed
                expect(result.pass?).to be(true),
                  "#{app_name} evaluation failed: #{result.reason}\n" \
                  "Response: #{(res[:text] || res['text']).to_s[0..300]}"

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

  describe 'Initial Message Matrix (initiate_from_assistant apps)' do
    # Apps with initiate_from_assistant: true should generate an initial greeting/introduction
    # without requiring a specific user task prompt.
    #
    # Test design:
    # - Mirror actual app behavior: system prompt only, no user message
    # - Each provider helper automatically adds the appropriate trigger message
    # - Verify the app responds with a valid introduction

    PROVIDER_CONFIG.each do |provider_key, config|
      # Skip generating tests for providers not in ENABLED_PROVIDERS
      next unless ENABLED_PROVIDERS.include?(provider_key)

      context "with #{provider_key} provider" do
        # Get all apps that have initiate_from_assistant: true for this provider
        APP_TEST_CONFIGS.keys.each do |app_base|
          next if SPECIAL_SETUP_APPS.include?(app_base)
          next unless app_exists_for_provider?(app_base, provider_key)
          next unless initiate_from_assistant?(app_base, provider_key)

          app_name = "#{app_base}#{config[:suffix]}"

          it "#{app_name} generates initial message without errors", :aggregate_failures do
            require_run_api!
            skip "Provider #{provider_key} not configured" unless provider_available?(provider_key)

            with_provider(provider_key) do |p|
              begin
                # Use initial_message which mirrors actual app behavior:
                # system prompt only, helper adds trigger message
                res = p.initial_message(app: app_name, timeout: config[:timeout])

                # Basic structure validation
                expect(res).to be_a(Hash), "Expected Hash response from #{app_name}"

                # Use two-stage evaluation for initial messages
                evaluation_context = {
                  purpose: "Generate an appropriate initial greeting or introduction for the #{app_base} app",
                  provider: provider_key,
                  is_initial_message: true
                }
                result = ResponseEvaluator.evaluate(
                  res,
                  app_name,
                  "(initial message)",
                  evaluation_context
                )

                # Log evaluation result
                if ENV['DEBUG']
                  response_text = res[:text] || res['text']
                  tool_calls = res[:tool_calls] || res['tool_calls'] || []
                  if tool_calls.any?
                    tool_names = tool_calls.map { |tc| tc['name'] || tc[:name] }.compact
                    puts "\n  #{app_name} (initial): #{result} (tools: #{tool_names.join(', ')})"
                  else
                    puts "\n  #{app_name} (initial): #{result} (#{response_text.to_s.length} chars)"
                  end
                end

                # Assert evaluation passed
                expect(result.pass?).to be(true),
                  "#{app_name} initial message evaluation failed: #{result.reason}\n" \
                  "Response: #{(res[:text] || res['text']).to_s[0..300]}"

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

  private

  def provider_available?(provider_key)
    providers_from_env.include?(provider_key)
  end
end
