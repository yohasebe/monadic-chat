# frozen_string_literal: true

require 'json'

module Monadic
  module TurnState
    # The form of an app's state as a chat keeps it, checked the same way
    # wherever it comes from (a tool saving it, the history, a file read in).
    #
    # - A reply's changes (its message's STATE_CHANGES_KEY): a list of
    #   { "app", "kind" => "value"|"item", "key" (value) or "collection" and
    #   "id" (item), "op" => "set"|"remove", "data" (set only) }. app, kind,
    #   key, collection, id and op are the form, never what anyone said:
    #   key and collection are names the app fixes, id one the server makes.
    # - The base: the state a chat began with (a file of an earlier version
    #   read in), { app => { key => { "data", "version", "updated_at" } } },
    #   kept apart from the messages and never made from them.
    #
    # Something that does not fit is refused whole (a reply's changes, or a
    # base entry), never cut: what was accepted reads the same after the
    # history or a file.
    module Form
      STATE_CHANGES_KEY = 'state_changes'
      SCHEMA = 1
      APP = /\A[A-Za-z][A-Za-z0-9_]{0,127}\z/
      NAME = /\A[a-z][a-z0-9_]{0,63}\z/
      ID = /\A[a-z0-9_]{1,32}\z/
      # Base entries the server keeps for an app beside its own keys.
      BASE_KEY = /\A(?:[A-Za-z][A-Za-z0-9_]{0,63}|_items|_ids)\z/
      RESERVED_APPS = %w[privacy conversation_context context_schema].freeze
      KINDS = %w[value item].freeze
      OPS = %w[set remove].freeze
      # What one reply may change (its changes as JSON, UTF-8 bytes) and how
      # many; what is read back may be twice as large, as masking makes
      # words longer.
      SAVE_BYTES = 64 * 1024
      READ_BYTES = 2 * SAVE_BYTES
      ENTRIES = 200
      DEPTH = 8
      KEY_LENGTH = 200
      # A chat's changes and base together.
      CHAT_BYTES = 2 * 1024 * 1024

      class Invalid < StandardError; end

      module_function

      # A reply's changes in their checked form (frozen copies), or nil when
      # there are none or they do not fit (limit: the bytes allowed).
      def clean_changes(list, limit: READ_BYTES)
        return nil unless list.is_a?(Array) && !list.empty? && list.size <= ENTRIES

        kept = list.map { |entry| change(entry) }
        return nil if kept.any?(&:nil?) || JSON.generate(kept).bytesize > limit

        deep_freeze(kept)
      rescue Invalid, JSON::GeneratorError
        nil
      end

      # One change in its checked form, or nil.
      def change(entry)
        return nil unless entry.is_a?(Hash)

        e = entry.transform_keys(&:to_s)
        app = e['app']
        kind = e['kind']
        op = e['op']
        return nil unless app.is_a?(String) && APP.match?(app) && !RESERVED_APPS.include?(app)
        return nil unless KINDS.include?(kind) && OPS.include?(op)

        out = { 'app' => app, 'kind' => kind }
        if kind == 'value'
          return nil unless e['key'].is_a?(String) && NAME.match?(e['key']) && !e.key?('collection') && !e.key?('id')

          out['key'] = e['key']
        else
          return nil unless e['collection'].is_a?(String) && NAME.match?(e['collection']) && e['id'].is_a?(String) &&
                            ID.match?(e['id']) && !e.key?('key')

          out['collection'] = e['collection']
          out['id'] = e['id']
        end
        out['op'] = op
        if op == 'set'
          return nil unless e.key?('data')

          out['data'] = data(e['data'])
        elsif e.key?('data')
          return nil
        end
        out
      end

      # A value as state keeps it: JSON's types only, with string keys, no
      # deeper than DEPTH. A copy; Invalid when it does not fit.
      def data(value, depth = 0)
        raise Invalid, 'too deep' if depth > DEPTH

        case value
        when Hash
          value.each_with_object({}) do |(k, v), out|
            key = k.is_a?(Symbol) ? k.to_s : k
            raise Invalid, 'a key is not text' unless key.is_a?(String) && key.length <= KEY_LENGTH

            out[key] = data(v, depth + 1)
          end
        when Array then value.map { |v| data(v, depth + 1) }
        when String then value.dup
        when Integer, true, false, nil then value
        when Float
          raise Invalid, 'not a finite number' unless value.finite?

          value
        when Symbol then value.to_s
        else raise Invalid, "#{value.class} is not kept in state"
        end
      end

      # A base in its checked form: { app => { key => entry } } with string
      # keys, an entry that does not fit left out. Returns [base, dropped]
      # (dropped: how many entries were left out); base is nil when empty.
      def clean_base(state)
        return [nil, 0] unless state.is_a?(Hash)

        dropped = 0
        base = state.each_with_object({}) do |(app_key, entries), out|
          app = app_key.to_s
          next if RESERVED_APPS.include?(app)
          next dropped += 1 unless APP.match?(app) && entries.is_a?(Hash)

          kept = entries.each_with_object({}) do |(key, entry), app_out|
            checked = base_entry(key.to_s, entry)
            checked ? app_out[key.to_s] = checked : dropped += 1
          end
          out[app] = kept unless kept.empty?
        end
        return [nil, dropped] if base.empty?
        return [nil, dropped + base.values.sum(&:size)] if JSON.generate(base).bytesize > CHAT_BYTES

        [deep_freeze(base), dropped]
      end

      # A checked base in the form a session keeps app state in
      # ({ app => { key => { data:, version:, updated_at: } } }, unfrozen,
      # for the code that writes into it), or nil.
      def to_session(base)
        return nil unless base.is_a?(Hash) && !base.empty?

        base.to_h do |app, entries|
          [app, entries.to_h do |key, entry|
            [key, { data: JSON.parse(JSON.generate(entry['data'])), version: entry['version'], updated_at: entry['updated_at'] }]
          end]
        end
      end

      def base_entry(key, entry)
        return nil unless BASE_KEY.match?(key) && entry.is_a?(Hash)

        e = entry.transform_keys(&:to_s)
        return nil unless e.key?('data')

        out = { 'data' => data(e['data']), 'version' => e['version'].to_i }
        out['updated_at'] = e['updated_at'] if e['updated_at'].is_a?(String) && e['updated_at'].length <= 40
        return nil if JSON.generate(out).bytesize > READ_BYTES

        out
      rescue Invalid, JSON::GeneratorError
        nil
      end

      def deep_freeze(value)
        case value
        when Hash then value.each_value { |v| deep_freeze(v) }
        when Array then value.each { |v| deep_freeze(v) }
        end
        value.freeze
      end
    end
  end
end
