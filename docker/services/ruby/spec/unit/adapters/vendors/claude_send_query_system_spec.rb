# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/claude_helper'

# The Messages API takes the system prompt as a top-level field and only user
# and assistant turns in messages.
RSpec.describe 'ClaudeHelper#send_query system message' do
  let(:helper) { Class.new { include ClaudeHelper }.new }

  before do
    stub_const('CONFIG', { 'ANTHROPIC_API_KEY' => 'test-key' })
    allow(Monadic::Utils::ExtraLogger).to receive(:log)
  end

  def capture_body(options)
    captured = nil
    response = double('res', status: double('status', success?: true),
                             body: JSON.generate('content' => [{ 'type' => 'text', 'text' => 'ok' }]))
    allow(helper).to receive(:post_json_with_retries) { |_http, _uri, body, **| captured = body; response }
    helper.send_query(options, model: 'claude-sonnet-5-5')
    captured
  end

  it 'sends a system message given among the messages as the system field' do
    body = capture_body('messages' => [{ 'role' => 'system', 'content' => 'Be brief.' },
                                       { 'role' => 'user', 'content' => 'Hi' }])
    expect(body['system']).to eq('Be brief.')
    expect(body['messages'].map { |m| m['role'] }).to eq(['user'])
  end

  it 'keeps a system field given as such' do
    body = capture_body('system' => 'Given.', 'messages' => [{ 'role' => 'user', 'content' => 'Hi' }])
    expect(body['system']).to eq('Given.')
  end
end
