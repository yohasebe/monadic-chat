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
    
    # Load MDSL schema if available
    begin
      require_relative 'mdsl_schema'
      use_schema = true
    rescue LoadError
      use_schema = false
    end
    
    if use_schema
      # First normalize the hash to convert aliases to canonical names
      parsed = MDSLSchema.normalize_hash(parsed)
      
      # Use MDSL schema for type information
      fields = parsed.keys.select { |key| MDSLSchema.boolean?(key) } if fields.empty?
    else
      # Fallback to pattern matching
      # Fields that should never be converted to boolean
      protected_fields = %w[images message text content html data files pdfs documents cells parameters settings config options]
      
      # If no specific fields provided, check common boolean field names
      if fields.empty?
        fields = hash.keys.select do |key|
          key_str = key.to_s.downcase
          # Skip protected fields
          next if protected_fields.include?(key_str)
          
          # Match boolean-like field names (exact match for single words)
          key_str.match?(/^(is_|has_|enable_|disable_|use_|websearch$|auto_|monadic$|jupyter$|easy_submit$|initiate_from_assistant$|stream$|vision$|reasoning$|ai_user$)/i)
        end
      end
    end
    
    fields.each do |field|
      field_str = field.to_s
      if parsed.key?(field_str)
        value = parsed[field_str]
        # Skip if MDSL schema says this field should be protected
        next if use_schema && MDSLSchema.protected?(field_str)
        
        # Only parse if it's a boolean-like value (not arrays, hashes, or complex objects)
        if value.nil? || value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
          parsed[field_str] = parse(value)
        end
      elsif parsed.key?(field.to_sym)
        value = parsed[field.to_sym]
        # Skip if MDSL schema says this field should be protected
        next if use_schema && MDSLSchema.protected?(field.to_sym)
        
        # Only parse if it's a boolean-like value (not arrays, hashes, or complex objects)
        if value.nil? || value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
          parsed[field.to_sym] = parse(value)
        end
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