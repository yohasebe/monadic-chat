require 'spec_helper'
require 'tmpdir'
require 'fileutils'

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
  
  # The TikZ is compiled in a run folder of the chat's folder, which keeps
  # the SVG and its LaTeX source; the SVG is shown on the work screen.
  describe '#generate_concept_diagram' do
    around do |example|
      Dir.mktmpdir('concept-spec') do |dir|
        @data = File.join(dir, 'data')
        @state = File.join(dir, 'state')
        FileUtils.mkdir_p(@data)
        @data = File.realpath(@data)
        example.run
      end
    end

    let(:workbench) { Struct.new(:chat_id).new(Monadic::Workspace::Ids.generate(:chat)) }
    let(:scripts) { [] }
    let(:valid_tikz_code) do
      <<~TIKZ
        \\begin{tikzpicture}
          \\node {Test};
        \\end{tikzpicture}
      TIKZ
    end

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
      allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
      allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown_in_work_screen"}')
    end

    # The container: it runs the script in the folder it changes to, and
    # leaves what a successful compile leaves there (or nothing).
    def container(succeeds: true)
      allow(app).to receive(:run_code) do |code:, **|
        scripts << code
        dir = code[%r{^cd (/monadic/data/\S+) \|\| exit 1$}, 1]
        base = code[/cat > (concept_\w+)\.tex/, 1]
        local = File.join(@data, dir.delete_prefix('/monadic/data/'))
        if succeeds
          File.write(File.join(local, "#{base}.svg"), '<svg/>')
          File.write(File.join(local, "#{base}.tex"), 'tex')
          { text: "Successfully generated diagram!" }
        else
          'Error: Failed to generate diagram'
        end
      end
    end

    def draw(type = 'mindmap', code = valid_tikz_code)
      app.generate_concept_diagram(diagram_type: type, tikz_code: code, title: 'Test', workbench: workbench)
    end

    it "keeps the SVG and its source in a run folder of the chat's folder and shows the SVG" do
      container
      result = draw
      svg = result[%r{conversations/\S+/artifacts/j_[a-z0-9]+/concept_mindmap_\d+\.svg}]
      expect(svg).not_to be_nil
      expect(scripts.first).to include("cd /monadic/data/#{File.dirname(svg)} || exit 1")
      expect(Dir.children(File.join(@data, File.dirname(svg))).sort).to eq([File.basename(svg), File.basename(svg, '.svg') + '.tex'])
      expect(MonadicSharedTools::WorkbenchTools).to have_received(:show_file).with(svg, workbench)
      expect(result).to include('work screen', File.basename(svg, '.svg') + '.tex')
      expect(Dir.children(@data)).to eq(['conversations'])
    end

    it 'names the files by the diagram type, in plain characters' do
      container
      expect(draw('Mind Map!')).to match(/concept_mind_map__\d+\.svg/)
    end

    it 'takes a complete LaTeX document' do
      container
      complete_doc = "\\documentclass{article}\n\\usepackage{tikz}\n\\begin{document}\n#{valid_tikz_code}\\end{document}\n"
      expect(draw('test', complete_doc)).to match(/concept_test_\d+\.svg/)
    end

    it 'says what went wrong and leaves no run folder when the compile fails' do
      container(succeeds: false)
      expect(draw).to start_with('Error generating diagram')
      expect(Dir.glob(File.join(@data, 'conversations/*/artifacts/*'))).to be_empty
    end

    it 'draws nothing without a chat' do
      allow(app).to receive(:run_code)
      result = app.generate_concept_diagram(diagram_type: 'mindmap', tikz_code: valid_tikz_code, title: 'Test')
      expect(result).to start_with('❌')
      expect(app).not_to have_received(:run_code)
    end

    context 'with invalid inputs' do
      it 'returns error when tikz_code is empty' do
        expect(app.generate_concept_diagram(diagram_type: 'mindmap', tikz_code: '', title: 'Test')).to include('TikZ code is required')
      end

      it 'returns error when diagram_type is empty' do
        expect(app.generate_concept_diagram(diagram_type: '', tikz_code: valid_tikz_code, title: 'Test')).to include('Diagram type is required')
      end

      it 'returns error when tikz_code has no TikZ commands' do
        expect(app.generate_concept_diagram(diagram_type: 'mindmap', tikz_code: 'just text', title: 'Test')).to include('Invalid TikZ code')
      end
    end

    it 'decodes HTML entities in tikz_code' do
      container
      draw('mindmap', "\\begin{tikzpicture}\n\\node {A &amp; B};\n\\end{tikzpicture}")
      expect(scripts.first).to include('A & B')
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
      expect(result).to match(/❌ Invalid TikZ code/)
    end
  end
end