#!/usr/bin/env ruby
# Test syntax tree generation

require 'open3'

notation = "[S [NP [Det The] [N cat]] [VP [V sits]]]"
timestamp = Time.now.to_i.to_s
base_filename = "syntree_test_#{timestamp}"

# Convert to tikz-qtree format
tikz_notation = notation.gsub(/\[([^\s\[\]]+)/) do |match|
  label = $1
  if label.include?("'")
    "[.{#{label}}"
  else
    "[.#{label}"
  end
end

tikz_notation = tikz_notation.gsub(/(\[\.[^\s\[\]]+)\s+([^\[\]]+)\]/) do
  "#{$1} #{$2.strip} ]"
end

puts "Tikz notation: #{tikz_notation}"

latex_code = <<~LATEX
\\documentclass[tikz,border=10pt]{standalone}
\\usepackage{tikz}
\\usepackage{tikz-qtree}
\\begin{document}
\\Tree #{tikz_notation}
\\end{document}
LATEX

script_code = <<~BASH
#!/bin/bash
cd /monadic/data

# Save LaTeX code to file
cat > #{base_filename}.tex << 'EOF'
#{latex_code}
EOF

echo "=== LaTeX file created ==="
ls -la #{base_filename}.tex

echo "=== LaTeX content ==="
cat #{base_filename}.tex

echo "=== Checking LaTeX installation ==="
which latex || echo "latex not found"
which dvisvgm || echo "dvisvgm not found"

echo "=== Running LaTeX ==="
latex -interaction=nonstopmode #{base_filename}.tex

echo "=== Checking output files ==="
ls -la #{base_filename}.*

if [ -f #{base_filename}.dvi ]; then
  echo "=== Converting to SVG ==="
  dvisvgm --bbox=min --precision=3 #{base_filename}.dvi -o #{base_filename}.svg
  
  if [ -f #{base_filename}.svg ]; then
    echo "SUCCESS: Generated #{base_filename}.svg"
    ls -la #{base_filename}.svg
  else
    echo "ERROR: Failed to convert to SVG"
  fi
else
  echo "ERROR: LaTeX compilation failed"
  if [ -f #{base_filename}.log ]; then
    echo "=== LaTeX log ==="
    tail -50 #{base_filename}.log
  fi
fi
BASH

puts "\n=== Executing in container ==="
container_name = "monadic-chat-python-container"
cmd = ["docker", "exec", "-i", container_name, "bash"]

stdout, stderr, status = Open3.capture3(*cmd, stdin_data: script_code)

puts "=== STDOUT ==="
puts stdout
puts "\n=== STDERR ==="
puts stderr
puts "\n=== Exit status: #{status.exitstatus}"