# frozen_string_literal: true

require 'rack'
require 'monadic/utils/auth_middleware'

RSpec.describe Monadic::Utils::AuthMiddleware do
  let(:downstream) do
    ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] }
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
  around do |ex|
    config_was_defined = Object.const_defined?(:CONFIG, false)
    saved = config_was_defined ? CONFIG.dup : nil
    Object.send(:remove_const, :CONFIG) if config_was_defined
    Object.const_set(:CONFIG, {})
    begin
      ex.run
    ensure
      Object.send(:remove_const, :CONFIG)
      Object.const_set(:CONFIG, saved) if saved
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
      expect(headers['WWW-Authenticate']).to match(/Bearer/)
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
      expect(headers['Location']).to eq('http://example.org/')
      # Cookie is set on the redirect response so the follow-up
      # request authenticates without the URL parameter.
      expect(headers['Set-Cookie']).to match(/monadic_auth=secret-token-1234567890abcdef/)
    end

    it 'preserves non-auth query parameters when redirecting' do
      env = env_for(path: '/path?foo=bar&monadic_auth=secret-token-1234567890abcdef&x=y',
                    remote_ip: '192.168.1.50')
      _, headers, _ = middleware.call(env)
      expect(headers['Location']).to start_with('http://example.org/path?')
      expect(headers['Location']).to include('foo=bar')
      expect(headers['Location']).to include('x=y')
      expect(headers['Location']).not_to include('monadic_auth')
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
      expect(headers['Set-Cookie'].to_s).not_to match(/monadic_auth=secret-token-1234567890abcdef/)
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

    it 'honours X-Forwarded-For only when the first hop is loopback' do
      env = env_for(remote_ip: '203.0.113.5',
                    headers: { 'HTTP_X_FORWARDED_FOR' => '127.0.0.1' })
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
end
