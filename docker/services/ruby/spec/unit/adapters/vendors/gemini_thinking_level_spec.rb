# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/gemini_helper'

# A model with thinking levels and no budget table is asked for its level by
# name; a level the model does not take falls back to its default.
RSpec.describe 'Gemini thinking level' do
  let(:helper) { Class.new { include GeminiHelper }.new }
  let(:model) { 'spec-gemini-levels' }

  before do
    allow(Monadic::Utils::ModelSpec).to receive(:get_thinking_level_options).and_call_original
    allow(Monadic::Utils::ModelSpec).to receive(:get_thinking_level_options)
      .with(model).and_return({ options: %w[low medium high xhigh], default: 'low' })
    allow(Monadic::Utils::ModelSpec).to receive(:get_thinking_budget).and_call_original
    allow(Monadic::Utils::ModelSpec).to receive(:get_thinking_budget).with(model).and_return(nil)
  end

  def thinking_config(reasoning_effort)
    obj = { 'model' => model, 'reasoning_effort' => reasoning_effort }
    caps = helper.send(:resolve_gemini_model_capabilities, obj, model)
    body = helper.send(:build_gemini_request_body,
      obj: obj, model_name: model, session: { parameters: {} }, context: [],
      temperature: nil, max_tokens: 1000, is_thinking_model: caps[:is_thinking_model],
      thinking_level: caps[:thinking_level], reasoning_effort: caps[:reasoning_effort],
      tool_capable: false, system_message: nil)
    body.dig('generationConfig', 'thinkingConfig')
  end

  it 'sends a level the model takes by name' do
    config = thinking_config('xhigh')
    expect(config['thinkingLevel']).to eq('xhigh')
    expect(config).not_to have_key('thinkingBudget')
  end

  it 'sends the default for a level the model does not take' do
    expect(thinking_config('minimal')['thinkingLevel']).to eq('low')
  end

  it 'sends the lowest level for none when thinking cannot be turned off' do
    expect(thinking_config('none')['thinkingLevel']).to eq('low')
  end

  it 'chooses the same level for helper calls' do
    expect(helper.send(:gemini_thinking_level, model, 'high')).to eq('high')
    expect(helper.send(:gemini_thinking_level, model, 'minimal')).to eq('low')
    expect(helper.send(:gemini_thinking_level, model, nil)).to eq('low')
    expect(helper.send(:gemini_thinking_level, 'spec-gemini-no-levels', 'high')).to be_nil
  end
end
