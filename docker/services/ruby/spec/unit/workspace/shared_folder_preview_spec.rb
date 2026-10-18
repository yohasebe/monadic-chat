# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'rack/test'
require 'sinatra/base'
require_relative '../../../lib/monadic/workspace'

# Previews of shared folder files for the Shared Folder panel: which files
# can be previewed, that the file read is the one checked (no link on the
# way, even one swapped in after the check), the beginning of a text file,
# byte ranges, and that only the app's own page may ask.
RSpec.describe Monadic::Workspace::SharedFolderPreview do
  around do |example|
    Dir.mktmpdir('shared-preview-spec') do |dir|
      @data = File.realpath(FileUtils.mkdir_p(File.join(dir, 'data')).first)
      @outside = File.realpath(FileUtils.mkdir_p(File.join(dir, 'outside')).first)
      example.run
    end
  end

  # The ledger and the background size count are this spec's own, not the
  # ones of the machine it runs on.
  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Workspace::Ledger).to receive(:default)
      .and_return(Monadic::Workspace::Ledger.new(File.join(File.dirname(@data), 'state', 'ledger.json')))
    allow(Monadic::Workspace::SharedFolder::Sizes).to receive(:default).and_return(nil)
  end

  def write(relative, body = 'x', root: @data)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, body)
  end

  describe 'kinds' do
    it 'comes from the extension, in any case, and shows HTML, SVG and XML as text' do
      expect(described_class.kind_for('a.PNG')).to eq('image')
      expect(described_class.kind_for('b.mov')).to eq('video')
      expect(described_class.kind_for('c.flac')).to eq('audio')
      expect(described_class.kind_for('d.pdf')).to eq('pdf')
      %w[e.md f.html g.svg h.xml i.csv].each { |n| expect(described_class.kind_for(n)).to eq('text'), n }
      expect(described_class.kind_for('j.exe')).to be_nil
      expect(described_class.kind_for('noext')).to be_nil
      expect(described_class.mime_for('f.html')).to be_nil
    end

    it 'comes with the root a chat uses for the shared folder' do
      expect(Monadic::Workspace::SharedFolder.list('')[:chat_root]).to eq('/monadic/data')
    end

    it 'is given to files in the listing, and not to folders or links' do
      write('pic.png')
      FileUtils.mkdir_p(File.join(@data, 'pics.png'))
      File.symlink(File.join(@data, 'pic.png'), File.join(@data, 'link.png'))
      items = Monadic::Workspace::SharedFolder.list('')[:items].to_h { |i| [i[:name], i[:preview]] }
      expect(items).to include('pic.png' => 'image', 'pics.png' => nil, 'link.png' => nil)
    end
  end

  describe 'opening a file' do
    it 'reads the file checked, in a folder of the shared folder' do
      write('a/b/notes.txt', 'hello')
      expect(described_class.read_text('a/b/notes.txt')[:text]).to eq('hello')
    end

    it 'refuses a link, at the end or on the way' do
      write('real.txt', 'in', root: @outside)
      File.symlink(File.join(@outside, 'real.txt'), File.join(@data, 'end.txt'))
      File.symlink(@outside, File.join(@data, 'way'))
      expect { described_class.read_text('end.txt') }.to raise_error(described_class::Invalid)
      expect { described_class.read_text('way/real.txt') }.to raise_error(described_class::Invalid)
    end

    it 'refuses a folder on the way that was swapped for a link after it was checked' do
      write('a/f.txt', 'in')
      write('f.txt', 'out', root: @outside)
      allow(Monadic::Workspace::SharedFolder).to receive(:folder_at).and_wrap_original do |original, *args|
        result = original.call(*args)
        File.rename(File.join(@data, 'a'), File.join(@data, 'a-moved'))
        File.symlink(@outside, File.join(@data, 'a'))
        result
      end
      expect { described_class.read_text('a/f.txt') }.to raise_error(described_class::Invalid, /not where it was checked/)
    end

    it 'reads a file whose name or folder is not ASCII' do
      write('日本語/café ☕.txt', 'ok')
      expect(described_class.read_text('日本語/café ☕.txt')[:text]).to eq('ok')
    end

    it 'takes each part as the folder spells it' do
      write('Notes/a.txt', 'x')
      expect { described_class.read_text('notes/a.txt') }.to raise_error(described_class::Invalid)
    end

    it 'refuses paths out of the shared folder, kinds it does not preview, and what is not a file' do
      write('a.exe')
      FileUtils.mkdir_p(File.join(@data, 'dir.txt'))
      ['../x.txt', '/etc/hosts', '', 'a.exe', 'dir.txt', 'missing.txt'].each do |path|
        expect { described_class.read_text(path) }.to raise_error(described_class::Invalid), path
      end
    end

    it 'refuses a FIFO without waiting on it' do
      skip 'mkfifo unavailable' unless File.respond_to?(:mkfifo)
      File.mkfifo(File.join(@data, 'pipe.txt'))
      expect { Timeout.timeout(2) { described_class.read_text('pipe.txt') } }.to raise_error(described_class::Invalid)
    end

    it 'opens nothing where the system cannot tell where an open file is' do
      write('a.txt')
      allow(described_class).to receive(:opened_path).and_raise(described_class::Unavailable)
      expect { described_class.read_text('a.txt') }.to raise_error(described_class::Unavailable)
    end
  end

  describe 'text' do
    let(:limit) { described_class::TEXT_LIMIT }

    it 'gives the whole of a short file' do
      write('a.md', "# title\n")
      expect(described_class.read_text('a.md')).to include(text: "# title\n", truncated: false, file_bytes: 8, shown_bytes: 8)
    end

    it 'gives the first TEXT_LIMIT bytes of a long one, leaving out a character cut at the limit' do
      write('long.txt', ('a' * (limit - 1)) + ('あ' * 10))
      result = described_class.read_text('long.txt')
      expect(result[:truncated]).to be(true)
      expect(result[:shown_bytes]).to eq(limit - 1)
      expect(result[:text]).to eq('a' * (limit - 1))
      expect(result[:file_bytes]).to eq(limit - 1 + 30)
    end

    it 'replaces bytes that are not UTF-8, and refuses what holds a NUL byte' do
      write('latin.txt', "caf\xE9")
      expect(described_class.read_text('latin.txt')[:text]).to eq("caf�")
      write('bin.txt', "a\0b")
      expect { described_class.read_text('bin.txt') }.to raise_error(described_class::NotText)
    end
  end

  describe 'ranges' do
    it 'takes one range in each of its three forms' do
      expect(described_class.range_for('bytes=0-9', 100)).to eq([0, 9])
      expect(described_class.range_for('bytes=90-', 100)).to eq([90, 99])
      expect(described_class.range_for('bytes=-10', 100)).to eq([90, 99])
      expect(described_class.range_for('bytes=95-200', 100)).to eq([95, 99])
      expect(described_class.range_for('bytes=-500', 100)).to eq([0, 99])
    end

    it 'cannot satisfy a range past the end, a zero suffix, or any range of an empty file' do
      expect(described_class.range_for('bytes=100-', 100)).to eq(:unsatisfiable)
      expect(described_class.range_for('bytes=-0', 100)).to eq(:unsatisfiable)
      expect(described_class.range_for('bytes=0-', 0)).to eq(:unsatisfiable)
    end

    it 'sends the whole file for what it does not take up' do
      [nil, '', 'items=0-1', 'bytes=0-1,5-6', 'bytes=9-1', 'bytes=x-', "bytes=#{'9' * 30}-", "bytes=0-#{' ' * 300}"].each do |h|
        expect(described_class.range_for(h, 100)).to be_nil, h.inspect
      end
    end
  end

  describe 'the routes' do
    include Rack::Test::Methods

    let(:app) do
      routes = File.expand_path('../../../lib/monadic/routes/shared_folder_routes.rb', __dir__)
      Class.new(Sinatra::Base) do
        set :environment, :test
        helpers { def error_json(message) = { success: false, error: message }.to_json }
        class_eval(File.read(routes), routes)
      end
    end

    before do
      header 'Host', 'localhost'
      stub_const('WebSocketHelper', Module.new { def self.live_chat_ids = [] })
      write('clip.mp4', (0..99).map(&:chr).join)
      write('doc.pdf', '%PDF-1.4')
      write('page.html', '<script>alert(1)</script>')
    end

    def same_origin = header('Sec-Fetch-Site', 'same-origin')

    it 'refuses another site, the same site on another port, and a request that does not say' do
      [nil, 'cross-site', 'same-site', 'none', 'other'].each do |site|
        header 'Sec-Fetch-Site', site
        get '/api/shared_folder/file', path: 'clip.mp4'
        expect(last_response.status).to eq(403), site.inspect
        expect(last_response.headers['cross-origin-resource-policy']).to eq('same-origin')
        get '/api/shared_folder/text', path: 'page.html'
        expect(last_response.status).to eq(403), site.inspect
      end
    end

    it 'sends a media file whole, then a range of it, from the app page' do
      same_origin
      get '/api/shared_folder/file', path: 'clip.mp4'
      expect(last_response.status).to eq(200)
      expect(last_response.headers).to include('content-type' => 'video/mp4', 'content-length' => '100',
                                               'x-content-type-options' => 'nosniff', 'cache-control' => 'no-store',
                                               'accept-ranges' => 'bytes')
      expect(last_response.headers['content-security-policy']).to include('sandbox')
      expect(last_response.body.bytesize).to eq(100)

      header 'Range', 'bytes=10-19'
      get '/api/shared_folder/file', path: 'clip.mp4'
      expect(last_response.status).to eq(206)
      expect(last_response.headers['content-range']).to eq('bytes 10-19/100')
      expect(last_response.body.bytes).to eq((10..19).to_a)

      header 'Range', 'bytes=500-'
      get '/api/shared_folder/file', path: 'clip.mp4'
      expect(last_response.status).to eq(416)
      expect(last_response.headers['content-range']).to eq('bytes */100')
    end

    it 'lets only the app frame a PDF, and sends HTML as text only' do
      same_origin
      get '/api/shared_folder/file', path: 'doc.pdf'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['content-type']).to eq('application/pdf')
      expect(last_response.headers['content-security-policy']).to eq("frame-ancestors 'self'")
      expect(last_response.headers['x-frame-options']).to eq('SAMEORIGIN')

      get '/api/shared_folder/file', path: 'page.html'
      expect(last_response.status).to eq(404)
      get '/api/shared_folder/text', path: 'page.html'
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)['text']).to eq('<script>alert(1)</script>')
      expect(last_response.content_type).to start_with('application/json')
    end

    it 'closes the file it opened, also for HEAD' do
      same_origin
      opened = []
      allow(described_class).to receive(:open_file).and_wrap_original do |original, *args, **kw|
        original.call(*args, **kw).tap { |io, *| opened << io }
      end
      get '/api/shared_folder/file', path: 'clip.mp4'
      head '/api/shared_folder/file', path: 'clip.mp4'
      header 'Range', 'bytes=500-'
      get '/api/shared_folder/file', path: 'clip.mp4'
      expect(opened.size).to eq(3)
      expect(opened).to all(be_closed)
    end

    it 'gives the length of what it sends, as the server sends it (not only as a test client sees it)' do
      env = ->(range) { Rack::MockRequest.env_for('/api/shared_folder/file?path=clip.mp4', 'HTTP_HOST' => 'localhost', 'HTTP_SEC_FETCH_SITE' => 'same-origin', 'HTTP_RANGE' => range) }
      [[nil, 200, '100', 100], ['bytes=10-19', 206, '10', 10]].each do |range, code, length, bytes|
        status, headers, body = app.call(env.call(range))
        sent = +''
        body.each { |chunk| sent << chunk }
        body.close if body.respond_to?(:close)
        expect([status, headers['content-length'], sent.bytesize]).to eq([code, length, bytes]), range.inspect
      end
    end

    it 'gives every matching entry that may go, on every page, for choosing all' do
      250.times { |n| write(format('many/f%03d.txt', n)) }
      write('many/other.md')
      FileUtils.mkdir_p(File.join(@data, 'scripts'))
      get '/api/shared_folder/matching', path: 'many', q: 'f'
      body = JSON.parse(last_response.body)
      expect(body['matched']).to eq(250)
      expect(body['items'].size).to eq(250)
      expect(body['items'].first.keys).to contain_exactly('path', 'kind', 'bytes', 'size_status')
      get '/api/shared_folder/matching', path: ''
      paths = JSON.parse(last_response.body)['items'].map { |i| i['path'] }
      expect(paths).not_to include('scripts') # kept for a purpose: never chosen
    end

    it 'filters the listing by age' do
      write('old.txt')
      File.utime(Time.now - (100 * 86_400), Time.now - (100 * 86_400), File.join(@data, 'old.txt'))
      get '/api/shared_folder', older_than_days: '90'
      names = JSON.parse(last_response.body)['items'].map { |i| i['name'] }
      expect(names).to eq(['old.txt'])
      %w[45 30junk 30.5].each do |days|
        get '/api/shared_folder', older_than_days: days
        expect(last_response.status).to eq(400), days
      end
    end
  end
end
