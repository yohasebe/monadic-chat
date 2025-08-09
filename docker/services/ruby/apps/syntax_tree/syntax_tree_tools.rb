require 'cgi'
require_relative '../../lib/monadic/adapters/latex_helper'

class SyntaxTreeOpenAI < MonadicApp
  include OpenAIHelper
  include LatexHelper


  def render_syntax_tree(bracket_notation:, language:)
    return "Error: bracket notation is required." if bracket_notation.to_s.empty?

    # Debug: Log the input bracket notation to check for stray quotes
    if CONFIG["EXTRA_LOGGING"]
      DebugHelper.debug("Syntax Tree input bracket notation: #{bracket_notation.inspect}", category: :app, level: :info)
    end
    
    # Clean up any stray quotes that might have been added
    # Remove quotes around terminals that aren't meant to be there
    cleaned_notation = bracket_notation.gsub(/\[\s*"([^"\[\]]+)"\s*\]/, '[\1]')
    
    # CRITICAL: Remove trailing spaces and extra brackets that cause LaTeX issues
    # This handles cases like "[T た]] ]" where there's an extra bracket at the end
    cleaned_notation = cleaned_notation.strip
    
    # Balance brackets - count and remove excess closing brackets
    open_count = cleaned_notation.count('[')
    close_count = cleaned_notation.count(']')
    if close_count > open_count
      # Remove excess closing brackets from the end
      excess = close_count - open_count
      cleaned_notation = cleaned_notation.gsub(/\s*\]{#{excess}}\s*$/, '')
    end
    
    timestamp = Time.now.to_i.to_s
    base_filename = "syntree_#{timestamp}"
    
    # Convert bracket notation to LaTeX code (use cleaned notation)
    latex_code = generate_latex_syntax_tree(cleaned_notation, language)
    
    # Create a shell script to run LaTeX and convert to SVG with error recovery
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
      
      # Check if compilation failed and try to recover
      if [ ! -f #{base_filename}.dvi ] && [ -f #{base_filename}.log ]; then
        echo "LaTeX compilation failed. Attempting automatic recovery..."
        
        # Save original for backup
        cp #{base_filename}.tex #{base_filename}.tex.original
        
        # Check for common tikz-qtree errors
        if grep -q "Paragraph ended before.*was complete" #{base_filename}.log; then
          echo "Detected unmatched delimiter error. Attempting to fix..."
          # Try to fix missing dots in node labels
          perl -i -pe 's/\[([^\s\[\]\.]+)(\s+[^\[\]]+\])/[.$1$2/g' #{base_filename}.tex
          echo "Applied qtree format fixes."
        fi
        
        # Check for missing escape characters
        if grep -q "Missing \\$ inserted" #{base_filename}.log || grep -q "Extra }, or forgotten \\$" #{base_filename}.log; then
          echo "Detected unescaped special characters. Already handled in preprocessing."
        fi
        
        # Show diff if any changes were made
        if ! diff -q #{base_filename}.tex.original #{base_filename}.tex >/dev/null 2>&1; then
          echo "Changes applied:"
          diff -u #{base_filename}.tex.original #{base_filename}.tex || true
          
          # Retry compilation
          echo "Retrying LaTeX compilation..."
          latex -interaction=nonstopmode #{base_filename}.tex
        fi
      fi
      
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
    
    # Check if the result contains error messages
    # run_result should be a string, but handle other types gracefully
    if run_result.is_a?(String) && (run_result.include?("Error:") || run_result.include?("timed out"))
      return "Error generating syntax tree: #{run_result}"
    end
    
    # Check if SVG file was created
    svg_path = File.join(File.expand_path(File.join(Dir.home, "monadic", "data")), "#{base_filename}.svg")
    unless File.exist?(svg_path)
      return "Error: Syntax tree SVG was not generated. Please check the bracket notation format."
    end
    
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
    
    # First, simplify redundant parent-child structures
    simplified_notation = simplify_redundant_nodes(bracket_notation)
    
    # Then, escape LaTeX special characters in the entire notation
    escaped_notation = escape_latex(simplified_notation)
    
    # Fix separated apostrophes before processing
    # Handle cases where V' is written as "V '" with a space
    # Also handle double apostrophes that might be interpreted as quotes
    escaped_notation = escaped_notation.gsub(/\[(\w+)\s+(['''])([\s\[\]])/) do
      "[#{$1}#{$2}#{$3}"
    end
    
    # IMPORTANT: Handle double apostrophes that LaTeX interprets as quotes
    # Replace '' with single ' to avoid quote rendering
    escaped_notation = escaped_notation.gsub(/(\w)''/, '\1\'')
    escaped_notation = escaped_notation.gsub(/(\w)''/, '\1\'')  # Smart quotes version
    
    # Also remove any standalone quotes that might appear
    escaped_notation = escaped_notation.gsub(/\[\s*"\s*\]/, '[]')  # Remove lone quotes in brackets
    escaped_notation = escaped_notation.gsub(/\s+""\s+/, ' ')      # Remove empty quotes
    
    # Convert underscores to spaces in terminal nodes (leaf nodes)
    # This allows "was_raced" to be displayed as "was raced" in the SVG
    escaped_notation = escaped_notation.gsub(/(\s)([^\[\]]+?)(\s*\])/) do |match|
      prefix = $1
      content = $2
      suffix = $3
      # Only convert underscores in terminal nodes (not in category labels)
      if content !~ /\[/ && content !~ /\]/
        content = content.gsub('_', ' ')
      end
      "#{prefix}#{content}#{suffix}"
    end
    
    # Add dots to all nodes (both terminal and non-terminal)
    # Updated regex to handle node labels with apostrophes and other characters
    result = escaped_notation.gsub(/\[([^\s\[\]]+)/) do |match|
      label = $1
      # Handle prime notation (X', N', V', etc.) for LaTeX
      # tikz-qtree handles prime notation directly without special escaping
      # Just ensure we use the correct prime symbol
      if label.include?("'") || label.include?("'") || label.include?("'") || label.include?("'")
        # Replace various apostrophe types with standard apostrophe for consistency
        # tikz-qtree will render this correctly as a prime symbol
        latex_label = label.gsub(/['''''']/, "'")
        "[.#{latex_label}"
      else
        "[.#{label}"
      end
    end
    
    # Ensure proper spacing after terminal nodes and remove any stray quotes
    result = result.gsub(/(\[\.[^\s\[\]]+)\s+([^\[\]]+)\]/) do
      node_label = $1
      terminal_content = $2.strip
      # Remove any quotes that might have been accidentally added
      terminal_content = terminal_content.gsub(/^["']|["']$/, '')
      "#{node_label} #{terminal_content} ]"
    end
    
    result
  end
  
  def simplify_redundant_nodes(notation)
    # Simplify redundant parent-child structures where a parent has only one child with the same category
    # For example: [NP [NP ...]] becomes [NP ...]
    
    # Parse the notation into a tree structure
    tree = parse_s_expression(notation)
    
    # Simplify the tree
    simplified_tree = simplify_tree(tree)
    
    # Convert back to S-expression
    tree_to_s_expression(simplified_tree)
  end
  
  def parse_s_expression(expr)
    # Remove extra whitespace and normalize
    expr = expr.gsub(/\s+/, ' ').strip
    
    # Parse recursively
    parse_s_expression_helper(expr)[0]
  end
  
  def parse_s_expression_helper(expr)
    expr = expr.strip
    return [nil, expr] if expr.empty?
    
    if expr[0] == '['
      # Find the matching closing bracket
      depth = 0
      i = 0
      expr.each_char.with_index do |char, idx|
        depth += 1 if char == '['
        depth -= 1 if char == ']'
        if depth == 0
          i = idx
          break
        end
      end
      
      inner = expr[1...i].strip
      rest = expr[(i+1)..-1].strip
      
      # Parse the inner content
      if match = inner.match(/^(\w+)\s*(.*)$/)
        label = match[1]
        remaining = match[2]
        
        children = []
        while remaining && !remaining.empty?
          if remaining[0] == '['
            child, remaining = parse_s_expression_helper(remaining)
            children << child if child
          else
            # Terminal node - find the next bracket or end
            next_bracket = remaining.index('[') || remaining.length
            terminal_text = remaining[0...next_bracket].strip
            remaining = remaining[next_bracket..-1] || ""
            unless terminal_text.empty?
              children << { label: terminal_text, children: [] }
            end
          end
        end
        
        return [{ label: label, children: children }, rest]
      end
    else
      # Terminal value
      next_bracket = expr.index('[') || expr.length
      value = expr[0...next_bracket].strip
      rest = expr[next_bracket..-1] || ""
      return [{ label: value, children: [] }, rest] unless value.empty?
    end
    
    [nil, ""]
  end
  
  def simplify_tree(node)
    return node unless node && node[:children]
    
    # First, recursively simplify all children
    simplified_children = node[:children].map { |child| simplify_tree(child) }
    
    # Check if this node has exactly one child with the same label
    if simplified_children.length == 1 && 
       simplified_children[0][:label] == node[:label] &&
       simplified_children[0][:children] && 
       !simplified_children[0][:children].empty?
      # Replace this node with its child's children
      return { label: node[:label], children: simplified_children[0][:children] }
    end
    
    { label: node[:label], children: simplified_children }
  end
  
  def tree_to_s_expression(node)
    return "" unless node
    
    if node[:children] && !node[:children].empty?
      children_str = node[:children].map { |child| tree_to_s_expression(child) }.join(' ')
      "[#{node[:label]} #{children_str}]"
    else
      node[:label]
    end
  end
  
  # Note: escape_latex method is now provided by LatexHelper module

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
  include LatexHelper

  def render_syntax_tree(bracket_notation:, language:)
    SyntaxTreeOpenAI.new.render_syntax_tree(
      bracket_notation: bracket_notation,
      language: language
    )
  end
end

