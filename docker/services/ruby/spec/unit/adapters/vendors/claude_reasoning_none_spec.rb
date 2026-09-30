# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/claude_helper'

# Reasoning effort "none" asks for as little reasoning as possible. Which
# request expresses that depends on the model: where omitting `thinking` means
# no thinking (Opus 4.8 and earlier), leaving it out is correct; where the API
# thinks whenever `thinking` is omitted (thinking_on_by_default), leaving it
# out ran the model's default effort, so "none" became more reasoning than
# "low". Those models get the lowest effort they offer instead.
RSpec.describe 'Claude reasoning effort "none"' do
  let(:spec) { Monadic::Utils::ModelSpec }
  let(:helper) { Class.new { include ClaudeHelper }.new }

  before do
    tool = { 'name' => 'noop', 'description' => 'No operation',
             'input_schema' => { 'type' => 'object', 'properties' => {} } }
    stub_const('APPS', { 'SpecApp' => Struct.new(:settings).new({ 'tools' => [tool] }) })
    stub_const('CONFIG', { 'ANTHROPIC_API_KEY' => 'test-key' })
    allow(Monadic::Utils::ExtraLogger).to receive(:log)
  end

  def request(model, effort)
    obj = { 'model' => model, 'reasoning_effort' => effort }
    config = helper.send(:configure_claude_thinking, obj, model, 4096, 'SpecApp')
    _, body = helper.send(:build_claude_headers_and_body, model, obj, 'SpecApp',
                          { parameters: {} }, ['System prompt'], config, 0.7, 'user')
    JSON.parse(body.to_json)
  end

  def claude_models
    spec.load_spec.keys.select { |m| m.start_with?('claude-') }
  end

  it 'marks exactly the models whose API thinks when thinking is omitted' do
    flagged = claude_models.select { |m| spec.thinking_on_by_default?(m) }
    expect(flagged).to contain_exactly('claude-fable-5-1', 'claude-fable-5', 'claude-opus-5-5',
                                       'claude-opus-5', 'claude-sonnet-5-5', 'claude-sonnet-5')
    # The flag only makes sense on adaptive-thinking models with an effort list.
    flagged.each do |m|
      expect(spec.supports_adaptive_thinking?(m)).to be(true), m
      expect(spec.get_reasoning_effort_options(m)&.dig(:options)).not_to be_empty, m
    end
  end

  it 'sends the lowest listed effort for "none" on every always-thinking model' do
    claude_models.select { |m| spec.thinking_on_by_default?(m) }.each do |model|
      body = request(model, 'none')
      lowest = spec.get_reasoning_effort_options(model)[:options].first
      expect(body.dig('thinking', 'type')).to eq('adaptive'), model
      expect(body['output_config']).to eq({ 'effort' => lowest }), model
      expect(body.dig('thinking', 'budget_tokens')).to be_nil
      # block_binding goes with the models that bind thinking blocks, and is
      # the reason between_tools (which cannot carry it) is not used.
      expect(body.dig('thinking', 'block_binding').nil?).to eq(!spec.thinking_block_binding?(model)), model
    end
  end

  it 'still leaves thinking out for "none" where that means no thinking' do
    claude_models.select { |m| spec.supports_adaptive_thinking?(m) && !spec.thinking_on_by_default?(m) }.each do |model|
      body = request(model, 'none')
      expect(body).not_to have_key('thinking'), model
      expect(body).not_to have_key('output_config'), model
    end
  end

  it "leaves an unspecified effort to the model's default everywhere" do
    claude_models.select { |m| spec.supports_adaptive_thinking?(m) }.each do |model|
      body = request(model, nil)
      expect(body).not_to have_key('output_config'), model
    end
  end
end
