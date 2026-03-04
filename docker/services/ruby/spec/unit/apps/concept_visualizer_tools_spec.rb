require 'spec_helper'
require 'cgi'

# Mock the base class and dependencies
class MonadicApp; end
module OpenAIHelper; end
module ClaudeHelper; end
module LatexHelper
  def escape_latex(text)
    return text if text.nil? || text.empty?
    
    text.gsub('\\', '\\textbackslash{}')
        .gsub('_', '\\_')
        .gsub('%', '\\%')
        .gsub('$', '\\$')
        .gsub('&', '\\&')
        .gsub('#', '\\#')
        .gsub('{', '\\{')
        .gsub('}', '\\}')
        .gsub('^', '\\^{}')
        .gsub('~', '\\~{}')
  end
  
  def decode_html_entities(text)
    return text if text.nil? || text.empty?
    
    text.gsub('&amp;', '&')
        .gsub('&lt;', '<')
        .gsub('&gt;', '>')
        .gsub('&quot;', '"')
        .gsub('&#39;', "'")
        .gsub('&apos;', "'")
  end
end

# Load the implementation
require_relative '../../../apps/concept_visualizer/concept_visualizer_tools'

RSpec.describe ConceptVisualizerOpenAI do
  let(:app) { described_class.new }
  
  describe '#generate_concept_diagram' do
    before do
      # Mock the run_code method to avoid actual script execution
      # Return a string that includes "Successfully generated" to simulate success
      allow(app).to receive(:run_code).and_return("Successfully generated diagram!")
      # Mock data_path and File.exist? for PNG check (default: no PNG)
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return('/tmp/test_data')
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/\.png$/).and_return(false)
    end
    
    let(:valid_tikz_code) do
      <<~TIKZ
        \\begin{tikzpicture}
          \\node {Test};
        \\end{tikzpicture}
      TIKZ
    end
    
    context 'with valid inputs' do
      it 'returns SVG filename as string when no PNG exists' do
        result = app.generate_concept_diagram(
          diagram_type: 'mindmap',
          tikz_code: valid_tikz_code,
          title: 'Test Diagram',
          language: 'english'
        )
        expect(result).to match(/^concept_mindmap_\d+\.svg$/)
      end

      it 'sanitizes diagram type in filename' do
        result = app.generate_concept_diagram(
          diagram_type: 'Mind Map!',
          tikz_code: valid_tikz_code,
          title: 'Test'
        )
        expect(result).to match(/^concept_mind_map__\d+\.svg$/)
      end

      it 'handles complete LaTeX documents' do
        complete_doc = <<~LATEX
          \\documentclass{article}
          \\usepackage{tikz}
          \\begin{document}
          \\begin{tikzpicture}
            \\node {Test};
          \\end{tikzpicture}
          \\end{document}
        LATEX

        result = app.generate_concept_diagram(
          diagram_type: 'test',
          tikz_code: complete_doc,
          title: 'Test'
        )
        expect(result).to match(/^concept_test_\d+\.svg$/)
      end

      it 'returns SVG filename String when PNG exists (no _image vision injection)' do
        # Mock data_path and File.exist? to simulate PNG availability
        data_path = '/tmp/test_data'
        allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data_path)

        # We need to capture the base_filename used, so we freeze time
        allow(Time).to receive_message_chain(:now, :to_i, :to_s).and_return('1234567890')
        expected_png = File.join(data_path, 'concept_mindmap_1234567890.png')

        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(expected_png).and_return(true)

        result = app.generate_concept_diagram(
          diagram_type: 'mindmap',
          tikz_code: valid_tikz_code,
          title: 'Test Diagram',
          language: 'english'
        )
        # Returns SVG filename String — no _image key (gallery_html handles display)
        expect(result).to be_a(String)
        expect(result).to eq('concept_mindmap_1234567890.svg')
      end
    end

    context 'when run_code returns a Hash' do
      it 'handles Hash return correctly' do
        allow(app).to receive(:run_code).and_return({ text: "Successfully generated mindmap diagram!" })

        data_path = '/tmp/test_data'
        allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(anything).and_return(false)

        result = app.generate_concept_diagram(
          diagram_type: 'mindmap',
          tikz_code: valid_tikz_code,
          title: 'Test Diagram'
        )
        # When PNG doesn't exist, returns plain string
        expect(result).to be_a(String)
        expect(result).to match(/\.svg$/)
      end

      it 'returns error when Hash result indicates failure' do
        allow(app).to receive(:run_code).and_return({ text: "LaTeX compilation failed" })

        result = app.generate_concept_diagram(
          diagram_type: 'mindmap',
          tikz_code: valid_tikz_code,
          title: 'Test Diagram'
        )
        expect(result).to start_with("Error generating diagram:")
      end
    end
    
    context 'with invalid inputs' do
      it 'returns error when tikz_code is empty' do
        result = app.generate_concept_diagram(
          diagram_type: 'mindmap',
          tikz_code: '',
          title: 'Test'
        )
        expect(result).to eq("Error: TikZ code is required.")
      end
      
      it 'returns error when diagram_type is empty' do
        result = app.generate_concept_diagram(
          diagram_type: '',
          tikz_code: valid_tikz_code,
          title: 'Test'
        )
        expect(result).to eq("Error: diagram type is required.")
      end
      
      it 'returns error when tikz_code has no TikZ commands' do
        result = app.generate_concept_diagram(
          diagram_type: 'test',
          tikz_code: 'Just some text',
          title: 'Test'
        )
        expect(result).to eq("Error: Invalid TikZ code. Code must contain TikZ commands.")
      end
    end
    
    context 'with HTML entities' do
      it 'decodes HTML entities in tikz_code' do
        encoded_tikz = '\\begin{tikzpicture}\n  \\node {Test &amp; Example};\n\\end{tikzpicture}'
        result = app.generate_concept_diagram(
          diagram_type: 'test',
          tikz_code: encoded_tikz,
          title: 'Test'
        )
        expect(result).to match(/^concept_test_\d+\.svg$/)
      end
    end
  end
  
  describe '#extract_tikz_content (private)' do
    it 'extracts TikZ content from complete document' do
      complete_doc = <<~LATEX
        \\documentclass{article}
        \\usepackage{tikz}
        \\begin{document}
        Some text before
        \\begin{tikzpicture}
          \\node {Content};
        \\end{tikzpicture}
        Some text after
        \\end{document}
      LATEX
      
      result = app.send(:extract_tikz_content, complete_doc)
      expect(result).to include('\\begin{tikzpicture}')
      expect(result).to include('\\node {Content};')
      expect(result).not_to include('Some text before')
      expect(result).not_to include('Some text after')
    end
  end
  
  describe '#generate_complete_latex (private)' do
    it 'generates LaTeX with CJK support for Chinese' do
      latex = app.send(:generate_complete_latex, '\\node {测试};', 'chinese', 'test')
      expect(latex).to include('\\usepackage{CJKutf8}')
      expect(latex).to include('\\begin{CJK}{UTF8}')
    end
    
    it 'generates standard LaTeX for English' do
      latex = app.send(:generate_complete_latex, '\\node {Test};', 'english', 'test')
      expect(latex).not_to include('CJKutf8')
      expect(latex).to include('\\documentclass')
      expect(latex).to include('\\usepackage{tikz}')
    end
    
    it 'includes required TikZ libraries' do
      latex = app.send(:generate_complete_latex, '\\node {Test};', 'english', 'mindmap')
      expect(latex).to include('\\usetikzlibrary')
      # The actual implementation includes different libraries
      expect(latex).to include('mindmap')
      expect(latex).to include('trees')
      expect(latex).to include('shadows')
    end
  end
  
  describe '#decode_html_entities (private)' do
    it 'decodes common HTML entities' do
      expect(app.send(:decode_html_entities, '&amp;')).to eq('&')
      expect(app.send(:decode_html_entities, '&lt;')).to eq('<')
      expect(app.send(:decode_html_entities, '&gt;')).to eq('>')
      expect(app.send(:decode_html_entities, '&quot;')).to eq('"')
    end
    
    it 'preserves text without entities' do
      text = 'Normal text with no entities'
      expect(app.send(:decode_html_entities, text)).to eq(text)
    end
  end
end

RSpec.describe ConceptVisualizerClaude do
  let(:app) { described_class.new }

  describe '#generate_concept_diagram' do
    it 'uses shared ConceptVisualizerTools module' do
      # ConceptVisualizerClaude should include ConceptVisualizerTools
      expect(described_class.ancestors).to include(ConceptVisualizerTools)
    end

    it 'validates TikZ code contains required commands' do
      # Invalid TikZ code should return error
      result = app.generate_concept_diagram(
        diagram_type: 'flowchart',
        tikz_code: '\\node {test};',  # Missing \begin{tikzpicture}
        title: 'Test Chart',
        language: 'english'
      )
      expect(result).to match(/Error: Invalid TikZ code/)
    end
  end
end