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
  # - mathjax: Enables mathematical notation rendering using MathJax library
  # - abc: Enables ABC music notation rendering and playback for music composition
  # - sourcecode: Enables enhanced source code highlighting and formatting
  # - toggle: Controls collapsible sections for code blocks and other content
  # - tools: Defines function-calling capabilities available to the model
  # - image_generation: Enables AI image generation within the conversation
  # - monadic: Enables monadic mode for structured JSON responses and special rendering
  # - websearch: Enables web search functionality for retrieving external information
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

class Loader
    def self.load(file)
      new(file).load
    rescue => e
      # Log the error but continue processing
      app_name = File.basename(file, ".*")
      error_message = "Warning: Failed to load app '#{app_name}' (#{file}): #{e.message}"
      warn error_message
      
      # Track failed apps in a global array
      $MONADIC_LOADING_ERRORS ||= []
      $MONADIC_LOADING_ERRORS << { app: app_name, file: file, error: e.message }
      
      nil
    end
    
    def initialize(file)
      @file = file
      begin
        @content = File.read(file)
      rescue => e
        warn "Warning: Could not read #{file}: #{e.message}"
        raise
      end
    end
    
    def load
      if dsl_file?
        begin
          load_dsl
        rescue => e
          warn "Warning: Failed to process DSL in #{@file}: #{e.message}"
          load_traditional
        end
      else
        load_traditional
      end
    end
    
    private
    
    def dsl_file?
      @content.match?(/MonadicDSL\.define_app/) ||
        File.extname(@file) == '.mdsl' ||
        @content.match?(/^#\s*@monadic_dsl:\s*true/)
    end
    
    def load_dsl
      app_state = eval(@content, TOPLEVEL_BINDING, @file)
      convert_to_class(app_state)
    rescue => e
      warn "Warning: Failed to evaluate DSL in #{@file}: #{e.message}"
      raise
    end
    
    def load_traditional
      require @file
    rescue => e
      warn "Warning: Failed to require #{@file}: #{e.message}"
      raise
    end
    
    def convert_to_class(app_state)
      # Determine the appropriate helper module based on the provider

      helper_module = case app_state.settings[:provider].to_s.downcase.gsub(/[\s\-]+/, "")
                     when "anthropic", "claude", "anthropicclaude"
                       'ClaudeHelper'
                     when "gemini", "google", "googlegemini"
                       'GeminiHelper'
                     when "cohere", "commandr", "coherecommandr", 
                       'CommandRHelper'
                     when "mistral", "mistralai"
                       'MistralHelper'
                     when "deepseek", "deep seek"
                       'DeepSeekHelper'
                     when "perplexity"
                       'PerplexityHelper'
                     when "xai", "grok", "xaigrok"
                       'GrokHelper'
                     else
                       'OpenAIHelper'
                     end

      # Generate class definition based on app_state

      class_def = <<~RUBY
        class #{app_state.name} < MonadicApp
          include #{helper_module} if defined?(#{helper_module})

          icon = #{app_state.ui[:icon].inspect}
          description = #{app_state.ui[:description].inspect}
          initial_prompt = #{app_state.prompts[:initial].inspect}

          @settings = {
            group: #{app_state.settings[:provider].to_s.capitalize.inspect},
            disabled: !defined?(CONFIG) || !CONFIG["#{app_state.settings[:provider].to_s.upcase}_API_KEY"],
            models: defined?(#{helper_module}) ? #{helper_module}.list_models : [],
            model: #{app_state.settings[:model].inspect},
            temperature: #{app_state.settings[:temperature]},
            initial_prompt: initial_prompt,
            app_name: #{(app_state.settings[:app_name] || app_state.name).inspect},
            description: description,
            icon: icon,
            initiate_from_assistant: #{app_state.features[:initiate_from_assistant] || false},
            easy_submit: #{app_state.features[:easy_submit] || false},
            auto_speech: #{app_state.features[:auto_speech] || false},
            image: #{app_state.features[:image] || false},
            pdf: #{app_state.features[:pdf] || false},
            mermaid: #{app_state.features[:mermaid] || false},
            mathjax: #{app_state.features[:mathjax] || false},
            abc: #{app_state.features[:abc] || false},
            sourcecode: #{app_state.features[:sourcecode] || false},
            toggle: #{app_state.features[:toggle] || false},
            image_generation: #{app_state.features[:image_generation] || false},
            monadic: #{app_state.features[:monadic] || false},
            websearch: #{app_state.features[:websearch] || false},
            tools: #{app_state.settings[:tools].inspect}
          }
        end
      RUBY

      eval(class_def, TOPLEVEL_BINDING, @file)
    end
  end

  class AppState
    attr_reader :name, :settings, :features, :ui, :prompts
    
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
    rescue => e
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
  
  # Configuration for basic settings

  class Configuration
    def initialize(state)
      @state = state
    end
    
    def use_provider(provider)
      @state.settings[:provider] = provider.to_sym
      self
    end
    
    def use_model(name)
      @state.settings[:model] = name
      self
    end
    
    def with_temperature(value)
      @state.settings[:temperature] = value
      self
    end
    
    def validate_settings
      raise ValidationError, "Provider not specified" unless @state.settings[:provider]
      raise ValidationError, "Model not specified" unless @state.settings[:model]
      self
    end
  end

  # Configuration for features

  class FeatureConfiguration
    # VALID_FEATURES = [
    #   :initiate_from_assistant,
    #   :image,
    #   :easy_submit,
    #   :auto_speech,
    #   :pdf
    # ].freeze

    def initialize(state)
      @state = state
    end

    def enable(feature)
      feature_key = feature.is_a?(String) ? feature.to_sym : feature
      # validate_feature(feature_key)
      @state.features[feature_key] = true
      self
    end

    def disable(feature)
      feature_key = feature.is_a?(String) ? feature.to_sym : feature
      # validate_feature(feature_key)
      @state.features[feature_key] = false
      self
    end

    private

    # def validate_feature(feature)
    #   unless VALID_FEATURES.include?(feature)
    #     raise ValidationError, "Invalid feature: #{feature}. Valid features are: #{VALID_FEATURES.join(', ')}"
    #   end
    # end
  end
  
  # Configuration for UI elements

  class UIConfiguration
    def initialize(state)
      @state = state
    end
    
    def set_icon(icon)
      @state.ui[:icon] = icon
      self
    end
    
    def set_description(text)
      @state.ui[:description] = text
      self
    end
    
    def to_h
      @state.ui
    end
  end
  
  # Configuration for prompts

  class PromptConfiguration
    def initialize(state)
      @state = state
    end
    
    def set_initial_prompt(text)
      @state.prompts[:initial] = text
      self
    end
    
    def set_system_prompt(text)
      @state.prompts[:system] = text
      self
    end
    
    def to_h
      @state.prompts
    end
  end
  
  # Base class for tool definitions with provider-specific validation

  class ToolDefinition
    attr_reader :name, :description, :parameters, :required, :enum_values
    
    def initialize(name, description)
      @name = name
      @description = description
      @parameters = {}
      @required = []
      @enum_values = {}
    end

    # Define a parameter with optional enum values

    def parameter(name, type, description, required: false, enum: nil)
      @parameters[name] = {
        type: type,
        description: description
      }
      @enum_values[name] = enum if enum
      @required << name if required
      self
    end
    
    # Provider-specific validation

    def validate_for_provider(provider)
      case provider
      when :gemini
        validate_gemini_requirements
      when :openai
        validate_openai_requirements
      when :anthropic
        validate_anthropic_requirements
      when :cohere
        validate_cohere_requirements
      when :mistral
        validate_mistral_requirements
      when :deepseek
        validate_deepseek_requirements
      when :perplexity
        validate_perplexity_requirements
      when :xai
        validate_grok_requirements
      end
    end
    
    private
    
    def validate_gemini_requirements
      # Gemini-specific validation

      raise ValidationError, "Invalid tool format for Gemini" unless valid_for_gemini?
    end
    
    def validate_openai_requirements
      # OpenAI-specific validation

      raise ValidationError, "Invalid tool format for OpenAI" unless valid_for_openai?
    end
    
    def validate_anthropic_requirements
      # Anthropic-specific validation

      raise ValidationError, "Invalid tool format for Anthropic" unless valid_for_anthropic?
    end
    
    def validate_cohere_requirements
      # Cohere-specific validation

      raise ValidationError, "Invalid tool format for Cohere" unless valid_for_cohere?
    end
    
    def validate_mistral_requirements
      # Mistral-specific validation

      raise ValidationError, "Invalid tool format for Mistral" unless valid_for_mistral?
    end
    
    def validate_deepseek_requirements
      # DeepSeek-specific validation

      raise ValidationError, "Invalid tool format for DeepSeek" unless valid_for_deepseek?
    end

    def validate_perplexity_requirements
      # Perplexity-specific validation

      raise ValidationError, "Invalid tool format for Perplexity" unless valid_for_perplexity?
    end

    def validate_grok_requirements
      # Grok-specific validation

      raise ValidationError, "Invalid tool format for Grok" unless valid_for_grok?
    end

    def valid_for_openai?
      # Implement OpenAI-specific validation logic

      true
    end
    
    def valid_for_grok?
      # Implement Grok-specific validation logic

      true
    end

    def valid_for_perplexity?
      # Implement Perplexity-specific validation logic

      true
    end


    def valid_for_gemini?
      # Implement Gemini-specific validation logic

      true
    end
    
    def valid_for_anthropic?
      # Implement Anthropic-specific validation logic

      true
    end
    
    def valid_for_cohere?
      # Implement Cohere-specific validation logic

      true
    end
    
    def valid_for_mistral?
      # Implement Mistral-specific validation logic

      true
    end
    
    def valid_for_deepseek?
      # Implement DeepSeek-specific validation logic

      true
    end
  end

  # Provider-specific tool formatters

  module ToolFormatters
    class OpenAIFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required,
              additionalProperties: false
            }
          },
          strict: true
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end

    class AnthropicFormatter
      def format(tool)
        {
          name: tool.name,
          description: tool.description,
          input_schema: {
            type: "object",
            properties: format_properties(tool),
            required: tool.required
          }
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end
    
    class CohereFormatter
      def format(tool)
        {
          name: tool.name,
          description: tool.description,
          parameter_definitions: format_parameters(tool)
        }
      end
      
      private
      
      def format_parameters(tool)
        params = {}
        tool.parameters.each do |name, param|
          params[name] = {
            type: param[:type],
            description: param[:description],
            required: tool.required.include?(name)
          }
          params[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        params
      end
    end
    
    class GeminiFormatter
      def format(tool)
        {
          name: tool.name,
          description: tool.description,
          parameters: {
            type: "object",
            properties: format_properties(tool),
            required: tool.required
          }
        }
      end

      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          # Gemini-specific enum handling

          if tool.enum_values[name]
            props[name][:enum] = tool.enum_values[name]
          end
        end
        props
      end
    end

    class MistralFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required
            }
          }
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end
    
    class DeepSeekFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required
            }
          }
        }
      end

      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end

    class PerplexityFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required
            }
          }
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end

    class GrokFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required,
              additionalProperties: false
            }
          },
          strict: true
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end
  end

  # Tool configuration DSL with provider-specific handling

  class ToolConfiguration
    FORMATTERS = {
      openai: ToolFormatters::OpenAIFormatter,
      anthropic: ToolFormatters::AnthropicFormatter,
      cohere: ToolFormatters::CohereFormatter,
      gemini: ToolFormatters::GeminiFormatter,
      mistral: ToolFormatters::MistralFormatter,
      deepseek: ToolFormatters::DeepSeekFormatter,
      perplexity: ToolFormatters::PerplexityFormatter,
      xai: ToolFormatters::GrokFormatter  # XAIFormatterからGrokFormatterに変更
    }
    
    PROVIDER_WRAPPERS = {
      gemini: ->(tools) { { function_declarations: tools } },
      default: ->(tools) { tools }
    }
    
    def initialize(state, provider)
      @state = state
      @provider = provider
      @tools = []
      @formatter = FORMATTERS[provider].new
    end
    
    # Define a new tool

    def define_tool(name, description, &block)
      tool = ToolDefinition.new(name, description)
      tool.instance_eval(&block) if block_given?
      tool.validate_for_provider(@provider)
      @tools << tool
      tool
    end

    # Convert tools to provider-specific format

    def to_h
      formatted_tools = @tools.map { |t| @formatter.format(t) }
      wrapper = PROVIDER_WRAPPERS[@provider] || PROVIDER_WRAPPERS[:default]
      wrapper.call(formatted_tools)
    end
    
    # Provider-specific settings

    def provider_specific_settings
      case @provider
      when :gemini
        @state.settings[:gemini_specific] = {
          parallel_calling: true,
          safety_settings: default_safety_settings
        }
      when :anthropic
        @state.settings[:anthropic_specific] = {
        }
      when :cohere
        @state.settings[:cohere_specific] = {
        }
      when :mistral
        @state.settings[:mistral_specific] = {
        }
      when :deepseek
        @state.settings[:deepseek_specific] = {
        }
      when :perplexity
        @state.settings[:perplexity_specific] = {
        }
      when :xai
        @state.settings[:xai_specific] = {
        }
      end
    end
    
    private
    
    def default_safety_settings
      {
        harassment: "block_none",
        hate_speech: "block_none",
        sexually_explicit: "block_none",
        dangerous_content: "block_none"
      }
    end
  end

  # Main application definition class

  class AppDefinition
    def self.define(name, &block)
      # Convert spaces to empty string for class name

      class_name = name.gsub(/\s+/, '')
      state = AppState.new(class_name)
      # Store original name as app_name if it contains spaces

      state.settings[:app_name] = name if name.include?(' ')
      new(state).instance_eval(&block)
      state
    end
    
    def initialize(state)
      @state = state
    end
    
    def configure(&block)
      Configuration.new(@state).instance_eval(&block)
    end
    
    def compose_features(&block)
      FeatureConfiguration.new(@state).instance_eval(&block)
    end
    
    def setup_ui(&block)
      UIConfiguration.new(@state).instance_eval(&block)
    end
    
    def compose_prompts(&block)
      PromptConfiguration.new(@state).instance_eval(&block)
    end

    def tools(provider = :openai, &block)
      tool_config = ToolConfiguration.new(@state, provider)
      tool_config.instance_eval(&block)
      @state.settings[:tools] = tool_config.to_h
      @state
    end

    def define_methods(&block)
      @state.settings[:instance_methods] = block
    end
  end

  # Custom error classes

  class ValidationError < StandardError; end
  class ConfigurationError < StandardError; end
  
  # Module methods

  def self.define_app(name, &block)
    AppDefinition.define(name, &block)
  end

  # Utility methods for state conversion

  def self.to_yaml(app_state)
    {
      name: app_state.name,
      settings: app_state.settings,
      features: app_state.features,
      ui: app_state.ui,
      prompts: app_state.prompts
    }.to_yaml
  end
  
  def self.from_yaml(yaml_string)
    config = YAML.safe_load(yaml_string)
    define_app(config["name"]) do
      configure do
        use_provider config["settings"]["provider"]
        use_model config["settings"]["model"]
        with_temperature config["settings"]["temperature"]
      end
      
      compose_features do
        config["features"].each do |feature, enabled|
          enabled ? enable(feature) : disable(feature)
        end
      end
      
      setup_ui do
        set_icon config["ui"]["icon"]
        set_description config["ui"]["description"]
      end
      
      compose_prompts do
        set_initial_prompt config["prompts"]["initial"]
        set_system_prompt config["prompts"]["system"] if config["prompts"]["system"]
      end
    end
  end
end
