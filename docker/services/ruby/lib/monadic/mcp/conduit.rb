# frozen_string_literal: true

require 'json'
require_relative 'cost_guard'

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
    # Phase 0 tools are read-only, side-effect-free and zero-cost:
    #   - monadic_status        : backend + dependent-container readiness
    #   - monadic_list_models   : provider × model + capabilities (from the SSOT)
    #
    # Phase 1 introduces the first provider-spending capability:
    #   - monadic_query         : single-provider, context-aware query
    #
    # Every spending tool goes through CostGuard (design §5): the platform
    # reserves a token budget BEFORE the call and records usage AFTER, so a
    # runaway CLI agent is refused rather than trusted. Provider Independence is
    # preserved by borrowing a real per-provider app instance from APPS and
    # calling its own send_query (no cross-provider routing).
    module Conduit
      module_function

      # Default cap on a single query's output tokens when the caller omits one.
      DEFAULT_MAX_OUTPUT = 4096

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
          },
          {
            name: "monadic_query",
            description: "Send a one-shot query to a specific provider's chat model and " \
                         "return the text response. Uses Monadic's own provider helpers " \
                         "(your local API keys, data stays local). Spends provider tokens; " \
                         "every call is gated by a platform-side token budget (see " \
                         "monadic_status.conduit_budget). Provide either `message` (a single " \
                         "user prompt) or `messages` (a full role/content conversation).",
            input_schema: {
              type: "object",
              properties: {
                provider: {
                  type: "string",
                  description: "Provider to query (openai, anthropic, gemini, cohere, " \
                               "mistral, deepseek, xai, ollama). Aliases (claude/google/grok) " \
                               "are accepted."
                },
                message: {
                  type: "string",
                  description: "A single user prompt. Use this OR `messages`, not both."
                },
                messages: {
                  type: "array",
                  description: "A full conversation as role/content turns. Use this OR `message`.",
                  items: {
                    type: "object",
                    properties: {
                      role: { type: "string", description: "user | assistant | system" },
                      content: { type: "string", description: "Message text." }
                    },
                    required: ["role", "content"]
                  }
                },
                system: {
                  type: "string",
                  description: "Optional system prompt prepended to the request."
                },
                model: {
                  type: "string",
                  description: "Optional model id. Defaults to the provider's chat default."
                },
                max_tokens: {
                  type: "integer",
                  description: "Optional cap on output tokens (default #{DEFAULT_MAX_OUTPUT})."
                },
                temperature: {
                  type: "number",
                  description: "Optional sampling temperature (ignored by models that reject it)."
                }
              },
              required: ["provider"],
              additionalProperties: false
            },
            handler: :handle_query
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
          conduit_budget: CostGuard.status,
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

      def handle_query(arguments)
        provider_arg = (arguments["provider"] || arguments[:provider]).to_s.strip
        raise ArgumentError, "provider is required" if provider_arg.empty?

        canonical = MonadicDSL::ProviderConfig.new(provider_arg).standard_key

        messages = normalize_messages(arguments)
        raise ArgumentError, "provide either `message` or `messages`" if messages.empty?

        system = (arguments["system"] || arguments[:system]).to_s
        model = (arguments["model"] || arguments[:model]).to_s.strip
        model = nil if model.empty?
        model ||= default_chat_model_for(canonical)
        raise "no chat model resolved for provider '#{canonical}'" if model.to_s.empty?

        max_output = (arguments["max_tokens"] || arguments[:max_tokens]).to_i
        max_output = DEFAULT_MAX_OUTPUT if max_output <= 0
        temperature = arguments["temperature"] || arguments[:temperature]

        host = provider_host(canonical)
        unless host
          raise "no app instance available for provider '#{canonical}' " \
                "(is the provider configured and an app loaded?)"
        end

        # Cost gate (hard ceiling) BEFORE spending any tokens.
        input_tokens = CostGuard.estimate_tokens(
          messages.map { |m| m["content"] }.join("\n") + "\n" + system
        )
        projected = input_tokens + max_output
        begin
          CostGuard.ensure_within!(projected)
        rescue CostGuard::BudgetExceeded => e
          return {
            provider: canonical,
            model: model,
            success: false,
            error: "❌ Budget exceeded: #{e.message}",
            budget: CostGuard.status
          }
        end

        body = { "messages" => messages, "model" => model, "max_tokens" => max_output }
        body["system"] = system unless system.empty?
        body["temperature"] = temperature unless temperature.nil?

        raw = host.send_query(body, model: model)
        normalized = normalize_query_response(raw)

        output_tokens = CostGuard.estimate_tokens(normalized[:text] || normalized[:error])
        CostGuard.record(input_tokens + output_tokens)

        {
          provider: canonical,
          model: model,
          success: normalized[:success],
          text: normalized[:text],
          tool_calls: normalized[:tool_calls],
          error: normalized[:error],
          usage: {
            input_tokens_est: input_tokens,
            output_tokens_est: output_tokens,
            note: "estimated via tiktoken; send_query does not expose provider usage"
          },
          budget: CostGuard.status
        }.compact
      end

      # ---- Query helpers --------------------------------------------------

      # Accept either a single `message` string or a `messages` array of
      # role/content (or role/text) turns; return Chat-Completions style
      # string-keyed message hashes.
      def normalize_messages(arguments)
        raw_messages = arguments["messages"] || arguments[:messages]
        single = arguments["message"] || arguments[:message]

        if raw_messages.is_a?(Array) && !raw_messages.empty?
          raw_messages.map do |m|
            next nil unless m.is_a?(Hash)
            role = (m["role"] || m[:role]).to_s
            role = "user" if role.empty?
            content = (m["content"] || m[:content] || m["text"] || m[:text]).to_s
            next nil if content.empty?
            { "role" => role, "content" => content }
          end.compact
        elsif !single.to_s.empty?
          [{ "role" => "user", "content" => single.to_s }]
        else
          []
        end
      end

      def default_chat_model_for(provider)
        model = Monadic::Utils::ModelSpec.default_chat_model(provider)
        return model if model && !model.to_s.empty?

        if defined?(::SystemDefaults)
          ::SystemDefaults.get_default_model(provider)
        end
      rescue StandardError
        nil
      end

      # Borrow a loaded app instance that includes the provider's helper (i.e.
      # responds to send_query) and whose group matches the provider. Prefers a
      # plain Chat app. Mirrors TitleSuggester / AIUserAgent provider routing.
      def provider_host(provider)
        return nil unless defined?(::APPS) && ::APPS.respond_to?(:each)

        keywords = provider_keywords(provider)
        fallback = nil

        ::APPS.each do |_key, app|
          next unless app.respond_to?(:settings) && app.respond_to?(:send_query)
          group = app.settings && app.settings["group"].to_s.downcase.strip
          next if group.to_s.empty?
          next unless keywords.any? { |kw| group.include?(kw) }

          return app if app.settings["display_name"] == "Chat"
          fallback ||= app
        end

        fallback
      end

      def provider_keywords(provider)
        case provider
        when "anthropic" then %w[anthropic claude]
        when "xai" then %w[grok xai]
        when "gemini" then %w[gemini google]
        else [provider]
        end
      end

      # send_query returns a String (text, or a formatted "[Provider] X Error:"
      # string) or a Hash { text:, tool_calls: }. Normalize to a uniform shape.
      def normalize_query_response(raw)
        case raw
        when String
          if error_string?(raw)
            { success: false, error: raw }
          else
            { success: true, text: raw }
          end
        when Hash
          text = raw[:text] || raw["text"]
          tool_calls = raw[:tool_calls] || raw["tool_calls"]
          if text && !text.to_s.empty?
            { success: true, text: text, tool_calls: (tool_calls unless tool_calls.to_s.empty?) }
          else
            { success: false, error: raw.to_s }
          end
        when nil
          { success: false, error: "empty response from provider" }
        else
          { success: true, text: raw.to_s }
        end
      end

      # Detects ErrorFormatter's "[Provider] <Category> Error: ..." convention.
      def error_string?(text)
        text.is_a?(String) && text.match?(/\A\[[^\]]+\][^\n]*?Error:/)
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
