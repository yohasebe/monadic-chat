# frozen_string_literal: true

module Monadic
  module Utils
    module Privacy
      class BackendError < StandardError; end

      # Pluggable backend interface. Phase 1 ships PresidioBackend; future
      # alternatives (e.g. GLiNER) implement the same three methods.
      class Backend
        # @return [{ masked_text: String, registry: Hash, entities: Array<Hash> }]
        def anonymize(text:, languages:, registry:, options: {})
          raise NotImplementedError
        end

        # @return [{ restored_text: String, missing: Array<String> }]
        def deanonymize(text:, registry:)
          raise NotImplementedError
        end

        def health
          raise NotImplementedError
        end
      end
    end
  end
end
