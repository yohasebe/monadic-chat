# frozen_string_literal: true

module Monadic
  module MCP
    module Adapters
      class SyntaxTreeAdapter
        def initialize
          # Initialize without dependency on SyntaxTree app
        end

        def list_tools
          [
            {
              name: "syntax_tree_validate",
              description: "Validate bracket notation for syntax tree generation",
              inputSchema: {
                type: "object",
                properties: {
                  notation: {
                    type: "string",
                    description: "Bracket notation for syntax tree (e.g., [S [NP John] [VP runs]])"
                  }
                },
                required: ["notation"]
              }
            },
            {
              name: "syntax_tree_convert",
              description: "Convert bracket notation to LaTeX tikz-qtree format",
              inputSchema: {
                type: "object",
                properties: {
                  notation: {
                    type: "string",
                    description: "Bracket notation for syntax tree"
                  },
                  language: {
                    type: "string",
                    enum: ["english", "japanese", "chinese", "korean"],
                    description: "Language for CJK support (default: english)"
                  }
                },
                required: ["notation"]
              }
            },
            {
              name: "syntax_tree_generate",
              description: "Generate SVG image of syntax tree using Python container",
              inputSchema: {
                type: "object",
                properties: {
                  notation: {
                    type: "string",
                    description: "Bracket notation for syntax tree"
                  },
                  language: {
                    type: "string",
                    enum: ["english", "japanese", "chinese", "korean"],
                    description: "Language for CJK support (default: english)"
                  }
                },
                required: ["notation"]
              }
            },
            {
              name: "syntax_tree_analyze",
              description: "Analyze syntax tree structure and suggest improvements",
              inputSchema: {
                type: "object",
                properties: {
                  notation: {
                    type: "string",
                    description: "Bracket notation to analyze"
                  }
                },
                required: ["notation"]
              }
            },
            {
              name: "syntax_tree_examples",
              description: "Get examples of syntax trees for different languages",
              inputSchema: {
                type: "object",
                properties: {
                  language: {
                    type: "string",
                    enum: ["english", "japanese", "chinese", "general"],
                    description: "Language for examples"
                  }
                }
              }
            }
          ]
        end

        def handles_tool?(tool_name)
          tool_name.start_with?("syntax_tree_")
        end

        def execute_tool(tool_name, arguments)
          case tool_name
          when "syntax_tree_validate"
            validate_notation(arguments["notation"])
          when "syntax_tree_convert"
            convert_to_latex(arguments["notation"], arguments["language"])
          when "syntax_tree_generate"
            generate_image(arguments["notation"], arguments["language"])
          when "syntax_tree_analyze"
            analyze_structure(arguments["notation"])
          when "syntax_tree_examples"
            get_examples(arguments["language"])
          else
            { error: "Unknown tool: #{tool_name}" }
          end
        rescue => e
          puts "Syntax tree adapter error: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] == "true"
          { error: "Error executing tool: #{e.message}" }
        end

        private

        def validate_notation(notation)
          return { error: "Notation is required" } if notation.nil? || notation.strip.empty?
          return { error: "Notation too long (max 5000 characters)" } if notation.length > 5000

          errors = []
          brackets = 0
          in_terminal = false
          
          # Count brackets and check basic structure
          notation.each_char.with_index do |char, idx|
            case char
            when '['
              brackets += 1
              in_terminal = false
            when ']'
              brackets -= 1
              if brackets < 0
                errors << "Unmatched closing bracket at position #{idx}"
                break
              end
            when ' '
              # Space after opening bracket indicates non-terminal
              if idx > 0 && notation[idx-1] == '['
                in_terminal = false
              end
            end
          end
          
          errors << "#{brackets} unclosed brackets" if brackets > 0
          
          # Check for empty nodes
          if notation.include?("[]")
            errors << "Empty nodes found ([])"
          end
          
          # Check for proper node format
          if notation.scan(/\[[^\[\]]+\]/).empty? && notation.include?("[")
            errors << "No properly formed nodes found"
          end
          
          if errors.empty?
            {
              content: [
                {
                  type: "text",
                  text: "✅ Valid syntax tree notation"
                }
              ]
            }
          else
            {
              content: [
                {
                  type: "text",
                  text: "❌ Invalid notation:\n• #{errors.join("\n• ")}"
                }
              ]
            }
          end
        end

        def convert_to_latex(notation, language = nil)
          return { error: "Notation is required" } if notation.nil? || notation.strip.empty?
          
          # Convert bracket notation to tikz-qtree format
          # Add dots to all nodes for tikz-qtree
          tikz_notation = notation.gsub(/\[([^\s\[\]]+)/) do |match|
            label = $1
            # Wrap labels with apostrophes in braces
            if label.include?("'")
              "[.{#{label}}"
            else
              "[.#{label}"
            end
          end
          
          # Ensure proper spacing
          tikz_notation = tikz_notation.gsub(/(\[\.[^\s\[\]]+)\s+([^\[\]]+)\]/) do
            "#{$1} #{$2.strip} ]"
          end
          
          # Generate LaTeX code
          needs_cjk = ["japanese", "chinese", "korean"].include?(language&.downcase)
          
          latex_template = if needs_cjk
            <<~LATEX
            \\documentclass[tikz,border=10pt]{standalone}
            \\usepackage{CJKutf8}
            \\usepackage{tikz}
            \\usepackage{tikz-qtree}
            \\begin{document}
            \\begin{CJK}{UTF8}{min}
            \\Tree #{tikz_notation}
            \\end{CJK}
            \\end{document}
            LATEX
          else
            <<~LATEX
            \\documentclass[tikz,border=10pt]{standalone}
            \\usepackage{tikz}
            \\usepackage{tikz-qtree}
            \\begin{document}
            \\Tree #{tikz_notation}
            \\end{document}
            LATEX
          end
          
          {
            content: [
              {
                type: "text",
                text: "📊 Converted to LaTeX tikz-qtree format:\n\n```latex\n#{latex_template}```\n\nTo generate an image:\n1. Save as .tex file\n2. Run: latex filename.tex\n3. Convert: dvisvgm filename.dvi -o filename.svg"
              }
            ]
          }
        end

        def analyze_structure(notation)
          return { error: "Notation is required" } if notation.nil? || notation.strip.empty?
          
          analysis = []
          
          # Count nodes
          nodes = notation.scan(/\[([^\s\[\]]+)/)
          non_terminals = []
          terminals = []
          
          # Simple heuristic: if a node has children, it's non-terminal
          notation.scan(/\[([^\s\[\]]+)\s+\[/).each { |match| non_terminals << match[0] }
          
          # Terminals are nodes that appear with content but no child nodes
          notation.scan(/\[([^\s\[\]]+)\s+([^\[\]]+)\]/).each do |match|
            terminals << "#{match[0]} '#{match[1].strip}'"
          end
          
          analysis << "Structure Analysis:"
          analysis << "• Total nodes: #{nodes.length}"
          analysis << "• Non-terminal nodes: #{non_terminals.uniq.length} (#{non_terminals.uniq.join(', ')})"
          analysis << "• Terminal nodes: #{terminals.length}"
          
          # Check for common patterns
          suggestions = []
          
          # Check for redundant nodes
          if notation.include?("[NP [NP") || notation.include?("[VP [VP")
            suggestions << "Consider simplifying redundant parent-child nodes with same labels"
          end
          
          # Check for missing root
          unless notation.strip.start_with?("[S ") || notation.strip.start_with?("[ROOT ")
            suggestions << "Consider adding a root node (S or ROOT) at the top level"
          end
          
          # Check depth
          max_depth = notation.scan(/\[/).length
          if max_depth > 10
            suggestions << "Tree is very deep (#{max_depth} levels). Consider simplifying if possible"
          end
          
          if suggestions.any?
            analysis << "\nSuggestions:"
            suggestions.each { |s| analysis << "• #{s}" }
          end
          
          {
            content: [
              {
                type: "text",
                text: analysis.join("\n")
              }
            ]
          }
        end

        def generate_image(notation, language = nil)
          return { error: "Notation is required" } if notation.nil? || notation.strip.empty?
          
          # Convert bracket notation to tikz-qtree format
          tikz_notation = notation.gsub(/\[([^\s\[\]]+)/) do |match|
            label = $1
            if label.include?("'")
              "[.{#{label}}"
            else
              "[.#{label}"
            end
          end
          
          # Ensure proper spacing
          tikz_notation = tikz_notation.gsub(/(\[\.[^\s\[\]]+)\s+([^\[\]]+)\]/) do
            "#{$1} #{$2.strip} ]"
          end
          
          # Generate unique filename
          timestamp = Time.now.to_i.to_s
          base_filename = "syntree_#{timestamp}"
          
          # Generate LaTeX code
          needs_cjk = ["japanese", "chinese", "korean"].include?(language&.downcase)
          
          latex_code = if needs_cjk
            <<~LATEX
            \\documentclass[tikz,border=10pt]{standalone}
            \\usepackage{CJKutf8}
            \\usepackage{tikz}
            \\usepackage{tikz-qtree}
            \\begin{document}
            \\begin{CJK}{UTF8}{min}
            \\Tree #{tikz_notation}
            \\end{CJK}
            \\end{document}
            LATEX
          else
            <<~LATEX
            \\documentclass[tikz,border=10pt]{standalone}
            \\usepackage{tikz}
            \\usepackage{tikz-qtree}
            \\begin{document}
            \\Tree #{tikz_notation}
            \\end{document}
            LATEX
          end
          
          # Create bash script for execution in Python container
          script_code = <<~BASH
            #!/bin/bash
            cd /monadic/data
            
            # Save LaTeX code to file
            cat > #{base_filename}.tex << 'EOF'
            #{latex_code}
            EOF
            
            echo "Generating syntax tree image..."
            
            # Compile with latex
            latex -interaction=nonstopmode #{base_filename}.tex
            
            if [ -f #{base_filename}.dvi ]; then
              echo "Converting to SVG..."
              dvisvgm --bbox=min --precision=3 #{base_filename}.dvi -o #{base_filename}.svg
              
              if [ -f #{base_filename}.svg ]; then
                echo "SUCCESS: Generated #{base_filename}.svg"
                # Clean up intermediate files
                rm -f #{base_filename}.tex #{base_filename}.dvi #{base_filename}.aux #{base_filename}.log
              else
                echo "ERROR: Failed to convert to SVG"
              fi
            else
              echo "ERROR: LaTeX compilation failed"
              cat #{base_filename}.log 2>/dev/null || echo "No log file found"
            fi
          BASH
          
          # Execute in Python container
          result = execute_in_container(script_code)
          
          if result.include?("SUCCESS")
            {
              content: [
                {
                  type: "text",
                  text: "✅ Syntax tree generated successfully!\n\n" +
                        "**File**: `/data/#{base_filename}.svg`\n" +
                        "**Language**: #{language || 'english'}\n\n" +
                        "To view the image:\n" +
                        "1. Open in Monadic Chat web interface\n" +
                        "2. Or access directly at: http://localhost:4567/data/#{base_filename}.svg"
                }
              ]
            }
          else
            error_msg = result[/ERROR: (.+)/, 1] || "Unknown error"
            {
              content: [
                {
                  type: "text",
                  text: "❌ Failed to generate syntax tree: #{error_msg}\n\n" +
                        "Please check:\n" +
                        "1. Python container is running\n" +
                        "2. LaTeX packages are installed\n" +
                        "3. Bracket notation syntax is correct"
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
        
        def get_examples(language = nil)
          examples = {
            "english" => [
              {
                description: "Simple sentence",
                notation: "[S [NP [Det The] [N cat]] [VP [V sits] [PP [P on] [NP [Det the] [N mat]]]]]",
                sentence: "The cat sits on the mat"
              },
              {
                description: "Question",
                notation: "[S [Aux Did] [NP [N John]] [VP [V eat] [NP [Det the] [N apple]]]]",
                sentence: "Did John eat the apple?"
              },
              {
                description: "Complex noun phrase",
                notation: "[NP [Det The] [AdjP [Adv very] [Adj tall]] [N man] [PP [P with] [NP [Det a] [N hat]]]]",
                sentence: "The very tall man with a hat"
              }
            ],
            "japanese" => [
              {
                description: "Basic sentence",
                notation: "[S [NP [N 猫が]] [VP [NP [N 魚を]] [V 食べた]]]",
                sentence: "猫が魚を食べた (The cat ate fish)"
              },
              {
                description: "Complex sentence",
                notation: "[S [NP [S [NP [N 太郎が]] [VP [V 書いた]]] [N 本を]] [NP [N 花子が]] [VP [V 読んだ]]]",
                sentence: "太郎が書いた本を花子が読んだ"
              }
            ],
            "chinese" => [
              {
                description: "Simple sentence",
                notation: "[S [NP [N 我]] [VP [V 喜欢] [NP [N 中文]]]]",
                sentence: "我喜欢中文 (I like Chinese)"
              }
            ],
            "general" => [
              {
                description: "Binary branching",
                notation: "[S [NP X] [VP [V Y] [NP Z]]]",
                sentence: "General X-bar structure"
              },
              {
                description: "Coordination",
                notation: "[XP [XP A] [Conj and] [XP B]]",
                sentence: "Coordinated structure"
              }
            ]
          }
          
          selected = examples[language&.downcase] || examples["general"]
          
          output = "## Syntax Tree Examples"
          output += " (#{language.capitalize})" if language
          output += "\n\n"
          
          selected.each do |example|
            output += "### #{example[:description]}\n"
            output += "Sentence: #{example[:sentence]}\n"
            output += "```\n#{example[:notation]}\n```\n\n"
          end
          
          output += "Use these as templates for creating your own syntax trees!"
          
          {
            content: [
              {
                type: "text",
                text: output
              }
            ]
          }
        end
      end
    end
  end
end