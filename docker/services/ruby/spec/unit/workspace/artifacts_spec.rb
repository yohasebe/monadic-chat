# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'digest'
require 'json'
require_relative '../../../lib/monadic/workspace'

# What a run makes is kept in the state folder, where only the server writes,
# and recorded with the size and sha256 of the bytes the server wrote. The run
# belongs to the chat the ledger gives for its workspace, or to a folder for
# runs outside any chat.
RSpec.describe Monadic::Workspace::Artifacts do
  around do |example|
    Dir.mktmpdir('artifacts-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      @outside = File.join(dir, 'outside')
      FileUtils.mkdir_p([@data, @outside])
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, 'ledger.json')) }
  let(:ledger_class) { Monadic::Workspace::Ledger }
  let(:disk) { Monadic::Workspace::Ledger::Disk }
  let(:ids) { Monadic::Workspace::Ids }
  let(:jobs) { Monadic::Workspace::Jobs }
  let(:chat_id) { ids.generate(:chat) }
  let(:workspace) { Monadic::Workspace::Folders.ensure_for_chat!(chat_id, app_name: 'Chat', ledger: ledger) }
  let(:job) { jobs.create!(workspace[:workspace_id], ledger: ledger) }
  let(:body) { "WEBVTT\n\n00:00.000 --> 00:01.000\nHello – there\n" }

  def store(kind: 'subtitle_vtt', text: body, run: job)
    described_class.store!(job: run, kind: kind, body: text, ledger: ledger)
  end

  def kept_folders
    root = File.join(@state, 'artifacts')
    File.directory?(root) ? Dir.children(root) : []
  end

  def on_disk
    JSON.parse(File.read(ledger.path))
  end

  describe 'Jobs' do
    it 'gives a run of a chat the chat and workspace the ledger has for it' do
      expect(job[:owner]).to eq(kind: :chat, chat_id: chat_id, workspace_id: workspace[:workspace_id])
      expect(job[:relative]).to eq("#{workspace[:relative_dir]}/artifacts/#{job[:job_id]}")
    end

    it 'refuses a workspace the ledger does not have' do
      expect { jobs.create!(ids.generate(:workspace), ledger: ledger) }.to raise_error(jobs::Unavailable)
    end

    it 'gives a run outside any chat its folder, and only a folder set aside for that' do
      run = jobs.create_outside_chat!('transcriptions')
      expect(run[:owner]).to eq(kind: :outside, root: 'transcriptions')
      expect(run[:relative]).to start_with('transcriptions/artifacts/j_')
      expect { jobs.create_outside_chat!('conversations') }.to raise_error(ArgumentError)
    end
  end

  it 'keeps the bytes in the state folder and records their size and sha256' do
    record = store
    bytes = body.b
    expect(record).to include(owner: 'chat', chat_id: chat_id, job_id: job[:job_id], kind: 'subtitle_vtt',
                              size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes), status: 'ready',
                              copy_path: "#{job[:relative]}/transcript.vtt")
    expect(record[:path]).to eq(described_class.path(record[:artifact_id], 'subtitle_vtt', ledger: ledger))
    expect(record[:path]).to start_with(File.join(@state, 'artifacts', record[:artifact_id]))
    expect(File.binread(record[:path])).to eq(bytes)
    expect(File.stat(record[:path]).mode & 0o777).to eq(0o600)
    expect(File.stat(File.dirname(record[:path])).mode & 0o777).to eq(0o700)
    expect(ledger.artifact(record[:artifact_id])).to include(sha256: record[:sha256])
  end

  it 'records what it wrote, not what the run folder holds later' do
    File.write(File.join(job[:path], 'transcript.vtt'), 'CHANGED')
    record = store
    expect(record[:sha256]).to eq(Digest::SHA256.hexdigest(body.b))
    expect(File.binread(record[:path])).to eq(body.b)
  end

  it 'writes nothing through a run folder replaced by a link' do
    FileUtils.rm_rf(job[:path])
    File.symlink(@outside, job[:path])
    record = store
    expect(Dir.children(@outside)).to be_empty
    expect(File.binread(record[:path])).to eq(body.b)
  end

  it 'records a run outside any chat with its folder and no chat' do
    record = store(kind: 'subtitle_srt', run: jobs.create_outside_chat!('transcriptions'))
    expect(record).to include(owner: 'outside', root: 'transcriptions')
    expect(record).not_to include(:chat_id, :workspace_id)
  end

  it 'gives each call a kept file of its own' do
    first = store
    second = store(text: 'WEBVTT\n')
    expect(first[:path]).not_to eq(second[:path])
    expect(File.binread(first[:path])).to eq(body.b)
  end

  it 'makes nothing while the ledger is no longer written' do
    job
    ledger_class.unsettle!(ledger.path)
    expect { store }.to raise_error(ledger_class::Unsettled)
    expect(kept_folders).to be_empty
  end

  it 'makes nothing while the server is stopping, and runs inside the server\'s writing gate' do
    job
    allow(Monadic::Workspace::ServerOwner).to receive(:writing).and_raise(Monadic::Workspace::ServerOwner::Refused, 'stopping')
    expect { store }.to raise_error(Monadic::Workspace::ServerOwner::Refused)
    expect(kept_folders).to be_empty

    inside = []
    allow(Monadic::Workspace::ServerOwner).to receive(:writing) do |&block|
      inside << :open
      result = block.call
      inside << :closed
      result
    end
    allow(disk).to receive(:create_exclusive).and_wrap_original do |m, *args|
      inside << :write
      m.call(*args)
    end
    store
    expect(inside.first(2)).to eq(%i[open write])
    expect(inside.last).to eq(:closed)
  end

  it 'removes the kept file when the record cannot be made' do
    job
    data = on_disk
    data['workspaces'].clear
    data['chats'].clear
    File.write(ledger.path, JSON.generate(data))
    expect { store }.to raise_error(ledger_class::Conflict)
    expect(kept_folders).to be_empty
  end

  it 'removes the kept file when the ledger is out of form' do
    job
    data = on_disk
    data['workspaces'].each_value { |w| w['app_name'] = 1 }
    File.write(ledger.path, JSON.generate(data))
    expect { store }.to raise_error(ledger_class::Shape)
    expect(kept_folders).to be_empty
  end

  it 'removes what it made when the bytes cannot be written' do
    job
    allow(disk).to receive(:create_exclusive).and_raise(Errno::ENOSPC)
    expect { store }.to raise_error(Errno::ENOSPC)
    expect(kept_folders).to be_empty
    expect(on_disk['artifacts']).to be_empty
  end

  it 'syncs the state folder before recording when it makes the folder of kept artifacts, and only then' do
    job
    state = File.dirname(ledger.path)
    root = File.join(state, described_class::DIRNAME)
    events = []
    allow(disk).to(receive(:sync_dir).and_wrap_original { |m, dir| events << dir; m.call(dir) })
    allow(ledger).to(receive(:register_artifact).and_wrap_original { |m, **kw| events << :record; m.call(**kw) })
    store
    first = events.take_while { |e| e != :record }
    expect(first.last(2)).to eq([root, state])
    events.clear
    store
    second = events.take_while { |e| e != :record }
    expect(second.last).to eq(root)
  end

  it 'removes what it made when its folder cannot be synced, before anything is recorded' do
    job
    allow(disk).to receive(:sync_dir).and_raise(Errno::EIO)
    expect { store }.to raise_error(Errno::EIO)
    expect(kept_folders).to be_empty
    expect(on_disk['artifacts']).to be_empty
  end

  it 'keeps the file once the record is saved, even when the ledger cannot be read afterwards' do
    job
    saved = false
    allow(ledger).to(receive(:save).and_wrap_original { |m, *args| m.call(*args).tap { saved = true } })
    allow(ledger).to receive(:read).and_wrap_original do |m, *args, &blk|
      raise Errno::EIO if saved

      m.call(*args, &blk)
    end
    record = store
    expect(record).to include(kind: 'subtitle_vtt', status: 'ready')
    saved = false
    expect(on_disk['artifacts'].keys).to eq([record[:artifact_id]])
    expect(File.binread(record[:path])).to eq(body.b)
  end

  it 'keeps the file when the record was saved but may not be settled, and writes nothing more' do
    job
    ledger_dir = File.dirname(ledger.path)
    allow(disk).to receive(:sync_dir).and_wrap_original do |m, dir|
      raise Errno::EIO if dir == ledger_dir && !on_disk['artifacts'].empty?

      m.call(dir)
    end
    expect { store }.to raise_error(ledger_class::Unsettled)
    id = on_disk['artifacts'].keys.first
    expect(File.binread(described_class.path(id, 'subtitle_vtt', ledger: ledger))).to eq(body.b)
    expect { store }.to raise_error(ledger_class::Unsettled)
    expect(kept_folders).to eq([id])
  end
end
