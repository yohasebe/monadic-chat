# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/utils/websocket'

# The context each chat keeps (what its context panel shows).
RSpec.describe Monadic::Workspace::ChatContext do
  let(:chats) { Monadic::Workspace::Chats }
  let(:session) { {}.tap { |s| chats.start_new!(s) } }
  let(:chat) { { id: session[chats::SESSION_KEY], epoch: chats.epoch(session[chats::SESSION_KEY]) } }

  after { described_class::LOCK.synchronize { described_class::STORE.clear } }

  def add(to, text, at: chat)
    described_class.update(to, chat: at) { |c| described_class.add_texts(c, 'topics', [text], 1) }
  end

  it 'keeps the context it had when a change fails' do
    add(session, 'trips')
    add(session, 'maps')
    expect { described_class.update(session, chat: chat) { raise 'failed' } }.to raise_error('failed')

    current = described_class.current(session)
    expect(current.version).to eq(2)
    expect(current.context['topics'].map { |i| i['text'] }).to eq(%w[trips maps])
  end

  it 'keeps the context of a chat in use however many other chats change theirs' do
    add(session, 'trips')
    600.times do
      other = {}.tap { |s| chats.start_new!(s) }
      add(other, 'x', at: { id: other[chats::SESSION_KEY], epoch: 0 })
      described_class.read(session)
    end
    expect(described_class.current(session).version).to eq(1)
  end

  describe 'a chat no tab keeps any more' do
    around do |example|
      tabs = []
      @tabs = tabs
      example.run
    ensure
      tabs.each { |tab, generation| WebSocketHelper.unregister_live_session(tab, generation) }
    end

    def tab_with(saved)
      tab = "tab-#{SecureRandom.hex(4)}"
      generation = WebSocketHelper.claim_session_state(tab)
      WebSocketHelper.update_session_state(tab, messages: [], parameters: {}, chat_id: saved[chats::SESSION_KEY])
      [tab, generation]
    end

    it 'is forgotten when the tab state that kept it is dropped, while a chat open in a tab stays' do
      stub_const('WebSocketHelper::STATE_MAX_IDLE', 0)
      open = {}.tap { |s| chats.start_new!(s) }
      add(session, 'closed tab')
      add(open, 'open tab', at: { id: open[chats::SESSION_KEY], epoch: 0 })
      tab_with(session)
      open_tab, generation = tab_with(open)
      WebSocketHelper.register_live_session(open_tab, open, generation)
      @tabs << [open_tab, generation]

      old_work = chat
      WebSocketHelper.claim_session_state("tab-#{SecureRandom.hex(4)}") # drops the idle tab's state

      expect(described_class.read(session)).to be_nil
      expect(add(session, 'late', at: old_work)).to be_nil
      expect(described_class.read(session)).to be_nil
      expect(described_class.read(open)['topics'].map { |i| i['text'] }).to eq(['open tab'])
    end

    it 'is kept while a tab is taking it from the history' do
      stub_const('WebSocketHelper::STATE_MAX_IDLE', 0)
      add(session, 'being taken')
      tab_with(session)
      WebSocketHelper.reserve_chat(session[chats::SESSION_KEY])

      WebSocketHelper.claim_session_state("tab-#{SecureRandom.hex(4)}")

      expect(described_class.read(session)['topics'].map { |i| i['text'] }).to eq(['being taken'])
    ensure
      WebSocketHelper.release_chat(session[chats::SESSION_KEY])
    end
  end
end
