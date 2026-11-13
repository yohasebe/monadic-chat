# frozen_string_literal: true

require 'time'
require 'json'
require_relative '../turn_state'

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
        return turn_state_load(app, key, default, session) if Monadic::TurnState.enabled?(session)

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
        return turn_state_save(app, key, payload, session) if Monadic::TurnState.enabled?(session)
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

      # The value of key changed by the block (given the value now, or
      # default; it returns the new one and only computes), with no other
      # change of this reply to the same state in between. The new value.
      def monadic_update_state(key:, default: nil, session: nil, &block)
        raise ArgumentError, "key is required" if key.to_s.strip.empty?
        return Monadic::TurnState.update(session, key.to_s, default, &block) if Monadic::TurnState.enabled?(session)

        current = JSON.parse(monadic_load_state(key: key, default: default, session: session))["data"]
        new_value = yield(current)
        monadic_save_state(key: key, payload: new_value, session: session)
        new_value
      end

      # The items of an app's collection (its characters, its glossary), each
      # kept by an id of its own, so deleting the turn that added, changed or
      # removed one takes that change back: for apps that keep their state
      # by turn (Monadic::TurnState).
      def monadic_put_item(collection:, data:, id: nil, session: nil)
        turn_state_only!(session)
        item_id = Monadic::TurnState.put_item(session, collection, data, id: id)
        { success: true, collection: collection.to_s, id: item_id }.to_json
      rescue Monadic::TurnState::Refused => e
        { success: false, error: e.message }.to_json
      end

      def monadic_remove_item(collection:, id:, session: nil)
        turn_state_only!(session)
        Monadic::TurnState.remove_item(session, collection, id)
        { success: true, collection: collection.to_s, id: id.to_s }.to_json
      rescue Monadic::TurnState::Refused => e
        { success: false, error: e.message }.to_json
      end

      def monadic_load_items(collection:, session: nil)
        turn_state_only!(session)
        items = Monadic::TurnState.items(session, collection.to_s).map { |i| { id: i[:id], data: i[:data] } }
        { success: true, collection: collection.to_s, items: items }.to_json
      rescue Monadic::TurnState::Refused => e
        { success: false, error: e.message }.to_json
      end

      private

      def turn_state_only!(session)
        return if Monadic::TurnState.enabled?(session)

        raise Monadic::TurnState::Refused, "items are kept only by apps that keep their state by turn"
      end

      # An app keeps state only under its own name.
      def turn_state_app!(app, session)
        own = Monadic::TurnState.app_of(session)
        return own if app.to_s.strip.empty? || app.to_s == own

        raise Monadic::TurnState::Refused, "a reply changes only its own app's state"
      end

      def turn_state_load(app, key, default, session)
        app_key = turn_state_app!(app, session)
        entry = Monadic::TurnState.value(session, key.to_s)
        { success: true, app: app_key, key: key, version: entry[:version], updated_at: entry[:updated_at],
          data: entry[:found] ? entry[:data] : default }.to_json
      rescue Monadic::TurnState::Refused => e
        { success: false, error: e.message }.to_json
      end

      def turn_state_save(app, key, payload, session)
        app_key = turn_state_app!(app, session)
        Monadic::TurnState.set_value(session, key.to_s, payload)
        entry = Monadic::TurnState.value(session, key.to_s)
        { success: true, app: app_key, key: key, version: entry[:version], updated_at: entry[:updated_at] }.to_json
      rescue Monadic::TurnState::Refused => e
        { success: false, error: e.message }.to_json
      end

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

      # Fetch last images from monadic state or legacy session keys.
      # Tolerant to symbol/string keys. Uses legacy_prefix for provider-specific fallbacks.
      # @param session [Hash] Session hash
      # @param app_key [String] App name key for monadic_state lookup
      # @param legacy_prefix [String] Provider prefix for legacy keys (e.g., "openai", "grok", "gemini3")
      # @return [Array<String>, nil] Array of image filenames or nil
      def fetch_last_images_from_session(session, app_key, legacy_prefix: nil)
        # monadic_state lookup (symbol and string keys)
        monadic_state = session[:monadic_state] || session["monadic_state"] || {}
        app_state = monadic_state[app_key] || monadic_state[app_key.to_s] || {}
        last_images_entry = app_state[:last_images] || app_state["last_images"]
        data = last_images_entry && (last_images_entry[:data] || last_images_entry["data"])
        return data if data.is_a?(Array) && !data.empty?

        return nil unless legacy_prefix

        # legacy {prefix}_last_image_generation
        gen_key_sym = :"#{legacy_prefix}_last_image_generation"
        gen_key_str = "#{legacy_prefix}_last_image_generation"
        legacy = session[gen_key_sym] || session[gen_key_str]
        if legacy
          imgs = legacy[:images] || legacy["images"]
          return imgs if imgs.is_a?(Array) && !imgs.empty?
        end

        # single last image fallback
        img_key_sym = :"#{legacy_prefix}_last_image"
        img_key_str = "#{legacy_prefix}_last_image"
        last_image = session[img_key_sym] || session[img_key_str]
        return [last_image] if last_image

        nil
      end
    end
  end
end
