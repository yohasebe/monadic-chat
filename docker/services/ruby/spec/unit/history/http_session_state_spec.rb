# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/history/private_request_guard'
require_relative '../../../lib/monadic/utils/websocket/connection_manager'

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
  let(:policy) { Monadic::History::Policy }
  let(:live) { {} }

  def save(chat_state = {})
    WebSocketHelper.update_session_state(tab, messages: [{ 'text' => 'conversation' }],
                                        parameters: { 'app_name' => 'Chat', 'message' => 'input' },
                                        chat_id: chat_id, chat_state: chat_state)
  end

  def request(path = '/attachments', &app)
    worker = Monadic::History::PrivateRequestGuard.new(
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
    expect(state[:chat_state][:monadic_state]).not_to have_key(:context)
    expect(request.first).to eq(200)
  end

  [
    { _history_policy: 'private' },
    { _privacy_session_enabled: true },
    { monadic_state: { privacy: { terms: [{ text: 'MARKEDWORD' }] } } },
    { monadic_state: { privacy: { registry: { 'MARKEDWORD' => 'PERSON_1' } } } }
  ].each do |trace|
    it "refuses an upload with stored privacy state #{trace.keys.first}" do
      save(trace)
      expect(request.first).to eq(403)
      live[tab] = { chat_id: chat_id }
      expect(request.first).to eq(403)
    end
  end

  # Every privacy trace Policy reads, so the snapshot decides as the whole
  # saved state does.
  [
    {},
    { _history_policy: 'private' },
    { _privacy_session_enabled: true },
    { _privacy_pipeline: { lang: 'en' } },
    { monadic_state: { privacy: { terms: [{ text: 'MARKEDWORD' }] } } },
    { monadic_state: { privacy: { registry: { 'MARKEDWORD' => 'PERSON_1' } } } }
  ].each do |trace|
    it "decides as the whole saved state for #{trace.keys.first || 'no trace'}" do
      save(trace)
      full = trace.merge(Monadic::Workspace::Chats::SESSION_KEY => chat_id)
      snapshot = WebSocketHelper.fetch_http_session_state(tab)
      expect(policy.private?(snapshot[:chat_state])).to eq(policy.private?(full))
    end
  end

  it 'keeps the decision of a snapshot when the chat changes after it is taken' do
    save
    snapshot = WebSocketHelper.fetch_http_session_state(tab)
    save(_history_policy: 'private')
    expect(policy.private?(snapshot[:chat_state])).to be false
    expect(policy.private?(WebSocketHelper.fetch_http_session_state(tab)[:chat_state])).to be true
  end

  it 'refuses a live Private chat even when the saved state is normal' do
    save
    live[tab] = { chat_id: chat_id, _history_policy: 'private' }
    expect(request.first).to eq(403)
  end

  it 'keeps a known Private chat private after its stored privacy fields are cleared' do
    policy.remember(chat_id)
    save
    expect(request.first).to eq(403)
  end

  it 'protects marked words and keeps snapshot changes separate from saved state' do
    save(monadic_state: { privacy: { terms: [{ text: 'MARKEDWORD', category: 'PERSON' }] } })
    state = WebSocketHelper.fetch_http_session_state(tab)
    state[:chat_state][:monadic_state][:privacy][:terms][0][:text].replace('changed')
    state[:parameters]['app_name'].replace('changed')
    expect(WebSocketHelper.fetch_http_session_state(tab)[:parameters]['app_name']).to eq('Chat')
    status, = request('/load') do |_env|
      expect(policy.current_work_private?).to be true
      expect(Monadic::Utils::Privacy::EgressGuard.words).to eq(['MARKEDWORD'])
      [200, {}, []]
    end
    expect(status).to eq(200)
  end
end
