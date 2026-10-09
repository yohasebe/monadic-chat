# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'rack/test'
require 'sinatra/base'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/routes/attachment_routes'
require_relative '../../../lib/monadic/utils/local_origin_guard'

RSpec.describe 'Attachments' do
  # lets and methods, not constants or classes: those would be defined at the
  # top level and collide with other specs.
  let(:mp4_head) { "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b }
  let(:webm_head) { "\x1A\x45\xDF\xA3\x9F\x42\x86\x81\x01\x42\xF7\x81".b }
  let(:avi_head) { "RIFF\x00\x10\x00\x00AVI LIST".b }

  around do |example|
    Dir.mktmpdir('attachments-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, 'ledger.json')) }
  let(:ids) { Monadic::Workspace::Ids }
  let(:attachments) { Monadic::Workspace::Attachments }
  let(:chat_id) { ids.generate(:chat) }

  def video(head = mp4_head, size: 4096)
    StringIO.new(head + ('x' * (size - head.bytesize)))
  end

  def accept(name: 'clip.mp4', source: video, chat: chat_id, purpose: 'video')
    attachments.accept!(chat_id: chat, app_name: 'VideoDescriberOpenAI', purpose: purpose,
                        original_name: name, source: source, ledger: ledger)
  end

  describe Monadic::Workspace::FileTypes do
    let(:types) { Monadic::Workspace::FileTypes }

    it 'accepts each video extension with matching leading bytes' do
      { 'a.mp4' => mp4_head, 'a.MOV' => mp4_head, 'a.m4v' => mp4_head,
        'a.webm' => webm_head, 'a.mkv' => webm_head, 'a.avi' => avi_head }.each do |name, head|
        expect { types.check!('video', name, head) }.not_to raise_error, name
      end
    end

    it 'turns away other extensions, renamed files, and unknown purposes' do
      expect { types.check!('video', 'notes.txt', 'hello') }
        .to raise_error(Monadic::Workspace::FileTypes::Rejected) { |e| expect(e.reason).to eq(:extension) }
      expect { types.check!('video', 'fake.mp4', "%PDF-1.7\n" + ('x' * 8)) }
        .to raise_error(Monadic::Workspace::FileTypes::Rejected) { |e| expect(e.reason).to eq(:content) }
      expect { types.check!('video', 'fake.webm', mp4_head) }
        .to raise_error(Monadic::Workspace::FileTypes::Rejected) { |e| expect(e.reason).to eq(:content) }
      expect { types.check!('video', 'short.mp4', 'ab') }
        .to raise_error(Monadic::Workspace::FileTypes::Rejected) { |e| expect(e.reason).to eq(:content) }
      expect { types.check!('script', 'a.mp4', mp4_head) }
        .to raise_error(Monadic::Workspace::FileTypes::Rejected) { |e| expect(e.reason).to eq(:purpose) }
    end
  end

  describe '.accept!' do
    it 'copies the file into the chat folder under a new id and records it ready' do
      source = video(size: 10_000)
      record = accept(source: source)

      expect(record[:status]).to eq('ready')
      expect(record[:attachment_id]).to match(/\Aa_[a-z0-9]{16}\z/)
      expect(record[:size]).to eq(10_000)
      expect(record[:sha256]).to eq(Digest::SHA256.hexdigest(source.string))
      expect(record[:original_name]).to eq('clip.mp4')
      expect(record[:relative_path]).to match(%r{\Aconversations/[^/]+/inputs/#{record[:attachment_id]}__clip\.mp4\z})
      expect(File.binread(File.join(@data, record[:relative_path]))).to eq(source.string)
      expect(ledger.workspace_for_chat(chat_id)[:workspace_id]).to eq(record[:workspace_id])
    end

    it 'keeps two files with the same name apart' do
      first = accept
      second = accept
      expect(second[:attachment_id]).not_to eq(first[:attachment_id])
      expect(second[:relative_path]).not_to eq(first[:relative_path])
      expect(File.exist?(File.join(@data, first[:relative_path]))).to be true
    end

    it 'never lets the name choose where the file goes' do
      ['../../escape.mp4', '..\\..\\escape.mp4', "/etc/passwd\u0000.mp4", ".hidden.mp4", "tab\tnew\nline.mp4"].each do |name|
        record = accept(name: name)
        path = File.join(@data, record[:relative_path])
        expect(File.dirname(path)).to end_with('/inputs'), name
        expect(File.basename(path)).to start_with("#{record[:attachment_id]}__"), name
        expect(File.basename(path)).not_to match(/[\x00-\x1f]/), name
      end
      expect(Dir.children(@data)).to eq(['conversations'])
    end

    it 'shortens long names but keeps the extension and the full display name' do
      long = "#{'長' * 100}.mp4"
      record = accept(name: long)
      stored = File.basename(record[:relative_path]).sub(/\A#{record[:attachment_id]}__/, '')
      expect(stored.bytesize).to be <= Monadic::Workspace::Attachments::NAME_MAX_BYTES
      expect(stored).to end_with('.mp4')
      expect(stored.valid_encoding?).to be true
      expect(record[:original_name]).to eq(long)
    end

    it 'records nothing and creates no folder for a rejected file' do
      expect { accept(name: 'notes.txt', source: StringIO.new('hello')) }
        .to raise_error(Monadic::Workspace::FileTypes::Rejected)
      expect(Dir.children(@data)).to be_empty
      expect(ledger.workspace_for_chat(chat_id)).to be_nil
    end

    it 'marks a failed copy failed and leaves no partial file' do
      source = video
      calls = 0
      allow(source).to receive(:read).and_wrap_original do |original, *args|
        calls += 1
        raise IOError, 'disk gone' if calls == 3

        original.call(*args)
      end
      allow(Monadic::Workspace::Attachments).to receive(:copy_exclusive).and_wrap_original do |original, src, dest, &blk|
        original.call(src, dest) do
          blk&.call
          src.read(10) # the first chunk arrives, then the source fails
        end
      end

      expect { accept(source: source) }.to raise_error(Monadic::Workspace::Attachments::Unusable) { |e| expect(e.reason).to eq(:write_failed) }
      inputs = Dir.glob(File.join(@data, 'conversations', '*', 'inputs', '*'))
      expect(inputs).to be_empty
      failed = JSON.parse(File.read(ledger.path))['attachments'].values
      expect(failed.map { |r| r['status'] }).to eq(['failed'])
    end
  end

  describe '.resolve!' do
    it 'gives a ready attachment to its own chat only' do
      record = accept
      resolved = attachments.resolve!(chat_id: chat_id, attachment_id: record[:attachment_id], ledger: ledger)
      expect(resolved[:path]).to eq(File.join(@data, record[:relative_path]))

      expect { attachments.resolve!(chat_id: ids.generate(:chat), attachment_id: record[:attachment_id], ledger: ledger) }
        .to raise_error(Monadic::Workspace::Attachments::Unusable) { |e| expect(e.reason).to eq(:unknown) }
      expect { attachments.resolve!(chat_id: chat_id, attachment_id: '../a_x', ledger: ledger) }
        .to raise_error(Monadic::Workspace::Attachments::Unusable) { |e| expect(e.reason).to eq(:unknown) }
    end

    it 'refuses an attachment that is not ready' do
      record = accept
      ledger.update_attachment(record[:attachment_id], status: 'validating')
      expect { attachments.resolve!(chat_id: chat_id, attachment_id: record[:attachment_id], ledger: ledger) }
        .to raise_error(Monadic::Workspace::Attachments::Unusable) { |e| expect(e.reason).to eq(:not_ready) }
    end

    it 'reports a file that was removed, changed in size, or replaced by a link' do
      [
        ->(path) { File.unlink(path) },
        ->(path) { File.open(path, 'ab') { |f| f.write('more') } },
        ->(path) { File.unlink(path); File.symlink('/etc/hosts', path) }
      ].each do |damage|
        record = accept
        damage.call(File.join(@data, record[:relative_path]))
        expect { attachments.resolve!(chat_id: chat_id, attachment_id: record[:attachment_id], ledger: ledger) }
          .to raise_error(Monadic::Workspace::Attachments::Unusable) { |e| expect(e.reason).to eq(:missing) }
      end
    end
  end

  describe 'Ledger#reconcile_interrupted!' do
    it 'fails attachments a stopped server left validating, and only those' do
      ready = accept
      stuck = accept
      ledger.update_attachment(stuck[:attachment_id], status: 'validating')
      changed = ledger.reconcile_interrupted!
      expect(changed.map { |r| r[:attachment_id] }).to eq([stuck[:attachment_id]])
      expect(ledger.attachment(stuck[:attachment_id])).to include(status: 'failed', failure: 'interrupted')
      expect(ledger.attachment(ready[:attachment_id])[:status]).to eq('ready')
    end

    it 'does not write when there is nothing to mark' do
      accept
      before = File.mtime(ledger.path)
      sleep 0.01
      expect(ledger.reconcile_interrupted!).to eq([])
      expect(File.mtime(ledger.path)).to eq(before)
    end
  end

  # An input that counts what was read, to show a refusal happened before
  # the body was consumed.
  def counting_input(size, chunk: 65_536)
    Object.new.tap do |input|
      remaining = size
      read_so_far = 0
      input.define_singleton_method(:bytes_read) { read_so_far }
      input.define_singleton_method(:rewind) { nil }
      input.define_singleton_method(:read) do |length = nil, buffer = nil|
        next nil if remaining <= 0

        n = [length || chunk, remaining].min
        remaining -= n
        read_so_far += n
        data = 'x' * n
        buffer ? buffer.replace(data) : data
      end
    end
  end

  describe Monadic::Workspace::UploadLimit do
    let(:downstream) do
      lambda do |env|
        input = env['rack.input']
        input.read(65_536) while input.read(65_536)
        [200, {}, ['read all']]
      end
    end
    let(:limit) { described_class.new(downstream, paths: ['/attachments'], max_bytes: 1_000_000) }

    def env_for(input, length: nil, path: '/attachments')
      env = Rack::MockRequest.env_for(path, method: 'POST')
      env['rack.input'] = input
      length ? env['CONTENT_LENGTH'] = length.to_s : env.delete('CONTENT_LENGTH')
      env
    end

    it 'refuses a declared length over the cap without reading' do
      input = counting_input(50_000_000)
      status, = limit.call(env_for(input, length: 50_000_000))
      expect(status).to eq(413)
      expect(input.bytes_read).to eq(0)
    end

    it 'stops reading an undeclared body once it passes the cap' do
      input = counting_input(50_000_000)
      status, _, body = limit.call(env_for(input))
      expect(status).to eq(413)
      expect(input.bytes_read).to be < 1_200_000
      expect(JSON.parse(body.join)['reason']).to eq('too_large')
    end

    it 'reports the cap even when the app turns the interruption into its own error' do
      swallowing = lambda do |env|
        env['rack.input'].read(2_000_000)
        [500, {}, ['internal error']]
      rescue Monadic::Workspace::UploadLimit::TooLarge
        [500, {}, ['internal error']]
      end
      status, = described_class.new(swallowing, paths: ['/attachments'], max_bytes: 1_000_000)
                                .call(env_for(counting_input(5_000_000)))
      expect(status).to eq(413)
    end

    it 'removes the partial file of an upload it cut off' do
      Dir.mktmpdir('rack-tmp') do |tmp|
        sink = lambda do |env|
          Rack::Request.new(env).POST # the real multipart parser, cut off mid-file
          [200, {}, ['parsed']]
        end
        boundary = 'XyZ'
        head = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"big.mp4\"\r\n" \
               "Content-Type: application/octet-stream\r\n\r\n"
        # Rack reads 1 MB at a time: the cap must fall after the file part
        # has begun, or the cut comes before any temporary file exists.
        body = StringIO.new(head + mp4_head + ('x' * 6_000_000))
        env = Rack::MockRequest.env_for('/attachments', method: 'POST')
        env.delete('CONTENT_LENGTH')
        env['CONTENT_TYPE'] = "multipart/form-data; boundary=#{boundary}"
        env['rack.input'] = body
        made = []
        env['rack.multipart.tempfile_factory'] = lambda do |name, _type|
          Tempfile.new(['part', File.extname(name)], tmp).tap { |file| made << file }
        end

        status, = described_class.new(sink, paths: ['/attachments'], max_bytes: 2_500_000).call(env)
        expect(status).to eq(413)
        expect(made.size).to eq(1) # a partial file was written before the cut
        expect(Dir.children(tmp)).to be_empty
      end
    end

    it 'passes bodies under the cap and other paths through' do
      expect(limit.call(env_for(counting_input(500_000), length: 500_000)).first).to eq(200)
      expect(limit.call(env_for(counting_input(5_000_000), path: '/pdf')).first).to eq(200)
    end
  end

  describe Monadic::Workspace::UploadContext do
    let(:reached) { [] }
    let(:downstream) { ->(env) { reached << env; [200, {}, ['ok']] } }
    let(:states) { {} }
    let(:context) { described_class.new(downstream, paths: ['/attachments'], state_lookup: ->(tab) { states[tab] }) }

    def env_for(headers: {}, query: 'tab_id=t1')
      env = Rack::MockRequest.env_for("http://localhost:4567/attachments?#{query}", method: 'POST')
      env['rack.input'] = counting_input(1_000_000)
      headers.each { |k, v| env[k] = v }
      env
    end

    it 'refuses a tab it does not know before reading the body' do
      env = env_for(query: 'tab_id=unknown')
      expect(context.call(env).first).to eq(409)
      expect(env['rack.input'].bytes_read).to eq(0)
    end

    it 'fixes the chat and app of the tab for the route' do
      states['t1'] = { chat_id: chat_id, parameters: { 'app_name' => 'VideoDescriberOpenAI' } }
      context.call(env_for)
      expect(reached.first[Monadic::Workspace::UploadContext::CHAT_KEY]).to eq(chat_id)
      expect(reached.first[Monadic::Workspace::UploadContext::APP_KEY]).to eq('VideoDescriberOpenAI')
    end
  end

  # The route behind the guard and both middlewares, stacked as config.ru
  # stacks them.
  describe 'POST /attachments' do
    include Rack::Test::Methods

    let(:states) { {} }
    let(:app) do
      web_app = Class.new(Sinatra::Base) do
        set :environment, :test
        register Monadic::Routes::AttachmentRoutes
      end
      lookup = ->(tab) { states[tab] }
      shared_ledger = ledger
      allow(Monadic::Workspace::Ledger).to receive(:default).and_return(shared_ledger)
      Rack::Builder.new do
        use Monadic::Utils::LocalOriginGuard
        use Monadic::Workspace::UploadContext, paths: ['/attachments'], state_lookup: lookup
        use Monadic::Workspace::UploadLimit, paths: ['/attachments'], max_bytes: 100_000
        run web_app
      end
    end

    before do
      states['t1'] = { chat_id: chat_id, parameters: { 'app_name' => 'VideoDescriberOpenAI' } }
      header 'Host', 'localhost:4567'
      header 'Origin', 'http://localhost:4567'
    end

    def upload(name, bytes, purpose: 'video', tab: 't1')
      file = Tempfile.new(['upload', File.extname(name)])
      file.binmode
      file.write(bytes)
      file.rewind
      post "/attachments?tab_id=#{tab}", 'purpose' => purpose,
                                         'file' => Rack::Test::UploadedFile.new(file.path, 'application/octet-stream', true, original_filename: name)
    ensure
      file&.close!
    end

    it 'accepts a video and answers with its id' do
      upload('clip.mp4', video.string)
      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      expect(body).to include('name' => 'clip.mp4', 'size' => 4096, 'purpose' => 'video', 'status' => 'ready')
      expect(attachments.resolve!(chat_id: chat_id, attachment_id: body['attachment_id'], ledger: ledger)[:path]).to start_with(@data)
    end

    it 'answers a wrong type, an oversized file, and a missing file with reasons' do
      upload('notes.txt', 'hello')
      expect([last_response.status, JSON.parse(last_response.body)['reason']]).to eq([415, 'extension'])

      upload('fake.mp4', '%PDF-1.7' + ('x' * 100))
      expect([last_response.status, JSON.parse(last_response.body)['reason']]).to eq([415, 'content'])

      upload('big.mp4', mp4_head + ('x' * 200_000))
      expect([last_response.status, JSON.parse(last_response.body)['reason']]).to eq([413, 'too_large'])

      post '/attachments?tab_id=t1', 'purpose' => 'video'
      expect([last_response.status, JSON.parse(last_response.body)['reason']]).to eq([400, 'no_file'])

      expect(Dir.glob(File.join(@data, '**', 'inputs', '*'))).to be_empty
    end

    it 'refuses another site before reading the body or saving anything' do
      header 'Origin', 'http://evil.example'
      upload('clip.mp4', video.string)
      expect(last_response.status).to eq(403)
      expect(Dir.glob(File.join(@data, '**', 'inputs', '*'))).to be_empty
      expect(ledger.workspace_for_chat(chat_id)).to be_nil
    end

    it 'puts the file in the chat the tab was in when the upload began' do
      later_chat = ids.generate(:chat)
      allow(Monadic::Workspace::Attachments).to receive(:accept!).and_wrap_original do |original, **kwargs|
        states['t1'] = { chat_id: later_chat, parameters: {} } # Reset while the body was arriving
        original.call(**kwargs)
      end
      upload('clip.mp4', video.string)
      id = JSON.parse(last_response.body)['attachment_id']
      expect(ledger.attachment(id)[:chat_id]).to eq(chat_id)
    end
  end
end
