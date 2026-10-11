# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'rack'
require 'rack/mock_request'
require_relative '../../../lib/monadic/utils/unlimited_session_store'

# The session store of config.ru: sessions must carry from one request to the
# next, and the limits that keep the pool from growing must never take a
# session that is in use or empty a chat's content.
RSpec.describe Rack::Session::CappedPool do
  # A clock the examples move by hand.
  let(:clock) { [0.0] }

  def build(**options)
    seen = []
    inner = lambda do |env|
      s = env['rack.session']
      seen << s[:n]
      s[:n] = (s[:n] || 0) + 1
      s[:payload] = env['payload'] if env['payload']
      [200, {}, ['ok']]
    end
    pool = described_class.new(inner, key: 'monadic.session', **options)
    time = clock
    pool.define_singleton_method(:now) { time[0] }
    [pool, Rack::MockRequest.new(pool), seen]
  end

  def cookie_of(response)
    response.headers['set-cookie'].to_s.split(';').first
  end

  it 'carries a session from one request to the next' do
    _, req, seen = build
    cookie = cookie_of(req.get('/'))
    2.times { req.get('/', 'HTTP_COOKIE' => cookie) }
    expect(seen).to eq([nil, 1, 2])
  end

  it 'starts a new session for an id it did not issue' do
    _, req, seen = build
    req.get('/', 'HTTP_COOKIE' => 'monadic.session=made-up')
    expect(seen).to eq([nil])
  end

  it 'keeps a session in use when there are more than max_sessions' do
    pool, req, seen = build(max_sessions: 2)
    mine = cookie_of(req.get('/'))
    3.times { req.get('/') } # other clients, all just now
    req.get('/', 'HTTP_COOKIE' => mine)
    expect(seen.last).to eq(1)
    expect(pool.pool.size).to eq(4)
  end

  it 'removes the least recently used of the idle sessions over max_sessions' do
    pool, req, seen = build(max_sessions: 2)
    old = cookie_of(req.get('/'))
    clock[0] += described_class::MIN_IDLE + 1
    mine = cookie_of(req.get('/'))
    2.times { req.get('/') }
    expect(pool.pool.size).to eq(3) # the idle one went, the recent ones stay
    req.get('/', 'HTTP_COOKIE' => mine)
    expect(seen.last).to eq(1)
    req.get('/', 'HTTP_COOKIE' => old)
    expect(seen.last).to be_nil
  end

  it 'removes a session idle longer than expire_after' do
    pool, req, = build(expire_after: 100)
    req.get('/')
    clock[0] += 101
    req.get('/')
    expect(pool.pool.size).to eq(1)
  end

  it 'keeps the content of a session over max_session_bytes' do
    _, req, seen = build(max_session_bytes: 100)
    cookie = nil
    expect do
      cookie = cookie_of(req.get('/', 'payload' => 'x' * 1000))
    end.to output(/kept as it is/).to_stderr
    req.get('/', 'HTTP_COOKIE' => cookie)
    expect(seen.last).to eq(1)
  end

  # Booted from config.ru in a child process with its own HOME: the routes
  # must get this store's session, not one made by another middleware.
  it 'is the session the routes of config.ru get' do
    script = <<~'RUBY'
      require "rack"
      require "rack/mock_request"
      require "json"
      app, = Rack::Builder.parse_file("config.ru")
      seen = []
      Sinatra::Application.before do
        seen << [session.instance_variable_get(:@store).class.name, session[:n]]
        session[:n] = (session[:n] || 0) + 1
      end
      req = Rack::MockRequest.new(app)
      env = { "HTTP_HOST" => "localhost:4567" }
      cookie = req.get("http://localhost:4567/", env).headers["set-cookie"].to_s.split(";").first
      req.get("http://localhost:4567/", env.merge("HTTP_COOKIE" => cookie))
      puts JSON.generate(seen)
    RUBY
    root = File.expand_path('../../..', __dir__)
    seen = Dir.mktmpdir('capped-pool') do |home|
      stdout, stderr, status = Open3.capture3({ 'HOME' => home }, RbConfig.ruby, '-e', script, chdir: root)
      raise "probe failed: #{stderr.lines.last(15).join}" unless status.success?

      JSON.parse(stdout.lines.last)
    end
    expect(seen).to eq([['Rack::Session::CappedPool', nil], ['Rack::Session::CappedPool', 1]])
  end
end
