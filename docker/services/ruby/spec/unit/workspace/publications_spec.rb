# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'digest'
require 'json'
require 'time'
require 'timeout'
require_relative '../../../lib/monadic/workspace'

# What the page loads by a pub_ name is a publication: a copy of an
# attachment or an artifact of a chat, made in the state folder from the
# bytes read once from the source and servable only when those bytes are the
# ones the ledger recorded. Every pub_ name is answered from the ledger.
RSpec.describe Monadic::Workspace::Publications do
  around do |example|
    Dir.mktmpdir('publications-spec') do |dir|
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

  let(:pubs) { described_class }
  let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, 'ledger.json')) }
  let(:ledger_class) { Monadic::Workspace::Ledger }
  let(:ids) { Monadic::Workspace::Ids }
  let(:chat_id) { ids.generate(:chat) }
  let(:workspace) { Monadic::Workspace::Folders.ensure_for_chat!(chat_id, app_name: 'Chat', ledger: ledger) }
  let(:video) { "\x00\x00\x00\x18ftypmp42".b + ('v' * 3000) }

  def attach(bytes = video)
    id = ids.generate(:attachment)
    relative = "#{workspace[:relative_dir]}/inputs/#{id}__clip.mp4"
    ledger.register_attachment(attachment_id: id, chat_id: chat_id, workspace_id: workspace[:workspace_id],
                               purpose: 'video', original_name: 'clip.mp4', relative_path: relative)
    path = File.join(File.realpath(@data), relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes)
    ledger.update_attachment(id, status: 'ready', 'size' => bytes.bytesize, 'sha256' => Digest::SHA256.hexdigest(bytes))
    { id: id, path: path }
  end

  def publish(source)
    pubs.create!(kind: 'attachment', id: source[:id], ledger: ledger)
  end

  def copy_of(record)
    File.join(@state, 'publications', record[:publication_id], record[:name])
  end

  def folders
    root = File.join(@state, 'publications')
    File.directory?(root) ? Dir.children(root) : []
  end

  def get(name, env = {})
    status, headers, body = pubs.response(name, { 'REQUEST_METHOD' => 'GET' }.merge(env), ledger: ledger)
    text = +''
    body.each { |chunk| text << chunk }
    body.close if body.respond_to?(:close)
    [status, headers, text]
  end

  describe 'making a publication' do
    it "copies an attachment's bytes, checked against the ledger, where only the server writes" do
      record = publish(attach)
      expect(record).to include(status: 'ready', chat_id: chat_id, content_type: 'video/mp4', sha256: Digest::SHA256.hexdigest(video))
      expect(record[:name]).to match(/\Apub_[a-z0-9]{16}\.mp4\z/)
      expect(File.binread(copy_of(record))).to eq(video)
      expect(File.stat(copy_of(record)).mode & 0o777).to eq(0o600)
      expect(Dir.glob(File.join(@data, 'pub_*'))).to be_empty
    end

    it 'uses the ready one again while its copy is there, and makes a new one when it is gone' do
      source = attach
      first = publish(source)
      expect(publish(source)[:name]).to eq(first[:name])
      File.delete(copy_of(first))
      second = publish(source)
      expect(second[:name]).not_to eq(first[:name])
      expect(ledger.publication_named(first[:name])[:status]).to eq('missing')
      expect(File.binread(copy_of(second))).to eq(video)
    end

    it 'makes a new one when the copy was changed to other bytes of the same size, after it was served' do
      source = attach
      first = publish(source)
      expect(get(first[:name]).first).to eq(200)
      copy = copy_of(first)
      times = [File.atime(copy), File.mtime(copy)]
      File.binwrite(copy, video.tr('v', 'w'))
      File.utime(*times, copy)
      expect(get(first[:name]).first).to eq(404)
      second = publish(source)
      expect(second[:name]).not_to eq(first[:name])
      expect(ledger.publication_named(first[:name])[:status]).to eq('missing')
      expect(get(second[:name])).to match([200, anything, video])
    end

    it 'does not take a copy that cannot be read now for one that is gone' do
      source = attach
      first = publish(source)
      File.chmod(0o000, copy_of(first))
      expect { publish(source) }.to raise_error(described_class::Unavailable)
      expect(ledger.publication_named(first[:name])[:status]).to eq('ready')
    ensure
      File.chmod(0o600, copy_of(first)) if first
    end

    it 'publishes nothing when the attached file was changed, even to the same size, or grew' do
      source = attach
      File.binwrite(source[:path], video.tr('v', 'w'))
      expect { publish(source) }.to raise_error(described_class::Changed)
      File.binwrite(source[:path], "#{video}more")
      expect { publish(source) }.to raise_error(described_class::Changed)
      expect(ledger.publications).to be_empty
      expect(folders).to be_empty
    end

    it 'publishes nothing behind a link put in place of the attached file' do
      source = attach
      secret = File.join(@outside, 'env')
      File.binwrite(secret, video)
      File.delete(source[:path])
      File.symlink(secret, source[:path])
      expect { publish(source) }.to raise_error(StandardError)
      expect(ledger.publications).to be_empty
      expect(folders).to be_empty
    end

    it 'refuses while the same source is being published' do
      source = attach
      reserved = ids.generate(:publication)
      ledger.reserve_publication(publication_id: reserved, name: "pub_#{reserved.delete_prefix('p_')}.mp4", token: 'b' * 16,
                                 kind: 'attachment', id: source[:id], cap_bytes: described_class::CAP_BYTES)
      expect { publish(source) }.to raise_error(described_class::Unavailable)
    end

    it 'does not make ready a publication revoked while it was copied, and removes its copy' do
      source = attach
      allow(ledger_class::Disk).to receive(:sync_dir).and_wrap_original do |m, dir|
        if dir.include?('/publications/p_')
          live = ledger.live_publication('attachment', source[:id])
          ledger.mark_publication(live[:publication_id], status: 'revoked', from: %w[pending])
        end
        m.call(dir)
      end
      expect { publish(source) }.to raise_error(described_class::Unavailable)
      expect(ledger.publications.map { |r| r[:status] }).to eq(['revoked'])
      expect(folders).to be_empty
    end

    it 'removes what it made when a step fails before the record is ready' do
      source = attach
      allow(ledger_class::Disk).to receive(:sync_dir).and_wrap_original do |m, dir|
        raise Errno::EIO if dir.include?('/publications/p_')

        m.call(dir)
      end
      expect { publish(source) }.to raise_error(Errno::EIO)
      expect(ledger.publications).to be_empty
      expect(folders).to be_empty
    end

    it 'keeps the copy when the ready record may not be settled, and the next start removes it if it stayed pending' do
      source = attach
      allow(ledger).to receive(:settle_publication).and_raise(ledger_class::Unsettled, 'not settled')
      expect { publish(source) }.to raise_error(ledger_class::Unsettled)
      pending = ledger.publications.first
      expect(pending[:status]).to eq('pending')
      expect(File.binread(copy_of(pending))).to eq(video)

      ledger_class.clear_unsettled!
      expect(pubs.reconcile!(ledger: ledger)).to eq([])
      expect(ledger.publications).to be_empty
      expect(folders).to be_empty
    end

    it 'keeps the ready record and its copy when only the sync after it fails, and serves it after the next start' do
      source = attach
      state_dir = File.dirname(ledger.path)
      allow(ledger_class::Disk).to receive(:sync_dir).and_wrap_original do |m, dir|
        on_disk = File.exist?(ledger.path) ? JSON.parse(File.read(ledger.path))['publications'].values : []
        raise Errno::EIO if dir == state_dir && on_disk.any? { |r| r['status'] == 'ready' }

        m.call(dir)
      end
      expect { publish(source) }.to raise_error(ledger_class::Unsettled)
      allow(ledger_class::Disk).to receive(:sync_dir).and_call_original
      ledger_class.clear_unsettled!
      record = ledger.publications.first
      expect(record[:status]).to eq('ready')
      expect(pubs.reconcile!(ledger: ledger)).to eq([])
      expect(get(record[:name]).first).to eq(200)
    end

    it 'refuses when the copies would take more room than allowed, or leave the disk too full' do
      source = attach
      stub_const("#{described_class}::CAP_BYTES", video.bytesize - 1)
      expect { publish(source) }.to raise_error(described_class::Unavailable, /more room/)
      stub_const("#{described_class}::CAP_BYTES", 10 * 1024**3)
      allow(pubs).to receive(:free_bytes).and_return(described_class::FREE_FLOOR_BYTES + video.bytesize - 1)
      expect { publish(source) }.to raise_error(described_class::Unavailable, /free space/)
      expect(ledger.publications).to be_empty
      expect(folders).to be_empty
    end

    it 'makes one publication when the same source is published twice at once' do
      source = attach
      results = Array.new(2) do
        Thread.new do
          publish(source)[:name]
        rescue described_class::Unavailable
          :refused
        end
      end.map(&:value)
      names = results - [:refused]
      expect(names.uniq.size).to eq(1)
      expect(ledger.publications.map { |r| r[:status] }).to eq(['ready'])
      expect(folders.size).to eq(1)
    end

    it 'leaves alone a folder already there under the id it drew, and records nothing' do
      source = attach
      taken = ids.generate(:publication)
      allow(ids).to receive(:generate).and_call_original
      allow(ids).to receive(:generate).with(:publication).and_return(taken)
      sentinel = File.join(@state, 'publications', taken, 'sentinel')
      FileUtils.mkdir_p(File.dirname(sentinel))
      File.write(sentinel, 'kept')
      expect { publish(source) }.to raise_error(Errno::EEXIST)
      expect(File.read(sentinel)).to eq('kept')
      expect(ledger.publications).to be_empty
    end

    it 'keeps the pending record while its copy is not gone, and the next start removes both' do
      source = attach
      allow(ledger_class::Disk).to receive(:sync_dir).and_wrap_original do |m, dir|
        raise Errno::EIO if dir.include?('/publications/p_')

        m.call(dir)
      end
      allow(FileUtils).to receive(:rm_r).and_raise(Errno::EACCES)
      expect { publish(source) }.to raise_error(Errno::EIO)
      expect(ledger.publications.map { |r| r[:status] }).to eq(['pending'])
      expect(folders.size).to eq(1)

      expect(pubs.reconcile!(ledger: ledger)).to eq([])
      expect(ledger.publications.map { |r| r[:status] }).to eq(['pending'])

      allow(FileUtils).to receive(:rm_r).and_call_original
      pubs.reconcile!(ledger: ledger)
      expect(ledger.publications).to be_empty
      expect(folders).to be_empty
    end

    it 'keeps the pending record while the folder of the copies cannot be searched' do
      source = attach
      reserved = ids.generate(:publication)
      pending = ledger.reserve_publication(publication_id: reserved, name: "pub_#{reserved.delete_prefix('p_')}.mp4", token: 'd' * 16,
                                           kind: 'attachment', id: source[:id], cap_bytes: described_class::CAP_BYTES)
      FileUtils.mkdir_p(File.dirname(copy_of(pending)))
      File.binwrite(copy_of(pending), video)
      root = File.join(@state, 'publications')
      File.chmod(0o000, root)
      pubs.reconcile!(ledger: ledger)
      File.chmod(0o700, root)
      expect(ledger.publications.map { |r| r[:status] }).to eq(['pending'])
      expect(File.exist?(copy_of(pending))).to be(true)

      pubs.reconcile!(ledger: ledger)
      expect(ledger.publications).to be_empty
      expect(folders).to be_empty
    ensure
      File.chmod(0o700, root) if root && File.exist?(root)
    end

    it 'checks the free space for one copy at a time, counting the copies made before it' do
      first = attach
      second = attach(video.tr('v', 'x'))
      base = described_class::FREE_FLOOR_BYTES + video.bytesize + 10
      asked = Queue.new
      allow(pubs).to receive(:free_bytes) do
        asked << true
        base - Dir.glob(File.join(@state, 'publications', '*', '*')).sum { |f| File.size(f) }
      end
      paused = false
      allow(ledger_class::Disk).to receive(:sync_dir).and_wrap_original do |m, dir|
        if dir.include?('/publications/p_') && !paused
          paused = true
          # Gives the other publication the chance to check the free space
          # while this copy is on the disk but not yet ready.
          2.times { Timeout.timeout(1) { asked.pop } rescue nil }
        end
        m.call(dir)
      end
      results = [first, second].map do |source|
        Thread.new do
          publish(source)[:status]
        rescue described_class::Unavailable
          'refused'
        end
      end.map(&:value)
      expect(results.sort).to eq(%w[ready refused])
    end

    it "publishes a chat's artifact, and nothing a run outside any chat made" do
      chat_job = Monadic::Workspace::Jobs.create!(workspace[:workspace_id], ledger: ledger)
      kept = Monadic::Workspace::Artifacts.store!(job: chat_job, kind: 'subtitle_vtt', body: "WEBVTT\n", ledger: ledger)
      record = pubs.create!(kind: 'artifact', id: kept[:artifact_id], ledger: ledger)
      expect(record).to include(status: 'ready', content_type: 'text/vtt')
      expect(File.read(copy_of(record))).to eq("WEBVTT\n")

      outside_job = Monadic::Workspace::Jobs.create_outside_chat!('transcriptions')
      outside = Monadic::Workspace::Artifacts.store!(job: outside_job, kind: 'subtitle_vtt', body: "WEBVTT\n", ledger: ledger)
      expect { pubs.create!(kind: 'artifact', id: outside[:artifact_id], ledger: ledger) }.to raise_error(described_class::Unavailable)
    end
  end

  describe 'serving' do
    it 'serves a ready publication from its copy: whole, a range, HEAD, and 304 for a current copy' do
      record = publish(attach)
      status, headers, text = get(record[:name])
      expect([status, text, headers['content-type'], headers['x-content-type-options']]).to eq([200, video, 'video/mp4', 'nosniff'])
      status, headers, text = get(record[:name], 'HTTP_RANGE' => 'bytes=0-3')
      expect([status, text, headers['content-range']]).to eq([206, video[0, 4], "bytes 0-3/#{video.bytesize}"])
      expect(pubs.response(record[:name], { 'REQUEST_METHOD' => 'HEAD' }, ledger: ledger)[2]).to eq([])
      since = (File.mtime(copy_of(record)) + 10).httpdate
      expect(get(record[:name], 'HTTP_IF_MODIFIED_SINCE' => since).first).to eq(304)
    end

    it "answers 404 for every other pub_ name, and never serves the shared folder's file of that name" do
      source = attach
      record = publish(source)
      old = "pub_#{source[:id]}.mp4"
      File.binwrite(File.join(@data, old), video)
      File.binwrite(File.join(@data, "pub_j_#{'a' * 16}.vtt"), "WEBVTT\n")
      [old, "pub_j_#{'a' * 16}.vtt", record[:name].upcase, "pub_#{'0' * 16}.mp4", 'pub_', "pub_#{'a' * 16}.exe"].each do |name|
        expect(get(name).first).to eq(404), name
        expect(get(name, 'HTTP_RANGE' => 'bytes=0-3').first).to eq(404), name
      end

      File.delete(copy_of(record))
      File.binwrite(File.join(@data, record[:name]), video)
      expect(get(record[:name]).first).to eq(404)
    end

    it 'serves nothing pending or revoked' do
      source = attach
      reserved = ids.generate(:publication)
      pending = ledger.reserve_publication(publication_id: reserved, name: "pub_#{reserved.delete_prefix('p_')}.mp4", token: 'd' * 16,
                                           kind: 'attachment', id: source[:id], cap_bytes: described_class::CAP_BYTES)
      expect(get(pending[:name]).first).to eq(404)
      ledger.drop_publication(pending[:publication_id], 'd' * 16)
      record = publish(source)
      ledger.mark_publication(record[:publication_id], status: 'revoked', from: %w[ready])
      expect(get(record[:name]).first).to eq(404)
    end

    it 'serves no copy whose bytes were changed in the state folder, even to the same size and times' do
      record = publish(attach)
      expect(get(record[:name]).first).to eq(200)
      copy = copy_of(record)
      times = [File.atime(copy), File.mtime(copy)]
      File.binwrite(copy, video.tr('v', 'w'))
      File.utime(*times, copy)
      expect(get(record[:name]).first).to eq(404)
      expect(get(record[:name], 'HTTP_RANGE' => 'bytes=0-3').first).to eq(404)
    end

    it "serves nothing while its chat's folder is a link, even to the folder itself" do
      record = publish(attach)
      chat_dir = File.join(File.realpath(@data), workspace[:relative_dir])
      moved = "#{chat_dir}.moved"
      File.rename(chat_dir, moved)
      File.symlink(moved, chat_dir)
      expect(get(record[:name]).first).to eq(404)
    end

    it "stops serving while its chat's folder cannot be found, and removes nothing for that" do
      record = publish(attach)
      chat_dir = File.join(File.realpath(@data), workspace[:relative_dir])
      moved = "#{chat_dir}.moved"
      File.rename(chat_dir, moved)
      expect(get(record[:name]).first).to eq(404)
      expect(ledger.publication_named(record[:name])[:status]).to eq('ready')
      expect(File.exist?(copy_of(record))).to be(true)
      File.rename(moved, chat_dir)
      expect(get(record[:name]).first).to eq(200)
    end

    it 'takes any name starting with pub_, in any case, as a publication name, and a name that is not UTF-8 as none' do
      expect(['pub_x', 'PUB_x', 'Pub_', "pub_#{'a' * 16}.mp4"].map { |n| pubs.public_name?(n) }).to all(be(true))
      expect(['pubx', 'xpub_', "\xFF\xFEpub_".b, ''].map { |n| pubs.public_name?(n) }).to all(be(false))
    end
  end

  describe 'at start' do
    it "revokes the publications whose chat's folder is gone, and removes their copies" do
      record = publish(attach)
      FileUtils.rm_rf(File.join(File.realpath(@data), workspace[:relative_dir]))
      # Not served from the next request on; revoked and removed at the next start.
      expect(get(record[:name]).first).to eq(404)
      expect(pubs.reconcile!(ledger: ledger)).to eq([record[:publication_id]])
      expect(ledger.publication_named(record[:name])[:status]).to eq('revoked')
      expect(folders).to be_empty
      expect(get(record[:name]).first).to eq(404)
    end

    it "leaves a publication whose chat's folder cannot be read, and everything when the ledger cannot be read" do
      record = publish(attach)
      chat_dir = File.join(File.realpath(@data), workspace[:relative_dir])
      allow(File).to receive(:lstat).and_call_original
      allow(File).to receive(:lstat).with(chat_dir).and_raise(Errno::EACCES)
      expect(pubs.reconcile!(ledger: ledger)).to eq([])
      expect(ledger.publication_named(record[:name])[:status]).to eq('ready')

      FileUtils.rm_rf(chat_dir)
      File.write(ledger.path, '{not json')
      expect(pubs.reconcile!(ledger: ledger)).to eq([])
      expect(File.exist?(copy_of(record))).to be(true)
    end
  end
end
