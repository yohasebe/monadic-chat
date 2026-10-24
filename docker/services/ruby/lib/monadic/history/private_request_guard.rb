# frozen_string_literal: true

require 'json'
require 'rack/utils'
require_relative 'policy'
require_relative '../utils/privacy/egress_guard'

module Monadic
  module History
    # The requests that make files of what a chat holds (attachments,
    # documents, audio files, PDFs to import, web pages) are refused for a
    # Private chat before anything reads their body: Rack writes the file
    # parts of a body to disk while it parses them, so a check in the route
    # would come after the file was made.
    #
    # The chat is the one of the tab the page names in the query string
    # (tab_id; the page's requests always carry it). A request that names no
    # tab is not a chat's (a program on this computer) and is let through. A
    # request to make files that names a tab this server does not know (its
    # state was dropped, or the server started again) is refused: its chat
    # cannot be told, and the page connects again before it tries once more.
    #
    # Any other request from the tab of a Private chat (an import, say) is
    # run as that chat's work, so it is not logged either: the cookie's
    # session is every tab's, and only the tab tells the chat.
    class PrivateRequestGuard
      def initialize(app, paths:, session_lookup:, state_lookup:)
        @app = app
        @paths = paths
        @session_lookup = session_lookup
        @state_lookup = state_lookup
      end

      def call(env)
        tab_id = Rack::Utils.parse_query(env['QUERY_STRING'].to_s)['tab_id']
        return @app.call(env) unless tab_id.is_a?(String) && !tab_id.empty?

        kind, chat_id = tab_kind(tab_id)
        if env['REQUEST_METHOD'] == 'POST' && @paths.include?(env['PATH_INFO'])
          return refuse('private_chat', 403) if kind == :private
          return refuse('tab_unknown', 409) if kind == :unknown
        end
        return @app.call(env) unless kind == :private

        as_private_work(chat_id) { @app.call(env) }
      end

      private

      # [:private, :normal or :unknown, the chat's id]. A doubt errs to
      # Private.
      def tab_kind(tab_id)
        session = @session_lookup.call(tab_id)
        state = @state_lookup.call(tab_id)
        return [:unknown, nil] if session.nil? && state.nil?

        chat_id = (session && session[Monadic::Workspace::Chats::SESSION_KEY]) || (state && state[:chat_id])
        private = (session && Policy.private?(session)) ||
                  (state && state[:chat_state].is_a?(Hash) && Policy.private?(state[:chat_state])) ||
                  Policy.known_private?(state && state[:chat_id]) || Policy.known_private?(chat_id)
        [private ? :private : :normal, chat_id]
      rescue StandardError
        [:private, nil]
      end

      # What runs for the request is the Private chat's work (see
      # Policy.current_work_private?), as for its connection.
      def as_private_work(chat_id)
        key = Monadic::Utils::Privacy::EgressGuard::CHAT_KEY
        before = Fiber[key]
        marked = { Policy::SESSION_KEY => Policy::PRIVATE, Monadic::Workspace::Chats::SESSION_KEY => chat_id }
        Fiber[key] = Monadic::Utils::Privacy::EgressGuard::Scope.new(marked, chat_id)
        yield
      ensure
        Fiber[key] = before
      end

      MESSAGES = {
        'private_chat' => 'This chat is Private: files are not made of it. Start a normal chat to use this.',
        'tab_unknown' => 'This tab is not connected to the server. Reload the page and try again.'
      }.freeze

      def refuse(reason, status)
        body = { error: MESSAGES[reason], reason: reason }.to_json
        [status, { 'content-type' => 'application/json', 'connection' => 'close' }, [body]]
      end
    end
  end
end
