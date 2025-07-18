require 'spec_helper'

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
    before do
      # Mock the run_code method to avoid actual script execution
      allow(app).to receive(:run_code).and_return(true)
    end
    
    context 'with valid inputs' do
      it 'generates filename with svg extension' do
        result = app.render_syntax_tree(
          bracket_notation: '[S [NP John] [VP runs]]',
          language: 'english'
        )
        expect(result).to match(/^syntree_\d+\.svg$/)
      end
      
      it 'handles Japanese language parameter' do
        result = app.render_syntax_tree(
          bracket_notation: '[S [NP 太郎が] [VP 走る]]',
          language: 'japanese'
        )
        expect(result).to match(/^syntree_\d+\.svg$/)
      end
    end
    
    context 'with invalid inputs' do
      it 'returns error message when bracket_notation is empty' do
        result = app.render_syntax_tree(
          bracket_notation: '',
          language: 'english'
        )
        expect(result).to eq("Error: bracket notation is required.")
      end
      
      it 'returns error message when bracket_notation is nil' do
        result = app.render_syntax_tree(
          bracket_notation: nil,
          language: 'english'
        )
        expect(result).to eq("Error: bracket notation is required.")
      end
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
    it 'delegates to SyntaxTreeOpenAI implementation' do
      openai_app = instance_double(SyntaxTreeOpenAI)
      expect(SyntaxTreeOpenAI).to receive(:new).and_return(openai_app)
      expect(openai_app).to receive(:render_syntax_tree).with(
        bracket_notation: '[S [NP test]]',
        language: 'english'
      ).and_return('syntree_123.svg')
      
      result = app.render_syntax_tree(
        bracket_notation: '[S [NP test]]',
        language: 'english'
      )
      expect(result).to eq('syntree_123.svg')
    end
  end
end