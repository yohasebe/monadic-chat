require 'cgi'

class SyntaxTreeOpenAI < MonadicApp
  include OpenAIHelper


  def render_syntax_tree(bracket_notation:, language:)
    return "Error: bracket notation is required." if bracket_notation.to_s.empty?

    timestamp = Time.now.to_i.to_s
    base_filename = "syntree_#{timestamp}"
    
    # Convert bracket notation to LaTeX code
    latex_code = generate_latex_syntax_tree(bracket_notation, language)
    
    # Create a shell script to run LaTeX and convert to SVG
    script_code = <<~BASH
      #!/bin/bash
      cd /monadic/data
      
      # Check if LaTeX is installed, if not, install it
      if ! command -v pdflatex >/dev/null 2>&1; then
        echo "LaTeX not found. Installing texlive packages..."
        apt-get update
        apt-get install -y --no-install-recommends texlive-latex-base texlive-latex-extra texlive-pictures texlive-xetex texlive-lang-cjk pdf2svg
        echo "LaTeX installation completed."
      fi
      
      # Check LaTeX installation
      echo "Checking for LaTeX installation..."
      which pdflatex || echo "pdflatex not found in PATH"
      which xelatex || echo "xelatex not found in PATH"
      
      # Save LaTeX code to file
      cat > #{base_filename}.tex << 'EOF'
      #{latex_code}
      EOF
      
      # Debug: Show the generated LaTeX code
      echo "Generated LaTeX code:"
      cat #{base_filename}.tex
      echo "---"
      
      # Always use latex + dvisvgm for editable SVG (works for both CJK and non-CJK)
      echo "Running latex to generate DVI..."
      latex -interaction=nonstopmode #{base_filename}.tex
      
      if [ -f #{base_filename}.dvi ]; then
        echo "DVI created successfully, converting to editable SVG with dvisvgm..."
        
        # Check if we have CJK content
        if grep -q "CJKutf8" #{base_filename}.tex; then
          echo "CJK content detected, using appropriate dvisvgm options..."
          # For CJK, use --no-merge to keep characters separate
          # This allows individual character editing
          # Use --bbox=min for tightest bounds and --no-styles to avoid embedded CSS
          dvisvgm --no-merge --font-format=woff --bbox=min --precision=5 --no-styles #{base_filename}.dvi -o #{base_filename}.svg
        else
          # For non-CJK, standard conversion with tight bounds
          dvisvgm --font-format=woff --bbox=min --precision=5 --no-styles #{base_filename}.dvi -o #{base_filename}.svg
        fi
        
        if [ -f #{base_filename}.svg ]; then
          echo "Successfully generated editable SVG!"
          echo "Tree structure preserved with editable text elements."
          
          # Show statistics
          echo "SVG statistics:"
          echo "- Path elements (lines): $(grep -c '<path' #{base_filename}.svg)"
          echo "- Text elements: $(grep -c '<text' #{base_filename}.svg)"
        else
          echo "Error: SVG conversion failed"
          exit 1
        fi
      else
        echo "Error: DVI generation failed"
        echo "LaTeX log:"
        cat #{base_filename}.log 2>/dev/null || echo "No log file found"
        exit 1
      fi
    BASH
    
    # Execute the script
    run_result = run_code(
      code: script_code,
      command: "bash",
      extension: "sh"
    )
    
    "#{base_filename}.svg"
  end

  private

  def generate_latex_syntax_tree(bracket_notation, language)
    # Generate LaTeX code for syntax tree using tikz-qtree package
    # Use standalone class with zero border for no margins
    
    # Convert bracket notation to qtree format
    qtree_notation = convert_to_qtree(bracket_notation)
    
    # Check if we need CJK support
    needs_cjk = ["japanese", "chinese", "korean", "ja", "zh", "ko"].include?(language.to_s.downcase)
    
    if needs_cjk
      # Use LaTeX with CJKutf8 and dvips driver for proper line rendering
      # This ensures both CJK text and tree lines are properly generated
      <<~LATEX
        \\documentclass[dvips,tikz,border=0pt]{standalone}
        \\usepackage{CJKutf8}
        \\usepackage{tikz}
        \\usepackage{tikz-qtree}
        \\begin{document}
        \\begin{CJK}{UTF8}{min}
        \\begin{tikzpicture}[baseline]
        \\Tree #{qtree_notation}
        \\end{tikzpicture}
        \\end{CJK}
        \\end{document}
      LATEX
    else
      # Use standard LaTeX for non-CJK languages
      <<~LATEX
        \\documentclass[tikz,border=0pt]{standalone}
        \\usepackage{tikz}
        \\usepackage{tikz-qtree}
        \\begin{document}
        \\begin{tikzpicture}[baseline]
        \\Tree #{qtree_notation}
        \\end{tikzpicture}
        \\end{document}
      LATEX
    end
  end
  
  def convert_to_qtree(bracket_notation)
    # Convert bracket notation to qtree format
    # qtree format: [.S [.NP [.Det the ] [.N cat ]] [.VP [.V sits ]]]
    
    # Process the bracket notation recursively to add dots before all node labels
    # This is necessary because tikz-qtree requires dots on all nodes
    
    # First, add dots to all nodes (both terminal and non-terminal)
    result = bracket_notation.gsub(/\[(\w+)/) do
      "[.#{$1}"
    end
    
    # Ensure proper spacing after terminal nodes
    result = result.gsub(/(\[\.[\w]+)\s+([^\[\]]+)\]/) do
      "#{$1} #{$2.strip} ]"
    end
    
    result
  end

  def parse_bracket_notation(notation)
    # Simple bracket notation parser
    # Parse formats like "[S [NP [PRP He]] [VP [VBZ is] [NP [DT the] [NN one]]]]"
    
    notation = notation.strip
    return nil if notation.empty?
    
    # Remove outer brackets
    if notation.start_with?('[') && notation.end_with?(']')
      inner = notation[1..-2]
      
      # Separate label and children
      if match = inner.match(/^(\w+)\s*(.*)$/)
        label = match[1]
        rest = match[2]
        
        children = []
        if !rest.empty? && rest.include?('[')
          # Parse children
          children = parse_children(rest)
        elsif !rest.empty?
          # Terminal node
          return { label: label, value: rest.strip, children: [] }
        end
        
        return { label: label, children: children }
      end
    end
    
    { label: notation, children: [] }
  end

  def parse_children(text)
    children = []
    depth = 0
    current = ""
    
    text.each_char do |char|
      if char == '['
        depth += 1
      elsif char == ']'
        depth -= 1
      end
      
      current += char
      
      if depth == 0 && !current.strip.empty?
        child = parse_bracket_notation(current.strip)
        children << child if child
        current = ""
      end
    end
    
    children
  end

  def draw_tree_node(node, x, y, available_width, level = 0)
    return "" unless node
    
    svg_elements = []
    
    # Draw node
    node_width = 60
    node_height = 30
    
    svg_elements << %Q{<rect x="#{x - node_width/2}" y="#{y}" width="#{node_width}" height="#{node_height}" class="node" rx="5"/>}
    
    # Draw label
    label_text = node[:value] || node[:label]
    svg_elements << %Q{<text x="#{x}" y="#{y + 20}" class="label">#{CGI.escapeHTML(label_text)}</text>}
    
    # Draw children
    if node[:children] && !node[:children].empty?
      child_count = node[:children].size
      child_spacing = available_width / (child_count + 1)
      start_x = x - available_width/2
      
      node[:children].each_with_index do |child, index|
        child_x = start_x + child_spacing * (index + 1)
        child_y = y + 80
        
        # Draw edge
        svg_elements << %Q{<line x1="#{x}" y1="#{y + node_height}" x2="#{child_x}" y2="#{child_y}" class="edge"/>}
        
        # Recursively draw child node
        svg_elements << draw_tree_node(child, child_x, child_y, child_spacing * 0.8, level + 1)
      end
    end
    
    svg_elements.join("\n")
  end
end

# Claude version
class SyntaxTreeClaude < MonadicApp
  include ClaudeHelper

  def render_syntax_tree(bracket_notation:, language:)
    SyntaxTreeOpenAI.new.render_syntax_tree(
      bracket_notation: bracket_notation,
      language: language
    )
  end
end

