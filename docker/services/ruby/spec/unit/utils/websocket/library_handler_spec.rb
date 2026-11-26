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
          language: 'en', license: 'CC-BY-NC-ND-4.0', scope_app: 'Global',
          turns_count: 7, messages_count: 7, created_at: '2026-04-30T10:00:00Z' },
        { conversation_id: 'B', title: nil, source: 'monadic-chat',
          language: 'en', license: 'private', scope_app: 'ChatOpenAI',
          turns_count: 4, messages_count: 4, created_at: '2026-04-29T10:00:00Z' }
      ]
      allow(Monadic::Library::Manager).to receive(:list_conversations)
        .with(hash_excluding(:app_name))
        .and_return(rows)

      host.send(:handle_ws_library_list, connection, {}, {})
      expect(replies.size).to eq(1)
      msg = replies.first
      expect(msg['type']).to eq('library_conversations')
      expect(msg['content'].size).to eq(2)
      expect(msg['content'].first.keys).to all(be_a(String))
      expect(msg['content'].first['conversation_id']).to eq('A')
    end

    it 'gives every entry and their number, and says of a record whether its chat can be continued' do
      rows = [{ conversation_id: 'A', title: 'Kept', source_chat_id: 'c_kept', created_at: '2026-11-02' },
              { conversation_id: 'B', title: 'Gone', source_chat_id: 'c_gone', created_at: '2026-11-01' },
              { conversation_id: 'C', title: 'Doc', created_at: '2026-10-31' }]
      allow(Monadic::Library::Manager).to receive(:list_conversations).with(store: store, limit: nil).and_return(rows)
      history = instance_double(Monadic::History::Store)
      allow(Monadic::History::Store).to receive(:default).and_return(history)
      allow(history).to receive(:resumable?) { |id| id == 'c_kept' }

      host.send(:handle_ws_library_list, connection, {}, {})

      msg = replies.first
      expect(msg['total']).to eq(3)
      expect(msg['content'][0]).to include('source_chat_id' => 'c_kept', 'source_chat_resumable' => true)
      expect(msg['content'][1].keys).not_to include('source_chat_id', 'source_chat_resumable')
      expect(msg['content'][2].keys).not_to include('source_chat_id')
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

  describe 'LIBRARY_CONVERSATION_DRAFT → library_conversation_draft' do
    let(:session) { { Monadic::Workspace::Chats::SESSION_KEY => 'chat-1', messages: [], parameters: {} } }

    let(:live) { ->(_tab) { 1 } }

    before do
      allow(host).to receive(:workbench_connection).and_return(tab: 't', generation: 1)
      stub_const('WebSocketHelper::WORKBENCH_LIVE', live)
    end

    it "puts the chat's record on its work screen and names the item" do
      expect(Monadic::Library::ConversationDraft).to receive(:put)
        .with(session, tab: 't', generation: 1, live: live).and_return('i_1')
      allow(Monadic::Workbench::Channel).to receive(:changed)

      host.send(:handle_ws_library_conversation_draft, connection, {}, session)

      expect(replies.first).to eq('type' => 'library_conversation_draft', 'item_id' => 'i_1')
      expect(Monadic::Workbench::Channel).to have_received(:changed).with('chat-1')
    end

    it 'says why nothing was put' do
      allow(Monadic::Library::ConversationDraft).to receive(:put)
        .and_raise(Monadic::Library::ConversationDraft::Refused, 'not_saved_by_app')

      host.send(:handle_ws_library_conversation_draft, connection, {}, session)

      expect(replies.first).to eq('type' => 'library_conversation_draft', 'error' => 'not_saved_by_app')
    end
  end

  describe 'LIBRARY_FROM_WORKBENCH → library_from_workbench' do
    let(:words) { Monadic::Utils::Privacy::Words }

    after { words::LOCK.synchronize { words::TABLES.clear } }

    it 'keeps nothing from a chat that hides words' do
      session = { chat_id: Monadic::Workspace::Ids.generate(:chat), messages: [], parameters: {} }
      words.start!(session)
      expect(Monadic::Library::DeskImport).not_to receive(:start)

      host.send(:handle_ws_library_from_workbench, connection, { 'item_id' => 'i_1', 'sha256' => 'a' * 64 }, session)

      expect(replies.first['error']).to eq('hides_words')
    end

    it 'keeps nothing for a tab that is not the live one of the chat' do
      allow(host).to receive(:workbench_connection).and_return(tab: 't', generation: 1)
      expect(Monadic::Library::DeskImport).not_to receive(:start)

      host.send(:handle_ws_library_from_workbench, connection, { 'item_id' => 'i_1', 'sha256' => 'a' * 64 },
                { messages: [], parameters: {} })

      expect(replies.first['error']).to eq('not_allowed')
    end

    it 'starts the import of the version the tab shows and gives its id' do
      board = double('board')
      allow(host).to receive(:workbench_connection).and_return(tab: 't', generation: 1)
      stub_const('WebSocketHelper::WORKBENCH_LIVE', ->(_tab) { 1 })
      allow(Monadic::Workbench::Board).to receive(:existing).with('chat-1').and_return(board)
      expect(Monadic::Library::DeskImport).to receive(:start)
        .with(board, 'i_1', 'a' * 64, app_name: 'ChatOpenAI', title: 'Tides', choice: { 'update' => 'conv-1', 'seen' => 't0' })
        .and_return('imp-1')

      host.send(:handle_ws_library_from_workbench, connection,
                { 'item_id' => 'i_1', 'sha256' => 'a' * 64, 'title' => 'Tides', 'choice' => { 'update' => 'conv-1', 'seen' => 't0' } },
                { Monadic::Workspace::Chats::SESSION_KEY => 'chat-1', messages: [], parameters: { 'app_name' => 'ChatOpenAI' } })

      expect(replies.first).to include('import_id' => 'imp-1', 'status_url' => '/library/import/status/imp-1')
    end

    it 'takes no choice the page makes up, and asks the user to choose when the chat is kept already, with the revision of each record to send back' do
      allow(host).to receive(:workbench_connection).and_return(tab: 't', generation: 1)
      stub_const('WebSocketHelper::WORKBENCH_LIVE', ->(_tab) { 1 })
      allow(Monadic::Workbench::Board).to receive(:existing).and_return(double('board'))
      records = [{ conversation_id: 'conv-1', title: 'Tides', created_at: 't0', revision: 'r1' }]
      expect(Monadic::Library::DeskImport).to receive(:start).with(anything, 'i_1', 'a' * 64, app_name: nil, title: nil, choice: nil)
                                                             .and_raise(Monadic::Library::DeskImport::Choose.new(records))

      host.send(:handle_ws_library_from_workbench, connection, { 'item_id' => 'i_1', 'sha256' => 'a' * 64, 'choice' => 'overwrite-all' },
                { Monadic::Workspace::Chats::SESSION_KEY => 'chat-1', messages: [], parameters: {} })

      expect(replies.first).to include('error' => 'choose',
                                       'records' => [{ 'id' => 'conv-1', 'title' => 'Tides', 'created_at' => 't0', 'revision' => 'r1' }])
    end

    it 'says the document changed when it is not the version the tab shows' do
      allow(host).to receive(:workbench_connection).and_return(tab: 't', generation: 1)
      stub_const('WebSocketHelper::WORKBENCH_LIVE', ->(_tab) { 1 })
      allow(Monadic::Workbench::Board).to receive(:existing).and_return(double('board'))
      allow(Monadic::Library::DeskImport).to receive(:start).and_raise(Monadic::Workbench::Artifact::Changed, 'changed')

      host.send(:handle_ws_library_from_workbench, connection, { 'item_id' => 'i_1', 'sha256' => 'a' * 64 },
                { Monadic::Workspace::Chats::SESSION_KEY => 'chat-1', messages: [], parameters: {} })

      expect(replies.first['error']).to eq('changed')
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
        .with(store: store, conversation_id: 'conv-y')
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
end
