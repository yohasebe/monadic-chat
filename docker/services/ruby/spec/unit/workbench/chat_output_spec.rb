# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../lib/monadic/workbench/chat_output'

# What a tool made, kept in a run folder of the chat's folder and shown on
# the work screen.
RSpec.describe Monadic::Workbench::ChatOutput do
  around do |example|
    Dir.mktmpdir('chat-output-spec') do |dir|
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
  end

  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:workbench) { Struct.new(:chat_id).new(chat) }

  it "makes a run folder in the folder of the reply's chat, or else the session's" do
    job = described_class.run_folder(session: nil, workbench: workbench, app_name: 'DrawIOGrapherOpenAI')
    expect(job[:relative]).to match(%r{\Aconversations/[^/]+/artifacts/j_[a-z0-9]+\z})
    expect(File.directory?(File.join(@data, job[:relative]))).to be true

    session = { Monadic::Workspace::Chats::SESSION_KEY => chat }
    expect(described_class.run_folder(session: session, workbench: nil, app_name: 'X')[:relative])
      .to start_with(File.dirname(job[:relative]))
  end

  it 'makes no run folder without a chat' do
    expect(described_class.run_folder(session: nil, workbench: nil, app_name: 'X')).to be_nil
    expect(described_class.run_folder(session: {}, workbench: Struct.new(:chat_id).new('not a chat'), app_name: 'X')).to be_nil
  end

  it 'keeps a file in the run folder, never over one that is there' do
    job = described_class.run_folder(session: nil, workbench: workbench, app_name: 'X')
    path = described_class.keep(job, 'tune.abc', 'X:1')
    expect(path).to eq(File.join(job[:relative], 'tune.abc'))
    expect(File.read(File.join(@data, path))).to eq('X:1')
    expect { described_class.keep(job, 'tune.abc', 'X:2') }.to raise_error(StandardError)
    expect(File.read(File.join(@data, path))).to eq('X:1')
  end

  it 'shows a file on the work screen of the reply, and says when it could not' do
    allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown_in_work_screen"}')
    expect(described_class.show('a/b.abc', workbench)).to be true
    allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('❌ The file was not shown')
    expect(described_class.show('a/b.abc', workbench)).to be false
    expect(described_class.show('a/b.abc', nil)).to be false
  end

  it 'lets an empty run folder go and keeps one with a file in it' do
    empty = described_class.run_folder(session: nil, workbench: workbench, app_name: 'X')
    kept = described_class.run_folder(session: nil, workbench: workbench, app_name: 'X')
    described_class.keep(kept, 'a.abc', 'X:1')
    [empty, kept, nil].each { |job| described_class.drop_if_empty(job) }
    expect(File.exist?(File.join(@data, empty[:relative]))).to be false
    expect(File.exist?(File.join(@data, kept[:relative], 'a.abc'))).to be true
  end

  it 'tells the model to say only that the file is on the work screen, or to give its path when it is not' do
    expect(described_class.said('The score', 'p/a.abc', shown: true)).to include('p/a.abc', 'work screen', 'do not put its content')
    expect(described_class.said('The score', 'p/a.abc', shown: false)).to include('p/a.abc', 'could not show it')
  end
end
