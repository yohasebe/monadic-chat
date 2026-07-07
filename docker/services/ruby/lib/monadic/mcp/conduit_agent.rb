# frozen_string_literal: true

require 'securerandom'
require 'timeout'
require 'active_support/core_ext/hash/indifferent_access'
require_relative '../shared_tools/registry'

module Monadic
  module MCP
    # Headless, bounded, tool-using agent.
    #
    # Rather than hand-format tools per provider, this builds a REAL Monadic app
    # at run time via the same DSL pipeline (`MonadicDSL.app` + `features` /
    # `import_shared_tools`) that every shipped app uses. The DSL produces the
    # correctly per-provider-formatted `settings[:tools]`, wires the executor
    # modules, and sets the session conventions — so adding a tool group or a
    # provider needs NO conversion code here. The agent then drives the app's
    # own tool-execution loop (api_request), whose MAX_FUNC_CALLS cap (20 tool
    # calls/turn) + ErrorPatternDetector guarantee termination; Conduit adds a
    # budget gate on top.
    #
    # Only safe, read-only tool groups are allowed by default; execution /
    # file-write / container groups are excluded.
    module ConduitAgent
      module_function

      # Safe, read-only tool groups. Single source of truth lives in
      # MonadicSharedTools::Registry.safe_groups (symbols); Conduit compares
      # against user-supplied strings, so mirror it as strings here.
      SAFE_GROUPS = MonadicSharedTools::Registry.safe_groups.map(&:to_s).freeze

      DEFAULT_GROUPS = %w[web_search_tools].freeze

      # Sliding-window size the WebSocket layer normally injects at runtime.
      RUNTIME_CONTEXT_SIZE = 100

      # Wall-clock ceiling for a single agent run, in seconds. MAX_FUNC_CALLS
      # (tool count) and CostGuard (tokens) already bound the agent, but neither
      # bounds elapsed time: a slow provider, a hung HTTP read, or a tool that
      # blocks could otherwise stall the run indefinitely. Override via the
      # CONDUIT_AGENT_WALL_CLOCK env var.
      DEFAULT_WALL_CLOCK_LIMIT = 300

      @apps_mutex = Mutex.new

      def allowed_groups
        SAFE_GROUPS
      end

      # Resolved wall-clock limit (seconds). Falls back to the default when the
      # env var is absent or not a positive integer.
      def wall_clock_limit
        raw = (defined?(CONFIG) ? CONFIG["CONDUIT_AGENT_WALL_CLOCK"] : nil).to_s.strip
        seconds = raw.to_i
        seconds.positive? ? seconds : DEFAULT_WALL_CLOCK_LIMIT
      end

      # Run the agent; returns the final answer text (or an "ERROR:"/provider
      # error string). `model` is resolved by the caller.
      def run(task:, provider:, model:, groups: DEFAULT_GROUPS)
        groups = normalize_groups(groups)

        state = build_agent_app(provider.to_s, model.to_s, groups)
        klass = Object.const_get(state.name)
        # Mirror init_apps: the DSL stores @settings on the class; an instance
        # gets them as a HashWithIndifferentAccess (string/symbol agnostic, which
        # is what api_request reads).
        host = klass.new
        host.settings = ::ActiveSupport::HashWithIndifferentAccess.new(
          klass.instance_variable_get(:@settings) || {}
        )
        # Disable Progressive Tool Disclosure: an autonomous agent should see all
        # its tools immediately, not unlock them via request_tool. With PTD off,
        # every provider's api_request surfaces web search directly (the Tavily-
        # fallback providers push their WEBSEARCH_TOOLS instead of hiding them).
        host.settings.delete("progressive_tools")
        app_key = host.settings["app_name"]

        register(app_key, host)
        begin
          # session[:parameters] = the app's settings PLUS the runtime params the
          # WebSocket layer normally injects (which a headless run lacks):
          #   - "message": every provider's prepare_request reads the user input
          #     from obj["message"] and appends it to session[:messages] itself,
          #     so we pass the task there (NOT pre-added to messages) and start
          #     with an empty history — exactly the WebSocket's first-turn shape.
          #   - "context_size": providers take messages.last(N); a missing/zero N
          #     drops the turn and the model just greets.
          params = host.settings.merge(
            "context_size" => RUNTIME_CONTEXT_SIZE,
            "message" => task.to_s
          )
          session = { parameters: params, messages: [] }
          results = Timeout.timeout(wall_clock_limit) do
            host.api_request("user", session, call_depth: 0) { |_fragment| nil }
          end
          extract_text(results)
        rescue Timeout::Error
          "ERROR: agent exceeded its wall-clock limit of #{wall_clock_limit}s"
        ensure
          unregister(app_key)
          remove_app_class(state.name)
        end
      end

      # --- build via the real DSL pipeline ------------------------------

      # Construct an agent app through the DSL. Web search is enabled via the
      # `websearch` feature (which sets up each provider's native/Tavily search
      # correctly); every other group is imported from the shared-tool registry.
      def build_agent_app(provider, model, groups)
        prov = provider
        mdl = model
        sys = system_prompt
        web = groups.include?("web_search_tools")
        other = groups - ["web_search_tools"]
        # Concurrency invariant — DO NOT memoize this app per (provider/model/
        # groups). Tool execution dispatches via APPS[app_name].send(fn) (see
        # cohere_helper#invoke_cohere_tool_function / claude_helper), so app_name
        # is a runtime routing key. A fresh, uniquely-named class+instance per run
        # gives each concurrent run its own APPS slot, settings, and session.
        # Reusing one host under a stable name would make two concurrent same-key
        # runs (Conduit runs blocking turns off-reactor in their own threads) race
        # on host.settings AND collide in APPS, routing tool calls to the wrong
        # run. The per-run DSL build is network-cheap next to an LLM turn.
        name = "ConduitAgentRun#{SecureRandom.hex(4)}"

        MonadicDSL.app(name) do
          llm do
            provider prov
            model mdl
          end
          system_prompt sys
          features { websearch true } if web
          unless other.empty?
            tools do
              other.each { |g| import_shared_tools g.to_sym, visibility: "always" }
            end
          end
        end
      end

      def normalize_groups(groups)
        list = Array(groups).map(&:to_s)
        list = DEFAULT_GROUPS.dup if list.empty?

        not_allowed = list - allowed_groups
        unless not_allowed.empty?
          raise ArgumentError,
                "tool group(s) not permitted for the agent: #{not_allowed.join(', ')} " \
                "(allowed: #{allowed_groups.join(', ')})"
        end
        list.uniq
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

      def remove_app_class(name)
        @apps_mutex.synchronize do
          Object.send(:remove_const, name) if Object.const_defined?(name, false)
        end
      rescue StandardError
        nil
      end
    end
  end
end
