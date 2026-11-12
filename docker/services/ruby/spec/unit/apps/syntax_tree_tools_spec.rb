require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'shellwords'

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
end

# Load the implementation
require_relative '../../../apps/syntax_tree/syntax_tree_tools'

RSpec.describe SyntaxTreeOpenAI do
  let(:app) { described_class.new }
  
  describe '#render_syntax_tree' do
    # Note: Actual SVG generation tests removed as they require Docker container
    # and LaTeX environment. These are better tested in integration tests.
    
    context 'with invalid inputs' do
      it 'returns error message when bracket_notation is empty' do
        result = app.render_syntax_tree(
          bracket_notation: '',
          language: 'english'
        )
        expect(result).to eq("❌ Bracket notation is required.")
      end

      it 'returns error message when bracket_notation is nil' do
        result = app.render_syntax_tree(
          bracket_notation: nil,
          language: 'english'
        )
        expect(result).to eq("❌ Bracket notation is required.")
      end
    end
  end
  
  # The tree is drawn in a run folder of the chat's folder, with nothing
  # else left there, and shown on the work screen.
  describe '#render_syntax_tree in a chat' do
    around do |example|
      Dir.mktmpdir('syntax-tree-spec') do |dir|
        @data = File.join(dir, 'data')
        @state = File.join(dir, 'state')
        FileUtils.mkdir_p(@data)
        @data = File.realpath(@data)
        example.run
      end
    end

    let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
    let(:workbench) { Struct.new(:chat_id).new(chat) }
    let(:scripts) { [] }

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
      allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
      allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown"}')
    end

    # The container's run: the SVG copied to the folder the script names.
    def draws(svg: true, ok: true)
      allow(app).to receive(:send_command) do |command:, **, &block|
        scripts << command
        out = command[%r{cp syntree\.svg (\S+)/syntax_tree\.svg}, 1]
        local = File.join(@data, Shellwords.split(out).first.delete_prefix('/monadic/data/')) if out
        File.write(File.join(local, 'syntax_tree.svg'), '<svg/>') if svg && ok
        block.call(ok ? 'done' : '', ok ? '' : 'Error: DVI generation failed', double(success?: ok))
      end
    end

    it "keeps only the SVG, in a run folder of the chat's folder, and shows it on the work screen" do
      draws
      result = app.render_syntax_tree(bracket_notation: '[S [NP John] [VP runs]]', language: 'english', workbench: workbench)
      path = result[%r{conversations/\S+/artifacts/j_[a-z0-9]+/syntax_tree\.svg}]
      expect(path).not_to be_nil
      expect(Dir.children(File.join(@data, File.dirname(path)))).to eq(['syntax_tree.svg'])
      expect(MonadicSharedTools::WorkbenchTools).to have_received(:show_file).with(path, workbench)
      expect(result).to include('shown on the work screen')
      expect(scripts.last).to include('mktemp -d').and include("trap 'rm -rf")
      expect(Dir.children(@data)).to eq(['conversations'])
    end

    it 'leaves no run folder when the drawing fails' do
      draws(ok: false)
      result = app.render_syntax_tree(bracket_notation: '[S [NP John] [VP runs]]', language: 'english', workbench: workbench)
      expect(result).to start_with('❌ Error generating syntax tree')
      artifacts = Dir.glob(File.join(@data, 'conversations', '*', 'artifacts', '*'))
      expect(artifacts).to be_empty
    end

    it 'draws nothing without a chat' do
      draws
      result = app.render_syntax_tree(bracket_notation: '[S [NP John] [VP runs]]', language: 'english')
      expect(result).to start_with('❌')
      expect(scripts).to be_empty
    end
  end

  describe '#generate_latex_syntax_tree (private)' do
    it 'generates LaTeX with CJK support for Japanese' do
      latex = app.send(:generate_latex_syntax_tree, '[S [NP 太郎] [VP 走る]]', 'japanese')
      expect(latex).to include('\\usepackage{CJKutf8}')
      expect(latex).to include('\\begin{CJK}{UTF8}{min}')
    end
    
    it 'generates standard LaTeX for English' do
      latex = app.send(:generate_latex_syntax_tree, '[S [NP John] [VP runs]]', 'english')
      expect(latex).not_to include('CJKutf8')
      expect(latex).to include('\\documentclass')
      expect(latex).to include('\\usepackage{tikz-qtree}')
    end
  end
  
  describe '#convert_to_qtree (private)' do
    it 'converts bracket notation to qtree format' do
      result = app.send(:convert_to_qtree, '[S [NP John] [VP runs]]')
      expect(result).to include('[.S')
      expect(result).to include('[.NP')
      expect(result).to include('[.VP')
    end
    
    it 'handles prime notation correctly without creating quotes' do
      # Test case from the actual Japanese example
      result = app.send(:convert_to_qtree, "[S [NP [N' [N test]]] [VP [V' [V run]]]]")
      
      # Should have prime symbols, not quotes or double primes
      expect(result).to include("[.N'")
      expect(result).to include("[.V'")
      
      # Should NOT have double quotes or escaped quotes
      expect(result).not_to include('""')
      expect(result).not_to include("''")
      expect(result).not_to include('\\"')
      expect(result).not_to include("\\ensuremath")
    end
    
    it 'handles complex Japanese syntax tree with primes' do
      # Simplified version of the problematic tree
      input = "[S [KP [NP [N' [N 先生]]] [K が]] [S' [VP [V' [V なる]]] [T た]]]"
      result = app.send(:convert_to_qtree, input)
      
      # Check that N' and V' are handled correctly
      expect(result).to include("[.N'")
      expect(result).to include("[.V'")
      expect(result).to include("[.S'")
      
      # No unwanted quotes
      expect(result).not_to include('""')
    end
    
    it 'escapes LaTeX special characters' do
      result = app.send(:convert_to_qtree, '[S [NP John_&_Mary] [VP run$s]]')
      # Check that special characters are escaped
      expect(result).to include('\\ &\\')  # & is escaped with spaces
      expect(result).to include('run\\$s')  # $ is escaped
    end
    
    it 'handles apostrophes correctly' do
      result = app.send(:convert_to_qtree, "[S [NP John's] [VP V']]")
      # The implementation doesn't wrap in braces, just includes the apostrophe
      expect(result).to include("John's")
      expect(result).to include("V'")
    end
  end
  
  describe '#simplify_redundant_nodes (private)' do
    it 'simplifies redundant parent-child structures' do
      input = '[NP [NP the cat]]'
      result = app.send(:simplify_redundant_nodes, input)
      # The simplified version should have only one NP
      expect(result.scan(/\bNP\b/).count).to eq(1)
    end
  end
end

RSpec.describe SyntaxTreeClaude do
  let(:app) { described_class.new }
  
  describe '#render_syntax_tree' do
    it 'validates required parameters' do
      # Test with missing bracket notation
      result = app.render_syntax_tree(
        bracket_notation: '',
        language: 'english'
      )
      expect(result).to eq("❌ Bracket notation is required.")
    end

    it 'uses the same implementation as SyntaxTreeOpenAI' do
      # Both classes should return the same error for invalid input
      openai_app = SyntaxTreeOpenAI.new
      claude_app = described_class.new
      
      openai_result = openai_app.render_syntax_tree(
        bracket_notation: nil,
        language: 'english'
      )
      
      claude_result = claude_app.render_syntax_tree(
        bracket_notation: nil,
        language: 'english'
      )
      
      expect(claude_result).to eq(openai_result)
      expect(claude_result).to eq("❌ Bracket notation is required.")
    end
  end
end