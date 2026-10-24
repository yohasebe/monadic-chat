# frozen_string_literal: true

require 'json'
require 'rack/utils'
require_relative 'policy'

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
    # tab is not a chat's (a program on this computer) and is let through.
    class PrivateRequestGuard
      def initialize(app, paths:, session_lookup:, state_lookup:)
        @app = app
        @paths = paths
        @session_lookup = session_lookup
        @state_lookup = state_lookup
      end

      def call(env)
        return @app.call(env) unless env['REQUEST_METHOD'] == 'POST' && @paths.include?(env['PATH_INFO'])

        tab_id = Rack::Utils.parse_query(env['QUERY_STRING'].to_s)['tab_id']
        return @app.call(env) unless tab_id.is_a?(String) && !tab_id.empty?
        return refuse('private_chat', 403) if private_tab?(tab_id)

        @app.call(env)
      end

      private

      def private_tab?(tab_id)
        session = @session_lookup.call(tab_id)
        return true if session && Policy.private?(session)

        state = @state_lookup.call(tab_id)
        Policy.known_private?(state && state[:chat_id]) ||
          Policy.known_private?(session && session[Monadic::Workspace::Chats::SESSION_KEY])
      rescue StandardError
        true
      end

      MESSAGES = {
        'private_chat' => 'This chat is Private: files are not made of it. Start a normal chat to use this.'
      }.freeze

      def refuse(reason, status)
        body = { error: MESSAGES[reason], reason: reason }.to_json
        [status, { 'content-type' => 'application/json', 'connection' => 'close' }, [body]]
      end
    end
  end
end
