# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra'

# Network-level smoke for the JsonRoute pattern. The H3c refactor
# removed the `request.xhr?` branching from /document, /fetch_webpage,
# and /load; this spec exercises each route through Rack::Test so a
# regression that re-introduces the form-fallback branch is caught at
# the response layer (where the original "No number after minus sign"
# bug actually surfaced).
#
# We intentionally do NOT send X-Requested-With. The whole point of the
# JsonRoute pattern is that the route returns JSON regardless of the
# header. If a future change adds an `if request.xhr?` back, this spec
# falls.

RSpec.describe 'JSON-route contract (no X-Requested-With)', :integration do
  include Rack::Test::Methods

  before(:all) do
    require_relative '../../lib/monadic/utils/environment'
    require_relative '../../lib/monadic/version'
    require_relative '../../lib/monadic/workspace'

    # Sinatra classic helper for the error JSON shape used by routes.
    Sinatra::Application.helpers do
      def error_json(message)
        { 'success' => false, 'error' => message }.to_json
      end
    end

    # Stub MonadicApp.doc2markdown / .fetch_webpage so the routes can
    # run without Docker. We test response shape, not extraction.
    stub_const('MonadicApp', Class.new) unless defined?(MonadicApp)
    MonadicApp.singleton_class.class_eval do
      define_method(:doc2markdown) { |_| "stub-markdown" }
      define_method(:fetch_webpage) { |_| "stub-webpage" }
    end

    require_relative '../../lib/monadic/routes/upload_routes'
  end

  def app
    Sinatra::Application
  end

  before do
    # Sinatra's host_authorization middleware (enabled by default in
    # development/test) returns 403 for the rack-test default host.
    # Posting from localhost matches the allow-list and lets the route
    # handler run.
    header 'Host', '127.0.0.1'

    # Pin Environment.data_path to a per-test tempdir so the route's
    # File.open succeeds whether IN_CONTAINER is set or not. Without
    # this, IN_CONTAINER=true makes data_path resolve to /monadic/data
    # which only exists inside the production container.
    @tmp_data_dir = File.realpath(Dir.mktmpdir('monadic-data-test'))
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@tmp_data_dir)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(File.join(@tmp_data_dir, '.state'))
  end

  # The chat UploadContext fixed for the upload (config.ru mounts it).
  let(:chat_env) { { Monadic::Workspace::UploadContext::CHAT_KEY => Monadic::Workspace::Ids.generate(:chat) } }

  after do
    FileUtils.remove_entry(@tmp_data_dir) if @tmp_data_dir && Dir.exist?(@tmp_data_dir)
  end

  describe 'POST /document without X-Requested-With' do
    it 'always returns JSON content-type' do
      file = Rack::Test::UploadedFile.new(
        StringIO.new("dummy"), 'application/octet-stream', original_filename: 'sample.txt'
      )
      post '/document', { 'docFile' => file, 'docLabel' => '' }, chat_env

      expect(last_response.content_type).to start_with('application/json')
    end

    it 'returns parseable JSON with success+content keys on the happy path' do
      file = Rack::Test::UploadedFile.new(
        StringIO.new("dummy"), 'text/plain', original_filename: 'sample.txt'
      )
      post '/document', { 'docFile' => file, 'docLabel' => 'Note' }, chat_env

      data = JSON.parse(last_response.body)
      expect(data).to include('success' => true)
      expect(data['content']).to be_a(String)
      expect(data['content']).to include('Note')
      # Kept as an attachment of the chat, nothing at the top of the shared folder
      expect(Dir.glob(File.join(@tmp_data_dir, 'conversations', '*', 'inputs', '*__sample.txt')).size).to eq(1)
      expect(Dir.children(@tmp_data_dir) - ['.state']).to eq(['conversations'])
    end

    it 'keeps nothing and says so when the page has no chat' do
      file = Rack::Test::UploadedFile.new(StringIO.new("dummy"), 'text/plain', original_filename: 'sample.txt')
      post '/document', { 'docFile' => file, 'docLabel' => '' }

      data = JSON.parse(last_response.body)
      expect(data).to include('success' => false)
      expect(Dir.children(@tmp_data_dir) - ['.state']).to be_empty
    end

    it 'returns parseable JSON error when docFile is missing' do
      post '/document', { 'docLabel' => 'no file' }, chat_env

      expect(last_response.content_type).to start_with('application/json')
      data = JSON.parse(last_response.body)
      expect(data).to include('success' => false)
      expect(data['error']).to match(/No file selected/)
    end
  end

  describe 'POST /fetch_webpage without X-Requested-With' do
    it 'always returns JSON content-type' do
      post '/fetch_webpage', { 'pageURL' => 'https://example.com/' }
      expect(last_response.content_type).to start_with('application/json')
    end

    it 'returns parseable JSON success on the happy path' do
      post '/fetch_webpage', { 'pageURL' => 'https://example.com/' }
      data = JSON.parse(last_response.body)
      expect(data).to include('success' => true)
      expect(data['content']).to be_a(String)
    end

    it 'returns parseable JSON error when pageURL is missing' do
      post '/fetch_webpage', {}
      expect(last_response.content_type).to start_with('application/json')
      data = JSON.parse(last_response.body)
      expect(data).to include('success' => false)
      expect(data['error']).to match(/No URL/)
    end
  end
end
