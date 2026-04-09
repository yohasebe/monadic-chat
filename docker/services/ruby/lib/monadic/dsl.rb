# Add required utilities
require_relative 'utils/fa_icons'
begin
  require_relative 'utils/mdsl_validator'
rescue LoadError
  # mdsl_validator is optional
end
require_relative 'utils/provider_model_cache'
require_relative 'shared_tools/registry'
require_relative 'shared_tools/file_operations'
require_relative 'shared_tools/python_execution'
require_relative 'shared_tools/web_search_tools'
require_relative 'shared_tools/app_creation'
require_relative 'shared_tools/file_reading'
require_relative 'shared_tools/jupyter_operations'
require_relative 'shared_tools/web_automation'
require_relative 'shared_tools/audio_transcription'
require_relative 'shared_tools/image_analysis'
require_relative 'shared_tools/video_analysis'
require_relative 'shared_tools/session_context'
require_relative 'shared_tools/context_panel_helper'
require_relative 'shared_tools/planning'
require_relative 'shared_tools/verification'
require_relative 'shared_tools/parallel_dispatch'
require_relative 'dsl/configurations'
require_relative 'dsl/loader'
require_relative 'dsl/provider_config'
require_relative 'dsl/tool_definitions'
require_relative 'dsl/tool_formatters'

# Add the app method to top-level scope to enable the simplified DSL
def app(name, &block)
  MonadicDSL.app(name, &block)
end

module MonadicDSL
  # Base class for application state management

  # The following setting parameters are available for defining applications:
  #
  # - image: Enables image handling and attachments in the UI
  # - pdf: Enables PDF document upload, parsing, and interaction
  # - easy_submit: Enables submitting messages on Enter key (without needing to click Send)
  # - auto_speech: Enables automatic text-to-speech for assistant messages
  # - initiate_from_assistant: Allows assistant to proactively send follow-up messages
  # - mermaid: Enables Mermaid diagram rendering and interaction for flowcharts and diagrams
  # - math: Enables mathematical notation rendering (KaTeX)
  # - abc: Enables ABC music notation rendering and playback for music composition
  # - tools: Defines function-calling capabilities available to the model
  # - image_generation: Enables AI image generation within the conversation
  # - monadic: Enables monadic mode for structured JSON responses and special rendering
  # - websearch: Enables web search functionality for retrieving external information (web_search)
  # - jupyter: Enables access to Jupyter notebooks in the conversation
  # - temperature: Controls randomness in model responses (0.0-2.0)
  # - model: Specifies which AI model to use for this app
  # - group: Groups apps by provider (e.g., "OpenAI", "Anthropic", "Google")
  # - app_name: Defines the display name of the application
  # - description: Provides UI description text for the application
  # - icon: Specifies the FontAwesome icon to use for the app
  # - initial_prompt: Sets the system prompt/instructions for the model
  # - disabled: Indicates if the app should be disabled (e.g., when API key is missing)
  # - reasoning_effort: Controls the depth of reasoning (e.g., "high")
  # - context_size: Controls the context window size for the conversation
  # - max_tokens: Specifies the maximum number of tokens to generate (max_output_tokens)
  #
  # Note: Some parameters support aliases (shown in parentheses) for backward compatibility:
  # - websearch (web_search)
  # - max_tokens (max_output_tokens)

  class AppState
    attr_reader :name
    attr_accessor :settings, :features, :ui, :prompts
    
    def initialize(name)
      @name = name
      @settings = {}
      @features = {}
      @ui = {}
      @prompts = {}
    end
    
    # Bind operation for state transformation

    def bind(&block)
      Result.new(block.call(self))
    rescue StandardError => e
      Result.new(nil, e)
    end
    
    # Map operation for value transformation

    def map(&block)
      bind { |state| self.class.new(block.call(state)) }
    end
    
    # Validate the current state

    def validate!
      raise ValidationError, "Name is required" unless @name
      raise ValidationError, "Settings are required" if @settings.empty?
      raise ValidationError, "Provider is required" unless @settings[:provider]
      true
    end
  end
  
  # Result monad for error handling

  class Result
    attr_reader :value, :error
    
    def initialize(value, error = nil)
      @value = value
      @error = error
    end
    
    def bind(&block)
      return self if @error
      begin
        block.call(@value)
      rescue => e
        Result.new(nil, e)
      end
    end
    
    def map(&block)
      bind { |value| Result.new(block.call(value)) }
    end
    
    def success?
      !@error
    end
  end
  
  
  class ConfigurationError < StandardError; end
  
  # Module methods
  
  # App definition method
  def self.app(name, &block)
    state = AppState.new(name.gsub(/\s+/, ''))
    # Always store original name as display_name to ensure consistency
    state.settings[:display_name] = name
    
    # Initialize default values
    state.features = {}
    state.settings[:provider] = "OpenAI"
    # model is NOT pre-set here; convert_to_class resolves it per-provider
    # via providerDefaults (SSOT) or ENV variable
    state.settings[:temperature] = 0.7
    
    # Process the DSL block
    app_def = SimplifiedAppDefinition.new(state)
    app_def.instance_eval(&block)
    
    # Debug the state
    puts "After DSL eval: #{state.name}, display_name: #{state.settings[:display_name]}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
    
    convert_to_class(state)
    state
  end
  
  # Simplified app definition class
  class SimplifiedAppDefinition
    def initialize(state)
      @state = state
    end
    
    def description(text = nil, &block)
      if block_given?
        # Multi-language description using block syntax
        desc_builder = DescriptionBuilder.new
        desc_builder.instance_eval(&block)
        @state.ui[:description] = desc_builder.descriptions
      else
        # Single string description (backward compatibility)
        @state.ui[:description] = text
      end
    end
    
    def icon(name)
      @state.ui[:icon] = IconHelper.to_html(name)
    end
    
    def app_name(name)
      @state.settings[:app_name] = name
    end
    
    def display_name(name)
      @state.settings[:display_name] = name
    end
    
    def system_prompt(text)
      @state.prompts[:initial] = text
    end
    
    # Module include support
    def include_modules(*modules)
      @state.settings[:include_modules] = modules.map(&:to_s)
    end
    
    # Monadic mode for structured output
    def monadic(value)
      @state.features[:monadic] = value
    end
    
    # Assistant initiation flag
    def initiate_from_assistant(value)
      @state.features[:initiate_from_assistant] = value
    end
    
    def llm(&block)
      LLMConfiguration.new(@state).instance_eval(&block)
    end
    
    def features(&block)
      SimplifiedFeatureConfiguration.new(@state).instance_eval(&block)
    end
    
    def context_management(&block)
      if block_given?
        config = ContextManagementConfiguration.new
        config.instance_eval(&block)
        @state.settings[:context_management] = config.to_hash
      end
    end

    def tools(tools_array = nil, &block)
      if tools_array
        # Direct array of tools provided (e.g., for Gemini/OpenAI style)
        @state.settings[:tools] = tools_array
      elsif block_given?
        # Convert provider to symbol
        provider = @state.settings[:provider].to_s.downcase.to_sym

        tool_config = ToolConfiguration.new(@state, provider)
        tool_config.instance_eval(&block)

        @state.settings[:tools] = tool_config.to_h
      end
    end

    def agents(&block)
      if block_given?
        config = AppAgentsConfiguration.new
        config.instance_eval(&block)
        @state.settings[:agents] = config.to_hash
      end
    end

    # Context schema for monadic apps
    # Defines what context fields should be tracked automatically
    # @example
    #   context_schema do
    #     field :topics, icon: "fa-tags", label: "Topics", description: "Main subjects"
    #     field :people, icon: "fa-users", label: "People", description: "Names mentioned"
    #     field :notes, icon: "fa-sticky-note", label: "Notes", description: "Important facts"
    #   end
    def context_schema(&block)
      if block_given?
        config = ContextSchemaConfiguration.new
        config.instance_eval(&block)
        @state.settings[:context_schema] = config.to_hash
      end
    end

    # Import shared tools at app level (delegates to ToolConfiguration)
    # This allows import_shared_tools to be called outside of tools {} block
    # Uses a persistent ToolConfiguration to accumulate tools across multiple calls
    def import_shared_tools(*groups, **options)
      provider = @state.settings[:provider].to_s.downcase.to_sym
      @tool_config ||= ToolConfiguration.new(@state, provider)

      @tool_config.import_shared_tools(*groups, **options)

      @state.settings[:tools] = @tool_config.to_h
    end
  end

  # Helper method to convert simplified state to class
  def self.convert_to_class(state)
    # Get standardized provider configuration
    provider_config = ProviderConfig.new(state.settings[:provider])
    helper_module = provider_config.helper_module
    
    # Build fallback model list using configured models, providerDefaults, and defaults
    fallback_models = []
    fallback_models.concat(Array(state.settings[:models])) if state.settings[:models]
    fallback_models << state.settings[:model] if state.settings[:model]
    # Add providerDefaults chat list as additional fallback
    pd_models = Monadic::Utils::ModelSpec.get_provider_models(provider_config.standard_key, "chat")
    fallback_models.concat(pd_models) if pd_models
    fallback_models = fallback_models.flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?).uniq
    fallback_literal = if fallback_models.empty?
      "[]"
    else
      "[#{fallback_models.map { |m| m.inspect }.join(', ')}]"
    end

    # Get model list via helper module with centralized fallback handling
    model_list_code = "Monadic::Utils::ProviderModelCache.fetch('#{provider_config.standard_key}', fallback: #{fallback_literal}) do\n        defined?(#{helper_module}) ? Array(#{helper_module}.list_models) : []\n      end"

    # Debug the state
    puts "Converting class: #{state.name}, app_name: #{state.settings[:app_name]}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]

    # Make sure app_name is set from either settings or features
    app_name = state.settings[:app_name] || state.name
    
    # Use display_name if provided, otherwise use app_name
    display_name = state.settings[:display_name] || app_name

    # Get distributed mode from CONFIG hash (loaded from .env file) instead of environment variable
    distributed_mode = defined?(CONFIG) && CONFIG["DISTRIBUTED_MODE"] ? CONFIG["DISTRIBUTED_MODE"] : "off"
    
    # Check if this app should be disabled in server mode due to security concerns
    jupyter_disabled_in_server = distributed_mode == "server" &&
      (state.features[:jupyter] == true ||
       state.features[:jupyter] == "true")
    
    # Get appropriate environment variable name based on provider
    provider_name = state.settings[:provider].to_s.downcase
    provider_env_var = provider_config.default_model_env

    # Determine model value for class definition
    # Priority: MDSL explicit model > ENV > providerDefaults (SSOT) > hardcoded
    model_value = if state.settings[:model]
                    # Use model from MDSL file if specified
                    state.settings[:model].inspect
                  elsif provider_env_var
                    # Resolve default: providerDefaults (SSOT) > ENV variable
                    default_model = Monadic::Utils::ModelSpec.get_provider_default(provider_config.standard_key, "chat")
                    if default_model.nil?
                      warn "[DSL] No providerDefault for #{provider_config.standard_key}/chat; relying on ENV['#{provider_env_var}']"
                    end
                    "ENV['#{provider_env_var}'] || #{default_model.inspect}"
                  else
                    # Fallback to providerDefaults (providers without ENV variable, e.g. Ollama)
                    pd_default = Monadic::Utils::ModelSpec.get_provider_default(provider_config.standard_key, "chat")
                    if pd_default.nil?
                      warn "[DSL] No providerDefault for #{provider_config.standard_key}/chat and no ENV variable configured"
                    end
                    pd_default.inspect
                  end

    # Construct disabled logic based on API key availability and server mode restrictions
    if provider_config.api_key_name.nil?
      # For providers that don't need API keys (like Ollama)
      # Check if provider has an endpoint availability method (e.g., OllamaHelper.find_endpoint)
      ollama_check = provider_name == "ollama" ? "(defined?(OllamaHelper) && OllamaHelper.find_endpoint.nil?)" : "false"
      if jupyter_disabled_in_server
        disabled_condition = "(defined?(CONFIG) && CONFIG[\"DISTRIBUTED_MODE\"] == \"server\") || #{ollama_check}"
      else
        disabled_condition = ollama_check
      end
    elsif jupyter_disabled_in_server
      disabled_condition = "!defined?(CONFIG) || !CONFIG[\"#{provider_config.api_key_name}\"] || (defined?(CONFIG) && CONFIG[\"DISTRIBUTED_MODE\"] == \"server\")"
    else
      disabled_condition = "!defined?(CONFIG) || !CONFIG[\"#{provider_config.api_key_name}\"]"
    end

    # Add extra modules if specified
    include_modules = state.settings[:include_modules] || []
    include_statements = [helper_module]

    # Automatically include tool module if it exists
    # Remove provider suffix to get base app name
    app_base_name = state.name.sub(/OpenAI|Claude|Gemini|Mistral|Cohere|Perplexity|Grok|DeepSeek|Ollama$/, '')
    tool_module_name = "#{app_base_name}Tools"
    include_statements << tool_module_name

    include_statements += include_modules

    # Include shared tool modules for imported tool groups
    # This ensures the Ruby methods are available when AI calls the tools
    if state.settings[:imported_tool_groups]
      state.settings[:imported_tool_groups].each do |group_info|
        group_name = group_info[:name]
        module_name = MonadicSharedTools::Registry.module_name_for(group_name)
        if module_name
          include_statements << module_name
        end
      end
    end

    include_lines = include_statements.map { |m| "        include #{m} if defined?(#{m})" }.join("\n")
    
    # Use group from features if defined, otherwise use provider's display_group
    group_value = state.features[:group] || provider_config.display_group
    
    # Use models from state if specified, otherwise use provider's model list
    # When neither MDSL model nor models is set, inject providerDefaults into settings
    # so the fallback list is richer for the ProviderModelCache
    if !state.settings[:models]
      pd_chat = Monadic::Utils::ModelSpec.get_provider_models(provider_config.standard_key, "chat")
      if pd_chat && !pd_chat.empty?
        state.settings[:models] = pd_chat
      end
    end

    models_value = if state.settings[:models]
                     state.settings[:models].inspect
                   else
                     model_list_code
                   end
    
    class_def = <<~RUBY
      class #{state.name} < MonadicApp
#{include_lines}

        icon = #{state.ui[:icon].inspect}
        description = #{state.ui[:description].inspect}
        initial_prompt = #{state.prompts[:initial].inspect}

        @settings = {
          provider: #{state.settings[:provider].inspect},
          group: #{group_value.inspect},
          disabled: #{disabled_condition},
          models: #{models_value},
          model: #{model_value},
          temperature: #{state.settings[:temperature]},
          initial_prompt: initial_prompt,
          app_name: #{app_name.inspect},
          display_name: #{display_name.inspect},
          description: description,
          icon: icon,
        }
    RUBY

    # Add feature settings (excluding group which was already set)
    state.features.each do |feature, value|
      next if feature == :group  # Skip group as it's already set above
      class_def << "        @settings[:#{feature}] = #{value.inspect}\n"
    end
    
    # Add max_tokens if specified
    if state.settings[:max_tokens]
      class_def << "        @settings[:max_tokens] = #{state.settings[:max_tokens].inspect}\n"
    end
    
    # Default reasoning_effort to "none" (thinking disabled) unless the app
    # explicitly opts in. This prevents unexpected thinking token generation
    # and tool call loops. Apps that benefit from reasoning should declare
    # reasoning_effort "low"/"medium"/"high" in their MDSL llm block.
    effort = state.settings[:reasoning_effort] || "none"
    class_def << "        @settings[:reasoning_effort] = #{effort.inspect}\n"
    
    
    # Add tools if specified
    if state.settings[:tools]
      class_def << "        @settings[:tools] = #{state.settings[:tools].inspect}\n"
    end

    if state.settings[:progressive_tools]
      class_def << "        @settings[:progressive_tools] = #{state.settings[:progressive_tools].inspect}\n"
    end

    # Add imported_tool_groups if specified
    if state.settings[:imported_tool_groups]
      class_def << "        @settings[:imported_tool_groups] = #{state.settings[:imported_tool_groups].inspect}\n"
    end

    # Build and add badges
    begin
      require_relative "utils/badge_builder"

      # IMPORTANT: BadgeBuilder expects features as a nested hash
      # but DSL stores them flat in settings. Create a temporary hash with features nested.
      badge_settings = state.settings.dup
      badge_settings[:features] = state.features

      all_badges = Monadic::Utils::BadgeBuilder.build_all_badges(badge_settings)

      # Validate structure before serializing
      unless all_badges.is_a?(Hash) && all_badges[:tools].is_a?(Array) && all_badges[:capabilities].is_a?(Array)
        STDERR.puts "[BadgeBuilder] Invalid badge structure for #{state.name}, using empty badges"
        all_badges = { tools: [], capabilities: [] }
      end

      badges_json = all_badges.to_json
      class_def << "        @settings[:all_badges] = #{badges_json.inspect}\n"
    rescue StandardError => e
      STDERR.puts "[BadgeBuilder] Failed to build badges for #{state.name}: #{e.message}"
      STDERR.puts e.backtrace.first(5).join("\n") if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      # Fail gracefully - empty badges instead of crashing app load
      class_def << "        @settings[:all_badges] = #{({ tools: [], capabilities: [] }.to_json).inspect}\n"
    end

    # Add tool_choice if specified
    if state.settings[:tool_choice]
      class_def << "        @settings[:tool_choice] = #{state.settings[:tool_choice].inspect}\n"
    end
    
    # Add parallel_function_calling if specified
    if state.settings[:parallel_function_calling]
      class_def << "        @settings[:parallel_function_calling] = #{state.settings[:parallel_function_calling].inspect}\n"
    end

    # Add betas if specified
    if state.settings[:betas]
      class_def << "        @settings[:betas] = #{state.settings[:betas].inspect}\n"
    end

    # Add agents if specified (internal sub-agents like code_generator, speech_to_text)
    if state.settings[:agents] && !state.settings[:agents].empty?
      class_def << "        @settings[:agents] = #{state.settings[:agents].inspect}\n"
    end

    # Add context_schema if specified (for monadic apps)
    if state.settings[:context_schema]
      class_def << "        @settings[:context_schema] = #{state.settings[:context_schema].inspect}\n"
    end

    class_def << "      end\n"

    eval(class_def, TOPLEVEL_BINDING, state.name)
  end

  # Utility method for state conversion to YAML
  def self.to_yaml(app_state)
    {
      name: app_state.name,
      settings: app_state.settings,
      features: app_state.features,
      ui: app_state.ui,
      prompts: app_state.prompts
    }.to_yaml
  end
end
