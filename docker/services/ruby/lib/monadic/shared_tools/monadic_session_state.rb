# frozen_string_literal: true

require 'time'

module Monadic
  module SharedTools
    # Minimal session-backed state utilities for monadic-style state handling.
    # Stores small JSON-serializable payloads per app/key, with versioning metadata.
    module MonadicSessionState
      DEFAULT_NAMESPACE = :monadic_state

      # Load state from session for a given app/key.
      # Returns JSON string with success, version, updated_at, and data.
      def monadic_load_state(app: nil, key:, default: nil, session: nil)
        raise ArgumentError, "key is required" if key.to_s.strip.empty?

        app_key = resolve_app_key(app, session)
        state_entry = dig_state(session, app_key, key)

        payload = state_entry ? state_entry[:data] : default
        version = state_entry ? state_entry[:version] : 0
        updated_at = state_entry ? state_entry[:updated_at] : nil

        {
          success: true,
          app: app_key,
          key: key,
          version: version,
          updated_at: updated_at,
          data: payload
        }.to_json
      rescue StandardError => e
        { success: false, error: e.message }.to_json
      end

      # Save state into session for a given app/key.
      # Wraps the payload with version/updated_at metadata and returns them.
      def monadic_save_state(app: nil, key:, payload:, session: nil, version: nil)
        raise ArgumentError, "key is required" if key.to_s.strip.empty?
        app_key = resolve_app_key(app, session)
        now = Time.now.utc.iso8601

        state_entry = {
          data: payload,
          version: (version || fetch_version(session, app_key, key) + 1),
          updated_at: now
        }

        ensure_namespace(session, app_key)
        session[DEFAULT_NAMESPACE][app_key][key] = state_entry

        {
          success: true,
          app: app_key,
          key: key,
          version: state_entry[:version],
          updated_at: now
        }.to_json
      rescue StandardError => e
        { success: false, error: e.message }.to_json
      end

      private

      def resolve_app_key(app, session)
        return app.to_s unless app.to_s.strip.empty?
        if session && session[:parameters] && session[:parameters]["app_name"]
          session[:parameters]["app_name"].to_s
        else
          "default"
        end
      end

      def ensure_namespace(session, app_key)
        raise ArgumentError, "session is required" unless session
        session[DEFAULT_NAMESPACE] ||= {}
        session[DEFAULT_NAMESPACE][app_key] ||= {}
      end

      def dig_state(session, app_key, key)
        return nil unless session && session[DEFAULT_NAMESPACE]
        session[DEFAULT_NAMESPACE].dig(app_key, key)
      end

      def fetch_version(session, app_key, key)
        entry = dig_state(session, app_key, key)
        entry ? entry[:version].to_i : 0
      end
    end
  end
end
