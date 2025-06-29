# frozen_string_literal: true

require 'json'

# Centralized schema validation and error handling for monadic responses
module MonadicSchemaValidator
  class ValidationError < StandardError; end

  # Validate response against monadic schema
  def validate_monadic_response!(response, schema_type = :basic)
    schema = get_schema(schema_type)
    errors = []
    
    begin
      data = parse_response(response)
      validate_against_schema(data, schema, errors)
      
      if errors.any?
        handle_validation_errors(data, errors)
      else
        data
      end
    rescue JSON::ParserError => e
      handle_parse_error(response, e)
    rescue StandardError => e
      handle_unexpected_error(response, e)
    end
  end

  # Safe parsing with multiple fallback strategies
  def safe_parse_monadic_response(response)
    return response if response.is_a?(Hash)
    
    # Strategy 1: Direct JSON parse
    begin
      return JSON.parse(response)
    rescue JSON::ParserError
      # Continue to next strategy
    end
    
    # Strategy 2: Handle double-encoded JSON
    if response.is_a?(String) && response.match?(/^["'].*["']$/)
      begin
        unquoted = JSON.parse(response)
        return JSON.parse(unquoted) if unquoted.is_a?(String)
      rescue JSON::ParserError
        # Continue to next strategy
      end
    end
    
    # Strategy 3: Handle malformed JSON (Perplexity issue)
    if response.is_a?(String) && response.match?(/^{\s*["{]/)
      cleaned = clean_malformed_json(response)
      begin
        return JSON.parse(cleaned)
      rescue JSON::ParserError
        # Continue to fallback
      end
    end
    
    # Fallback: Wrap in basic monadic structure
    {
      "message" => response.to_s,
      "context" => {
        "parse_error" => true,
        "original_format" => response.class.name
      }
    }
  end

  # Get appropriate schema based on type
  def get_schema(schema_type)
    case schema_type
    when :chat_plus
      MonadicProviderInterface::CHAT_PLUS_SCHEMA
    when :basic
      MonadicProviderInterface::MONADIC_JSON_SCHEMA
    else
      # Allow custom schemas
      schema_type.is_a?(Hash) ? schema_type : MonadicProviderInterface::MONADIC_JSON_SCHEMA
    end
  end

  private

  def parse_response(response)
    case response
    when Hash
      response
    when String
      safe_parse_monadic_response(response)
    else
      raise ValidationError, "Invalid response type: #{response.class}"
    end
  end

  def validate_against_schema(data, schema, errors)
    # Check required fields
    if schema["required"]
      schema["required"].each do |field|
        unless data.key?(field)
          errors << "Missing required field: #{field}"
        end
      end
    end
    
    # Check property types
    if schema["properties"]
      schema["properties"].each do |field, field_schema|
        if data.key?(field)
          validate_field(data[field], field_schema, field, errors)
        end
      end
    end
  end

  def validate_field(value, field_schema, field_name, errors)
    expected_type = field_schema["type"]
    
    case expected_type
    when "string"
      unless value.is_a?(String)
        errors << "Field '#{field_name}' must be a string, got #{value.class}"
      end
    when "array"
      unless value.is_a?(Array)
        errors << "Field '#{field_name}' must be an array, got #{value.class}"
      else
        # Validate array items if schema provided
        if field_schema["items"]
          value.each_with_index do |item, index|
            validate_field(item, field_schema["items"], "#{field_name}[#{index}]", errors)
          end
        end
      end
    when "object"
      unless value.is_a?(Hash)
        errors << "Field '#{field_name}' must be an object, got #{value.class}"
      else
        # Recursively validate nested objects
        if field_schema["properties"]
          nested_errors = []
          validate_against_schema(value, field_schema, nested_errors)
          errors.concat(nested_errors.map { |e| "#{field_name}.#{e}" })
        end
      end
    end
  end

  def handle_validation_errors(data, errors)
    # Log errors for debugging
    if defined?(DebugHelper)
      DebugHelper.debug("Monadic validation errors: #{errors.join(', ')}", category: :monadic, level: :warn)
    end
    
    # Attempt to fix common issues
    fixed_data = attempt_auto_fix(data, errors)
    
    # Re-validate after fixes
    new_errors = []
    validate_against_schema(fixed_data, get_schema(:basic), new_errors)
    
    if new_errors.empty?
      fixed_data
    else
      # Return with error context
      fixed_data["context"] ||= {}
      fixed_data["context"]["validation_errors"] = errors
      fixed_data
    end
  end

  def attempt_auto_fix(data, errors)
    fixed = data.deep_dup rescue data.dup
    
    errors.each do |error|
      case error
      when /Missing required field: message/
        fixed["message"] = fixed.to_s
      when /Missing required field: context/
        fixed["context"] = {}
      when /Field '(.+)' must be an array/
        field = $1
        set_nested_value(fixed, field, [])
      when /Field '(.+)' must be an object/
        field = $1
        set_nested_value(fixed, field, {})
      end
    end
    
    fixed
  end

  def set_nested_value(hash, path, value)
    keys = path.split('.')
    current = hash
    
    keys[0...-1].each do |key|
      current[key] ||= {}
      current = current[key]
    end
    
    current[keys.last] = value
  end

  def clean_malformed_json(json_str)
    # Handle Perplexity's malformed JSON: {"{"message":"...
    if json_str.match?(/^{"{"/)
      # Find the actual JSON starting from the second {
      actual_start = json_str.index('{', 1)
      if actual_start
        # Extract and balance braces
        actual_json = json_str[actual_start..-1]
        balance_braces(actual_json)
      else
        json_str
      end
    else
      json_str
    end
  end

  def balance_braces(json_str)
    brace_count = 0
    last_valid_pos = -1
    
    json_str.each_char.with_index do |char, idx|
      case char
      when '{'
        brace_count += 1
      when '}'
        brace_count -= 1
        if brace_count == 0
          last_valid_pos = idx
          break
        end
      end
    end
    
    last_valid_pos > -1 ? json_str[0..last_valid_pos] : json_str
  end

  def handle_parse_error(response, error)
    {
      "message" => "Failed to parse response",
      "context" => {
        "error_type" => "parse_error",
        "error_message" => error.message,
        "original_response" => response.to_s[0..500] # Truncate for safety
      }
    }
  end

  def handle_unexpected_error(response, error)
    {
      "message" => "An unexpected error occurred",
      "context" => {
        "error_type" => "unexpected_error",
        "error_class" => error.class.name,
        "error_message" => error.message
      }
    }
  end
end