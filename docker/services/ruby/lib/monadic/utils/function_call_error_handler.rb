# frozen_string_literal: true

# Mixin module for vendor helpers to track and handle repeated function call errors
module FunctionCallErrorHandler
  # Detect whether a function return value indicates an error.
  # Covers multiple error formats:
  #   - String prefixes: "ERROR:", "Error:", "Error executing code:", "Error occurred:", "❌"
  #   - Hash with { success: false } or { "success" => false }
  #   - JSON string containing {"success":false}
  def function_return_is_error?(function_return)
    # Hash-style error detection (e.g., { success: false, error: "..." })
    if function_return.is_a?(Hash)
      return true if function_return[:success] == false || function_return["success"] == false
    end

    text = function_return.to_s
    return true if text.start_with?("ERROR:")
    return true if text.start_with?("Error executing code")
    return true if text.start_with?("Error occurred")
    return true if text.start_with?("Error:")
    return true if text.start_with?("❌")

    # JSON string with success:false (e.g., from .to_json calls)
    return true if text.include?('"success":false') || text.include?('"success": false')

    false
  end

  # Process function returns and check for repeated errors
  def handle_function_error(session, function_return, function_name, &block)
    return false unless function_return_is_error?(function_return)

    # Initialize error pattern detector if not already done
    ErrorPatternDetector.initialize_session(session) unless session[:error_patterns]

    # Track the error
    ErrorPatternDetector.add_error(session, function_return.to_s, function_name)

    # Tag the most recently recorded tool call as errored so cycle detection
    # can distinguish stuck loops from legitimate iterative refinement.
    ErrorPatternDetector.mark_last_tool_errored(session)
    
    # Check if we should stop retrying
    if ErrorPatternDetector.should_stop_retrying?(session)
      suggestion = ErrorPatternDetector.get_error_suggestion(session)
      
      # Send suggestion as a fragment if block given
      if block
        res = {
          "type" => "fragment",
          "content" => "\n\n#{suggestion}"
        }
        block.call res
      end
      
      # Mark that we should stop retrying
      session[:parameters] ||= {}
      session[:parameters]["stop_retrying"] = true
      
      return true # Signal that we should stop
    end
    
    false # Continue processing
  end
  
  # Record a tool call (regardless of success/failure) for cycle detection
  def record_tool_call(session, function_name)
    ErrorPatternDetector.record_tool_call(session, function_name)
  end

  # Check if we should stop due to repeated errors OR tool call cycles
  def should_stop_for_errors?(session)
    return true if session[:parameters] && session[:parameters]["stop_retrying"]

    if ErrorPatternDetector.tool_call_cycle_detected?(session)
      session[:parameters] ||= {}
      session[:parameters]["stop_retrying"] = true
      return true
    end

    false
  end

  # Get stop message (error suggestion or cycle warning)
  def stop_message_for_session(session)
    ErrorPatternDetector.tool_cycle_message(session) ||
      ErrorPatternDetector.get_error_suggestion(session)
  end

  # Reset error tracking for a new conversation
  def reset_error_tracking(session)
    session[:error_patterns] = nil
    ErrorPatternDetector.reset_tool_tracking(session)
    session[:parameters]["stop_retrying"] = false if session[:parameters]
  end
end