# frozen_string_literal: true

require_relative 'capability_request'

module Monadic
  module Utils
    # Stops an answer at POST /reply/cancel/<token>, while the tab's read loop
    # waits for the answer and cannot read its Cancel (WebSocketHelper::
    # Replies). The token was written only to the connection the answer runs
    # for. This only cancels the answer and stops what it runs; its end (and
    # what it writes to the chat) stays with its worker, and the WebSocket
    # Cancel that follows does the rest. Nothing is read from the body: a
    # request with one gets the same "not found" as an unknown or ended
    # token. 204 says the stop was asked, not that the answer has stopped.
    class ReplyCancelServer
      PREFIX = '/reply/cancel/'

      def initialize(app)
        @app = app
      end

      def call(env)
        path = env['PATH_INFO'].to_s
        return @app.call(env) unless path.start_with?(PREFIX)

        stop(env, path.delete_prefix(PREFIX))
      rescue StandardError
        CapabilityRequest.not_found
      end

      private

      def stop(env, token)
        return CapabilityRequest.not_found unless CapabilityRequest.same_origin_post?(env) && bodiless?(env)

        handle = WebSocketHelper::Replies.by_token(token)
        return CapabilityRequest.not_found unless handle

        WebSocketHelper::Replies.cancel(handle)
        CapabilityRequest.taken
      end

      def bodiless?(env)
        return false if env.key?('HTTP_TRANSFER_ENCODING')

        length = env['CONTENT_LENGTH']
        length.nil? || length.to_s == '0'
      end
    end
  end
end
