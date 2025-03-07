# Add required utilities
require_relative 'utils/fa_icons'

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
  # - mathjax: Enables mathematical notation rendering using MathJax library
  # - abc: Enables ABC music notation rendering and playback for music composition
  # - sourcecode: Enables enhanced source code highlighting and formatting (code_highlight)
  # - toggle: Controls collapsible sections for code blocks and other content
  # - tools: Defines function-calling capabilities available to the model
  # - image_generation: Enables AI image generation within the conversation
  # - monadic: Enables monadic mode for structured JSON responses and special rendering
  # - websearch: Enables web search functionality for retrieving external information (web_search)
  # - jupyter_access: Enables access to Jupyter notebooks in the conversation (jupyter)
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
  # - sourcecode (code_highlight)
  # - websearch (web_search)
  # - jupyter (jupyter_access)
  # - max_tokens (max_output_tokens)

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
      @content.match?(/^app\s+["']/) ||
        File.extname(@file) == '.mdsl'
    end
    
    def load_dsl
      # Only handle the simplified DSL format
      app_state = eval(@content, TOPLEVEL_BINDING, @file)
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
  end

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
  
  # These configuration classes were for the old DSL format
  # and have been removed since we're using only the simplified format
  
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

  # No longer needed - removed the old AppDefinition class as we're 
  # focusing on the simplified DSL format

  # Custom error classes

  class ValidationError < StandardError; end
  class ConfigurationError < StandardError; end
  
  # Module methods
  
  # App definition method
  def self.app(name, &block)
    state = AppState.new(name.gsub(/\s+/, ''))
    # Store original name as app_name if it contains spaces
    state.settings[:app_name] = name if name.include?(' ')
    
    # Initialize default values
    state.features = {}
    state.settings[:provider] = "OpenAI"
    state.settings[:model] = "gpt-4o"
    state.settings[:temperature] = 0.7
    
    SimplifiedAppDefinition.new(state).instance_eval(&block)
    
    convert_to_class(state)
    state
  end
  
  # Simplified app definition class
  class SimplifiedAppDefinition
    def initialize(state)
      @state = state
    end
    
    def description(text)
      @state.ui[:description] = text
    end
    
    def icon(name)
      @state.ui[:icon] = IconHelper.to_html(name)
    end
    
    def system_prompt(text)
      @state.prompts[:initial] = text
    end
    
    def llm(&block)
      LLMConfiguration.new(@state).instance_eval(&block)
    end
    
    def features(&block)
      SimplifiedFeatureConfiguration.new(@state).instance_eval(&block)
    end
    
    def tools(&block)
      # Convert provider to symbol
      provider = @state.settings[:provider].to_s.downcase.to_sym
      
      tool_config = ToolConfiguration.new(@state, provider)
      tool_config.instance_eval(&block) if block_given?
      @state.settings[:tools] = tool_config.to_h
    end
  end
  
  # LLM Configuration for simplified syntax
  class LLMConfiguration
    # Map newer parameter names to standard ones
    PARAMETER_MAP = {
      max_output_tokens: :max_tokens
    }
    
    def initialize(state)
      @state = state
    end
    
    def provider(value)
      @state.settings[:provider] = value
    end
    
    def model(value)
      @state.settings[:model] = value
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
  
  # Simplified Feature Configuration
  class SimplifiedFeatureConfiguration
    # Map newer feature names to old ones where needed
    FEATURE_MAP = {
      code_highlight: :sourcecode,
      web_search: :websearch,
      jupyter_access: :jupyter
    }
    
    def initialize(state)
      @state = state
    end
    
    def method_missing(method_name, *args)
      # Default all called methods to true, handle special cases
      value = args.first.nil? ? true : args.first
      
      feature_name = FEATURE_MAP[method_name] || method_name
      @state.features[feature_name] = value
    end
    
    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end

  # Helper method to convert simplified state to class
  def self.convert_to_class(state)
    # Determine the appropriate helper module based on the provider
    provider_str = state.settings[:provider].to_s.downcase.gsub(/[\s\-]+/, "")
    
    helper_module = case provider_str
                   when "anthropic", "claude", "anthropicclaude"
                     'ClaudeHelper'
                   when "gemini", "google", "googlegemini"
                     'GeminiHelper'
                   when "cohere", "commandr", "coherecommandr"
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

    class_def = <<~RUBY
      class #{state.name} < MonadicApp
        include #{helper_module} if defined?(#{helper_module})

        icon = #{state.ui[:icon].inspect}
        description = #{state.ui[:description].inspect}
        initial_prompt = #{state.prompts[:initial].inspect}

        @settings = {
          group: #{state.settings[:provider].to_s.capitalize.inspect},
          disabled: !defined?(CONFIG) || !CONFIG["#{state.settings[:provider].to_s.upcase}_API_KEY"],
          models: defined?(#{helper_module}) ? #{helper_module}.list_models : [],
          model: #{state.settings[:model].inspect},
          temperature: #{state.settings[:temperature]},
          initial_prompt: initial_prompt,
          app_name: #{(state.settings[:app_name] || state.name).inspect},
          description: description,
          icon: icon
        }
    RUBY

    # Add feature settings
    state.features.each do |feature, value|
      class_def << "        @settings[:#{feature}] = #{value.inspect}\n"
    end
    
    # Add max_tokens if specified
    if state.settings[:max_tokens]
      class_def << "        @settings[:max_tokens] = #{state.settings[:max_tokens].inspect}\n"
    end
    
    # Add tools if specified
    if state.settings[:tools]
      class_def << "        @settings[:tools] = #{state.settings[:tools].inspect}\n"
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