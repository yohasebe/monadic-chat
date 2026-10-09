# frozen_string_literal: true

require 'json'
require 'uri'

module Monadic
  module Utils
    # Keeps the servers on this computer from being driven by web pages.
    #
    # The ports are published to the loopback interface only, but any page
    # open in a browser on the same computer can still send requests to
    # localhost: forms and WebSockets cross origins freely, and a page can
    # rename its own site to 127.0.0.1 through DNS (rebinding), which also
    # makes its requests look same-origin. So:
    #
    # - Host must name this computer (localhost, 127.0.0.1, [::1]). A page
    #   that rebinds its own name still sends that name as Host. A request
    #   without Host is refused too.
    # - Changes (anything but GET, HEAD, OPTIONS) and WebSocket upgrades
    #   must carry no Origin, or an Origin naming this computer on the port
    #   the request came to. "null" (sandboxed frames, file: pages) is not
    #   one. Browsers send Origin on every such request from a page; a
    #   request without one comes from a program, or is a plain navigation.
    #
    # Origins are compared with a fixed list, never with the request's own
    # base URL: that is built from Host, which the sender controls.
    #
    # mode: :api is for a server no browser page has reason to call (MCP):
    # any Origin at all is refused, on every method.
    class LocalOriginGuard
      LOCAL_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze
      SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

      def initialize(app, mode: :web)
        raise ArgumentError, "unknown mode #{mode}" unless %i[web api].include?(mode)

        @app = app
        @mode = mode
      end

      def call(env)
        host, port = split_host(env['HTTP_HOST'])
        return refuse('host') unless LOCAL_HOSTS.include?(host)

        origin = env['HTTP_ORIGIN']
        if @mode == :api
          return refuse('origin') if origin
        elsif origin && checks_origin?(env) && !local_origin?(origin, port || env['SERVER_PORT'])
          return refuse('origin')
        end

        @app.call(env)
      end

      private

      def checks_origin?(env)
        !SAFE_METHODS.include?(env['REQUEST_METHOD']) || websocket_upgrade?(env)
      end

      def websocket_upgrade?(env)
        env['HTTP_UPGRADE'].to_s.casecmp?('websocket')
      end

      # "localhost:4567" -> ["localhost", "4567"]; "[::1]:4567" -> ["[::1]", "4567"]
      def split_host(value)
        return [nil, nil] if value.nil? || value.empty? # HTTP/1.1 requires Host

        match = value.downcase.match(/\A(\[[0-9a-f:.]+\]|[^:\[\]]+)(?::(\d+))?\z/)
        match ? [match[1], match[2]] : ['', nil]
      end

      def local_origin?(origin, port)
        uri = URI.parse(origin)
        return false unless uri.is_a?(URI::HTTP) && uri.scheme == 'http' && uri.userinfo.nil?
        # An Origin is scheme, host and port; anything more is not one a browser sent.
        return false unless uri.path.to_s.empty? && uri.query.nil? && uri.fragment.nil?

        host = uri.host.to_s.downcase
        host = "[#{host}]" if host.include?(':') && !host.start_with?('[')
        LOCAL_HOSTS.include?(host) && port && uri.port.to_s == port.to_s
      rescue URI::InvalidURIError
        false
      end

      def refuse(what)
        message = what == 'host' ? 'This server answers requests for this computer only.' : 'Requests from other sites are not accepted.'
        [403, { 'content-type' => 'application/json', 'connection' => 'close' }, [{ error: message, reason: "#{what}_not_local" }.to_json]]
      end
    end
  end
end
