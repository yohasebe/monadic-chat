require 'cgi'

class ConceptVisualizerOpenAI < MonadicApp
  include OpenAIHelper

  def generate_concept_diagram(diagram_type:, tikz_code:, title:, language: "english")
    return "Error: TikZ code is required." if tikz_code.to_s.empty?
    return "Error: diagram type is required." if diagram_type.to_s.empty?
    
    # Decode HTML entities in TikZ code
    tikz_code = decode_html_entities(tikz_code)
    
    # Check if TikZ code is a complete LaTeX document or just TikZ code
    is_complete_document = tikz_code.include?("\\documentclass") && tikz_code.include?("\\begin{document}")
    
    # Ensure TikZ code contains actual TikZ commands
    unless tikz_code.include?("\\begin{tikzpicture}") || tikz_code.include?("\\tikz") || tikz_code.include?("\\Tree")
      return "Error: Invalid TikZ code. Code must contain TikZ commands."
    end

    timestamp = Time.now.to_i.to_s
    sanitized_type = diagram_type.gsub(/[^a-zA-Z0-9]/, '_').downcase
    base_filename = "concept_#{sanitized_type}_#{timestamp}"
    
    # Generate complete LaTeX document with TikZ code
    if is_complete_document
      # If already a complete document, extract just the TikZ content
      tikz_content = extract_tikz_content(tikz_code)
      latex_code = generate_complete_latex(tikz_content, language, diagram_type)
    else
      # If just TikZ code, wrap it properly
      latex_code = generate_complete_latex(tikz_code, language, diagram_type)
    end
    
    # Create a shell script to compile LaTeX and convert to SVG
    script_code = <<~BASH
      #!/bin/bash
      cd /monadic/data
      
      # Check if LaTeX is available
      if ! command -v latex >/dev/null 2>&1; then
        echo "ERROR: LaTeX is not installed in the Python container."
        echo "Please rebuild the Python container with the updated Dockerfile."
        exit 1
      fi
      
      # Verify required packages are available
      echo "Verifying LaTeX packages..."
      MISSING_PACKAGES=""
      
      # Check for essential packages
      for package in tikz.sty pgf.sty tikz-3dplot.sty; do
        if ! kpsewhich $package >/dev/null 2>&1; then
          MISSING_PACKAGES="$MISSING_PACKAGES $package"
        fi
      done
      
      if [ -n "$MISSING_PACKAGES" ]; then
        echo "ERROR: Missing LaTeX packages:$MISSING_PACKAGES"
        echo "Please rebuild the Python container with the updated Dockerfile."
        exit 1
      else
        echo "All required LaTeX packages are available."
      fi
      
      # Save LaTeX code to file with UTF-8 encoding
      cat > #{base_filename}.tex << 'EOF'
      #{latex_code}
      EOF
      
      # Ensure the file is UTF-8 encoded
      file #{base_filename}.tex
      iconv -f UTF-8 -t UTF-8 -c #{base_filename}.tex -o #{base_filename}_clean.tex
      mv #{base_filename}_clean.tex #{base_filename}.tex
      
      # Debug: Check the generated LaTeX file
      echo "Checking LaTeX file content..."
      if [ -f #{base_filename}.tex ]; then
        echo "First 10 lines of LaTeX file:"
        head -n 10 #{base_filename}.tex
        echo "---"
      else
        echo "Error: LaTeX file was not created"
      fi
      
      echo "Generating #{diagram_type} diagram..."
      echo "Title: #{title}"
      
      # Always use latex + dvisvgm for consistent SVG output
      # XeLaTeX + pdf2svg can produce incompatible SVG files
      if false; then
        # Disabled XeLaTeX path
        echo "XeLaTeX path disabled for SVG compatibility"
      else
        # Use latex + dvisvgm for CJK languages or as fallback
        echo "Using latex + dvisvgm for compilation..."
        latex -interaction=nonstopmode #{base_filename}.tex 2>&1 | tee #{base_filename}_compile.log
        
        # Check if compilation was successful
        if [ $? -ne 0 ]; then
          echo "LaTeX compilation failed. Showing error log:"
          tail -n 20 #{base_filename}.log
        fi
        
        if [ -f #{base_filename}.dvi ]; then
          echo "DVI created, converting to editable SVG..."
          
          # Convert DVI to SVG with proper settings
          # Use simpler options for better compatibility
          echo "Converting DVI to SVG..."
          # Set encoding to UTF-8 for proper character handling
          export LANG=en_US.UTF-8
          export LC_ALL=en_US.UTF-8
          dvisvgm --bbox=min --precision=3 --encoding=utf8 #{base_filename}.dvi -o #{base_filename}.svg 2>&1
          
          # Check if SVG was created and has content
          if [ -f #{base_filename}.svg ] && [ -s #{base_filename}.svg ]; then
            echo "SVG file created successfully"
            # Add XML declaration if missing (sometimes needed for proper rendering)
            if ! head -n 1 #{base_filename}.svg | grep -q "<?xml"; then
              echo "Adding XML declaration to SVG..."
              echo '<?xml version="1.0" encoding="UTF-8"?>' > #{base_filename}_temp.svg
              cat #{base_filename}.svg >> #{base_filename}_temp.svg
              mv #{base_filename}_temp.svg #{base_filename}.svg
            fi
          fi
        fi
      fi
      
      if [ -f #{base_filename}.svg ]; then
        echo "Successfully generated #{diagram_type} diagram!"
        
        # Check SVG content
        echo "SVG file preview (first 10 lines):"
        head -n 10 #{base_filename}.svg
        
        # Clean up intermediate files but keep log for debugging
        rm -f #{base_filename}.aux #{base_filename}.dvi #{base_filename}.pdf
        
        # Show SVG statistics
        echo "Diagram statistics:"
        file_size=$(stat -c%s #{base_filename}.svg 2>/dev/null || stat -f%z #{base_filename}.svg)
        echo "- File size: $(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size} bytes")"
        echo "- Path elements: $(grep -c '<path' #{base_filename}.svg || echo 0)"
        echo "- Text elements: $(grep -c '<text' #{base_filename}.svg || echo 0)"
      else
        echo "Error: Failed to generate diagram"
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
    
    # Return the filename if successful
    if run_result.include?("Successfully generated")
      "#{base_filename}.svg"
    else
      "Error generating diagram: #{run_result}"
    end
  end

  def list_diagram_examples(category: nil)
    examples = {
      "business" => [
        "SWOT Analysis - Strengths, Weaknesses, Opportunities, Threats matrix",
        "Business Model Canvas - Key partners, activities, resources, value propositions",
        "Organizational Chart - Company hierarchy and reporting structure",
        "Process Flow - Business process mapping with decision points",
        "Stakeholder Map - Relationships between different stakeholders"
      ],
      "education" => [
        "Concept Map - Relationships between key concepts in a subject",
        "Learning Path - Sequential steps in a learning journey",
        "Bloom's Taxonomy - Hierarchical learning objectives",
        "Mind Map - Central topic with branching subtopics",
        "Venn Diagram - Overlapping concepts or categories"
      ],
      "science" => [
        "Molecular Structure - Chemical bonds and atomic arrangements",
        "Food Web - Energy flow in an ecosystem",
        "Cell Diagram - Organelles and cellular components",
        "Physics Diagram - Forces, vectors, and motion",
        "Evolutionary Tree - Species relationships and common ancestors",
        "3D Scatter Plot - Three-dimensional data visualization",
        "3D Surface Plot - Mathematical functions in 3D space"
      ],
      "technology" => [
        "System Architecture - Components and their interactions",
        "Network Topology - Computers, servers, and connections",
        "Database Schema - Tables, relationships, and keys",
        "UML Diagram - Classes, objects, and methods",
        "Data Flow - Information movement through a system"
      ],
      "general" => [
        "Timeline - Chronological sequence of events",
        "Flowchart - Decision-making process with branches",
        "Hierarchy - Tree structure with parent-child relationships",
        "Cycle Diagram - Repeating processes or lifecycles",
        "Matrix Diagram - Two-dimensional relationship grid"
      ]
    }
    
    if category && examples.key?(category.downcase)
      selected = examples[category.downcase]
      output = "## #{category.capitalize} Diagram Examples\n\n"
      selected.each { |example| output += "- #{example}\n" }
    else
      output = "## Available Diagram Categories\n\n"
      examples.keys.each do |cat|
        output += "### #{cat.capitalize}\n"
        examples[cat].first(2).each { |example| output += "- #{example}\n" }
        output += "- ... and more\n\n"
      end
    end
    
    output + "\nYou can ask me to create any of these diagrams by describing what you want to visualize!"
  end

  private
  
  def decode_html_entities(text)
    # Decode common HTML entities
    text = text.gsub(/&amp;/, '&')
    text = text.gsub(/&lt;/, '<')
    text = text.gsub(/&gt;/, '>')
    text = text.gsub(/&quot;/, '"')
    text = text.gsub(/&#39;/, "'")
    text = text.gsub(/&apos;/, "'")
    
    # Decode numeric entities (&#123; etc.)
    text = text.gsub(/&#(\d+);/) { |m| $1.to_i.chr(Encoding::UTF_8) rescue m }
    
    # Decode hex entities (&#x263A; etc.)
    text = text.gsub(/&#x([0-9a-fA-F]+);/) { |m| $1.to_i(16).chr(Encoding::UTF_8) rescue m }
    
    text
  end
  
  def extract_tikz_content(latex_code)
    # Extract TikZ content from a complete LaTeX document
    # Look for content between \begin{tikzpicture} and \end{tikzpicture}
    if match = latex_code.match(/\\begin\{tikzpicture\}.*?\\end\{tikzpicture\}/m)
      match[0]
    else
      # If no tikzpicture found, return original code
      latex_code
    end
  end

  def generate_complete_latex(tikz_code, language, diagram_type)
    # Determine if we need CJK support
    needs_cjk = ["japanese", "chinese", "korean", "ja", "zh", "ko"].include?(language.to_s.downcase)
    
    # Add necessary TikZ libraries based on diagram type
    tikz_libraries = determine_tikz_libraries(diagram_type)
    
    if needs_cjk
      # LaTeX with CJK support
      # Remove dvips driver option for better SVG compatibility
      <<~LATEX
        \\documentclass[tikz,border=10pt]{standalone}
        \\usepackage{CJKutf8}
        \\usepackage{tikz}
        #{tikz_libraries}
        \\usepackage{xcolor}
        \\begin{document}
        \\begin{CJK}{UTF8}{min}
        #{tikz_code}
        \\end{CJK}
        \\end{document}
      LATEX
    else
      # Standard LaTeX for non-CJK languages
      <<~LATEX
        \\documentclass[tikz,border=10pt]{standalone}
        \\usepackage{tikz}
        #{tikz_libraries}
        \\usepackage{xcolor}
        \\usepackage[utf8]{inputenc}
        \\begin{document}
        #{tikz_code}
        \\end{document}
      LATEX
    end
  end
  
  def determine_tikz_libraries(diagram_type)
    libraries = []
    
    case diagram_type.downcase
    when /mindmap|mind/
      libraries << "\\usetikzlibrary{mindmap,trees,shadows}"
    when /flow|process/
      libraries << "\\usetikzlibrary{shapes.geometric,arrows.meta,positioning,shadows}"
    when /network|graph/
      libraries << "\\usetikzlibrary{graphs,positioning}"
      # Graph drawing library can cause issues with dvisvgm
      # Use simpler graph layouts instead
    when /timeline/
      libraries << "\\usetikzlibrary{arrows.meta,positioning,decorations.pathreplacing}"
    when /venn/
      libraries << "\\usetikzlibrary{shapes.geometric}"
    when /tree|hierarchy|org/
      libraries << "\\usetikzlibrary{trees,positioning,shadows,arrows.meta}"
    when /uml|class/
      libraries << "\\usetikzlibrary{shapes.multipart,positioning,arrows.meta}"
    when /circuit/
      libraries << "\\usetikzlibrary{circuits.logic.US,circuits.ee.IEC}"
    when /chem|molecule/
      libraries << "\\usepackage{chemfig}"
    when /matrix/
      libraries << "\\usetikzlibrary{matrix,positioning}"
    when /3d|three.*dimensional|scatter/
      # 3D plotting libraries
      libraries << "\\usetikzlibrary{3d,perspective}"
      libraries << "\\usepackage{tikz-3dplot}"
    else
      # Default libraries for general diagrams
      libraries << "\\usetikzlibrary{shapes,arrows.meta,positioning,shadows,patterns}"
    end
    
    # Common libraries often needed
    libraries << "\\usetikzlibrary{calc,fit,backgrounds}"
    
    libraries.join("\n        ")
  end
end

# Claude version inherits all functionality
class ConceptVisualizerClaude < MonadicApp
  include ClaudeHelper

  def generate_concept_diagram(diagram_type:, tikz_code:, title:, language: "english")
    ConceptVisualizerOpenAI.new.generate_concept_diagram(
      diagram_type: diagram_type,
      tikz_code: tikz_code,
      title: title,
      language: language
    )
  end
  
  def list_diagram_examples(category: nil)
    ConceptVisualizerOpenAI.new.list_diagram_examples(category: category)
  end
end