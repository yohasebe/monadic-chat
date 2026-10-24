# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'securerandom'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/utils/websocket'
require_relative '../../../lib/monadic/utils/container_dependencies'
require_relative '../../../lib/monadic/utils/privacy/presidio_backend'

# The history as the WebSocket handlers write it: through the sync of the
# tab's state, the Privacy Filter toggle and a change of app.
RSpec.describe 'What the handlers write to the history' do
  let(:dir) { Dir.mktmpdir('history-wiring') }
  let(:store) { Monadic::History::Store.new(File.join(dir, 'history.sqlite3')) }
  let(:tab) { "tab-#{SecureRandom.hex(4)}" }
  let(:marker) { "MARK#{SecureRandom.hex(16)}" }
  let(:host) do
    Class.new do
      include WebSocketHelper
      def sent
        @sent ||= []
      end

      def send_to_client(_connection, payload)
        sent << payload
      end
    end.new
  end

  around do |example|
    saved = ENV['MONADIC_HISTORY']
    ENV['MONADIC_HISTORY'] = 'true'
    example.run
  ensure
    store.close
    FileUtils.rm_rf(dir)
    saved ? ENV['MONADIC_HISTORY'] = saved : ENV.delete('MONADIC_HISTORY')
    opened.each { |id, generation| WebSocketHelper.unregister_live_session(id, generation) }
    Thread.current[:websocket_session_id] = nil
    Thread.current[:rack_session] = nil
  end

  before do
    allow(Monadic::History::Store).to receive(:default).and_return(store)
    allow(WebSocketHelper).to receive(:send_to_session)
    allow(Monadic::Utils::ContainerDependencies).to receive(:ensure_services_async)
    Thread.current[:websocket_session_id] = tab
  end

  let(:opened) { [] }

  # The chat open in a tab of its own, as a connection registers it.
  def open_in_tab(session)
    id = "tab-#{SecureRandom.hex(4)}"
    WebSocketHelper.register_live_session(id, session, 1)
    opened << [id, 1]
    id
  end

  def chat_session(text, generation:)
    {
      chat_id: Monadic::Workspace::Ids.generate(:chat), _ws_generation: generation,
      messages: [{ 'mid' => 'm1', 'role' => 'user', 'text' => text }],
      parameters: { 'app_name' => 'ChatOpenAI', 'model' => 'gpt-x' }
    }
  end

  # Two connections of the tab, as a reconnect makes them: the second one
  # claims the tab's state after the first.
  def connect_twice
    [WebSocketHelper.claim_session_state(tab), WebSocketHelper.claim_session_state(tab)]
  end

  def sync(session)
    Thread.current[:rack_session] = session
    host.sync_session_state!
  end

  def stored_bytes
    Dir.glob(File.join(dir, '*')).map { |f| File.binread(f) }.join
  end

  it 'does not let a connection that a newer one replaced write its older copy' do
    first, second = connect_twice
    newer = chat_session('newer text', generation: second)
    older = newer.merge(_ws_generation: first, messages: [{ 'mid' => 'm1', 'role' => 'user', 'text' => marker }])
    sync(newer)
    sync(older)
    expect(store.get(newer[:chat_id])['payload']['messages'].map { |m| m['text'] }).to eq(['newer text'])
    expect(stored_bytes).not_to include(marker)
  end

  # The newer connection is in another chat (a Reset), so the store has no
  # row of the older one's chat to compare with: the tab's state says no.
  it 'does not let a replaced connection bring back the chat the tab has left' do
    first, second = connect_twice
    sync(chat_session('the chat the tab is in now', generation: second))
    left = chat_session(marker, generation: first)
    sync(left)
    expect(store.get(left[:chat_id])).to be_nil
    expect(stored_bytes).not_to include(marker)
  end

  [true, false].each do |healthy|
    it "keeps out a chat that asked for the filter before its first words (filter up: #{healthy})" do
      allow_any_instance_of(Monadic::Utils::Privacy::PresidioBackend).to receive(:health).and_return(healthy)
      allow(host).to receive(:send_privacy_state)
      session = chat_session(marker, generation: 1).merge(messages: [])

      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
      session[:messages] << { 'mid' => 'm1', 'role' => 'user', 'text' => marker }
      sync(session)
      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => false })
      sync(session)
      expect(store.get(session[:chat_id])).to be_nil
      store.close
      expect(stored_bytes).not_to include(marker)
    end
  end

  # Whether a chat is Private is decided when it begins: the filter asked
  # for in a chat with words in it is refused, and what was kept stays.
  it 'refuses the filter in a chat the user has written in, and keeps the chat' do
    probe = class_double(Monadic::Utils::Privacy::PresidioBackend)
    allow(Monadic::Utils::Privacy::PresidioBackend).to receive(:new).and_return(probe)
    session = chat_session('kept words', generation: 1)
    sync(session)

    host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
    expect(host.sent.last).to include('type' => 'privacy_toggle_ack', 'enabled' => false, 'error' => 'privacy_chat_started')
    expect(session[:_privacy_session_enabled]).not_to be(true)
    expect(Monadic::History::Policy.private?(session)).to be(false)
    sync(session)
    expect(store.get(session[:chat_id])['payload']['messages'].map { |m| m['text'] }).to eq(['kept words'])
  end

  it 'refuses the filter once the session has started, before any user words' do
    session = chat_session('x', generation: 1).merge(messages: [{ 'mid' => 's1', 'role' => 'system', 'text' => 'You are helpful.' }])
    host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
    expect(host.sent.last).to include('enabled' => false, 'error' => 'privacy_chat_started')
    expect(Monadic::History::Policy.private?(session)).to be(false)
  end

  it 'lets a Private chat ask for the filter again' do
    allow_any_instance_of(Monadic::Utils::Privacy::PresidioBackend).to receive(:health).and_return(true)
    allow(host).to receive(:send_privacy_state)
    session = chat_session(marker, generation: 1).merge(_privacy_session_enabled: true)
    host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
    expect(host.sent.last).to include('type' => 'privacy_toggle_ack', 'enabled' => true, 'error' => nil)
  end

  it 'does not carry a chat into the next app when the app changes without Reset' do
    session = chat_session(marker, generation: 1).merge(_privacy_session_enabled: true)
    sync(session)
    host.send(:handle_ws_update_params, nil, { 'params' => { 'app_name' => 'ChatClaude' } }, session)
    session[:messages] << { 'mid' => 'm2', 'role' => 'user', 'text' => 'first words in the new app' }
    sync(session)

    texts = store.list.map { |row| store.get(row['chat_id'])['payload']['messages'].map { |m| m['text'] } }
    expect(texts).to eq([['first words in the new app']])
    store.close
    expect(stored_bytes).not_to include(marker)
  end

  describe 'the list, names and removal' do
    it 'lists headings and whether a chat is open, and finds a chat by its words' do
      session = chat_session("plan the trip to #{marker}", generation: 1)
      sync(session)
      allow(WebSocketHelper).to receive(:live_chat_ids).and_return([session[:chat_id]])

      host.send(:handle_ws_history_list, nil, { 'query' => marker })
      reply = host.sent.last
      expect(reply['items'].map { |i| i['chat_id'] }).to eq([session[:chat_id]])
      expect(reply['items'].first).to include('open' => true, 'heading_first' => "plan the trip to #{marker}")
      expect(reply['items'].first.keys).not_to include('payload', 'search_text')

      host.send(:handle_ws_history_list, nil, { 'query' => '%' })
      expect(host.sent.last['items']).to eq([])
    end

    it 'names a chat, and removes it only when no tab has it open' do
      session = chat_session(marker, generation: 1)
      sync(session)
      host.send(:handle_ws_history_rename, nil, { 'chat_id' => session[:chat_id], 'title' => "  My\ntrip  " })
      expect(store.list.first['title_user']).to eq('My trip')

      open_tab = open_in_tab(session)
      host.send(:handle_ws_history_delete, nil, { 'chat_id' => session[:chat_id] })
      expect(host.sent.last).to include('success' => false, 'error' => 'history_chat_open')

      WebSocketHelper.unregister_live_session(open_tab, 1)
      host.send(:handle_ws_history_delete, nil, { 'chat_id' => session[:chat_id] })
      expect(host.sent.last).to include('success' => true)
      store.close
      expect(stored_bytes).not_to include(marker)
    end

    it 'takes only chat ids this server issues' do
      host.send(:handle_ws_history_delete, nil, { 'chat_id' => '../history.sqlite3' })
      expect(host.sent.last).to include('success' => false, 'error' => 'history_not_found')
    end

    it 'keeps the order of the list when only the Session Context changes' do
      first = chat_session('first chat', generation: 1)
      sync(first)
      later = chat_session('later chat', generation: 1).merge(chat_id: Monadic::Workspace::Ids.generate(:chat))
      allow(Time).to receive(:now).and_return(Time.now + 60)
      sync(later)
      allow(Time).to receive(:now).and_return(Time.now + 120)
      first[:monadic_state] = { conversation_context: { 'topics' => [{ 'text' => 'trips' }] } }
      sync(first)
      expect(store.list.map { |r| r['chat_id'] }).to eq([later[:chat_id], first[:chat_id]])
    end
  end

  describe 'resuming a chat' do
    before { allow(host).to receive(:prepare_apps_data).and_return({}) }

    def resume_in(other_tab, session, chat_id)
      Thread.current[:websocket_session_id] = other_tab
      Thread.current[:rack_session] = session
      obj = { 'chat_id' => chat_id }
      host.send(:handle_ws_history_resume, nil, obj, session, host.send(:history_resume_refusal, obj, session))
      host.sent.last
    end

    def empty_tab_session(other_tab)
      { chat_id: Monadic::Workspace::Ids.generate(:chat), _ws_generation: WebSocketHelper.claim_session_state(other_tab),
        messages: [], parameters: {} }
    end

    it 'continues the chat under its id in another tab, which then is the only one to write it' do
      kept = chat_session(marker, generation: 1)
      sync(kept)
      other_tab = "tab-#{SecureRandom.hex(4)}"
      generation = WebSocketHelper.claim_session_state(other_tab)
      here = { chat_id: Monadic::Workspace::Ids.generate(:chat), _ws_generation: generation,
               messages: [], parameters: { 'ui_language' => 'ja' }, gemini3_last_image: 'left.png' }

      expect(resume_in(other_tab, here, kept[:chat_id])).to include('success' => true)
      expect(here[:chat_id]).to eq(kept[:chat_id])
      expect(here[:messages].map { |m| m['text'] }).to eq([marker])
      expect(here[:parameters]).to include('app_name' => 'ChatOpenAI', 'ui_language' => 'ja', 'auto_speech' => false)
      expect(here).not_to have_key(:gemini3_last_image)
      expect(host.sent.map { |m| m['type'] }).to include('past_messages')

      Thread.current[:websocket_session_id] = tab
      kept[:messages] << { 'mid' => 'm2', 'role' => 'user', 'text' => 'from the old tab' }
      sync(kept)
      expect(store.get(kept[:chat_id])['payload']['messages'].map { |m| m['text'] }).to eq([marker])
      Thread.current[:websocket_session_id] = other_tab
      here[:messages] << { 'mid' => 'm3', 'role' => 'user', 'text' => 'from the new tab' }
      sync(here)
      expect(store.get(kept[:chat_id])['payload']['messages'].map { |m| m['text'] }).to eq([marker, 'from the new tab'])
    end

    it 'asks before it replaces a Private chat with words in it, and shows the resumed chat locked' do
      kept = chat_session('kept', generation: 1)
      sync(kept)
      other_tab = "tab-#{SecureRandom.hex(4)}"
      here = { chat_id: Monadic::Workspace::Ids.generate(:chat), _ws_generation: WebSocketHelper.claim_session_state(other_tab),
               messages: [{ 'role' => 'user', 'text' => 'private words' }], parameters: {}, _privacy_session_enabled: true }
      expect(resume_in(other_tab, here, kept[:chat_id])).to include('success' => false, 'error' => 'history_private_here')
      expect(here[:messages].map { |m| m['text'] }).to eq(['private words'])

      Thread.current[:websocket_session_id] = other_tab
      obj = { 'chat_id' => kept[:chat_id], 'confirm' => true }
      host.send(:handle_ws_history_resume, nil, obj, here, host.send(:history_resume_refusal, obj, here))
      expect(host.sent.last).to include('success' => true)
      expect(host.sent).to include(include('type' => 'privacy_state', 'enabled' => false, 'restored' => true))
    end

    it 'does not resume a chat open in another tab, or touch the chat here' do
      kept = chat_session(marker, generation: 1)
      sync(kept)
      open_in_tab(kept)
      here = { chat_id: Monadic::Workspace::Ids.generate(:chat), messages: [{ 'role' => 'user', 'text' => 'mine' }],
               parameters: { 'app_name' => 'ChatClaude' } }
      expect(resume_in("tab-#{SecureRandom.hex(4)}", here, kept[:chat_id])).to include('success' => false, 'error' => 'history_chat_open')
      expect(here[:messages].map { |m| m['text'] }).to eq(['mine'])
    end

    # Between the check and taking the chat, the tab stops what runs for its
    # current chat; another tab cannot take the chat meanwhile, nor remove it.
    it 'lets only one tab take a chat, and removes none while it is being taken' do
      kept = chat_session(marker, generation: 1)
      sync(kept)
      tab_a = "tab-#{SecureRandom.hex(4)}"
      tab_b = "tab-#{SecureRandom.hex(4)}"
      a = empty_tab_session(tab_a)
      b = empty_tab_session(tab_b)
      obj = { 'chat_id' => kept[:chat_id] }

      refusal_a = host.send(:history_resume_refusal, obj, a)
      expect(refusal_a).to be_nil
      expect(host.send(:history_resume_refusal, obj, b)).to eq('history_chat_open')
      host.send(:handle_ws_history_delete, nil, obj)
      expect(host.sent.last).to include('success' => false, 'error' => 'history_chat_open')

      Thread.current[:websocket_session_id] = tab_a
      host.send(:handle_ws_history_resume, nil, obj, a, refusal_a)
      expect(host.sent.last).to include('success' => true)
      expect(store.get(kept[:chat_id])['owner_tab']).to eq(tab_a)
    end

    it 'does not take a chat that is not kept, so what runs here goes on' do
      here = empty_tab_session(tab)
      missing = { 'chat_id' => Monadic::Workspace::Ids.generate(:chat) }
      expect(host.send(:history_resume_refusal, missing, here)).to eq('history_not_found')
      expect(WebSocketHelper.reserve_chat(missing['chat_id'])).to be(true)
      WebSocketHelper.release_chat(missing['chat_id'])
    end

    # The tab a chat was taken from neither brings it back on reconnecting
    # nor removes what the new tab keeps of it.
    it 'leaves a chat with the tab that took it' do
      kept = chat_session(marker, generation: 1)
      sync(kept)
      expect(host.send(:history_taken_elsewhere?, kept[:chat_id], tab)).to be(false)
      other_tab = "tab-#{SecureRandom.hex(4)}"
      expect(resume_in(other_tab, empty_tab_session(other_tab), kept[:chat_id])).to include('success' => true)
      expect(host.send(:history_taken_elsewhere?, kept[:chat_id], tab)).to be(true)
      expect(host.send(:history_taken_elsewhere?, kept[:chat_id], other_tab)).to be(false)

      Thread.current[:websocket_session_id] = tab
      kept[:messages] = []
      sync(kept)
      kept[:_privacy_session_enabled] = true
      sync(kept)
      expect(store.get(kept[:chat_id])).to include('owner_tab' => other_tab)
      kept.delete(:_privacy_session_enabled)
      kept.delete(Monadic::History::Policy::SESSION_KEY)
      kept[:messages] = [{ 'mid' => 'm9', 'role' => 'user', 'text' => 'from the old tab' }]
      sync(kept)
      expect(store.get(kept[:chat_id])).to include('owner_tab' => other_tab)
      expect(store.get(kept[:chat_id])['payload']['messages'].map { |m| m['text'] }).to eq([marker])
    end
  end
end
