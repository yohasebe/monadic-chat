# frozen_string_literal: true

require_relative "model_spec"

module Monadic
  module Utils
    module TtsProvider
      def self.gemini?(label)
        provider_of(label) == "gemini"
      end

      MAX_ALIAS_HOPS = 5

      # A TTS provider selector value resolved through ttsChoices
      # (model_spec.js): { requested_id:, id:, provider:, model:, execution: },
      # following `alias` for values saved by earlier versions. nil for an
      # empty, unknown or broken value, which is never sent to another
      # provider in its place.
      def self.choice(label)
        requested = label.to_s.strip
        return nil if requested.empty?

        choices = Monadic::Utils::ModelSpec.load_tts_choices
        id = requested
        MAX_ALIAS_HOPS.times do
          entry = choices[id]
          return nil unless entry.is_a?(Hash)

          if entry["alias"]
            id = entry["alias"].to_s
            next
          end
          return nil if entry["provider"].to_s.empty?

          return { requested_id: requested, id: id, provider: entry["provider"].to_s,
                   model: entry["model"], execution: (entry["execution"] || "server").to_s }
        end
        nil
      end

      def self.provider_of(label)
        choice(label)&.dig(:provider)
      end

      def self.model_for(label)
        choice(label)&.dig(:model)
      end
    end
  end
end
