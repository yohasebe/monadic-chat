require 'spec_helper'
require 'open3'
require 'fileutils'

RSpec.describe "LaTeX Processing Integration Tests", :integration do
  let(:container_name) { "monadic-chat-python-container" }
  let(:data_dir) { File.expand_path("~/monadic/data") }
  
  def cleanup_generated_files(pattern)
    Dir.glob(File.join(data_dir, pattern)).each do |file|
      FileUtils.rm_f(file)
    end
  end
  
  describe "LaTeX installation in Python container" do
    it "has latex command available" do
      stdout, stderr, status = Open3.capture3("docker", "exec", container_name, "which", "latex")
      expect(status.success?).to be true
      expect(stdout).to include("/usr/bin/latex")
    end
    
    it "has dvisvgm command available" do
      stdout, stderr, status = Open3.capture3("docker", "exec", container_name, "which", "dvisvgm")
      expect(status.success?).to be true
      expect(stdout).to include("/usr/bin/dvisvgm")
    end
    
    it "has required LaTeX packages" do
      packages = %w[tikz.sty tikz-qtree.sty pgf.sty]
      packages.each do |package|
        stdout, stderr, status = Open3.capture3("docker", "exec", container_name, "kpsewhich", package)
        expect(status.success?).to be(true), "Missing LaTeX package: #{package}"
      end
    end
  end
  
  describe "Basic LaTeX compilation" do
    it "can compile simple TikZ document" do
      test_tex = <<~LATEX
        \\documentclass{standalone}
        \\usepackage{tikz}
        \\begin{document}
        \\begin{tikzpicture}
          \\node[circle,draw] {Test};
        \\end{tikzpicture}
        \\end{document}
      LATEX
      
      timestamp = Time.now.to_i
      filename = "test_tikz_#{timestamp}"
      
      begin
        # Write test file
        File.write(File.join(data_dir, "#{filename}.tex"), test_tex)
        
        # Compile in container
        compile_cmd = <<~BASH
          cd /monadic/data && 
          latex -interaction=nonstopmode #{filename}.tex && 
          dvisvgm #{filename}.dvi -o #{filename}.svg
        BASH
        
        stdout, stderr, status = Open3.capture3("docker", "exec", container_name, "bash", "-c", compile_cmd)
        
        expect(status.success?).to be true
        expect(File.exist?(File.join(data_dir, "#{filename}.svg"))).to be true
      ensure
        cleanup_generated_files("test_tikz_#{timestamp}*")
      end
    end
    
    it "can compile syntax tree with tikz-qtree" do
      test_tex = <<~LATEX
        \\documentclass{standalone}
        \\usepackage{tikz}
        \\usepackage{tikz-qtree}
        \\begin{document}
        \\begin{tikzpicture}
          \\Tree [.S [.NP John ] [.VP runs ]]
        \\end{tikzpicture}
        \\end{document}
      LATEX
      
      timestamp = Time.now.to_i
      filename = "test_qtree_#{timestamp}"
      
      begin
        File.write(File.join(data_dir, "#{filename}.tex"), test_tex)
        
        compile_cmd = <<~BASH
          cd /monadic/data && 
          latex -interaction=nonstopmode #{filename}.tex && 
          dvisvgm #{filename}.dvi -o #{filename}.svg
        BASH
        
        stdout, stderr, status = Open3.capture3("docker", "exec", container_name, "bash", "-c", compile_cmd)
        
        expect(status.success?).to be true
        expect(File.exist?(File.join(data_dir, "#{filename}.svg"))).to be true
        
        # Check SVG contains text elements
        svg_content = File.read(File.join(data_dir, "#{filename}.svg"))
        expect(svg_content).to include("John")
        expect(svg_content).to include("runs")
      ensure
        cleanup_generated_files("test_qtree_#{timestamp}*")
      end
    end
    
    it "can compile CJK content" do
      test_tex = <<~LATEX
        \\documentclass{standalone}
        \\usepackage{CJKutf8}
        \\usepackage{tikz}
        \\begin{document}
        \\begin{CJK}{UTF8}{min}
        \\begin{tikzpicture}
          \\node {日本語テスト};
        \\end{tikzpicture}
        \\end{CJK}
        \\end{document}
      LATEX
      
      timestamp = Time.now.to_i
      filename = "test_cjk_#{timestamp}"
      
      begin
        File.write(File.join(data_dir, "#{filename}.tex"), test_tex)
        
        compile_cmd = <<~BASH
          cd /monadic/data && 
          latex -interaction=nonstopmode #{filename}.tex && 
          dvisvgm --no-merge #{filename}.dvi -o #{filename}.svg
        BASH
        
        stdout, stderr, status = Open3.capture3("docker", "exec", container_name, "bash", "-c", compile_cmd)
        
        # CJK compilation might have warnings but should produce output
        expect(File.exist?(File.join(data_dir, "#{filename}.svg"))).to be true
      ensure
        cleanup_generated_files("test_cjk_#{timestamp}*")
      end
    end
  end
  
  describe "Error handling" do
    it "reports error for invalid LaTeX syntax" do
      test_tex = <<~LATEX
        \\documentclass{standalone}
        \\usepackage{tikz}
        \\begin{document}
        \\begin{tikzpicture}
          \\node {Missing closing brace
        \\end{tikzpicture}
        \\end{document}
      LATEX
      
      timestamp = Time.now.to_i
      filename = "test_error_#{timestamp}"
      
      begin
        File.write(File.join(data_dir, "#{filename}.tex"), test_tex)
        
        compile_cmd = "cd /monadic/data && latex -interaction=nonstopmode #{filename}.tex 2>&1"
        stdout, stderr, status = Open3.capture3("docker", "exec", container_name, "bash", "-c", compile_cmd)
        
        expect(status.success?).to be false
        expect(stdout).to include("error") # LaTeX will report an error
      ensure
        cleanup_generated_files("test_error_#{timestamp}*")
      end
    end
  end
end