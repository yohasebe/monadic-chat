# frozen_string_literal: true

require 'json'

module Monadic
  module MCP
    # Monadic Conduit — the capability surface exposed to external agentic CLIs
    # (e.g. Claude Code) over MCP.
    #
    # Design principle (the "first principle"): Conduit does NOT re-publish the
    # app-specific tools (the former `app__tool` surface). It publishes a small,
    # stable set of *capabilities* over Monadic's data, environment, model access
    # and modalities — leaving orchestration to the calling CLI agent.
    #
    # Phase 0 (this file) ships two read-only, side-effect-free, zero-cost tools:
    #   - monadic_status        : backend + dependent-container readiness
    #   - monadic_list_models   : provider × model + capabilities (from the SSOT)
    #
    # Neither tool calls a provider API or mutates a container, so they carry no
    # runaway-cost or arbitrary-execution risk. Cost-safety and authorization
    # gates (design §5/§6) are introduced alongside the write/query tools in
    # later phases.
    module Conduit
      module_function

      # Public: MCP tool definitions for `tools/list`.
      def tools
        registry.map do |tool|
          {
            name: tool[:name],
            description: tool[:description],
            inputSchema: tool[:input_schema]
          }
        end
      end

      # Public: whether a tool name belongs to the Conduit surface.
      def tool?(name)
        registry.any? { |tool| tool[:name] == name }
      end

      # Public: invoke a Conduit tool. Returns a Ruby Hash (structured result);
      # the MCP server wraps it as both text and structuredContent.
      def call(name, arguments = {})
        tool = registry.find { |t| t[:name] == name }
        raise "Unknown Conduit tool: #{name}" unless tool

        send(tool[:handler], arguments || {})
      end

      # ---- Tool registry --------------------------------------------------

      def registry
        [
          {
            name: "monadic_status",
            description: "Report Monadic Chat backend health: version, execution mode, " \
                         "MCP server state, which providers have API keys configured, and " \
                         "which dependent containers are running. Read-only.",
            input_schema: { type: "object", properties: {}, additionalProperties: false },
            handler: :handle_status
          },
          {
            name: "monadic_list_models",
            description: "List available providers and their models with capabilities " \
                         "(context window, max output, vision/tool/reasoning support) drawn " \
                         "from Monadic's model specification. Read-only; no provider API call. " \
                         "Optionally filter by provider, or include deprecated models.",
            input_schema: {
              type: "object",
              properties: {
                provider: {
                  type: "string",
                  description: "Optional provider filter (e.g. openai, anthropic, gemini, " \
                               "cohere, mistral, deepseek, xai, ollama). Aliases like " \
                               "'claude', 'google', 'grok' are accepted."
                },
                include_deprecated: {
                  type: "boolean",
                  description: "Include models marked deprecated. Defaults to false."
                }
              },
              additionalProperties: false
            },
            handler: :handle_list_models
          }
        ]
      end

      # ---- Handlers -------------------------------------------------------

      def handle_status(_arguments)
        {
          backend: {
            name: "monadic-chat",
            version: (defined?(Monadic::VERSION) ? Monadic::VERSION : "unknown"),
            mode: execution_mode
          },
          mcp: safe_mcp_status,
          providers: provider_readiness,
          containers: container_readiness
        }
      end

      def handle_list_models(arguments)
        include_deprecated = truthy?(arguments["include_deprecated"] || arguments[:include_deprecated])
        requested = (arguments["provider"] || arguments[:provider]).to_s.strip

        provider_keys = MonadicDSL::ProviderConfig::PROVIDER_INFO.keys
        if !requested.empty?
          canonical = MonadicDSL::ProviderConfig.new(requested).standard_key
          provider_keys = provider_keys.select { |k| k == canonical }
        end

        providers = provider_keys.map do |provider|
          provider_models_entry(provider, include_deprecated)
        end

        { providers: providers }
      end

      # ---- Status helpers -------------------------------------------------

      def execution_mode
        if defined?(Monadic::Utils::Environment) &&
           Monadic::Utils::Environment.respond_to?(:in_container?)
          Monadic::Utils::Environment.in_container? ? "container" : "host"
        else
          "unknown"
        end
      end

      def safe_mcp_status
        return {} unless defined?(Monadic::MCP::Server) &&
                         Monadic::MCP::Server.respond_to?(:status)

        Monadic::MCP::Server.status
      rescue StandardError
        {}
      end

      def provider_readiness
        MonadicDSL::ProviderConfig::PROVIDER_INFO.map do |provider, info|
          {
            provider: provider,
            display_group: info[:display_group],
            configured: provider_configured?(info[:api_key])
          }
        end
      end

      # A provider with no api_key requirement (Ollama, local) is considered
      # configured; otherwise the key must be present and non-empty in CONFIG.
      def provider_configured?(api_key_env)
        return true if api_key_env.nil?
        return false unless defined?(CONFIG) && CONFIG

        !CONFIG[api_key_env].to_s.strip.empty?
      end

      def container_readiness
        return [] unless defined?(Monadic::Utils::ContainerDependencies)

        deps = Monadic::Utils::ContainerDependencies
        deps::CONTAINER_NAMES.map do |service, container_name|
          running =
            begin
              deps.container_running?(service)
            rescue StandardError
              nil
            end
          {
            service: service.to_s,
            container: container_name,
            running: running
          }
        end
      end

      # ---- Model listing helpers -----------------------------------------

      # Text-LLM categories whose models get capability enrichment. Media
      # categories (image/video/tts/music/audio_transcription) are listed under
      # `categories` for discovery but not enriched with chat capabilities.
      TEXT_CATEGORIES = %w[chat code vision].freeze

      def provider_models_entry(provider, include_deprecated)
        info = MonadicDSL::ProviderConfig::PROVIDER_INFO[provider]
        categories = provider_categories(provider)

        text_models = TEXT_CATEGORIES
                      .flat_map { |cat| categories[cat] || [] }
                      .uniq

        models = text_models.map { |id| model_capabilities(id) }
        models = models.reject { |m| m[:deprecated] } unless include_deprecated

        {
          provider: provider,
          display_group: info && info[:display_group],
          configured: provider_configured?(info && info[:api_key]),
          default_chat_model: categories.dig("chat", 0),
          categories: categories,
          models: models
        }
      end

      def provider_categories(provider)
        defaults = Monadic::Utils::ModelSpec.load_provider_defaults
        entry = defaults[provider]
        entry.is_a?(Hash) ? entry : {}
      rescue StandardError
        {}
      end

      def model_capabilities(model_id)
        spec = Monadic::Utils::ModelSpec.get_model_spec(model_id)
        if spec.nil? || spec.empty?
          return { id: model_id, known: false }
        end

        {
          id: model_id,
          known: true,
          context_window: numeric_max(spec["context_window"]),
          max_output_tokens: numeric_max(spec["max_output_tokens"]),
          vision: Monadic::Utils::ModelSpec.vision_capability?(model_id),
          tool: Monadic::Utils::ModelSpec.tool_capability?(model_id),
          reasoning: Monadic::Utils::ModelSpec.is_reasoning_model?(model_id),
          deprecated: Monadic::Utils::ModelSpec.deprecated?(model_id)
        }
      rescue StandardError
        { id: model_id, known: false }
      end

      # context_window / max_output_tokens are stored as [min, max] in the spec.
      def numeric_max(value)
        value.is_a?(Array) ? value.last : value
      end

      def truthy?(value)
        value == true || value.to_s.strip.downcase == "true"
      end
    end
  end
end
