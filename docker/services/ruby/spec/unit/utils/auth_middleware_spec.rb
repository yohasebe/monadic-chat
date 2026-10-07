# frozen_string_literal: true

require 'rack'
require 'monadic/utils/auth_middleware'

RSpec.describe Monadic::Utils::AuthMiddleware do
  let(:downstream) do
    ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] }
  end
  let(:middleware) { described_class.new(downstream) }

  def env_for(path: '/', remote_ip: '203.0.113.5', headers: {}, cookies: {})
    e = Rack::MockRequest.env_for(path)
    e['REMOTE_ADDR'] = remote_ip
    headers.each { |k, v| e[k] = v }
    if cookies.any?
      e['HTTP_COOKIE'] = cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
    end
    e
  end

  # Save and restore CONFIG between examples so tests do not bleed state.
  # The middleware also falls back to ENV for these two settings, which
  # spec_helper fills from the developer's config/env when another spec loads
  # it first; clear them too so the result does not depend on that machine.
  around do |ex|
    config_was_defined = Object.const_defined?(:CONFIG, false)
    saved = config_was_defined ? CONFIG.dup : nil
    saved_env = ENV.to_h.slice('MONADIC_AUTH_TOKEN', 'DISTRIBUTED_MODE')
    saved_env.each_key { |k| ENV.delete(k) }
    Object.send(:remove_const, :CONFIG) if config_was_defined
    Object.const_set(:CONFIG, {})
    begin
      ex.run
    ensure
      Object.send(:remove_const, :CONFIG)
      Object.const_set(:CONFIG, saved) if saved
      %w[MONADIC_AUTH_TOKEN DISTRIBUTED_MODE].each { |k| ENV.delete(k) }
      saved_env.each { |k, v| ENV[k] = v }
    end
  end

  context 'standalone mode (DISTRIBUTED_MODE != "server")' do
    before { CONFIG['DISTRIBUTED_MODE'] = 'off' }

    it 'passes every request through without auth' do
      status, _, body = middleware.call(env_for)
      expect(status).to eq(200)
      expect(body.first).to eq('ok')
    end

    it 'does not require a configured token' do
      status, _, _ = middleware.call(env_for)
      expect(status).to eq(200)
    end
  end

  context 'server mode' do
    before do
      CONFIG['DISTRIBUTED_MODE'] = 'server'
      CONFIG['MONADIC_AUTH_TOKEN'] = 'secret-token-1234567890abcdef'
    end

    it 'allows loopback (127.0.0.1) requests without a token' do
      status, _, _ = middleware.call(env_for(remote_ip: '127.0.0.1'))
      expect(status).to eq(200)
    end

    it 'allows IPv6 loopback (::1) without a token' do
      status, _, _ = middleware.call(env_for(remote_ip: '::1'))
      expect(status).to eq(200)
    end

    it 'rejects non-loopback requests without a token (401)' do
      status, headers, body = middleware.call(env_for(remote_ip: '192.168.1.50'))
      expect(status).to eq(401)
      expect(headers['www-authenticate']).to match(/Bearer/)
      expect(body.first).to match(/Authentication required/)
    end

    it 'accepts the token via Authorization: Bearer header' do
      env = env_for(remote_ip: '192.168.1.50',
                    headers: { 'HTTP_AUTHORIZATION' => 'Bearer secret-token-1234567890abcdef' })
      status, _, _ = middleware.call(env)
      expect(status).to eq(200)
    end

    it 'accepts the token via the monadic_auth cookie' do
      env = env_for(remote_ip: '192.168.1.50',
                    cookies: { 'monadic_auth' => 'secret-token-1234567890abcdef' })
      status, _, _ = middleware.call(env)
      expect(status).to eq(200)
    end

    it 'accepts the token via the ?monadic_auth=... query parameter' do
      env = env_for(path: '/?monadic_auth=secret-token-1234567890abcdef',
                    remote_ip: '192.168.1.50')
      status, _, _ = middleware.call(env)
      # Query-param GET successes redirect to a clean URL (302), not 200.
      expect([200, 302]).to include(status)
    end

    it 'redirects (302) to a clean URL after a successful query-param GET (Referer leak fix)' do
      # The token in the URL would otherwise leak via browser history,
      # bookmarks, and Referer headers. We scrub it on first auth.
      env = env_for(path: '/?monadic_auth=secret-token-1234567890abcdef',
                    remote_ip: '192.168.1.50')
      status, headers, _ = middleware.call(env)
      expect(status).to eq(302)
      expect(headers['location']).to eq('http://example.org/')
      # Cookie is set on the redirect response so the follow-up
      # request authenticates without the URL parameter.
      expect(Array(headers['set-cookie']).join("\n")).to match(/monadic_auth=secret-token-1234567890abcdef/)
    end

    it 'preserves non-auth query parameters when redirecting' do
      env = env_for(path: '/path?foo=bar&monadic_auth=secret-token-1234567890abcdef&x=y',
                    remote_ip: '192.168.1.50')
      _, headers, _ = middleware.call(env)
      expect(headers['location']).to start_with('http://example.org/path?')
      expect(headers['location']).to include('foo=bar')
      expect(headers['location']).to include('x=y')
      expect(headers['location']).not_to include('monadic_auth')
    end

    it 'does not redirect when the token came from a Bearer header' do
      # Programmatic clients (curl, scripts) get the response directly.
      env = env_for(remote_ip: '192.168.1.50',
                    headers: { 'HTTP_AUTHORIZATION' => 'Bearer secret-token-1234567890abcdef' })
      status, _, _ = middleware.call(env)
      expect(status).to eq(200)
    end

    it 'does not redirect a WebSocket upgrade request even if the query param is present' do
      env = env_for(path: '/websocket?monadic_auth=secret-token-1234567890abcdef',
                    remote_ip: '192.168.1.50',
                    headers: { 'HTTP_UPGRADE' => 'websocket', 'HTTP_CONNECTION' => 'Upgrade' })
      status, _, _ = middleware.call(env)
      # The upgrade must reach the WS adapter; redirect would break it.
      expect(status).to eq(200)
    end

    it 'does not redirect a non-GET request even if the query param is present' do
      e = env_for(path: '/api/foo?monadic_auth=secret-token-1234567890abcdef',
                  remote_ip: '192.168.1.50')
      e['REQUEST_METHOD'] = 'POST'
      status, _, _ = middleware.call(e)
      expect(status).to eq(200)
    end

    it 'does not duplicate the cookie when the request already carries it' do
      env = env_for(remote_ip: '192.168.1.50',
                    cookies: { 'monadic_auth' => 'secret-token-1234567890abcdef' })
      _, headers, _ = middleware.call(env)
      # No Set-Cookie header (or, if downstream set one, ours is not appended).
      expect(Array(headers['set-cookie']).join("\n")).not_to match(/monadic_auth=secret-token-1234567890abcdef/)
    end

    it 'rejects a wrong-length token without leaking timing information' do
      env = env_for(remote_ip: '192.168.1.50',
                    headers: { 'HTTP_AUTHORIZATION' => 'Bearer too-short' })
      status, _, _ = middleware.call(env)
      expect(status).to eq(401)
    end

    it 'rejects an empty token (Bearer with no value)' do
      env = env_for(remote_ip: '192.168.1.50',
                    headers: { 'HTTP_AUTHORIZATION' => 'Bearer ' })
      status, _, _ = middleware.call(env)
      expect(status).to eq(401)
    end

    it 'rejects a same-length but different token' do
      env = env_for(remote_ip: '192.168.1.50',
                    headers: { 'HTTP_AUTHORIZATION' => 'Bearer secret-token-1234567890abcdee' })
      status, _, _ = middleware.call(env)
      expect(status).to eq(401)
    end

    it 'returns 503 when MONADIC_AUTH_TOKEN is missing in server mode' do
      CONFIG.delete('MONADIC_AUTH_TOKEN')
      status, _, body = middleware.call(env_for(remote_ip: '192.168.1.50'))
      expect(status).to eq(503)
      expect(body.first).to match(/MONADIC_AUTH_TOKEN/)
    end

    it 'still rejects loopback when token is missing only if non-local (loopback bypasses)' do
      CONFIG.delete('MONADIC_AUTH_TOKEN')
      # Loopback always passes — host process can always connect even
      # before a token has been provisioned (Settings UI uses this).
      status, _, _ = middleware.call(env_for(remote_ip: '127.0.0.1'))
      expect(status).to eq(200)
    end

    # The client writes forwarding headers, so they never make a remote
    # request local (this used to return 200 and skip the token).
    it 'rejects a remote request that claims a loopback X-Forwarded-For' do
      %w[127.0.0.1 ::1 ::ffff:127.0.0.1].each do |claimed|
        env = env_for(remote_ip: '203.0.113.5', headers: { 'HTTP_X_FORWARDED_FOR' => claimed })
        status, _, _ = middleware.call(env)
        expect(status).to eq(401), claimed
      end
    end

    it 'ignores X-Forwarded-For on a real loopback connection' do
      env = env_for(remote_ip: '127.0.0.1', headers: { 'HTTP_X_FORWARDED_FOR' => '203.0.113.99' })
      status, _, _ = middleware.call(env)
      expect(status).to eq(200)
    end

    it 'does not honour X-Forwarded-For when the first hop is NOT loopback' do
      env = env_for(remote_ip: '203.0.113.5',
                    headers: { 'HTTP_X_FORWARDED_FOR' => '203.0.113.99, 127.0.0.1' })
      status, _, _ = middleware.call(env)
      expect(status).to eq(401)
    end
  end

  # Rack 3 rejects uppercase header names and "\n"-joined cookies; the server
  # then dropped the rest of an authorized response and closed the
  # connection, so a Bearer client (the desktop app in Server Mode) never got
  # a usable reply. Rack's own Lint decides what is valid here.
  describe 'Rack 3 response format' do
    require 'rack/lint'

    let(:linted) { Rack::Lint.new(described_class.new(Rack::Lint.new(downstream))) }

    before do
      CONFIG['DISTRIBUTED_MODE'] = 'server'
      CONFIG['MONADIC_AUTH_TOKEN'] = 'secret-token-1234567890abcdef'
    end

    def run(env)
      status, headers, body = linted.call(env)
      body.each { |_| }
      body.close if body.respond_to?(:close)
      [status, headers]
    end

    it 'passes Rack::Lint when a Bearer token is accepted, a query token redirects, or the token is missing' do
      status, headers = run(env_for(remote_ip: '192.168.65.1',
                                    headers: { 'HTTP_AUTHORIZATION' => 'Bearer secret-token-1234567890abcdef' }))
      expect(status).to eq(200)
      expect(Array(headers['set-cookie']).join).to include('monadic_auth=')
      expect(run(env_for(path: '/?monadic_auth=secret-token-1234567890abcdef', remote_ip: '192.168.65.1')).first).to eq(302)
      expect(run(env_for(remote_ip: '192.168.65.1')).first).to eq(401)
    end

    it 'keeps a cookie the app already set, as a separate value' do
      app = ->(_env) { [200, { 'content-type' => 'text/plain', 'set-cookie' => 'other=1' }, ['ok']] }
      stack = Rack::Lint.new(described_class.new(Rack::Lint.new(app)))
      _, headers, body = stack.call(env_for(remote_ip: '192.168.65.1',
                                            headers: { 'HTTP_AUTHORIZATION' => 'Bearer secret-token-1234567890abcdef' }))
      body.each { |_| }
      body.close if body.respond_to?(:close)
      expect(Array(headers['set-cookie'])).to include('other=1')
      expect(Array(headers['set-cookie']).size).to eq(2)
    end
  end

end
