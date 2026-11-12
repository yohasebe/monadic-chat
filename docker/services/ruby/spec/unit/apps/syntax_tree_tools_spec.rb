require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

# Mock the base class and dependencies
class MonadicApp; end
module OpenAIHelper; end
module ClaudeHelper; end

# Load the implementation
require_relative '../../../apps/syntax_tree/syntax_tree_tools'

RSpec.describe SyntaxTreeOpenAI do
  let(:app) { described_class.new }

  describe '#render_syntax_tree' do
    it 'returns an error message when bracket_notation is empty or nil' do
      expect(app.render_syntax_tree(bracket_notation: '', language: 'english')).to eq("❌ Bracket notation is required.")
      expect(app.render_syntax_tree(bracket_notation: nil, language: 'english')).to eq("❌ Bracket notation is required.")
    end
  end

  # The tree is drawn by RSyntaxTree in a run folder of the chat's folder,
  # with nothing else left there, and shown on the work screen.
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
    let(:runs) { [] }
    let(:notation) { '[S [NP John] [VP runs]]' }

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
      allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
      allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown"}')
    end

    def status(ok)
      double(success?: ok)
    end

    # The command: --validate answers with errors (none by default); a
    # drawing writes syntree.<ext> in the -o folder unless it fails.
    def rsyntaxtree(errors: [], fails: false)
      allow(Monadic::Shell).to receive(:capture) do |argv, **options|
        runs << { argv: argv, notation: File.read(argv.last), env: options[:env] }
        if argv.include?('--validate')
          [JSON.generate('ok' => errors.empty?, 'errors' => errors), '', status(errors.empty?)]
        elsif fails
          ['', 'Error: the drawing failed', status(false)]
        else
          format = argv[argv.index('-f') + 1]
          File.write(File.join(argv[argv.index('-o') + 1], "syntree.#{format == 'tikz' ? 'tex' : format}"), format)
          ['', '', status(true)]
        end
      end
    end

    def drawings
      runs.reject { |run| run[:argv].include?('--validate') }
    end

    it "keeps only the SVG, in a run folder of the chat's folder, and shows it on the work screen" do
      rsyntaxtree
      result = app.render_syntax_tree(bracket_notation: notation, language: 'english', workbench: workbench)
      path = result[%r{conversations/\S+/artifacts/j_[a-z0-9]+/syntax_tree\.svg}]
      expect(path).not_to be_nil
      expect(Dir.children(File.join(@data, File.dirname(path)))).to eq(['syntax_tree.svg'])
      expect(MonadicSharedTools::WorkbenchTools).to have_received(:show_file).with(path, workbench)
      expect(result).to include('shown on the work screen')
      expect(Dir.children(@data)).to eq(['conversations'])
    end

    it 'draws the notation as given, in the app style, outside the bundle' do
      rsyntaxtree
      app.render_syntax_tree(bracket_notation: notation, language: 'english', workbench: workbench)
      expect(runs.map { |run| run[:argv].first }.uniq).to eq(['rsyntaxtree'])
      expect(runs.map { |run| run[:notation] }.uniq).to eq([notation])
      expect(drawings.map { |run| run[:argv] }).to all(include(*SyntaxTreeTools::STYLE))
      expect(drawings.first[:argv]).not_to include('--mirror')
      expect(runs.first[:env]).to include('BUNDLE_GEMFILE' => nil) if ENV.key?('BUNDLE_GEMFILE')
    end

    it 'gives the notation back indented, to show as it is' do
      rsyntaxtree
      result = app.render_syntax_tree(bracket_notation: notation, language: 'english', workbench: workbench)
      expect(result).to end_with("[S\n  [NP John]\n  [VP runs]\n]")
    end

    it 'mirrors the tree for a language written right to left' do
      rsyntaxtree
      app.render_syntax_tree(bracket_notation: notation, language: 'Arabic', workbench: workbench)
      expect(drawings.first[:argv].each_cons(2)).to include(['--mirror', 'on'])
    end

    it 'keeps the LaTeX source too when asked' do
      rsyntaxtree
      result = app.render_syntax_tree(bracket_notation: notation, language: 'english', tikz: true, workbench: workbench)
      folder = File.join(@data, File.dirname(result[%r{conversations/\S+/syntax_tree\.svg}]))
      expect(Dir.children(folder).sort).to eq(['syntax_tree.svg', 'syntax_tree.tex'])
      expect(result).to include('syntax_tree.tex')
    end

    it 'gives back what is wrong in the notation, with its hint, and keeps nothing' do
      rsyntaxtree(errors: [{ 'message' => "Error: input text contains an invalid string\n > was_raced", 'hint' => "A '_' subscript is never closed." }])
      result = app.render_syntax_tree(bracket_notation: '[V was_raced]', language: 'english', workbench: workbench)
      expect(result).to start_with('❌ The notation was not drawn')
      expect(result).to include('> was_raced').and include("A '_' subscript is never closed.")
      expect(drawings).to be_empty
      expect(Dir.children(@data)).to be_empty
    end

    it 'leaves no run folder when the drawing fails' do
      rsyntaxtree(fails: true)
      result = app.render_syntax_tree(bracket_notation: notation, language: 'english', workbench: workbench)
      expect(result).to start_with('❌ Error generating syntax tree').and include('the drawing failed')
      expect(Dir.glob(File.join(@data, 'conversations', '*', 'artifacts', '*'))).to be_empty
    end

    it 'says so when the command does not finish' do
      allow(Monadic::Shell).to receive(:capture).and_raise(Monadic::Shell::TimedOut, 'rsyntaxtree did not finish within 60 seconds')
      result = app.render_syntax_tree(bracket_notation: notation, language: 'english', workbench: workbench)
      expect(result).to eq('❌ Error generating syntax tree: rsyntaxtree did not finish within 60 seconds')
    end

    it 'draws nothing without a chat' do
      rsyntaxtree
      result = app.render_syntax_tree(bracket_notation: notation, language: 'english')
      expect(result).to start_with('❌')
      expect(drawings).to be_empty
    end
  end
end

RSpec.describe SyntaxTreeTools do
  let(:app) { SyntaxTreeOpenAI.new }

  describe '#indented' do
    it 'opens each node with nodes below it on a line of its own, two spaces deeper per level' do
      expect(app.indented("[CP [DP What+>1] [C' [C did] [TP [DP t+1] [VP left]]]]")).to eq(<<~TREE.chomp)
        [CP
          [DP What+>1]
          [C'
            [C did]
            [TP
              [DP t+1]
              [VP left]
            ]
          ]
        ]
      TREE
    end

    it 'keeps a leaf of several words on the line of its node' do
      expect(app.indented('[VP [V saw] [DP the man with the hat]]')).to eq("[VP\n  [V saw]\n  [DP the man with the hat]\n]")
    end

    it 'never takes a bracket after a backslash for a node' do
      expect(app.indented('[S [N a\\[b] [V c]]')).to eq("[S\n  [N a\\[b]\n  [V c]\n]")
    end

    it 'gives notation whose brackets do not pair back as it is' do
      ['[S [NP a]', '[S a]]', 'S a'].each { |text| expect(app.indented(text)).to eq(text) }
    end
  end
end

RSpec.describe SyntaxTreeClaude do
  it 'uses the same implementation as SyntaxTreeOpenAI' do
    expect(described_class.instance_method(:render_syntax_tree).owner).to eq(SyntaxTreeTools)
    expect(SyntaxTreeOpenAI.instance_method(:render_syntax_tree).owner).to eq(SyntaxTreeTools)
  end
end
