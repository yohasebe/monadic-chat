# frozen_string_literal: true

module Monadic
  module Workbench
    module Look
      # What a message keeps of the looks of its reply (Ledger#records), as
      # read back from a message, a history or an import: the listed fields
      # only, of the listed kinds and sizes. It names what was looked at; it
      # never gives the bytes or a way to read them again.
      module Record
        LIMIT = 8
        STATES = %w[acquired embedded sent unsent refused unknown].freeze
        KINDS = %w[image text].freeze
        SCOPES = %w[visible whole].freeze
        SOURCES = %w[workbench_image workbench_file].freeze
        TEXT_FIELDS = { 'id' => 40, 'item_id' => 40, 'name' => 255, 'path' => 1024, 'at' => 40 }.freeze
        HASH = /\A[0-9a-f]{64}\z/

        module_function

        # The records in list that are well formed, or nil when none is.
        def clean(list)
          return nil unless list.is_a?(Array)

          kept = list.first(LIMIT).filter_map { |entry| clean_one(entry) }
          kept.empty? ? nil : kept
        end

        def clean_one(entry)
          return nil unless entry.is_a?(Hash)

          entry = entry.transform_keys(&:to_s)
          out = {}
          TEXT_FIELDS.each do |key, limit|
            value = entry[key]
            out[key] = value.gsub(/[[:cntrl:]]/, ' ')[0, limit] if value.is_a?(String) && !value.empty?
          end
          return nil unless out['id'] && KINDS.include?(entry['kind']) && STATES.include?(entry['state'])

          out['kind'] = entry['kind']
          out['state'] = entry['state']
          %w[version image_sha256].each { |key| out[key] = entry[key] if entry[key].is_a?(String) && entry[key].match?(HASH) }
          out['source'] = entry['source'] if SOURCES.include?(entry['source'])
          out['scope'] = entry['scope'] if SCOPES.include?(entry['scope'])
          %w[image truncated empty].each { |key| out[key] = entry[key] if [true, false].include?(entry[key]) }
          lines = entry['lines']
          if lines.is_a?(Hash)
            lines = lines.transform_keys(&:to_s)
            picked = lines.slice('first', 'last', 'total').select { |_, v| v.is_a?(Integer) && v >= 0 }
            picked['partial'] = true if lines['partial'] == true && !picked.empty?
            out['lines'] = picked unless picked.empty?
          end
          out
        end
      end
    end
  end
end
