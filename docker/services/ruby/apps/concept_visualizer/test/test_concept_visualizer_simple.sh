#!/bin/bash

echo "=== Simple Concept Visualizer Test ==="

# Create a test Ruby script that mimics what the app does
cat > ~/monadic/data/test_concept_viz.rb << 'EOF'
require 'time'

timestamp = Time.now.to_i.to_s
base_filename = "test_concept_3d_#{timestamp}"

# Create LaTeX file with pgfplots
latex_code = <<~LATEX
\\documentclass[tikz,border=10pt]{standalone}
\\usepackage{tikz}
\\usetikzlibrary{3d,perspective}
\\usepackage{pgfplots}
\\pgfplotsset{compat=1.18}
\\usepackage{tikz-3dplot}
\\usetikzlibrary{calc,fit,backgrounds}
\\usepackage{xcolor}
\\usepackage[utf8]{inputenc}
\\begin{document}
\\begin{tikzpicture}
  \\begin{axis}[
    xlabel=$x$,
    ylabel=$y$,
    zlabel=$z$,
    title={3D Test Plot},
    colormap/viridis,
    view={60}{30}
  ]
  \\addplot3[
    surf,
    domain=-1:1,
    domain y=-1:1,
    samples=20
  ] {sin(deg(x))*cos(deg(y))};
  \\end{axis}
\\end{tikzpicture}
\\end{document}
LATEX

File.write("#{base_filename}.tex", latex_code)
puts "Created LaTeX file: #{base_filename}.tex"

# Compile LaTeX
system("latex -interaction=nonstopmode #{base_filename}.tex")

if File.exist?("#{base_filename}.dvi")
  puts "DVI file created"
  
  # Convert to SVG
  system("dvisvgm --bbox=min --precision=3 #{base_filename}.dvi -o #{base_filename}.svg")
  
  if File.exist?("#{base_filename}.svg")
    puts "SUCCESS: #{base_filename}.svg created"
  else
    puts "ERROR: SVG conversion failed"
  end
else
  puts "ERROR: LaTeX compilation failed"
end
EOF

# Run in Python container
echo "Running test in Python container..."
docker exec monadic-chat-python-container bash -c "cd /monadic/data && ruby test_concept_viz.rb"

# List output files
echo ""
echo "=== Output files ==="
ls -la ~/monadic/data/test_concept_3d_* 2>/dev/null | tail -5