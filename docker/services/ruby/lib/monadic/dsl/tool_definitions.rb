# frozen_string_literal: true

require_relative 'tool_formatters'

module MonadicDSL
  # Custom error classes
  class ValidationError < StandardError; end

  # Base class for tool definitions with provider-specific validation

  class ToolDefinition
    attr_reader :name,
                :description,
                :parameters,
                :required,
                :enum_values,
                :unlock_conditions

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
      raise ValidationError, "Invalid tool format for Gemini" unless valid_for_gemini?
    end

    def validate_openai_requirements
      raise ValidationError, "Invalid tool format for OpenAI" unless valid_for_openai?
    end

    def validate_anthropic_requirements
      raise ValidationError, "Invalid tool format for Anthropic" unless valid_for_anthropic?
    end

    def validate_cohere_requirements
      raise ValidationError, "Invalid tool format for Cohere" unless valid_for_cohere?
    end

    def validate_mistral_requirements
      raise ValidationError, "Invalid tool format for Mistral" unless valid_for_mistral?
    end

    def validate_deepseek_requirements
      raise ValidationError, "Invalid tool format for DeepSeek" unless valid_for_deepseek?
    end

    def validate_perplexity_requirements
      raise ValidationError, "Invalid tool format for Perplexity" unless valid_for_perplexity?
    end

    def validate_grok_requirements
      raise ValidationError, "Invalid tool format for Grok" unless valid_for_grok?
    end

    def valid_for_openai? = true
    def valid_for_grok? = true
    def valid_for_perplexity? = true
    def valid_for_gemini? = true
    def valid_for_anthropic? = true
    def valid_for_cohere? = true
    def valid_for_mistral? = true
    def valid_for_deepseek? = true
  end

  # Tool configuration DSL with provider-specific handling

  class ToolConfiguration
    FORMATTERS = {
      openai: ToolFormatters::OpenAIFormatter,
      anthropic: ToolFormatters::ClaudeFormatter,
      claude: ToolFormatters::ClaudeFormatter,
      cohere: ToolFormatters::CohereFormatter,
      gemini: ToolFormatters::GeminiFormatter,
      mistral: ToolFormatters::MistralFormatter,
      deepseek: ToolFormatters::DeepSeekFormatter,
      perplexity: ToolFormatters::PerplexityFormatter,
      xai: ToolFormatters::GrokFormatter,
      grok: ToolFormatters::GrokFormatter,
      ollama: ToolFormatters::OpenAIFormatter
    }.freeze

    PROVIDER_WRAPPERS = {
      gemini: ->(tools) { { "function_declarations" => tools } },
      default: ->(tools) { tools }
    }.freeze

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

      if @tools.any?
        @state.settings[:progressive_tools] ||= {}
        @state.settings[:progressive_tools][:provider] = @provider
        @state.settings[:progressive_tools][:all_tool_names] = @tools.map(&:name)
        @state.settings[:progressive_tools][:always_visible] = @tools.select { |t| t.visibility == :always }.map(&:name)
      end

      if conditional_metadata.any?
        @state.settings[:progressive_tools][:conditional] = conditional_metadata
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
        @state.settings[:anthropic_specific] = {}
      when :cohere
        @state.settings[:cohere_specific] = {}
      when :mistral
        @state.settings[:mistral_specific] = {}
      when :deepseek
        @state.settings[:deepseek_specific] = {}
      when :perplexity
        @state.settings[:perplexity_specific] = {}
      when :xai
        @state.settings[:xai_specific] = {}
      end
    end

    # Import shared tool groups with specified visibility
    #
    # @param groups [Array<Symbol>] Tool group names (e.g., :file_operations, :web_search_tools)
    # @param visibility [String] Visibility type: "always", "conditional", or "initial" (default: "conditional")
    # @param options [Hash] Additional options
    # @option options [String] :unlock_hint Custom unlock hint (overrides default)
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
              parameter param[:name], param[:type], param[:description], required: param[:required], items: param[:items]
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

        # Ensure request_tool is defined if any conditional tools exist
        ensure_request_tool_defined if visibility == "conditional"
      end
    end

    private

    # Ensure request_tool is defined for PTD
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
end
