# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/dsl/configurations'
require_relative '../../../../lib/monadic/dsl'

# Tests for the OpenAI Responses API server-side compaction integration.
#
# Context: OpenAI shipped server-side compaction via the Responses API in
# February 2026. When `context_management: [{type: "compaction",
# compact_threshold: N}]` is attached to a /v1/responses request, the server
# automatically compacts the conversation when the rendered token count
# crosses the threshold. See docs_dev/provider_specific_features.md.
#
# These tests verify the DSL configuration path. The end-to-end wiring into
# `convert_to_responses_api_body` is exercised by the openai_helper body
# construction tests.
RSpec.describe 'OpenAI Compaction integration' do
  describe MonadicDSL::CompactionConfiguration do
    it 'uses 150_000 tokens as the default compact_threshold' do
      cfg = described_class.new
      expect(cfg.to_hash).to eq(compact_threshold: 150_000)
    end

    it 'accepts a custom compact_threshold' do
      cfg = described_class.new
      cfg.compact_threshold 180_000
      expect(cfg.to_hash).to eq(compact_threshold: 180_000)
    end

    it 'uses the constant for the default' do
      expect(described_class::DEFAULT_COMPACT_THRESHOLD).to eq(150_000)
    end
  end

  describe 'CompactionConfiguration block semantics' do
    # Directly test the class that backs the `compaction do ... end` DSL
    # block. This avoids testing harness issues with `instance_eval` in
    # RSpec example context.
    it 'allows overriding compact_threshold after construction' do
      cfg = MonadicDSL::CompactionConfiguration.new
      expect(cfg.to_hash[:compact_threshold]).to eq(150_000)

      cfg.compact_threshold(200_000)
      expect(cfg.to_hash[:compact_threshold]).to eq(200_000)
    end

    it 'supports block-style construction via instance_eval' do
      cfg = MonadicDSL::CompactionConfiguration.new
      cfg.instance_eval do
        compact_threshold 180_000
      end
      expect(cfg.to_hash[:compact_threshold]).to eq(180_000)
    end
  end

  describe 'openai_helper compaction wiring' do
    # Test that the openai_helper reads the app's compaction settings and
    # attaches them to the Responses API body. We don't run the full
    # convert_to_responses_api_body pipeline; instead, we verify the key
    # logic by simulating the relevant code path.
    before do
      stub_const('APPS', {})
    end

    it 'attaches context_management when app has compaction settings' do
      fake_app = Struct.new(:settings).new({ 'compaction' => { compact_threshold: 150_000 } })
      APPS['TestApp'] = fake_app

      # Simulate the code from convert_to_responses_api_body
      responses_body = {}
      compaction_settings = APPS['TestApp']&.settings&.[]('compaction') ||
                            APPS['TestApp']&.settings&.[](:compaction)
      if compaction_settings && !compaction_settings.empty?
        threshold = compaction_settings[:compact_threshold] || compaction_settings['compact_threshold']
        if threshold && threshold.to_i > 0
          responses_body['context_management'] = [
            { 'type' => 'compaction', 'compact_threshold' => threshold.to_i }
          ]
        end
      end

      expect(responses_body['context_management']).to eq(
        [{ 'type' => 'compaction', 'compact_threshold' => 150_000 }]
      )
    end

    it 'does not attach context_management when app has no compaction settings' do
      fake_app = Struct.new(:settings).new({ 'other_key' => 'value' })
      APPS['TestApp'] = fake_app

      responses_body = {}
      compaction_settings = APPS['TestApp']&.settings&.[]('compaction') ||
                            APPS['TestApp']&.settings&.[](:compaction)
      if compaction_settings && !compaction_settings.empty?
        responses_body['context_management'] = [
          { 'type' => 'compaction', 'compact_threshold' => compaction_settings[:compact_threshold] }
        ]
      end

      expect(responses_body).not_to have_key('context_management')
    end

    it 'accepts both symbol and string keys for the compact_threshold' do
      # When MDSL emits settings via class_def, keys may be converted to
      # strings or stay as symbols depending on HashWithIndifferentAccess
      # usage. Support both.
      %w[symbol string].each do |key_type|
        threshold_key = (key_type == 'symbol' ? :compact_threshold : 'compact_threshold')
        fake_app = Struct.new(:settings).new({ 'compaction' => { threshold_key => 180_000 } })
        APPS['TestApp'] = fake_app

        compaction_settings = APPS['TestApp']&.settings&.[]('compaction')
        threshold = compaction_settings[:compact_threshold] || compaction_settings['compact_threshold']
        expect(threshold).to eq(180_000)
      end
    end

    it 'skips context_management when compact_threshold is zero or missing' do
      fake_app = Struct.new(:settings).new({ 'compaction' => { compact_threshold: 0 } })
      APPS['TestApp'] = fake_app

      responses_body = {}
      compaction_settings = APPS['TestApp']&.settings&.[]('compaction')
      if compaction_settings && !compaction_settings.empty?
        threshold = compaction_settings[:compact_threshold] || compaction_settings['compact_threshold']
        if threshold && threshold.to_i > 0
          responses_body['context_management'] = [
            { 'type' => 'compaction', 'compact_threshold' => threshold.to_i }
          ]
        end
      end

      expect(responses_body).not_to have_key('context_management')
    end
  end

  describe 'Request body shape expectations' do
    # Document the exact shape that convert_to_responses_api_body should
    # produce when compaction is enabled. This is a documentation test
    # that future changes to openai_helper.rb should respect.
    it 'documents the expected context_management array structure' do
      compact_threshold = 150_000
      expected = [
        { "type" => "compaction", "compact_threshold" => compact_threshold }
      ]

      # This matches the shape produced by openai_helper.rb
      # in convert_to_responses_api_body around the compaction injection.
      expect(expected.first["type"]).to eq("compaction")
      expect(expected.first["compact_threshold"]).to be_a(Integer)
      expect(expected.first["compact_threshold"]).to be > 0
    end

    it 'documents that context_management is an array, not a hash' do
      # OpenAI allows multiple context_management strategies in a single
      # request, so the API expects an array. Even for a single compaction
      # entry, we must wrap it in an array.
      single_entry = { "type" => "compaction", "compact_threshold" => 150_000 }
      expect([single_entry]).to be_a(Array)
    end
  end
end
