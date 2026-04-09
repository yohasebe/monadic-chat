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
