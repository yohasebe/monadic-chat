# frozen_string_literal: true

require_relative 'core'

module MonadicChat
  # JSON-specific handling for monadic operations
  module JsonHandler
    include Core
    
    # Wrap a value as JSON (compatible with existing monadic_unit)
    def wrap_as_json(message, context = {})
      data = {
        "message" => message,
        "context" => context || {}
      }
      data.to_json
    end
    
    # Unwrap from JSON (compatible with existing monadic_unwrap)
    def unwrap_from_json(json_string)
      case json_string
      when String
        begin
          # First attempt to parse
          parsed = JSON.parse(json_string)
          
          # Check for various double-encoding situations
          if parsed.is_a?(Hash)
            # Check if we got the correct structure
            if parsed.key?("message") && parsed.key?("context")
              # Check if the message is itself an escaped JSON string
              if parsed["message"].is_a?(String) && parsed["message"].match(/^\{\\"/)
                begin
                  # First unescape the string
                  unescaped = parsed["message"].gsub('\"', '"').gsub('\\\\', '\\')
                  
                  # Then parse the unescaped JSON
                  actual_content = JSON.parse(unescaped)
                  if actual_content.is_a?(Hash) && actual_content.key?("message") && actual_content.key?("context")
                    return actual_content
                  end
                rescue JSON::ParserError => e
                  # Try another approach - use eval to handle the escaping
                  begin
                    # This is a last resort for heavily escaped JSON
                    evaluated = eval('"' + parsed["message"] + '"')
                    actual_content = JSON.parse(evaluated)
                    if actual_content.is_a?(Hash) && actual_content.key?("message") && actual_content.key?("context")
                      return actual_content
                    end
                  rescue => e2
                    # Continue with original parsed value
                  end
                end
              end
              return parsed
            end
            
            # Check if the hash has a single key that looks like JSON
            if parsed.keys.length == 1 && parsed.keys.first.start_with?('{')
              # The JSON itself is the key! Extract and parse it
              json_key = parsed.keys.first
              begin
                actual_json = JSON.parse(json_key)
                return actual_json
              rescue JSON::ParserError
                # Continue with original parsed value
              end
            end
          elsif parsed.is_a?(String) && parsed.start_with?('{')
            # Double-encoded JSON string
            begin
              double_parsed = JSON.parse(parsed)
              return double_parsed
            rescue JSON::ParserError
              # Not double-encoded, use first parse result
              return parsed
            end
          end
          
          parsed
        rescue JSON::ParserError => e
          # Fallback behavior matching original implementation
          { "message" => json_string.to_s, "context" => @context || {} }
        end
      when Hash
        json_string
      else
        { "message" => json_string.to_s, "context" => @context || {} }
      end
    end
    
    # Transform JSON monad (compatible with existing monadic_map)
    def transform_json(json_monad, &block)
      obj = unwrap_from_json(json_monad)
      
      # Update context if block is given
      if block_given? && obj["context"]
        new_context = yield(obj["context"])
        obj["context"] = new_context
        
        # Update instance variable if it exists (for compatibility)
        @context = new_context if defined?(@context)
      end
      
      # Return pretty-printed JSON
      JSON.pretty_generate(sanitize_json_data(obj))
    end
    
    # Parse JSON response with validation
    def parse_json_response(response, expected_structure = nil)
      parsed = unwrap_from_json(response)
      
      if expected_structure
        validate_json_structure(parsed, expected_structure)
      end
      
      parsed
    end
    
    # == Validation Methods ==
    
    # Validate JSON structure against expected format
    def validate_json_structure(data, expected)
      errors = []
      
      expected.each do |key, type_or_value|
        if !data.key?(key)
          errors << "Missing required field: #{key}"
        elsif type_or_value.is_a?(Class)
          unless data[key].is_a?(type_or_value)
            errors << "Field '#{key}' should be #{type_or_value}, got #{data[key].class}"
          end
        elsif type_or_value.is_a?(Hash)
          # Recursive validation for nested structures
          if data[key].is_a?(Hash)
            nested_errors = validate_json_structure(data[key], type_or_value)
            errors.concat(nested_errors.map { |e| "#{key}.#{e}" })
          else
            errors << "Field '#{key}' should be a Hash"
          end
        end
      end
      
      errors
    end
    
    # == Utility Methods ==
    
    private
    
    # Sanitize data for JSON (matching original sanitize_data method)
    def sanitize_json_data(data)
      case data
      when String
        data.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      when Hash
        data.transform_values { |v| sanitize_json_data(v) }
      when Array
        data.map { |v| sanitize_json_data(v) }
      else
        data
      end
    end
    
    # Extract JSON from mixed content
    def extract_json_from_content(content)
      # Try to find JSON object in the content
      json_match = content.match(/\{.*\}/m)
      return nil unless json_match
      
      begin
        JSON.parse(json_match[0])
      rescue JSON::ParserError
        nil
      end
    end
  end
end