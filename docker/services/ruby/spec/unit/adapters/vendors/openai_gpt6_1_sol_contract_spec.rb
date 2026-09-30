# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/openai_helper'

# GPT-6.1 Sol (2026-09-29) has GPT-6 Sol's price and limits but cannot turn
# reasoning off: the API lists low..max and answers "none" with a 400
# (probed 2026-09-30). An app, the second opinion agent or an AI user asking
# for "none" must get the lowest level, not a 400 and not the API default
# (medium).
RSpec.describe 'GPT-6.1 Sol request contract' do
  let(:model) { 'gpt-6.1-sol' }
  let(:spec) { Monadic::Utils::ModelSpec }
  let(:helper) { Class.new { include OpenAIHelper }.new }
  let(:tool) { { 'type' => 'function', 'function' => { 'name' => 'noop', 'description' => 'No operation', 'parameters' => { 'type' => 'object', 'properties' => {} } } } }

  before do
    stub_const('APPS', {})
    stub_const('CONFIG', { 'OPENAI_API_KEY' => 'test-key' })
    allow(Monadic::Utils::ExtraLogger).to receive(:log)
    allow(HTTP).to receive(:headers).and_return(double('http'))
  end

  def chat_body(effort)
    obj = { 'reasoning_effort' => effort, 'verbosity' => 'low' }
    caps = helper.send(:resolve_openai_model_capabilities, model, obj, spec.responses_api?(model))
    base = helper.send(:build_openai_base_body, model, obj, nil, caps, 4096, 0.7, 0.5, 0.5)
    base['messages'] = [{ 'role' => 'user', 'content' => 'Hello' }]
    base['tools'] = [tool]
    helper.send(:convert_to_responses_api_body, base, obj, model, {}, 4096, model)
  end

  it 'declares the measured contract, with no "none" level' do
    expect(spec.responses_api?(model)).to be(true)
    expect(spec.get_reasoning_effort_options(model)).to eq(options: %w[low medium high xhigh max], default: 'low')
    expect(spec.get_model_property(model, 'context_window')).to eq([1, 1_050_000])
    expect(spec.get_model_property(model, 'max_output_tokens')).to eq([1, 128_000])
    expect(spec.get_model_property(model, 'verbosity')).to eq([%w[low medium high], 'medium'])
    expect(spec.tool_capability?(model)).to be(true)
    expect(spec.get_model_property(model, 'supports_pdf_upload')).to be(true)
  end

  it 'is the OpenAI chat default, with GPT-6 Sol kept as a choice' do
    expect(spec.default_chat_model('openai')).to eq(model)
    expect(spec.get_provider_models('openai', 'chat')).to include('gpt-6-sol')
  end

  %w[low medium high xhigh max].each do |effort|
    it "sends the listed level #{effort} as is" do
      body = chat_body(effort)
      expect(body.dig('reasoning', 'effort')).to eq(effort)
      expect(body.dig('reasoning', 'summary')).to eq('auto')
      expect(body).not_to have_key('temperature')
    end
  end

  [nil, 'none', 'minimal'].each do |effort|
    it "sends the lowest level for #{effort.inspect} on the chat pipeline" do
      expect(chat_body(effort).dig('reasoning', 'effort')).to eq('low')
    end
  end

  [nil, 'none'].each do |effort|
    it "sends the lowest level for #{effort.inspect} on a simple query (second opinion, AI user)" do
      captured = nil
      allow(helper).to receive(:post_json_with_retries) do |_, uri, body, **|
        expect(uri).to end_with('/responses')
        captured = body
        double(status: double(success?: true),
               body: { 'output' => [{ 'type' => 'message', 'content' => [{ 'type' => 'output_text', 'text' => 'ok' }] }] }.to_json)
      end
      helper.send_query({ 'message' => 'Hello', 'reasoning_effort' => effort, 'temperature' => 0.7 }, model: model)
      expect(captured.dig('reasoning', 'effort')).to eq('low')
      expect(captured).not_to have_key('temperature')
    end
  end

  it 'still sends "none" to GPT-6 Sol, which lists it' do
    obj = { 'reasoning_effort' => 'none' }
    expect(helper.send(:openai_effort_for, 'gpt-6-sol', 'none')).to eq('none')
    expect(helper.send(:openai_effort_for, model, 'none')).to eq('low')
    expect(helper.send(:openai_effort_for, model, 'bogus')).to be_nil
    expect(obj['reasoning_effort']).to eq('none')
  end
end
