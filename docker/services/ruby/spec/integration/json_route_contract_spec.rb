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
  end

  describe 'POST /document without X-Requested-With' do
    it 'always returns JSON content-type' do
      file = Rack::Test::UploadedFile.new(
        StringIO.new("dummy"), 'application/octet-stream', original_filename: 'sample.txt'
      )
      post '/document', { 'docFile' => file, 'docLabel' => '' }

      expect(last_response.content_type).to start_with('application/json')
    end

    it 'returns parseable JSON with success+content keys on the happy path' do
      file = Rack::Test::UploadedFile.new(
        StringIO.new("dummy"), 'text/plain', original_filename: 'sample.txt'
      )
      post '/document', { 'docFile' => file, 'docLabel' => 'Note' }

      data = JSON.parse(last_response.body)
      expect(data).to include('success' => true)
      expect(data['content']).to be_a(String)
      expect(data['content']).to include('Note')
    end

    it 'returns parseable JSON error when docFile is missing' do
      post '/document', { 'docLabel' => 'no file' }

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
