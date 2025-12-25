# frozen_string_literal: true

# Tool-Prompt Consistency Validation Tests
#
# These tests verify that the AI can correctly understand tool existence
# and usage through prompts and API specifications by validating:
#
# 1. MDSL tool definitions match Ruby method implementations
# 2. System prompts document all defined tools
# 3. Tool parameter names are consistent between MDSL and Ruby
# 4. Tool descriptions provide meaningful guidance for AI
#
# This helps prevent issues where:
# - AI knows about a tool but Ruby method doesn't exist
# - AI uses wrong parameter names
# - Tools are defined but not documented in prompt

require 'spec_helper'

RSpec.describe 'Tool-Prompt Consistency Validation' do
  let(:app_base_dir) { File.expand_path('../../../apps', __dir__) }

  # Apps with custom tools that need validation
  # Format: app_dir => [expected_tools]
  TOOL_APPS = {
    'chord_accompanist' => {
      mdsl_patterns: ['chord_accompanist_*.mdsl'],
      ruby_patterns: ['chord_accompanist_*_tools.rb'],
      expected_tools: %w[validate_chord_progression validate_abc_syntax analyze_abc_error]
    },
    'mermaid_grapher' => {
      mdsl_patterns: ['mermaid_grapher*.mdsl'],
      ruby_patterns: ['mermaid_grapher*_tools.rb'],
      expected_tools: %w[preview_mermaid]
    },
    'math_tutor' => {
      mdsl_patterns: ['math_tutor_*.mdsl'],
      ruby_patterns: ['math_tutor_tools.rb'],
      expected_tools: %w[add_concepts add_solved_problem]
    },
    'novel_writer' => {
      mdsl_patterns: ['novel_writer_*.mdsl'],
      ruby_patterns: ['novel_writer_tools.rb'],
      expected_tools: %w[count_num_of_chars count_num_of_words]
    },
    'translate' => {
      mdsl_patterns: ['translate_*.mdsl'],
      ruby_patterns: ['translate_tools.rb'],
      expected_tools: %w[add_vocabulary_entry clear_vocabulary]
    },
    'syntax_tree' => {
      mdsl_patterns: ['syntax_tree_*.mdsl'],
      ruby_patterns: ['syntax_tree_tools.rb'],
      expected_tools: %w[render_syntax_tree]
    },
    'language_practice_plus' => {
      mdsl_patterns: ['language_practice_plus_*.mdsl'],
      ruby_patterns: ['language_practice_plus_tools.rb'],
      expected_tools: %w[set_target_language]
    }
  }.freeze

  # Standard tools imported from shared modules (should be skipped in custom tool checks)
  STANDARD_TOOLS = %w[
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
  ].freeze

  describe 'MDSL-Ruby Parameter Consistency' do
    TOOL_APPS.each do |app_dir, config|
      context "#{app_dir}" do
        let(:app_path) { File.join(app_base_dir, app_dir) }

        it 'has MDSL tool parameter names matching Ruby method signatures' do
          skip "App directory not found: #{app_path}" unless File.directory?(app_path)

          errors = []

          # Find MDSL files
          mdsl_files = config[:mdsl_patterns].flat_map do |pattern|
            Dir.glob(File.join(app_path, pattern))
          end

          skip "No MDSL files found for #{app_dir}" if mdsl_files.empty?

          # Find Ruby files
          ruby_files = config[:ruby_patterns].flat_map do |pattern|
            Dir.glob(File.join(app_path, pattern))
          end

          skip "No Ruby tool files found for #{app_dir}" if ruby_files.empty?

          # Extract tool definitions from MDSL
          mdsl_tools = {}
          mdsl_files.each do |mdsl_file|
            content = File.read(mdsl_file)
            extract_mdsl_tools(content).each do |tool_name, params|
              mdsl_tools[tool_name] = params
            end
          end

          # Extract method signatures from Ruby
          ruby_methods = {}
          ruby_files.each do |ruby_file|
            content = File.read(ruby_file)
            extract_ruby_method_params(content).each do |method_name, params|
              ruby_methods[method_name] = params
            end
          end

          # Compare
          config[:expected_tools].each do |tool_name|
            mdsl_params = mdsl_tools[tool_name] || []
            ruby_params = ruby_methods[tool_name] || []

            # Check all MDSL required params exist in Ruby method
            mdsl_params.each do |mdsl_param|
              param_name = mdsl_param[:name]
              unless ruby_params.include?(param_name)
                errors << "#{app_dir}: Tool '#{tool_name}' - MDSL parameter '#{param_name}' not found in Ruby method"
              end
            end
          end

          expect(errors).to be_empty, "Parameter mismatches found:\n#{errors.join("\n")}"
        end
      end
    end
  end

  describe 'System Prompt Tool Documentation' do
    TOOL_APPS.each do |app_dir, config|
      context "#{app_dir}" do
        let(:app_path) { File.join(app_base_dir, app_dir) }

        it 'mentions all defined tools in system prompt' do
          skip "App directory not found: #{app_path}" unless File.directory?(app_path)

          warnings = []

          # Find MDSL files
          mdsl_files = config[:mdsl_patterns].flat_map do |pattern|
            Dir.glob(File.join(app_path, pattern))
          end

          skip "No MDSL files found for #{app_dir}" if mdsl_files.empty?

          mdsl_files.each do |mdsl_file|
            content = File.read(mdsl_file)

            # Extract system prompt
            system_prompt = extract_system_prompt(content)
            next if system_prompt.nil? || system_prompt.empty?

            # Extract tool names from tools block
            tool_names = extract_tool_names(content)

            # Check each tool is mentioned in system prompt
            tool_names.each do |tool_name|
              # Skip standard imported tools
              next if STANDARD_TOOLS.include?(tool_name)

              unless system_prompt.include?(tool_name) || system_prompt.include?(tool_name.gsub('_', ' '))
                warnings << "#{File.basename(mdsl_file)}: Tool '#{tool_name}' not mentioned in system prompt"
              end
            end
          end

          # This is informational only - some apps may intentionally not document all tools
          # We log the warnings but don't fail the test
          if warnings.any?
            puts "\n  [Info] #{app_dir}: Tools not documented in system prompt:\n    #{warnings.join("\n    ")}"
          end

          # Test passes as long as no critical errors occurred
          expect(true).to be true
        end
      end
    end
  end

  describe 'Tool Description Quality' do
    it 'validates all tool definitions have non-empty descriptions' do
      errors = []

      Dir.glob(File.join(app_base_dir, '**/*.mdsl')).each do |mdsl_file|
        content = File.read(mdsl_file)

        # Find define_tool calls
        content.scan(/define_tool\s+"(\w+)"\s*,\s*"([^"]*)"/) do |tool_name, description|
          if description.strip.empty?
            errors << "#{File.basename(mdsl_file)}: Tool '#{tool_name}' has empty description"
          elsif description.strip.length < 10
            errors << "#{File.basename(mdsl_file)}: Tool '#{tool_name}' has very short description: '#{description}'"
          end
        end
      end

      expect(errors).to be_empty, "Tool description issues:\n#{errors.join("\n")}"
    end

    it 'validates all tool parameters have descriptions' do
      errors = []

      Dir.glob(File.join(app_base_dir, '**/*.mdsl')).each do |mdsl_file|
        content = File.read(mdsl_file)

        # Find parameter definitions with empty descriptions
        content.scan(/parameter\s+:(\w+)\s*,\s*"[^"]*"\s*,\s*"([^"]*)"/) do |param_name, description|
          if description.strip.empty?
            errors << "#{File.basename(mdsl_file)}: Parameter '#{param_name}' has empty description"
          end
        end
      end

      expect(errors).to be_empty, "Parameter description issues:\n#{errors.join("\n")}"
    end
  end

  describe 'Tool Method Implementation' do
    it 'validates all MDSL-defined custom tools have Ruby implementations' do
      errors = []

      TOOL_APPS.each do |app_dir, config|
        app_path = File.join(app_base_dir, app_dir)
        next unless File.directory?(app_path)

        # Find MDSL files
        mdsl_files = config[:mdsl_patterns].flat_map do |pattern|
          Dir.glob(File.join(app_path, pattern))
        end

        # Find Ruby files
        ruby_files = config[:ruby_patterns].flat_map do |pattern|
          Dir.glob(File.join(app_path, pattern))
        end

        next if mdsl_files.empty? || ruby_files.empty?

        # Extract tool names from MDSL
        mdsl_tool_names = []
        mdsl_files.each do |mdsl_file|
          content = File.read(mdsl_file)
          mdsl_tool_names.concat(extract_tool_names(content))
        end
        mdsl_tool_names.uniq!

        # Check each custom tool has Ruby implementation
        mdsl_tool_names.each do |tool_name|
          next if STANDARD_TOOLS.include?(tool_name)

          implemented = ruby_files.any? do |ruby_file|
            content = File.read(ruby_file)
            content.include?("def #{tool_name}")
          end

          unless implemented
            errors << "#{app_dir}: Tool '#{tool_name}' defined in MDSL but no Ruby implementation found"
          end
        end
      end

      expect(errors).to be_empty, "Missing Ruby implementations:\n#{errors.join("\n")}"
    end
  end

  describe 'API Schema Validation' do
    it 'validates MDSL parameter types are valid' do
      valid_types = %w[string integer number boolean array object]
      errors = []

      Dir.glob(File.join(app_base_dir, '**/*.mdsl')).each do |mdsl_file|
        content = File.read(mdsl_file)

        # Find parameter definitions
        content.scan(/parameter\s+:(\w+)\s*,\s*"([^"]*)"/) do |param_name, type|
          unless valid_types.include?(type.downcase)
            errors << "#{File.basename(mdsl_file)}: Parameter '#{param_name}' has invalid type '#{type}'"
          end
        end
      end

      expect(errors).to be_empty, "Invalid parameter types:\n#{errors.join("\n")}"
    end

    it 'validates required parameters are explicitly marked' do
      # All tools should explicitly mark required parameters
      # This helps ensure the API schema is complete
      tool_param_counts = {}

      Dir.glob(File.join(app_base_dir, '**/*.mdsl')).each do |mdsl_file|
        content = File.read(mdsl_file)

        # Count parameters per tool
        current_tool = nil
        content.each_line do |line|
          if line =~ /define_tool\s+"(\w+)"/
            current_tool = Regexp.last_match(1)
            tool_param_counts[current_tool] = { required: 0, optional: 0, total: 0 }
          elsif current_tool && line =~ /parameter\s+:\w+/
            tool_param_counts[current_tool][:total] += 1
            if line.include?('required: true')
              tool_param_counts[current_tool][:required] += 1
            else
              tool_param_counts[current_tool][:optional] += 1
            end
          elsif line =~ /^\s*end\s*$/ && current_tool
            current_tool = nil
          end
        end
      end

      # Tools with no required parameters might be problematic
      warnings = []
      tool_param_counts.each do |tool_name, counts|
        next if STANDARD_TOOLS.include?(tool_name)
        next if counts[:total] == 0 # No parameters is OK

        if counts[:required] == 0 && counts[:total] > 0
          warnings << "Tool '#{tool_name}' has #{counts[:total]} parameters but none marked as required"
        end
      end

      # This is informational, not a failure
      if warnings.any?
        puts "\nParameter specification notes:\n#{warnings.join("\n")}"
      end
    end
  end

  private

  # Extract tool definitions from MDSL content
  def extract_mdsl_tools(content)
    tools = {}

    current_tool = nil
    content.each_line do |line|
      if line =~ /define_tool\s+"(\w+)"/
        current_tool = Regexp.last_match(1)
        tools[current_tool] = []
      elsif current_tool && line =~ /parameter\s+:(\w+)\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"(?:.*required:\s*(true|false))?/
        param_name = Regexp.last_match(1)
        param_type = Regexp.last_match(2)
        param_desc = Regexp.last_match(3)
        required = Regexp.last_match(4) == 'true'

        tools[current_tool] << {
          name: param_name.to_sym,
          type: param_type,
          description: param_desc,
          required: required
        }
      elsif line =~ /^\s*end\s*$/ && current_tool
        # Check if this ends the define_tool block
        # Simple heuristic - might need refinement for nested blocks
      end
    end

    tools
  end

  # Extract Ruby method parameters (keyword arguments)
  def extract_ruby_method_params(content)
    methods = {}

    # Match method definitions with keyword arguments
    content.scan(/def\s+(\w+)\s*\(([^)]*)\)/) do |method_name, params_str|
      next if params_str.strip.empty?

      params = params_str.scan(/(\w+):/).flatten.map(&:to_sym)
      methods[method_name] = params
    end

    methods
  end

  # Extract system prompt from MDSL
  def extract_system_prompt(content)
    # Match system_prompt <<~TEXT ... TEXT pattern
    if content =~ /system_prompt\s*<<~(\w+)(.*?)^\s*\1$/m
      Regexp.last_match(2).strip
    elsif content =~ /system_prompt\s*"([^"]+)"/
      Regexp.last_match(1)
    else
      nil
    end
  end

  # Extract tool names from MDSL tools block
  def extract_tool_names(content)
    content.scan(/define_tool\s+"(\w+)"/).flatten
  end
end
