# frozen_string_literal: true

require_relative '../workspace/ids'
require_relative '../workspace/ledger_schema'

module Monadic
  module Workbench
    # The record of what a reply made, kept on its message
    # (message["artifacts"]): what the history, the export and the import
    # carry. Each entry names an image of the chat's folder (its ledger id
    # and its path in the shared folder) with these fields only: no token,
    # URL or local path. What comes from an import is a claim of what was
    # made; it grants nothing in this environment (reading an image goes
    # through the ledger, Artifact).
    module Record
      LIMIT = 20
      FIELDS = %w[id path name sha256 content_type created_at derived_from].freeze
      SHA256 = /\A\h{64}\z/
      PATH = %r{\Aconversations/[A-Za-z0-9][A-Za-z0-9._-]{0,150}/artifacts/([^/]+)\z}
      TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/

      module_function

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
        return nil unless Monadic::Workspace::Ids.valid?(:artifact, entry['id']) && SHA256.match?(entry['sha256'].to_s)

        name = entry['path'].to_s[PATH, 1]
        ext = name && name[Monadic::Workspace::LedgerSchema::IMAGE_NAME, 1]
        return nil unless ext && entry['name'] == name
        return nil unless entry['content_type'] == Monadic::Workspace::LedgerSchema::IMAGE_TYPES[ext]
        return nil unless entry['derived_from'].nil? || Monadic::Workspace::Ids.valid?(:artifact, entry['derived_from'])
        return nil unless TIME.match?(entry['created_at'].to_s)

        entry.slice(*FIELDS)
      end

      # The path of the image made last in this conversation, by the
      # messages' records (newest message first), or nil. What the record
      # says is all this reads: a restart or a chat taken from the history
      # gives the same answer.
      def last_path(messages)
        Array(messages).reverse_each do |message|
          next unless message.is_a?(Hash)

          entries = clean(message['artifacts'] || message[:artifacts])
          return entries.last['path'] if entries
        end
        nil
      end
    end
  end
end
