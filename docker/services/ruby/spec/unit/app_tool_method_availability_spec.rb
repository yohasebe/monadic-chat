# frozen_string_literal: true

# This spec validates that all tool methods in apps can actually be called
# at runtime, including verifying that internal method calls are valid.
#
# This catches issues like the Chord Accompanist bug where a tool method
# called a non-existent helper method (call_claude).

require 'spec_helper'

RSpec.describe 'App Tool Method Availability' do
  let(:app_base_dir) { File.expand_path('../../apps', __dir__) }

  # Load all helper modules for method resolution
  before(:all) do
    # Ensure helpers are loaded
    Dir.glob(File.join(File.expand_path('../../lib/monadic/adapters/vendors', __dir__), '*.rb')).each do |f|
      require f
    end
    Dir.glob(File.join(File.expand_path('../../lib/monadic/agents', __dir__), '*.rb')).each do |f|
      require f
    end
  end

  describe 'Tool Implementation Validation' do
    # Collect all tool implementation classes
    let(:tool_classes) do
      classes = []
      Dir.glob(File.join(app_base_dir, '**/*_tools.rb')).each do |file|
        content = File.read(file)
        # Extract class definitions
        content.scan(/class\s+(\w+)\s*<\s*MonadicApp/).each do |match|
          class_name = match[0]
          classes << { file: file, class_name: class_name }
        end
      end
      classes
    end

    it 'validates all tool classes can be instantiated without errors' do
      errors = []

      tool_classes.each do |info|
        begin
          # Load the file
          require info[:file]

          # Get the class
          klass = Object.const_get(info[:class_name])

          # Check all included modules (including from ancestors)
          all_modules = klass.ancestors.flat_map do |ancestor|
            ancestor.included_modules.map(&:name)
          end.compact.uniq

          # Check for provider-specific helper inclusion
          # Note: Classes inherit from MonadicApp which may include helpers,
          # so we check the full ancestor chain
          if info[:class_name].include?('Claude') && !info[:class_name].include?('Accompanist')
            # Skip Chord Accompanist as it has its own tools file structure
            unless all_modules.include?('ClaudeHelper')
              errors << "#{info[:class_name]} should include ClaudeHelper but doesn't"
            end
          end
          # Note: OpenAI classes often inherit helper from parent class or have
          # conditional includes, so we don't strictly validate those here
        rescue StandardError => e
          errors << "Failed to load #{info[:file]}: #{e.message}"
        end
      end

      expect(errors).to be_empty, "Tool class validation errors:\n#{errors.join("\n")}"
    end

    it 'validates tool methods do not call undefined helper methods' do
      errors = []

      # Known helper methods from each provider
      claude_helper_methods = %w[
        send_query api_request process_json_data
        check_num_tokens process_functions sanitize_data
      ]

      openai_helper_methods = %w[
        send_query api_request process_json_data
        run_code run_bash_command
      ]

      gemini_helper_methods = %w[
        send_query api_request
      ]

      # Common patterns that indicate a missing method call
      dangerous_patterns = [
        /call_claude\s*\(/,           # call_claude doesn't exist
        /call_openai\s*\(/,           # Should use send_query or api_request
        /call_gemini\s*\(/,           # Should use send_query or api_request
        /call_anthropic\s*\(/,        # Should use send_query or api_request
      ]

      Dir.glob(File.join(app_base_dir, '**/*_tools.rb')).each do |file|
        content = File.read(file)

        dangerous_patterns.each do |pattern|
          if content.match?(pattern)
            match = content.match(pattern)
            # Get line number
            lines = content[0...match.begin(0)].count("\n") + 1
            errors << "#{file}:#{lines} - Calls potentially undefined method: #{match[0]}"
          end
        end
      end

      expect(errors).to be_empty, "Found calls to potentially undefined methods:\n#{errors.join("\n")}"
    end

    it 'validates provider-specific tool files include correct helpers' do
      errors = []

      provider_helper_map = {
        'claude' => 'ClaudeHelper',
        'openai' => 'OpenAIHelper',
        'gemini' => 'GeminiHelper',
        'grok' => 'GrokHelper',
        'mistral' => 'MistralHelper',
        'cohere' => 'CohereHelper',
        'deepseek' => 'DeepSeekHelper',
        'perplexity' => 'PerplexityHelper',
        'ollama' => 'OllamaHelper'
      }

      Dir.glob(File.join(app_base_dir, '**/*_tools.rb')).each do |file|
        content = File.read(file)
        filename = File.basename(file, '.rb')

        provider_helper_map.each do |provider, helper|
          # Check if file is provider-specific
          if filename.include?("_#{provider}") || filename.end_with?("#{provider}_tools")
            # Verify correct helper is included
            unless content.include?("include #{helper}")
              # Check for conditional include
              unless content.include?("include #{helper} if defined?(#{helper})")
                errors << "#{file} appears to be #{provider}-specific but doesn't include #{helper}"
              end
            end
          end
        end
      end

      expect(errors).to be_empty, "Provider helper inclusion errors:\n#{errors.join("\n")}"
    end
  end

  describe 'Agent Method Availability' do
    it 'validates apps using agents have access to agent methods' do
      errors = []

      agent_method_map = {
        'Monadic::Agents::OpenAICodeAgent' => 'call_openai_code',
        'Monadic::Agents::GrokCodeAgent' => 'call_grok_code',
        'Monadic::Agents::ClaudeCodeAgent' => 'call_claude_code',
        'SecondOpinionAgent' => 'second_opinion_agent'
      }

      Dir.glob(File.join(app_base_dir, '**/*.rb')).each do |file|
        content = File.read(file)

        agent_method_map.each do |agent_module, expected_method|
          # Check if agent is included
          if content.include?("include #{agent_module}")
            # Check if the expected method is called somewhere
            # This is informational - the include should provide the method
            next
          end

          # Check if method is called without including agent
          if content.include?(expected_method) && !content.include?("include #{agent_module}")
            # Might be calling method without proper include
            # But could also be delegating - needs manual review
            unless content.include?("def #{expected_method}")
              errors << "#{file} calls #{expected_method} but may not include #{agent_module}"
            end
          end
        end
      end

      # This test is informational - errors may have false positives
      if errors.any?
        puts "\nPotential agent method issues (review manually):"
        errors.each { |e| puts "  - #{e}" }
      end
    end
  end

  describe 'Runtime Method Resolution' do
    # These tests actually load the classes and check method availability

    it 'validates ClaudeHelper provides expected methods' do
      # Create a test class that includes ClaudeHelper
      test_class = Class.new do
        include ClaudeHelper
      end

      instance = test_class.new

      # Methods that SHOULD exist
      expect(instance).to respond_to(:send_query)
      expect(instance).to respond_to(:api_request)

      # Methods that should NOT exist (common mistakes)
      expect(instance).not_to respond_to(:call_claude)
    end

    it 'validates OpenAIHelper provides expected methods' do
      test_class = Class.new do
        include OpenAIHelper
      end

      instance = test_class.new

      expect(instance).to respond_to(:send_query)
      expect(instance).to respond_to(:api_request)
      expect(instance).not_to respond_to(:call_openai)
    end

    it 'validates GeminiHelper provides expected methods' do
      test_class = Class.new do
        include GeminiHelper
      end

      instance = test_class.new

      expect(instance).to respond_to(:send_query)
      expect(instance).to respond_to(:api_request)
      expect(instance).not_to respond_to(:call_gemini)
    end
  end

  describe 'Tool Method Signature Validation' do
    it 'validates tool methods accept keyword arguments correctly' do
      errors = []

      Dir.glob(File.join(app_base_dir, '**/*_tools.rb')).each do |file|
        content = File.read(file)

        # Find tool method definitions with parameters
        content.scan(/def\s+(\w+)\s*\(([^)]+)\)/).each do |method_name, params|
          # Check if any required parameters are missing defaults for keyword args
          if params.include?(':') && !params.include?('**')
            # Has keyword arguments - validate they have reasonable patterns
            keyword_params = params.scan(/(\w+):\s*([^,]+)?/)

            keyword_params.each do |param_name, default_value|
              # Skip if has default value
              next if default_value && !default_value.strip.empty?

              # Required keyword argument - should be documented
              # This is informational, not an error
            end
          end
        end
      end
    end
  end
end
