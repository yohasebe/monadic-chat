# frozen_string_literal: true

# Mixin module for vendor helpers to track and handle repeated function call errors
module FunctionCallErrorHandler
  # Process function returns and check for repeated errors
  def handle_function_error(session, function_return, function_name, &block)
    return false unless function_return.to_s.start_with?("ERROR:")
    
    # Initialize error pattern detector if not already done
    ErrorPatternDetector.initialize_session(session) unless session[:error_patterns]
    
    # Track the error
    ErrorPatternDetector.add_error(session, function_return.to_s, function_name)
    
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
  
  # Check if we should stop due to repeated errors
  def should_stop_for_errors?(session)
    session[:parameters] && session[:parameters]["stop_retrying"]
  end
  
  # Reset error tracking for a new conversation
  def reset_error_tracking(session)
    session[:error_patterns] = nil
    session[:parameters]["stop_retrying"] = false if session[:parameters]
  end
end