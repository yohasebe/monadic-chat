# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/utils/websocket/connection_manager'
require_relative '../../../lib/monadic/workspace/chat_request_scope'

RSpec.describe 'HTTP session checks' do
  around do |example|
    saved = WebSocketHelper.class_variable_get(:@@session_state)
    WebSocketHelper.class_variable_set(:@@session_state, {})
    example.run
  ensure
    WebSocketHelper.class_variable_set(:@@session_state, saved)
  end

  let(:tab) { SecureRandom.hex(8) }
  let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
  let(:live) { {} }

  def save(chat_state = {})
    WebSocketHelper.update_session_state(tab, messages: [{ 'text' => 'conversation' }],
                                        parameters: { 'app_name' => 'Chat', 'message' => 'input' },
                                        chat_id: chat_id, chat_state: chat_state)
  end

  def request(path = '/attachments', &app)
    worker = Monadic::Workspace::ChatRequestScope.new(
      app || ->(_env) { [200, {}, []] }, paths: ['/attachments'],
      session_lookup: ->(id) { live[id] }, state_lookup: WebSocketHelper.method(:fetch_http_session_state)
    )
    worker.call('REQUEST_METHOD' => 'POST', 'PATH_INFO' => path, 'QUERY_STRING' => "tab_id=#{tab}")
  end

  it 'returns nil for an unknown tab and refuses its upload' do
    expect(WebSocketHelper.fetch_http_session_state(tab)).to be_nil
    expect(request.first).to eq(409)
  end

  it 'keeps normal uploads working without copying the conversation or Session Context' do
    save(monadic_state: { context: 'context' }, tool_results: ['result'])
    expect(WebSocketHelper).not_to receive(:deep_clone_session_state)
    state = WebSocketHelper.fetch_http_session_state(tab)
    expect(state[:chat_id]).to eq(chat_id)
    expect(state[:parameters]).to eq('app_name' => 'Chat')
    expect(state).not_to have_key(:messages)
    expect(state[:chat_state]).not_to have_key(:tool_results)
    expect(state[:chat_state]).not_to have_key(:monadic_state)
    expect(request.first).to eq(200)
  end

  describe 'a chat that hides its words with a word table' do
    let(:words) { Monadic::Utils::Privacy::Words }
    let(:guard) { Monadic::Utils::Privacy::EgressGuard }

    after { words::LOCK.synchronize { words::TABLES.clear } }

    it 'checks what is sent for it against its words' do
      session = { Monadic::Workspace::Chats::SESSION_KEY => chat_id }
      words.start!(session).confirm!('Ada', 'PERSON')
      save(words::MARK_KEY => session[words::MARK_KEY])

      state = WebSocketHelper.fetch_http_session_state(tab)
      expect(state[:chat_state][words::MARK_KEY]).to eq(chat_id)
      expect(state[:chat_state]).not_to have_key(:monadic_state)
      checked = nil
      status, = request do |_env|
        checked = begin
          guard.check!('api.example.com', 'about Ada')
          :sent
        rescue Monadic::Utils::Privacy::Outbound::Refused
          :refused
        end
        [200, {}, []]
      end
      expect(status).to eq(200)
      expect(checked).to eq(:refused)
    end

    # A chat of its own, with a table, saved with its mark; whether a request from its tab may send ordinary text out.
    def sent_through_request(drop_table: false)
      id = Monadic::Workspace::Ids.generate(:chat)
      session = { Monadic::Workspace::Chats::SESSION_KEY => id }
      words.start!(session)
      words::LOCK.synchronize { words::TABLES.delete(id) } if drop_table
      WebSocketHelper.update_session_state(tab, messages: [], parameters: { 'app_name' => 'Chat' }, chat_id: id,
                                                chat_state: { words::MARK_KEY => id })
      result = nil
      request('/elsewhere') do |_env|
        result = begin
          guard.check!('api.example.com', 'ordinary text')
          :sent
        rescue Monadic::Utils::Privacy::Outbound::Refused
          :refused
        end
        [200, {}, []]
      end
      result
    end

    it 'sends nothing for it when its table is gone' do
      expect(sent_through_request).to eq(:sent)
      # Refused because its words are not known.
      expect(sent_through_request(drop_table: true)).to eq(:refused)
    end
  end

  it 'keeps nothing in the snapshot but the chat, its app and the mark of its word table' do
    save(_history_policy: 'private', _privacy_session_enabled: true,
         monadic_state: { privacy: { terms: [{ text: 'MARKEDWORD' }] } })
    snapshot = WebSocketHelper.fetch_http_session_state(tab)
    expect(snapshot[:chat_state]).to eq({})
    expect(request.first).to eq(200)
  end

  it 'takes the upload of a live chat whatever its saved state holds' do
    save(_history_policy: 'private')
    live[tab] = { chat_id: chat_id }
    expect(request.first).to eq(200)
  end

  it 'checks the words of a saved chat and keeps snapshot changes separate from saved state' do
    words = Monadic::Utils::Privacy::Words
    session = { Monadic::Workspace::Chats::SESSION_KEY => chat_id }
    words.start!(session).confirm!('MARKEDWORD', 'PERSON')
    save(words::MARK_KEY => session[words::MARK_KEY])
    state = WebSocketHelper.fetch_http_session_state(tab)
    state[:chat_state][words::MARK_KEY].replace('changed')
    state[:parameters]['app_name'].replace('changed')
    again = WebSocketHelper.fetch_http_session_state(tab)
    expect(again[:parameters]['app_name']).to eq('Chat')
    expect(again[:chat_state][words::MARK_KEY]).to eq(chat_id)
    status, = request('/load') do |_env|
      expect(Monadic::Utils::Privacy::EgressGuard.words).to eq(['MARKEDWORD'])
      [200, {}, []]
    end
    expect(status).to eq(200)
  ensure
    words::LOCK.synchronize { words::TABLES.clear }
  end
end
