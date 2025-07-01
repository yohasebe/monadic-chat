require_relative '../../lib/monadic/utils/environment'

class MermaidGrapher < MonadicApp
  def validate_mermaid_syntax(code:)
    raise ArgumentError, "Code cannot be empty" if code.to_s.strip.empty?
    
    # Try Selenium-based validation first
    begin
      actual_validation = validate_with_mermaid_cli(code)
      # If Selenium validation worked (regardless of result), return it
      return actual_validation
    rescue => e
      # If Selenium failed, fall back to static validation
      puts "Selenium validation failed: #{e.message}, falling back to static validation"
    end
    
    # Fallback to static validation
    static_validation(code)
  rescue StandardError => e
    { error: "Validation failed: #{e.message}" }
  end
  
  def preview_mermaid(code:)
    timestamp = Time.now.to_i
    html_filename = "mermaid_preview_#{timestamp}.html"
    screenshot_filename = "mermaid_preview_#{timestamp}.png"
    
    # Determine correct path based on environment
    shared_volume = Monadic::Utils::Environment.shared_volume
    
    html_path = File.join(shared_volume, html_filename)
    screenshot_path = File.join(shared_volume, screenshot_filename)
    
    # Create HTML with Mermaid.js
    html_content = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <style>
          body { 
            background: transparent;
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
          }
          .mermaid { 
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
          }
        </style>
      </head>
      <body>
        <div class="mermaid">
#{code}
        </div>
        <script>
          mermaid.initialize({ 
            startOnLoad: true,
            theme: 'default',
            securityLevel: 'loose'
          });
        </script>
      </body>
      </html>
    HTML
    
    # Write HTML file
    File.write(html_path, html_content)
    
    # Use Selenium to take screenshot
    command = <<~CMD
      bash -c 'cd /monadic/scripts && python -c "
import time
from selenium import webdriver
from selenium.webdriver.common.by import By

options = webdriver.ChromeOptions()
options.add_argument(\\"--headless\\")
options.add_argument(\\"--no-sandbox\\")
options.add_argument(\\"--disable-dev-shm-usage\\")
options.add_argument(\\"--window-size=1920,1080\\")

driver = webdriver.Remote(
    command_executor=\\"http://monadic-chat-selenium-container:4444/wd/hub\\",
    options=options
)

try:
    driver.get(\\"file:///monadic/data/#{html_filename}\\")
    time.sleep(3)  # Wait for mermaid to render
    
    # Find the mermaid element
    mermaid_element = driver.find_element(By.CLASS_NAME, \\"mermaid\\")
    
    # Take screenshot of just the mermaid element
    mermaid_element.screenshot(\\"/monadic/data/#{screenshot_filename}\\")
    print(\\"SUCCESS: Screenshot saved\\")
    
except Exception as e:
    print(f\\"ERROR: {str(e)}\\")
    
finally:
    driver.quit()
"'
    CMD
    
    result = run_bash_command(command: command)
    
    # Clean up HTML file
    File.delete(html_path) if File.exist?(html_path)
    
    # run_bash_command returns a string
    if result.is_a?(String) && result.include?("SUCCESS") && File.exist?(screenshot_path)
      { 
        success: true, 
        filename: screenshot_filename,
        message: "Preview image saved as '#{screenshot_filename}' in the shared folder"
      }
    else
      error_match = result.to_s.match(/ERROR: (.+)/)
      error_msg = error_match ? error_match[1] : "Failed to generate preview"
      { 
        success: false, 
        error: error_msg,
        suggestion: "Check the mermaid syntax and try again"
      }
    end
  rescue StandardError => e
    { success: false, error: "Preview generation failed: #{e.message}" }
  end
  
  def analyze_mermaid_error(code:, error:)
    error_str = error.to_s.downcase
    suggestions = []
    
    # Common error patterns and their fixes
    error_patterns = {
      "parse error" => [
        "Check for missing semicolons or commas",
        "Verify all brackets and quotes are properly closed",
        "Ensure proper indentation (use spaces, not tabs)"
      ],
      "syntax error" => [
        "Verify the diagram type is correctly specified",
        "Check node and edge definitions match the diagram type",
        "Ensure all IDs are alphanumeric without spaces"
      ],
      "unknown diagram" => [
        "The diagram type might be misspelled",
        "Use one of: flowchart, sequenceDiagram, classDiagram, etc.",
        "Some diagram types require specific suffixes (e.g., stateDiagram-v2)"
      ],
      "invalid" => [
        "Check for special characters in node IDs",
        "Ensure labels with spaces are quoted",
        "Verify arrow syntax matches diagram type"
      ],
      "sankey" => [
        "Sankey diagrams use CSV format: source,target,value",
        "Do not use arrow notation (-->) in Sankey diagrams",
        "Each line should have exactly 3 comma-separated values"
      ]
    }
    
    # Find matching patterns and collect suggestions
    error_patterns.each do |pattern, fixes|
      if error_str.include?(pattern)
        suggestions.concat(fixes)
      end
    end
    
    # Add general suggestions if no specific match
    if suggestions.empty?
      suggestions = [
        "Verify the diagram type declaration is correct",
        "Check for proper syntax according to diagram type",
        "Ensure all special characters are properly escaped"
      ]
    end
    
    { 
      error: error,
      suggestions: suggestions,
      quick_fixes: generate_quick_fixes(code, error)
    }
  end
  
  def fetch_mermaid_docs(diagram_type:)
    # Map common names to documentation URLs
    doc_urls = {
      "flowchart" => "https://mermaid.js.org/syntax/flowchart.html",
      "sequence" => "https://mermaid.js.org/syntax/sequenceDiagram.html",
      "class" => "https://mermaid.js.org/syntax/classDiagram.html",
      "state" => "https://mermaid.js.org/syntax/stateDiagram.html",
      "er" => "https://mermaid.js.org/syntax/entityRelationshipDiagram.html",
      "gantt" => "https://mermaid.js.org/syntax/gantt.html",
      "pie" => "https://mermaid.js.org/syntax/pie.html",
      "sankey" => "https://mermaid.js.org/syntax/sankey.html",
      "mindmap" => "https://mermaid.js.org/syntax/mindmap.html"
    }
    
    url = doc_urls[diagram_type.downcase] || "https://mermaid.js.org/intro/"
    
    {
      documentation_url: url,
      hint: "Use websearch_agent to fetch the latest syntax from this URL"
    }
  end
  
  private
  
  def validate_with_mermaid_cli(code)
    # Use Selenium to validate Mermaid diagram
    timestamp = Time.now.to_i
    html_filename = "mermaid_test_#{timestamp}.html"
    
    # Determine correct path based on environment
    shared_volume = Monadic::Utils::Environment.shared_volume
    
    html_path = File.join(shared_volume, html_filename)
    
    # Create HTML with Mermaid.js
    html_content = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <style>
          body { 
            background: #1e1e1e; 
            display: flex; 
            justify-content: center; 
            align-items: center; 
            min-height: 100vh; 
            margin: 0;
          }
          #error { 
            color: red; 
            font-family: monospace; 
            white-space: pre-wrap;
            padding: 20px;
          }
          .mermaid { 
            background: white; 
            padding: 20px; 
            border-radius: 8px;
          }
        </style>
      </head>
      <body>
        <div id="error"></div>
        <div class="mermaid">
#{code}
        </div>
        <script>
          mermaid.initialize({ 
            startOnLoad: true,
            theme: 'default',
            securityLevel: 'loose'
          });
          
          // Capture any errors
          window.addEventListener('error', function(e) {
            document.getElementById('error').textContent = 'Error: ' + e.message;
          });
          
          // Also catch mermaid specific errors
          mermaid.parseError = function(err, hash) {
            document.getElementById('error').textContent = 'Mermaid Error: ' + err;
          };
        </script>
      </body>
      </html>
    HTML
    
    # Write HTML file
    File.write(html_path, html_content)
    
    # Use Selenium to check for errors
    command = <<~CMD
      bash -c 'cd /monadic/scripts && python -c "
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

options = webdriver.ChromeOptions()
options.add_argument(\\"--headless\\")
options.add_argument(\\"--no-sandbox\\")
options.add_argument(\\"--disable-dev-shm-usage\\")

driver = webdriver.Remote(
    command_executor=\\"http://monadic-chat-selenium-container:4444/wd/hub\\",
    options=options
)

try:
    driver.get(\\"file:///monadic/data/#{html_filename}\\")
    time.sleep(2)  # Wait for mermaid to render
    
    # Check for errors
    error_element = driver.find_element(By.ID, \\"error\\")
    error_text = error_element.text.strip()
    
    if error_text:
        print(\\"ERROR: \\" + error_text)
    else:
        # Check if mermaid diagram was rendered
        svg_elements = driver.find_elements(By.TAG_NAME, \\"svg\\")
        if svg_elements:
            print(\\"SUCCESS: Diagram rendered successfully\\")
        else:
            print(\\"ERROR: No SVG element found - diagram may have failed to render\\")
            
finally:
    driver.quit()
"'
    CMD
    
    result = run_bash_command(command: command)
    
    # Clean up HTML file
    File.delete(html_path) if File.exist?(html_path)
    
    # run_bash_command returns a string, not a hash
    if result.is_a?(String)
      if result.include?("SUCCESS")
        { 
          valid: true, 
          message: "Diagram validated successfully with Selenium and Mermaid.js" 
        }
      else
        error_match = result.match(/ERROR: (.+)/)
        error_msg = error_match ? error_match[1] : "Unknown validation error"
        { 
          valid: false, 
          errors: [error_msg]
        }
      end
    else
      { 
        valid: false, 
        errors: ["Selenium validation failed: #{result}"]
      }
    end
  rescue StandardError => e
    raise e  # Re-raise to be caught by validate_mermaid_syntax
  end
  
  def static_validation(code)
    errors = []
    lines = code.strip.split("\n")
    
    # Check for diagram type declaration
    first_line = lines.first.strip
    valid_types = %w[graph flowchart sequenceDiagram classDiagram stateDiagram-v2 erDiagram 
                     journey gantt pie quadrantChart requirementDiagram gitGraph C4Context 
                     mindmap timeline sankey-beta xychart-beta block-beta packet-beta 
                     kanban architecture-beta]
    
    unless valid_types.any? { |type| first_line.start_with?(type) }
      errors << "Missing or invalid diagram type declaration. Should start with one of: #{valid_types.join(', ')}"
    end
    
    # Special handling for sankey-beta
    if first_line == "sankey-beta"
      validate_sankey_syntax(lines[1..-1], errors)
    else
      validate_general_syntax(lines, errors)
    end
    
    # Check for balanced brackets
    check_balanced_brackets(code, errors)
    
    if errors.empty?
      { valid: true, message: "Static syntax validation passed" }
    else
      { valid: false, errors: errors }
    end
  end
  
  def validate_sankey_syntax(lines, errors)
    lines.each_with_index do |line, index|
      next if line.strip.empty? || line.strip.start_with?("%%")
      
      # Check for arrow notation in sankey (common error)
      if line.include?("-->") || line.include?("->")
        errors << "Line #{index + 2}: Sankey diagrams use CSV format (source,target,value), not arrow notation. Example: 'Japan,USA,300'"
        
        # Try to extract what they might have meant
        if match = line.match(/(\w+)(?:\[[^\]]+\])?\s*(\d+)?\s*-->\s*(\w+)(?:\[[^\]]+\])?/)
          source = match[1]
          value = match[2] || line[/\d+/] || "100"
          target = match[3]
          errors << "  Suggested fix: #{source},#{target},#{value}"
        end
      elsif !line.include?(",")
        errors << "Line #{index + 2}: Missing commas. Sankey format is: source,target,value"
      else
        # Check CSV format
        parts = line.split(",").map(&:strip)
        if parts.length != 3
          errors << "Line #{index + 2}: Should have exactly 3 comma-separated values: source,target,value. Found #{parts.length} values."
        elsif parts[2] && !parts[2].match?(/^\d+(\.\d+)?$/)
          errors << "Line #{index + 2}: Third value should be a number, got: '#{parts[2]}'"
        end
      end
    end
  end
  
  def validate_general_syntax(lines, errors)
    lines.each_with_index do |line, index|
      # Skip empty lines and comments
      next if line.strip.empty? || line.strip.start_with?("%%")
      
      # Check for tabs (should use spaces)
      if line.include?("\t")
        errors << "Line #{index + 1}: Use spaces instead of tabs for indentation"
      end
      
      # Check for unescaped brackets in labels
      if line =~ /[^\\][\[\]()]/ && line.include?(":")
        errors << "Line #{index + 1}: Brackets and parentheses in labels should be escaped with backslash"
      end
    end
  end
  
  def check_balanced_brackets(code, errors)
    # Remove escaped brackets and brackets in strings
    cleaned_code = code.gsub(/\\[\[\](){}]/, "").gsub(/"[^"]*"/, "")
    
    brackets = {
      "{" => "}",
      "[" => "]",
      "(" => ")"
    }
    
    stack = []
    cleaned_code.each_char do |char|
      if brackets.keys.include?(char)
        stack.push(char)
      elsif brackets.values.include?(char)
        expected = brackets.key(char)
        if stack.empty? || stack.pop != expected
          errors << "Unmatched closing bracket: #{char}"
          return
        end
      end
    end
    
    unless stack.empty?
      errors << "Unclosed brackets: #{stack.join(', ')}"
    end
  end
  
  def generate_quick_fixes(code, error)
    fixes = []
    error_str = error.to_s
    
    # Auto-fix suggestions based on error type
    if code.strip.start_with?("sankey-beta") && code.include?("-->")
      lines = code.split("\n")
      fixed_lines = lines.map do |line|
        if line.strip == "sankey-beta" || line.strip.empty? || line.strip.start_with?("%%")
          line
        else
          # Convert arrow notation to CSV
          # Pattern: source[Label] value --> target[Label]
          if match = line.match(/(\w+)(?:\[[^\]]+\])?\s*(\d+)?\s*-->\s*(\w+)(?:\[[^\]]+\])?/)
            source = match[1]
            value = match[2] || line[/\d+/] || "100"
            target = match[3]
            "#{source},#{target},#{value}"
          else
            line
          end
        end
      end
      
      fixes << {
        description: "Convert Sankey arrow notation to CSV format",
        fixed_code: fixed_lines.join("\n")
      }
    end
    
    if error_str.include?("tab")
      fixed_code = code.gsub("\t", "  ")
      fixes << {
        description: "Replace tabs with spaces",
        fixed_code: fixed_code
      }
    end
    
    fixes
  end
end
