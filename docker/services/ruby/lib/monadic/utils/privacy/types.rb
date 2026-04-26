# frozen_string_literal: true

# Strongly-typed value objects for the privacy pipeline.
#
# The chain is:
#   RawMessage → MaskedMessage → (sent to LLM) → MaskedResponse → RestoredResponse
#
# Conversions go through dedicated methods (#to_masked, #to_restored) so a
# stray RawMessage cannot be passed where a MaskedMessage is expected.
# This is the runtime equivalent of "do not let unmasked text reach the LLM".

module Monadic
  module Utils
    module Privacy
      # Maps DSL mask_types symbols to Presidio canonical entity type strings.
      # Source of truth shared by PrivacyFilterConfiguration (DSL whitelist
      # validation) and Pipeline (runtime translation for the backend).
      PRESIDIO_TYPE_MAP = {
        person: 'PERSON',
        organization: 'ORGANIZATION',
        email: 'EMAIL_ADDRESS',
        url: 'URL',
        address: 'LOCATION',
        postal_code: 'POSTAL_CODE',
        phone: 'PHONE_NUMBER',
        credit_card: 'CREDIT_CARD',
        ip: 'IP_ADDRESS',
        iban: 'IBAN_CODE',
        us_ssn: 'US_SSN',
        medical_license: 'US_MEDICAL_LICENSE'
      }.freeze

      RawMessage = Struct.new(:text, :role, :meta) do
        def safe_for_llm?
          false
        end

        def to_masked(masked_text, entities)
          MaskedMessage.new(masked_text, role, (meta || {}).merge(
            privacy: { masked: true, entities: entities, original_length: text.length }
          ))
        end
      end

      MaskedMessage = Struct.new(:text, :role, :meta) do
        def safe_for_llm?
          true
        end
      end

      MaskedResponse = Struct.new(:text, :meta) do
        def to_restored(restored_text, missing)
          RestoredResponse.new(restored_text, (meta || {}).merge(
            privacy: { restored: true, missing_placeholders: missing }
          ))
        end
      end

      RestoredResponse = Struct.new(:text, :meta) do
        def safe_for_user?
          true
        end
      end
    end
  end
end
