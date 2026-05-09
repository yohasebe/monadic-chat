# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra'

# Network-level contract for /library/import (asynchronous since
# beta.16) and /library/import/status/:id.
#
# Goals:
#   1. POST returns 202 + a JSON envelope with `import_id` and
#      `status_url`. The body of work runs in a background thread.
#   2. The worker thread invokes FileImporter.build_conversation +
#      Manager.import_conversation exactly once on success, with the
#      right scope_app / file path. The ImportTracker entry transitions
#      to stage='done' with conversation_id and per-segment counts.
#   3. Oversized uploads are rejected before the extractor or the
#      worker thread is ever set up.
#   4. Errors raised by the worker land on the tracker as stage='error'.
#
# Real PDF extraction is out of scope; that needs Docker (covered by
# spec/integration/docker_smoke/). To make the test deterministic we
# stub Thread.new to execute its block synchronously — the production
# path uses a real thread, but the contract we want to lock down is
# what the worker writes to the tracker, which is identical.

RSpec.describe '/library/import contract', :integration do
  include Rack::Test::Methods

  before(:all) do
    require_relative '../../lib/monadic/utils/environment'
    require_relative '../../lib/monadic/version'

    Sinatra::Application.helpers do
      def error_json(message)
        { 'success' => false, 'error' => message }.to_json
      end
    end

    require_relative '../../lib/monadic/routes/library_import_routes'
  end

  def app
    Sinatra::Application
  end

  before do
    header 'Host', '127.0.0.1'

    # Pin the upload destination so the test does not touch /monadic/data
    # under IN_CONTAINER=true. Real PDF/MD content is irrelevant; we
    # only need a writable path.
    @tmp_data_dir = Dir.mktmpdir('monadic-data-test')
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@tmp_data_dir)

    # Run the worker block synchronously so we can assert tracker state
    # immediately after POST returns. Production uses Thread.new with
    # real concurrency; the block's contract (what it writes to the
    # tracker) is the same in both modes.
    allow(Thread).to receive(:new) do |&blk|
      blk.call
      double('Thread', :report_on_exception= => nil, join: nil)
    end

    Monadic::Library::ImportTracker.reset!
  end

  after do
    FileUtils.remove_entry(@tmp_data_dir) if @tmp_data_dir && Dir.exist?(@tmp_data_dir)
    Monadic::Library::ImportTracker.reset!
  end

  let(:fake_conversation) do
    {
      'header' => { 'title' => 'Sample', 'language' => 'en' },
      'messages' => [{ 'id' => 'm1', 'speaker' => { 'id' => 'doc' }, 'text' => 'hello' }],
      'participants' => [{ 'id' => 'doc', 'role' => 'narrator' }]
    }
  end

  let(:import_result) do
    { conversation_id: 'conv-test-123', counts: { summaries: 1, turns: 1, messages: 1 } }
  end

  describe 'happy path' do
    it 'returns 202 with import_id + status_url, and dispatches through FileImporter + Manager' do
      file = Rack::Test::UploadedFile.new(
        StringIO.new('# Hello'), 'text/markdown', original_filename: 'hello.md'
      )

      expect(Monadic::Library::FileImporter)
        .to receive(:build_conversation)
        .with(hash_including(filename: 'hello.md'))
        .and_return(fake_conversation)

      fake_store = instance_double(Monadic::Library::Store)
      allow(Monadic::Library::Store).to receive(:new).and_return(fake_store)

      expect(Monadic::Library::Manager)
        .to receive(:import_conversation)
        .with(hash_including(store: fake_store, conversation: fake_conversation))
        .and_return(import_result)

      post '/library/import', { 'libraryFile' => file }

      expect(last_response.status).to eq(202)
      expect(last_response.content_type).to start_with('application/json')
      data = JSON.parse(last_response.body)
      expect(data).to include('success' => true, 'filename' => 'hello.md', 'scope_app' => 'Global')
      expect(data['import_id']).to match(/\A[0-9a-f-]{36}\z/)
      expect(data['status_url']).to eq("/library/import/status/#{data['import_id']}")

      # Worker has run synchronously — tracker entry should now reflect 'done'.
      entry = Monadic::Library::ImportTracker.get(data['import_id'])
      expect(entry).to include(stage: 'done', conversation_id: 'conv-test-123')
      expect(entry[:counts]).to include('summaries' => 1, 'turns' => 1, 'messages' => 1)
    end

    it 'forwards libraryScopeApp to the manager' do
      file = Rack::Test::UploadedFile.new(
        StringIO.new('# Hello'), 'text/markdown', original_filename: 'hello.md'
      )

      allow(Monadic::Library::FileImporter).to receive(:build_conversation).and_return(fake_conversation)
      allow(Monadic::Library::Store).to receive(:new).and_return(instance_double(Monadic::Library::Store))

      expect(Monadic::Library::Manager)
        .to receive(:import_conversation)
        .with(hash_including(scope_app: 'ChatOpenAI'))
        .and_return(import_result)

      post '/library/import', { 'libraryFile' => file, 'libraryScopeApp' => 'ChatOpenAI' }

      expect(last_response.status).to eq(202)
      data = JSON.parse(last_response.body)
      expect(data).to include('scope_app' => 'ChatOpenAI')
    end
  end

  describe 'rejection paths' do
    it 'returns JSON error when libraryFile is missing' do
      post '/library/import', {}

      expect(last_response.content_type).to start_with('application/json')
      data = JSON.parse(last_response.body)
      expect(data).to include('success' => false)
      expect(data['error']).to match(/No file selected/)
    end

    it 'returns JSON error when libraryFile is a hash without a filename' do
      # Some upload paths (rare; e.g. malformed multipart) deliver a
      # libraryFile param that is a Hash but has an empty/missing
      # filename field. Rack::Test::UploadedFile insists on a non-empty
      # filename, so we hit this branch by stubbing params directly.
      file = Rack::Test::UploadedFile.new(StringIO.new('x'), 'text/plain', original_filename: 'placeholder.txt')
      allow_any_instance_of(Sinatra::Application).to receive(:params).and_wrap_original do |orig|
        params = orig.call
        params['libraryFile'] = params['libraryFile'].merge('filename' => '') if params['libraryFile'].is_a?(Hash)
        params
      end

      post '/library/import', { 'libraryFile' => file }

      data = JSON.parse(last_response.body)
      expect(data).to include('success' => false)
      expect(data['error']).to match(/Missing filename/i)
    end

    it 'rejects oversized uploads before reaching FileImporter or the worker' do
      stub_const('LIBRARY_IMPORT_MAX_BYTES', 32)
      file = Rack::Test::UploadedFile.new(
        StringIO.new('x' * 4096), 'text/plain', original_filename: 'big.txt'
      )

      expect(Monadic::Library::FileImporter).not_to receive(:build_conversation)
      expect(Thread).not_to receive(:new)

      post '/library/import', { 'libraryFile' => file }

      data = JSON.parse(last_response.body)
      expect(data).to include('success' => false)
      expect(data['error']).to match(/import limit/)
    end

    it 'records FileImporter::ExtractionError on the tracker as stage="error"' do
      file = Rack::Test::UploadedFile.new(
        StringIO.new('x'), 'text/plain', original_filename: 'broken.md'
      )

      allow(Monadic::Library::FileImporter).to receive(:build_conversation)
        .and_raise(Monadic::Library::FileImporter::ExtractionError, 'extractor died')

      post '/library/import', { 'libraryFile' => file }

      expect(last_response.status).to eq(202)
      data = JSON.parse(last_response.body)
      entry = Monadic::Library::ImportTracker.get(data['import_id'])
      expect(entry).to include(stage: 'error')
      expect(entry[:error]).to match(/extractor died/i)
    end
  end

  describe 'GET /library/import/status/:id' do
    it 'returns 200 + the tracker payload for a known id' do
      id = Monadic::Library::ImportTracker.create
      Monadic::Library::ImportTracker.update(
        id, stage: 'extracting', filename: 'foo.md', scope_app: 'Global'
      )

      get "/library/import/status/#{id}"

      expect(last_response.status).to eq(200)
      data = JSON.parse(last_response.body)
      expect(data).to include(
        'success' => true,
        'import_id' => id,
        'stage' => 'extracting',
        'filename' => 'foo.md'
      )
    end

    it 'returns 404 for an unknown import_id' do
      get '/library/import/status/00000000-0000-0000-0000-000000000000'

      expect(last_response.status).to eq(404)
      data = JSON.parse(last_response.body)
      expect(data).to include('success' => false)
    end
  end
end
