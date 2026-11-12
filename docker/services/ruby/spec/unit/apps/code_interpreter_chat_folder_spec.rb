# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../lib/monadic/app'
require_relative '../../../lib/monadic/shared_tools/python_execution'

# In an app that keeps what its code makes in the chat's folder (Code
# Interpreter), code runs in a run folder of the chat: what it writes by a
# plain name stays there and is shown on the work screen.
RSpec.describe 'code that runs in a run folder of the chat' do
  around do |example|
    Dir.mktmpdir('code-run-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p(@data)
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:klass) { Class.new(MonadicApp) { include MonadicSharedTools::PythonExecution } }
  let(:app) { klass.new }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:workbench) { Struct.new(:chat_id).new(chat) }
  let(:runs) { [] }
  let(:writes) { {} }

  def session_of(app_name)
    { parameters: { 'app_name' => app_name } }
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(true)
    stub_const('MonadicApp::COMMAND_DELAY', 0)
    stub_const('APPS', {
                 'CodeInterpreterOpenAI' => double(settings: { code_runs_in_chat_folder: true }),
                 'MathTutorOpenAI' => double(settings: {})
               })
    allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown_in_work_screen"}')
    # The container: it sees the shared folder at /monadic/data, and the
    # code writes the files of `writes` where it runs.
    allow(app).to receive(:capture_command) do |argv, chdir: nil, **|
      runs << { argv: argv, chdir: chdir }
      here = chdir ? File.join(@data, chdir.delete_prefix('/monadic/data/')) : @data
      writes.each { |name, body| File.write(File.join(here, name), body) }
      ['done', '', double(success?: true)]
    end
  end

  def artifacts
    Dir.glob(File.join(@data, 'conversations', '*', 'artifacts', '*'))
  end

  it "runs the code in a run folder of the chat and shows what it wrote there" do
    writes['plot.png'] = 'png'
    result = app.run_code(code: "print(1)", command: 'python', extension: 'py',
                          session: session_of('CodeInterpreterOpenAI'), workbench: workbench)

    folder = artifacts.first
    relative = folder.delete_prefix("#{@data}/")
    expect(runs.first[:chdir]).to eq("/monadic/data/#{relative}")
    expect(Dir.children(folder)).to eq(['plot.png'])
    expect(result).to include("#{relative}/plot.png", 'shown on the work screen', '/monadic/data/', 'done')
    expect(MonadicSharedTools::WorkbenchTools).to have_received(:show_file).with("#{relative}/plot.png", workbench)
    expect(Dir.children(@data)).to eq(['conversations'])
  end

  it 'lets the run folder go when the code wrote nothing' do
    result = app.run_code(code: "print(1)", command: 'python', extension: 'py',
                          session: session_of('CodeInterpreterOpenAI'), workbench: workbench)
    expect(artifacts).to be_empty
    expect(result).to include('done')
    expect(result).not_to include('work screen')
  end

  it 'runs from the shared folder in an app that does not keep its output in the chat' do
    app.run_code(code: "print(1)", command: 'python', extension: 'py', session: session_of('MathTutorOpenAI'), workbench: workbench)
    expect(runs.first[:chdir]).to be_nil
    expect(artifacts).to be_empty
  end

  it 'runs from the shared folder without a chat' do
    app.run_code(code: "print(1)", command: 'python', extension: 'py', session: session_of('CodeInterpreterOpenAI'), workbench: nil)
    expect(runs.first[:chdir]).to be_nil
    expect(artifacts).to be_empty
  end

  it 'runs a command in the container from the folder it is given' do
    allow(Monadic::Shell).to receive(:exec).and_return(['', '', double(success?: true)])
    MonadicApp.capture_command(%w[python a.py], container: :python, chdir: '/monadic/data/x')
    MonadicApp.capture_command(%w[python a.py], container: :python)
    expect(Monadic::Shell).to have_received(:exec).with(hash_including(workdir: '/monadic/data/x'))
    expect(Monadic::Shell).to have_received(:exec).with(hash_including(workdir: MonadicApp::SHARED_VOL))
  end
end
