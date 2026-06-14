# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/claude_helper'

# Transparent fallback for a temporarily-unavailable model. While Claude
# Fable 5's public access is paused, the Messages API returns 404
# not_found_error pointing to Opus 4.8. execute_claude_api_call detects this
# via the model spec's `unavailable_fallback` field and retries once with the
# fallback model (whose API contract is identical), reusing the body verbatim.
RSpec.describe 'ClaudeHelper model unavailable fallback' do
  subject(:helper) do
    Class.new do
      include ClaudeHelper
    end.new
  end

  def response(code, hash)
    status = double('status', success?: (200..299).cover?(code), code: code)
    double('res', status: status, body: JSON.generate(hash))
  end

  let(:headers) { { 'x-api-key' => 'k', 'anthropic-version' => '2023-06-01' } }
  let(:not_found_body) do
    { 'type' => 'error',
      'error' => { 'type' => 'not_found_error',
                   'message' => 'Claude Fable 5 is not available. Please use Opus 4.8.' } }
  end

  before do
    allow(HTTP).to receive(:headers).and_return(double('http'))
    # Default: privacy disabled, success path returns a sentinel so we can see
    # the call reached process_json_data without exercising the SSE parser.
    allow(helper).to receive(:privacy_enabled_for?).and_return(false)
    allow(helper).to receive(:process_json_data) { |**_| [:processed] }
  end

  def run(body, session)
    helper.send(:execute_claude_api_call, headers, body, 'App', session, 0, false, false) { |_| }
  end

  it 'retries with the spec fallback model when the requested model is not found' do
    calls = []
    allow(helper).to receive(:post_json_with_retries) do |_http, _uri, body, **_|
      calls << body['model']
      body['model'] == 'claude-fable-5' ? response(404, not_found_body) : response(200, { 'content' => [] })
    end

    body = { 'model' => 'claude-fable-5', 'messages' => [], 'max_tokens' => 16 }
    result = run(body, {})

    expect(calls).to eq(['claude-fable-5', 'claude-opus-4-8'])
    expect(body['model']).to eq('claude-opus-4-8') # body reused, only model swapped
    expect(result).to eq([:processed])
  end

  it 'emits a one-time system_info notice naming both models' do
    allow(helper).to receive(:post_json_with_retries) do |_http, _uri, body, **_|
      body['model'] == 'claude-fable-5' ? response(404, not_found_body) : response(200, { 'content' => [] })
    end

    notices = []
    helper.send(:execute_claude_api_call, headers,
                { 'model' => 'claude-fable-5', 'messages' => [], 'max_tokens' => 16 },
                'App', {}, 0, false, false) { |msg| notices << msg }

    info = notices.select { |m| m['type'] == 'system_info' }
    expect(info.size).to eq(1)
    expect(info.first['content']).to include('claude-fable-5').and include('claude-opus-4-8')
  end

  it 'does not recurse when the fallback model itself is not found' do
    calls = []
    allow(helper).to receive(:post_json_with_retries) do |_http, _uri, body, **_|
      calls << body['model']
      response(404, not_found_body) # both models 404
    end

    result = run({ 'model' => 'claude-fable-5', 'messages' => [], 'max_tokens' => 16 }, {})

    # one swap only: fable-5 -> opus-4-8, then give up (opus has no fallback)
    expect(calls).to eq(['claude-fable-5', 'claude-opus-4-8'])
    expect(result.first['type']).to eq('error')
  end

  it 'surfaces the error unchanged for a model without an unavailable_fallback' do
    allow(helper).to receive(:post_json_with_retries).and_return(response(404, not_found_body))

    result = run({ 'model' => 'claude-opus-4-8', 'messages' => [], 'max_tokens' => 16 }, {})

    expect(result.first['type']).to eq('error')
  end

  it 'does not fall back on a non-404 error even if a fallback exists' do
    overloaded = { 'error' => { 'type' => 'overloaded_error', 'message' => 'busy' } }
    calls = []
    allow(helper).to receive(:post_json_with_retries) do |_http, _uri, body, **_|
      calls << body['model']
      response(529, overloaded)
    end

    result = run({ 'model' => 'claude-fable-5', 'messages' => [], 'max_tokens' => 16 }, {})

    expect(calls).to eq(['claude-fable-5']) # no retry
    expect(result.first['type']).to eq('error')
  end
end
