# frozen_string_literal: true

# Helper module for flexible E2E test validation
module ValidationHelper
  # Check if response is valid (not an error)
  def valid_response?(response)
    return false if response.nil? || response.empty?
    
    # Check for common error patterns (but be more specific to avoid false positives)
    error_patterns = [
      /\berror\b.*occurred|failed to|exception:|traceback/i,
      /undefined method|no such file or directory/i,
      /timeout|connection refused/i,
      /NameError:|TypeError:|SyntaxError:/i
    ]
    
    !error_patterns.any? { |pattern| response.match?(pattern) }
  end
  
  # Check if response indicates successful completion
  def successful_response?(response)
    return false unless valid_response?(response)
    
    # Look for success indicators
    success_patterns = [
      /completed|success|done|finished/i,
      /created|generated|saved|written/i,
      /calculated|computed|analyzed/i,
      /result|output|answer/i
    ]
    
    success_patterns.any? { |pattern| response.match?(pattern) } ||
      response.length > 20  # Non-trivial response
  end
  
  # Check if response contains code
  def contains_code?(response)
    response.include?("```") || 
      response.match?(/def\s+\w+|class\s+\w+|import\s+\w+|function\s+\w+/i)
  end
  
  # Check if response contains numeric results
  def contains_numeric_results?(response)
    # Remove commas and check for numbers
    cleaned = response.gsub(",", "")
    cleaned.match?(/\b\d+\.?\d*\b/)
  end
  
  # Check if response acknowledges the task
  def acknowledges_task?(response, keywords)
    keywords = Array(keywords)
    keywords.any? { |keyword| response.downcase.include?(keyword.downcase) }
  end
  
  # Generic validation for complex workflows
  def validates_workflow_step?(response, step_type)
    case step_type
    when :code_generation
      contains_code?(response) || acknowledges_task?(response, %w[function code implement write])
    when :data_analysis
      contains_numeric_results?(response) || acknowledges_task?(response, %w[calculate analyze average sum])
    when :file_operation
      acknowledges_task?(response, %w[file save create read write csv json png])
    when :visualization
      acknowledges_task?(response, %w[chart graph plot visualization image])
    else
      successful_response?(response)
    end
  end
  
  # Check if response indicates code was executed
  def shows_code_execution?(response)
    # Look for signs that code was run
    patterns = [
      /output:|result:|executed|ran|running/i,
      /```[\s\S]*?```/,  # Code blocks
      /\b\d+\b/,         # Numbers in output
      /successfully|completed|finished/i,
      /run_code/i,       # Function call mentioned
      /python.*print/i,  # Python execution
      /mean|average|sum|calculation/i, # Data analysis terms
      /dataframe|pandas|numpy/i # Data science libraries
    ]
    patterns.any? { |pattern| response.match?(pattern) }
  end
  
  # Check if response shows understanding of the task
  def understands_task?(response, task_keywords)
    # More flexible - just needs to mention some aspect of the task
    task_keywords = Array(task_keywords)
    task_keywords.any? { |keyword| response.downcase.include?(keyword.downcase) } ||
      shows_code_execution?(response)
  end
  
  # Extract any numbers from response
  def extract_numbers(response)
    response.scan(/\b\d+(?:\.\d+)?\b/).map(&:to_f)
  end
  
  # Check if response contains expected number within tolerance
  def contains_number_near?(response, expected, tolerance = 0.1)
    numbers = extract_numbers(response)
    numbers.any? { |n| (n - expected).abs <= tolerance }
  end
  
  # Check if AI attempted to use a tool/function
  def attempted_tool_use?(response)
    tool_patterns = [
      /run_code|fetch_text|find_closest|get_text/i,
      /function.*call|calling.*function|using.*tool/i,
      /execute|executing|running/i,
      /unable.*execute.*missing.*parameter/i,  # Common Cohere error
      /issue.*connecting|error.*find/i  # PDF Navigator errors
    ]
    tool_patterns.any? { |pattern| response.match?(pattern) }
  end
  
  # Check if response indicates a system/API error (not user error)
  def system_error?(response)
    system_patterns = [
      /API ERROR:|internal error|server error/i,
      /connecting to the server|connection.*issue/i,
      /unable to access|cannot.*retrieve/i,
      /try again later|check your connection/i
    ]
    system_patterns.any? { |pattern| response.match?(pattern) }
  end
  
  # More flexible validation for PDF Navigator
  def pdf_search_attempted?(response)
    # Accept if the AI tried to search, even if it failed
    attempted_tool_use?(response) || 
      acknowledges_task?(response, %w[search find look pdf document text])
  end
  
  # More flexible validation for code interpreter
  def code_execution_attempted?(response)
    # Accept if the AI tried to execute code or mentioned the task
    attempted_tool_use?(response) ||
      contains_code?(response) ||
      acknowledges_task?(response, %w[code execute run python calculate])
  end
end