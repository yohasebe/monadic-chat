# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/utils/websocket'
require_relative '../../../lib/monadic/utils/container_dependencies'

RSpec.describe 'Per-chat workspaces' do
  around do |example|
    Dir.mktmpdir('workspace-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, 'ledger.json')) }
  let(:ids) { Monadic::Workspace::Ids }
  let(:chats) { Monadic::Workspace::Chats }
  let(:folders) { Monadic::Workspace::Folders }

  describe Monadic::Workspace::Ids do
    it 'issues prefixed lowercase ids that it recognises' do
      chat = ids.generate(:chat)
      workspace = ids.generate(:workspace)
      expect(chat).to match(/\Ac_[a-z0-9]{16}\z/)
      expect(workspace).to match(/\Aw_[a-z0-9]{16}\z/)
      expect(ids.valid?(:chat, chat)).to be true
      expect(ids.valid?(:workspace, chat)).to be false
    end

    it 'rejects anything it did not issue' do
      ['', nil, 'c_short', 'c_ABCDEFGHIJKLMNOP', 'c_abcdefghijklmnop/..', "c_abcdefghijklmnop\n", 42].each do |value|
        expect(ids.valid?(:chat, value)).to be(false), value.inspect
      end
    end
  end

  describe 'Environment.state_path' do
    it 'is outside the shared folder in both modes' do
      allow(Monadic::Utils::Environment).to receive(:state_path).and_call_original
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(true)
      expect(Monadic::Utils::Environment.state_path).to eq('/monadic/state')
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      expect(Monadic::Utils::Environment.state_path).to eq(File.join(Dir.home, 'monadic', 'state'))
    end
  end

  describe Monadic::Workspace::Chats do
    it 'issues a chat once and keeps it' do
      session = {}
      first = chats.current(session)
      expect(chats.current(session)).to eq(first)
    end

    it 'starts a new chat on request' do
      session = {}
      first = chats.current(session)
      expect(chats.start_new!(session)).not_to eq(first)
    end

    it 'resumes an issued id and replaces anything else' do
      session = {}
      saved = ids.generate(:chat)
      expect(chats.resume!(session, saved)).to eq(saved)
      expect(chats.resume!(session, '../c_x')).not_to eq('../c_x')
      expect(ids.valid?(:chat, session[:chat_id])).to be true
      expect(chats.resume!(session, nil)).not_to eq(saved)
    end
  end

  describe Monadic::Workspace::Ledger do
    let(:chat_id) { ids.generate(:chat) }
    let(:workspace_id) { ids.generate(:workspace) }

    def register(**overrides)
      ledger.register_workspace(chat_id: chat_id, workspace_id: workspace_id, app_name: 'ChatOpenAI',
                                relative_dir: "conversations/x_#{workspace_id}", **overrides)
    end

    it 'records a workspace under its chat and reads it back from a new instance' do
      register
      reopened = Monadic::Workspace::Ledger.new(ledger.path)
      record = reopened.workspace_for_chat(chat_id)
      expect(record).to include(workspace_id: workspace_id, chat_id: chat_id, app_name: 'ChatOpenAI')
      expect(record[:relative_dir]).to eq("conversations/x_#{workspace_id}")
      expect(reopened.schema_version).to eq(1)
    end

    it 'keeps the ledger out of the shared folder' do
      register
      expect(File.exist?(ledger.path)).to be true
      expect(ledger.path).not_to start_with(@data)
    end

    it 'refuses a second workspace for the same chat' do
      register
      expect { register(workspace_id: ids.generate(:workspace)) }
        .to raise_error(Monadic::Workspace::Ledger::Conflict)
    end

    it 'refuses a reused workspace id or folder' do
      register
      expect { register(chat_id: ids.generate(:chat)) }.to raise_error(Monadic::Workspace::Ledger::Conflict)
      expect do
        register(chat_id: ids.generate(:chat), workspace_id: ids.generate(:workspace),
                 relative_dir: "conversations/x_#{workspace_id}")
      end.to raise_error(Monadic::Workspace::Ledger::Conflict)
    end

    it 'keeps the record readable only by the user' do
      register
      expect(File.stat(ledger.path).mode & 0o777).to eq(0o600)
    end

    it 'stops on a damaged or newer ledger instead of starting over' do
      File.write(ledger.path, '{not json')
      expect { ledger.workspace_for_chat(chat_id) }.to raise_error(Monadic::Workspace::Ledger::Unreadable)
      expect { register }.to raise_error(Monadic::Workspace::Ledger::Unreadable)
      expect(File.read(ledger.path)).to eq('{not json')

      File.write(ledger.path, JSON.generate('schema_version' => 99))
      expect { ledger.workspace_for_chat(chat_id) }.to raise_error(Monadic::Workspace::Ledger::Unreadable, /newer/)
    end

    it 'leaves no temporary files behind' do
      register
      expect(Dir.children(File.dirname(ledger.path)).sort).to eq(['ledger.json', 'ledger.json.lock'])
    end

    it 'stores only relative folders and only ids it issued' do
      expect { register(relative_dir: '/abs/monadic/data/x') }.to raise_error(ArgumentError)
      expect { register(relative_dir: 'conversations/../../x') }.to raise_error(ArgumentError)
      expect { register(chat_id: 'tab-1234') }.to raise_error(ArgumentError)
    end
  end

  describe Monadic::Workspace::Folders do
    let(:now) { Time.utc(2026, 10, 9, 10, 15, 30) }

    it 'creates the folder on first need, named for people and recorded for the server' do
      session = {}
      result = folders.ensure!(session, app_name: 'VideoDescriberOpenAI', ledger: ledger, now: now)

      expect(result[:status]).to eq(:ready)
      expect(result[:relative_dir]).to match(%r{\Aconversations/20261009-101530_video-describer-open-ai_w_[a-z0-9]{16}\z})
      expect(result[:relative_dir]).to end_with(result[:workspace_id])
      %w[inputs work artifacts].each do |sub|
        expect(File.directory?(File.join(result[:path], sub))).to be(true), sub
      end
      expect(ledger.workspace_for_chat(session[:chat_id])[:workspace_id]).to eq(result[:workspace_id])
    end

    it 'gives the same folder to the same chat and a new one after a new chat' do
      session = {}
      first = folders.ensure!(session, app_name: 'ChatOpenAI', ledger: ledger, now: now)
      again = folders.ensure!(session, app_name: 'ChatClaude', ledger: ledger, now: now + 60)
      expect(again[:workspace_id]).to eq(first[:workspace_id])

      chats.start_new!(session)
      other = folders.ensure!(session, app_name: 'ChatOpenAI', ledger: ledger, now: now)
      expect(other[:workspace_id]).not_to eq(first[:workspace_id])
      expect(File.directory?(first[:path])).to be true
    end

    it 'creates one folder when one chat asks from several threads at once' do
      session = { chat_id: ids.generate(:chat) }
      results = Array.new(8) { Thread.new { folders.ensure!(session, app_name: 'ChatOpenAI', ledger: ledger, now: now) } }.map(&:value)
      expect(results.map { |r| r[:workspace_id] }.uniq.size).to eq(1)
      expect(Dir.children(File.join(@data, 'conversations')).size).to eq(1)
    end

    it 'reports a removed or renamed folder as missing instead of recreating it' do
      session = {}
      result = folders.ensure!(session, app_name: 'ChatOpenAI', ledger: ledger, now: now)
      File.rename(result[:path], "#{result[:path]}-renamed")

      again = folders.ensure!(session, app_name: 'ChatOpenAI', ledger: ledger, now: now)
      expect(again[:status]).to eq(:missing)
      expect(File.exist?(result[:path])).to be false
    end

    it 'looks up without creating' do
      session = {}
      expect(folders.lookup(session, ledger: ledger)).to be_nil
      chats.current(session)
      expect(folders.lookup(session, ledger: ledger)).to be_nil
      expect(File.exist?(File.join(@data, 'conversations'))).to be false
      folders.ensure!(session, app_name: 'ChatOpenAI', ledger: ledger, now: now)
      expect(folders.lookup(session, ledger: ledger)[:status]).to eq(:ready)
    end

    it 'refuses a conversations entry that links elsewhere' do
      outside = File.join(File.dirname(@data), 'outside')
      FileUtils.mkdir_p(outside)
      File.symlink(outside, File.join(@data, 'conversations'))

      expect { folders.ensure!({}, app_name: 'ChatOpenAI', ledger: ledger, now: now) }
        .to raise_error(Monadic::Workspace::Folders::Unavailable)
      expect(Dir.children(outside)).to be_empty
    end

    it 'reports a missing shared folder without a path in the message' do
      FileUtils.rm_rf(@data)
      expect { folders.ensure!({}, app_name: 'ChatOpenAI', ledger: ledger, now: now) }
        .to raise_error(Monadic::Workspace::Folders::Unavailable) { |e| expect(e.message).not_to include(@data) }
    end

    it 'turns any app name into a short safe slug' do
      expect(folders.slug('CodeInterpreterOpenAI')).to eq('code-interpreter-open-ai')
      expect(folders.slug('../../etc')).to eq('etc')
      expect(folders.slug('日本語')).to eq('chat')
      expect(folders.slug(nil)).to eq('chat')
      expect(folders.slug('A' * 80).length).to be <= Monadic::Workspace::Folders::SLUG_MAX
    end
  end

  # The real handlers, not a copy of their logic.
  describe 'chat boundaries in the WebSocket handlers' do
    let(:host) do
      Class.new { include WebSocketHelper }.new.tap do |h|
        allow(h).to receive(:sync_session_state!)
        allow(h).to receive(:send_or_broadcast)
      end
    end

    def base_session(app)
      { messages: [], parameters: { 'app_name' => app }, chat_id: ids.generate(:chat) }
    end

    it 'starts a new chat on Reset' do
      session = base_session('ChatOpenAI')
      before_id = session[:chat_id]
      host.send(:handle_ws_reset, session)
      expect(ids.valid?(:chat, session[:chat_id])).to be true
      expect(session[:chat_id]).not_to eq(before_id)
    end

    it 'starts a new chat when the app changes and keeps it otherwise' do
      allow(Monadic::Utils::ContainerDependencies).to receive(:ensure_services_async)
      session = base_session('ChatOpenAI')
      before_id = session[:chat_id]

      host.send(:handle_ws_update_params, nil, { 'params' => { 'app_name' => 'ChatOpenAI', 'temperature' => 0.5 } }, session)
      expect(session[:chat_id]).to eq(before_id)

      host.send(:handle_ws_update_params, nil, { 'params' => { 'app_name' => 'VideoDescriberOpenAI' } }, session)
      expect(session[:chat_id]).not_to eq(before_id)
    end
  end

  # The real connection handler, with the socket replaced by one that closes
  # at once: what a tab gets when it connects and reconnects.
  describe 'connecting a tab' do
    let(:host) do
      Class.new { include WebSocketHelper }.new.tap do |h|
        allow(h).to receive(:handle_load_message)
        allow(h).to receive(:teardown_sts_session)
      end
    end

    before do
      closed_socket = double('connection', read: nil)
      allow(Async::WebSocket::Adapters::Rack).to receive(:open) { |_env, &block| block.call(closed_socket) }
    end

    def connect(tab_id)
      rack_session = {}
      host.handle_websocket_connection({ 'rack.session' => rack_session, 'QUERY_STRING' => "tab_id=#{tab_id}" })
      rack_session[:chat_id]
    end

    it 'continues the chat when the same tab reconnects, and not across tabs' do
      tab = "tab-#{SecureRandom.hex(4)}"
      first = connect(tab)
      expect(ids.valid?(:chat, first)).to be true
      expect(connect(tab)).to eq(first)
      expect(connect("tab-#{SecureRandom.hex(4)}")).not_to eq(first)
    end

    it 'starts a new chat when the saved id is not one it issued' do
      tab = "tab-#{SecureRandom.hex(4)}"
      WebSocketHelper.update_session_state(tab, messages: [], parameters: {}, chat_id: 'c_../../etc')
      expect(ids.valid?(:chat, connect(tab))).to be true
    end
  end

  # A tab reconnecting can have its old and new connections open at once.
  describe 'an old connection closing after the new one changed the chat' do
    let(:tab) { "tab-#{SecureRandom.hex(4)}" }
    let(:host) { Class.new { include WebSocketHelper }.new }

    # The real save, run as the given connection would run it.
    def save_as(connection_session)
      Thread.current[:websocket_session_id] = tab
      Thread.current[:rack_session] = connection_session
      host.send(:sync_session_state!)
    ensure
      Thread.current[:websocket_session_id] = nil
      Thread.current[:rack_session] = nil
    end

    it 'keeps the new chat when the replaced connection saves last' do
      old_chat = ids.generate(:chat)
      a = { messages: [], parameters: {}, chat_id: old_chat, _ws_generation: WebSocketHelper.claim_session_state(tab) }
      save_as(a)
      b = { messages: [], parameters: {}, chat_id: old_chat, _ws_generation: WebSocketHelper.claim_session_state(tab) }
      host.send(:handle_ws_reset, b.tap { Thread.current[:websocket_session_id] = tab; Thread.current[:rack_session] = b })
      new_chat = b[:chat_id]
      expect(new_chat).not_to eq(old_chat)
      expect(WebSocketHelper.fetch_session_state(tab)[:chat_id]).to eq(new_chat)

      save_as(a) # the old connection closes
      expect(WebSocketHelper.fetch_session_state(tab)[:chat_id]).to eq(new_chat)
    ensure
      Thread.current[:websocket_session_id] = nil
      Thread.current[:rack_session] = nil
    end

    it 'lets the newest connection keep saving' do
      a = { messages: [], parameters: {}, chat_id: ids.generate(:chat), _ws_generation: WebSocketHelper.claim_session_state(tab) }
      save_as(a)
      a[:messages] << { 'text' => 'later' }
      save_as(a)
      expect(WebSocketHelper.fetch_session_state(tab)[:messages].size).to eq(1)
    end
  end

  describe 'tab state across reconnects' do
    let(:tab) { "tab-#{SecureRandom.hex(4)}" }

    it 'keeps the chat id when a caller does not carry one' do
      chat_id = ids.generate(:chat)
      WebSocketHelper.update_session_state(tab, messages: [], parameters: {}, chat_id: chat_id)
      WebSocketHelper.update_session_state(tab, messages: [{ 'text' => 'x' }], parameters: {})
      expect(WebSocketHelper.fetch_session_state(tab)[:chat_id]).to eq(chat_id)
    end

    it 'moves to the chat a caller sets' do
      first = ids.generate(:chat)
      second = ids.generate(:chat)
      WebSocketHelper.update_session_state(tab, messages: [], parameters: {}, chat_id: first)
      WebSocketHelper.update_session_state(tab, messages: [], parameters: {}, chat_id: second)
      expect(WebSocketHelper.fetch_session_state(tab)[:chat_id]).to eq(second)
    end
  end
end
