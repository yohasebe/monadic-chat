# frozen_string_literal: true

require 'json'

module ModelTokenUtils
  module_function

  # Default max_tokens if model not found
  DEFAULT_MAX_TOKENS = 4096

  # Load model_spec.js and extract max_output_tokens
  def load_model_spec
    spec_file = File.join(File.dirname(__FILE__), '../../../public/js/monadic/model_spec.js')
    return {} unless File.exist?(spec_file)
    
    content = File.read(spec_file)
    # Extract the JSON-like content
    match = content.match(/const\s+modelSpec\s*=\s*(\{[\s\S]*?\n\});?/m)
    return {} unless match
    
    json_content = match[1]
    # Remove comments
    json_content = json_content.gsub(%r{//[^\n]*}, "")
    # Fix trailing commas (not valid in JSON)
    json_content = json_content.gsub(/,(\s*[}\]])/, '\1')
    
    begin
      JSON.parse(json_content)
    rescue JSON::ParserError => e
      puts "Warning: Failed to parse model_spec.js: #{e.message}" if ENV['DEBUG']
      {}
    end
  end

  # Get max_tokens for a model from model_spec.js
  def get_max_tokens(model_name)
    return DEFAULT_MAX_TOKENS if model_name.nil?
    
    # Load model spec
    spec = load_model_spec
    
    # Try exact match first
    if spec[model_name] && spec[model_name]["max_output_tokens"]
      max_tokens = spec[model_name]["max_output_tokens"]
      # Handle array format [min, max] or [[min, max], default]
      if max_tokens.is_a?(Array)
        # If it's [[min, max], default], use default
        if max_tokens.length == 2 && max_tokens[0].is_a?(Array)
          return max_tokens[1]
        # If it's [min, max], use max
        elsif max_tokens.length == 2
          return max_tokens[1]
        end
      end
      return max_tokens
    end
    
    # Try partial match for models with dates
    spec.each do |key, value|
      if (model_name.include?(key) || key.include?(model_name)) && value["max_output_tokens"]
        max_tokens = value["max_output_tokens"]
        # Handle array format
        if max_tokens.is_a?(Array)
          if max_tokens.length == 2 && max_tokens[0].is_a?(Array)
            return max_tokens[1]
          elsif max_tokens.length == 2
            return max_tokens[1]
          end
        end
        return max_tokens
      end
    end
    
    # Return default if no match found
    DEFAULT_MAX_TOKENS
  end
end