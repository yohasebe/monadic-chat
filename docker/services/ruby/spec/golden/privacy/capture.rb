#!/usr/bin/env ruby
# frozen_string_literal: true

# Privacy golden-fixture capture / verify tool (Phase 2.1).
#
#   bundle exec ruby spec/golden/privacy/capture.rb            # (re)record fixtures.yml
#   bundle exec ruby spec/golden/privacy/capture.rb --verify   # diff live vs committed
#
# Live scenarios are recorded against the running Presidio container
# (default http://localhost:8001, override with PRIVACY_DEV_PORT). Synthetic
# scenarios (backend failures) carry an authored cassette and need no
# container. The generated snapshot must be human-reviewed before commit.

require_relative 'support'

module PrivacyGolden
  module Capture
    FIXTURES_PATH = File.expand_path('fixtures.yml', __dir__)

    BASE_CONFIG = { 'enabled' => true, 'score_threshold' => 0.4, 'honorific_trim' => true }.freeze

    # The scenario catalog. Inputs use synthetic PII (no real people). The
    # `llm_output` field (canonical tokens) defaults to echoing the masked
    # text — set it only to exercise reorder / repetition / unknown tokens.
    SCENARIOS = [
      # ---- single PII type (en) -------------------------------------------
      { id: 'person_en', description: 'Single PERSON, English',
        language: 'en', config: { 'mask_types' => %w[person] },
        turns: [{ input: 'Please contact Alice Johnson about the renewal.' }] },

      { id: 'email_en', description: 'Single EMAIL_ADDRESS, English',
        language: 'en', config: { 'mask_types' => %w[email] },
        turns: [{ input: 'Send the invoice to alice@example.com please.' }] },

      { id: 'phone_en', description: 'Single PHONE_NUMBER, English',
        language: 'en', config: { 'mask_types' => %w[phone] },
        turns: [{ input: 'You can reach the desk at 555-867-5309 after noon.' }] },

      { id: 'credit_card_en', description: 'Single CREDIT_CARD, English',
        language: 'en', config: { 'mask_types' => %w[credit_card] },
        turns: [{ input: 'The card on file is 4111 1111 1111 1111.' }] },

      { id: 'ip_en', description: 'Single IP_ADDRESS, English',
        language: 'en', config: { 'mask_types' => %w[ip] },
        turns: [{ input: 'The gateway at 192.168.1.42 stopped responding.' }] },

      { id: 'iban_en', description: 'Single IBAN_CODE, English',
        language: 'en', config: { 'mask_types' => %w[iban] },
        turns: [{ input: 'Transfer to GB82 WEST 1234 5698 7654 32 by Friday.' }] },

      # US_SSN and POSTAL_CODE are synthetic: this Presidio build does not
      # enable recognizers that fire for them, so we author the cassette Python
      # *would* return to exercise the Ruby path for those token types (notably
      # the multi-segment TTS label "US SSN 1"). The golden outputs are still
      # derived by running the real pipeline against the authored cassette.
      { id: 'us_ssn_en', description: 'Single US_SSN, English (synthetic cassette)',
        language: 'en', config: { 'mask_types' => %w[us_ssn] },
        synthetic: true,
        backend: [{ 'masked_text' => 'The applicant SSN is {{US_SSN_1}} on the form.',
                    'registry' => { '{{US_SSN_1}}' => '123-45-6789' },
                    'entities' => [{ 'placeholder' => '{{US_SSN_1}}', 'type' => 'US_SSN', 'original' => '123-45-6789' }],
                    'stats' => { 'detected' => 1, 'kept_after_merge' => 1, 'kept_after_trim' => 1 } }],
        turns: [{ input: 'The applicant SSN is 123-45-6789 on the form.' }] },

      { id: 'postal_code_en', description: 'Single POSTAL_CODE, English (synthetic cassette)',
        language: 'en', config: { 'mask_types' => %w[postal_code] },
        synthetic: true,
        backend: [{ 'masked_text' => 'Ship the package to postal code {{POSTAL_CODE_1}} please.',
                    'registry' => { '{{POSTAL_CODE_1}}' => '90210' },
                    'entities' => [{ 'placeholder' => '{{POSTAL_CODE_1}}', 'type' => 'POSTAL_CODE', 'original' => '90210' }],
                    'stats' => { 'detected' => 1, 'kept_after_merge' => 1, 'kept_after_trim' => 1 } }],
        turns: [{ input: 'Ship the package to postal code 90210 please.' }] },

      # ---- multiple PII in one message ------------------------------------
      { id: 'multi_pii_en', description: 'PERSON + EMAIL + PHONE in one message',
        language: 'en', config: { 'mask_types' => %w[person email phone] },
        turns: [{ input: 'Alice Johnson (alice@example.com, 555-123-4567) signed off.' }] },

      { id: 'kitchen_sink_en', description: 'Many default PII types together',
        language: 'en', config: { 'mask_types' => %w[person email phone credit_card us_ssn] },
        turns: [{ input: 'Alice Johnson — alice@example.com, 555-123-4567, ' \
                          'SSN 123-45-6789, card 4111 1111 1111 1111 — is verified.' }] },

      # ---- registry reuse within a single message -------------------------
      { id: 'repeated_same_entity_en', description: 'Same PERSON twice reuses one placeholder',
        language: 'en', config: { 'mask_types' => %w[person] },
        turns: [{ input: 'Alice Johnson asked whether Alice Johnson had approved it.' }] },

      # ---- output-path: reorder / dedup / missing / no-token --------------
      { id: 'output_reorder_en', description: 'LLM reorders the placeholders',
        language: 'en', config: { 'mask_types' => %w[person email phone] },
        turns: [{ input: 'Alice Johnson (alice@example.com, 555-123-4567) signed off.',
                  llm_output: 'Reach {{PERSON_1}} on {{PHONE_NUMBER_1}} or {{EMAIL_ADDRESS_1}}.' }] },

      { id: 'output_dedup_en', description: 'LLM repeats one placeholder; spans dedupe',
        language: 'en', config: { 'mask_types' => %w[person] },
        turns: [{ input: 'Alice Johnson will join the call.',
                  llm_output: '{{PERSON_1}} confirmed. I will remind {{PERSON_1}} again.' }] },

      { id: 'output_missing_placeholder_en', description: 'LLM emits an unregistered placeholder',
        language: 'en', config: { 'mask_types' => %w[person] },
        turns: [{ input: 'Alice Johnson will join the call.',
                  llm_output: '{{PERSON_1}} and {{PERSON_9}} will attend.' }] },

      { id: 'output_no_placeholder_en', description: 'LLM reply contains no placeholders',
        language: 'en', config: { 'mask_types' => %w[person] },
        turns: [{ input: 'Alice Johnson will join the call.',
                  llm_output: 'Understood, I have noted the attendee.' }] },

      # ---- honorific trim on/off ------------------------------------------
      { id: 'honorific_trim_on_en', description: 'honorific_trim true (default)',
        language: 'en', config: { 'mask_types' => %w[person], 'honorific_trim' => true },
        turns: [{ input: 'Dear Mr. Smith, your appointment is confirmed.' }] },

      { id: 'honorific_trim_off_en', description: 'honorific_trim false',
        language: 'en', config: { 'mask_types' => %w[person], 'honorific_trim' => false },
        turns: [{ input: 'Dear Mr. Smith, your appointment is confirmed.' }] },

      # ---- score threshold gating -----------------------------------------
      { id: 'score_threshold_high_en', description: 'High threshold suppresses a low-score detection',
        language: 'en', config: { 'mask_types' => %w[phone], 'score_threshold' => 0.95 },
        turns: [{ input: 'You can reach the desk at 555-867-5309 after noon.' }] },

      # ---- multi-language --------------------------------------------------
      # Japanese is live (this build's ja NER fires and exercises non-ASCII
      # originals end to end). French is synthetic: this build's fr/de/es NER
      # models do not fire for plain names, so we author the cassette to verify
      # the Ruby path round-trips an accented original ("Marie Dubois") and a
      # non-en language parameter uniformly. Per-language *detection* is the
      # Python container's concern (docker/services/privacy/tests) and language
      # resolution is covered by pipeline_spec.
      { id: 'person_ja', description: 'PERSON, Japanese (live)',
        language: 'ja', config: { 'mask_types' => %w[person] },
        turns: [{ input: '田中太郎さんに連絡を取ってください。' }] },

      { id: 'person_email_fr', description: 'PERSON + EMAIL, French (synthetic cassette)',
        language: 'fr', config: { 'mask_types' => %w[person email] },
        synthetic: true,
        backend: [{ 'masked_text' => 'Veuillez écrire à {{PERSON_1}} à {{EMAIL_ADDRESS_1}}.',
                    'registry' => { '{{PERSON_1}}' => 'Marie Dubois', '{{EMAIL_ADDRESS_1}}' => 'marie.dubois@example.com' },
                    'entities' => [
                      { 'placeholder' => '{{PERSON_1}}', 'type' => 'PERSON', 'original' => 'Marie Dubois' },
                      { 'placeholder' => '{{EMAIL_ADDRESS_1}}', 'type' => 'EMAIL_ADDRESS', 'original' => 'marie.dubois@example.com' }
                    ],
                    'stats' => { 'detected' => 2, 'kept_after_merge' => 2, 'kept_after_trim' => 2 } }],
        turns: [{ input: 'Veuillez écrire à Marie Dubois à marie.dubois@example.com.' }] },

      # ---- multi-turn registry accumulation -------------------------------
      { id: 'multiturn_accumulate_en', description: 'PERSON reused across turns, new PERSON added',
        language: 'en', config: { 'mask_types' => %w[person] },
        turns: [
          { input: 'Alice Johnson emailed the quarterly report.' },
          { input: 'Alice Johnson also looped in Robert Chen on the thread.' }
        ] },

      # ---- pipeline disabled (pass-through) -------------------------------
      { id: 'disabled_passthrough_en', description: 'enabled=false: text passes through untouched',
        language: 'en', config: { 'enabled' => false, 'mask_types' => %w[person email] },
        turns: [{ input: 'Alice Johnson (alice@example.com) sent the file.' }] },

      # ---- synthetic backend failures -------------------------------------
      { id: 'failure_block', description: 'on_failure=:block re-raises (no leak)',
        language: 'en', config: { 'mask_types' => %w[person], 'on_failure' => 'block' },
        synthetic: true,
        backend: [{ 'error' => 'simulated backend outage' }],
        turns: [{ input: 'Alice Johnson will join the call.' }] },

      { id: 'failure_pass', description: 'on_failure=:pass forwards raw text on backend failure',
        language: 'en', config: { 'mask_types' => %w[person], 'on_failure' => 'pass' },
        synthetic: true,
        backend: [{ 'error' => 'simulated backend outage' }],
        turns: [{ input: 'Alice Johnson will join the call.' }] }
    ].freeze

    module_function

    def endpoint
      "http://localhost:#{ENV.fetch('PRIVACY_DEV_PORT', '8001')}"
    end

    def stringify_turn(turn)
      out = { 'input' => turn[:input] }
      out['llm_output'] = turn[:llm_output] if turn[:llm_output]
      out
    end

    # Canonicalize a live RecordingBackend response array for storage.
    def store_recordings(recordings)
      recordings.map do |r|
        {
          'masked_text' => Format.to_canon(r[:masked_text]),
          'registry' => (r[:registry] || {}).each_with_object({}) { |(k, v), o| o[Format.to_canon(k.to_s)] = v },
          'entities' => (r[:entities] || []).map { |e| canon_entity(e) },
          'stats' => r[:stats] || {}
        }
      end
    end

    def canon_entity(entity)
      entity.each_with_object({}) do |(k, v), o|
        o[k.to_s] = (k.to_s == 'placeholder') ? Format.to_canon(v) : v
      end
    end

    def build_fixture(scenario)
      config = BASE_CONFIG.merge(scenario[:config] || {})
      fixture = {
        'id' => scenario[:id],
        'description' => scenario[:description],
        'language' => scenario[:language],
        'config' => config,
        'turns' => scenario[:turns].map { |t| stringify_turn(t) }
      }

      if scenario[:synthetic]
        responses = scenario[:backend].map { |r| Cassette.to_backend_response(r) }
        fixture['synthetic'] = true
        fixture['backend'] = scenario[:backend]
        fixture['golden'] = Harness.run(fixture, StubBackend.new(responses))
      else
        recorder = RecordingBackend.new(Monadic::Utils::Privacy::PresidioBackend.new(endpoint: endpoint))
        fixture['golden'] = Harness.run(fixture, recorder)
        fixture['backend'] = store_recordings(recorder.recordings)
      end
      fixture
    end

    def record_all
      health_check!
      fixtures = SCENARIOS.map do |scenario|
        warn "  recording #{scenario[:id]}..."
        build_fixture(scenario)
      end
      File.write(FIXTURES_PATH, fixtures.to_yaml)
      warn "Wrote #{fixtures.length} fixtures to #{FIXTURES_PATH}"
    end

    # Re-record live scenarios and diff their backend cassettes against the
    # committed file. Surfaces Presidio detection-contract drift without
    # rewriting fixtures. Exit 1 on drift.
    def verify
      health_check!
      committed = YAML.safe_load_file(FIXTURES_PATH)
      by_id = committed.each_with_object({}) { |f, h| h[f['id']] = f }
      drift = []

      SCENARIOS.reject { |s| s[:synthetic] }.each do |scenario|
        fresh = build_fixture(scenario)
        old = by_id[scenario[:id]]
        if old.nil?
          drift << "#{scenario[:id]}: missing from committed fixtures"
        elsif old['backend'] != fresh['backend']
          drift << "#{scenario[:id]}: backend cassette drift (Presidio contract changed)"
        elsif old['golden'] != fresh['golden']
          drift << "#{scenario[:id]}: golden drift with identical backend (harness change?)"
        end
      end

      if drift.empty?
        warn 'Cassettes match the live container. No drift.'
      else
        warn 'DRIFT detected:'
        drift.each { |d| warn "  - #{d}" }
        exit 1
      end
    end

    def health_check!
      backend = Monadic::Utils::Privacy::PresidioBackend.new(endpoint: endpoint)
      return if backend.health

      abort "Presidio container not healthy at #{endpoint}. Start it (rake server:debug / monadic.sh ensure-service privacy) and retry."
    end
  end
end

PrivacyGolden::Capture.send(ARGV.include?('--verify') ? :verify : :record_all)
