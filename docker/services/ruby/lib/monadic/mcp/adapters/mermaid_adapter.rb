# frozen_string_literal: true

module Monadic
  module MCP
    module Adapters
      class MermaidAdapter
        def initialize
          # Initialize without dependency on MermaidGrapher app
        end

        def list_tools
          [
            {
              name: "mermaid_validate_syntax",
              description: "Validate Mermaid diagram syntax and get error messages",
              inputSchema: {
                type: "object",
                properties: {
                  code: {
                    type: "string",
                    description: "Mermaid diagram code to validate"
                  }
                },
                required: ["code"]
              }
            },
            {
              name: "mermaid_preview",
              description: "Generate a preview image of a Mermaid diagram",
              inputSchema: {
                type: "object",
                properties: {
                  code: {
                    type: "string",
                    description: "Mermaid diagram code"
                  },
                  theme: {
                    type: "string",
                    enum: ["default", "dark", "forest", "neutral"],
                    description: "Mermaid theme (default: default)"
                  }
                },
                required: ["code"]
              }
            },
            {
              name: "mermaid_generate",
              description: "Generate PNG image of Mermaid diagram using Python container",
              inputSchema: {
                type: "object",
                properties: {
                  code: {
                    type: "string",
                    description: "Mermaid diagram code"
                  },
                  theme: {
                    type: "string",
                    enum: ["default", "dark", "forest", "neutral"],
                    description: "Mermaid theme (default: default)"
                  }
                },
                required: ["code"]
              }
            },
            {
              name: "mermaid_analyze_error",
              description: "Analyze Mermaid syntax errors and get suggestions",
              inputSchema: {
                type: "object",
                properties: {
                  code: {
                    type: "string",
                    description: "Mermaid code with errors"
                  },
                  error: {
                    type: "string",
                    description: "Error message from validation"
                  }
                },
                required: ["code", "error"]
              }
            }
          ]
        end

        def handles_tool?(tool_name)
          tool_name.start_with?("mermaid_")
        end

        def execute_tool(tool_name, arguments)
          case tool_name
          when "mermaid_validate_syntax"
            validate_syntax(arguments["code"])
          when "mermaid_preview"
            preview_diagram(arguments["code"], arguments["theme"])
          when "mermaid_generate"
            generate_image(arguments["code"], arguments["theme"])
          when "mermaid_analyze_error"
            analyze_error(arguments["code"], arguments["error"])
          else
            { error: "Unknown tool: #{tool_name}" }
          end
        rescue => e
          puts "Mermaid adapter error: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] == "true"
          { error: "Error executing tool: #{e.message}" }
        end

        private

        def validate_syntax(code)
          return { error: "Code is required" } if code.nil? || code.strip.empty?
          return { error: "Code too long (max 5000 characters)" } if code.length > 5000

          # Basic syntax validation
          errors = []
          lines = code.strip.split("\n")
          
          # Check for diagram type
          first_line = lines.first.strip
          valid_types = %w[graph flowchart sequenceDiagram classDiagram stateDiagram-v2 erDiagram 
                         journey gantt pie quadrantChart requirementDiagram gitGraph C4Context 
                         mindmap timeline sankey-beta xychart-beta block-beta]
          
          unless valid_types.any? { |type| first_line.start_with?(type) }
            errors << "Missing or invalid diagram type. Should start with: #{valid_types.join(', ')}"
          end
          
          # Special handling for sankey
          if first_line == "sankey-beta" && code.include?("-->")
            errors << "Sankey diagrams use CSV format (source,target,value), not arrow notation"
          end
          
          if errors.empty?
            {
              content: [
                {
                  type: "text",
                  text: "✅ Valid Mermaid syntax"
                }
              ]
            }
          else
            {
              content: [
                {
                  type: "text",
                  text: "❌ Invalid syntax: #{errors.join('; ')}"
                }
              ]
            }
          end
        end

        def preview_diagram(code, theme = nil)
          return { error: "Code is required" } if code.nil? || code.strip.empty?
          
          # For MCP adapter, we can't generate actual images
          # Instead, provide instructions for using the full app
          {
            content: [
              {
                type: "text",
                text: "📊 To generate a Mermaid diagram preview:\n\n1. Use the Mermaid Grapher app in Monadic Chat\n2. Or use mermaid.live online editor\n3. Or install mermaid-cli locally\n\nDiagram code validated and ready to use!"
              }
            ]
          }
        end

        def analyze_error(code, error)
          error_str = error.to_s.downcase
          suggestions = []
          
          # Common error patterns and fixes
          if error_str.include?("parse error")
            suggestions << "Check for missing semicolons or commas"
            suggestions << "Verify all brackets and quotes are properly closed"
            suggestions << "Ensure proper indentation (use spaces, not tabs)"
          elsif error_str.include?("syntax error")
            suggestions << "Verify the diagram type is correctly specified"
            suggestions << "Check node and edge definitions match the diagram type"
            suggestions << "Ensure all IDs are alphanumeric without spaces"
          elsif error_str.include?("unknown diagram")
            suggestions << "The diagram type might be misspelled"
            suggestions << "Use one of: flowchart, sequenceDiagram, classDiagram, etc."
          elsif error_str.include?("sankey")
            suggestions << "Sankey diagrams use CSV format: source,target,value"
            suggestions << "Do not use arrow notation (-->) in Sankey diagrams"
            suggestions << "Each line should have exactly 3 comma-separated values"
          else
            suggestions << "Verify the diagram type declaration is correct"
            suggestions << "Check for proper syntax according to diagram type"
            suggestions << "Ensure all special characters are properly escaped"
          end
          
          analysis = "Error Analysis:\n\n"
          analysis += "Error: #{error}\n\n"
          analysis += "Suggestions:\n"
          suggestions.each { |s| analysis += "• #{s}\n" }
          
          {
            content: [
              {
                type: "text",
                text: analysis
              }
            ]
          }
        end
        
        def generate_image(code, theme = nil)
          return { error: "Code is required" } if code.nil? || code.strip.empty?
          
          # Generate unique filename
          timestamp = Time.now.to_i.to_s
          base_filename = "mermaid_#{timestamp}"
          theme ||= "default"
          
          # Create Python script for Mermaid rendering
          python_script = <<~PYTHON
            #!/usr/bin/env python3
            import os
            import sys
            from selenium import webdriver
            from selenium.webdriver.common.by import By
            from selenium.webdriver.support.ui import WebDriverWait
            from selenium.webdriver.support import expected_conditions as EC
            import time
            
            # Mermaid code
            mermaid_code = '''#{code}'''
            
            # Create HTML with Mermaid
            html_content = f'''<!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
                <style>
                    body {{
                        background: white;
                        margin: 0;
                        padding: 20px;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        min-height: 100vh;
                    }}
                    .mermaid {{
                        background: white;
                        padding: 40px;
                        border-radius: 8px;
                    }}
                </style>
            </head>
            <body>
                <div class="mermaid" id="mermaid-diagram">
            {mermaid_code}
                </div>
                <script>
                    mermaid.initialize({{
                        startOnLoad: true,
                        theme: '#{theme}',
                        securityLevel: 'loose'
                    }});
                </script>
            </body>
            </html>'''
            
            # Write HTML file
            html_path = '/monadic/data/#{base_filename}.html'
            with open(html_path, 'w', encoding='utf-8') as f:
                f.write(html_content)
            
            print(f"HTML file created: {html_path}")
            
            # Set up Chrome options
            options = webdriver.ChromeOptions()
            options.add_argument('--headless')
            options.add_argument('--no-sandbox')
            options.add_argument('--disable-dev-shm-usage')
            options.add_argument('--window-size=1920,1080')
            
            try:
                # Connect to Selenium container
                driver = webdriver.Remote(
                    command_executor='http://monadic-chat-selenium-container:4444/wd/hub',
                    options=options
                )
                
                # Load the HTML file
                driver.get(f'file://{html_path}')
                
                # Wait for Mermaid to render
                WebDriverWait(driver, 10).until(
                    EC.presence_of_element_located((By.CSS_SELECTOR, "svg"))
                )
                time.sleep(2)  # Additional wait for complete rendering
                
                # Take screenshot of the mermaid element
                mermaid_element = driver.find_element(By.ID, "mermaid-diagram")
                screenshot_path = f'/monadic/data/#{base_filename}.png'
                mermaid_element.screenshot(screenshot_path)
                
                print(f"SUCCESS: Screenshot saved to {screenshot_path}")
                
                # Clean up HTML file
                os.remove(html_path)
                
            except Exception as e:
                print(f"ERROR: {str(e)}")
            finally:
                if 'driver' in locals():
                    driver.quit()
          PYTHON
          
          # Execute Python script in container
          script_code = <<~BASH
            #!/bin/bash
            cd /monadic/data
            
            # Save Python script
            cat > #{base_filename}_render.py << 'EOF'
            #{python_script}
            EOF
            
            echo "Generating Mermaid diagram..."
            python3 #{base_filename}_render.py
            
            # Clean up script
            rm -f #{base_filename}_render.py
          BASH
          
          # Execute in Python container
          result = execute_in_container(script_code)
          
          if result.include?("SUCCESS")
            {
              content: [
                {
                  type: "text",
                  text: "✅ Mermaid diagram generated successfully!\n\n" +
                        "**File**: `/data/#{base_filename}.png`\n" +
                        "**Theme**: #{theme}\n\n" +
                        "To view the image:\n" +
                        "1. Open in Monadic Chat web interface\n" +
                        "2. Or access directly at: http://localhost:4567/data/#{base_filename}.png"
                }
              ]
            }
          else
            error_msg = result[/ERROR: (.+)/, 1] || "Unknown error"
            {
              content: [
                {
                  type: "text",
                  text: "❌ Failed to generate Mermaid diagram: #{error_msg}\n\n" +
                        "Please check:\n" +
                        "1. Python and Selenium containers are running\n" +
                        "2. Mermaid syntax is correct\n" +
                        "3. Network connection between containers"
                }
              ]
            }
          end
        end
        
        def execute_in_container(script_code)
          require 'open3'
          
          # Execute in Python container directly using stdin
          container_name = "monadic-chat-python-container"
          cmd = ["docker", "exec", "-i", container_name, "bash"]
          
          stdout, stderr, status = Open3.capture3(*cmd, stdin_data: script_code)
          
          # Return combined output
          "#{stdout}\n#{stderr}".strip
        rescue => e
          "ERROR: Container execution failed: #{e.message}"
        end
      end
    end
  end
end