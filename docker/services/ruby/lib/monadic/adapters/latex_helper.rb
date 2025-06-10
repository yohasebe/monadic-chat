# frozen_string_literal: true

module LatexHelper
  # Escape special LaTeX characters in text
  def escape_latex(text)
    return text if text.nil? || text.empty?
    
    text.gsub('\\', '\\textbackslash{}')  # Must be first
        .gsub('_', '\\_')
        .gsub('%', '\\%')
        .gsub('$', '\\$')
        .gsub('&', '\\&')
        .gsub('#', '\\#')
        .gsub('{', '\\{')
        .gsub('}', '\\}')
        .gsub('^', '\\^{}')
        .gsub('~', '\\~{}')
  end
  
  # Decode HTML entities that might appear in LaTeX code
  def decode_html_entities(text)
    return text if text.nil? || text.empty?
    
    # Common HTML entities
    text = text.gsub('&amp;', '&')
               .gsub('&lt;', '<')
               .gsub('&gt;', '>')
               .gsub('&quot;', '"')
               .gsub('&#39;', "'")
               .gsub('&apos;', "'")
    
    # Numeric entities
    text = text.gsub(/&#(\d+);/) { [$1.to_i].pack('U') }
    
    # Hex entities
    text = text.gsub(/&#x([0-9a-fA-F]+);/) { [$1.to_i(16)].pack('U') }
    
    text
  end
  
  # Analyze LaTeX compilation log for errors
  def analyze_latex_error(log_content)
    errors = []
    
    # Check for undefined control sequences
    if log_content =~ /Undefined control sequence.*\\(\w+)/
      errors << { type: :undefined_command, command: $1 }
    end
    
    # Check for missing packages
    if log_content =~ /LaTeX Error: Environment (\w+) undefined/
      errors << { type: :undefined_environment, environment: $1 }
    end
    
    # Check for unmatched brackets/braces
    if log_content =~ /Paragraph ended before .* was complete/
      errors << { type: :unmatched_delimiter }
    end
    
    # Check for file not found
    if log_content =~ /File `(.+)' not found/
      errors << { type: :file_not_found, file: $1 }
    end
    
    # Check for tikz-qtree specific errors
    if log_content =~ /Package tikz-qtree Error/
      errors << { type: :tikz_qtree_error }
    end
    
    errors
  end
  
  # Apply automatic fixes based on error analysis
  def apply_latex_fixes(latex_code, errors)
    fixed_code = latex_code.dup
    
    errors.each do |error|
      case error[:type]
      when :undefined_environment
        if error[:environment] == 'axis' && !fixed_code.include?('\\usepackage{pgfplots}')
          # Add pgfplots package after tikz
          fixed_code.gsub!(/\\usepackage{tikz}/, "\\usepackage{tikz}\n\\usepackage{pgfplots}\n\\pgfplotsset{compat=1.18}")
        end
      when :tikz_qtree_error
        # Ensure proper qtree format
        fixed_code = ensure_qtree_format(fixed_code)
      end
    end
    
    fixed_code
  end
  
  # Ensure proper tikz-qtree format
  def ensure_qtree_format(latex_code)
    # Make sure all nodes have dots before labels
    latex_code.gsub(/\[([^\s\[\]\.]+)(\s+[^\[\]]+\])/) do |match|
      label = $1
      rest = $2
      if label.start_with?('.')
        match
      else
        "[.#{label}#{rest}"
      end
    end
  end
  
  # Run LaTeX compilation with error recovery
  def compile_latex_with_recovery(latex_code, base_filename, working_dir = "/monadic/data")
    log_file = "#{base_filename}.log"
    tex_file = "#{base_filename}.tex"
    
    # First compilation attempt
    compile_result = compile_latex(latex_code, base_filename, working_dir)
    
    # Check if compilation failed
    if compile_result[:success] == false && File.exist?("#{working_dir}/#{log_file}")
      log_content = File.read("#{working_dir}/#{log_file}")
      errors = analyze_latex_error(log_content)
      
      if errors.any?
        # Try to fix errors
        fixed_code = apply_latex_fixes(latex_code, errors)
        
        if fixed_code != latex_code
          # Save backup
          File.write("#{working_dir}/#{tex_file}.backup", latex_code)
          
          # Try compilation with fixed code
          compile_result = compile_latex(fixed_code, base_filename, working_dir)
          compile_result[:fixes_applied] = true
          compile_result[:errors_fixed] = errors
        end
      end
    end
    
    compile_result
  end
  
  # Basic LaTeX compilation (to be implemented by specific adapters)
  def compile_latex(latex_code, base_filename, working_dir)
    # This method should be overridden by specific implementations
    raise NotImplementedError, "compile_latex must be implemented by the including class"
  end
end