# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/grok_helper'

# Unit coverage for the xAI Context Compaction orchestration mixed into
# GrokHelper. The compact HTTP call is stubbed; these specs pin the decision
# logic, the [blob, system, tail] input rebuild, the cache invalidation matrix,
# and the degrade-to-full-history failure contract.
RSpec.describe GrokCompaction do
  subject(:helper) do
    Class.new do
      include GrokHelper
    end.new
  end

  # Converted Responses API items (output shape of convert_messages_to_input).
  def sys_item(text = 'system prompt')
    { 'role' => 'system', 'content' => [{ 'type' => 'input_text', 'text' => text }] }
  end

  def user_item(text)
    { 'role' => 'user', 'content' => [{ 'type' => 'input_text', 'text' => text }] }
  end

  def assistant_item(text)
    { 'role' => 'assistant', 'content' => [{ 'type' => 'output_text', 'text' => text }] }
  end

  def blob_item(id = 'cmp_test')
    { 'type' => 'compaction', 'id' => id, 'encrypted_content' => 'OPAQUE' }
  end

  # Register a fake app exposing settings["compaction"].
  def register_app(name, compaction_setting)
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
    APPS[name] = Struct.new(:settings).new({ 'compaction' => compaction_setting })
  end

  before do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
    APPS.clear
  end

  describe '#grok_compaction_threshold' do
    it 'returns the configured threshold' do
      register_app('App', { 'compact_threshold' => 120_000 })
      expect(helper.grok_compaction_threshold('App')).to eq(120_000)
    end

    it 'returns :disabled for the opt-out sentinel' do
      register_app('App', false)
      expect(helper.grok_compaction_threshold('App')).to eq(:disabled)
    end

    it 'returns nil when the app declares no compaction' do
      Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
      APPS['App'] = Struct.new(:settings).new({})
      expect(helper.grok_compaction_threshold('App')).to be_nil
    end

    it 'falls back to the default threshold for a hash without compact_threshold' do
      register_app('App', {})
      expect(helper.grok_compaction_threshold('App'))
        .to eq(MonadicDSL::CompactionConfiguration::DEFAULT_COMPACT_THRESHOLD)
    end
  end

  describe '#apply_grok_compaction' do
    let(:model) { 'grok-4.3' }
    let(:api_key) { 'xai-test' }
    # [sys, u1, a1, u2] -> convo [u1, a1, u2], live turn = u2
    let(:input) { [sys_item, user_item('first'), assistant_item('reply'), user_item('live')] }

    def call(session)
      helper.apply_grok_compaction(input, session: session, app: 'App', model: model, api_key: api_key)
    end

    it 'returns input unchanged when compaction is disabled' do
      register_app('App', false)
      session = {}
      expect(call(session)).to eq(input)
    end

    it 'returns input unchanged when the app declares no compaction' do
      Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
      APPS['App'] = Struct.new(:settings).new({})
      expect(call({})).to eq(input)
    end

    it 'is a no-op while orchestration-history pruning is active' do
      register_app('App', { 'compact_threshold' => 1 })
      helper.instance_variable_set(:@clear_orchestration_history, true)
      expect(helper).not_to receive(:request_compaction)
      expect(call({})).to eq(input)
    end

    context 'below threshold' do
      before { register_app('App', { 'compact_threshold' => 100_000 }) }

      it 'sends the full history unchanged when there is no cache' do
        expect(helper).not_to receive(:request_compaction)
        expect(call({})).to eq(input)
      end

      it 'reuses an existing valid blob as [blob, system, tail]' do
        session = { grok_compaction: { 'blob' => blob_item, 'covered_count' => 2,
                                       'model' => model, 'app' => 'App', 'threshold' => 100_000 } }
        result = call(session)
        expect(result.first).to eq(blob_item)
        expect(result[1]).to eq(sys_item)
        expect(result[2..]).to eq([user_item('live')])
      end
    end

    context 'above threshold' do
      before do
        register_app('App', { 'compact_threshold' => 1 })
        allow(helper).to receive(:request_compaction).and_return(blob_item('cmp_new'))
      end

      it 'compacts the pre-turn history and rebuilds input as [blob, system, live_tail]' do
        session = {}
        result = call(session)
        expect(result.first).to eq(blob_item('cmp_new'))
        expect(result[1]).to eq(sys_item)
        expect(result[2..]).to eq([user_item('live')])
      end

      it 'caches the blob with coverage, model, app and threshold' do
        session = {}
        call(session)
        cache = session[:grok_compaction]
        expect(cache['blob']).to eq(blob_item('cmp_new'))
        expect(cache['covered_count']).to eq(2)
        expect(cache['model']).to eq(model)
        expect(cache['app']).to eq('App')
        expect(cache['threshold']).to eq(1)
      end

      it 'only sends the uncovered pending slice to the compact endpoint when a blob exists' do
        prior = blob_item('cmp_prior')
        session = { grok_compaction: { 'blob' => prior, 'covered_count' => 1,
                                       'model' => model, 'app' => 'App', 'threshold' => 1 } }
        # covered=1 -> pending = convo[1...2] = [a1]; folds prior blob + [a1]
        expect(helper).to receive(:request_compaction) do |compact_input, **_|
          expect(compact_input.first).to eq(prior)
          expect(compact_input[1..]).to eq([assistant_item('reply')])
          blob_item('cmp_refreshed')
        end
        call(session)
      end

      it 'masks the compact input through the privacy pipeline before sending' do
        # No production app enables both privacy and compaction today, so this
        # fail-safe path is unreachable by dogfood. Pin the wiring here: when
        # privacy is on, the slice handed to the compact endpoint must be masked
        # with the same apply_privacy_to_messages used on the main request.
        allow(helper).to receive(:privacy_enabled_for?).and_return(true)
        allow(helper).to receive(:apply_privacy_to_messages) do |messages, _session, _settings|
          messages.map { |m| m.merge('masked' => true) }
        end
        received = nil
        allow(helper).to receive(:request_compaction) do |compact_input, **_|
          received = compact_input
          blob_item('cmp_masked')
        end

        call({})
        expect(received).to all(include('masked' => true))
      end

      it 'degrades to full history and clears the cache when compaction fails' do
        allow(helper).to receive(:request_compaction).and_return(nil)
        # covered_count=1 leaves a non-empty pending slice ([a1]) so a compact
        # call is actually attempted (and fails).
        session = { grok_compaction: { 'blob' => blob_item, 'covered_count' => 1,
                                       'model' => model, 'app' => 'App', 'threshold' => 1 } }
        expect(call(session)).to eq(input)
        expect(session).not_to have_key(:grok_compaction)
      end
    end

    context 'invalidation matrix' do
      before do
        register_app('App', { 'compact_threshold' => 100_000 })
      end

      it 'discards a cache created with a different model' do
        session = { grok_compaction: { 'blob' => blob_item, 'covered_count' => 2,
                                       'model' => 'grok-4.20-0309-non-reasoning',
                                       'app' => 'App', 'threshold' => 100_000 } }
        # Stale model -> cache dropped -> below threshold -> full history.
        expect(call(session)).to eq(input)
        expect(session).not_to have_key(:grok_compaction)
      end

      it 'discards a cache created for a different app' do
        session = { grok_compaction: { 'blob' => blob_item, 'covered_count' => 2,
                                       'model' => model, 'app' => 'OtherApp', 'threshold' => 100_000 } }
        expect(call(session)).to eq(input)
        expect(session).not_to have_key(:grok_compaction)
      end

      it 'discards a cache created with a different threshold' do
        session = { grok_compaction: { 'blob' => blob_item, 'covered_count' => 2,
                                       'model' => model, 'app' => 'App', 'threshold' => 999 } }
        expect(call(session)).to eq(input)
        expect(session).not_to have_key(:grok_compaction)
      end
    end
  end

  describe '#request_compaction (HTTP contract)' do
    let(:compact_input) { [{ 'role' => 'user', 'content' => 'hi' }] }

    def fake_response(code, body)
      status = double('status', success?: (200..299).cover?(code), code: code, nil?: false)
      double('response', status: status, body: body)
    end

    before do
      allow(HTTP).to receive(:headers).and_return(double('http'))
    end

    it 'returns the compaction item on HTTP 200' do
      body = JSON.generate('output' => [blob_item('cmp_ok')])
      allow(helper).to receive(:post_json_with_retries).and_return(fake_response(200, body))
      item = helper.send(:request_compaction, compact_input, model: 'grok-4.3', api_key: 'k')
      expect(item).to eq(blob_item('cmp_ok'))
    end

    it 'returns nil on the decrypt-error 400' do
      body = JSON.generate('code' => 'invalid-argument',
                           'error' => 'Could not decrypt the provided encrypted_content.')
      allow(helper).to receive(:post_json_with_retries).and_return(fake_response(400, body))
      expect(helper.send(:request_compaction, compact_input, model: 'grok-4.3', api_key: 'k')).to be_nil
    end

    it 'returns nil when the response has no compaction item' do
      body = JSON.generate('output' => [{ 'type' => 'message' }])
      allow(helper).to receive(:post_json_with_retries).and_return(fake_response(200, body))
      expect(helper.send(:request_compaction, compact_input, model: 'grok-4.3', api_key: 'k')).to be_nil
    end
  end
end
