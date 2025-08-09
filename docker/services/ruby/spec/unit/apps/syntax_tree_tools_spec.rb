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
    # Note: Actual SVG generation tests removed as they require Docker container
    # and LaTeX environment. These are better tested in integration tests.
    
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
    it 'validates required parameters' do
      # Test with missing bracket notation
      result = app.render_syntax_tree(
        bracket_notation: '',
        language: 'english'
      )
      expect(result).to eq("Error: bracket notation is required.")
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
      expect(claude_result).to eq("Error: bracket notation is required.")
    end
  end
end