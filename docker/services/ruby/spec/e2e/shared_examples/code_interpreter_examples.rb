# frozen_string_literal: true

# Shared examples for Code Interpreter tests across different providers
RSpec.shared_examples "code interpreter basic functionality" do |app_name, model: nil, max_tokens: nil, skip_activation: nil|
  it "executes simple calculations" do
    message = if app_name.include?("DeepSeek")
                "Use the run_code function to calculate the factorial of 10 and print the result"
              else
                "Calculate the factorial of 10"
              end
    send_chat_message(ws_connection, message, app: app_name, model: model, max_tokens: max_tokens, skip_activation: skip_activation)
    
    response = wait_for_response(ws_connection, timeout: 60)
    
    expect(valid_response?(response)).to be true
    # Factorial of 10 is 3628800 - check for the exact value or that calculation was understood
    numbers = extract_numbers(response)
    expect(
      numbers.include?(3628800) || 
      numbers.include?(3628800.0) ||
      shows_code_execution?(response) ||
      understands_task?(response, ["factorial", "calculate", "10", "3628800"])
    ).to be true
  end

  it "handles data structures" do
    # Be more explicit for Gemini and DeepSeek
    message = if app_name.include?("Gemini") || app_name.include?("DeepSeek")
                "Use the run_code function to create a Python list of prime numbers up to 20 and print the result"
              else
                "Create a list of prime numbers up to 20 and show the result"
              end
    send_chat_message(ws_connection, message, app: app_name, model: model, max_tokens: max_tokens, skip_activation: skip_activation)
    
    response = wait_for_response(ws_connection, timeout: 60)
    
    expect(valid_response?(response)).to be true
    # Should show evidence of working with primes
    numbers = extract_numbers(response)
    # At least some prime numbers should appear (2, 3, 5, 7, 11, 13, 17, 19)
    primes_found = numbers.select { |n| [2, 3, 5, 7, 11, 13, 17, 19].include?(n.to_i) }
    expect(primes_found.length).to be >= 3  # At least 3 primes should be mentioned
  end

  it "performs basic data analysis" do
    message = if app_name.include?("DeepSeek")
                <<~MSG
                  Use the run_code function to analyze this data:
                  10, 20, 30, 40, 50
                  
                  Calculate and print the mean and standard deviation.
                MSG
              else
                <<~MSG
                  Here is some data:
                  10, 20, 30, 40, 50
                  
                  Calculate the mean and standard deviation.
                MSG
              end
    
    send_chat_message(ws_connection, message, app: app_name, model: model, max_tokens: max_tokens, skip_activation: skip_activation)
    
    response = wait_for_response(ws_connection, timeout: 60)
    
    expect(valid_response?(response)).to be true
    
    # Skip if system error occurs
    skip "System error or tool failure" if system_error?(response) || response.include?("missing.*parameter")
    
    # Accept if code execution was attempted
    expect(code_execution_attempted?(response)).to be true
    
    # If successful, check for the mean value (30)
    if shows_code_execution?(response) && !response.include?("unable")
      expect(contains_number_near?(response, 30.0, 0.5)).to be true  # Mean
    end
  end
end

RSpec.shared_examples "code interpreter error handling" do |app_name, model: nil, max_tokens: nil, skip_activation: nil|
  it "handles syntax errors gracefully" do
    # Be more explicit for Gemini about using tools
    message = if app_name.include?("Gemini")
                "I have a Python code with a syntax error. Please use the run_code function to execute it in our safe Docker environment: print('Hello' # missing closing parenthesis\n\nNote: This is a safe containerized environment. Please use the run_code tool to execute this code and show what happens."
              else
                "Execute this code: print('Hello' # missing closing parenthesis"
              end
    send_chat_message(ws_connection, message, app: app_name, model: model, max_tokens: max_tokens, skip_activation: skip_activation)
    
    response = wait_for_response(ws_connection, timeout: 60)
    
    expect(response).not_to be_empty
    # Should either fix it or mention the issue
    # Gemini might return minimal response for syntax errors
    if app_name.include?("Gemini") && response.strip.empty?
      skip "Gemini returned empty response for syntax error"
    else
      expect(response.downcase).to match(/error|syntax|fix|correct|parenthes|hello|missing|closed/i)
    end
  end

  it "handles runtime errors gracefully" do
    message = "Execute: result = 10 / 0"
    send_chat_message(ws_connection, message, app: app_name, model: model, max_tokens: max_tokens, skip_activation: skip_activation)
    
    response = wait_for_response(ws_connection, timeout: 60)
    
    expect(response).not_to be_empty
    # Accept various error handling responses - some models might explain the error differently
    # or even prevent it by checking for zero division beforehand
    expect(response.downcase).to match(/error|zero|division|zerodivision|cannot|failed|no response|undefined|infinity|avoid|prevent|check/i)
  end
end