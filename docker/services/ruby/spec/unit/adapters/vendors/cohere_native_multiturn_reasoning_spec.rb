# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/cohere_helper'

# North Mini Code handles the native Cohere v2 multi-turn tool flow with
# reasoning on (verified against the live API), so it must skip the single-text
# flattening that configure_cohere_reasoning applies to command-a-reasoning.
# The opt-out is the model_spec flag `native_multiturn_reasoning`.
RSpec.describe 'CohereHelper native_multiturn_reasoning bypass' do
  subject(:helper) do
    Class.new do
      include CohereHelper
    end.new
  end

  let(:history) do
    [
      { 'role' => 'user', 'content' => 'What is 47*53? Use the calculator.' },
      { 'role' => 'assistant', 'tool_calls' => [{ 'id' => 'c1', 'type' => 'function',
                                                  'function' => { 'name' => 'calculator', 'arguments' => '{"expression":"47*53"}' } }] },
      { 'role' => 'tool', 'tool_call_id' => 'c1', 'content' => '2491' },
      { 'role' => 'user', 'content' => 'Now double it.' }
    ]
  end

  def configure(model, messages)
    body = { 'model' => model, 'messages' => messages }
    obj = { 'model' => model, 'reasoning_effort' => 'enabled' }
    helper.send(:configure_cohere_reasoning, body, messages, obj, {})
    body
  end

  it 'keeps the native multi-turn message array for a native_multiturn_reasoning model' do
    body = configure('north-mini-code-1-0', history)
    # No flattening: the original 4-message array is preserved as-is.
    expect(body['messages'].size).to eq(4)
    expect(body['messages']).to eq(history)
    expect(body['thinking']).to eq({ 'type' => 'enabled' })
  end

  it 'still flattens to single text for command-a-reasoning (workaround retained)' do
    body = configure('command-a-reasoning-08-2025', history)
    # Flattened: collapsed into one user message.
    expect(body['messages'].size).to eq(1)
    expect(body['messages'].first['role']).to eq('user')
    expect(body['thinking']).to eq({ 'type' => 'enabled' })
  end

  it 'disables thinking for both models when reasoning_effort is disabled' do
    %w[north-mini-code-1-0 command-a-reasoning-08-2025].each do |model|
      body = { 'model' => model, 'messages' => history }
      obj = { 'model' => model, 'reasoning_effort' => 'disabled' }
      helper.send(:configure_cohere_reasoning, body, history, obj, {})
      expect(body['thinking']).to eq({ 'type' => 'disabled' })
      expect(body['messages']).to eq(history) # no flattening when disabled
    end
  end
end
