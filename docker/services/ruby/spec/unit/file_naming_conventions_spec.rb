# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe "File Naming Conventions" do
  let(:app_base_dir) { 
    if Dir.pwd.end_with?('docker/services/ruby')
      File.join(Dir.pwd, "apps")
    else
      File.join(Dir.pwd, "docker", "services", "ruby", "apps")
    end
  }

  describe "Ruby Support File Naming" do
    it "follows *_tools.rb convention for tool implementation files" do
      tool_files = Dir.glob(File.join(app_base_dir, "**/*_tools.rb"))
      
      tool_files.each do |file|
        content = File.read(file)
        # Tool files should contain method definitions
        expect(content).to match(/def\s+\w+/), 
          "Tool file #{file} should contain method definitions"
        
        # Tool files should not contain constants like ICON, DESCRIPTION
        expect(content).not_to match(/^\s*(ICON|DESCRIPTION|INITIAL_PROMPT)\s*=/),
          "Tool file #{file} should not contain app constants"
      end
    end

    it "follows *_constants.rb convention for constant definition files" do
      constant_files = Dir.glob(File.join(app_base_dir, "**/*_constants.rb"))
      
      constant_files.each do |file|
        content = File.read(file)
        # Constants files should contain module with constants
        expect(content).to match(/module\s+\w+/),
          "Constants file #{file} should define a module"
        
        # Should contain at least one constant definition
        expect(content).to match(/(ICON|DESCRIPTION|INITIAL_PROMPT)\s*=/),
          "Constants file #{file} should define constants"
      end
    end

    it "ensures no legacy *_app.rb files exist" do
      legacy_files = Dir.glob(File.join(app_base_dir, "**/*_app.rb"))
      backup_files = Dir.glob(File.join(app_base_dir, "**/*.backup"))
      
      expect(legacy_files).to be_empty,
        "Found legacy app files: #{legacy_files.join(', ')}"
      
      expect(backup_files).to be_empty,
        "Found backup files that should be removed: #{backup_files.join(', ')}"
    end
  end

  describe "MDSL File Organization" do
    it "validates MDSL files have correct provider suffixes" do
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |file|
        basename = File.basename(file, ".mdsl")
        
        # Check for valid provider suffixes (case-insensitive at end of name)
        valid_suffixes = %w[openai claude gemini mistral cohere perplexity grok deepseek ollama]
        has_valid_suffix = valid_suffixes.any? { |suffix| basename.downcase.end_with?(suffix) }
        
        # Some apps may not follow this pattern (e.g., wikipedia.mdsl, mermaid_grapher.mdsl)
        exceptions = %w[wikipedia mermaid_grapher video_describer_app]
        is_exception = exceptions.any? { |ex| basename.include?(ex) }
        
        unless has_valid_suffix || is_exception
          fail "MDSL file #{file} should have a valid provider suffix or be a known exception"
        end
      end
    end
  end

  describe "MDSL Naming Conventions" do
    let(:provider_mapping) do
      {
        "openai" => { suffix: "OpenAI", group: "OpenAI" },
        "anthropic" => { suffix: "Claude", group: "Anthropic" },
        "google" => { suffix: "Gemini", group: "Google" },
        "mistral" => { suffix: "Mistral", group: "Mistral" },
        "cohere" => { suffix: "Cohere", group: "Cohere" },
        "perplexity" => { suffix: "Perplexity", group: "Perplexity" },
        "xai" => { suffix: "Grok", group: "xAI" },
        "deepseek" => { suffix: "DeepSeek", group: "DeepSeek" },
        "ollama" => { suffix: "Ollama", group: "Ollama" }
      }
    end

    it "validates app identifier follows NameProviderSuffix pattern" do
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |file|
        content = File.read(file)
        
        # Extract app identifier
        app_match = content.match(/^app\s+"([^"]+)"/)
        next unless app_match
        
        app_identifier = app_match[1]
        basename = File.basename(file, ".mdsl")
        
        # Skip exceptions (including apps with spaces in identifier)
        exceptions = %w[Wikipedia MermaidGrapher VideoDescriber]
        is_exception = exceptions.any? { |ex| app_identifier.include?(ex) } || app_identifier.include?(" ")
        next if is_exception
        
        # Check if app identifier ends with a valid provider suffix
        valid_suffixes = provider_mapping.values.map { |v| v[:suffix] }
        # Add special case for MistralAI
        valid_suffixes << "MistralAI"
        has_valid_suffix = valid_suffixes.any? { |suffix| app_identifier.end_with?(suffix) }
        
        expect(has_valid_suffix).to be(true),
          "App identifier '#{app_identifier}' in #{file} should end with a valid provider suffix (#{valid_suffixes.join(', ')})"
      end
    end

    it "validates display_name does NOT include provider information" do
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |file|
        content = File.read(file)
        
        # Extract display_name
        display_match = content.match(/display_name\s+"([^"]+)"/)
        next unless display_match
        
        display_name = display_match[1]
        
        # Check that display_name doesn't contain provider names
        provider_names = %w[OpenAI Anthropic Claude Google Gemini Mistral Cohere Perplexity xAI Grok DeepSeek Ollama]
        
        provider_names.each do |provider|
          expect(display_name).not_to include("(#{provider})"),
            "display_name '#{display_name}' in #{file} should not include provider information like '(#{provider})'"
          
          # Also check for provider names at the end
          expect(display_name).not_to match(/\s+#{provider}$/),
            "display_name '#{display_name}' in #{file} should not end with provider name '#{provider}'"
        end
      end
    end

    it "validates group matches provider correctly" do
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |file|
        content = File.read(file)
        
        # Extract app identifier and group
        app_match = content.match(/^app\s+"([^"]+)"/)
        group_match = content.match(/group\s+"([^"]+)"/)
        
        next unless app_match && group_match
        
        app_identifier = app_match[1]
        group = group_match[1]
        
        # Skip exceptions
        exceptions = %w[Wikipedia MermaidGrapher VideoDescriber]
        is_exception = exceptions.any? { |ex| app_identifier.include?(ex) }
        next if is_exception
        
        # Determine expected group based on app identifier suffix
        expected_group = nil
        provider_mapping.each do |_provider, mapping|
          if app_identifier.end_with?(mapping[:suffix])
            expected_group = mapping[:group]
            break
          end
        end
        
        if expected_group
          expect(group).to eq(expected_group),
            "App '#{app_identifier}' in #{file} should have group '#{expected_group}' but has '#{group}'"
        end
      end
    end

    it "ensures no duplicate display_names within same provider group" do
      # Group MDSL files by their provider group
      apps_by_group = Hash.new { |h, k| h[k] = [] }
      
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |file|
        content = File.read(file)
        
        display_match = content.match(/display_name\s+"([^"]+)"/)
        group_match = content.match(/group\s+"([^"]+)"/)
        
        if display_match && group_match
          display_name = display_match[1]
          group = group_match[1]
          
          apps_by_group[group] << { file: file, display_name: display_name }
        end
      end
      
      # Check for duplicates within each group
      apps_by_group.each do |group, apps|
        display_names = apps.map { |app| app[:display_name] }
        duplicates = display_names.select { |name| display_names.count(name) > 1 }.uniq
        
        expect(duplicates).to be_empty,
          "Found duplicate display_names in group '#{group}': #{duplicates.join(', ')}"
      end
    end

    it "validates file name matches app identifier pattern" do
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |file|
        content = File.read(file)
        basename = File.basename(file, ".mdsl")
        
        # Extract app identifier
        app_match = content.match(/^app\s+"([^"]+)"/)
        next unless app_match
        
        app_identifier = app_match[1]
        
        # Skip special cases with spaces or special naming
        special_cases = ["Mermaid Grapher", "Wikipedia", "VideoDescriber"]
        next if special_cases.include?(app_identifier)
        
        # Convert CamelCase app identifier to snake_case for comparison
        expected_basename = app_identifier.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                                        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                                        .downcase
        
        # Allow for some flexibility in naming (e.g., VideoDescriber vs video_describer_app)
        unless basename == expected_basename || basename.start_with?(expected_basename.split('_')[0])
          fail "File name '#{basename}.mdsl' doesn't match app identifier '#{app_identifier}'"
        end
      end
    end

    it "ensures app identifiers are unique across all MDSL files" do
      app_identifiers = {}
      
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |file|
        content = File.read(file)
        
        # Extract app identifier
        app_match = content.match(/^app\s+"([^"]+)"/)
        next unless app_match
        
        app_identifier = app_match[1]
        
        if app_identifiers[app_identifier]
          fail "Duplicate app identifier '#{app_identifier}' found in:\n  - #{app_identifiers[app_identifier]}\n  - #{file}"
        else
          app_identifiers[app_identifier] = file
        end
      end
    end

    it "validates provider in llm block matches app identifier suffix" do
      mdsl_files = Dir.glob(File.join(app_base_dir, "**/*.mdsl"))
      
      mdsl_files.each do |file|
        content = File.read(file)
        
        # Extract app identifier
        app_match = content.match(/^app\s+"([^"]+)"/)
        next unless app_match
        
        app_identifier = app_match[1]
        
        # Extract provider from llm block
        provider_match = content.match(/provider\s+"([^"]+)"/)
        next unless provider_match
        
        provider = provider_match[1]
        
        # Skip exceptions (including apps with spaces in identifier)
        exceptions = %w[Wikipedia MermaidGrapher VideoDescriber]
        is_exception = exceptions.any? { |ex| app_identifier.include?(ex) } || app_identifier.include?(" ")
        next if is_exception
        
        # Validate provider matches app suffix
        expected_suffix = provider_mapping[provider]&.fetch(:suffix, nil)
        
        if expected_suffix
          # Handle special case where ChatMistralAI uses MistralAI suffix
          valid_suffixes = [expected_suffix]
          if provider == "mistral"
            valid_suffixes << "MistralAI"
          end
          
          has_valid_suffix = valid_suffixes.any? { |suffix| app_identifier.end_with?(suffix) }
          expect(has_valid_suffix).to be(true),
            "App '#{app_identifier}' with provider '#{provider}' should end with one of: #{valid_suffixes.join(', ')}"
        end
      end
    end
  end

  describe "Support File Patterns" do
    it "validates Pattern A: Shared constants with multiple MDSL files" do
      # Check apps like coding_assistant
      pattern_a_apps = Dir.glob(File.join(app_base_dir, "*")).select do |dir|
        File.directory?(dir) &&
        Dir.glob(File.join(dir, "*_constants.rb")).any? &&
        Dir.glob(File.join(dir, "*.mdsl")).size > 1
      end
      
      pattern_a_apps.each do |app_dir|
        constants_files = Dir.glob(File.join(app_dir, "*_constants.rb"))
        mdsl_files = Dir.glob(File.join(app_dir, "*.mdsl"))
        
        expect(constants_files.size).to eq(1),
          "Pattern A app #{app_dir} should have exactly one constants file"
        
        expect(mdsl_files.size).to be > 1,
          "Pattern A app #{app_dir} should have multiple MDSL files"
      end
    end

    it "validates Pattern B: MDSL-only apps" do
      # Check apps with only MDSL files
      pattern_b_apps = Dir.glob(File.join(app_base_dir, "*")).select do |dir|
        File.directory?(dir) &&
        Dir.glob(File.join(dir, "*.mdsl")).size == 1 &&
        Dir.glob(File.join(dir, "*.rb")).empty?
      end
      
      pattern_b_apps.each do |app_dir|
        mdsl_files = Dir.glob(File.join(app_dir, "*.mdsl"))
        ruby_files = Dir.glob(File.join(app_dir, "*.rb"))
        
        expect(mdsl_files.size).to eq(1),
          "Pattern B app #{app_dir} should have exactly one MDSL file"
        
        expect(ruby_files).to be_empty,
          "Pattern B app #{app_dir} should have no Ruby files"
      end
    end

    it "validates Pattern C/D: Tool implementation files" do
      # Check apps with tool implementations
      tool_apps = Dir.glob(File.join(app_base_dir, "*")).select do |dir|
        File.directory?(dir) &&
        Dir.glob(File.join(dir, "*_tools.rb")).any?
      end
      
      tool_apps.each do |app_dir|
        tool_files = Dir.glob(File.join(app_dir, "*_tools.rb"))
        mdsl_files = Dir.glob(File.join(app_dir, "*.mdsl"))
        
        expect(tool_files.size).to eq(1),
          "Tool-based app #{app_dir} should have exactly one tools file"
        
        expect(mdsl_files).not_to be_empty,
          "Tool-based app #{app_dir} should have at least one MDSL file"
      end
    end
  end

  describe "Cleanup Validation" do
    it "ensures no commented legacy code exists" do
      all_ruby_files = Dir.glob(File.join(app_base_dir, "**/*.rb"))
      
      files_with_legacy_comments = []
      
      all_ruby_files.each do |file|
        content = File.read(file)
        
        # Check for commented class definitions
        if content.match?(/^\s*#\s*class\s+\w+\s*<\s*MonadicApp/)
          files_with_legacy_comments << file
        end
      end
      
      expect(files_with_legacy_comments).to be_empty,
        "Found commented legacy code in: #{files_with_legacy_comments.join(', ')}"
    end

    it "ensures debug output uses environment variables" do
      tool_files = Dir.glob(File.join(app_base_dir, "**/*_tools.rb"))
      
      files_with_unconditional_debug = []
      
      tool_files.each do |file|
        content = File.read(file)
        lines = content.split("\n")
        
        in_conditional_block = false
        
        lines.each_with_index do |line, index|
          # Track if we're inside an if ENV block
          if line.match?(/if\s+ENV\[/)
            in_conditional_block = true
          elsif line.match?(/^\s*end\s*$/) && in_conditional_block
            in_conditional_block = false
          end
          
          # Check for debug puts without ENV condition
          if line.match?(/puts\s+["']\[DEBUG\]/) && !line.match?(/if\s+ENV\[/) && !in_conditional_block
            files_with_unconditional_debug << "#{file}:#{index + 1}"
          end
        end
      end
      
      expect(files_with_unconditional_debug).to be_empty,
        "Found unconditional debug output in: #{files_with_unconditional_debug.join(', ')}"
    end
  end
end