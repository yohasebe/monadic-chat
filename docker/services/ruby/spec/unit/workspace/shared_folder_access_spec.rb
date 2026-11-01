# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/monadic/workspace'

RSpec.describe Monadic::Workspace::SharedFolder do
  around do |example|
    Dir.mktmpdir('shared-access-spec') do |dir|
      @root = File.realpath(dir)
      @data = File.join(@root, 'data')
      FileUtils.mkdir_p(@data)
      example.run
    end
  end

  before { allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data) }

  let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@root, 'state', 'ledger.json')) }
  let(:id_path) { File.join(@data, described_class::ROOT_ID_FILE) }

  [32, 64, 65, 4096].each do |size|
    it "accepts only ID files within the byte limit (#{size} bytes)" do
      id = 'a' * 32
      File.write(id_path, id.ljust(size))
      if size <= 64
        expect(described_class.root_id).to eq(id)
      else
        expect { described_class.root_id }.to raise_error(described_class::Invalid)
      end
    end
  end

  it 'refuses an ID file swapped for a link before opening' do
    File.write(id_path, 'a' * 32)
    other = File.join(@root, 'other-id')
    File.write(other, 'a' * 32)
    allow(Monadic::Utils::SharedFs).to receive(:open_read).and_wrap_original do |read, *args|
      File.unlink(id_path)
      File.symlink(other, id_path)
      read.call(*args)
    end
    expect { described_class.root_id }.to raise_error(described_class::Invalid)
  end

  it 'refuses a FIFO without waiting for a writer' do
    File.mkfifo(id_path)
    expect { described_class.root_id }.to raise_error(described_class::Invalid)
  end

  it 'closes the ID file when a read fails' do
    File.write(id_path, 'a' * 32)
    opened = nil
    allow(Monadic::Utils::SharedFs).to receive(:open_read).and_wrap_original do |read, *args|
      opened = read.call(*args)
      allow(opened).to receive(:read).and_raise(IOError)
      opened
    end
    expect { described_class.root_id }.to raise_error(IOError)
    expect(opened).to be_closed
  end

  describe 'checking entries for removal' do
    let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
    let(:workspace) { Monadic::Workspace::Ids.generate(:workspace) }
    let(:relative) { "conversations/#{workspace}" }

    before do
      FileUtils.mkdir_p(File.join(@data, relative))
      ledger.register_workspace(chat_id: chat, workspace_id: workspace, app_name: 'Chat', relative_dir: relative)
      4.times { |n| File.write(File.join(@data, relative, "file#{n}.txt"), 'x') }
    end

    it 'reuses the validated ledger and the listing of an unchanged folder' do
      allow(ledger).to receive(:snapshot).and_call_original
      allow(Dir).to receive(:children).and_call_original
      4.times do |n|
        path = "#{relative}/file#{n}.txt"
        expect(described_class.entry(path, ledger: ledger)[:capabilities][:trash]).to be true
        expect(described_class.entry(path, ledger: ledger, live_chat_ids: [chat])[:capabilities][:trash]).to be false
      end
      expect(ledger).to have_received(:snapshot).once
      expect(Dir).to have_received(:children).with(File.join(@data, relative)).once

      File.unlink(File.join(@data, relative, 'file0.txt'))
      expect { described_class.entry("#{relative}/file0.txt", ledger: ledger) }.to raise_error(described_class::Invalid)
      expect(Dir).to have_received(:children).with(File.join(@data, relative)).twice
    end

    it "refuses a chat's folder asked for in another spelling, whatever path an open file reports" do
      allow(Monadic::Workspace::SharedFolderPreview).to receive(:opened_path) do |io|
        io.respond_to?(:path) ? io.path : nil
      end
      upper = "Conversations/#{workspace}"
      expect { described_class.entry(upper, ledger: ledger, live_chat_ids: [chat]) }.to raise_error(described_class::Invalid)
      expect { described_class.entry("#{upper}/file0.txt", ledger: ledger) }.to raise_error(described_class::Invalid)
      expect(described_class.entry(relative, ledger: ledger, live_chat_ids: [chat])[:capabilities][:trash]).to be false
    end

    it 'can check an unreadable file by its exact directory entry' do
      path = File.join(@data, relative, 'file0.txt')
      File.chmod(0o000, path)
      expect(described_class.entry("#{relative}/file0.txt", ledger: ledger)[:capabilities][:trash]).to be true
      expect { described_class.entry("#{relative}/FILE0.txt", ledger: ledger) }.to raise_error(described_class::Invalid)
    ensure
      File.chmod(0o600, path) if path
    end

    it 'refreshes ownership when the ledger is replaced' do
      path = "#{relative}/file0.txt"
      expect(described_class.entry(path, ledger: ledger, live_chat_ids: [chat])[:capabilities][:trash]).to be false
      other = Monadic::Workspace::Ids.generate(:chat)
      ledger.register_workspace(chat_id: other, workspace_id: Monadic::Workspace::Ids.generate(:workspace),
                                app_name: 'Chat', relative_dir: 'conversations/other')
      FileUtils.mkdir_p(File.join(@data, 'conversations/other'))
      expect(described_class.entry('conversations/other', ledger: ledger, live_chat_ids: [other])[:capabilities][:trash]).to be false
      expect(described_class.entry(path, ledger: ledger, live_chat_ids: [chat])[:capabilities][:trash]).to be false
    end

    it 'refuses removal when a previously valid ledger becomes unreadable, and recovers after replacement' do
      path = "#{relative}/file0.txt"
      expect(described_class.entry(path, ledger: ledger)[:capabilities][:trash]).to be true
      valid = File.binread(ledger.path)
      File.write(ledger.path, '{')
      expect(described_class.entry(path, ledger: ledger)[:capabilities][:trash]).to be false
      File.write(ledger.path, valid)
      expect(described_class.entry(path, ledger: ledger, live_chat_ids: [chat])[:capabilities][:trash]).to be false
    end

    it 'refuses old spelling after a case-only rename and paths through replaced parents' do
      path = "#{relative}/file0.txt"
      expect(described_class.entry(path, ledger: ledger)[:capabilities][:trash]).to be true
      File.rename(File.join(@data, path), File.join(@data, relative, 'FILE0.txt'))
      expect { described_class.entry(path, ledger: ledger) }.to raise_error(described_class::Invalid)
      moved = File.join(@root, 'moved')
      File.rename(File.join(@data, relative), moved)
      File.symlink(moved, File.join(@data, relative))
      expect { described_class.entry("#{relative}/file1.txt", ledger: ledger) }.to raise_error(described_class::Invalid)
    end
  end
end
