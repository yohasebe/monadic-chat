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
      # Return a mock result that looks like successful execution output
      mock_result = double('result')
      allow(mock_result).to receive(:include?).and_return(true)
      allow(app).to receive(:run_code).and_return(mock_result)
    end
    
    let(:valid_tikz_code) do
      <<~TIKZ
        \\begin{tikzpicture}
          \\node {Test};
        \\end{tikzpicture}
      TIKZ
    end
    
    context 'with valid inputs' do
      it 'generates filename with svg extension' do
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
    it 'delegates to ConceptVisualizerOpenAI implementation' do
      openai_app = instance_double(ConceptVisualizerOpenAI)
      expect(ConceptVisualizerOpenAI).to receive(:new).and_return(openai_app)
      expect(openai_app).to receive(:generate_concept_diagram).with(
        diagram_type: 'flowchart',
        tikz_code: '\\node {test};',
        title: 'Test Chart',
        language: 'english'
      ).and_return('concept_flowchart_123.svg')
      
      result = app.generate_concept_diagram(
        diagram_type: 'flowchart',
        tikz_code: '\\node {test};',
        title: 'Test Chart',
        language: 'english'
      )
      expect(result).to eq('concept_flowchart_123.svg')
    end
  end
end