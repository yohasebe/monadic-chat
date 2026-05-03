# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra'

# Network-level contract for /library/import.
#
# Goals:
#   1. The route always returns JSON (size-limit, missing-filename,
#      success, and unexpected-error all share the same envelope shape).
#   2. The dispatch layer (FileImporter.build_conversation +
#      Manager.import_conversation) is invoked exactly once on success
#      with the right scope_app and uploaded file path.
#   3. Oversized uploads are rejected before the extractor is ever
#      called.
#
# Real PDF extraction is out of scope here; that needs Docker (covered
# by future smokes under spec/integration/docker_smoke/). This spec
# verifies the route shape and dispatch contract using stubs.

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
  end

  after do
    FileUtils.remove_entry(@tmp_data_dir) if @tmp_data_dir && Dir.exist?(@tmp_data_dir)
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
    it 'dispatches through FileImporter + Manager and returns success JSON' do
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

      expect(last_response.content_type).to start_with('application/json')
      data = JSON.parse(last_response.body)
      expect(data).to include(
        'success' => true,
        'filename' => 'hello.md',
        'conversation_id' => 'conv-test-123'
      )
      expect(data['counts']).to include('summaries' => 1, 'turns' => 1, 'messages' => 1)
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

      expect(last_response.status).to eq(200)
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

    it 'rejects oversized uploads before reaching FileImporter' do
      stub_const('LIBRARY_IMPORT_MAX_BYTES', 32)
      file = Rack::Test::UploadedFile.new(
        StringIO.new('x' * 4096), 'text/plain', original_filename: 'big.txt'
      )

      expect(Monadic::Library::FileImporter).not_to receive(:build_conversation)

      post '/library/import', { 'libraryFile' => file }

      data = JSON.parse(last_response.body)
      expect(data).to include('success' => false)
      expect(data['error']).to match(/import limit/)
    end

    it 'turns FileImporter errors into JSON error envelopes' do
      file = Rack::Test::UploadedFile.new(
        StringIO.new('x'), 'text/plain', original_filename: 'broken.md'
      )

      allow(Monadic::Library::FileImporter).to receive(:build_conversation)
        .and_raise(Monadic::Library::FileImporter::ExtractionError, 'extractor died')

      post '/library/import', { 'libraryFile' => file }

      expect(last_response.content_type).to start_with('application/json')
      data = JSON.parse(last_response.body)
      expect(data).to include('success' => false)
      expect(data['error']).to match(/extractor died/i)
    end
  end
end
