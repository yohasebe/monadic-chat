# frozen_string_literal: true

# Utility module for consistent boolean parsing between JavaScript and Ruby
module BooleanParser
  # Convert various boolean representations to actual boolean value
  # Handles: true, false, "true", "false", 1, 0, "1", "0", "yes", "no", nil
  def self.parse(value)
    return false if value.nil?
    
    case value
    when true, false
      value
    when String
      case value.downcase.strip
      when "true", "1", "yes", "on"
        true
      when "false", "0", "no", "off", ""
        false
      else
        # For any other string value, consider it truthy
        !value.empty?
      end
    when Integer
      value != 0
    when Float
      value != 0.0
    else
      # For any other type, use Ruby's truthiness
      !!value
    end
  end

  # Strict version that only accepts specific values
  # Returns nil for invalid input
  def self.parse_strict(value)
    return nil if value.nil?
    
    case value
    when true, false
      value
    when String
      case value.downcase.strip
      when "true", "1", "yes", "on"
        true
      when "false", "0", "no", "off", ""
        false
      else
        nil
      end
    when 1, 1.0
      true
    when 0, 0.0
      false
    else
      nil
    end
  end

  # Parse all boolean-like fields in a hash
  # Useful for processing parameters from JavaScript
  def self.parse_hash(hash, fields = [])
    return hash unless hash.is_a?(Hash)
    
    parsed = hash.dup
    
    # If no specific fields provided, check common boolean field names
    if fields.empty?
      fields = hash.keys.select do |key|
        key.to_s.match?(/^(is_|has_|enable_|disable_|use_|websearch|auto_|monadic|toggle|jupyter|image|pdf|easy_submit|initiate_from_assistant|stream|vision|reasoning|ai_user)/i)
      end
    end
    
    fields.each do |field|
      field_str = field.to_s
      if parsed.key?(field_str)
        parsed[field_str] = parse(parsed[field_str])
      elsif parsed.key?(field.to_sym)
        parsed[field.to_sym] = parse(parsed[field.to_sym])
      end
    end
    
    parsed
  end
end

# Convenience module to include in classes
module BooleanParsable
  def parse_boolean(value)
    BooleanParser.parse(value)
  end
  
  def parse_boolean_strict(value)
    BooleanParser.parse_strict(value)
  end
  
  def parse_boolean_params(params, fields = [])
    BooleanParser.parse_hash(params, fields)
  end
end