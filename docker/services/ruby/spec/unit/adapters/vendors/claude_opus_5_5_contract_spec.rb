# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/claude_helper'

RSpec.describe 'Claude Opus 5.5 request contract' do
  let(:model) { 'claude-opus-5-5' }
  let(:spec) { Monadic::Utils::ModelSpec }
  let(:helper) { Class.new { include ClaudeHelper }.new }

  before do
    tool = { 'name' => 'noop', 'description' => 'No operation',
             'input_schema' => { 'type' => 'object', 'properties' => {} } }
    stub_const('APPS', { 'SpecApp' => Struct.new(:settings).new({ 'tools' => [tool] }) })
    stub_const('CONFIG', { 'ANTHROPIC_API_KEY' => 'test-key' })
    allow(Monadic::Utils::ExtraLogger).to receive(:log)
  end

  def request(effort: 'high', role: 'user', **options)
    obj = { 'model' => model, 'reasoning_effort' => effort }.merge(options.transform_keys(&:to_s))
    config = helper.send(:configure_claude_thinking, obj, model, 4096, 'SpecApp')
    headers, body = helper.send(:build_claude_headers_and_body, model, obj, 'SpecApp',
                                { parameters: {} }, ['Changed system prompt'], config, 0.7, role)
    helper.send(:configure_claude_tools, body, obj, 'SpecApp', { parameters: {} }, role, config[:thinking_enabled], false)
    [headers, JSON.parse(body.to_json)]
  end

  it 'declares the measured adaptive-thinking contract and limits' do
    %w[supports_thinking supports_adaptive_thinking rejects_sampling_params rejects_forced_tool_choice
       thinking_block_binding thinking_display_default_omitted].each do |flag|
      expect(spec.get_model_property(model, flag)).to be(true), flag
    end
    expect(spec.get_model_property(model, 'context_window')).to eq([1, 1_000_000])
    expect(spec.get_model_property(model, 'max_output_tokens')).to eq([[1, 128_000], 128_000])
    expect(spec.get_reasoning_effort_options(model)).to eq(options: %w[low medium high xhigh max], default: 'high')
  end

  it 'preserves the other Opus capabilities and the older catalog entry' do
    %w[vision_capability tool_capability supports_web_search supports_pdf supports_streaming
       supports_context_management structured_output structured_output_mode].each do |flag|
      expect(spec.get_model_property(model, flag)).to eq(spec.get_model_property('claude-opus-5', flag))
    end
    expect(spec.load_spec).to have_key('claude-opus-5')
  end

  %w[low medium high xhigh max].each do |effort|
    %w[user tool].each do |role|
      it "sends only adaptive thinking with #{effort} effort on the #{role} path" do
        headers, body = request(effort: effort, role: role)
        expect(body['thinking']).to eq('type' => 'adaptive', 'display' => 'summarized',
                                      'block_binding' => { 'prefix_mismatch_behavior' => 'drop_block' })
        expect(body['output_config']).to eq('effort' => effort)
        expect(body).not_to have_key('temperature')
        expect(body['thinking']).not_to have_key('budget_tokens')
        expect(headers['anthropic-beta'].split(',')).to include('thinking-binding-controls-2026-08-01')
      end
    end
  end

  it 'preserves the existing three beta headers alongside binding controls' do
    headers, = request
    expect(headers['anthropic-beta'].split(',')).to include(
      'mid-conversation-tool-changes-2026-07-01', 'context-management-2025-06-27',
      'model-context-window-exceeded-2025-08-26', 'thinking-binding-controls-2026-08-01'
    )
  end

  it 'maps a stale minimal effort to low rather than sending a rejected value' do
    _, body = request(effort: 'minimal')
    expect(body['output_config']).to eq('effort' => 'low')
  end

  it 'omits the thinking display when the user hides it' do
    _, body = request(show_thinking: false)
    expect(body['thinking']['display']).to eq('omitted')
  end

  it 'replaces forced tool choice with auto when helper thinking is off' do
    _, body = request(effort: 'none')
    expect(body['tool_choice']).to eq('type' => 'auto')
    expect(body['tools']).not_to be_empty
    expect(body).not_to have_key('temperature')
    expect(body).not_to have_key('output_config')
  end

  [{ effort: nil }, { effort: 'none' }, { effort: 'high', monadic: true }].each do |options|
    %w[user tool].each do |role|
      it "never sends disabled/enabled or an extra effort when thinking is off for #{options.inspect} on #{role}" do
        headers, body = request(**options, role: role)
        expect(body['thinking']).to eq('type' => 'adaptive',
                                      'block_binding' => { 'prefix_mismatch_behavior' => 'drop_block' })
        expect(headers['anthropic-beta'].split(',')).to include('thinking-binding-controls-2026-08-01')
        expect(body.dig('thinking', 'budget_tokens')).to be_nil
        expect(body).not_to have_key('output_config')
        expect(body).not_to have_key('temperature')
      end
    end
  end

  it 'uses the same-contract replacement for Fable 5.1 without changing Fable 5' do
    expect(spec.get_model_property('claude-fable-5-1', 'unavailable_fallback')).to eq(model)
    expect(spec.get_model_property('claude-fable-5', 'unavailable_fallback')).to eq('claude-opus-5')
    expect(spec.get_model_property(model, 'unavailable_fallback')).to be_nil
  end

  ([nil] + %w[low medium high xhigh max none]).each do |effort|
    it "never sends enabled/disabled or sampling parameters on a simple query with #{effort}" do
      allow(HTTP).to receive(:headers).and_return(double('http'))
      captured = nil
      response = double(status: double(success?: true), body: '{"content":[{"type":"text","text":"ok"}]}')
      allow(helper).to receive(:post_json_with_retries) do |_, _, body, **|
        captured = JSON.parse(body.to_json)
        response
      end
      expect(helper.send_query({ 'message' => 'Hello', 'reasoning_effort' => effort, 'temperature' => 0.7 }, model: model)).to eq('ok')
      expect(captured).not_to have_key('temperature')
      expect([nil, 'adaptive']).to include(captured.dig('thinking', 'type'))
      expect(captured.dig('thinking', 'budget_tokens')).to be_nil
      if effort.nil? || effort == 'none'
        expect(captured).not_to have_key('output_config')
      else
        expect(captured['output_config']).to eq('effort' => effort)
      end
    end
  end
end
