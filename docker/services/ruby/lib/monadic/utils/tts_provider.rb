# frozen_string_literal: true

module Monadic
  module Utils
    module TtsProvider
      GEMINI_LABELS = %w[gemini gemini-flash gemini-flash-lite gemini-pro].freeze

      # Only the unsuffixed legacy label follows the default list order.
      # Explicit variants must never silently resolve to a different family.
      def self.resolve_gemini_model(label, models)
        case label
        when "gemini"
          models&.first
        when "gemini-flash-lite"
          models&.find { |model| model.include?("flash-lite") }
        when "gemini-flash"
          models&.find { |model| model.include?("-flash-") && !model.include?("flash-lite") && !model.include?("-pro-") }
        when "gemini-pro"
          models&.find { |model| model.include?("-pro-") }
        end
      end

      def self.gemini?(label)
        GEMINI_LABELS.include?(label)
      end
    end
  end
end
