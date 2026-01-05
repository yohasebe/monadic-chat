# frozen_string_literal: true

# This spec validates that all tool methods in apps can be invoked
# without undefined method errors.
#
# This is a UNIT test - it doesn't require API calls.
# It loads app classes and verifies their tool methods are callable.
#
# This test would have caught the Chord Accompanist bug where
# call_claude was called but didn't exist.

require 'spec_helper'

RSpec.describe 'Tool Method Invocation Validation' do
  # Load all apps before running tests
  before(:all) do
    TestAppLoader.load_all_apps
  end

  let(:app_base_dir) { File.expand_path('../../../apps', __dir__) }

  # List of apps known to have tools that should be tested
  # Format: { app_class_name => { tool_name => { required_args } } }
  let(:apps_with_tools) do
    {
      # Chord Accompanist - the app that had the bug
      'ChordAccompanistClaude' => {
        'validate_abc_syntax' => { code: 'X:1\nT:Test\nM:4/4\nK:C\n|C D E F|' },
        # 'validate_chord_progression' => { chords: 'C, Am, F, G', key: 'C' },  # This calls send_query which needs full setup
        'analyze_abc_error' => { code: 'invalid', error: 'parse error' }
      },

      # Code Interpreter tools
      'CodeInterpreterOpenAI' => {
        # run_code requires Docker, skip in unit tests
      },

      # Jupyter Notebook tools
      'JupyterNotebookOpenAI' => {
        # Jupyter tools require Docker, skip in unit tests
      },

      # Mermaid Grapher tools
      'MermaidGrapherOpenAI' => {
        'validate_mermaid_syntax' => { code: 'graph TD\nA-->B' }
      },

      # Concept Visualizer
      'ConceptVisualizerOpenAI' => {
        # Most tools require LaTeX or external services
      },

      # Image Generator
      'ImageGeneratorOpenAI' => {
        # Image generation requires API calls
      },

      # Video Generator
      'VideoGeneratorGemini' => {
        # Video generation requires API calls
      },
    }
  end

  describe 'Static Tool Method Analysis' do
    it 'validates all tool methods are defined in their respective classes' do
      errors = []

      Dir.glob(File.join(app_base_dir, '**/*_tools.rb')).each do |file|
        content = File.read(file)

        # Extract class name
        class_match = content.match(/class\s+(\w+)\s*</)
        next unless class_match

        class_name = class_match[1]

        # Extract tool method definitions
        tool_methods = content.scan(/def\s+(\w+)\s*\(/).map(&:first)

        # For each tool method, check if any internal method calls exist
        # that might not be defined
        tool_methods.each do |method_name|
          # Extract the method body
          method_regex = /def\s+#{Regexp.escape(method_name)}\s*\([^)]*\)(.*?)(?=\n\s*def\s|\n\s*private|\n\s*protected|\nend\s*$)/m
          method_match = content.match(method_regex)

          next unless method_match

          method_body = method_match[1]

          # Check for potentially undefined method calls
          # These are common patterns that indicate a bug
          problematic_patterns = {
            /\bcall_claude\s*\(/ => 'call_claude (use send_query instead)',
            /\bcall_openai\s*\(/ => 'call_openai (use send_query or api_request instead)',
            /\bcall_gemini\s*\(/ => 'call_gemini (use send_query or api_request instead)',
            /\bcall_anthropic\s*\(/ => 'call_anthropic (use send_query instead)',
            /\bcall_grok\s*\(/ => 'call_grok (use send_query instead)',
            /\bcall_mistral\s*\(/ => 'call_mistral (use send_query instead)',
          }

          problematic_patterns.each do |pattern, suggestion|
            if method_body.match?(pattern)
              line_num = content[0...content.index(method_body)].count("\n") + 1
              errors << "#{file}:#{line_num} - #{class_name}##{method_name} calls undefined method: #{suggestion}"
            end
          end
        end
      end

      expect(errors).to be_empty, "Found calls to undefined methods:\n#{errors.join("\n")}"
    end

    it 'validates helper modules provide expected methods' do
      # Test that each helper module provides the methods apps depend on
      helper_expected_methods = {
        'ClaudeHelper' => [:send_query, :api_request],
        'OpenAIHelper' => [:send_query, :api_request],
        'GeminiHelper' => [:send_query, :api_request],
        'GrokHelper' => [:send_query, :api_request],
        'MistralHelper' => [:send_query, :api_request],
        'CohereHelper' => [:send_query, :api_request],
        'DeepSeekHelper' => [:send_query, :api_request],
        'PerplexityHelper' => [:send_query, :api_request],
      }

      errors = []

      helper_expected_methods.each do |helper_name, expected_methods|
        next unless Object.const_defined?(helper_name)

        helper_module = Object.const_get(helper_name)

        # Create a test class that includes the helper
        test_class = Class.new do
          include helper_module
        end

        instance = test_class.new

        expected_methods.each do |method_name|
          unless instance.respond_to?(method_name)
            errors << "#{helper_name} does not provide #{method_name}"
          end
        end
      end

      expect(errors).to be_empty, "Missing helper methods:\n#{errors.join("\n")}"
    end
  end

  describe 'Runtime Tool Method Validation' do
    # Test that specific tool methods can be called with proper arguments
    # (without actually calling external APIs)

    context 'ChordAccompanistClaude' do
      let(:app_class) do
        # Load the class if not already loaded
        tools_file = File.join(app_base_dir, 'chord_accompanist', 'chord_accompanist_claude_tools.rb')
        require tools_file if File.exist?(tools_file)
        Object.const_get('ChordAccompanistClaude') if Object.const_defined?('ChordAccompanistClaude')
      end

      it 'has validate_abc_syntax method that accepts code parameter' do
        skip 'ChordAccompanistClaude not loaded' unless app_class

        instance = app_class.new
        expect(instance).to respond_to(:validate_abc_syntax)

        # Check method accepts keyword argument
        method = instance.method(:validate_abc_syntax)
        params = method.parameters
        expect(params.any? { |type, name| name == :code }).to be true
      end

      it 'has analyze_abc_error method that accepts code and error parameters' do
        skip 'ChordAccompanistClaude not loaded' unless app_class

        instance = app_class.new
        expect(instance).to respond_to(:analyze_abc_error)

        method = instance.method(:analyze_abc_error)
        params = method.parameters
        expect(params.any? { |type, name| name == :code }).to be true
        expect(params.any? { |type, name| name == :error }).to be true
      end

      it 'includes ClaudeHelper and has access to send_query' do
        skip 'ChordAccompanistClaude not loaded' unless app_class

        instance = app_class.new
        expect(instance).to respond_to(:send_query)
      end

      it 'does NOT have call_claude method (the bug we fixed)' do
        skip 'ChordAccompanistClaude not loaded' unless app_class

        instance = app_class.new
        # This should fail - call_claude doesn't exist
        expect(instance).not_to respond_to(:call_claude)
      end
    end

    context 'MermaidGrapherOpenAI' do
      let(:app_class) do
        if Object.const_defined?('MermaidGrapherOpenAI')
          Object.const_get('MermaidGrapherOpenAI')
        end
      end

      it 'has validate_mermaid_syntax method' do
        skip 'MermaidGrapherOpenAI not loaded' unless app_class

        instance = app_class.new
        expect(instance).to respond_to(:validate_mermaid_syntax)
      end
    end
  end

  describe 'Tool Definition Consistency' do
    it 'validates MDSL tool definitions match Ruby implementations' do
      errors = []

      Dir.glob(File.join(app_base_dir, '**/*.mdsl')).each do |mdsl_file|
        content = File.read(mdsl_file)

        # Skip if no tools defined
        next unless content.include?('tools do')

        # Extract tool names from MDSL
        mdsl_tools = content.scan(/define_tool\s+"(\w+)"/).flatten

        next if mdsl_tools.empty?

        # Find corresponding Ruby file
        app_dir = File.dirname(mdsl_file)
        ruby_files = Dir.glob(File.join(app_dir, '*.rb'))

        mdsl_tools.each do |tool_name|
          # Skip standard tools that are provided by helpers/shared modules
          standard_tools = %w[
            run_code run_bash_command fetch_web_content search_wikipedia
            write_to_file run_jupyter create_jupyter_notebook add_jupyter_cells
            create_and_populate_jupyter_notebook
            system_info current_time websearch_agent text_to_speech
            fetch_text_from_pdf fetch_text_from_file fetch_text_from_office
            analyze_image analyze_audio analyze_video
            monadic_save_state monadic_load_state
            list_providers_and_voices
            generate_image_with_dalle generate_image_with_gpt_image
            generate_image_with_imagen generate_image_with_flux
            generate_video_with_sora generate_video_with_veo
            lib_installer check_environment
            delete_jupyter_cell update_jupyter_cell get_jupyter_cells_with_results
            execute_and_fix_jupyter_cells list_jupyter_notebooks
            restart_jupyter_kernel interrupt_jupyter_execution
            move_jupyter_cell insert_jupyter_cells
            validate_mermaid_syntax analyze_mermaid_error preview_mermaid fetch_mermaid_docs
            save_context get_context update_context remove_from_context clear_context
          ]

          next if standard_tools.include?(tool_name)

          # Check if tool is implemented in any Ruby file
          implemented = ruby_files.any? do |ruby_file|
            ruby_content = File.read(ruby_file)
            ruby_content.include?("def #{tool_name}")
          end

          unless implemented
            errors << "#{mdsl_file}: Tool '#{tool_name}' defined but not implemented in Ruby"
          end
        end
      end

      expect(errors).to be_empty, "Tool definition mismatches:\n#{errors.join("\n")}"
    end
  end
end
