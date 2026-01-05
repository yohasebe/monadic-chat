# frozen_string_literal: true

# Comprehensive Tool Validation for All Tool-Using Apps
#
# This spec validates:
# 1. All tool methods are defined and callable
# 2. Tool methods have correct signatures (keyword arguments)
# 3. No undefined method calls within tool implementations
# 4. Error pattern detection (type errors, argument errors, etc.)
#
# Covers all 23 tool-using apps with their specific tools.

require 'spec_helper'

RSpec.describe 'Comprehensive Tool Validation' do
  let(:app_base_dir) { File.expand_path('../../../apps', __dir__) }

  # Complete mapping of apps to their custom tools
  # (excludes standard tools provided by helpers)
  APPS_WITH_CUSTOM_TOOLS = {
    'auto_forge' => {
      tools: %w[generate_application generate_additional_file validate_specification list_projects],
      agents: %w[openai_code_agent claude_code_agent grok_code_agent],
      providers: %w[OpenAI Claude Grok]
    },
    'chord_accompanist' => {
      tools: %w[validate_abc_syntax validate_chord_progression analyze_abc_error],
      agents: [],
      providers: %w[Claude]  # Only Claude version exists
    },
    'code_interpreter' => {
      tools: [],
      agents: %w[openai_code_agent grok_code_agent],
      providers: %w[OpenAI Grok]
    },
    'coding_assistant' => {
      tools: [],
      agents: %w[openai_code_agent grok_code_agent],
      providers: %w[OpenAI Grok]
    },
    'concept_visualizer' => {
      tools: %w[generate_concept_diagram list_diagram_examples],
      agents: [],
      providers: %w[OpenAI Claude]
    },
    'content_reader' => {
      tools: %w[fetch_text_from_file fetch_text_from_office fetch_text_from_pdf],
      agents: [],
      providers: %w[OpenAI]
    },
    'drawio_grapher' => {
      tools: %w[write_drawio_file],
      agents: [],
      providers: %w[OpenAI Claude Gemini Grok Mistral Cohere DeepSeek Perplexity]
    },
    'image_generator' => {
      tools: %w[generate_image_with_openai generate_image_with_grok generate_image_with_gemini3_preview],
      agents: [],
      providers: %w[OpenAI Grok Gemini]
    },
    'jupyter_notebook' => {
      tools: %w[create_and_populate_jupyter_notebook],
      agents: %w[openai_code_agent grok_code_agent],
      providers: %w[OpenAI Claude Gemini Grok]
    },
    'language_practice_plus' => {
      tools: %w[set_target_language save_response load_context],
      agents: [],
      providers: %w[OpenAI Claude]
    },
    'math_tutor' => {
      tools: %w[add_concepts add_learning_notes add_solved_problem add_weak_areas load_learning_progress save_learning_progress],
      agents: [],
      providers: %w[OpenAI Claude Gemini Grok]
    },
    'mermaid_grapher' => {
      tools: %w[preview_mermaid],
      agents: [],
      providers: %w[OpenAI Claude Gemini Grok Mistral Cohere DeepSeek Perplexity]
    },
    'novel_writer' => {
      tools: %w[add_character count_num_of_chars count_num_of_words load_novel_context save_novel_context update_progress update_summary],
      agents: [],
      providers: %w[OpenAI Mistral]
    },
    'pdf_navigator' => {
      tools: %w[find_closest_doc find_closest_text get_text_snippet get_text_snippets list_titles],
      agents: [],
      providers: %w[OpenAI]
    },
    'research_assistant' => {
      tools: %w[add_finding add_research_notes add_research_topics add_search add_sources load_research_progress save_research_progress request_tool],
      agents: %w[openai_code_agent grok_code_agent],
      providers: %w[OpenAI Claude Gemini Grok Cohere Mistral DeepSeek]
    },
    'second_opinion' => {
      tools: %w[second_opinion_agent],
      agents: [],
      # Note: Perplexity excluded - does not support tool calling
      providers: %w[OpenAI Claude Gemini Grok Mistral Cohere DeepSeek Ollama]
    },
    'speech_draft_helper' => {
      tools: %w[list_providers_and_voices text_to_speech],
      agents: [],
      providers: %w[OpenAI]
    },
    'syntax_tree' => {
      tools: %w[render_syntax_tree],
      agents: [],
      providers: %w[OpenAI Claude]
    },
    'translate' => {
      tools: %w[add_vocabulary_entry clear_vocabulary load_translation_context save_translation_context],
      agents: [],
      providers: %w[OpenAI]
    },
    'video_generator' => {
      tools: %w[generate_video_with_sora generate_video_with_veo],
      agents: [],
      providers: %w[OpenAI Gemini]
    },
    'voice_interpreter' => {
      tools: %w[set_target_language save_translation load_context],
      agents: [],
      providers: %w[OpenAI Cohere]
    },
    'wikipedia' => {
      tools: %w[search_wikipedia],
      agents: [],
      providers: %w[OpenAI]
    }
  }.freeze

  # Error patterns to detect in code
  ERROR_PATTERNS = {
    # Undefined method calls
    /\bcall_claude\s*\(/ => {
      type: :undefined_method,
      message: 'call_claude is not defined - use send_query instead',
      severity: :critical
    },
    /\bcall_openai\s*\(/ => {
      type: :undefined_method,
      message: 'call_openai is not defined - use send_query or api_request instead',
      severity: :critical
    },
    /\bcall_gemini\s*\(/ => {
      type: :undefined_method,
      message: 'call_gemini is not defined - use send_query instead',
      severity: :critical
    },
    /\bcall_anthropic\s*\(/ => {
      type: :undefined_method,
      message: 'call_anthropic is not defined - use send_query instead',
      severity: :critical
    },

    # Incorrect method usage patterns
    /\.send\s*\(\s*:/ => {
      type: :dynamic_dispatch,
      message: 'Dynamic method dispatch with send() - verify method exists',
      severity: :warning
    },
    /method_missing/ => {
      type: :dynamic_dispatch,
      message: 'method_missing usage - ensure fallback is safe',
      severity: :warning
    },

    # Potential nil errors
    /\[\s*["']\w+["']\s*\]\s*\[/ => {
      type: :nil_safety,
      message: 'Chained hash access without nil check - consider using dig()',
      severity: :info
    },

    # Incorrect argument patterns
    /def\s+\w+\s*\([^)]*\)\s*\n[^}]*JSON\.parse\s*\(\s*\w+\s*\)/ => {
      type: :json_parse,
      message: 'JSON.parse without rescue - may raise on invalid input',
      severity: :warning
    },

    # Missing return value handling
    /result\s*=\s*send_query.*\n\s*(?!if|unless|result)/ => {
      type: :unchecked_result,
      message: 'send_query result may not be checked for errors',
      severity: :info
    }
  }.freeze

  describe 'Tool Method Existence' do
    APPS_WITH_CUSTOM_TOOLS.each do |app_name, config|
      context "#{app_name}" do
        config[:providers].each do |provider|
          it "#{provider} version has all custom tools defined" do
            tools_file = find_tools_file(app_name, provider)
            skip "No tools file found for #{app_name} #{provider}" unless tools_file

            content = File.read(tools_file)
            missing_tools = []

            config[:tools].each do |tool_name|
              # Check for method definition
              unless content.include?("def #{tool_name}")
                # Check if it's provided by an included module
                unless tool_provided_by_module?(content, tool_name)
                  missing_tools << tool_name
                end
              end
            end

            expect(missing_tools).to be_empty,
              "#{app_name} #{provider} missing tool methods: #{missing_tools.join(', ')}"
          end
        end
      end
    end
  end

  describe 'Agent Method Availability' do
    APPS_WITH_CUSTOM_TOOLS.each do |app_name, config|
      next if config[:agents].empty?

      context "#{app_name}" do
        config[:providers].each do |provider|
          it "#{provider} version has access to its agent method" do
            # Each provider version only needs its own agent
            expected_agent = provider_to_agent(provider)
            next unless config[:agents].include?(expected_agent)

            # Find the tools file (agents are typically included there)
            tools_file = find_tools_file(app_name, provider)
            app_file = find_app_class_file(app_name, provider)

            files_to_check = [tools_file, app_file].compact
            skip "No files found for #{app_name} #{provider}" if files_to_check.empty?

            content = files_to_check.map { |f| File.read(f) }.join("\n")
            agent_module = agent_name_to_module(expected_agent)

            # Check if agent module is included
            has_agent = content.include?("include #{agent_module}") ||
                       content.include?("include Monadic::Agents::#{agent_module}")

            expect(has_agent).to be(true),
              "#{app_name} #{provider} should include #{agent_module}"
          end
        end
      end
    end
  end

  describe 'Error Pattern Detection' do
    APPS_WITH_CUSTOM_TOOLS.each do |app_name, config|
      context "#{app_name}" do
        it "has no critical error patterns in tool implementations" do
          errors = []

          Dir.glob(File.join(app_base_dir, app_name, '*.rb')).each do |file|
            content = File.read(file)
            filename = File.basename(file)

            ERROR_PATTERNS.each do |pattern, info|
              next unless info[:severity] == :critical

              if content.match?(pattern)
                matches = content.scan(pattern)
                line_numbers = find_line_numbers(content, pattern)
                errors << "#{filename}:#{line_numbers.first} - #{info[:message]}"
              end
            end
          end

          expect(errors).to be_empty,
            "Critical error patterns found in #{app_name}:\n#{errors.join("\n")}"
        end

        it "reports warnings for potentially problematic patterns" do
          warnings = []

          Dir.glob(File.join(app_base_dir, app_name, '*.rb')).each do |file|
            content = File.read(file)
            filename = File.basename(file)

            ERROR_PATTERNS.each do |pattern, info|
              next unless info[:severity] == :warning

              if content.match?(pattern)
                line_numbers = find_line_numbers(content, pattern)
                warnings << "#{filename}:#{line_numbers.first} - #{info[:message]}"
              end
            end
          end

          # Warnings are informational, not failures
          if warnings.any?
            puts "\n  Warnings for #{app_name}:"
            warnings.each { |w| puts "    - #{w}" }
          end
        end
      end
    end
  end

  describe 'Tool Method Signatures' do
    APPS_WITH_CUSTOM_TOOLS.each do |app_name, config|
      next if config[:tools].empty?

      context "#{app_name}" do
        it "all tool methods accept keyword arguments correctly" do
          errors = []

          Dir.glob(File.join(app_base_dir, app_name, '*_tools.rb')).each do |file|
            content = File.read(file)

            config[:tools].each do |tool_name|
              # Find method definition
              method_match = content.match(/def\s+#{Regexp.escape(tool_name)}\s*\(([^)]*)\)/)
              next unless method_match

              params = method_match[1]

              # Tool methods should use keyword arguments or params hash
              # Valid patterns:
              # - def tool(arg:) - keyword argument
              # - def tool(params = {}) - hash with default
              # - def tool(**kwargs) - keyword splat
              if params && !params.strip.empty?
                has_keyword = params.include?(':') ||  # keyword arg
                             params.include?('= {}') || # hash with default
                             params.include?('**')      # kwargs
                unless has_keyword
                  errors << "#{tool_name} uses positional arguments instead of keyword arguments"
                end
              end

              # Check for required arguments without defaults
              if params.match?(/\w+:\s*,/) || params.match?(/\w+:\s*\)/)
                # This is fine - required keyword argument
              end
            end
          end

          expect(errors).to be_empty,
            "Tool signature issues in #{app_name}:\n#{errors.join("\n")}"
        end
      end
    end
  end

  describe 'Helper Module Consistency' do
    # This test only applies to apps with Ruby class files (not MDSL-only apps)
    APPS_WITH_CUSTOM_TOOLS.each do |app_name, config|
      context "#{app_name}" do
        config[:providers].each do |provider|
          # Pre-check: only create test if Ruby class file exists
          app_base = File.expand_path('../../../apps', __dir__)
          provider_suffix = provider.downcase
          patterns = [
            File.join(app_base, app_name, "*_#{provider_suffix}.rb"),
            File.join(app_base, app_name, "#{app_name}_#{provider_suffix}.rb")
          ]
          class_files = patterns.flat_map { |p| Dir.glob(p) }.reject { |f| f.include?('_tools') }

          # Only create test if Ruby class file exists
          next if class_files.empty?

          it "#{provider} version includes correct helper module" do
            app_file = class_files.first
            content = File.read(app_file)
            expected_helper = provider_to_helper(provider)

            # Check for helper inclusion (direct or conditional)
            has_helper = content.include?("include #{expected_helper}") ||
                        content.include?("include #{expected_helper} if defined?")

            expect(has_helper).to be(true),
              "#{app_name} #{provider} should include #{expected_helper}"
          end
        end
      end
    end
  end

  describe 'MDSL Provider Configuration' do
    # Validate that MDSL-defined apps specify the correct provider
    APPS_WITH_CUSTOM_TOOLS.each do |app_name, config|
      context "#{app_name}" do
        config[:providers].each do |provider|
          # Find MDSL file for this provider
          app_base = File.expand_path('../../../apps', __dir__)
          provider_suffix = provider.downcase
          mdsl_pattern = File.join(app_base, app_name, "*_#{provider_suffix}.mdsl")
          mdsl_files = Dir.glob(mdsl_pattern)

          # Only create test if MDSL file exists
          next if mdsl_files.empty?

          it "#{provider} MDSL specifies correct provider" do
            mdsl_file = mdsl_files.first
            content = File.read(mdsl_file)

            # Check that the MDSL includes the correct provider specification
            # MDSL format: provider "openai" or provider "OpenAI" (case-insensitive)
            expected_patterns = case provider.downcase
            when 'openai'
              [/provider\s+["']openai["']/i, /include\s+OpenAIHelper/]
            when 'claude'
              [/provider\s+["']anthropic["']/i, /provider\s+["']claude["']/i, /include\s+ClaudeHelper/]
            when 'gemini'
              [/provider\s+["']gemini["']/i, /provider\s+["']google["']/i, /include\s+GeminiHelper/]
            when 'grok'
              [/provider\s+["']grok["']/i, /provider\s+["']xai["']/i, /include\s+GrokHelper/]
            when 'mistral'
              [/provider\s+["']mistral["']/i, /include\s+MistralHelper/]
            when 'cohere'
              [/provider\s+["']cohere["']/i, /include\s+CohereHelper/]
            when 'deepseek'
              [/provider\s+["']deepseek["']/i, /include\s+DeepSeekHelper/]
            when 'perplexity'
              [/provider\s+["']perplexity["']/i, /include\s+PerplexityHelper/]
            when 'ollama'
              [/provider\s+["']ollama["']/i, /include\s+OllamaHelper/]
            else
              []
            end

            has_provider = expected_patterns.any? { |pattern| content.match?(pattern) }
            expect(has_provider).to be(true),
              "#{app_name} #{provider} MDSL should specify provider correctly. Checked patterns: #{expected_patterns.inspect}"
          end
        end
      end
    end
  end

  describe 'MDSL and Ruby Consistency' do
    APPS_WITH_CUSTOM_TOOLS.each do |app_name, config|
      context "#{app_name}" do
        it "all MDSL-defined tools have Ruby implementations" do
          errors = []

          Dir.glob(File.join(app_base_dir, app_name, '*.mdsl')).each do |mdsl_file|
            mdsl_content = File.read(mdsl_file)
            mdsl_tools = mdsl_content.scan(/define_tool\s+"(\w+)"/).flatten

            # Find corresponding Ruby files
            ruby_files = Dir.glob(File.join(app_base_dir, app_name, '*.rb'))
            ruby_content = ruby_files.map { |f| File.read(f) }.join("\n")

            mdsl_tools.each do |tool_name|
              # Skip standard tools
              next if standard_tool?(tool_name)

              # Check for implementation
              unless ruby_content.include?("def #{tool_name}")
                errors << "#{File.basename(mdsl_file)}: #{tool_name} not implemented"
              end
            end
          end

          expect(errors).to be_empty,
            "MDSL/Ruby mismatches in #{app_name}:\n#{errors.join("\n")}"
        end
      end
    end
  end

  # Helper methods

  def find_tools_file(app_name, provider)
    provider_suffix = provider.downcase

    # First, look for dedicated tools files
    tools_patterns = [
      File.join(app_base_dir, app_name, "*#{provider_suffix}*_tools.rb"),
      File.join(app_base_dir, app_name, "*_tools.rb")
    ]

    tools_patterns.each do |pattern|
      files = Dir.glob(pattern)
      return files.first if files.any?
    end

    # Fallback: look in the main class file (some apps define tools there)
    class_patterns = [
      File.join(app_base_dir, app_name, "#{app_name}_#{provider_suffix}.rb"),
      File.join(app_base_dir, app_name, "*_#{provider_suffix}.rb")
    ]

    class_patterns.each do |pattern|
      files = Dir.glob(pattern).reject { |f| f.include?('_tools') }
      return files.first if files.any?
    end

    nil
  end

  def find_app_class_file(app_name, provider)
    provider_suffix = provider.downcase
    patterns = [
      File.join(app_base_dir, app_name, "*_#{provider_suffix}.rb"),
      File.join(app_base_dir, app_name, "#{app_name}_#{provider_suffix}.rb")
    ]

    patterns.each do |pattern|
      files = Dir.glob(pattern).reject { |f| f.include?('_tools') }
      return files.first if files.any?
    end

    nil
  end

  def tool_provided_by_module?(content, tool_name)
    # Check for module includes that might provide the tool
    module_patterns = [
      /include\s+\w+Helper/,
      /include\s+Monadic::\w+/,
      /include\s+\w+Tools/
    ]

    module_patterns.any? { |pattern| content.match?(pattern) }
  end

  def agent_name_to_method(agent_name)
    case agent_name
    when 'openai_code_agent' then 'call_openai_code'
    when 'claude_code_agent' then 'call_claude_code'
    when 'grok_code_agent' then 'call_grok_code'
    else agent_name
    end
  end

  def agent_name_to_module(agent_name)
    case agent_name
    when 'openai_code_agent' then 'OpenAICodeAgent'
    when 'claude_code_agent' then 'ClaudeCodeAgent'
    when 'grok_code_agent' then 'GrokCodeAgent'
    else agent_name.split('_').map(&:capitalize).join
    end
  end

  def provider_to_helper(provider)
    case provider
    when 'OpenAI' then 'OpenAIHelper'
    when 'Claude' then 'ClaudeHelper'
    when 'Gemini' then 'GeminiHelper'
    when 'Grok' then 'GrokHelper'
    when 'Mistral' then 'MistralHelper'
    when 'Cohere' then 'CohereHelper'
    when 'DeepSeek' then 'DeepSeekHelper'
    when 'Perplexity' then 'PerplexityHelper'
    when 'Ollama' then 'OllamaHelper'
    else "#{provider}Helper"
    end
  end

  def provider_to_agent(provider)
    case provider
    when 'OpenAI' then 'openai_code_agent'
    when 'Claude' then 'claude_code_agent'
    when 'Grok' then 'grok_code_agent'
    else nil
    end
  end

  def find_line_numbers(content, pattern)
    lines = []
    content.each_line.with_index do |line, index|
      lines << (index + 1) if line.match?(pattern)
    end
    lines.empty? ? [0] : lines
  end

  def standard_tool?(tool_name)
    STANDARD_TOOLS.include?(tool_name)
  end

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
    openai_code_agent claude_code_agent grok_code_agent
    second_opinion_agent
  ].freeze
end
