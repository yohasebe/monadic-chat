# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'tmpdir'
require 'timeout'
require 'monadic/routes/help_routes'
require 'monadic/utils/auth_middleware'

RSpec.describe 'Help database routes' do
  include Rack::Test::Methods

  let(:web_app) do
    Class.new(Sinatra::Base) do
      set :environment, :test
      set :views, File.expand_path('../../../views', __dir__)
      set :protection, except: [:frame_options]
      register Monadic::Routes::HelpRoutes
    end
  end
  let(:app) { Monadic::Utils::AuthMiddleware.new(web_app) }
  let(:installation) { instance_double(Monadic::Help::Installation) }

  before do
    header 'Host', 'localhost'
    header 'Origin', 'http://localhost'
    stub_const('CONFIG', CONFIG.merge('DISTRIBUTED_MODE' => 'standalone'))
    allow(Monadic::Help).to receive(:installation).and_return(installation)
  end

  %w[not_installed installing installed update_available legacy failed unavailable].each do |state|
    it "returns the #{state} snapshot without starting installation" do
      snapshot = { state: state, searchable: %w[installed update_available].include?(state), reason: 'detail' }
      expect(installation).to receive(:status).and_return(snapshot)
      expect(installation).not_to receive(:start)
      get '/help/database/status'
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to start_with('application/json')
      expect(last_response.headers['cache-control']).to eq('no-store')
      expect(JSON.parse(last_response.body)).to eq(JSON.parse(snapshot.to_json))
    end
  end

  %w[validating preparing loading verifying completed].each do |stage|
    it "preserves #{stage} progress and counts" do
      progress = { stage: stage, processed: 2, total: 5 }
      allow(installation).to receive(:status).and_return(state: 'installing', searchable: false, progress: progress)
      get '/help/database/status'
      expect(JSON.parse(last_response.body)['progress']).to eq(JSON.parse(progress.to_json))
    end
  end

  it 'serves data management without an API key, model call or installation' do
    stub_const('CONFIG', { 'DISTRIBUTED_MODE' => 'standalone' })
    expect(Monadic::Help).not_to receive(:installation)
    get '/help/database'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('data-standalone="true"', 'help-database-install', '/js/monadic/help-database.js')
  end

  it 'returns accepted immediately without waiting for the worker' do
    expect(installation).to receive(:start).with(no_args).and_return(accepted: true, state: 'installing', install_id: 'job')
    expect(installation).not_to receive(:wait)
    post '/help/database/install'
    expect(last_response.status).to eq(202)
    expect(JSON.parse(last_response.body)).to include('accepted' => true, 'install_id' => 'job')
  end

  it 'returns retryable busy on a second POST while the real worker is still running' do
    Dir.mktmpdir('help-routes-spec') do |directory|
      entered, release = Queue.new, Queue.new
      service = Monadic::Help::Installation.new(store: double('unused store'), coordination_dir: directory)
      allow(Monadic::Help).to receive(:installation).and_return(service)
      allow(Monadic::Help::ValidatedDump).to receive(:new) do
        entered << true
        release.pop
        Thread.exit
      end
      post '/help/database/install'
      expect(last_response.status).to eq(202)
      Timeout.timeout(5) { entered.pop }
      post '/help/database/install'
      expect(last_response.status).to eq(409)
      expect(JSON.parse(last_response.body)).to include('accepted' => false, 'state' => 'busy', 'retryable' => true)
    ensure
      release << true
      service.instance_variable_get(:@worker)&.join(3)
    end
  end

  %w[path dump_path url collection collections].each do |key|
    it "rejects a client-supplied #{key} in JSON, form and query parameters" do
      expect(installation).not_to receive(:start)
      post '/help/database/install', { key => 'arbitrary' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      post '/help/database/install', { key => 'arbitrary' }
      expect(last_response.status).to eq(400)
      post "/help/database/install?#{key}=arbitrary"
      expect(last_response.status).to eq(400)
    end
  end

  ['{', '[]', 'null', 'true', '"path"'].each do |body|
    it "rejects invalid or non-object JSON #{body}" do
      expect(installation).not_to receive(:start)
      post '/help/database/install', body, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
    end
  end

  it 'does not install through GET' do
    expect(installation).not_to receive(:start)
    get '/help/database/install'
    expect(last_response.status).to eq(404)
  end

  it 'uses the existing server-mode authentication for reads and writes' do
    stub_const('CONFIG', { 'DISTRIBUTED_MODE' => 'server', 'MONADIC_AUTH_TOKEN' => 'test-token' })
    expect(installation).not_to receive(:start)
    get '/help/database/status', {}, 'REMOTE_ADDR' => '192.0.2.1'
    expect(last_response.status).to eq(401)
    post '/help/database/install', {}, 'REMOTE_ADDR' => '192.0.2.1'
    expect(last_response.status).to eq(401)
    header 'Authorization', 'Bearer test-token'
    allow(installation).to receive(:status).and_return(state: 'not_installed')
    get '/help/database/status', {}, 'REMOTE_ADDR' => '192.0.2.1'
    expect(last_response.status).to eq(200)
  end

  it 'rejects cross-origin installation requests' do
    header 'Origin', 'http://other.example'
    expect(installation).not_to receive(:start)
    post '/help/database/install', '{}', 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(403)
  end

  it 'returns a structured service failure without leaking an exception' do
    allow(installation).to receive(:status).and_raise('private details')
    allow(installation).to receive(:start).and_raise('private details')
    get '/help/database/status'
    expect(last_response.status).to eq(503)
    expect(JSON.parse(last_response.body)).to include('state' => 'unavailable', 'searchable' => false)
    post '/help/database/install'
    expect(last_response.status).to eq(503)
    expect(JSON.parse(last_response.body)).to include('accepted' => false, 'retryable' => true)
    expect(last_response.body).not_to include('private details')
  end
end
