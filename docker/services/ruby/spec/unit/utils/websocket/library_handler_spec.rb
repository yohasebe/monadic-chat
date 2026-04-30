# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'
require_relative '../../../../lib/monadic/utils/websocket/library_handler'

# Behaviour tests for the WebSocket Library handlers. We instantiate a
# host class that mixes in WebSocketHelper and stub:
#   - the Library Store factory (no Qdrant in unit tests)
#   - send_to_client (capture replies)
#   - the underlying Manager methods (we only assert the WS contract)
RSpec.describe 'WebSocketHelper Library handlers' do
  let(:host) do
    Class.new {
      include WebSocketHelper

      def self.fake_replies
        @fake_replies ||= []
      end

      def send_to_client(_connection, payload)
        self.class.fake_replies << payload
      end
    }.new
  end

  let(:replies) { host.class.fake_replies }
  let(:connection) { instance_double('Connection') }
  let(:store) { instance_double(Monadic::Library::Store) }

  before do
    host.class.fake_replies.clear
    allow(host).to receive(:library_store_for_ws).and_return(store)
  end

  describe 'LIBRARY_LIST → library_conversations' do
    it 'returns the inventory rows with stringified keys' do
      rows = [
        { conversation_id: 'A', title: 'Talk A', source: 'ted-talk',
          language: 'en', license: 'CC-BY-NC-ND-4.0', visibility: 'shareable',
          turns_count: 7, messages_count: 7, created_at: '2026-04-30T10:00:00Z' },
        { conversation_id: 'B', title: nil, source: 'monadic-chat',
          language: 'en', license: 'private', visibility: 'personal',
          turns_count: 4, messages_count: 4, created_at: '2026-04-29T10:00:00Z' }
      ]
      allow(Monadic::Library::Manager).to receive(:list_conversations)
        .with(hash_including(scope: :kb))
        .and_return(rows)

      host.send(:handle_ws_library_list, connection, {}, {})
      expect(replies.size).to eq(1)
      msg = replies.first
      expect(msg['type']).to eq('library_conversations')
      expect(msg['content'].size).to eq(2)
      expect(msg['content'].first.keys).to all(be_a(String))
      expect(msg['content'].first['conversation_id']).to eq('A')
    end

    it 'returns an empty content array on Manager error' do
      allow(Monadic::Library::Manager).to receive(:list_conversations).and_raise('boom')
      host.send(:handle_ws_library_list, connection, {}, {})
      msg = replies.first
      expect(msg['type']).to eq('library_conversations')
      expect(msg['content']).to eq([])
      expect(msg['error']).to eq('boom')
    end
  end

  describe 'LIBRARY_DELETE → library_deleted' do
    it 'deletes the conversation and confirms success' do
      expect(Monadic::Library::Manager).to receive(:delete_conversation)
        .with(store: store, conversation_id: 'conv-x').and_return(true)
      host.send(:handle_ws_library_delete, connection, { 'contents' => 'conv-x' }, {})
      msg = replies.first
      expect(msg['type']).to eq('library_deleted')
      expect(msg['res']).to eq('success')
      expect(msg['conversation_id']).to eq('conv-x')
    end

    it 'reports failure when conversation_id is missing' do
      host.send(:handle_ws_library_delete, connection, { 'contents' => '' }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to match(/Missing conversation_id/)
    end

    it 'reports failure when Manager raises' do
      allow(Monadic::Library::Manager).to receive(:delete_conversation).and_raise('qdrant down')
      host.send(:handle_ws_library_delete, connection, { 'contents' => 'conv-x' }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to eq('qdrant down')
      expect(msg['conversation_id']).to eq('conv-x')
    end
  end

  describe 'LIBRARY_STATS → library_stats' do
    it 'returns the counts payload with stringified keys' do
      allow(Monadic::Library::Manager).to receive(:library_stats)
        .with(store: store)
        .and_return(conversations_total: 10, conversations_shareable: 3, conversations_personal: 7)
      host.send(:handle_ws_library_stats, connection, {}, {})
      msg = replies.first
      expect(msg['type']).to eq('library_stats')
      expect(msg['content']).to eq(
        'conversations_total' => 10,
        'conversations_shareable' => 3,
        'conversations_personal' => 7
      )
    end

    it 'reports zeros and an error message when Manager fails' do
      allow(Monadic::Library::Manager).to receive(:library_stats).and_raise('embed-svc down')
      host.send(:handle_ws_library_stats, connection, {}, {})
      msg = replies.first
      expect(msg['type']).to eq('library_stats')
      expect(msg['content']['conversations_total']).to eq(0)
      expect(msg['error']).to eq('embed-svc down')
    end
  end
end
