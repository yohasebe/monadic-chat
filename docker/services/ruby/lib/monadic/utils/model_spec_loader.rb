# frozen_string_literal: true

module ModelSpecLoader
  extend self

  # Get the path to user's custom models.json file
  # Returns different paths based on environment (Docker container vs development)
  def user_models_path
    if IN_CONTAINER
      # Inside Docker container
      "/monadic/config/models.json"
    else
      # Development environment (host machine)
      File.expand_path("~/monadic/config/models.json")
    end
  end

  # Deep merge two hashes recursively
  # New values override old values, nested hashes are merged
  def deep_merge(hash1, hash2)
    hash1.merge(hash2) do |key, old_val, new_val|
      if old_val.is_a?(Hash) && new_val.is_a?(Hash)
        deep_merge(old_val, new_val)
      else
        new_val
      end
    end
  end

  # Load and merge model specifications
  # Returns merged model spec with user customizations applied
  def load_merged_spec(default_spec_path)
    # Load default model specification
    content = File.read(default_spec_path)
    
    # Find the modelSpec object boundaries
    start_match = content.index("const modelSpec = {")
    if start_match
      # Find the matching closing brace
      lines = content.split("\n")
      brace_count = 0
      start_line_idx = nil
      end_line_idx = nil
      
      lines.each_with_index do |line, idx|
        if line.include?("const modelSpec = {")
          start_line_idx = idx
          brace_count = 1
        elsif start_line_idx && brace_count > 0
          brace_count += line.count("{")
          brace_count -= line.count("}")
          if brace_count == 0
            end_line_idx = idx
            break
          end
        end
      end
      
      if start_line_idx && end_line_idx
        # Extract just the JSON part
        json_lines = lines[start_line_idx..end_line_idx]
        json_content = json_lines.join("\n")
        
        # Remove the const declaration
        json_content = json_content.sub(/^const modelSpec = /, '')
        
        # Remove trailing semicolon on the last line
        json_content = json_content.sub(/};?\s*$/, '}')
        
        # Remove JavaScript comments (do this per line to preserve structure)
        cleaned_lines = json_content.split("\n").map do |line|
          # Remove // comments and trim whitespace
          line.gsub(/\/\/.*$/, '').rstrip
        end
        
        # Join non-empty lines (remove blank lines that can break JSON)
        json_content = cleaned_lines.reject { |line| line.strip.empty? }.join("\n")
        # Remove multi-line comments
        json_content = json_content.gsub(%r{/\*.*?\*/}m, '')
        
        # Fix trailing commas before closing braces/brackets (invalid in JSON)
        json_content = json_content.gsub(/,(\s*[}\]])/, '\1')
        
        # Debug: Check for any remaining semicolons
        if json_content.include?(';')
          STDERR.puts "[Model Spec Debug] JSON still contains semicolon after processing" if CONFIG["EXTRA_LOGGING"]
          json_content = json_content.gsub(';', '')
        end
        
        default_spec = JSON.parse(json_content)
      else
        raise "Could not find modelSpec object in #{default_spec_path}"
      end
    else
      raise "Could not find modelSpec declaration in #{default_spec_path}"
    end
    
    # Check for user's custom models file
    user_path = user_models_path
    
    if File.exist?(user_path)
      begin
        user_spec = JSON.parse(File.read(user_path))
        merged_spec = deep_merge(default_spec, user_spec)
        
        if CONFIG["EXTRA_LOGGING"]
          STDERR.puts "[Model Spec] Loaded user models from #{user_path}"
          STDERR.puts "[Model Spec] Merged #{user_spec.keys.size} custom model definitions"
        end
        
        merged_spec
      rescue JSON::ParserError => e
        STDERR.puts "[Model Spec Error] Invalid JSON in #{user_path}: #{e.message}"
        default_spec
      rescue => e
        STDERR.puts "[Model Spec Error] Failed to load user models: #{e.message}"
        default_spec
      end
    else
      STDERR.puts "[Model Spec] Using default models (no custom models.json found at #{user_path})" if CONFIG["EXTRA_LOGGING"]
      default_spec
    end
  end
end