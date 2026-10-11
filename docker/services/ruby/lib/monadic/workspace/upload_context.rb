# frozen_string_literal: true

require 'json'
require 'rack/utils'
require_relative 'ids'

module Monadic
  module Workspace
    # Fixes which chat an upload belongs to before its body is read. The
    # route itself runs only after the whole body has been parsed, and the
    # tab may have been Reset into a new chat by then; the file belongs to
    # the chat that was open when the user sent it. Where the request comes
    # from is LocalOriginGuard's question, answered earlier in config.ru.
    #
    # The tab id comes in the query string. Its saved state (the same record
    # a reconnecting tab resumes from) names the chat and the app.
    class UploadContext
      CHAT_KEY = 'monadic.upload.chat_id'
      APP_KEY = 'monadic.upload.app_name'

      def initialize(app, paths:, state_lookup:)
        @app = app
        @paths = paths
        @state_lookup = state_lookup
      end

      def call(env)
        if env['REQUEST_METHOD'] == 'POST' && @paths.include?(env['PATH_INFO'])
          tab_id = Rack::Utils.parse_query(env['QUERY_STRING'].to_s)['tab_id']
          state = tab_id.is_a?(String) && !tab_id.empty? ? @state_lookup.call(tab_id) : nil
          # Without a chat there is nowhere to put the file: refuse before
          # reading the body rather than after.
          return no_chat unless state && Ids.valid?(:chat, state[:chat_id])

          env[CHAT_KEY] = state[:chat_id]
          env[APP_KEY] = (state[:parameters] || {})['app_name']
        end
        @app.call(env)
      end

      private

      def no_chat
        body = { error: 'This page is no longer connected. Reload the page and attach the file again.',
                 reason: 'no_chat' }.to_json
        [409, { 'content-type' => 'application/json', 'connection' => 'close' }, [body]]
      end
    end
  end
end
