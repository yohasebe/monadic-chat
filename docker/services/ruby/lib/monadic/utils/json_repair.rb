# JSON repair utility for handling truncated tool inputs from Claude
module JSONRepair
  def self.attempt_repair(json_string)
    return {} if json_string.nil? || json_string.empty?
    
    # First, try normal parsing
    begin
      return JSON.parse(json_string)
    rescue JSON::ParserError
      # Continue with repair attempts
    end
    
    # Attempt to repair common truncation issues
    repaired = json_string.dup
    
    # Count quotes to detect unclosed strings
    double_quotes = repaired.scan(/"/).count
    single_quotes = repaired.scan(/'/).count
    
    # Fix unclosed strings by adding closing quotes
    if double_quotes.odd?
      # Find the last opening quote without a closing quote
      repaired += '"'
    end
    
    # Fix unclosed braces/brackets
    open_braces = repaired.count('{')
    close_braces = repaired.count('}')
    open_brackets = repaired.count('[')
    close_brackets = repaired.count(']')
    
    # Add missing closing brackets/braces
    (open_brackets - close_brackets).times { repaired += ']' }
    (open_braces - close_braces).times { repaired += '}' }
    
    # Try parsing the repaired JSON
    begin
      JSON.parse(repaired)
    rescue JSON::ParserError => e
      # If still failing, try more aggressive repairs
      
      # Handle truncated strings in the middle of JSON
      if repaired =~ /"[^"]*$/
        # String starts but doesn't end - close it
        repaired += '"'
        
        # Add closing braces/brackets after string
        repaired += '}' * [open_braces - close_braces, 0].max
        repaired += ']' * [open_brackets - close_brackets, 0].max
      end
      
      # Final attempt
      begin
        JSON.parse(repaired)
      rescue JSON::ParserError
        # Log the failed repair attempt
        {
          "_json_repair_failed" => true,
          "_original_length" => json_string.length,
          "_error" => e.message
        }
      end
    end
  end
  
  # Extract code from potentially truncated run_script JSON
  def self.extract_run_script_params(json_string)
    extract_code_execution_params(json_string)
  end
  
  # Extract code from potentially truncated run_code JSON
  def self.extract_run_code_params(json_string)
    extract_code_execution_params(json_string)
  end
  
  # Extract parameters from potentially truncated add_jupyter_cells JSON
  def self.extract_jupyter_cells_params(json_string)
    # First try normal repair
    result = attempt_repair(json_string)
    return result unless result["_json_repair_failed"]
    
    # Manual extraction for Jupyter cells parameters
    params = {}
    
    # Extract filename parameter
    if match = json_string.match(/"filename"\s*:\s*"([^"]+)"/)
      params["filename"] = match[1]
    end
    
    # Extract cells array (complex structure, may be truncated)
    if match = json_string.match(/"cells"\s*:\s*(\[.*)/m)
      cells_json = match[1]
      
      # Try to parse the cells array
      begin
        # Add closing brackets if needed
        open_brackets = cells_json.count('[')
        close_brackets = cells_json.count(']')
        cells_json += ']' * [open_brackets - close_brackets, 0].max
        
        # Add closing braces if needed
        open_braces = cells_json.count('{')
        close_braces = cells_json.count('}')
        cells_json += '}' * [open_braces - close_braces, 0].max
        
        params["cells"] = JSON.parse(cells_json)
      rescue JSON::ParserError
        # If cells parsing fails, try to extract at least the cell types and partial content
        cells = []
        
        # Extract individual cells using pattern matching
        cells_json.scan(/\{[^}]*"cell_type"\s*:\s*"([^"]+)"[^}]*"source"\s*:\s*"([^"]*)/m) do |type, source|
          cells << {
            "cell_type" => type,
            "source" => source + (source.end_with?('\\') ? '' : ' # [Content may have been truncated]')
          }
        end
        
        params["cells"] = cells unless cells.empty?
      end
    end
    
    # Extract run parameter (boolean)
    if match = json_string.match(/"run"\s*:\s*(true|false)/)
      params["run"] = match[1] == "true"
    end
    
    # Extract escaped parameter (boolean)
    if match = json_string.match(/"escaped"\s*:\s*(true|false)/)
      params["escaped"] = match[1] == "true"
    end
    
    params
  end
  
  # Common extraction logic for both run_script and run_code
  def self.extract_code_execution_params(json_string)
    # First try normal repair
    result = attempt_repair(json_string)
    return result unless result["_json_repair_failed"]
    
    # Manual extraction for code execution parameters
    params = {}
    
    # Extract code parameter (may be truncated)
    if match = json_string.match(/"code"\s*:\s*"([^"]*)/m)
      params["code"] = match[1]
      # If code seems truncated (no closing quote found after), add a comment
      if json_string.index('"', match.end(0)).nil?
        params["code"] += "\n# [Code may have been truncated]"
      end
    end
    
    # Extract command parameter
    if match = json_string.match(/"command"\s*:\s*"([^"]+)"/)
      params["command"] = match[1]
    end
    
    # Extract extension parameter  
    if match = json_string.match(/"extension"\s*:\s*"([^"]+)"/)
      params["extension"] = match[1]
    end
    
    params
  end
end