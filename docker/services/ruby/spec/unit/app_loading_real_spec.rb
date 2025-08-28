# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe "App Loading and Initialization (Real Implementation)" do
  let(:app_base_dir) { 
    # Handle both direct execution and rake execution
    if Dir.pwd.end_with?('docker/services/ruby')
      File.join(Dir.pwd, "apps")
    else
      File.join(Dir.pwd, "docker", "services", "ruby", "apps")
    end
  }
  let(:test_errors) { [] }
  
  before(:each) do
    # Clear any previous loading errors
    $MONADIC_LOADING_ERRORS = [] if defined?($MONADIC_LOADING_ERRORS)
    # Note: We're NOT mocking APPS constant - using the real one if it exists
  end

  describe "App File Discovery" do
    it "discovers all Ruby app files" do
      ruby_files = Dir.glob(File.join(app_base_dir, "**/*.rb"))
      expect(ruby_files).not_to be_empty
      ruby_files.each do |file|
        expect(File.exist?(file)).to be true
        expect(file).to end_with('.rb')
      end
    end

    it "discovers all MDSL app files" do
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      expect(mdsl_files).not_to be_empty
      mdsl_files.each do |file|
        expect(File.exist?(file)).to be true
        expect(file).to end_with('.mdsl')
      end
    end
  end

  describe "App File Validation" do
    it "validates all Ruby app files can be loaded without syntax errors" do
      ruby_files = Dir.glob(File.join(app_base_dir, "**/*.rb"))
      
      ruby_files.each do |file|
        begin
          # Check syntax without executing
          code = File.read(file)
          RubyVM::InstructionSequence.compile(code, file)
        rescue SyntaxError => e
          test_errors << "Syntax error in #{file}: #{e.message}"
        rescue => e
          # Other errors are acceptable at this level (missing dependencies, etc.)
        end
      end
      
      expect(test_errors).to be_empty, "Syntax errors found:\n#{test_errors.join("\n")}"
    end

    it "validates all MDSL app files have valid structure" do
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |file|
        content = File.read(file)
        
        # Basic MDSL structure validation
        expect(content).to match(/app\s+"[^"]+"\s+do/), "#{file} should have proper app declaration"
        # Allow both inline descriptions, module references, and multi-language block format
        expect(content).to match(/(description\s+<<~TEXT|description\s+\w+::\w+|description\s+do)/), "#{file} should have description"
        # Allow both inline icons and module references
        expect(content).to match(/(icon\s+"[^"]+"|icon\s+\w+::\w+)/), "#{file} should have icon"
        # Allow both system_prompt formats and module references
        expect(content).to match(/(system_prompt\s+<<~(TEXT|PROMPT)|system_prompt\s+\w+::\w+)/), "#{file} should have system_prompt"
        expect(content).to match(/llm\s+do/), "#{file} should have llm configuration"
        expect(content).to match(/features\s+do/), "#{file} should have features configuration"
      end
    end
  end

  describe "App Dependency Validation" do
    it "validates Ruby apps have required include statements" do
      ruby_files = Dir.glob(File.join(app_base_dir, "**/*.rb"))
      
      ruby_files.each do |file|
        content = File.read(file)
        next unless content.include?("class") && content.include?("< MonadicApp")
        
        # Check for required helper includes based on provider
        # Skip MDSL-only support files, module-based files, and tool implementation files
        module_based_files = ["chat_app.rb", "coding_assistant_constants.rb", "drawio_grapher_tools.rb", "mermaid_grapher_tools.rb", "novel_writer_tools.rb", "research_assistant_constants.rb", "monadic_help_openai.rb"]
        tool_implementation_files = ["_tools.rb"]
        
        # Skip if it's a module-based file or a tool implementation file
        is_tool_file = tool_implementation_files.any? { |pattern| file.include?(pattern) }
        is_module_file = module_based_files.any? { |f| file.end_with?(f) }
        
        unless is_module_file || is_tool_file || content.match(/include\s+\w+Agent/)
          if content.include?("OpenAI") || content.include?("gpt-")
            expect(content).to match(/include\s+OpenAIHelper/), "#{file} should include OpenAIHelper"
          end
        end
        
        unless is_module_file || is_tool_file || content.match(/include\s+\w+Agent/)
          if content.include?("Claude") || content.include?("claude-")
            expect(content).to match(/include\s+ClaudeHelper/), "#{file} should include ClaudeHelper"
          end
        end
        
        # Check for agent includes when tools are used
        if content.include?("second_opinion")
          expect(content).to match(/include\s+SecondOpinionAgent/), "#{file} should include SecondOpinionAgent"
        end
        
        # Check for websearch method calls, not just string mentions
        if content.match(/def\s+websearch|\.websearch|websearch_agent\(/)
          expect(content).to match(/include\s+WebSearchAgent/), "#{file} should include WebSearchAgent"
        end
      end
    end

    it "validates apps with tools have corresponding implementation methods" do
      # Find MDSL files with tool definitions
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |mdsl_file|
        content = File.read(mdsl_file)
        next unless content.include?("tools do")
        
        # Extract tool names using regex
        tool_matches = content.scan(/define_tool\s+"([^"]+)"/)
        next if tool_matches.empty?
        
        # Find corresponding Ruby file
        base_name = File.basename(mdsl_file, ".mdsl")
        app_dir = File.dirname(mdsl_file)
        
        # Look for Ruby implementation files in the same directory
        ruby_files = Dir.glob(File.join(app_dir, "*.rb"))
        
        # If no Ruby files, check if tools are provided by included agents
        if ruby_files.empty?
          # Some tools might be provided by included agents/helpers
          # This is acceptable for certain patterns
          next
        end
        
        # Skip validation for apps that use standard helper methods
        standard_tools = %w[
          fetch_text_from_office fetch_text_from_pdf fetch_text_from_file
          analyze_image analyze_audio analyze_video
          run_code run_bash_command lib_installer check_environment
          fetch_web_content search_wikipedia
          write_to_file run_jupyter create_jupyter_notebook add_jupyter_cells system_info
          delete_jupyter_cell update_jupyter_cell get_jupyter_cells_with_results execute_and_fix_jupyter_cells
          list_jupyter_notebooks
          restart_jupyter_kernel interrupt_jupyter_execution move_jupyter_cell insert_jupyter_cells
          websearch_agent list_providers_and_voices text_to_speech
          generate_video_with_veo generate_image_with_imagen
          validate_mermaid_syntax analyze_mermaid_error preview_mermaid fetch_mermaid_docs
          current_time
        ]
        
        tools_to_check = tool_matches.flatten.reject { |tool| standard_tools.include?(tool) }
        
        # Check that custom tools (not standard ones) are implemented
        tools_to_check.each do |tool_name|
          ruby_implementation_found = false
          
          ruby_files.each do |ruby_file|
            ruby_content = File.read(ruby_file)
            
            # Check for direct method implementation
            if ruby_content.include?("def #{tool_name}")
              ruby_implementation_found = true
              break
            end
            
            # Check for agent includes that provide the method
            agent_includes = ruby_content.scan(/include\s+(\w+Agent)/)
            if agent_includes.any? { |agent| tool_name.include?(agent.first.downcase.gsub('agent', '')) }
              ruby_implementation_found = true
              break
            end
          end
          
          unless ruby_implementation_found
            test_errors << "Tool '#{tool_name}' in #{mdsl_file} has no implementation in corresponding Ruby files"
          end
        end
      end
      
      expect(test_errors).to be_empty, "Missing tool implementations:\n#{test_errors.join("\n")}"
    end
  end

  describe "App Configuration Completeness" do
    it "validates all apps have required configuration elements" do
      # Test both Ruby and MDSL apps
      all_app_files = Dir.glob(File.join(app_base_dir, "**/*.{rb,mdsl}"))
      
      all_app_files.each do |file|
        content = File.read(file)
        
        if file.end_with?('.rb') && content.include?("< MonadicApp")
          # Ruby app validation - Skip MDSL support files and module-based files
          module_based_files = ["chat_app.rb", "coding_assistant_constants.rb", "drawio_grapher_tools.rb", "mermaid_grapher_tools.rb", "novel_writer_tools.rb", "research_assistant_constants.rb"]
          unless module_based_files.any? { |f| file.end_with?(f) } || content.match(/include\s+\w+Agent/) || !content.include?("@settings")
            expect(content).to match(/@settings\s*=\s*\{/), "#{file} should have @settings hash"
          end
          
          if content.include?("@settings")
            expect(content).to match(/display_name/), "#{file} should have display_name in settings"
            expect(content).to match(/description/), "#{file} should have description in settings"
            expect(content).to match(/icon/), "#{file} should have icon in settings"
          end
          
        elsif file.end_with?('.mdsl')
          # MDSL app validation already done in previous test
          # Additional checks can be added here
        end
      end
    end
  end

  describe "App Loading Error Detection" do
    it "validates correct MDSL app naming patterns" do
      issues = []
      
      # Check MDSL apps for correct naming patterns
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      mdsl_files.each do |file|
        content = File.read(file)
        
        # Extract app identifier and display_name
        app_match = content.match(/app\s+"([^"]+)"\s+do/)
        display_name_match = content.match(/display_name\s+"([^"]+)"/)
        provider_match = content.match(/provider\s+"([^"]+)"/)
        group_match = content.match(/group\s+"([^"]+)"/)
        
        next unless app_match
        
        app_id = app_match[1]
        display_name = display_name_match ? display_name_match[1] : nil
        provider = provider_match ? provider_match[1] : nil
        group = group_match ? group_match[1] : nil
        
        # Check for correct provider suffix in app identifier
        if provider
          expected_suffixes = case provider.downcase
                             when "openai" then ["OpenAI"]
                             when "anthropic" then ["Claude"]
                             when "google", "gemini" then ["Gemini"]
                             when "mistral" then ["Mistral", "MistralAI"]
                             when "cohere" then ["Cohere"]
                             when "perplexity" then ["Perplexity"]
                             when "x", "xai", "grok" then ["Grok"]
                             when "deepseek" then ["DeepSeek"]
                             else [provider.capitalize]
                             end
          
          # Skip validation for apps with non-standard naming (like single-provider apps)
          # Also skip legacy apps that haven't been updated yet
          legacy_apps = ["VideoDescriberApp", "Wikipedia"]
          unless expected_suffixes.any? { |suffix| app_id.end_with?(suffix) } || app_id.include?(" ") || legacy_apps.include?(app_id)
            issues << "#{file}: App ID '#{app_id}' should end with one of #{expected_suffixes.join(', ')} for provider '#{provider}'"
          end
        end
        
        # Check that display_name doesn't include provider info
        if display_name && provider
          provider_names = ["OpenAI", "Claude", "Anthropic", "Gemini", "Google", "Mistral", "Cohere", "Perplexity", "Grok", "xAI", "DeepSeek"]
          if provider_names.any? { |pname| display_name.include?(pname) }
            issues << "#{file}: Display name '#{display_name}' should not include provider information"
          end
        end
        
        # Check that group matches provider (allowing existing variations)
        if provider && group
          expected_groups = case provider.downcase
                           when "openai" then ["OpenAI"]
                           when "anthropic" then ["Anthropic"]
                           when "google", "gemini" then ["Google", "Gemini"]
                           when "mistral" then ["Mistral"]
                           when "cohere" then ["Cohere"]
                           when "perplexity" then ["Perplexity"]
                           when "x", "xai", "grok" then ["xAI"]
                           when "deepseek" then ["DeepSeek"]
                           else [provider.capitalize]
                           end
          
          unless expected_groups.include?(group)
            issues << "#{file}: Group '#{group}' should be one of #{expected_groups.join(', ')} for provider '#{provider}'"
          end
        end
      end
      
      expect(issues).to be_empty, "MDSL naming pattern issues:\n#{issues.join("\n")}"
    end

    it "validates MDSL and Ruby app coexistence follows expected patterns" do
      issues = []
      
      # Check each app directory
      app_dirs = Dir.glob(File.join(app_base_dir, "*/"))
      app_dirs.each do |app_dir|
        mdsl_files = Dir.glob(File.join(app_dir, "*.mdsl"))
        ruby_files = Dir.glob(File.join(app_dir, "*.rb"))
        
        # Pattern 1: Provider-specific MDSL files with shared Ruby module
        if mdsl_files.length > 1 && ruby_files.length == 1
          # This is expected pattern for multi-provider apps
          next
        end
        
        # Pattern 2: Single MDSL with implementation Ruby file
        if mdsl_files.length == 1 && ruby_files.length == 1
          # Check if Ruby file is just implementation (has tool methods) or full app definition
          ruby_content = File.read(ruby_files.first)
          if ruby_content.include?("< MonadicApp") && ruby_content.include?("@settings")
            # This might be a duplicate definition
            mdsl_content = File.read(mdsl_files.first)
            mdsl_app_name_match = mdsl_content.match(/app\s+"([^"]+)"\s+do/)
            display_name_match = ruby_content.match(/display_name:\s*["']([^"']+)["']/)
            
            if mdsl_app_name_match && display_name_match && 
               mdsl_app_name_match[1] == display_name_match[1]
              # Same app defined in both files - check if they're for same provider
              mdsl_provider_match = mdsl_content.match(/provider\s+"([^"]+)"/)
              ruby_group_match = ruby_content.match(/group:\s*["']([^"']+)["']/)
              
              if mdsl_provider_match && ruby_group_match
                mdsl_group = case mdsl_provider_match[1]
                            when "openai" then "OpenAI"
                            when "anthropic" then "Anthropic"
                            else mdsl_provider_match[1].capitalize
                            end
                
                if mdsl_group == ruby_group_match[1]
                  issues << "Potential duplicate: #{mdsl_files.first} and #{ruby_files.first} define same app for same provider"
                end
              end
            end
          end
        end
      end
      
      expect(issues).to be_empty, "App coexistence issues found:\n#{issues.join("\n")}"
    end

    it "validates consistent property naming in MDSL files" do
      issues = []
      deprecated_properties = ['jupyter_access']  # Properties that should not be used
      
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      mdsl_files.each do |file|
        content = File.read(file)
        
        # Check for deprecated properties
        deprecated_properties.each do |prop|
          if content.match(/#{prop}\s*(true|false|:)/)
            issues << "#{file}: Uses deprecated property '#{prop}' (use 'jupyter' instead)"
          end
        end
        
        # Check that jupyter property is used correctly when needed
        if content.include?("run_jupyter") || content.include?("create_jupyter_notebook")
          unless content.match(/jupyter\s+(true|false)/)
            issues << "#{file}: Has Jupyter tools but missing 'jupyter' property in features block"
          end
        end
      end
      
      expect(issues).to be_empty, "MDSL property consistency issues:\n#{issues.join("\n")}"
    end
  end

  describe "Tool Auto-Completion Validation" do
    it "validates Ruby implementations are either explicitly defined or auto-completed" do
      app_dirs = Dir.glob(File.join(app_base_dir, "*/"))
      standard_tools = discover_standard_tools
      
      app_dirs.each do |app_dir|
        mdsl_files = Dir.glob(File.join(app_dir, "*.mdsl"))
        ruby_files = Dir.glob(File.join(app_dir, "*_tools.rb"))
        
        next if mdsl_files.empty? || ruby_files.empty?
        
        # Extract tool methods from each Ruby file
        ruby_files.each do |ruby_file|
          discoverable_tools = extract_tool_methods_from_ruby(ruby_file, standard_tools)
          
          # Check definition status in corresponding MDSL files
          mdsl_files.each do |mdsl_file|
            explicit_tools = extract_tools_from_mdsl(mdsl_file)
            auto_completion_enabled = has_auto_completion_comment(mdsl_file)
            
            # If auto-completion is enabled, tools don't need explicit definitions
            if auto_completion_enabled
              next # Skip validation for auto-completed tools
            end
            
            missing_definitions = discoverable_tools - explicit_tools
            
            # Report undefined tools only when auto-completion is NOT enabled
            missing_definitions.each do |tool_name|
              test_errors << "Tool '#{tool_name}' implemented in #{ruby_file} but not defined in #{mdsl_file} (auto-completion not enabled)"
            end
          end
        end
      end
      
      expect(test_errors).to be_empty, "Missing MDSL tool definitions:\n#{test_errors.join("\n")}"
    end

    it "validates auto-completion system functionality" do
      test_errors = []
      auto_completion_apps = []
      
      app_dirs = Dir.glob(File.join(app_base_dir, "*/"))
      app_dirs.each do |app_dir|
        mdsl_files = Dir.glob(File.join(app_dir, "*.mdsl"))
        ruby_files = Dir.glob(File.join(app_dir, "*_tools.rb"))
        
        next if mdsl_files.empty? || ruby_files.empty?
        
        mdsl_files.each do |mdsl_file|
          if has_auto_completion_comment(mdsl_file)
            app_name = File.basename(app_dir)
            auto_completion_apps << app_name
          end
        end
      end
      
      # Test that auto-completion apps have proper structure
      auto_completion_apps.uniq.each do |app_name|
        tools_file = File.join(app_base_dir, app_name, "#{app_name}_tools.rb")
        unless File.exist?(tools_file)
          test_errors << "Auto-completion app '#{app_name}' should have #{app_name}_tools.rb file"
        end
      end
      
      expect(test_errors).to be_empty, "Auto-completion validation errors:\n#{test_errors.join("\n")}"
    end

    it "validates system prompts reference implemented tool methods" do
      app_dirs = Dir.glob(File.join(app_base_dir, "*/"))
      standard_tools = discover_standard_tools
      
      # Apps that use auto-discovery and don't need explicit tool mentions
      auto_discovery_apps = %w[
        code_interpreter jupyter_notebook chat_plus language_practice_plus
        research_assistant speech_draft_helper second_opinion pdf_navigator
        video_describer drawio_grapher mermaid_grapher novel_writer
        math_tutor image_generator video_generator monadic_help
      ]
      
      app_dirs.each do |app_dir|
        app_name = File.basename(app_dir)
        
        # Skip apps that use auto-discovery
        next if auto_discovery_apps.include?(app_name)
        
        mdsl_files = Dir.glob(File.join(app_dir, "*.mdsl"))
        ruby_files = Dir.glob(File.join(app_dir, "*_tools.rb"))
        
        next if mdsl_files.empty? || ruby_files.empty?
        
        # Extract tool methods from Ruby files
        ruby_files.each do |ruby_file|
          discoverable_tools = extract_tool_methods_from_ruby(ruby_file, standard_tools)
          
          # Skip if no custom tools (only standard tools)
          next if discoverable_tools.empty?
          
          # Check if tools are mentioned in system prompts
          mdsl_files.each do |mdsl_file|
            content = File.read(mdsl_file)
            system_prompt_match = content.match(/system_prompt\s+<<~TEXT(.*?)TEXT/m)
            
            if system_prompt_match
              system_prompt = system_prompt_match[1]
              
              # Only check for non-standard tools that are specific to this app
              app_specific_tools = discoverable_tools - standard_tools
              
              app_specific_tools.each do |tool_name|
                unless system_prompt.include?(tool_name) || system_prompt.include?("`#{tool_name}`")
                  test_errors << "Tool '#{tool_name}' in #{ruby_file} not referenced in system prompt of #{mdsl_file}"
                end
              end
            end
          end
        end
      end
      
      expect(test_errors).to be_empty, "Tools not referenced in system prompts:\n#{test_errors.join("\n")}"
    end

    it "validates auto-completion consistency across provider variations" do
      app_dirs = Dir.glob(File.join(app_base_dir, "*/"))
      
      # Provider-specific tools that are OK to differ
      provider_specific_tools = %w[websearch_agent tavily_search generate_video_with_veo]
      
      app_dirs.each do |app_dir|
        mdsl_files = Dir.glob(File.join(app_dir, "*.mdsl"))
        ruby_files = Dir.glob(File.join(app_dir, "*_tools.rb"))
        
        next if mdsl_files.length <= 1 || ruby_files.empty?
        
        # Extract core tools from Ruby implementation
        ruby_tools = Set.new
        ruby_files.each do |ruby_file|
          ruby_tools.merge(extract_tool_methods_from_ruby(ruby_file, []))
        end
        
        # Remove provider-specific tools from core set
        core_tools = ruby_tools - provider_specific_tools
        
        # For multi-provider apps, ensure core tool consistency
        mdsl_files.each do |mdsl_file|
          current_tools = extract_tools_from_mdsl(mdsl_file)
          
          # Check that all core tools are present (ignoring provider-specific ones)
          missing_core_tools = core_tools - current_tools - provider_specific_tools
          
          missing_core_tools.each do |tool_name|
            test_errors << "Core tool '#{tool_name}' missing in #{mdsl_file}"
          end
        end
      end
      
      expect(test_errors).to be_empty, "Tool definition inconsistencies:\n#{test_errors.join("\n")}"
    end
  end


  private

  def discover_standard_tools
    # Static list of known standard tools
    known_standard = %w[
      fetch_text_from_office fetch_text_from_pdf fetch_text_from_file
      analyze_image analyze_audio analyze_video
      run_code run_script run_bash_command lib_installer check_environment
      fetch_web_content search_wikipedia tavily_search websearch_agent
      write_to_file run_jupyter create_jupyter_notebook add_jupyter_cells system_info
      delete_jupyter_cell update_jupyter_cell get_jupyter_cells_with_results execute_and_fix_jupyter_cells
      list_jupyter_notebooks restart_jupyter_kernel interrupt_jupyter_execution 
      move_jupyter_cell insert_jupyter_cells
      list_providers_and_voices generate_video_with_veo
    ]
    
    # Dynamically discover additional standard tools from MonadicApp if available
    begin
      # Try to load MonadicApp to get real method list
      require_relative '../../lib/monadic/app'
      if defined?(MonadicApp)
        instance_methods = MonadicApp.instance_methods(false)
        standard_tool_pattern = /^(fetch_|analyze_|run_|lib_|check_|search_|write_|create_|add_|system_)/
        dynamic_standard = instance_methods.select { |m| m.to_s.match?(standard_tool_pattern) }.map(&:to_s)
        known_standard = (known_standard + dynamic_standard).uniq
      end
    rescue LoadError, NameError
      # Fallback to static list if dynamic discovery fails
      puts "Note: Using static standard tools list (MonadicApp not available)"
    end
    
    known_standard
  end

  def extract_tool_methods_from_ruby(ruby_file, standard_tools)
    content = File.read(ruby_file)
    
    # Find the private keyword position to separate public from private methods
    private_keyword_pos = content.index(/^\s*private\s*$/)
    
    # If there's a private section, only consider methods before it
    if private_keyword_pos
      public_content = content[0...private_keyword_pos]
    else
      public_content = content
    end
    
    # Extract method definitions that could be tools from public section only
    methods = public_content.scan(/def\s+(\w+)/).flatten
    
    # Filter out obvious non-tool methods
    excluded_patterns = /^(initialize|private|protected|validate|format|parse|setup|teardown|before|after|test_|spec_|help_embeddings_db)/
    potential_tools = methods.reject { |method| 
      method.match?(excluded_patterns) || standard_tools.include?(method)
    }
    
    potential_tools
  end

  def extract_tools_from_mdsl(mdsl_file)
    content = File.read(mdsl_file)
    content.scan(/define_tool\s+"([^"]+)"/).flatten
  end

  def has_auto_completion_comment(mdsl_file)
    content = File.read(mdsl_file)
    # Check for auto-completion comments that indicate reliance on auto-completion system
    auto_completion_patterns = [
      /Tool definitions will be auto-completed/,
      /auto-completed from.*tools\.rb/,
      /Standard tools will be auto-completed from MonadicApp base class/
    ]
    
    auto_completion_patterns.any? { |pattern| content.match?(pattern) }
  end
end