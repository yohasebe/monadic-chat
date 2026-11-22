# frozen_string_literal: true

require 'json'
require 'rack/utils'
require_relative '../utils/privacy/egress_guard'
require_relative '../utils/privacy/words'

module Monadic
  module Workspace
    # The chat a request from a page is for, fixed before anything reads
    # its body.
    #
    # The chat is the one of the tab the page names in the query string
    # (tab_id; the page's requests always carry it). A request that names no
    # tab is not a chat's (a program on this computer) and is let through. A
    # request to make files that names a tab this server does not know (its
    # state was dropped, or the server started again) is refused: its chat
    # cannot be told, and the page connects again before it tries once more.
    #
    # A request from the tab of a chat that hides words runs as that chat's
    # work: what it sends out is checked against the chat's words
    # (EgressGuard), in the route and in the body's each, call and close,
    # which run after the route returned. The cookie's session is every
    # tab's, and only the tab tells the chat.
    class ChatRequestScope
      def initialize(app, paths:, session_lookup:, state_lookup:)
        @app = app
        @paths = paths
        @session_lookup = session_lookup
        @state_lookup = state_lookup
      end

      def call(env)
        tab_id = Rack::Utils.parse_query(env['QUERY_STRING'].to_s)['tab_id']
        return @app.call(env) unless tab_id.is_a?(String) && !tab_id.empty?

        chat = tab_chat(tab_id)
        return refuse if chat.nil? && env['REQUEST_METHOD'] == 'POST' && @paths.include?(env['PATH_INFO'])
        return @app.call(env) unless chat && Monadic::Utils::Privacy::Words.marked?(chat)

        scope = Monadic::Utils::Privacy::EgressGuard::Scope.of(chat)
        status, headers, body = Work.within(scope) { @app.call(env) }
        [status, headers, Work.new(body, scope)]
      end

      # The response body of such a request, run in the chat's scope.
      class Work
        def self.within(scope)
          key = Monadic::Utils::Privacy::EgressGuard::CHAT_KEY
          before = Fiber[key]
          Fiber[key] = scope
          yield
        ensure
          Fiber[key] = before
        end

        def initialize(body, scope)
          @body = body
          @scope = scope
        end

        def each(&block)
          Work.within(@scope) { @body.each(&block) }
        end

        def call(stream)
          Work.within(@scope) { @body.call(stream) }
        end

        def close
          Work.within(@scope) { @body.close if @body.respond_to?(:close) }
        end

        # A body that is only streamed (call) or only listed (each) stays so.
        def respond_to?(name, include_all = false)
          return @body.respond_to?(name, include_all) if %i[each call].include?(name)

          super
        end
      end

      private

      # The tab's chat: its live session, or, while the tab is away, the chat
      # as its saved state keeps it (its id and the mark of its word table).
      # nil when the tab is not known.
      def tab_chat(tab_id)
        session = @session_lookup.call(tab_id)
        return session if session

        state = @state_lookup.call(tab_id)
        return nil unless state

        kept = state[:chat_state].is_a?(Hash) ? state[:chat_state] : {}
        kept.merge(Monadic::Workspace::Chats::SESSION_KEY => state[:chat_id])
      end

      MESSAGE = 'This tab is not connected to the server. Reload the page and try again.'

      def refuse
        body = { error: MESSAGE, reason: 'tab_unknown' }.to_json
        [409, { 'content-type' => 'application/json', 'connection' => 'close' }, [body]]
      end
    end
  end
end
