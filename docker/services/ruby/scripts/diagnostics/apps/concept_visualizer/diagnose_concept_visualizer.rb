#!/usr/bin/env ruby

require 'pathname'
require 'fileutils'

# Add the lib directory to the load path
lib_path = File.expand_path('../docker/services/ruby/lib', __FILE__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

# Load the monadic framework
require 'monadic'

# Create a minimal test instance
class TestConceptVisualizer < MonadicApp
  include PythonContainerHelper
  
  def test_svg_generation
    puts "=== Testing Concept Visualizer SVG Generation ==="
    
    # Simple 3D plot TikZ code
    tikz_code = <<~TIKZ
      \\begin{tikzpicture}
        \\begin{axis}[
          xlabel=$x$,
          ylabel=$y$,
          zlabel=$z$,
          title={Test 3D Plot},
          colormap/viridis,
          view={60}{30}
        ]
        \\addplot3[
          surf,
          domain=-2:2,
          domain y=-2:2,
          samples=15
        ] {x^2 + y^2};
        \\end{axis}
      \\end{tikzpicture}
    TIKZ
    
    # Use the actual concept visualizer code
    visualizer = ConceptVisualizerOpenAI.new
    result = visualizer.generate_concept_diagram(
      diagram_type: "3d_plot",
      tikz_code: tikz_code,
      title: "Test 3D Surface",
      language: "english"
    )
    
    puts "\nResult: #{result}"
    
    # Check if file exists
    if result.end_with?('.svg')
      file_path = File.join(ENV['HOME'], 'monadic', 'data', result)
      if File.exist?(file_path)
        puts "✅ SUCCESS: SVG file created at #{file_path}"
        puts "File size: #{File.size(file_path)} bytes"
      else
        puts "❌ ERROR: SVG file not found at #{file_path}"
      end
    else
      puts "❌ ERROR: #{result}"
    end
  end
end

# Run the test
begin
  test = TestConceptVisualizer.new
  test.test_svg_generation
rescue => e
  puts "ERROR: #{e.message}"
  puts e.backtrace.join("\n")
end