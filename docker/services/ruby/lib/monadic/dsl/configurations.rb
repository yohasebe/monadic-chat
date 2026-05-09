# frozen_string_literal: true

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
    DEFAULT_MODEL = "claude-opus-4-7".freeze

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

  # Privacy Filter Configuration DSL.
  # See docs_dev/privacy_filter_design.md (Block B §2) for the full spec.
  # Usage:
  #   privacy do
  #     enabled true
  #     languages ["ja", "en"]
  #     mask_types [:person, :organization, :email, :phone, :credit_card]
  #     score_threshold 0.4
  #     honorific_trim true
  #     on_failure :block
  #   end
  class PrivacyFilterConfiguration
    # Symbols allowed in `mask_types`. DATE_TIME and `:address` (Presidio
    # LOCATION) are intentionally excluded from the default whitelist because
    # dates and city names rarely identify individuals and create noise in
    # the registry.
    ALLOWED_TYPES = %i[person organization email url address postal_code
                       phone credit_card ip iban us_ssn medical_license].freeze
    # Default whitelist excludes :address (Presidio LOCATION). DATE_TIME is
    # not in ALLOWED_TYPES at all because dates rarely identify individuals.
    DEFAULT_MASK_TYPES = %i[person organization email url postal_code
                            phone credit_card ip iban us_ssn medical_license].freeze
    ALLOWED_FAILURE_MODES = %i[block pass].freeze

    def initialize
      @config = {
        enabled: false,
        languages: ['en'],
        mask_types: DEFAULT_MASK_TYPES.dup,
        score_threshold: 0.4,
        honorific_trim: true,
        on_failure: :block
      }
    end

    def enabled(value)
      @config[:enabled] = !!value
    end

    def languages(value)
      @config[:languages] = Array(value).map(&:to_s)
    end

    def mask_types(value)
      types = Array(value).map(&:to_sym)
      invalid = types - ALLOWED_TYPES
      raise ArgumentError, "Unknown mask_types: #{invalid}" unless invalid.empty?
      @config[:mask_types] = types
    end

    def score_threshold(value)
      raise ArgumentError, "score_threshold must be between 0 and 1" unless (0..1).cover?(value)
      @config[:score_threshold] = value.to_f
    end

    def honorific_trim(value)
      @config[:honorific_trim] = !!value
    end

    def on_failure(value)
      sym = value.to_sym
      raise ArgumentError, "on_failure must be one of #{ALLOWED_FAILURE_MODES}" unless ALLOWED_FAILURE_MODES.include?(sym)
      @config[:on_failure] = sym
    end

    def to_hash
      @config
    end
  end

  # Context Schema Configuration DSL
  # Defines what context fields should be tracked for monadic apps
  # Each field represents a category of information to extract from conversations
  class ContextSchemaConfiguration
    attr_reader :fields

    def initialize
      @fields = []
    end

    # Define a context field to track
    # @param name [Symbol] The field identifier (e.g., :topics, :people)
    # @param options [Hash] Field options
    # @option options [String] :icon FontAwesome icon name (e.g., "fa-tags")
    # @option options [String] :label Display label for the field
    # @option options [String] :description Description for AI extraction prompt
    def field(name, icon: nil, label: nil, description: nil)
      @fields << {
        name: name.to_s,
        icon: icon || default_icon_for(name),
        label: label || name.to_s.capitalize.tr("_", " "),
        description: description || default_description_for(name)
      }
    end

    def to_hash
      {
        fields: @fields
      }
    end

    private

    def default_icon_for(name)
      case name.to_sym
      when :topics then "fa-tags"
      when :people then "fa-users"
      when :notes then "fa-sticky-note"
      when :images, :generated_images, :uploaded_images then "fa-image"
      when :files then "fa-file"
      when :code then "fa-code"
      when :links, :urls then "fa-link"
      when :dates then "fa-calendar"
      when :locations then "fa-map-marker"
      when :tasks then "fa-tasks"
      when :questions then "fa-question"
      when :ideas then "fa-lightbulb"
      when :decisions then "fa-check-circle"
      when :styles, :style_preferences then "fa-palette"
      when :prompts, :prompt_history then "fa-history"
      else "fa-circle"
      end
    end

    def default_description_for(name)
      case name.to_sym
      when :topics then "Main subjects discussed"
      when :people then "Names of people mentioned"
      when :notes then "Important facts to remember"
      when :images then "Images referenced in conversation"
      when :generated_images then "Images generated in this session"
      when :uploaded_images then "Images uploaded by user"
      when :files then "Files mentioned or processed"
      when :code then "Code snippets discussed"
      when :links, :urls then "URLs and web links"
      when :dates then "Important dates mentioned"
      when :locations then "Places or locations discussed"
      when :tasks then "Action items or tasks"
      when :questions then "Questions raised"
      when :ideas then "Ideas proposed"
      when :decisions then "Decisions made"
      when :styles, :style_preferences then "Visual or stylistic preferences"
      when :prompts, :prompt_history then "Key prompts or requests"
      else "#{name.to_s.tr('_', ' ').capitalize} information"
      end
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
    def initialize(state)
      @state = state
    end

    def method_missing(method_name, *args)
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
