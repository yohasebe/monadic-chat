# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/utils/websocket/verify_handler'

# Behaviour tests for the confidence-via-agreement Verify WebSocket handler.
# We mix WebSocketHelper into a host, stub the transport + the Conduit call, and
# run the background thread synchronously so we can assert the contract:
#   - guards (message not found / not assistant / no preceding user turn)
#   - the panel context built for the panel (prior turns, NOT the reviewed
#     answer, NOT the system prompt)
#   - persistence (slimmed verdict written onto the message)
RSpec.describe 'WebSocketHelper Verify handler' do
  let(:host) do
    Class.new {
      include WebSocketHelper

      def self.sent
        @sent ||= []
      end

      def send_to_client(_conn, payload)
        self.class.sent << payload
      end

      def send_or_broadcast(json, _sid = nil)
        self.class.sent << JSON.parse(json)
      end

      def sync_session_state!; end
    }.new
  end

  let(:sent) { host.class.sent }
  let(:connection) { instance_double('Connection') }

  let(:messages) do
    [
      { 'role' => 'system', 'text' => 'You are a vet.', 'mid' => 's0', 'app_name' => 'ChatOpenAI', 'active' => true },
      { 'role' => 'user', 'text' => 'How long do puppies sleep?', 'mid' => 'u1', 'app_name' => 'ChatOpenAI', 'active' => true },
      { 'role' => 'assistant', 'text' => 'About 18-20 hours.', 'mid' => 'a1', 'app_name' => 'ChatOpenAI', 'active' => true }
    ]
  end

  let(:conduit_result) do
    { confidence: 'high', score: 0.9, consensus: '18h', disagreements: [],
      responses: [{ provider: 'openai', model: 'm', success: true, text: 'x', usage: { a: 1 }, index: 0 }],
      budget: { spent: 1 } }
  end

  before do
    host.class.sent.clear
    Thread.current[:rack_session] = { messages: messages }
    Thread.current[:websocket_session_id] = 'sid-1'
    stub_const('Monadic::MCP::Conduit', double('Conduit'))
    allow(Monadic::MCP::Conduit).to receive(:call).and_return(conduit_result)
    # Run the background thread synchronously.
    allow(Thread).to receive(:new) { |&blk| blk.call; instance_double(Thread, join: nil) }
  end

  after do
    Thread.current[:rack_session] = nil
    Thread.current[:websocket_session_id] = nil
  end

  it 'errors when the message id is not found' do
    host.handle_ws_verify_confidence(connection, { 'mid' => 'nope' }, {})
    expect(sent.last['confidence']).to eq('unavailable')
    expect(Monadic::MCP::Conduit).not_to have_received(:call)
  end

  it 'errors when the target is not an assistant message' do
    host.handle_ws_verify_confidence(connection, { 'mid' => 'u1' }, {})
    expect(sent.last['confidence']).to eq('unavailable')
    expect(Monadic::MCP::Conduit).not_to have_received(:call)
  end

  it 'errors when there is no preceding user question' do
    Thread.current[:rack_session] = {
      messages: [{ 'role' => 'assistant', 'text' => 'orphan', 'mid' => 'a9', 'app_name' => 'ChatOpenAI', 'active' => true }]
    }
    host.handle_ws_verify_confidence(connection, { 'mid' => 'a9' }, {})
    expect(sent.last['note']).to match(/No preceding user question/)
    expect(Monadic::MCP::Conduit).not_to have_received(:call)
  end

  it 'passes prior context to the panel, excluding the reviewed answer and the system prompt' do
    host.handle_ws_verify_confidence(connection, { 'mid' => 'a1' }, {})
    expect(Monadic::MCP::Conduit).to have_received(:call) do |name, args|
      expect(name).to eq('monadic_confidence')
      roles = args['messages'].map { |m| m['role'] }
      expect(roles).to eq(['user'])                 # system excluded, reviewed answer excluded
      expect(args['messages'].last['content']).to eq('How long do puppies sleep?')
      expect(args['review_answer']).to eq('About 18-20 hours.')
      # No temperature override: each provider uses its standard setting.
      expect(args).not_to have_key('temperature')
    end
  end

  it 'persists a slimmed verdict onto the message (drops budget/usage, caps text)' do
    host.handle_ws_verify_confidence(connection, { 'mid' => 'a1' }, {})
    stored = messages[2]['verify']
    expect(stored).not_to be_nil
    expect(stored).not_to have_key(:budget)
    expect(stored[:responses].first.keys).to contain_exactly(:provider, :model, :success, :text)
  end

  it 'caps long panel answers when persisting' do
    big = { confidence: 'high', score: 0.9, consensus: 'c', disagreements: [],
            responses: [{ provider: 'openai', model: 'm', success: true, text: 'z' * 9000 }] }
    expect(host.slim_verify_for_persist(big)[:responses].first[:text].length).to be <= 4001
  end
end
