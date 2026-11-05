# frozen_string_literal: true

require 'digest'
require_relative 'board'
require_relative 'view_tokens'
require_relative '../workspace/chats'

module Monadic
  module Workbench
    # Serves a candidate's image to the page at /workbench/asset/<token>
    # (ViewTokens), ahead of the application so that the request is not
    # written to the access log: the token in the address is the permission.
    #
    # Only a GET or HEAD sent by a page of this server (Sec-Fetch-Site:
    # same-origin) is served, and only while the token's tab still has the
    # connection it was given to, its chat is at the same epoch and not
    # Private, and the item's candidate has the sha256 named.
    # Anything else gets the same "not found".
    class AssetServer
      PREFIX = '/workbench/asset/'
      HEADERS = {
        'cache-control' => 'no-store',
        'x-content-type-options' => 'nosniff',
        'cross-origin-resource-policy' => 'same-origin',
        'referrer-policy' => 'no-referrer',
        'content-security-policy' => "default-src 'none'"
      }.freeze

      # live: the generation of the connection a tab has now (or nil).
      # private_chat: whether a chat is Private.
      def initialize(app, live:, private_chat:, store: nil)
        @app = app
        @live = live
        @private_chat = private_chat
        @store = store
      end

      def call(env)
        path = env['PATH_INFO'].to_s
        return @app.call(env) unless path.start_with?(PREFIX)

        serve(env, path.delete_prefix(PREFIX))
      rescue StandardError
        not_found
      end

      private

      def serve(env, token)
        return not_found unless %w[GET HEAD].include?(env['REQUEST_METHOD'])
        return not_found unless env['HTTP_SEC_FETCH_SITE'] == 'same-origin'

        view = ViewTokens.view(token) or return not_found
        return not_found unless @live.call(view.tab) == view.generation
        return not_found unless view.epoch == Monadic::Workspace::Chats.epoch(view.chat_id)
        return not_found if @private_chat.call(view.chat_id)

        board = Board.existing(view.chat_id, **(@store ? { store: @store } : {})) or return not_found
        return not_found if board.private?

        candidate = board.item(view.item_id)&.dig('candidate')
        return not_found unless candidate && candidate['sha256'] == view.sha256

        bytes = board.read(candidate['path'])
        return not_found unless Digest::SHA256.hexdigest(bytes) == view.sha256

        headers = HEADERS.merge('content-type' => candidate['content_type'], 'content-length' => bytes.bytesize.to_s)
        [200, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [bytes]]
      end

      def not_found
        [404, HEADERS.merge('content-type' => 'text/plain', 'content-length' => '9'), ['Not found']]
      end
    end
  end
end
