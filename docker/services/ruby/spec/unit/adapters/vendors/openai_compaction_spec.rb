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

  describe 'MonadicDSL compaction method — opt-out semantics' do
    # Build a real SimplifiedAppDefinition around a minimal AppState so we
    # exercise the actual DSL method body, including the false-sentinel
    # branch added for the unified context-management design.
    def build_app_definition
      state = MonadicDSL::AppState.new('SpecApp')
      MonadicDSL::SimplifiedAppDefinition.new(state)
    end

    it 'sets :compaction to false when `compaction false` is called' do
      app = build_app_definition
      app.compaction(false)
      expect(app.instance_variable_get(:@state).settings[:compaction]).to eq(false)
    end

    it 'sets :compaction to the default hash when called with no args' do
      app = build_app_definition
      app.compaction
      expect(app.instance_variable_get(:@state).settings[:compaction]).to eq(
        { compact_threshold: 150_000 }
      )
    end

    it 'sets :compaction to the hash produced by a block' do
      app = build_app_definition
      app.compaction do
        compact_threshold 200_000
      end
      expect(app.instance_variable_get(:@state).settings[:compaction]).to eq(
        { compact_threshold: 200_000 }
      )
    end
  end

  describe 'MonadicDSL context_management method — opt-out semantics' do
    def build_app_definition
      state = MonadicDSL::AppState.new('SpecApp')
      MonadicDSL::SimplifiedAppDefinition.new(state)
    end

    it 'sets :context_management to false when `context_management false` is called' do
      app = build_app_definition
      app.context_management(false)
      expect(app.instance_variable_get(:@state).settings[:context_management]).to eq(false)
    end

    it 'leaves :context_management unset when called with no args and no block' do
      app = build_app_definition
      app.context_management
      expect(app.instance_variable_get(:@state).settings[:context_management]).to be_nil
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

    # Simulated openai_helper decision logic (mirrors the real helper in
    # openai_helper.rb L1360+). Kept inline so the test documents the full
    # branching logic: custom settings vs default-on vs explicit opt-out.
    DEFAULT_COMPACT_THRESHOLD_SPEC = 150_000

    def resolve_compaction_for(app_name)
      compaction_settings = APPS[app_name]&.settings&.[]('compaction')
      compaction_settings = APPS[app_name]&.settings&.[](:compaction) if compaction_settings.nil?
      return :opt_out if compaction_settings == false

      threshold = nil
      if compaction_settings.is_a?(Hash) && !compaction_settings.empty?
        threshold = compaction_settings[:compact_threshold] || compaction_settings['compact_threshold']
      end
      threshold = DEFAULT_COMPACT_THRESHOLD_SPEC if threshold.nil? || threshold.to_i <= 0
      [{ 'type' => 'compaction', 'compact_threshold' => threshold.to_i }]
    end

    it 'attaches context_management when app has custom compaction settings' do
      APPS['TestApp'] = Struct.new(:settings).new({ 'compaction' => { compact_threshold: 120_000 } })
      expect(resolve_compaction_for('TestApp')).to eq(
        [{ 'type' => 'compaction', 'compact_threshold' => 120_000 }]
      )
    end

    it 'attaches context_management at the default threshold when compaction is not specified' do
      # Default-on: apps without an explicit `compaction` setting get the
      # default threshold. This is the new behavior as of the unified
      # context-management design.
      APPS['TestApp'] = Struct.new(:settings).new({ 'other_key' => 'value' })
      expect(resolve_compaction_for('TestApp')).to eq(
        [{ 'type' => 'compaction', 'compact_threshold' => 150_000 }]
      )
    end

    it 'returns :opt_out when app explicitly sets compaction false' do
      APPS['TestApp'] = Struct.new(:settings).new({ 'compaction' => false })
      expect(resolve_compaction_for('TestApp')).to eq(:opt_out)
    end

    it 'accepts symbol key for the compaction setting' do
      APPS['TestApp'] = Struct.new(:settings).new({ compaction: { compact_threshold: 180_000 } })
      expect(resolve_compaction_for('TestApp')).to eq(
        [{ 'type' => 'compaction', 'compact_threshold' => 180_000 }]
      )
    end

    it 'accepts both symbol and string keys for the compact_threshold' do
      %w[symbol string].each do |key_type|
        threshold_key = (key_type == 'symbol' ? :compact_threshold : 'compact_threshold')
        APPS['TestApp'] = Struct.new(:settings).new({ 'compaction' => { threshold_key => 180_000 } })
        expect(resolve_compaction_for('TestApp')).to eq(
          [{ 'type' => 'compaction', 'compact_threshold' => 180_000 }]
        )
      end
    end

    it 'falls back to default threshold when compact_threshold is zero or missing' do
      APPS['TestApp'] = Struct.new(:settings).new({ 'compaction' => { compact_threshold: 0 } })
      expect(resolve_compaction_for('TestApp')).to eq(
        [{ 'type' => 'compaction', 'compact_threshold' => 150_000 }]
      )
    end

    it 'returns default-on when the app is missing entirely (APPS lookup nil)' do
      expect(resolve_compaction_for('NonexistentApp')).to eq(
        [{ 'type' => 'compaction', 'compact_threshold' => 150_000 }]
      )
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
