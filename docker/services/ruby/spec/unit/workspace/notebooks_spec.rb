# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'shellwords'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/workspace/notebooks'
require_relative '../../../lib/monadic/shared_tools/jupyter_operations'

# A chat's notebooks: made in its folder, and a name the model gives taken
# as one of them, never as a file of another chat.
RSpec.describe 'The notebooks of a chat' do
  around do |example|
    Dir.mktmpdir('notebooks-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p(@data)
      @data = File.realpath(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Board).to receive(:existing).and_return(nil)
  end

  let(:notebooks) { Monadic::Workspace::Notebooks }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:other_chat) { Monadic::Workspace::Ids.generate(:chat) }

  def make(chat_id, name)
    notebooks.create(chat_id, app_name: 'JupyterNotebookOpenAI', name: name)
  end

  def on_board(chat_id, *paths)
    board = double('board', snapshot: { items: paths.map { |path| { kind: 'file', path: path } } })
    allow(Monadic::Workbench::Board).to receive(:existing).with(chat_id).and_return(board)
  end

  describe 'making one' do
    it "makes an empty notebook in the work folder of the chat's folder, numbering a name already there" do
      first = make(chat, 'analysis')
      second = make(chat, 'analysis.ipynb')
      expect(first).to match(%r{\Aconversations/[^/]+_jupyter-notebook-open-ai_w_[a-z0-9]+/work/analysis\.ipynb\z})
      expect(second).to eq(first.sub('analysis.ipynb', 'analysis-2.ipynb'))
      expect(JSON.parse(File.read(File.join(@data, first)))).to include('cells' => [], 'nbformat' => 4)
    end

    it 'keeps letters of any script and makes the rest of a name safe' do
      expect(File.basename(make(chat, '売上 分析/../x'))).to eq('x.ipynb')
      expect(File.basename(make(chat, '売上 分析'))).to eq('売上_分析.ipynb')
      expect(File.basename(make(chat, '...'))).to eq('notebook.ipynb')
    end

    it 'makes none when the chat folder is gone, or for no chat' do
      path = make(chat, 'a')
      FileUtils.rm_rf(File.join(@data, File.dirname(path, 2)))
      expect { make(chat, 'b') }.to raise_error(notebooks::Refused, /no longer/)
      expect { make('not-a-chat', 'b') }.to raise_error(notebooks::Refused)
    end
  end

  describe 'naming one' do
    it 'takes its path, its name, or its name without .ipynb' do
      path = make(chat, 'analysis')
      expect(notebooks.resolve(chat, path)).to eq(path)
      expect(notebooks.resolve(chat, 'analysis.ipynb')).to eq(path)
      expect(notebooks.resolve(chat, 'analysis')).to eq(path)
    end

    it 'takes the current one for no name, and refuses a current one that is not the chat\'s' do
      path = make(chat, 'analysis')
      elsewhere = make(other_chat, 'other')
      expect(notebooks.resolve(chat, '', current: path)).to eq(path)
      expect { notebooks.resolve(chat, nil, current: elsewhere) }.to raise_error(notebooks::Refused)
      expect { notebooks.resolve(chat, '') }.to raise_error(notebooks::Refused, /none yet/)
    end

    it "never takes another chat's notebook, by path or by name, and says which ones the chat has" do
      own = make(chat, 'mine')
      theirs = make(other_chat, 'theirs')
      expect { notebooks.resolve(chat, theirs) }.to raise_error(notebooks::Refused, /not a notebook of this chat.*#{Regexp.escape(own)}/)
      expect { notebooks.resolve(chat, 'theirs') }.to raise_error(notebooks::Refused)
      expect { notebooks.resolve(chat, "#{File.dirname(own)}/../../#{theirs}") }.to raise_error(notebooks::Refused)
    end

    it 'takes a notebook at the top of the shared folder only when named with ./' do
      File.write(File.join(@data, 'old.ipynb'), '{"cells":[]}')
      make(chat, 'new')
      expect { notebooks.resolve(chat, 'old.ipynb') }.to raise_error(notebooks::Refused, %r{name it \./old\.ipynb})
      expect(notebooks.resolve(chat, './old.ipynb')).to eq('old.ipynb')
      expect { notebooks.resolve(chat, './missing.ipynb') }.to raise_error(notebooks::Refused)
      expect { notebooks.resolve(chat, './conversations/x.ipynb') }.to raise_error(notebooks::Refused)
    end

    it 'counts a notebook on the chat\'s work screen as its own, and asks for the path when two share a name' do
      File.write(File.join(@data, 'analysis.ipynb'), '{"cells":[]}')
      on_board(chat, 'analysis.ipynb')
      expect(notebooks.resolve(chat, 'analysis')).to eq('analysis.ipynb')
      made = make(chat, 'analysis')
      expect { notebooks.resolve(chat, 'analysis') }
        .to raise_error(notebooks::Refused, %r{More than one.*\./analysis\.ipynb, #{Regexp.escape(made)}|More than one.*#{Regexp.escape(made)}, \./analysis\.ipynb})
      expect(notebooks.resolve(chat, made)).to eq(made)
      expect(notebooks.resolve(chat, './analysis')).to eq('analysis.ipynb')
    end

    it 'lists the latest changed first, leaving out what is gone or reached through a link' do
      older = make(chat, 'older')
      newer = make(chat, 'newer')
      File.utime(Time.now - 60, Time.now - 60, File.join(@data, older))
      File.symlink(File.join(@data, older), File.join(@data, File.dirname(older), 'link.ipynb'))
      expect(notebooks.known(chat)).to eq([newer, older])
      File.delete(File.join(@data, newer))
      expect(notebooks.known(chat)).to eq([older])
    end
  end

  describe 'the Jupyter tools in a chat' do
    let(:app) do
      Class.new do
        include MonadicSharedTools::JupyterOperations

        attr_reader :commands

        def send_command(command:, container:, **_)
          (@commands ||= []) << command
          block_given? ? yield('', '', Struct.new(:success?).new(true)) : 'Cell updated.'
        end
      end.new
    end
    let(:caller_for) { ->(chat_id) { Struct.new(:chat_id).new(chat_id) } }

    before { allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown"}') }
    let(:session) { { Monadic::Workspace::Chats::SESSION_KEY => chat, parameters: { 'app_name' => 'JupyterNotebookOpenAI' } } }

    it "makes a notebook in the chat's folder, and the next calls take it by name or by default" do
      result = app.create_jupyter_notebook(filename: 'analysis', session: session, workbench: caller_for.(chat))
      path = notebooks.known(chat).first
      expect(result).to start_with("Notebook #{path} created successfully. Access it at: ")
      expect(result).to include("/lab/tree/#{path.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')}")
      expect(session[:current_notebook_filename]).to eq(path)

      app.update_jupyter_cell(filename: 'analysis', index: 0, content: 'x', session: session, workbench: caller_for.(chat))
      app.delete_jupyter_cell(filename: '', index: 0, session: session, workbench: caller_for.(chat))
      expect(app.commands.map { |c| Shellwords.split(c)[2] }).to eq([path, path])
    end

    it 'takes the chat the reply was asked in, not one the session moved to' do
      path = make(chat, 'analysis')
      moved = session.merge(Monadic::Workspace::Chats::SESSION_KEY => other_chat)
      app.update_jupyter_cell(filename: 'analysis', index: 0, content: 'x', session: moved, workbench: caller_for.(chat))
      expect(Shellwords.split(app.commands.last)[2]).to eq(path)
    end

    it "refuses another chat's notebook and runs nothing" do
      theirs = make(other_chat, 'theirs')
      result = app.update_jupyter_cell(filename: theirs, index: 0, content: 'x', session: session, workbench: caller_for.(chat))
      expect(result).to start_with('Error:')
      expect(app.commands).to be_nil
    end

    it 'takes the latest notebook of a continued chat when none is named (the session forgot it)' do
      older = make(chat, 'older')
      File.utime(Time.now - 60, Time.now - 60, File.join(@data, older))
      newer = make(chat, 'newer')
      app.delete_jupyter_cell(filename: '', index: 0, session: session, workbench: caller_for.(chat))
      expect(Shellwords.split(app.commands.last)[2]).to eq(newer)
    end

    it "lists the chat's notebooks" do
      path = make(chat, 'analysis')
      expect(app.list_jupyter_notebooks(session: session, workbench: caller_for.(chat))).to eq("- #{path}")
      expect(app.list_jupyter_notebooks(session: session, workbench: caller_for.(other_chat))).to eq('This chat has no notebooks yet.')
    end
  end
end
