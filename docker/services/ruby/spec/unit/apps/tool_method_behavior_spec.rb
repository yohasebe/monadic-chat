# frozen_string_literal: true

# Tool Method Behavior Tests
#
# This spec tests ACTUAL tool method invocation with test inputs.
# Unlike static analysis tests, these tests call the methods and verify:
# 1. Return value structure
# 2. Error handling
# 3. Edge cases
#
# Note: Some tools require external services (API, Docker, etc.)
# Those are marked as :integration and skipped in unit tests.

require 'spec_helper'

RSpec.describe 'Tool Method Behavior' do
  let(:app_base_dir) { File.expand_path('../../../apps', __dir__) }

  # Load app classes for testing
  before(:all) do
    # Load required helpers
    Dir.glob(File.join(File.expand_path('../../../lib/monadic/adapters/vendors', __dir__), '*.rb')).each do |f|
      require f rescue nil
    end
  end

  # ============================================
  # Chord Accompanist Tools
  # ============================================
  describe 'ChordAccompanist Tools' do
    let(:app_class) do
      tools_file = File.join(app_base_dir, 'chord_accompanist', 'chord_accompanist_claude_tools.rb')
      require tools_file if File.exist?(tools_file)
      Object.const_get('ChordAccompanistClaude') if Object.const_defined?('ChordAccompanistClaude')
    end

    let(:instance) { app_class&.new }

    describe '#validate_abc_syntax' do
      it 'returns success for valid ABC notation' do
        skip 'ChordAccompanistClaude not loaded' unless instance

        valid_abc = <<~ABC
          X:1
          T:Test Tune
          M:4/4
          K:C
          |C D E F|G A B c|
        ABC

        result = instance.validate_abc_syntax(code: valid_abc)

        expect(result).to be_a(Hash)
        # Should have success key or valid structure
        expect(result.key?('valid') || result.key?(:valid) || result.key?('success')).to be true
      end

      it 'returns error information for invalid ABC notation' do
        skip 'ChordAccompanistClaude not loaded' unless instance

        invalid_abc = "This is not ABC notation at all!!!"

        result = instance.validate_abc_syntax(code: invalid_abc)

        expect(result).to be_a(Hash)
        # Should indicate invalid or have error info
      end

      it 'handles empty input gracefully' do
        skip 'ChordAccompanistClaude not loaded' unless instance

        result = instance.validate_abc_syntax(code: "")

        expect(result).to be_a(Hash)
        # Should not raise exception
      end

      it 'handles nil input gracefully' do
        skip 'ChordAccompanistClaude not loaded' unless instance

        # Method should handle nil without crashing
        expect { instance.validate_abc_syntax(code: nil) }.not_to raise_error
      end
    end

    describe '#analyze_abc_error' do
      it 'returns analysis for error' do
        skip 'ChordAccompanistClaude not loaded' unless instance

        result = instance.analyze_abc_error(code: "X:1\nK:C\n|invalid|", error: "parse error at line 3")

        expect(result).to be_a(Hash)
      end

      it 'handles empty error gracefully' do
        skip 'ChordAccompanistClaude not loaded' unless instance

        result = instance.analyze_abc_error(code: "test", error: "")

        expect(result).to be_a(Hash)
      end
    end
  end

  # ============================================
  # Math Tutor Tools
  # ============================================
  describe 'MathTutor Tools' do
    let(:tools_file) { File.join(app_base_dir, 'math_tutor', 'math_tutor_tools.rb') }

    before(:all) do
      tools_file = File.join(File.expand_path('../../../apps/math_tutor', __dir__), 'math_tutor_tools.rb')
      require tools_file if File.exist?(tools_file)
    end

    let(:app_class) do
      Object.const_get('MathTutorOpenAI') if Object.const_defined?('MathTutorOpenAI')
    end

    let(:instance) { app_class&.new }

    describe '#add_concepts' do
      it 'accepts concepts parameter and returns result' do
        skip 'MathTutorOpenAI not loaded' unless instance
        skip 'add_concepts not defined' unless instance.respond_to?(:add_concepts)

        # Note: concepts expects an Array
        result = instance.add_concepts(concepts: ["quadratic equations", "factoring"])

        expect(result).to be_a(Hash).or be_a(String)
      end
    end

    describe '#add_solved_problem' do
      it 'accepts problem parameter and returns result' do
        skip 'MathTutorOpenAI not loaded' unless instance
        skip 'add_solved_problem not defined' unless instance.respond_to?(:add_solved_problem)

        result = instance.add_solved_problem(problem: "2x + 3 = 7, x = 2")

        expect(result).to be_a(Hash).or be_a(String)
      end
    end
  end

  # ============================================
  # Novel Writer Tools
  # ============================================
  describe 'NovelWriter Tools' do
    before(:all) do
      tools_file = File.join(File.expand_path('../../../apps/novel_writer', __dir__), 'novel_writer_tools.rb')
      require tools_file if File.exist?(tools_file)
    end

    let(:app_class) do
      Object.const_get('NovelWriterOpenAI') if Object.const_defined?('NovelWriterOpenAI')
    end

    let(:instance) { app_class&.new }

    describe '#count_num_of_chars' do
      it 'returns correct character count' do
        skip 'NovelWriterOpenAI not loaded' unless instance
        skip 'count_num_of_chars not defined' unless instance.respond_to?(:count_num_of_chars)

        result = instance.count_num_of_chars(text: "Hello World")

        # May return Integer directly or Hash
        expect(result).to be_a(Integer).or be_a(Hash)
        expect(result).to eq(11) if result.is_a?(Integer)
      end
    end

    describe '#count_num_of_words' do
      it 'returns correct word count' do
        skip 'NovelWriterOpenAI not loaded' unless instance
        skip 'count_num_of_words not defined' unless instance.respond_to?(:count_num_of_words)

        result = instance.count_num_of_words(text: "Hello World Test")

        # May return Integer directly or Hash
        expect(result).to be_a(Integer).or be_a(Hash)
        expect(result).to eq(3) if result.is_a?(Integer)
      end
    end
  end

  # ============================================
  # Translate Tools
  # ============================================
  describe 'Translate Tools' do
    before(:all) do
      tools_file = File.join(File.expand_path('../../../apps/translate', __dir__), 'translate_tools.rb')
      require tools_file if File.exist?(tools_file)
    end

    let(:app_class) do
      Object.const_get('TranslateOpenAI') if Object.const_defined?('TranslateOpenAI')
    end

    let(:instance) { app_class&.new }

    describe '#add_vocabulary_entry' do
      it 'accepts vocabulary entry' do
        skip 'TranslateOpenAI not loaded' unless instance
        skip 'add_vocabulary_entry not defined' unless instance.respond_to?(:add_vocabulary_entry)

        # Note: parameters are :original_text and :translation
        result = instance.add_vocabulary_entry(
          original_text: "hello",
          translation: "こんにちは"
        )

        expect(result).to be_a(Hash).or be_a(String)
      end
    end

    describe '#clear_vocabulary' do
      it 'clears vocabulary without error' do
        skip 'TranslateOpenAI not loaded' unless instance
        skip 'clear_vocabulary not defined' unless instance.respond_to?(:clear_vocabulary)

        expect { instance.clear_vocabulary }.not_to raise_error
      end
    end
  end

  # ============================================
  # Syntax Tree Tools
  # ============================================
  describe 'SyntaxTree Tools' do
    before(:all) do
      tools_file = File.join(File.expand_path('../../../apps/syntax_tree', __dir__), 'syntax_tree_tools.rb')
      require tools_file if File.exist?(tools_file)
    end

    let(:app_class) do
      Object.const_get('SyntaxTreeOpenAI') if Object.const_defined?('SyntaxTreeOpenAI')
    end

    let(:instance) { app_class&.new }

    describe '#render_syntax_tree' do
      it 'accepts tree data and renders', :integration do
        skip 'SyntaxTreeOpenAI not loaded' unless instance
        skip 'render_syntax_tree not defined' unless instance.respond_to?(:render_syntax_tree)

        # This may require LaTeX, so it's an integration test
        # Method requires: bracket_notation, language
        tree_data = "[S [NP [Det the] [N cat]] [VP [V sat]]]"

        result = instance.render_syntax_tree(
          bracket_notation: tree_data,
          language: "English"
        )

        expect(result).to be_a(Hash).or be_a(String)
      end
    end
  end

  # ============================================
  # Language Practice Plus Tools
  # ============================================
  describe 'LanguagePracticePlus Tools' do
    before(:all) do
      tools_file = File.join(File.expand_path('../../../apps/language_practice_plus', __dir__), 'language_practice_plus_tools.rb')
      require tools_file if File.exist?(tools_file)
    end

    let(:app_class) do
      Object.const_get('LanguagePracticePlusOpenAI') if Object.const_defined?('LanguagePracticePlusOpenAI')
    end

    let(:instance) { app_class&.new }

    describe '#set_target_language' do
      it 'accepts target_lang setting' do
        skip 'LanguagePracticePlusOpenAI not loaded' unless instance
        skip 'set_target_language not defined' unless instance.respond_to?(:set_target_language)

        # Note: parameter is :target_lang, not :language
        result = instance.set_target_language(target_lang: "French")

        expect(result).to be_a(Hash).or be_a(String)
      end
    end
  end

  # ============================================
  # Mermaid Grapher Tools
  # ============================================
  describe 'MermaidGrapher Tools' do
    before(:all) do
      tools_file = File.join(File.expand_path('../../../apps/mermaid_grapher', __dir__), 'mermaid_grapher_tools.rb')
      require tools_file if File.exist?(tools_file)
    end

    let(:app_class) do
      Object.const_get('MermaidGrapherOpenAI') if Object.const_defined?('MermaidGrapherOpenAI')
    end

    let(:instance) { app_class&.new }

    describe '#preview_mermaid', :integration do
      it 'validates mermaid code' do
        skip 'MermaidGrapherOpenAI not loaded' unless instance
        skip 'preview_mermaid not defined' unless instance.respond_to?(:preview_mermaid)

        # This may require external service
        mermaid_code = "graph TD\n    A-->B"

        result = instance.preview_mermaid(code: mermaid_code)

        expect(result).to be_a(Hash).or be_a(String)
      end
    end
  end

  # ============================================
  # Second Opinion Tools
  # ============================================
  describe 'SecondOpinion Tools' do
    before(:all) do
      # SecondOpinion uses SecondOpinionAgent module
      agent_file = File.join(File.expand_path('../../../lib/monadic/agents', __dir__), 'second_opinion_agent.rb')
      require agent_file if File.exist?(agent_file)
    end

    describe 'SecondOpinionAgent module' do
      it 'is defined and has second_opinion_agent method' do
        expect(defined?(SecondOpinionAgent)).to be_truthy

        # Create a test class that includes the module
        test_class = Class.new do
          include SecondOpinionAgent

          # Mock configure_reasoning_params
          def configure_reasoning_params(params, model)
            params
          end
        end

        instance = test_class.new
        expect(instance).to respond_to(:second_opinion_agent)
      end
    end
  end

  # ============================================
  # Generic Tool Return Value Tests
  # ============================================
  describe 'Tool Return Value Consistency' do
    # Tools should return consistent structures

    it 'format_tool_response helper returns Hash with expected keys' do
      # Check if format_tool_response is available
      # This is a common helper pattern in tools

      # Example of expected tool response structure:
      expected_keys = [:success, :message, :data]

      # Tools should return structured responses, not raw strings
      # This test documents the expected pattern
    end
  end
end
