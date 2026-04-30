# frozen_string_literal: true

require "json"
require "json_schemer"

require_relative "version"

module Monadic
  module Library
    # Validator wrapper around the monadic-conversation v1 JSON Schema.
    # Loads the schema once and exposes valid?/validate for callers.
    module Schema
      module_function

      # Path to the JSON Schema document. Resolved relative to this file so
      # both dev and packaged environments work without ENV tweaks.
      SCHEMA_PATH = File.expand_path(
        "../../../schema/monadic-conversation-v#{FORMAT_VERSION.split('.').first}.json",
        __dir__
      )

      # Cached JSONSchemer instance. Lazily built so requiring this file does
      # not pay the parsing cost up front.
      def schemer
        @schemer ||= begin
          schema_json = JSON.parse(File.read(SCHEMA_PATH))
          JSONSchemer.schema(
            schema_json,
            meta_schema: "https://json-schema.org/draft/2020-12/schema"
          )
        end
      end

      # Boolean predicate. Returns true when data conforms to the schema.
      def valid?(data)
        schemer.valid?(data)
      end

      # Returns an array of error hashes (JSONSchemer's standard shape) for
      # each violation. Empty array means the data is valid.
      def validate(data)
        schemer.validate(data).to_a
      end

      # Drop the cached schemer so a hot-reloaded schema file is picked up.
      # Used in development and tests.
      def reset!
        @schemer = nil
      end
    end
  end
end
