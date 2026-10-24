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
      def send_to_client(*); end
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
    Thread.current[:websocket_session_id] = nil
    Thread.current[:rack_session] = nil
  end

  before do
    allow(Monadic::History::Store).to receive(:default).and_return(store)
    allow(WebSocketHelper).to receive(:send_to_session)
    allow(Monadic::Utils::ContainerDependencies).to receive(:ensure_services_async)
    Thread.current[:websocket_session_id] = tab
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
    it "removes the chat and keeps it out once the filter is asked for (filter up: #{healthy})" do
      allow_any_instance_of(Monadic::Utils::Privacy::PresidioBackend).to receive(:health).and_return(healthy)
      allow(host).to receive(:send_privacy_state)
      session = chat_session(marker, generation: 1)
      sync(session)
      expect(store.get(session[:chat_id])).not_to be_nil

      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
      expect(store.get(session[:chat_id])).to be_nil
      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => false })
      sync(session)
      expect(store.get(session[:chat_id])).to be_nil
      store.close
      expect(stored_bytes).not_to include(marker)
    end
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
end
