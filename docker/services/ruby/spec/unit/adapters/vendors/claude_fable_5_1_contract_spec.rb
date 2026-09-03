# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/claude_helper'

# Claude Fable 5.1 rejects forced tool choice, and rejects a replayed thinking
# block whose prefix changed. Both are driven by flags in model_spec.js, which
# documents them; these examples pin the helper's side.
RSpec.describe 'Claude Fable 5.1 request contract' do
  FABLE_5_1 = 'claude-fable-5-1'
  FABLE_5 = 'claude-fable-5'
  OPUS_5 = 'claude-opus-5'
  BINDING_BETA = 'thinking-binding-controls-2026-08-01'

  let(:helper) do
    Class.new do
      include ClaudeHelper

      def pub_headers_and_body(model, thinking_config)
        send(:build_claude_headers_and_body,
             model, { 'model' => model }, 'SpecApp', { parameters: {} }, [],
             thinking_config, nil, 'user')
      end

      # Drive the tool_choice branch the way a tool-capable, non-thinking
      # request reaches it (monadic structured outputs or effort "none").
      # The tools come from the app's settings, as in production; a
      # pre-set body["tools"] would be rebuilt from there and discarded.
      def pub_tool_choice(model)
        body = { 'model' => model }
        send(:configure_claude_tools, body, { 'model' => model }, 'SpecApp', { parameters: {} }, 'user', false, false)
        body['tool_choice']
      end
    end.new
  end

  before do
    noop_tool = { 'name' => 'noop', 'description' => 'Does nothing.',
                  'input_schema' => { 'type' => 'object', 'properties' => {} } }
    stub_const('APPS', { 'SpecApp' => Struct.new(:settings).new({ 'tools' => [noop_tool] }) })
    allow(CONFIG).to receive(:[]).and_call_original
    allow(CONFIG).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
  end

  describe 'forced tool choice' do
    it 'never sends "any" to a model that rejects forced tool choice' do
      expect(helper.pub_tool_choice(FABLE_5_1)).to eq({ 'type' => 'auto' })
    end

    it 'still sends "any" to Fable 5, which accepts it (control)' do
      expect(helper.pub_tool_choice(FABLE_5)).to eq({ 'type' => 'any' })
    end
  end

  describe 'thinking block binding' do
    let(:thinking_on) { { thinking_enabled: true, adaptive_effort: 'high', max_tokens: 4096 } }
    let(:thinking_off) { { thinking_enabled: false, max_tokens: 4096 } }

    it 'opts Fable 5.1 into drop_block under the binding beta' do
      headers, body = helper.pub_headers_and_body(FABLE_5_1, thinking_on)

      expect(headers['anthropic-beta'].split(',')).to include(BINDING_BETA)
      expect(body['thinking']['block_binding']).to eq({ 'prefix_mismatch_behavior' => 'drop_block' })
    end

    it 'still sends the binding object when the helper has thinking off' do
      # Thinking is always on for these models, so the object must ride on an
      # adaptive thinking param even when the helper omitted one.
      _headers, body = helper.pub_headers_and_body(FABLE_5_1, thinking_off)

      expect(body['thinking']).to include('block_binding' => { 'prefix_mismatch_behavior' => 'drop_block' })
      expect(body['thinking'][:type] || body['thinking']['type']).to eq('adaptive')
    end

    [FABLE_5, OPUS_5].each do |model|
      it "sends neither the beta nor the object for #{model}" do
        headers, body = helper.pub_headers_and_body(model, thinking_on)

        expect((headers['anthropic-beta'] || '').split(',')).not_to include(BINDING_BETA)
        expect(body['thinking']).not_to have_key('block_binding')
      end
    end
  end

  describe 'input_transformations logging' do
    it 'logs each dropped block with its path and reason' do
      logged = nil
      allow(Monadic::Utils::ExtraLogger).to receive(:log) { |&blk| logged = blk.call }

      helper.send(:log_claude_input_transformations,
                  [{ 'type' => 'thinking_dropped', 'path' => 'messages.1.content.0', 'reason' => 'prefix_binding_mismatch' }])

      expect(logged).to include('thinking_dropped at messages.1.content.0 (prefix_binding_mismatch)')
    end

    it 'stays silent for an empty array and for an absent field' do
      expect(Monadic::Utils::ExtraLogger).not_to receive(:log)

      helper.send(:log_claude_input_transformations, [])
      helper.send(:log_claude_input_transformations, nil)
    end
  end

  describe 'SSOT consistency' do
    it 'declares the binding flag only on models that think adaptively' do
      # The helper adds {type: "adaptive"} when it opts a model into
      # drop_block, which a non-adaptive model would reject.
      Monadic::Utils::ModelSpec.load_spec.each do |model, props|
        next unless props.is_a?(Hash) && props['thinking_block_binding'] == true

        expect(props['supports_adaptive_thinking']).to eq(true),
          "#{model} declares thinking_block_binding without supports_adaptive_thinking"
      end
    end
  end
end
