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
    APPS[name] = Struct.new(:settings).new({ 'compaction' => compaction_setting })
  end

  # stub_const, NOT `APPS.clear`: clearing mutated the REAL global that
  # TestAppLoader had populated (and memoization never repopulates), which
  # made later specs in the same run skip with "<App> not loaded" —
  # a seed-dependent pending flake (reproduced with --seed 53864).
  before do
    stub_const('APPS', {})
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

      it 'hides the words of the chat in the compact input before sending' do
        words = Monadic::Utils::Privacy::Words
        session = {}
        Monadic::Workspace::Chats.start_new!(session)
        words.start!(session).confirm!('first', 'PERSON')
        received = nil
        allow(helper).to receive(:request_compaction) do |compact_input, **_|
          received = compact_input
          blob_item('cmp_hidden')
        end

        call(session)
        expect(received.to_s).to include('<<PERSON_1>>')
        expect(received.to_s).not_to include('first')
      ensure
        words::LOCK.synchronize { words::TABLES.clear }
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

  describe 'a chat that hides its words with a word table' do
    let(:words) { Monadic::Utils::Privacy::Words }
    let(:session) { {}.tap { |s| Monadic::Workspace::Chats.start_new!(s) } }
    let(:table) { words.start!(session) }
    let(:model) { 'grok-4.3' }
    let(:input) do
      [sys_item, user_item('Ask Ada Lovelace'), assistant_item('Ada Lovelace answered'), user_item('live')]
    end

    before { table.confirm!('Ada Lovelace', 'PERSON') }
    after { words::LOCK.synchronize { words::TABLES.clear } }

    def call
      helper.apply_grok_compaction(input, session: session, app: 'App', model: model, api_key: 'xai-test')
    end

    context 'above threshold' do
      before { register_app('App', { 'compact_threshold' => 1 }) }

      it 'sends the history to compact with its words hidden, and keeps the words the blob was made with' do
        prior = blob_item('cmp_prior')
        session[:grok_compaction] = { 'blob' => prior, 'covered_count' => 0, 'model' => model, 'app' => 'App',
                                      'threshold' => 1, 'words' => table.revision }
        received = nil
        allow(helper).to receive(:request_compaction) do |compact_input, **_|
          received = compact_input
          blob_item('cmp_new')
        end

        expect(call.first).to eq(blob_item('cmp_new'))
        expect(received).to eq([prior, user_item('Ask <<PERSON_1>>'), assistant_item('<<PERSON_1>> answered')])
        expect(session[:grok_compaction]['words']).to eq(table.revision)
      end

      it 'does not fold in a blob made before the words changed' do
        session[:grok_compaction] = { 'blob' => blob_item('cmp_prior'), 'covered_count' => 0, 'model' => model,
                                      'app' => 'App', 'threshold' => 1, 'words' => table.revision }
        allow(helper).to receive(:validated_compaction_cache).and_wrap_original do |original, *args|
          original.call(*args).tap { table.confirm!('Grace Hopper', 'PERSON') }
        end
        expect(helper).not_to receive(:request_compaction)

        expect(call).to eq(input)
        expect(session).not_to have_key(:grok_compaction)
      end

      it 'sends nothing to compact once the words change while it is being sent' do
        allow(helper).to receive(:request_compaction) do
          table.confirm!('Grace Hopper', 'PERSON')
          words.check_sending!
          blob_item('cmp_late')
        end

        expect(call).to eq(input)
        expect(session).not_to have_key(:grok_compaction)
      end
    end

    it 'makes the blob again once the words to hide have changed' do
      register_app('App', { 'compact_threshold' => 100_000 })
      session[:grok_compaction] = { 'blob' => blob_item, 'covered_count' => 2, 'model' => model, 'app' => 'App',
                                    'threshold' => 100_000, 'words' => table.revision }
      expect(call.first).to eq(blob_item)

      table.confirm!('Grace Hopper', 'PERSON')
      expect(call).to eq(input)
      expect(session).not_to have_key(:grok_compaction)
    end

    it 'does not send a blob made with other words than the request is hidden with' do
      session[:grok_compaction] = { 'blob' => blob_item, 'covered_count' => 2, 'model' => model, 'app' => 'App',
                                    'threshold' => 1, 'words' => table.revision }
      body = { 'input' => [blob_item, sys_item, user_item('live')] }
      expect { helper.compacted_with_other_words!(body, session, table.snapshot) }.not_to raise_error

      table.confirm!('Grace Hopper', 'PERSON')
      expect { helper.compacted_with_other_words!(body, session, table.snapshot) }
        .to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
      expect(session).not_to have_key(:grok_compaction)
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
