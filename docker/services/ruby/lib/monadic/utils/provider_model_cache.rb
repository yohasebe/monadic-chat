# frozen_string_literal: true

require_relative 'system_defaults'

module Monadic
  module Utils
    module ProviderModelCache
      class << self
        def fetch(provider_key, fallback: [], &block)
          key = provider_key.to_s.downcase
          cache[key] ||= begin
            resolved_fallback = normalize_models(fallback)
            default_model = default_for(key)
            if default_model && !resolved_fallback.include?(default_model)
              resolved_fallback << default_model
            end

            models = if block_given?
              safe_fetch(key, &block)
            else
              []
            end

            models = normalize_models(models)
            models = resolved_fallback if models.empty?
            models
          end
        end

        def clear(provider_key = nil)
          if provider_key
            cache.delete(provider_key.to_s.downcase)
          else
            cache.clear
          end
        end

        private

        def cache
          @cache ||= {}
        end

        def safe_fetch(provider_key)
          Array(yield)
        rescue StandardError => e
          log(provider_key, e)
          []
        end

        def normalize_models(value)
          Array(value).flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?).uniq
        end

        def default_for(provider_key)
          if defined?(Monadic::Utils::SystemDefaults)
            Monadic::Utils::SystemDefaults.get_default_model(provider_key)
          end
        rescue StandardError => e
          log(provider_key, e)
          nil
        end

        def log(provider_key, error)
          return unless defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "[ProviderModelCache] #{provider_key} model list fallback: #{error.class}: #{error.message}"
        end
      end
    end
  end
end
