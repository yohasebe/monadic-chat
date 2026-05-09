# frozen_string_literal: true

require 'rack'
require 'uri'

module Monadic
  module Utils
    # Rack middleware that gates HTTP and WebSocket access when Monadic
    # Chat is running in distributed (server) mode. Standalone-mode and
    # loopback (host) requests skip authentication so the local Electron
    # webview, the host browser tab, and the MCP stdio bridge keep
    # working without setup.
    #
    # Token sources, in order of precedence:
    #   1. `Authorization: Bearer <token>` — programmatic clients
    #   2. `monadic_auth` cookie               — set after a successful query
    #                                            match so subsequent requests
    #                                            (CSS/JS/WebSocket) authenticate
    #                                            without echoing the token in
    #                                            the URL
    #   3. `?monadic_auth=<token>` query param — sharable link form
    #
    # On a successful match the middleware sets a session-scoped cookie so
    # the token need only ride in the URL once. Constant-time comparison
    # is used to avoid token-leakage timing attacks.
    class AuthMiddleware
      LOCAL_IPS = %w[127.0.0.1 ::1 ::ffff:127.0.0.1].freeze
      COOKIE_NAME = 'monadic_auth'
      AUTH_HEADER = 'HTTP_AUTHORIZATION'
      QUERY_PARAM = 'monadic_auth'

      # Status codes
      STATUS_UNAUTHORIZED = 401
      STATUS_MISCONFIGURED = 503

      def initialize(app)
        @app = app
      end

      def call(env)
        # Standalone mode: never gate. Loopback requests in any mode
        # bypass — the host process always has full access.
        return @app.call(env) unless server_mode?
        return @app.call(env) if loopback?(env)

        configured = expected_token
        return reject(STATUS_MISCONFIGURED, 'Server mode requires MONADIC_AUTH_TOKEN to be configured') if configured.nil? || configured.empty?

        request = Rack::Request.new(env)
        provided = extract_token(request)
        return reject(STATUS_UNAUTHORIZED, 'Authentication required') unless secure_match?(provided, configured)

        # If the token came in via the query parameter, redirect to a clean
        # URL so the token does not linger in the browser's history /
        # bookmarks / Referer headers on outbound clicks. The cookie is
        # set on the redirect response so the follow-up request still
        # authenticates without the URL parameter.
        if scrub_query_token?(env, request)
          redirect_headers = { 'Location' => clean_url_for(request), 'Content-Type' => 'text/html; charset=utf-8' }
          attach_auth_cookie(redirect_headers, configured)
          return [302, redirect_headers, ['<html><body>Redirecting...</body></html>']]
        end

        status, headers, body = @app.call(env)
        attach_auth_cookie(headers, configured) unless cookie_already_set?(request, configured)
        [status, headers, body]
      end

      private

      def server_mode?
        mode = (defined?(CONFIG) && CONFIG['DISTRIBUTED_MODE']) || ENV['DISTRIBUTED_MODE']
        mode.to_s == 'server'
      end

      def expected_token
        token = (defined?(CONFIG) && CONFIG['MONADIC_AUTH_TOKEN']) || ENV['MONADIC_AUTH_TOKEN']
        token.to_s.strip
      end

      def loopback?(env)
        ip = env['REMOTE_ADDR'].to_s
        # X-Forwarded-For is honoured for setups behind a reverse proxy
        # whose proxy host is itself loopback (e.g. localhost test runs).
        # In production we have no such proxy, so this widens the bypass
        # only when the packet truly originated locally.
        return true if LOCAL_IPS.include?(ip)
        forwarded = env['HTTP_X_FORWARDED_FOR'].to_s
        return false if forwarded.empty?
        first = forwarded.split(',').first.to_s.strip
        LOCAL_IPS.include?(first)
      end

      def extract_token(request)
        # Authorization: Bearer XXX
        auth = request.env[AUTH_HEADER].to_s
        if auth.start_with?('Bearer ')
          return auth.sub(/\ABearer\s+/, '').strip
        end
        # Cookie set on a previous successful auth
        cookie = request.cookies[COOKIE_NAME].to_s
        return cookie unless cookie.empty?
        # Query parameter — used for the initial sharable URL
        request.params[QUERY_PARAM].to_s
      end

      # Constant-time comparison; falls back to false on any length /
      # encoding mismatch so a 0-length probe cannot leak the token.
      def secure_match?(provided, expected)
        return false unless provided.is_a?(String) && expected.is_a?(String)
        return false if provided.empty? || expected.empty?
        return false unless provided.bytesize == expected.bytesize
        Rack::Utils.secure_compare(provided, expected)
      end

      def cookie_already_set?(request, configured)
        request.cookies[COOKIE_NAME] == configured
      end

      def attach_auth_cookie(headers, token)
        # Don't ship Secure flag yet — the app uses HTTP on the LAN.
        # Path=/ ensures the cookie applies to /js, /css, /pdf, etc.
        # SameSite=Lax keeps the cookie on top-level navigations while
        # preventing cross-site requests from carrying it.
        cookie_str = "#{COOKIE_NAME}=#{token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400"
        if headers['Set-Cookie']
          # Rack accepts multiple Set-Cookie headers separated by "\n".
          headers['Set-Cookie'] = "#{headers['Set-Cookie']}\n#{cookie_str}"
        else
          headers['Set-Cookie'] = cookie_str
        end
      end

      def reject(status, message)
        [status, {
          'Content-Type' => 'text/plain',
          'WWW-Authenticate' => 'Bearer realm="Monadic Chat"'
        }, [message]]
      end

      # Decide whether to 302 the request to a clean URL after a successful
      # query-param auth. We deliberately skip:
      #   - non-GET methods (would discard the body)
      #   - WebSocket upgrades (would break the upgrade handshake)
      #   - requests that did NOT carry the query param (nothing to scrub)
      def scrub_query_token?(env, request)
        return false unless env['REQUEST_METHOD'] == 'GET'
        return false if env['HTTP_UPGRADE'].to_s.downcase == 'websocket'
        !request.params[QUERY_PARAM].to_s.empty?
      end

      # Build the same URL with the monadic_auth parameter dropped. Other
      # query parameters are preserved so deep-links continue to work.
      def clean_url_for(request)
        params = request.params.reject { |k, _| k == QUERY_PARAM }
        suffix = params.empty? ? '' : ('?' + URI.encode_www_form(params))
        scheme = request.scheme
        host = request.host
        port = request.port
        port_part =
          if (scheme == 'http' && port == 80) || (scheme == 'https' && port == 443)
            ''
          else
            ":#{port}"
          end
        "#{scheme}://#{host}#{port_part}#{request.path}#{suffix}"
      end
    end
  end
end
