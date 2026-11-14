# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../../lib/monadic/utils/websocket'

# Opening a notebook in JupyterLab from the page: only a notebook file of the
# shared folder, JupyterLab started only then (and only when it does not
# answer), and the page given the notebook's address once it answers.
RSpec.describe 'Opening a notebook in JupyterLab from the page' do
  let(:host) do
    Class.new do
      include WebSocketHelper
      def sent
        @sent ||= Queue.new
      end

      def send_to_client(_connection, payload)
        sent << payload
      end

      def send_or_broadcast(json, _tab)
        sent << JSON.parse(json)
      end
    end.new
  end
  let(:lab) { Monadic::Utils::JupyterLab }

  around do |example|
    Dir.mktmpdir('jupyter-open-spec') do |dir|
      @data = File.realpath(FileUtils.mkdir_p(File.join(dir, 'data')).first)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).with(:python).and_return(true)
    Thread.current[:websocket_session_id] = 'tab-jupyter'
    FileUtils.mkdir_p(File.join(@data, 'work'))
    File.write(File.join(@data, 'work', 'my analysis.ipynb'), '{"cells": []}')
  end

  after { Thread.current[:websocket_session_id] = nil }

  def answer
    Timeout.timeout(5) { host.sent.pop }
  end

  def open(path, request: 'r1')
    host.send(:handle_ws_jupyter_open, nil, { 'path' => path, 'request' => request }, {})
    answer
  end

  it 'starts JupyterLab for a notebook of the shared folder and gives its address once it answers' do
    expect(lab).to receive(:start).once.and_return(true)
    expect(open('work/my analysis.ipynb')).to eq(
      'type' => 'jupyter_opened', 'request' => 'r1', 'success' => true,
      'url' => "#{lab.base_url}/lab/tree/work/my%20analysis.ipynb"
    )
  end

  it 'starts nothing for what is not a notebook file of the shared folder' do
    expect(lab).not_to receive(:start)
    File.write(File.join(@data, 'notes.txt'), 'x')
    FileUtils.mkdir_p(File.join(@data, 'folder.ipynb'))
    File.symlink(File.join(@data, 'work', 'my analysis.ipynb'), File.join(@data, 'link.ipynb'))
    ['notes.txt', 'folder.ipynb', 'link.ipynb', 'missing.ipynb', '../outside.ipynb', '/etc/x.ipynb',
     'work/../work/my analysis.ipynb', 'Work/my analysis.ipynb', "x\0.ipynb", ''].each do |path|
      expect(open(path)).to include('success' => false, 'error' => 'not_a_notebook'), path.inspect
    end
  end

  it 'starts the Python container first when it is not running, and says so' do
    allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).with(:python).and_return(false)
    expect(Monadic::Utils::ContainerDependencies).to receive(:start_service_async).with(:python, reason: kind_of(String))
    expect(lab).not_to receive(:start)
    expect(open('work/my analysis.ipynb')).to include('success' => false, 'error' => 'python_starting')
  end

  it 'says JupyterLab did not start, with no address' do
    allow(lab).to receive(:start).and_return(false)
    expect(open('work/my analysis.ipynb')).to eq('type' => 'jupyter_opened', 'request' => 'r1',
                                                  'success' => false, 'error' => 'not_started')
  end

  describe Monadic::Utils::JupyterLab do
    it 'starts JupyterLab with run_jupyter.sh in the Python container, given longer than the script waits' do
      status = instance_double(Process::Status, success?: true)
      expect(Monadic::Shell).to receive(:exec)
        .with(container: :python, argv: %w[run_jupyter.sh run], timeout: described_class::START_LIMIT)
        .and_return(["JupyterLab is running.\n", '', status])
      expect(described_class.start).to be(true)
      expect(described_class::START_LIMIT).to be > 90
    end

    it 'takes an error, a failed run or a failure to run as not started' do
      failed = instance_double(Process::Status, success?: false)
      allow(Monadic::Shell).to receive(:exec).and_return(["Error: JupyterLab did not answer in time.\n", '', failed])
      expect(described_class.start).to be(false)
      allow(Monadic::Shell).to receive(:exec).and_raise(Errno::ENOENT)
      expect(described_class.start).to be(false)
      quiet = instance_double(Process::Status, success?: true)
      allow(Monadic::Shell).to receive(:exec).and_return(["Usage: run_jupyter.sh {run|stop|status}\n", '', quiet])
      expect(described_class.start).to be(false)
    end

    it 'names the notebook by each part of its path, encoded' do
      expect(described_class.notebook_url('a b/c#d?.ipynb')).to eq("#{described_class.base_url}/lab/tree/a%20b/c%23d%3F.ipynb")
    end
  end
end
