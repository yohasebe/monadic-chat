# frozen_string_literal: true

# Shared support for the Privacy golden-fixture safety net (Phase 2.1).
#
# Why golden fixtures: the Substitution Pipeline Phase 2.2 refactor moves the
# *Ruby* privacy orchestration (registry merge, restore round-trip, TTS
# sanitization, span/registry-entry derivation, language/entity-type
# resolution) onto a provider abstraction. Entity *detection* itself lives in
# the Python Presidio container and is NOT refactored. These fixtures pin the
# Ruby transformation layer so a behaviour change is caught immediately.
#
# Three design properties (see docs_dev / memory privacy-golden-fixtures-design):
#   1. Recorded cassettes — capture.rb records the live container's
#      /v1/anonymize responses once; the golden spec replays them through a
#      StubBackend. Deterministic, container-free, no language-detector flake.
#   2. Format-neutral fixtures — tokens are stored in a *canonical* notation
#      ({{TYPE_N}}) deliberately distinct from the current wire form
#      (<<TYPE_N>>). The harness renders canonical -> wire at the pipeline
#      boundary and canonicalizes wire -> canonical on the way out, so a future
#      wire-format migration (e.g. ${TYPE_N}) only touches Format::WIRE_* here,
#      never the fixtures. The distinct canonical form means the indirection is
#      exercised on every run and cannot silently rot.
#   3. Shared harness — capture and spec both run fixtures through Harness.run,
#      so the snapshot the human reviews at capture time is the exact shape the
#      spec asserts.

require 'yaml'

privacy_lib = File.expand_path('../../../lib/monadic/utils/privacy', __dir__)
require File.join(privacy_lib, 'pipeline')
require File.join(privacy_lib, 'types')
require File.join(privacy_lib, 'registry')
require File.join(privacy_lib, 'presidio_backend')
require File.join(privacy_lib, 'streaming_restorer')

module PrivacyGolden
  # Canonical <-> wire token translation. The *only* place that knows the
  # current wire placeholder format. Phase 2.2 changes WIRE_* (and, when it
  # extracts a production SSOT, delegates to it); the drift-guard spec asserts
  # these stay in lockstep with the production regexes.
  module Format
    # Canonical fixture notation — kept distinct from the wire form on purpose.
    CANON_RE  = /\{\{([A-Z_]+_\d+)\}\}/
    # Current production wire form (Python server.py + Ruby Pipeline regexes).
    WIRE_OPEN  = '<<'
    WIRE_CLOSE = '>>'
    WIRE_RE    = /<<([A-Z_]+_\d+)>>/

    module_function

    # "{{PERSON_1}}" -> "<<PERSON_1>>"
    def to_wire(str)
      return str unless str.is_a?(String)
      str.gsub(CANON_RE) { "#{WIRE_OPEN}#{Regexp.last_match(1)}#{WIRE_CLOSE}" }
    end

    # "<<PERSON_1>>" -> "{{PERSON_1}}"
    def to_canon(str)
      return str unless str.is_a?(String)
      str.gsub(WIRE_RE) { "{{#{Regexp.last_match(1)}}}" }
    end

    # Rewrite a single canonical token body (no braces) to a wire token.
    def render(type, index)
      "#{WIRE_OPEN}#{type}_#{index}#{WIRE_CLOSE}"
    end

    def canon_keys(hash)
      hash.each_with_object({}) { |(k, v), o| o[to_canon(k.to_s)] = v }
    end
  end

  # Replays recorded backend responses in call order. Used by the golden spec;
  # never touches the network. A response carrying :error simulates a backend
  # failure (for on_failure mode fixtures).
  class StubBackend
    def initialize(responses)
      @responses = responses.dup
    end

    def anonymize(text:, languages:, registry:, entity_types: nil, options: {})
      resp = @responses.shift
      raise Monadic::Utils::Privacy::BackendError, (resp && resp[:error]) || 'no recorded response' if resp.nil? || resp[:error]
      resp
    end

    def deanonymize(text:, registry:)
      raise NotImplementedError
    end

    def health
      true
    end
  end

  # Wraps a live PresidioBackend and records each anonymize response verbatim.
  # Used only by capture.rb against the running container.
  class RecordingBackend
    attr_reader :recordings

    def initialize(inner)
      @inner = inner
      @recordings = []
    end

    def anonymize(**kwargs)
      resp = @inner.anonymize(**kwargs)
      @recordings << resp
      resp
    end

    def deanonymize(**kwargs)
      @inner.deanonymize(**kwargs)
    end

    def health
      @inner.health
    end
  end

  # Runs one fixture through the real Privacy::Pipeline and returns its
  # observable outputs in canonical notation. Shared by capture (to generate
  # the golden snapshot) and the spec (to compare against it).
  module Harness
    module_function

    # @param fixture [Hash] string-keyed: 'config', 'language', 'turns'
    # @param backend [#anonymize] RecordingBackend (capture) or StubBackend (spec)
    # @return [Hash] normalized canonical outputs matching fixture['golden']
    def run(fixture, backend)
      config = (fixture['config'] || {}).transform_keys(&:to_sym)
      session = { parameters: { 'conversation_language' => fixture['language'] } }
      pipeline = Monadic::Utils::Privacy::Pipeline.new(backend: backend, config: config, session: session)

      turns = (fixture['turns'] || []).map { |turn| run_turn(pipeline, turn) }

      {
        'turns' => turns,
        'registry' => Format.canon_keys(pipeline.registry_state[:registry] || {}),
        'registry_entries' => canon_entries(pipeline.registry_entries)
      }
    end

    def run_turn(pipeline, turn)
      raw = Monadic::Utils::Privacy::RawMessage.new(turn['input'], 'user', {})
      masked = pipeline.before_send_to_llm(raw)
      masked_text = masked.text
      tts_masked = pipeline.sanitize_for_tts(masked_text)

      # The LLM "reply" defaults to echoing the masked text (a pure round-trip).
      # Fixtures override 'llm_output' (canonical) to exercise reordering,
      # repetition (span dedup) and unknown placeholders (missing).
      llm_wire = Format.to_wire(turn['llm_output'] || Format.to_canon(masked_text))
      restored = pipeline.after_receive_from_llm(llm_wire)
      restored_text = restored.text

      # Every string field is canonicalized so the *whole* golden is format
      # neutral. Normally restored text / TTS labels carry no tokens (to_canon
      # is a no-op); the exception is an unrestored placeholder (the "missing"
      # case) which the pipeline leaves as a raw wire token — canonicalizing it
      # keeps the fixture stable across a future wire-format migration.
      {
        'masked_message' => Format.to_canon(masked_text),
        'tts_masked' => Format.to_canon(tts_masked),
        'restored' => {
          'text' => Format.to_canon(restored_text),
          'restored_spans' => canon_spans(restored.meta[:restored_spans] || []),
          'missing_placeholders' => (restored.meta[:missing_placeholders] || []).map { |p| Format.to_canon(p) }
        },
        'tts_restored' => Format.to_canon(pipeline.sanitize_restored_for_tts(restored_text))
      }
    rescue Monadic::Utils::Privacy::BackendError
      # on_failure: :block re-raises here. The behaviour we pin is "the masking
      # call raises and nothing leaks"; the message text is intentionally not
      # asserted (it embeds the transient backend error).
      { 'error' => 'BackendError' }
    end

    def canon_spans(spans)
      spans.map do |s|
        {
          'placeholder' => Format.to_canon(s[:placeholder]),
          'entity_type' => s[:entity_type],
          'original' => s[:original]
        }
      end
    end

    def canon_entries(entries)
      entries.map do |e|
        {
          'placeholder' => Format.to_canon(e[:placeholder]),
          'entity_type' => e[:entity_type],
          'original' => e[:original]
        }
      end
    end
  end

  # Turn a stored (canonical, string-keyed) cassette response into the exact
  # shape PresidioBackend#anonymize returns (symbol top-level keys, wire
  # tokens). Used by the spec to build StubBackend responses.
  module Cassette
    module_function

    def to_backend_response(stored)
      return { error: stored['error'] } if stored['error']
      {
        masked_text: Format.to_wire(stored['masked_text']),
        registry: (stored['registry'] || {}).each_with_object({}) { |(k, v), o| o[Format.to_wire(k)] = v },
        entities: (stored['entities'] || []).map { |e| wire_entity(e) },
        stats: stored['stats'] || {}
      }
    end

    def wire_entity(entity)
      entity.each_with_object({}) do |(k, v), o|
        o[k] = (k == 'placeholder') ? Format.to_wire(v) : v
      end
    end
  end
end
