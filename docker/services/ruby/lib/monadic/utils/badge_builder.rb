# frozen_string_literal: true

module Monadic
  module Utils
    # BadgeBuilder: Unified utility for building app capability badges
    #
    # Transforms raw MDSL settings into structured badge metadata for frontend display.
    # Supports 2-category architecture:
    #   - Tools: Callable functions (tool groups, agent tools)
    #   - Capabilities: App properties (features, backend models)
    #
    # @example
    #   settings = {
    #     imported_tool_groups: [...],
    #     features: { monadic: true, pdf_vector_storage: true },
    #     agents: { code_generator: "gpt-5-codex" }
    #   }
    #   badges = BadgeBuilder.build_all_badges(settings)
    #   # => { tools: [...], capabilities: [...] }
    class BadgeBuilder
      # Map agent tool names to generic badge labels
      AGENT_BADGE_LABELS = {
        'openai_code_agent' => 'code agent',
        'grok_code_agent' => 'code agent',
        'claude_code_agent' => 'code agent'
      }.freeze

      # Main entry point for badge generation
      #
      # @param app_settings [Hash] MDSL settings hash
      # @return [Hash] Badge structure with :tools and :capabilities arrays
      def self.build_all_badges(app_settings)
        # Defensive: ensure app_settings is a Hash
        settings = app_settings.is_a?(Hash) ? app_settings : {}

        {
          tools: build_tool_badges(settings),
          capabilities: build_capability_badges(settings)
        }
      rescue StandardError => e
        STDERR.puts "[BadgeBuilder] Error building badges: #{e.message}"
        STDERR.puts e.backtrace.first(3)
        { tools: [], capabilities: [] }
      end

      # Build tool badges from tool groups and individual tools
      #
      # Handles three different tool data formats:
      #   - OpenAI/Claude: { tools: [...] }
      #   - Gemini: [...]
      #   - Uninitialized: nil or {}
      #
      # @param settings [Hash] App settings
      # @return [Array<Hash>] Array of tool badge hashes
      def self.build_tool_badges(settings)
        badges = []

        # 1. From imported_tool_groups
        if settings[:imported_tool_groups]
          settings[:imported_tool_groups].each do |group|
            badges << {
              type: :tools,
              subtype: :group,
              id: group[:name].to_s,
              icon: get_tool_group_icon(group[:name]),
              label: format_label(group[:name]),
              visibility: group[:visibility] || "always",
              tool_count: group[:tool_count] || 0,
              description: "#{group[:tool_count] || 0} tools (#{group[:visibility] || 'always'})",
              order: 1
            }
          end
        end

        # 2. From defined tools - DEFENSIVE HANDLING for multiple formats
        tools_data = settings[:tools]

        # Debug logging for Auto Forge apps
        if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
          app_name = settings[:app_name] || settings["app_name"] || "Unknown"
          if app_name.to_s.include?("AutoForge")
            STDERR.puts "[BadgeBuilder] ===== #{app_name} Tool Badge Building ====="
            STDERR.puts "[BadgeBuilder] tools_data class: #{tools_data.class}"
            STDERR.puts "[BadgeBuilder] tools_data keys: #{tools_data.keys if tools_data.respond_to?(:keys)}"
            if tools_data.is_a?(Hash)
              STDERR.puts "[BadgeBuilder] tools_data[:tools]: #{tools_data[:tools].inspect[0..500]}"
            elsif tools_data.is_a?(Array)
              STDERR.puts "[BadgeBuilder] tools_data (Array): #{tools_data.map { |t| t[:name] || t['name'] }.inspect}"
            end
          end
        end

        tools = case tools_data
                when Hash
                  # OpenAI/Claude format: { tools: [...] }
                  tools_data[:tools] || tools_data["tools"] || []
                when Array
                  # Gemini format: [...]
                  tools_data
                when nil
                  # Uninitialized
                  []
                else
                  # Unknown format - log warning and skip
                  STDERR.puts "[BadgeBuilder] Unexpected tools format: #{tools_data.class}"
                  []
                end

        # Extract agent tools
        agent_patterns = [
          /openai_code_agent/,
          /grok_code_agent/,
          /claude_code_agent/
        ]

        tools.each do |tool|
          # Additional safety: ensure tool is a Hash
          next unless tool.is_a?(Hash)

          # Extract tool name - handle both flat (Gemini) and nested (OpenAI/Claude) formats
          tool_name = if tool[:function] || tool["function"]
                        # OpenAI/Claude format: { type: "function", function: { name: "tool_name", ... } }
                        func = tool[:function] || tool["function"]
                        func[:name] || func["name"]
                      else
                        # Gemini format: { name: "tool_name", ... }
                        tool[:name] || tool["name"]
                      end
          next unless tool_name

          if agent_patterns.any? { |pattern| tool_name.to_s =~ pattern }
            # Use generic label from mapping, or fall back to transformed tool name
            agent_label = AGENT_BADGE_LABELS[tool_name.to_s] || tool_name.to_s.gsub("_agent", "").tr("_", "-")
            badges << {
              type: :tools,
              subtype: :agent,
              id: tool_name.to_s,
              icon: "fa-robot",
              label: agent_label,
              visibility: tool[:visibility] || tool["visibility"] || "conditional",
              description: tool[:description] || tool["description"] || "AI agent",
              order: 2
            }
          end
        end

        badges
      end

      # Build capability badges from features and agents config
      #
      # CRITICAL: Reads from settings[:agents] not settings[:llm_agents]
      #
      # @param settings [Hash] App settings
      # @return [Array<Hash>] Array of capability badge hashes
      def self.build_capability_badges(settings)
        badges = []
        features = settings[:features] || {}

        # Normalize feature names (handle MDSL naming variations)
        normalized_features = normalize_feature_names(features)

        # Special handling for image_generation (upload_only vs full generation)
        if normalized_features[:image_generation]
          if normalized_features[:image_generation] == "upload_only"
            badges << {
              type: :capabilities,
              subtype: :feature,
              id: "image_upload",
              icon: "fa-file-image",
              label: "image input",
              description: "Image upload support",
              user_controlled: false,
              order: 3
            }
          elsif normalized_features[:image_generation] == true
            badges << {
              type: :capabilities,
              subtype: :feature,
              id: "image_generation",
              icon: "fa-image",
              label: "image gen",
              description: "AI image generation capability",
              user_controlled: false,
              order: 3
            }
          end
        end

        # Voice chat capability (easy_submit + auto_speech)
        if normalized_features[:easy_submit] && normalized_features[:auto_speech]
          badges << {
            type: :capabilities,
            subtype: :feature,
            id: "voice_chat",
            icon: "fa-microphone",
            label: "voice chat",
            description: "Voice conversation support",
            user_controlled: false,
            order: 3
          }
        end

        # Badge-worthy features (filter out internal flags and already-handled features)
        BADGE_WORTHY_FEATURES.each do |feature_name, config|
          # Skip features already handled above
          next if feature_name == :image_generation
          next unless normalized_features[feature_name]

          badges << {
            type: :capabilities,
            subtype: :feature,
            id: feature_name.to_s,
            icon: config[:icon],
            label: config[:label],
            description: config[:description],
            user_controlled: config[:user_controlled] || false,
            order: 3
          }
        end

        # Backend models from agents block (CRITICAL: Use settings[:agents])
        if settings[:agents]
          settings[:agents].each do |agent_type, model_name|
            # Skip if model_name is nil or empty
            next unless model_name && !model_name.to_s.strip.empty?

            badges << {
              type: :capabilities,
              subtype: :backend,
              id: "#{agent_type}_backend",
              icon: "fa-server",
              label: model_name.to_s,
              description: "Backend: #{model_name}",
              order: 4
            }
          end
        end

        badges
      end

      # Normalize feature names from MDSL to canonical badge names
      #
      # Maps actual MDSL feature names to the canonical names expected by BADGE_WORTHY_FEATURES
      #
      # @param features [Hash] Raw features hash from MDSL
      # @return [Hash] Normalized features hash
      def self.normalize_feature_names(features)
        # No aliases needed - all features use their canonical names
        features.dup
      end

      # Get Font Awesome icon for tool group
      #
      # @param group_name [String, Symbol] Tool group name
      # @return [String] Font Awesome icon class
      def self.get_tool_group_icon(group_name)
        TOOL_GROUP_ICONS[group_name.to_sym] || "fa-tools"
      end

      # Format label (snake_case → spaces)
      #
      # @param name [String, Symbol] Raw name
      # @return [String] Formatted label
      def self.format_label(name)
        name.to_s.tr("_", " ")
      end

      # Icon mapping for tool groups
      TOOL_GROUP_ICONS = {
        file_operations: "fa-folder",
        python_execution: "fa-terminal",
        web_search_tools: "fa-search",
        web_automation: "fa-globe",
        jupyter_operations: "fa-book",
        file_reading: "fa-book-open",
        content_analysis_openai: "fa-film",
        app_creation: "fa-puzzle-piece"
      }.freeze

      # Configuration for badge-worthy features
      BADGE_WORTHY_FEATURES = {
        monadic: {
          icon: "fa-project-diagram",
          label: "monadic",
          description: "Structured context management"
        },
        mathjax: {
          icon: "fa-square-root-alt",
          label: "mathjax",
          description: "Mathematical notation rendering",
          user_controlled: true
        },
        mermaid: {
          icon: "fa-project-diagram",
          label: "mermaid",
          description: "Diagram rendering",
          user_controlled: true
        },
        websearch: {
          icon: "fa-search",
          label: "web search",
          description: "Native web search capability",
          user_controlled: true
        },
        image_generation: {
          icon: "fa-image",
          label: "image gen",
          description: "Image generation capability"
        },
        video_generation: {
          icon: "fa-video",
          label: "video gen",
          description: "Video generation capability"
        },
        jupyter: {
          icon: "fa-code",
          label: "jupyter",
          description: "Jupyter notebook integration"
        }
      }.freeze
    end
  end
end
