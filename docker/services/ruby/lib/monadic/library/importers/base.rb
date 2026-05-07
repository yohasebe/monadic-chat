# frozen_string_literal: true

require 'securerandom'
require 'time'

module Monadic
  module Library
    module Importers
      # Shared helpers used by every importer. Importers consume some
      # external format and produce a Hash that conforms to the
      # monadic-conversation v1 JSON Schema.
      module Base
        module_function

        # Padded sequential message id ("msg-0001" through "msg-9999").
        # Used so message ordering is reflected in the id alphabetically.
        def message_id(idx)
          format('msg-%04d', idx + 1)
        end

        # Slug a free-form label into a stable participant id. Lower-cases,
        # replaces non-alphanumerics with underscores, and trims length so
        # the id stays human-scannable.
        def participant_id(label)
          slug = label.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_+|_+$/, '')
          slug = slug[0, 32]
          slug.empty? ? "p_#{SecureRandom.hex(4)}" : slug
        end

        def now_iso8601
          Time.now.utc.iso8601
        end

        def new_conversation_id
          SecureRandom.uuid
        end

        # Derive a default title from a filename — basename without the
        # extension. Returns nil when the input is blank so callers can
        # fall back to other defaults.
        def derive_title_from_filename(filename)
          return nil if filename.to_s.strip.empty?
          base = File.basename(filename.to_s, '.*')
          base.empty? ? nil : base
        end

        # Compose the conversation_metadata object from explicit options
        # plus required defaults. options is a Hash from the importer caller.
        def build_metadata(source:, options: {})
          meta = {
            'source' => source,
            'language' => options[:language] || options['language'] || 'en',
            'license' => options[:license] || options['license'] || 'private'
          }
          %w[external_id title publication_date duration_seconds cite_as content_type pii_status].each do |k|
            v = options[k.to_sym] || options[k]
            meta[k] = v unless v.nil?
          end
          topics = options[:topics] || options['topics']
          meta['topics'] = Array(topics) if topics
          meta['retrieved_at'] = options[:retrieved_at] || options['retrieved_at'] || now_iso8601
          meta
        end
      end
    end
  end
end
