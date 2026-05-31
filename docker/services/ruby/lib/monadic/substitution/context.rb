# frozen_string_literal: true

module Monadic
  module Substitution
    # Per-message context object passed to every Provider lifecycle hook.
    #
    # Wraps the active session Hash and the current app instance to give
    # providers a stable, testable read surface without exposing the raw
    # session structure directly. Providers should never mutate the session
    # outside their own #state(context) slot (see Provider#state).
    class Context
      attr_reader :session, :app

      # @param session [Hash] active session hash (per WebSocket connection)
      # @param app [MonadicApp, nil] current app instance, or nil before an app is selected
      def initialize(session:, app: nil)
        @session = session
        @app = app
      end

      # Convenience: identifying name of the active app, or nil.
      # @return [String, nil]
      def app_name
        @app && @app.class.name.to_s.split("::").last
      end

      # All recorded messages in this session (assistant + user + system).
      # @return [Array<Hash>]
      def messages
        Array(@session[:messages])
      end

      # Number of user-authored turns in this session.
      # @return [Integer]
      def turn_count
        messages.count { |m| m["role"] == "user" }
      end
    end
  end
end
