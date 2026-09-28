# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/openai_helper'

RSpec.describe 'GPT-6 Sol and Luna request contract' do
  let(:spec) { Monadic::Utils::ModelSpec }
  let(:helper) { Class.new { include OpenAIHelper }.new }
  let(:tool) { { 'type' => 'function', 'function' => { 'name' => 'noop', 'description' => 'No operation', 'parameters' => { 'type' => 'object', 'properties' => {} } } } }

  before do
    stub_const('APPS', {})
    stub_const('CONFIG', { 'OPENAI_API_KEY' => 'test-key' })
    allow(Monadic::Utils::ExtraLogger).to receive(:log)
    allow(HTTP).to receive(:headers).and_return(double('http'))
  end

  %w[gpt-6-sol gpt-6-luna].each do |model|
    context model do
      it 'declares Responses, supported effort levels, verbosity and measured limits' do
        expect(spec.responses_api?(model)).to be(true)
        expect(spec.get_reasoning_effort_options(model)).to eq(options: %w[none low medium high xhigh max], default: 'none')
        expect(spec.get_model_property(model, 'context_window')).to eq([1, 1_050_000])
        expect(spec.get_model_property(model, 'max_output_tokens')).to eq([1, 128_000])
        expect(spec.get_model_property(model, 'verbosity')).to eq([%w[low medium high], 'medium'])
        expect(spec.tool_capability?(model)).to be(true)
      end

      [nil, 'none', 'low', 'medium', 'high', 'xhigh', 'max'].each do |effort|
        it "sends #{effort.inspect} effort correctly through the chat body pipeline" do
          obj = { 'reasoning_effort' => effort, 'verbosity' => 'low' }
          caps = helper.send(:resolve_openai_model_capabilities, model, obj, spec.responses_api?(model))
          base = helper.send(:build_openai_base_body, model, obj, nil, caps, 4096, 0.7, 0.5, 0.5)
          base['messages'] = [{ 'role' => 'user', 'content' => 'Hello' }]
          base['tools'] = [tool]
          body = helper.send(:convert_to_responses_api_body, base, obj, model, {}, 4096, model)
          expect(body.dig('reasoning', 'effort')).to eq(effort || 'none')
          expect(body.dig('reasoning', 'summary')).to eq(effort.nil? || effort == 'none' ? nil : 'auto')
          expect(body).not_to have_key('temperature')
          expect(body).not_to have_key('top_p')
          expect(body['tools'].first).to include('type' => 'function', 'name' => 'noop')
          expect(body['max_output_tokens']).to eq(4096)
          expect(body['text']).to eq('verbosity' => 'low')
        end
      end

      [nil, 'none', 'high'].each do |effort|
        it "routes a simple tool query to Responses with #{effort.inspect} effort and parses its result" do
          captured = nil
          response_body = { 'output' => [
            { 'type' => 'message', 'content' => [{ 'type' => 'output_text', 'text' => 'Hello' }] },
            { 'type' => 'function_call', 'name' => 'noop', 'arguments' => '{}' }
          ] }
          allow(helper).to receive(:post_json_with_retries) do |_, uri, body, **|
            expect(uri).to end_with('/responses')
            captured = body
            double(status: double(success?: true), body: response_body.to_json)
          end
          result = helper.send_query({ 'message' => 'Hello', 'reasoning_effort' => effort, 'temperature' => 0.7,
                                       'tools' => [tool], 'verbosity' => 'low', 'max_tokens' => 4096 }, model: model)
          expect(result).to eq(text: 'Hello', tool_calls: [{ 'name' => 'noop', 'args' => {} }])
          expect(captured.dig('reasoning', 'effort')).to eq(effort || 'none')
          expect(captured).not_to have_key('temperature')
          expect(captured['tools'].first).to include('name' => 'noop')
          expect(captured['max_output_tokens']).to eq(4096)
          expect(captured['text']).to eq('verbosity' => 'low')
        end
      end

      ['json_object', 'json_schema'].each do |format_type|
        it "preserves simple-query #{format_type} output on Responses" do
          format = { 'type' => format_type }
          schema = { 'name' => 'answer', 'schema' => { 'type' => 'object', 'properties' => {} }, 'strict' => true }
          format['json_schema'] = schema if format_type == 'json_schema'
          allow(helper).to receive(:post_json_with_retries) do |_, uri, body, **|
            expect(uri).to end_with('/responses')
            expect(body.dig('text', 'format')).to eq(format_type == 'json_schema' ? { 'type' => format_type }.merge(schema) : format)
            double(status: double(success?: true), body: '{"output":[{"type":"message","content":[{"type":"output_text","text":"{}"}]}]}')
          end
          expect(helper.send_query({ 'message' => 'Return JSON', 'response_format' => format }, model: model)).to eq('{}')
        end
      end
    end
  end

  it 'changes chat and vision defaults while preserving old choices and the code default' do
    expect(spec.default_chat_model('openai')).to eq('gpt-6-sol')
    expect(spec.get_provider_models('openai', 'chat').take(2)).to eq(%w[gpt-6-sol gpt-6-luna])
    expect(spec.get_provider_models('openai', 'chat')).to include('gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna')
    expect(spec.default_vision_model('openai')).to eq('gpt-6-luna')
    expect(spec.get_provider_models('openai', 'vision')).to include('gpt-5.6-luna')
    expect(spec.default_code_model('openai')).to eq('gpt-5.3-codex')
  end

  it 'preserves Chat Completions for models whose SSOT does not request Responses' do
    allow(helper).to receive(:post_json_with_retries) do |_, uri, body, **|
      expect(uri).to end_with('/chat/completions')
      expect(body['temperature']).to eq(0.7)
      double(status: double(success?: true), body: '{"choices":[{"message":{"content":"ok"}}]}')
    end
    expect(helper.send_query({ 'message' => 'Hello', 'temperature' => 0.7 }, model: 'gpt-4.1')).to eq('ok')
  end
end
