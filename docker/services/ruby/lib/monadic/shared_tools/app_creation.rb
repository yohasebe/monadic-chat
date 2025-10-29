# frozen_string_literal: true

require 'json'

# Shared App Creation/Management Tools for Monadic Chat
# Provides basic Monadic Chat application management capabilities
#
# This module provides:
# - List available Monadic apps
# - Get app configuration and metadata
# - Create simple app templates
#
# Usage in MDSL:
#   tools do
#     import_shared_tools :app_creation, visibility: "conditional"
#   end
#
# Available tools:
#   - list_monadic_apps: List all available Monadic Chat applications
#   - get_app_info: Get detailed information about a specific app
#   - create_simple_app_template: Create a basic app template file

module MonadicSharedTools
  module AppCreation
    include MonadicHelper

    # List all available Monadic Chat applications
    #
    # Scans the apps/ directory and returns a list of all applications
    # with their provider variants and basic metadata.
    #
    # @return [Hash] Success status and list of apps with metadata
    #
    # @example List all apps
    #   list_monadic_apps()
    #   # => {success: true, apps: [{name: "ChatPlus", variants: ["openai", "claude", ...], ...}, ...]}
    def list_monadic_apps
      begin
        # Determine apps directory based on environment
        apps_dir = if defined?(Monadic::Utils::Environment) && Monadic::Utils::Environment.in_container?
                     '/monadic/apps'
                   else
                     File.expand_path('../../apps', __dir__)
                   end

        unless Dir.exist?(apps_dir)
          return {
            success: false,
            error: "Apps directory not found: #{apps_dir}"
          }
        end

        # Scan directories
        app_families = []
        Dir.glob(File.join(apps_dir, '*')).sort.each do |app_path|
          next unless File.directory?(app_path)

          app_name = File.basename(app_path)

          # Find MDSL files for this app
          mdsl_files = Dir.glob(File.join(app_path, '*.mdsl'))
          variants = mdsl_files.map do |mdsl_file|
            # Extract variant name from filename (e.g., "chat_plus_openai.mdsl" -> "openai")
            basename = File.basename(mdsl_file, '.mdsl')
            basename.split('_').last
          end.sort

          # Read first MDSL file to get description
          description = nil
          display_name = nil
          icon = nil

          if mdsl_files.first
            content = File.read(mdsl_files.first)

            # Extract display_name
            if content =~ /display_name\s+"([^"]+)"/
              display_name = $1
            end

            # Extract icon
            if content =~ /icon\s+"([^"]+)"/
              icon = $1
            end

            # Extract English description
            if content =~ /description\s+do.*?en\s+<<~TEXT\s+(.*?)\s+TEXT/m
              description = $1.strip
            end
          end

          app_families << {
            name: app_name,
            display_name: display_name || app_name.split('_').map(&:capitalize).join(' '),
            icon: icon,
            description: description,
            variants: variants,
            variant_count: variants.size,
            path: app_path
          }
        end

        {
          success: true,
          app_count: app_families.size,
          total_variants: app_families.sum { |app| app[:variant_count] },
          apps: app_families
        }

      rescue StandardError => e
        {
          success: false,
          error: "Failed to list apps: #{e.message}"
        }
      end
    end

    # Get detailed information about a specific Monadic app
    #
    # Returns complete configuration, tools, and metadata for the specified
    # application and provider variant.
    #
    # @param app_name [String] Name of the app (e.g., "chat_plus", "code_interpreter")
    # @param variant [String] Provider variant (e.g., "openai", "claude"). Optional.
    # @return [Hash] Success status and app information
    #
    # @example Get Chat Plus OpenAI info
    #   get_app_info(app_name: "chat_plus", variant: "openai")
    #   # => {success: true, app: {...}, mdsl_content: "...", tools: [...]}
    #
    # @example Get first variant of Code Interpreter
    #   get_app_info(app_name: "code_interpreter")
    def get_app_info(app_name:, variant: nil)
      begin
        # Determine apps directory
        apps_dir = if defined?(Monadic::Utils::Environment) && Monadic::Utils::Environment.in_container?
                     '/monadic/apps'
                   else
                     File.expand_path('../../apps', __dir__)
                   end

        app_path = File.join(apps_dir, app_name)

        unless Dir.exist?(app_path)
          return {
            success: false,
            error: "App not found: #{app_name}"
          }
        end

        # Find MDSL files
        mdsl_files = Dir.glob(File.join(app_path, '*.mdsl')).sort

        if mdsl_files.empty?
          return {
            success: false,
            error: "No MDSL files found for app: #{app_name}"
          }
        end

        # Select specific variant or first available
        mdsl_file = if variant
                      mdsl_files.find { |f| f.include?("_#{variant}.mdsl") }
                    else
                      mdsl_files.first
                    end

        unless mdsl_file
          return {
            success: false,
            error: "Variant '#{variant}' not found for app: #{app_name}"
          }
        end

        # Read MDSL content
        mdsl_content = File.read(mdsl_file)

        # Extract app name from MDSL
        app_class_name = nil
        if mdsl_content =~ /app\s+"([^"]+)"\s+do/
          app_class_name = $1
        end

        # Extract provider and model
        provider = nil
        model = nil
        if mdsl_content =~ /provider\s+"([^"]+)"/
          provider = $1
        end
        if mdsl_content =~ /model\s+(?:\[([^\]]+)\]|"([^"]+)")/
          model = $1 || $2
        end

        # Extract tools
        tools = []
        mdsl_content.scan(/define_tool\s+"([^"]+)",\s+"([^"]+)"/) do |tool_name, tool_desc|
          tools << { name: tool_name, description: tool_desc }
        end

        # Extract shared tool imports
        shared_tools = []
        mdsl_content.scan(/import_shared_tools\s+:(\w+)/) do |group_name|
          shared_tools << group_name[0]
        end

        # Extract features
        features = {}
        if mdsl_content =~ /features\s+do(.*?)end/m
          features_block = $1
          features_block.scan(/(\w+)\s+(true|false)/) do |feature_name, feature_value|
            features[feature_name.to_sym] = feature_value == 'true'
          end
        end

        {
          success: true,
          app: {
            name: app_name,
            class_name: app_class_name,
            provider: provider,
            model: model,
            mdsl_file: File.basename(mdsl_file),
            path: app_path
          },
          tools: {
            defined: tools,
            shared_imports: shared_tools,
            total_count: tools.size + shared_tools.size * 3 # Estimate 3 tools per shared group
          },
          features: features,
          mdsl_content: mdsl_content
        }

      rescue StandardError => e
        {
          success: false,
          error: "Failed to get app info: #{e.message}"
        }
      end
    end

    # Create a simple Monadic app template
    #
    # Generates a basic MDSL template file for creating a new Monadic Chat
    # application. This is a starting point that needs to be customized.
    #
    # @param app_name [String] Name for the new app (snake_case)
    # @param display_name [String] Display name (e.g., "My App")
    # @param provider [String] AI provider (e.g., "openai", "claude")
    # @param description [String] App description
    # @return [Hash] Success status and filepath
    #
    # @example Create new app template
    #   create_simple_app_template(
    #     app_name: "my_assistant",
    #     display_name: "My Assistant",
    #     provider: "openai",
    #     description: "A helpful AI assistant"
    #   )
    def create_simple_app_template(app_name:, display_name:, provider: "openai", description: "")
      begin
        # Validate app_name format
        unless app_name =~ /^[a-z][a-z0-9_]*$/
          return {
            success: false,
            error: "Invalid app_name format. Use lowercase letters, numbers, and underscores only (e.g., 'my_app')"
          }
        end

        # Determine data directory
        data_dir = if defined?(Monadic::Utils::Environment) && Monadic::Utils::Environment.in_container?
                     SHARED_VOL
                   else
                     LOCAL_SHARED_VOL
                   end

        # Create template content
        template = <<~MDSL
        app "#{app_name.split('_').map(&:capitalize).join}#{provider.capitalize}" do
          display_name "#{display_name}"

          description do
            en <<~TEXT
            #{description}
            TEXT
          end

          icon "fa-solid fa-robot"

          llm do
            provider "#{provider}"
            model "gpt-4.1"  # Update with appropriate model
            temperature 0.7
            max_tokens 4000
          end

          system_prompt <<~TEXT
          You are a helpful AI assistant.

          [Customize this system prompt for your specific use case]
          TEXT

          features do
            easy_submit false
            auto_speech false
            image false
            pdf false
          end

          tools do
            # Import shared tool groups
            import_shared_tools :file_operations, visibility: "always"

            # Define custom tools here
            # define_tool "custom_tool", "Description" do
            #   parameter :param1, "string", "Parameter description", required: true
            # end
          end
        end
        MDSL

        # Save template
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        filename = "#{app_name}_#{provider}_template_#{timestamp}.mdsl"
        filepath = File.join(data_dir, filename)

        File.write(filepath, template, encoding: 'UTF-8')

        {
          success: true,
          filepath: filename,
          full_path: filepath,
          message: "App template created successfully. Customize the MDSL file and place it in apps/#{app_name}/ directory to activate."
        }

      rescue StandardError => e
        {
          success: false,
          error: "Failed to create app template: #{e.message}"
        }
      end
    end
  end
end
