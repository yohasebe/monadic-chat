# frozen_string_literal: true

module ErrorPatternDetector
  # Common error patterns that indicate system/environment issues rather than code issues
  SYSTEM_ERROR_PATTERNS = [
    # Font-related errors
    /findfont:.*Font family.*not found/i,
    /cannot find font/i,
    /font.*not available/i,
    /missing.*font/i,
    
    # Package/module errors
    /no module named/i,
    /modulenotfounderror/i,
    /importerror/i,
    
    # Permission errors
    /permission denied/i,
    /access denied/i,
    /operation not permitted/i,
    
    # Resource errors
    /out of memory/i,
    /disk full/i,
    /no space left/i,
    /cannot allocate memory/i,
    
    # Network errors
    /connection refused/i,
    /network unreachable/i,
    /timeout/i,
    
    # Matplotlib/plotting specific errors
    /backend.*not available/i,
    /cannot create figure/i,
    /failed to create.*window/i,
    /display.*not.*found/i,
    /DISPLAY.*not set/i,
    /cairo.*error/i,
    /agg.*error/i,
    
    # File I/O errors
    /cannot write file/i,
    /file.*locked/i,
    /read-only file system/i
  ].freeze
  
  # Track error patterns per session
  def self.initialize_session(session)
    session[:error_patterns] ||= {
      history: [],        # Array of { error: String, timestamp: Time, function: String }
      similar_count: 0,   # Count of similar consecutive errors
      last_pattern: nil   # Last detected error pattern
    }
  end
  
  def self.add_error(session, error_message, function_name)
    initialize_session(session)
    
    # Detect pattern for current error
    current_pattern = detect_pattern(error_message)
    
    # Check if this matches the last pattern before adding to history
    if current_pattern && current_pattern == session[:error_patterns][:last_pattern]
      # Same pattern as last error - increment count
      session[:error_patterns][:similar_count] += 1
    elsif current_pattern
      # New pattern detected - start counting from 0
      session[:error_patterns][:similar_count] = 0
      session[:error_patterns][:last_pattern] = current_pattern
    else
      # No pattern detected - reset
      session[:error_patterns][:similar_count] = 0
      session[:error_patterns][:last_pattern] = nil
    end
    
    # Add to history after checking pattern
    session[:error_patterns][:history] << {
      error: error_message,
      timestamp: Time.now,
      function: function_name
    }
    
    # Keep only last 10 errors
    if session[:error_patterns][:history].length > 10
      session[:error_patterns][:history].shift
    end
  end
  
  def self.should_stop_retrying?(session)
    return false unless session[:error_patterns]
    
    # Stop if we've seen 3 or more similar errors (similar_count starts at 0)
    # So after 3 errors: 0, 1, 2 - we should stop
    session[:error_patterns][:similar_count] >= 2
  end
  
  def self.get_error_suggestion(session)
    return nil unless session[:error_patterns][:last_pattern]
    
    pattern = session[:error_patterns][:last_pattern]
    
    case pattern
    when :font_error
      <<~MSG
        I'm encountering repeated font-related errors. This appears to be an environment issue.
        
        Suggestions:
        1. You can use a different plotting backend that doesn't require specific fonts
        2. Try using `plt.rcParams['font.family'] = 'DejaVu Sans'` or another available font
        3. Generate plots without text labels temporarily
        4. Contact your system administrator to install the missing fonts
        
        Would you like me to try one of these alternatives, or would you prefer to address the font issue first?
      MSG
    when :module_error
      <<~MSG
        I'm encountering repeated module import errors. The required packages may not be installed.

        Suggestions:
        1. Install the missing package using uv (faster) or pip:
           - `!uv pip install package_name` (recommended, 10-100x faster)
           - `!pip install package_name` (traditional)
        2. Use alternative packages that are already installed
        3. Check the environment with the `check_environment` function

        What would you like me to do?
      MSG
    when :permission_error
      <<~MSG
        I'm encountering repeated permission errors. This appears to be a system configuration issue.
        
        This might be due to:
        1. File system permissions
        2. Docker container restrictions
        3. Security policies
        
        Please check your system configuration or contact your administrator.
      MSG
    when :resource_error
      <<~MSG
        I'm encountering repeated resource errors (memory/disk space).
        
        Suggestions:
        1. Try processing smaller datasets
        2. Free up system resources
        3. Restart the container
        
        Would you like me to try a different approach?
      MSG
    when :plotting_error
      <<~MSG
        I'm encountering repeated plotting/visualization errors. This may be due to the display backend configuration.
        
        Suggestions:
        1. Switch to a non-interactive backend: `plt.switch_backend('Agg')`
        2. Save plots without displaying: `plt.savefig('plot.png', bbox_inches='tight')`
        3. Use simpler plotting libraries or export data for external visualization
        4. Try reducing plot complexity (fewer data points, simpler styles)
        
        Would you like me to try one of these alternatives?
      MSG
    when :file_io_error
      <<~MSG
        I'm encountering repeated file I/O errors. This may be due to permissions or file system issues.
        
        Suggestions:
        1. Try saving to a different filename or location
        2. Check if the file is already open in another program
        3. Use a different file format (e.g., PNG instead of PDF)
        4. Save to memory buffer instead of file
        
        How would you like to proceed?
      MSG
    else
      <<~MSG
        I'm encountering repeated errors while executing this task.
        
        Recent errors:
        #{session[:error_patterns][:history].last(3).map { |e| "- #{e[:error].lines.first.strip}" }.join("\n")}
        
        Would you like me to:
        1. Try a different approach
        2. Break down the task into smaller steps
        3. Check the environment configuration
        
        Please let me know how you'd like to proceed.
      MSG
    end
  end
  
  private
  
  def self.similar_to_recent?(session, error_message)
    return false if session[:error_patterns][:history].empty?
    
    # Get last 3 errors
    recent_errors = session[:error_patterns][:history].last(3).map { |e| e[:error] }
    
    # Check if error matches any system error pattern
    pattern = detect_pattern(error_message)
    return false unless pattern
    
    # Check if recent errors have the same pattern
    recent_errors.any? { |e| detect_pattern(e) == pattern }
  end
  
  def self.detect_pattern(error_message)
    return nil unless error_message
    
    error_lower = error_message.downcase
    
    # Check font errors
    if error_lower.include?('font') || error_lower.include?('findfont')
      return :font_error
    end
    
    # Check module errors
    if error_lower.include?('no module named') || error_lower.include?('modulenotfounderror')
      return :module_error
    end
    
    # Check permission errors
    if error_lower.include?('permission denied') || error_lower.include?('access denied')
      return :permission_error
    end
    
    # Check resource errors
    if error_lower.include?('out of memory') || error_lower.include?('disk full') || error_lower.include?('cannot allocate memory')
      return :resource_error
    end
    
    # Check plotting-specific errors
    if error_lower.include?('backend') || error_lower.include?('display') || 
       error_lower.include?('cairo') || error_lower.include?('agg') ||
       error_lower.include?('figure') || error_lower.include?('window')
      return :plotting_error
    end
    
    # Check file I/O errors
    if error_lower.include?('cannot write') || error_lower.include?('file locked') || 
       error_lower.include?('read-only')
      return :file_io_error
    end
    
    # Check for any system error pattern
    SYSTEM_ERROR_PATTERNS.each_with_index do |pattern, index|
      return "system_error_#{index}".to_sym if pattern =~ error_message
    end
    
    nil
  end
end