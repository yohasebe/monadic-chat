# frozen_string_literal: true

# Provider-specific tool formatters for converting MDSL tool definitions
# into the JSON format required by each AI provider's API.

module MonadicDSL
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

    # ClaudeFormatter for Anthropic Claude API
    # Note: Claude API requires 'type: custom' for custom tools (as of 2025)
    class ClaudeFormatter
      def format(tool)
        {
          type: "custom",
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

    # Alias for backwards compatibility
    AnthropicFormatter = ClaudeFormatter

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
          # Add items specification for array types (required by many LLM APIs)
          if param[:type] == "array" && param[:items]
            properties[name][:items] = param[:items]
          end
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

          # Add empty properties for object types (required by Gemini to avoid MALFORMED_FUNCTION_CALL)
          if param[:type] == "object"
            props[name.to_s]["properties"] = {}
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
          # Add items specification for array types
          if param[:type] == "array" && param[:items]
            props[name][:items] = param[:items]
          end
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
          # Add items specification for array types
          if param[:type] == "array" && param[:items]
            props[name][:items] = param[:items]
          end
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
          # Add items specification for array types
          if param[:type] == "array" && param[:items]
            props[name][:items] = param[:items]
          end
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
end
