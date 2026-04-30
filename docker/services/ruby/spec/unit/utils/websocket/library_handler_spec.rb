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

  describe 'LIBRARY_SAVE → library_saved' do
    let(:valid_payload) do
      {
        'messages' => [
          { 'role' => 'system', 'text' => 'You are a helper.', 'mid' => 1 },
          { 'role' => 'user', 'text' => 'Hi', 'mid' => 2 },
          { 'role' => 'assistant', 'text' => 'Hello!', 'mid' => 3 }
        ],
        'parameters' => { 'app_name' => 'ChatOpenAI', 'model' => 'gpt-5.4' },
        'visibility' => 'personal',
        'title' => 'Demo'
      }
    end

    it 'ingests via Manager.import_from_text and reports success' do
      expect(Monadic::Library::Manager).to receive(:import_from_text)
        .with(hash_including(store: store, visibility: 'personal'))
        .and_return(conversation_id: 'conv-9', counts: { summary: 1, turns: 2, trajectory: 0 })

      host.send(:handle_ws_library_save, connection, { 'contents' => valid_payload }, {})
      msg = replies.first
      expect(msg['type']).to eq('library_saved')
      expect(msg['res']).to eq('success')
      expect(msg['conversation_id']).to eq('conv-9')
      expect(msg['visibility']).to eq('personal')
      expect(msg['counts']).to eq('summary' => 1, 'turns' => 2, 'trajectory' => 0)
    end

    it 'forwards title and license options into Manager.import_from_text' do
      expect(Monadic::Library::Manager).to receive(:import_from_text) do |args|
        expect(args[:options][:title]).to eq('Demo')
        expect(args[:options]).not_to have_key(:license)
        expect(args[:visibility]).to eq('shareable')
        { conversation_id: 'conv-X', counts: { summary: 1, turns: 0, trajectory: 0 } }
      end

      payload = valid_payload.merge('visibility' => 'shareable')
      host.send(:handle_ws_library_save, connection, { 'contents' => payload }, {})
      expect(replies.first['res']).to eq('success')
    end

    it 'rejects payloads with no messages' do
      payload = valid_payload.merge('messages' => [])
      host.send(:handle_ws_library_save, connection, { 'contents' => payload }, {})
      msg = replies.first
      expect(msg['type']).to eq('library_saved')
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to match(/No messages/)
    end

    it 'rejects payloads missing parameters' do
      payload = valid_payload.dup
      payload.delete('parameters')
      host.send(:handle_ws_library_save, connection, { 'contents' => payload }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to match(/Missing parameters/)
    end

    it 'rejects invalid visibility values like "excluded"' do
      payload = valid_payload.merge('visibility' => 'excluded')
      host.send(:handle_ws_library_save, connection, { 'contents' => payload }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to match(/visibility must be one of/)
    end

    it 'reports failure when Manager raises' do
      allow(Monadic::Library::Manager).to receive(:import_from_text).and_raise('embeddings down')
      host.send(:handle_ws_library_save, connection, { 'contents' => valid_payload }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to eq('embeddings down')
    end

    it 'reports failure when contents is not a Hash' do
      host.send(:handle_ws_library_save, connection, { 'contents' => 'not-a-hash' }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      # Falls through validations; message-array check fires first.
      expect(msg['content']).to match(/No messages/)
    end
  end

  describe 'LIBRARY_GET_CONVERSATION → library_conversation_data' do
    it 'returns the verbatim messages payload on success' do
      record = {
        conversation_id: 'conv-y', title: 'Demo',
        messages: [{ 'id' => 'm1', 'speaker' => { 'id' => 'human' }, 'text' => 'Hi' }],
        participants: [{ 'id' => 'human', 'role' => 'human' }],
        skipped_reason: nil
      }
      expect(Monadic::Library::Manager).to receive(:get_conversation_messages)
        .with(hash_including(store: store, conversation_id: 'conv-y', scope: :kb))
        .and_return(record)
      host.send(:handle_ws_library_get_conversation, connection,
                { 'contents' => { 'conversation_id' => 'conv-y' } }, {})
      msg = replies.first
      expect(msg['type']).to eq('library_conversation_data')
      expect(msg['res']).to eq('success')
      expect(msg['conversation_id']).to eq('conv-y')
      expect(msg['conversation']['messages'].first['text']).to eq('Hi')
    end

    it 'accepts a bare conversation_id in contents (legacy clients)' do
      allow(Monadic::Library::Manager).to receive(:get_conversation_messages)
        .and_return(conversation_id: 'c', messages: [], participants: [])
      host.send(:handle_ws_library_get_conversation, connection,
                { 'contents' => 'c' }, {})
      expect(replies.first['res']).to eq('success')
    end

    it 'rejects payloads without conversation_id' do
      host.send(:handle_ws_library_get_conversation, connection,
                { 'contents' => {} }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to match(/Missing conversation_id/)
    end

    it 'reports failure when the conversation is not found' do
      allow(Monadic::Library::Manager).to receive(:get_conversation_messages).and_return(nil)
      host.send(:handle_ws_library_get_conversation, connection,
                { 'contents' => { 'conversation_id' => 'missing' } }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to match(/Conversation not found/)
    end

    it 'reports failure when Manager raises' do
      allow(Monadic::Library::Manager).to receive(:get_conversation_messages).and_raise('qdrant down')
      host.send(:handle_ws_library_get_conversation, connection,
                { 'contents' => { 'conversation_id' => 'c' } }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to eq('qdrant down')
    end
  end

  describe 'LIBRARY_TOGGLE_VISIBILITY → library_visibility_updated' do
    it 'forwards to Manager.update_visibility and confirms success' do
      expect(Monadic::Library::Manager).to receive(:update_visibility)
        .with(store: store, conversation_id: 'conv-x', visibility: 'shareable').and_return(true)
      host.send(:handle_ws_library_toggle_visibility, connection,
                { 'contents' => { 'conversation_id' => 'conv-x', 'visibility' => 'shareable' } }, {})
      msg = replies.first
      expect(msg['type']).to eq('library_visibility_updated')
      expect(msg['res']).to eq('success')
      expect(msg['conversation_id']).to eq('conv-x')
      expect(msg['visibility']).to eq('shareable')
    end

    it 'rejects payloads missing conversation_id' do
      host.send(:handle_ws_library_toggle_visibility, connection,
                { 'contents' => { 'visibility' => 'personal' } }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to match(/Missing conversation_id/)
    end

    it 'rejects invalid visibility values' do
      host.send(:handle_ws_library_toggle_visibility, connection,
                { 'contents' => { 'conversation_id' => 'c', 'visibility' => 'excluded' } }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to match(/visibility must be one of/)
    end

    it 'reports failure when Manager raises' do
      allow(Monadic::Library::Manager).to receive(:update_visibility).and_raise('qdrant down')
      host.send(:handle_ws_library_toggle_visibility, connection,
                { 'contents' => { 'conversation_id' => 'c', 'visibility' => 'personal' } }, {})
      msg = replies.first
      expect(msg['res']).to eq('failure')
      expect(msg['content']).to eq('qdrant down')
      expect(msg['conversation_id']).to eq('c')
    end
  end

  describe 'LIBRARY_RAG_TOGGLE → library_rag_state' do
    it 'persists the enabled flag in session[:parameters] and echoes back state' do
      session = {}
      host.send(:handle_ws_library_rag_toggle, connection,
                { 'contents' => { 'enabled' => true } }, session)
      expect(session[:parameters]['library_rag_enabled']).to be true
      expect(replies.first).to eq('type' => 'library_rag_state', 'enabled' => true)
    end

    it 'clears the flag when payload disables the toggle' do
      session = { parameters: { 'library_rag_enabled' => true } }
      host.send(:handle_ws_library_rag_toggle, connection,
                { 'contents' => { 'enabled' => false } }, session)
      expect(session[:parameters]['library_rag_enabled']).to be false
      expect(replies.first['enabled']).to be false
    end

    it 'accepts a bare boolean in `contents` for older clients' do
      session = {}
      host.send(:handle_ws_library_rag_toggle, connection,
                { 'contents' => true }, session)
      expect(session[:parameters]['library_rag_enabled']).to be true
    end
  end

  describe 'LIBRARY_RAG_QUERY → library_rag_state' do
    it 'returns the current flag without mutating session' do
      session = { parameters: { 'library_rag_enabled' => true } }
      host.send(:handle_ws_library_rag_query, connection, {}, session)
      expect(replies.first).to eq('type' => 'library_rag_state', 'enabled' => true)
      expect(session[:parameters]['library_rag_enabled']).to be true
    end

    it 'reports false when the flag is missing' do
      session = {}
      host.send(:handle_ws_library_rag_query, connection, {}, session)
      expect(replies.first['enabled']).to be false
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
