# frozen_string_literal: true

require 'time'
require 'json'
require 'securerandom'
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

      # A value whose list fields accumulate entries (findings, vocabulary,
      # characters): read and saved as one Hash, as apps did before, while an
      # app that keeps its state by turn keeps each entry of a list as an
      # item, so deleting the turn that added an entry takes it back without
      # touching the rest. lists: { field => identity }, identity being the
      # entry's field that names it (nil: the entry as a whole). Apps that do
      # not keep their state by turn keep the whole Hash as one value.
      def monadic_load_record(key:, lists:, default: {}, session: nil)
        return monadic_load_state(key: key, default: default, session: session) unless Monadic::TurnState.enabled?(session)

        monadic_record_base!(session, key, lists)
        entry = Monadic::TurnState.value(session, key.to_s)
        stored = entry[:found] && entry[:data].is_a?(Hash) ? entry[:data] : {}
        data = Monadic::TurnState::Form.data(default || {}).merge(stored.except(*lists.keys))
        lists.each_key { |field| data[field] = Monadic::TurnState.items(session, field).map { |item| item[:data] } }
        { success: true, app: Monadic::TurnState.app_of(session), key: key, version: entry[:version],
          updated_at: entry[:updated_at], data: data }.to_json
      rescue Monadic::TurnState::Refused, Monadic::TurnState::Form::Invalid => e
        { success: false, error: e.message }.to_json
      end

      # Saves payload (the whole Hash) as monadic_load_record reads it: its
      # other fields as one value, changed only when they changed, and each
      # list given in full: entries added or changed are put, entries left
      # out removed, the others not touched.
      def monadic_save_record(key:, payload:, lists:, session: nil)
        return monadic_save_state(key: key, payload: payload, session: session) unless Monadic::TurnState.enabled?(session)

        monadic_record_base!(session, key, lists)
        given = Monadic::TurnState::Form.data(payload || {})
        fields = given.except(*lists.keys)
        now = Monadic::TurnState.value(session, key.to_s)
        stored = now[:found] && now[:data].is_a?(Hash) ? now[:data].except(*lists.keys) : nil
        Monadic::TurnState.set_value(session, key.to_s, fields) unless stored == fields
        lists.each { |field, identity| monadic_record_list(session, field, given[field], identity) if given.key?(field) }
        entry = Monadic::TurnState.value(session, key.to_s)
        { success: true, app: Monadic::TurnState.app_of(session), key: key, version: entry[:version],
          updated_at: entry[:updated_at] }.to_json
      rescue Monadic::TurnState::Refused, Monadic::TurnState::Form::Invalid => e
        { success: false, error: e.message }.to_json
      end

      private

      def monadic_record_list(session, field, entries, identity)
        given = Array(entries)
        name = ->(entry) { identity && entry.is_a?(Hash) ? entry[identity.to_s].to_s : JSON.generate(entry) }
        current = Monadic::TurnState.items(session, field)
        by_name = current.to_h { |item| [name.call(item[:data]), item] }
        given.each do |entry|
          found = by_name[name.call(entry)]
          next if found && found[:data] == entry

          Monadic::TurnState.put_item(session, field, entry, id: found && found[:id])
        end
        names = given.map { |entry| name.call(entry) }
        current.each { |item| Monadic::TurnState.remove_item(session, field, item[:id]) unless names.include?(name.call(item[:data])) }
      end

      # A chat that began from a file of an earlier version holds the lists
      # inside the value: they become items of the base once, with their ids
      # kept in the base ("_items", "_ids"), so the history and a file keep
      # the same ids. A list kept as { name => entry } (Novel Writer's
      # characters) becomes entries with that "name"; the block, when given,
      # makes an entry of each.
      def monadic_record_base!(session, key, lists)
        return unless session.is_a?(Hash)

        entries = session.dig(:monadic_state, Monadic::TurnState.app_of(session))
        return unless entries.is_a?(Hash) && !entries.key?("_ids")

        old = entries[key.to_s] || entries[key.to_sym]
        old_data = old.is_a?(Hash) ? (old[:data] || old["data"]) : nil
        return unless old_data.is_a?(Hash)

        items = {}
        ids = {}
        lists.each do |field, identity|
          found = old_data[field] || old_data[field.to_sym]
          list = found.is_a?(Hash) ? found.map { |label, entry| { "name" => label.to_s }.merge(entry.is_a?(Hash) ? entry : { "value" => entry }) } : Array(found)
          next if list.empty?

          items[field] = {}
          ids[field] = {}
          list.each do |raw|
            entry = Monadic::TurnState::Form.data(raw)
            id = "i_#{SecureRandom.alphanumeric(10).downcase}"
            items[field][id] = entry
            ids[field][identity && entry.is_a?(Hash) ? entry[identity.to_s].to_s : JSON.generate(entry)] = id
          end
        end
        return if items.empty?

        entries["_items"] = { data: items, version: 1, updated_at: nil }
        entries["_ids"] = { data: ids, version: 1, updated_at: nil }
        Monadic::TurnState.changed!(session[Monadic::Workspace::Chats::SESSION_KEY])
      end

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
    end
  end
end
