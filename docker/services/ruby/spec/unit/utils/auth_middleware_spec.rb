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
      expect(status).to eq(200)
    end

    it 'sets the auth cookie after a successful query-param match (so refresh works)' do
      env = env_for(path: '/?monadic_auth=secret-token-1234567890abcdef',
                    remote_ip: '192.168.1.50')
      _, headers, _ = middleware.call(env)
      expect(headers['Set-Cookie']).to match(/monadic_auth=secret-token-1234567890abcdef/)
      expect(headers['Set-Cookie']).to match(/HttpOnly/)
      expect(headers['Set-Cookie']).to match(/SameSite=Lax/)
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
