# frozen_string_literal: true

require 'securerandom'

module Monadic
  module MCP
    # Headless, bounded, tool-using agent. Runs a provider's real tool-execution
    # loop (api_request) so the model can call tools, read results, and decide to
    # call more — web search is just one tool group. Termination is guaranteed by
    # the engine's own MAX_FUNC_CALLS cap (20 tool calls/turn) plus the
    # ErrorPatternDetector (stuck-loop detection); Conduit adds a budget gate.
    #
    # Tool groups come from the shared-tool Registry (module + JSON schemas), so
    # the mechanism is tool-agnostic. Only safe, read-only groups are allowed by
    # default; execution / file-write / container groups are excluded.
    module ConduitAgent
      module_function

      # Safe, read-only tool groups an autonomous agent may use. Deliberately
      # excludes python_execution, file_operations, web_automation,
      # jupyter_operations, app_creation, parallel_* (code/file/container power).
      SAFE_GROUPS = %w[
        web_search_tools file_reading image_analysis video_analysis
        audio_transcription session_context verification planning
      ].freeze

      DEFAULT_GROUPS = %w[web_search_tools].freeze

      @apps_mutex = Mutex.new

      def allowed_groups
        SAFE_GROUPS
      end

      # Run the agent and return its final answer text (or an "ERROR:"/provider
      # error string). `model` is resolved by the caller.
      def run(task:, provider:, model:, groups: DEFAULT_GROUPS)
        groups = normalize_groups(groups)
        helper = provider_helper(provider)

        tool_defs, modules = assemble_tools(groups)
        app_key = "ConduitAgent_#{SecureRandom.hex(6)}"
        host = build_host(helper, modules, tool_defs, model, app_key)

        register(app_key, host)
        begin
          session = build_session(task, model, app_key, tool_defs)
          results = host.api_request("user", session, call_depth: 0) { |_fragment| nil }
          extract_text(results)
        ensure
          unregister(app_key)
        end
      end

      # --- internals ----------------------------------------------------

      def normalize_groups(groups)
        list = Array(groups).map(&:to_s)
        list = DEFAULT_GROUPS.dup if list.empty?

        not_allowed = list - allowed_groups
        unless not_allowed.empty?
          raise ArgumentError,
                "tool group(s) not permitted for the agent: #{not_allowed.join(', ')} " \
                "(allowed: #{allowed_groups.join(', ')})"
        end

        unknown = list.reject { |g| MonadicSharedTools::Registry.group_exists?(g.to_sym) }
        raise ArgumentError, "unknown tool group(s): #{unknown.join(', ')}" unless unknown.empty?

        list.uniq
      end

      def provider_helper(provider)
        name = MonadicDSL::ProviderConfig::PROVIDER_INFO.dig(provider, :helper_module)
        raise ArgumentError, "no helper for provider '#{provider}'" unless name && Object.const_defined?(name)

        Object.const_get(name)
      end

      # Build the OpenAI-style function tool definitions + the executor modules
      # for the requested groups, from the Registry.
      def assemble_tools(groups)
        defs = []
        modules = []
        groups.each do |group|
          sym = group.to_sym
          MonadicSharedTools::Registry.tools_for(sym).each do |spec|
            s = spec.respond_to?(:to_h) ? spec.to_h : spec
            defs << {
              "type" => "function",
              "function" => {
                "name" => s[:name].to_s,
                "description" => s[:description].to_s,
                "parameters" => params_to_schema(s[:parameters])
              },
              "strict" => false
            }
          end
          modules << Object.const_get(MonadicSharedTools::Registry.module_name_for(sym))
        end
        [defs, modules]
      end

      def build_host(helper, modules, tool_defs, model, app_key)
        sys = system_prompt
        Class.new(MonadicApp) do
          include helper
          modules.each { |m| include m }
          define_method(:settings) do
            { "tools" => tool_defs, "app_name" => app_key, "model" => model, "initial_prompt" => sys }
          end
        end.new
      end

      def build_session(task, model, app_key, tool_defs)
        {
          parameters: {
            "model" => model,
            "app_name" => app_key,
            "tools" => tool_defs,
            "initial_prompt" => system_prompt,
            "temperature" => 0.3
          },
          messages: [{ "role" => "user", "text" => task.to_s, "active" => true }]
        }
      end

      def system_prompt
        "You are an autonomous assistant with access to tools. Use the tools as needed to " \
          "accomplish the user's task: search, read, and analyze, then reason over the results " \
          "and call tools again if useful. When you have gathered enough, STOP calling tools and " \
          "write a complete, self-contained final answer. Cite source URLs you actually used."
      end

      def extract_text(results)
        return "" unless results.is_a?(Array) && results.first

        first = results.first
        return first.to_s unless first.is_a?(Hash)

        first["content"] || first[:content] || first.dig("choices", 0, "message", "content") || first.to_s
      end

      def register(key, host)
        @apps_mutex.synchronize { APPS[key] = host }
      end

      def unregister(key)
        @apps_mutex.synchronize { APPS.delete(key) }
      end

      # Registry stores a tool's parameters as an array of {name, type,
      # description, required, ...}; providers want a JSON-Schema object.
      def params_to_schema(params)
        properties = {}
        required = []
        Array(params).each do |raw|
          p = raw.respond_to?(:to_h) ? raw.to_h : raw
          name = (p[:name] || p["name"]).to_s
          next if name.empty?

          schema = {}
          p.each do |k, v|
            next if %i[name required].include?(k.to_sym)

            schema[k.to_s] = deep_stringify(v)
          end
          schema["type"] ||= "string"
          properties[name] = schema
          required << name if p[:required] || p["required"]
        end
        { "type" => "object", "properties" => properties, "required" => required, "additionalProperties" => false }
      end

      def deep_stringify(obj)
        case obj
        when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
        when Array then obj.map { |e| deep_stringify(e) }
        else obj
        end
      end
    end
  end
end
