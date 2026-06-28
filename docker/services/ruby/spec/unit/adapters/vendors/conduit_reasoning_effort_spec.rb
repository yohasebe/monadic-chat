# frozen_string_literal: true

require 'spec_helper'

# The Conduit simple-query path (send_query) must honor reasoning_effort for the
# providers whose APIs expose it. These tests stub the HTTP layer
# (post_json_with_retries) and assert the request body the helper builds.
RSpec.describe 'send_query reasoning_effort wiring (Conduit path)' do
  def ok_response
    status = double('status', success?: true, code: 200)
    double('res', status: status, body: JSON.generate('content' => [{ 'type' => 'text', 'text' => 'ok' }]))
  end

  describe 'ClaudeHelper' do
    let(:helper) { Class.new { include ClaudeHelper }.new }
    before { allow(HTTP).to receive(:headers).and_return(double('http')) }

    def capture_body(opts, model)
      captured = nil
      allow(helper).to receive(:post_json_with_retries) { |_h, _u, body, **| captured = body; ok_response }
      helper.send_query(opts, model: model) rescue nil
      captured
    end

    it 'maps reasoning_effort to output_config.effort for an adaptive model and drops temperature' do
      body = capture_body(
        { 'messages' => [{ 'role' => 'user', 'content' => 'hi' }], 'max_tokens' => 20000, 'reasoning_effort' => 'high' },
        'claude-opus-4-8'
      )
      expect(body['output_config'] || body['thinking']).not_to be_nil
      expect(body).not_to have_key('temperature')
    end

    it 'does not enable thinking when reasoning_effort is none' do
      body = capture_body(
        { 'messages' => [{ 'role' => 'user', 'content' => 'hi' }], 'max_tokens' => 20000, 'reasoning_effort' => 'none' },
        'claude-opus-4-8'
      )
      expect(body['output_config']).to be_nil
      expect(body['thinking']).to be_nil
    end
  end

  describe 'GrokHelper' do
    let(:helper) { Class.new { include GrokHelper }.new }
    before { allow(HTTP).to receive(:headers).and_return(double('http')) }

    def capture_body(opts, model)
      captured = nil
      allow(helper).to receive(:post_json_with_retries) { |_h, _u, body, **| captured = body; ok_response }
      helper.send_query(opts, model: model) rescue nil
      captured
    end

    it 'sets nested reasoning.effort for a model that supports it (grok-4.3)' do
      body = capture_body(
        { 'messages' => [{ 'role' => 'user', 'content' => 'hi' }], 'max_tokens' => 100, 'reasoning_effort' => 'low' },
        'grok-4.3'
      )
      expect(body['reasoning']).to eq('effort' => 'low')
    end

    it 'omits reasoning for a model that does not expose reasoning_effort' do
      body = capture_body(
        { 'messages' => [{ 'role' => 'user', 'content' => 'hi' }], 'max_tokens' => 100, 'reasoning_effort' => 'low' },
        'grok-4.20-0309-reasoning'
      )
      expect(body).not_to have_key('reasoning')
    end
  end
end
