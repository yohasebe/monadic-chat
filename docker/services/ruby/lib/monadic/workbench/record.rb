# frozen_string_literal: true

module Monadic
  module Workbench
    # The record of what was saved from the workbench, kept on the message
    # that asked (message["artifacts"]): what the history, the export and the
    # import carry. Only saved artifacts are recorded, each with these fields
    # and no token, path or URL. What comes from an import is a claim of what
    # was saved; it grants nothing in this environment.
    module Record
      LIMIT = 20
      FIELDS = %w[id name sha256 content_type derived_from action by saved_at].freeze
      SHA256 = /\A\h{64}\z/
      ID = /\Ar_[a-f0-9]{20}\z/
      NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,150}\z/
      TYPES = %w[image/png image/jpeg image/webp].freeze
      TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/

      module_function

      def entry(artifact_id:, name:, sha256:, content_type:, derived_from:, saved_at:)
        { 'id' => artifact_id, 'name' => name, 'sha256' => sha256, 'content_type' => content_type,
          'derived_from' => derived_from, 'action' => 'saved', 'by' => 'user', 'saved_at' => saved_at }
      end

      # The entries of list that have this form, each with only its fields;
      # anything else is left out. nil when there is none.
      def clean(list)
        return nil unless list.is_a?(Array)

        entries = list.first(LIMIT).filter_map { |entry| clean_entry(entry) }
        entries.empty? ? nil : entries
      end

      def clean_entry(entry)
        return nil unless entry.is_a?(Hash)

        entry = entry.transform_keys(&:to_s)
        return nil unless (entry.keys - FIELDS).empty?
        return nil unless ID.match?(entry['id'].to_s) && NAME.match?(entry['name'].to_s) && SHA256.match?(entry['sha256'].to_s)
        return nil unless TYPES.include?(entry['content_type']) && entry['action'] == 'saved' && entry['by'] == 'user'
        return nil unless entry['derived_from'].nil? || SHA256.match?(entry['derived_from'].to_s)
        return nil unless TIME.match?(entry['saved_at'].to_s)

        entry.slice(*FIELDS)
      end

      # The name of the image saved last in this conversation, by the
      # messages' records (newest message first), or nil. What the record
      # says is all this reads: a restart or a chat taken from the history
      # gives the same answer.
      def last_saved_name(messages)
        Array(messages).reverse_each do |message|
          next unless message.is_a?(Hash)

          entries = clean(message['artifacts'] || message[:artifacts])
          return entries.last['name'] if entries
        end
        nil
      end

      # Adds entry to the message's record unless an entry of that id is
      # there (recording the same save twice changes nothing). True when it
      # was added.
      def add!(message, entry)
        list = Array(message['artifacts'])
        return false if list.any? { |e| e['id'] == entry['id'] }

        message['artifacts'] = list + [entry]
        true
      end
    end
  end
end
