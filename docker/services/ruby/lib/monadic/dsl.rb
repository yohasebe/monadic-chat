# Add required utilities
require_relative 'utils/fa_icons'
require_relative 'utils/mdsl_validator' rescue nil
require_relative 'utils/provider_model_cache'
require_relative 'shared_tools/registry'
require_relative 'shared_tools/file_operations'
require_relative 'shared_tools/python_execution'
require_relative 'shared_tools/web_search_tools'
require_relative 'shared_tools/app_creation'
require_relative 'shared_tools/file_reading'
require_relative 'shared_tools/jupyter_operations'
require_relative 'shared_tools/web_automation'
require_relative 'shared_tools/content_analysis_openai'

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
      
      # Validate MDSL configuration if validator is available
      if defined?(Monadic::Utils::MDSLValidator) && app_state
        begin
          provider = determine_provider(app_state)
          model = app_state.settings[:model] || app_state.settings[:models]&.first

          if provider && model
            validation_result = Monadic::Utils::MDSLValidator.validate_reasoning_parameters(
              app_state.settings,
              provider,
              model
            )
            
            # Log errors and warnings
            validation_result[:errors].each do |error|
              warn "MDSL Validation Error in #{@file}: #{error}"
            end
            validation_result[:warnings].each do |warning|
              warn "MDSL Validation Warning in #{@file}: #{warning}"
            end
          end
        rescue => e
          warn "MDSL Validation failed for #{@file}: #{e.message}"
        end
      end
      
      # After creating the class from MDSL, check for and load corresponding files
      base_name = File.basename(@file, '.*')
      dir_path = File.dirname(@file)
      
      # Remove provider suffix (e.g., _openai, _claude) to get base app name
      app_base_name = base_name.sub(/_\w+$/, '')
      
      # Load constants file if it exists
      constants_file = File.join(dir_path, "#{app_base_name}_constants.rb")
      if File.exist?(constants_file)
        require constants_file
      end
      
      # Load tools file if it exists
      tools_file = File.join(dir_path, "#{app_base_name}_tools.rb")
      if File.exist?(tools_file)
        require tools_file
      end
      
      app_state
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
    
    def determine_provider(app_state)
      # Determine provider from app_state
      if app_state.respond_to?(:settings)
        provider = app_state.settings[:provider]
        return provider if provider
        
        # Try to infer from group
        group = app_state.settings[:group] if app_state.respond_to?(:settings)
        case group
        when /OpenAI/i then 'OpenAI'
        when /Anthropic|Claude/i then 'Anthropic'
        when /Google|Gemini/i then 'Google'
        when /xAI|Grok/i then 'xAI'
        when /DeepSeek/i then 'DeepSeek'
        when /Perplexity/i then 'Perplexity'
        when /Mistral/i then 'Mistral'
        when /Cohere/i then 'Cohere'
        end
      end
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
  
  
  # Base class for tool definitions with provider-specific validation

  class ToolDefinition
    attr_reader :name,
                :description,
                :parameters,
                :required,
                :enum_values,
                :visibility,
                :unlock_conditions,
                :unlock_hint
    
    def initialize(name, description)
      @name = name
      @description = description
      @parameters = {}
      @required = []
      @enum_values = {}
      @visibility = :always
      @unlock_conditions = []
      @unlock_hint = nil
    end

    # Define a parameter with optional enum values and array items

    def parameter(name, type, description, required: false, enum: nil, items: nil)
      @parameters[name] = {
        type: type,
        description: description
      }
      @parameters[name][:items] = items if items
      @enum_values[name] = enum if enum
      @required << name if required
      self
    end

    # Configure tool visibility (e.g., :always, :conditional)

    def visibility(value = nil)
      return @visibility if value.nil?

      normalized = value.to_sym
      unless [:always, :conditional, :hidden].include?(normalized)
        raise ArgumentError, "Unsupported visibility: #{value.inspect}"
      end
      @visibility = normalized
      self
    end

    # Add unlock conditions used for progressive disclosure

    def unlock_when(condition = nil, **kwargs)
      condition_hash =
        if condition.is_a?(Hash) && !condition.empty?
          condition
        elsif kwargs.any?
          kwargs
        else
          raise ArgumentError, "unlock_when requires at least one condition"
        end

      @unlock_conditions << condition_hash.transform_keys(&:to_sym)
      self
    end

    # Optional hint shown when suggesting a tool unlock

    def unlock_hint(text = nil)
      return @unlock_hint if text.nil?

      @unlock_hint = text
      self
    end

    alias unlock_recommendation unlock_hint
    
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
          
          # Add items property for array types (required by OpenAI)
          if param[:type] == "array"
            props[name][:items] = param[:items] || { type: "object" }
          end
          
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
        properties = {}
        tool.parameters.each do |name, param|
          properties[name] = {
            type: param[:type],
            description: param[:description]
          }
          properties[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        properties
      end
    end
    
    class GeminiFormatter
      def format(tool)
        {
          "name" => tool.name,
          "description" => tool.description,
          "parameters" => {
            "type" => "object",
            "properties" => format_properties(tool),
            "required" => tool.required.map(&:to_s)
          }
        }
      end

      private

      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name.to_s] = {
            "type" => param[:type],
            "description" => param[:description]
          }

          # Add items property for array types (required by Gemini)
          if param[:type] == "array"
            props[name.to_s]["items"] = param[:items] || { "type" => "object" }
          end

          # Gemini-specific enum handling
          if tool.enum_values[name]
            props[name.to_s]["enum"] = tool.enum_values[name]
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
          
          # Add items property for array types (required by OpenAI-compatible APIs)
          if param[:type] == "array"
            props[name][:items] = param[:items] || { type: "object" }
          end
          
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
      claude: ToolFormatters::AnthropicFormatter,
      cohere: ToolFormatters::CohereFormatter,
      gemini: ToolFormatters::GeminiFormatter,
      mistral: ToolFormatters::MistralFormatter,
      deepseek: ToolFormatters::DeepSeekFormatter,
      perplexity: ToolFormatters::PerplexityFormatter,
      xai: ToolFormatters::GrokFormatter,
      grok: ToolFormatters::GrokFormatter,
      ollama: ToolFormatters::OpenAIFormatter
    }
    
    PROVIDER_WRAPPERS = {
      gemini: ->(tools) { { "function_declarations" => tools } },
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
      conditional_metadata = []
      formatted_tools = @tools.map do |tool|
        formatted = @formatter.format(tool)

        if tool.visibility != :always
          conditional_metadata << {
            name: tool.name,
            description: tool.description,
            visibility: tool.visibility,
            unlock_conditions: tool.unlock_conditions,
            unlock_hint: tool.unlock_hint,
            parameters: tool.parameters,
            required: tool.required,
            enum_values: tool.enum_values,
            formatted: formatted
          }
        end

        formatted
      end

      if conditional_metadata.any?
        @state.settings[:progressive_tools] ||= {}
        @state.settings[:progressive_tools][:provider] = @provider
        @state.settings[:progressive_tools][:conditional] = conditional_metadata
        @state.settings[:progressive_tools][:always_visible] = @tools.select { |t| t.visibility == :always }.map(&:name)
        @state.settings[:progressive_tools][:all_tool_names] = @tools.map(&:name)
      end

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

    # Import shared tool groups with specified visibility
    #
    # This method allows apps to import common tool groups (e.g., :file_operations)
    # and specify whether they should be always visible or managed by PTD.
    #
    # @param groups [Array<Symbol>] Tool group names (e.g., :file_operations, :web_search_tools)
    # @param visibility [String] Visibility type: "always", "conditional", or "initial" (default: "conditional")
    # @param options [Hash] Additional options
    # @option options [String] :unlock_hint Custom unlock hint (overrides default)
    # @example Same visibility for multiple groups
    #   import_shared_tools :file_operations, :python_execution, visibility: "conditional"
    # @example Single group, always visible
    #   import_shared_tools :file_operations, visibility: "always"
    # @example Custom unlock hint
    #   import_shared_tools :web_search_tools, visibility: "conditional", unlock_hint: "Call request_tool..."
    def import_shared_tools(*groups, visibility: "conditional", **options)
      # Track imported tool groups for UI display
      @state.settings[:imported_tool_groups] ||= []

      groups.each do |group|
        # Validate group exists
        unless MonadicSharedTools::Registry.group_exists?(group)
          raise ArgumentError, "Unknown tool group: #{group}. Available: #{MonadicSharedTools::Registry.available_groups.join(', ')}"
        end

        # Get tool specifications from registry
        tool_specs = MonadicSharedTools::Registry.tools_for(group)

        # Define each tool in the group and count actually added tools
        added_tool_count = 0
        tool_specs.each do |spec|
          # Check if tool is already defined (prevent duplicates across groups)
          existing_tool = @tools.find { |t| t.name == spec.name }
          if existing_tool
            if CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[DSL Warning] Tool '#{spec.name}' from group '#{group}' is already defined. Skipping duplicate."
            end
            next
          end

          define_tool spec.name, spec.description do
            # Add parameters
            spec.parameters.each do |param|
              parameter param[:name], param[:type], param[:description], required: param[:required]
            end

            # Set visibility
            visibility visibility

            # Add PTD configuration for conditional tools
            if visibility == "conditional"
              unlock_when tool_request: group.to_s
              unlock_hint options[:unlock_hint] || MonadicSharedTools::Registry.default_hint_for(group)
            end
          end

          added_tool_count += 1
        end

        # Record tool group metadata for UI (with actual count of added tools)
        metadata = {
          name: group,
          visibility: visibility,
          tool_count: added_tool_count
        }
        @state.settings[:imported_tool_groups] << metadata

        # Debug logging (unconditional to verify execution)
        STDERR.puts "[DEBUG DSL] Imported tool group: #{metadata.inspect}"
        STDERR.puts "[DEBUG DSL] Settings keys: #{@state.settings.keys.inspect}"
        STDERR.puts "[DEBUG DSL] Total groups: #{@state.settings[:imported_tool_groups].length}"

        # Ensure request_tool is defined if any conditional tools exist
        ensure_request_tool_defined if visibility == "conditional"
      end
    end

    private

    # Ensure request_tool is defined for PTD
    # This method checks if request_tool already exists and adds it if not
    def ensure_request_tool_defined
      return if @tools.any? { |t| t.name == "request_tool" }

      define_tool "request_tool", "Request access to a locked tool by name" do
        parameter :tool_name, "string", "Name of the tool to unlock", required: true
        visibility "always"
      end
    end
    
    def default_safety_settings
      {
        harassment: "block_none",
        hate_speech: "block_none",
        sexually_explicit: "block_none",
        dangerous_content: "block_none"
      }
    end
  end


  # Custom error classes

  class ValidationError < StandardError; end
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
    state.settings[:model] = "gpt-4.1"
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

    # Import shared tools at app level (delegates to ToolConfiguration)
    # This allows import_shared_tools to be called outside of tools {} block
    def import_shared_tools(*groups, **options)
      # Get current provider
      provider = @state.settings[:provider].to_s.downcase.to_sym

      # Create or get existing tool configuration
      tool_config = ToolConfiguration.new(@state, provider)

      # If tools are already defined, we need to merge with existing configuration
      if @state.settings[:tools]
        # Load existing tools into tool_config
        existing_tools = @state.settings[:tools]
        if existing_tools.is_a?(Hash) && existing_tools[:tools]
          tool_config.instance_variable_set(:@tools, existing_tools[:tools])
        end
      end

      # Import the shared tools
      tool_config.import_shared_tools(*groups, **options)

      # Update state with the new configuration
      @state.settings[:tools] = tool_config.to_h
    end
  end

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
    }
    
    def initialize(state)
      @state = state
    end
    
    def provider(value)
      @state.settings[:provider] = value
    end
    
    def model(value = nil)
      provider_name = @state.settings[:provider].to_s.downcase
      provider_env_var = nil

      # Determine the environment variable based on provider
      if provider_name.include?("anthropic") || provider_name.include?("claude")
        provider_env_var = "ANTHROPIC_DEFAULT_MODEL"
      elsif provider_name.include?("openai") || provider_name.include?("gpt")
        provider_env_var = "OPENAI_DEFAULT_MODEL"
      elsif provider_name.include?("cohere") || provider_name.include?("command")
        provider_env_var = "COHERE_DEFAULT_MODEL"
      elsif provider_name.include?("gemini") || provider_name.include?("google")
        provider_env_var = "GEMINI_DEFAULT_MODEL"
      elsif provider_name.include?("mistral")
        provider_env_var = "MISTRAL_DEFAULT_MODEL"
      elsif provider_name.include?("grok") || provider_name.include?("xai")
        provider_env_var = "GROK_DEFAULT_MODEL"
      elsif provider_name.include?("perplexity")
        provider_env_var = "PERPLEXITY_DEFAULT_MODEL"
      elsif provider_name.include?("deepseek")
        provider_env_var = "DEEPSEEK_DEFAULT_MODEL"
      elsif provider_name.include?("ollama")
        provider_env_var = "OLLAMA_DEFAULT_MODEL"
      end

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
      # Support for tool choice configuration
      # Can be "auto", "required", "none", or specific tool object
      @state.settings[:tool_choice] = value
    end
    
    def parallel_function_calling(value)
      # Support for parallel function calling (default: true)
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

  # Provider configuration for standardizing provider-related settings
  class ProviderConfig
    # Provider information mapping
    PROVIDER_INFO = {
      # Anthropic/Claude
      "anthropic" => {
        helper_module: 'ClaudeHelper',
        api_key: 'ANTHROPIC_API_KEY',
        display_group: 'Anthropic',
        aliases: ['claude', 'anthropicclaude']
      },
      # Google/Gemini
      "gemini" => {
        helper_module: 'GeminiHelper',
        api_key: 'GEMINI_API_KEY',
        display_group: 'Google',
        aliases: ['google', 'googlegemini']
      },
      # Cohere
      "cohere" => {
        helper_module: 'CohereHelper',
        api_key: 'COHERE_API_KEY',
        display_group: 'Cohere',
        aliases: ['commandr', 'coherecommandr']
      },
      # Mistral
      "mistral" => {
        helper_module: 'MistralHelper',
        api_key: 'MISTRAL_API_KEY',
        display_group: 'Mistral',
        aliases: ['mistralai']
      },
      # DeepSeek
      "deepseek" => {
        helper_module: 'DeepSeekHelper',
        api_key: 'DEEPSEEK_API_KEY',
        display_group: 'DeepSeek',
        aliases: ['deep seek']
      },
      # Perplexity
      "perplexity" => {
        helper_module: 'PerplexityHelper',
        api_key: 'PERPLEXITY_API_KEY',
        display_group: 'Perplexity',
        aliases: []
      },
      # XAI/Grok
      "xai" => {
        helper_module: 'GrokHelper',
        api_key: 'XAI_API_KEY',
        display_group: 'xAI',
        aliases: ['grok', 'xaigrok']
      },
      # OpenAI (default)
      "openai" => {
        helper_module: 'OpenAIHelper',
        api_key: 'OPENAI_API_KEY',
        display_group: 'OpenAI',
        aliases: []
      },
      # Ollama (local)
      "ollama" => {
        helper_module: 'OllamaHelper',
        api_key: nil,  # Ollama doesn't need an API key
        display_group: 'Ollama',
        aliases: ['local', 'ollama-local']
      }
    }
    
    # Constructor
    def initialize(provider_name)
      @provider_name = provider_name.to_s.downcase.gsub(/[\s\-]+/, "")
      @config = find_provider_config
    end
    
    # Get helper module name
    def helper_module
      @config[:helper_module]
    end
    
    # Get API key environment variable name
    def api_key_name
      @config[:api_key]
    end
    
    # Get display group name
    def display_group
      @config[:display_group]
    end
    
    # Get standard provider key
    def standard_key
      @config[:standard_key] || @provider_name
    end
    
    # Get model list using the appropriate helper
    def model_list
      if Object.const_defined?(@config[:helper_module])
        helper_class = Object.const_get(@config[:helper_module])
        if helper_class.respond_to?(:list_models)
          return helper_class.list_models
        end
      end
      []
    end
    
    private
    
    # Find the provider configuration based on name or aliases
    def find_provider_config
      # Direct match
      PROVIDER_INFO.each do |key, config|
        return config.merge(standard_key: key) if key == @provider_name
      end
      
      # Check aliases
      PROVIDER_INFO.each do |key, config|
        return config.merge(standard_key: key) if config[:aliases].include?(@provider_name)
      end
      
      # Default to OpenAI if no match
      PROVIDER_INFO["openai"]
    end
  end

  # Helper method to convert simplified state to class
  def self.convert_to_class(state)
    # Get standardized provider configuration
    provider_config = ProviderConfig.new(state.settings[:provider])
    helper_module = provider_config.helper_module
    
    # Build fallback model list using configured models and defaults
    fallback_models = []
    fallback_models.concat(Array(state.settings[:models])) if state.settings[:models]
    fallback_models << state.settings[:model] if state.settings[:model]
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
       state.features[:jupyter_access] == true || 
       state.features[:jupyter] == "true" || 
       state.features[:jupyter_access] == "true")
    
    # Get appropriate environment variable name based on provider
    provider_name = state.settings[:provider].to_s.downcase
    provider_env_var = nil
    
    if provider_name.include?("anthropic") || provider_name.include?("claude")
      provider_env_var = "ANTHROPIC_DEFAULT_MODEL"
    elsif provider_name.include?("openai") || provider_name.include?("gpt")
      provider_env_var = "OPENAI_DEFAULT_MODEL"
    elsif provider_name.include?("cohere") || provider_name.include?("command")
      provider_env_var = "COHERE_DEFAULT_MODEL"
    elsif provider_name.include?("gemini") || provider_name.include?("google")
      provider_env_var = "GEMINI_DEFAULT_MODEL"
    elsif provider_name.include?("mistral")
      provider_env_var = "MISTRAL_DEFAULT_MODEL"
    elsif provider_name.include?("grok") || provider_name.include?("xai")
      provider_env_var = "GROK_DEFAULT_MODEL"
    elsif provider_name.include?("perplexity")
      provider_env_var = "PERPLEXITY_DEFAULT_MODEL"
    elsif provider_name.include?("deepseek")
      provider_env_var = "DEEPSEEK_DEFAULT_MODEL"
    elsif provider_name.include?("ollama")
      provider_env_var = "OLLAMA_DEFAULT_MODEL"
    end

    # Determine model value for class definition
    model_value = if state.settings[:model]
                    # Use model from MDSL file if specified
                    state.settings[:model].inspect
                  elsif provider_env_var
                    # Use environment variable with string interpolation in generated code
                    # Include provider-specific default fallback value if no env var
                    default_model = case provider_name
                                    when /anthropic|claude/ then "claude-sonnet-4-5-20250929"
                                    when /openai|gpt/ then "gpt-4.1"
                                    when /cohere|command/ then "command-a-03-2025"
                                    when /gemini|google/ then "gemini-2.0-flash"
                                    when /mistral/ then "mistral-large-latest"
                                    when /grok|xai/ then "grok-2"
                                    when /perplexity/ then "sonar"
                                    when /deepseek/ then "deepseek-chat"
                                    when /ollama/ then "(defined?(OllamaHelper) && OllamaHelper.list_models.first) || 'llama3.2:3b'"
                                    else "gpt-4.1" # Default fallback
                                    end
                    "ENV['#{provider_env_var}'] || #{default_model.inspect}"
                  else
                    # Fallback to default if no model and no environment variable
                    # This shouldn't typically happen due to initialization in app method
                    "\"gpt-4.1\""
                  end

    # Construct disabled logic based on API key availability and server mode restrictions
    if provider_config.api_key_name.nil?
      # For providers that don't need API keys (like Ollama)
      if jupyter_disabled_in_server
        disabled_condition = "(defined?(CONFIG) && CONFIG[\"DISTRIBUTED_MODE\"] == \"server\")"
      else
        disabled_condition = "false"  # Never disabled if no API key needed
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
    include_lines = include_statements.map { |m| "        include #{m} if defined?(#{m})" }.join("\n")
    
    # Use group from features if defined, otherwise use provider's display_group
    group_value = state.features[:group] || provider_config.display_group
    
    # Use models from state if specified, otherwise use provider's model list
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
    
    # Add reasoning_effort if specified
    if state.settings[:reasoning_effort]
      class_def << "        @settings[:reasoning_effort] = #{state.settings[:reasoning_effort].inspect}\n"
    end
    
    
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
