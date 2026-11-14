# frozen_string_literal: true

require_relative '../substitution/vocabulary'

module MonadicDSL
  # Description builder for multi-language support
  class DescriptionBuilder
    attr_reader :descriptions

    def initialize
      @descriptions = {}
    end

    # Define methods for each supported language
    %w[en ja zh ko es fr de].each do |lang|
      define_method(lang) do |text|
        @descriptions[lang] = text
      end
    end
  end

  # Context Management Configuration DSL
  class ContextManagementConfiguration
    def initialize
      @config = {}
    end

    def edits(edits_array)
      @config[:edits] = edits_array
    end

    def to_hash
      @config
    end
  end

  # Compaction Configuration (OpenAI Responses API server-side compaction)
  # See docs_dev/provider_specific_features.md and the OpenAI documentation:
  # https://developers.openai.com/api/docs/guides/compaction
  #
  # When the rendered token count crosses compact_threshold, the server runs
  # server-side compaction and returns an encrypted compaction item that
  # carries forward key prior state into the next request. This keeps long
  # agentic conversations under the model's context window automatically.
  class CompactionConfiguration
    # Sensible default for GPT-5-class models with 200K context windows
    # (roughly 75% of the window, leaves headroom for a complete response).
    DEFAULT_COMPACT_THRESHOLD = 150_000

    def initialize
      @config = { compact_threshold: DEFAULT_COMPACT_THRESHOLD }
    end

    def compact_threshold(value)
      @config[:compact_threshold] = value
    end

    def to_hash
      @config
    end
  end

  # Advisor Tool Configuration (Anthropic Advisor Tool beta)
  # See docs_dev/provider_specific_features.md and the Anthropic documentation:
  # https://docs.claude.com/en/docs/agents-and-tools/tool-use/advisor-tool
  class AdvisorToolConfiguration
    DEFAULT_MODEL = "claude-opus-5-5".freeze

    def initialize
      @config = { model: DEFAULT_MODEL }
    end

    def model(value)
      @config[:model] = value
    end

    def max_uses(value)
      @config[:max_uses] = value
    end

    # Accepts true (enables ephemeral 5m), false, a ttl string ("5m"/"1h"), or a hash
    def caching(value)
      @config[:caching] =
        case value
        when true       then { type: "ephemeral", ttl: "5m" }
        when false, nil then nil
        when "5m", "1h" then { type: "ephemeral", ttl: value }
        when Hash       then value
        else value
        end
    end

    def to_hash
      @config.compact
    end
  end

  # Vocabulary Configuration DSL (built-in opt-in, MVP).
  #
  # Declares which built-in `${TOKEN}` variables an app exposes. Behaviour
  # (resolution/display) lives in Ruby (Monadic::Substitution::Vocabulary,
  # Phase 4), keeping the MDSL purely declarative. The produced hash is plain
  # data (symbols only) so it serializes through the app-class generator's
  # `.inspect` path.
  #
  # Usage:
  #   vocabulary do
  #     use :shared
  #   end
  class VocabularyConfiguration
    def initialize
      @tokens = []
      @enabled = true
    end

    # Expose one or more built-in vocabulary tokens. Unknown names raise so a
    # typo (`use :shred`) fails fast at app-load time rather than silently
    # producing a token nothing resolves.
    def use(*names)
      names.flatten.each do |name|
        sym = name.to_sym
        unless Monadic::Substitution::Vocabulary.builtin?(sym)
          raise ArgumentError,
                "Unknown vocabulary token: #{name.inspect}. " \
                "Known built-ins: #{Monadic::Substitution::Vocabulary.builtin_names}"
        end
        @tokens << sym unless @tokens.include?(sym)
      end
    end

    # Opt out: `${SHARED}` (and any vocabulary) is on by default for every app;
    # an app with strict output can disable it with `vocabulary false` (which
    # sets enabled=false via #disable!).
    def disable!
      @enabled = false
    end

    def to_hash
      { tokens: @tokens, enabled: @enabled }
    end
  end

  # App-level Agents Configuration DSL (for STT, TTS, etc.)
  class AppAgentsConfiguration
    def initialize
      @config = {}
    end

    def speech_to_text(options = {})
      model = options[:model] || options["model"]
      @config[:speech_to_text] = model if model
    end

    def to_hash
      @config
    end
  end

  # LLM Configuration for simplified syntax
  class LLMConfiguration
    # Map newer parameter names to standard ones
    PARAMETER_MAP = {
      max_output_tokens: :max_tokens
    }.freeze

    def initialize(state)
      @state = state
    end

    def provider(value)
      @state.settings[:provider] = value
    end

    def model(value = nil)
      provider_name = @state.settings[:provider].to_s.downcase
      provider_env_var = ProviderConfig.new(provider_name).default_model_env

      # If a value is provided, it takes precedence over environment variables
      if value
        # Handle both single model and array of models
        if value.is_a?(Array)
          # Store the array as models (for dropdown) and first item as default model
          @state.settings[:models] = value
          @state.settings[:model] = value.first
        else
          @state.settings[:model] = value
        end
      # Otherwise, try to use environment variable if available
      elsif provider_env_var && ENV[provider_env_var]
        @state.settings[:model] = ENV[provider_env_var]
      # For Ollama, don't set a default model here - let the UI handle it
      elsif provider_name.include?("ollama")
        # Don't set a default model - the UI will select the first available model
        @state.settings[:model] = nil
      end
    end

    def temperature(value)
      @state.settings[:temperature] = value
    end

    def max_tokens(value)
      @state.settings[:max_tokens] = value
    end

    def max_output_tokens(value)
      # Alias for max_tokens
      max_tokens(value)
    end

    def reasoning_effort(value)
      @state.settings[:reasoning_effort] = value
    end

    def reasoning_content(value)
      # Per-app default for the On/Off reasoning toggle (currently DeepSeek
      # V4). Independent of reasoning_effort: "disabled" turns thinking off by
      # default, "enabled" turns it on. The user can still flip it in the UI.
      @state.settings[:reasoning_content] = value
    end

    def verbosity(value)
      # GPT-5 verbosity setting: "high", "medium", or "low"
      @state.settings[:verbosity] = value
    end

    def presence_penalty(value)
      @state.settings[:presence_penalty] = value
    end

    def frequency_penalty(value)
      @state.settings[:frequency_penalty] = value
    end

    def response_format(value)
      @state.settings[:response_format] = value
    end

    def context_size(value)
      @state.settings[:context_size] = value
    end

    def tool_choice(value)
      @state.settings[:tool_choice] = value
    end

    def parallel_function_calling(value)
      @state.settings[:parallel_function_calling] = value
    end

    def betas(value)
      # Beta headers for provider-specific features (e.g., Anthropic Skills)
      @state.settings[:betas] = value
    end

    def agents(&block)
      # Support for internal agent configuration (e.g., code generators)
      if block_given?
        agent_config = AgentsConfiguration.new
        agent_config.instance_eval(&block)
        @state.settings[:agents] = agent_config.to_h
      end
    end

    def method_missing(method_name, *args)
      if PARAMETER_MAP.key?(method_name)
        send(PARAMETER_MAP[method_name], *args)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      PARAMETER_MAP.key?(method_name) || super
    end
  end

  # Agents Configuration for internal code generation agents
  class AgentsConfiguration
    def initialize
      @agents = {}
    end

    def code_generator(model:)
      @agents[:code_generator] = model
    end

    def chord_validator(model:)
      @agents[:chord_validator] = model
    end

    # Support for any agent type via method_missing
    def method_missing(method_name, model:)
      @agents[method_name.to_sym] = model
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end

    def to_h
      @agents
    end
  end

  # Simplified Feature Configuration
  class SimplifiedFeatureConfiguration
    # Settings of earlier versions: read and not used.
    RETIRED = %i[monadic turn_state].freeze

    def initialize(state)
      @state = state
    end

    def method_missing(method_name, *args)
      return if RETIRED.include?(method_name)

      # Default all called methods to true, handle special cases
      # For multi-argument settings like tts_target, store as array
      value = if args.empty?
                true
              elsif args.length == 1
                args.first
              else
                args  # Store multiple arguments as array
              end

      @state.features[method_name] = value
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end
end
