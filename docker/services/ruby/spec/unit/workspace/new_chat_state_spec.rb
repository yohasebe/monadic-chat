# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'rack'
require 'rack/session/pool'
require_relative '../../../lib/monadic/utils/unlimited_session_store'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/utils/websocket'
require_relative '../../../lib/monadic/utils/container_dependencies'

# A new chat (Reset, another app, an imported conversation) must not inherit
# what the previous chat left in the session: tools keep their last image,
# notebook or output file there, and the next chat's tools read them back.
RSpec.describe 'What a new chat keeps from the session' do
  let(:ids) { Monadic::Workspace::Ids }

  # The session object of a request through the same middleware as config.ru
  # (not a Hash).
  def real_session(values)
    made = nil
    inner = lambda do |env|
      made = env['rack.session']
      values.each { |k, v| made[k] = v }
      [200, {}, ['ok']]
    end
    Rack::Session::CappedPool.new(inner, key: 'monadic.session').call(Rack::MockRequest.env_for('/'))
    made
  end

  # Left by the previous chat's tools and handlers, as the code writes them.
  def leftovers
    {
      gemini3_last_image: 'img_1.png', openai_last_image: 'img_2.png', grok_last_video_filename: 'v.mp4',
      current_notebook_filename: 'nb.ipynb', last_notebook_url: 'http://localhost:8889/nb.ipynb',
      code_interpreter_last_output_file: 'plot.png', gemini3_duplicate_check: { 'hash' => 1 },
      openai_file_inputs_cache: { 'h' => 'file_1' }, verification_history: [{ attempt: 1 }],
      proposed_plan: { status: 'proposed' }, substitution_state: { 'vocab' => {} },
      tool_html_fragments: ['<p>x</p>'], pending_tool_images: ['img_3.png'],
      monadic_state: { privacy: { registry: { 'Alice' => '<<PERSON_1>>' } } },
      progressive_tools: { 'ChatOpenAI' => { unlocked: ['x'] } },
      _privacy_pipeline: Object.new, _privacy_session_enabled: true, _substitution_pipeline: Object.new,
      grok_compaction: { 'blob' => 'x' }, _model_fallback_notified: true, error_patterns: { similar_count: 2 },
      tool_call_sequence: [{ name: 'run' }], call_depth_per_turn: 3, obj: { 'message' => 'x' }, error: 'boom'
    }
  end

  def connection_values
    { websocket_session_id: 'tab-1', version: '1.0.0', docker: true, _ws_generation: 4,
      runtime_settings: { language: 'ja' } }
  end

  describe 'Chats.begin_new!' do
    it 'drops every key the previous chat left and keeps the connection' do
      session = real_session(leftovers.merge(connection_values)
                                      .merge(messages: [{ 'text' => 'hi' }], parameters: { 'app_name' => 'ChatOpenAI' },
                                             chat_id: ids.generate(:chat)))
      before_id = session[:chat_id]
      Monadic::Workspace::Chats.begin_new!(session)

      leftovers.each_key { |key| expect(session.key?(key)).to be(false), "#{key} carried over" }
      connection_values.each { |key, value| expect(session[key]).to eq(value) }
      expect(session[:parameters]).to eq('app_name' => 'ChatOpenAI') # left to the caller
      expect(ids.valid?(:chat, session[:chat_id])).to be true
      expect(session[:chat_id]).not_to eq(before_id)
    end

    it 'drops a key it has never heard of' do
      session = real_session(parameters: {}, messages: [], some_future_tool_last_result: 'x')
      Monadic::Workspace::Chats.begin_new!(session)
      expect(session.key?(:some_future_tool_last_result)).to be false
    end

    it 'keeps the keys of the session middleware' do
      session = real_session(parameters: {}, messages: [], 'csrf' => 'token', 'tracking' => { 'HTTP_USER_AGENT' => 'x' })
      Monadic::Workspace::Chats.begin_new!(session)
      expect(session['csrf']).to eq('token')
      expect(session['tracking']).to eq('HTTP_USER_AGENT' => 'x')
    end

    it 'works the same on a Hash given in place of a session' do
      session = leftovers.merge(connection_values).merge(messages: [], parameters: {})
      Monadic::Workspace::Chats.begin_new!(session)
      leftovers.each_key { |key| expect(session.key?(key)).to be(false), "#{key} carried over" }
      connection_values.each { |key, value| expect(session[key]).to eq(value) }
    end
  end

  describe 'in the WebSocket handlers' do
    let(:host) do
      Class.new { include WebSocketHelper }.new.tap do |h|
        allow(h).to receive(:sync_session_state!)
        allow(h).to receive(:send_or_broadcast)
      end
    end

    it 'tells the page that the Privacy Filter is off for the new chat' do
      session = real_session(messages: [{ 'text' => 'hi' }], parameters: { 'app_name' => 'MailComposerOpenAI' },
                             _privacy_session_enabled: true)
      sent = []
      allow(host).to receive(:send_or_broadcast) { |json, _| sent << JSON.parse(json) }
      host.send(:handle_ws_reset, session)
      expect(sent).to include(include('type' => 'privacy_state', 'enabled' => false, 'registry_count' => 0))
      expect(session.key?(:_privacy_session_enabled)).to be false
    end

    it 'leaves nothing of the previous chat after Reset' do
      session = real_session(leftovers.merge(connection_values)
                                      .merge(messages: [{ 'text' => 'hi' }], parameters: { 'app_name' => 'ChatOpenAI' }))
      host.send(:handle_ws_reset, session)
      leftovers.each_key { |key| expect(session.key?(key)).to be(false), "#{key} carried over" }
      expect(session[:messages]).to be_empty
      expect(session[:websocket_session_id]).to eq('tab-1')
    end

    it 'leaves nothing of the previous app when the app changes, and keeps it otherwise' do
      allow(Monadic::Utils::ContainerDependencies).to receive(:ensure_services_async)
      allow(WebSocketHelper).to receive(:send_to_session)
      session = real_session(leftovers.merge(connection_values)
                                      .merge(messages: [], parameters: { 'app_name' => 'ImageGeneratorGemini' }))

      host.send(:handle_ws_update_params, nil, { 'params' => { 'app_name' => 'ImageGeneratorGemini', 'temperature' => 0.5 } }, session)
      expect(session[:gemini3_last_image]).to eq('img_1.png')

      host.send(:handle_ws_update_params, nil, { 'params' => { 'app_name' => 'ChatOpenAI' } }, session)
      leftovers.each_key { |key| expect(session.key?(key)).to be(false), "#{key} carried over" }
      expect(session[:parameters]['app_name']).to eq('ChatOpenAI')
    end
  end

  # The real connection handler, with a socket that closes at once, on the
  # session the cookie gives (shared by every tab, not updated by an open
  # connection).
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

    def connect(tab_id, cookie_session)
      host.handle_websocket_connection({ 'rack.session' => cookie_session, 'QUERY_STRING' => "tab_id=#{tab_id}" })
      cookie_session
    end

    it 'takes nothing of a chat from the cookie session' do
      tab = "tab-#{SecureRandom.hex(4)}"
      session = connect(tab, real_session(leftovers.merge(chat_id: ids.generate(:chat))))
      leftovers.each_key { |key| expect(session.key?(key)).to be(false), "#{key} came from the cookie" }
    end

    it 'gives a reconnecting tab its chat back, with what it had besides its messages' do
      tab = "tab-#{SecureRandom.hex(4)}"
      first = connect(tab, real_session({}))
      first[:current_notebook_filename] = 'nb.ipynb'
      first[:monadic_state] = { conversation_context: { 'topic' => 'x' } }
      Thread.current[:websocket_session_id] = tab
      Thread.current[:rack_session] = first
      host.send(:sync_session_state!)
      Thread.current[:websocket_session_id] = nil
      Thread.current[:rack_session] = nil

      again = connect(tab, real_session(gemini3_last_image: 'from-another-tab.png'))
      expect(again[:chat_id]).to eq(first[:chat_id])
      expect(again[:current_notebook_filename]).to eq('nb.ipynb')
      expect(again[:monadic_state]).to eq(conversation_context: { 'topic' => 'x' })
      expect(again.key?(:gemini3_last_image)).to be false

      other = connect("tab-#{SecureRandom.hex(4)}", real_session({}))
      expect(other.key?(:current_notebook_filename)).to be false
    ensure
      Thread.current[:websocket_session_id] = nil
      Thread.current[:rack_session] = nil
    end
  end

  # A tab reconnecting can have its old connection still running for a
  # moment: what it changes after the new one took the chat must not reach
  # the new one, and objects built for the old session are not handed on.
  describe 'the chat a tab saves between connections' do
    let(:tab) { "tab-#{SecureRandom.hex(4)}" }
    let(:host) { Class.new { include WebSocketHelper }.new }

    def save_as(connection_session)
      Thread.current[:websocket_session_id] = tab
      Thread.current[:rack_session] = connection_session
      host.send(:sync_session_state!)
    ensure
      Thread.current[:websocket_session_id] = nil
      Thread.current[:rack_session] = nil
    end

    it 'is a copy the old connection can no longer change' do
      old = { messages: [], parameters: {}, chat_id: ids.generate(:chat),
              monadic_state: { conversation_context: { 'topic' => 'kept' } },
              _ws_generation: WebSocketHelper.claim_session_state(tab) }
      save_as(old)
      WebSocketHelper.claim_session_state(tab) # the new connection
      restored = WebSocketHelper.fetch_session_state(tab)[:chat_state]
      old[:monadic_state][:conversation_context]['topic'] = 'late old reply'
      save_as(old)
      expect(restored[:monadic_state][:conversation_context]['topic']).to eq('kept')
      expect(WebSocketHelper.fetch_session_state(tab)[:chat_state][:monadic_state][:conversation_context]['topic']).to eq('kept')
    end

    it 'leaves out the pipelines built for the old session' do
      save_as({ messages: [], parameters: {}, chat_id: ids.generate(:chat), _privacy_session_enabled: true,
                _privacy_pipeline: Object.new, _substitution_pipeline: Object.new })
      saved = WebSocketHelper.fetch_session_state(tab)[:chat_state]
      expect(saved.keys.map(&:to_s)).to include('_privacy_session_enabled')
      expect(saved.keys.map(&:to_s)).not_to include('_privacy_pipeline', '_substitution_pipeline')
    end
  end

  describe 'imports waiting for their tab' do
    it 'keeps one per tab, a limited number in all, and none for a tab that closed' do
      first = WebSocketHelper.stage_import('tab-a', { messages: [] })
      second = WebSocketHelper.stage_import('tab-a', { messages: [] })
      expect(WebSocketHelper.take_import('tab-a', first)).to be_nil
      tokens = Array.new(WebSocketHelper::IMPORT_MAX + 1) { |i| WebSocketHelper.stage_import("tab-cap-#{i}", { n: i }) }
      expect(WebSocketHelper.take_import('tab-cap-0', tokens.first)).to be_nil
      expect(WebSocketHelper.take_import("tab-cap-#{WebSocketHelper::IMPORT_MAX}", tokens.last)).to eq(n: WebSocketHelper::IMPORT_MAX)
      kept = WebSocketHelper.stage_import('tab-b', { messages: [] })
      WebSocketHelper.drop_imports('tab-b')
      expect(WebSocketHelper.take_import('tab-b', kept)).to be_nil
      expect(second).to be_a(String)
    end
  end

  # The real connection handler reading a stale token: the reply running in
  # the tab is left alone.
  describe 'a token that is not there' do
    it 'does not stop the reply being written' do
      host = Class.new { include WebSocketHelper }.new
      allow(host).to receive(:handle_load_message)
      allow(host).to receive(:teardown_sts_session)
      reply = Thread.new { sleep 30 }
      allow(host).to receive(:handle_ws_streaming).and_return(reply)
      alive_after_import = nil
      reads = [{ 'message' => 'hello' }.to_json, { 'message' => 'IMPORT_APPLY', 'token' => 'stale' }.to_json]
      socket = double('connection', flush: nil)
      allow(socket).to receive(:write)
      allow(socket).to receive(:read) do
        next reads.shift unless reads.empty?

        alive_after_import = reply.alive?
        nil
      end
      allow(Async::WebSocket::Adapters::Rack).to receive(:open) { |_env, &block| block.call(socket) }
      host.handle_websocket_connection({ 'rack.session' => real_session({}), 'QUERY_STRING' => "tab_id=tab-#{SecureRandom.hex(4)}" })
      expect(alive_after_import).to be true
    ensure
      reply&.kill
    end
  end

  # The /load route of the app (through config.ru, with its session store)
  # reads the file and stages it for the tab; the tab's connection takes it
  # (IMPORT_APPLY) into its chat. Booted in a child process with its own
  # HOME, as the other route specs are, so nothing of the user's
  # configuration is read.
  describe 'importing a conversation' do
    def probe_script
      <<~'RUBY'
        require "rack"
        require "rack/mock_request"
        require "json"
        app, = Rack::Builder.parse_file("config.ru")
        tab = "tab-probe"
        conversation = { "parameters" => { "app_name" => "ChatOpenAI" },
                         "messages" => [{ "role" => "user", "text" => "hello", "mid" => "m1" }],
                         "session_context" => { "topic" => "imported" } }.to_json
        post = lambda do |tab_id|
          parts = ["--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"c.json\"\r\n" \
                   "Content-Type: application/json\r\n\r\n#{conversation}\r\n"]
          parts << "--B\r\nContent-Disposition: form-data; name=\"tab_id\"\r\n\r\n#{tab_id}\r\n" if tab_id
          body = parts.join + "--B--\r\n"
          res = Rack::MockRequest.new(app).post("http://localhost:4567/load",
                                                input: body, "CONTENT_TYPE" => "multipart/form-data; boundary=B",
                                                "HTTP_HOST" => "localhost:4567", "HTTP_ORIGIN" => "http://localhost:4567")
          JSON.parse(res.body)
        end
        without_tab = post.call(nil)
        staged = post.call(tab)

        # The tab's open connection, holding a previous chat.
        host = Class.new { include WebSocketHelper }.new
        old_chat = Monadic::Workspace::Ids.generate(:chat)
        # A real session object (keys kept as strings), as a connection has.
        live = nil
        Rack::Session::CappedPool.new(lambda { |env| live = env["rack.session"]; [200, {}, []] }, key: "probe")
                                 .call(Rack::MockRequest.env_for("/"))
        { messages: [{ "text" => "old" }], parameters: { "app_name" => "ChatOpenAI", "ui_language" => "ja" },
          chat_id: old_chat, gemini3_last_image: "img_1.png", current_notebook_filename: "nb.ipynb",
          _ws_generation: WebSocketHelper.claim_session_state(tab) }.each { |k, v| live[k] = v }
        sent = []
        connection = Object.new
        connection.define_singleton_method(:write) { |json| sent << JSON.parse(json)["type"] }
        connection.define_singleton_method(:flush) {}
        Thread.current[:websocket_session_id] = tab
        Thread.current[:rack_session] = live
        token = staged["import_token"]
        host.send(:handle_ws_import_apply, connection, { "token" => token }, live, WebSocketHelper.take_import(tab, token))
        again = []
        connection.define_singleton_method(:write) { |json| again << JSON.parse(json) }
        host.send(:handle_ws_import_apply, connection, { "token" => token }, live, WebSocketHelper.take_import(tab, token))
        stored = WebSocketHelper.fetch_session_state(tab)
        # The export reads the tab's chat from its open connection.
        WebSocketHelper.register_live_session(tab, live, live[:_ws_generation])
        export = lambda do |tab_id|
          JSON.parse(Rack::MockRequest.new(app).get("http://localhost:4567/monadic_state?tab_id=#{tab_id}",
                                                    "HTTP_HOST" => "localhost:4567").body)
        end
        exported = export.call(tab)
        # While the tab reconnects, from what it saved; a tab with nothing,
        # not from the cookie's session.
        WebSocketHelper.unregister_live_session(tab, live[:_ws_generation])
        exported_saved = export.call(tab)
        exported_unknown = export.call("tab-nobody")
        puts JSON.generate(
          "without_tab" => without_tab, "staged" => staged.keys,
          "keys" => live.keys.map(&:to_s), "real_session" => live.class.name, "messages" => live[:messages].map { |m| m["text"] },
          "ui_language" => live[:parameters]["ui_language"], "context" => live[:monadic_state] && live[:monadic_state][:conversation_context],
          "old_chat" => old_chat, "chat" => live[:chat_id], "stored_chat" => stored[:chat_id],
          "stored_messages" => stored[:messages].map { |m| m["text"] }, "sent" => sent,
          "second_try" => again.map { |m| [m["type"], m["success"]] }, "exported_context" => exported["session_context"],
          "exported_saved" => exported_saved["session_context"], "exported_unknown" => exported_unknown["monadic_state"]
        )
      RUBY
    end

    it 'is taken over by the tab, which starts a new chat holding none of the previous one' do
      root = File.expand_path('../../..', __dir__)
      out = Dir.mktmpdir('new-chat-load') do |home|
        stdout, stderr, status = Open3.capture3({ 'HOME' => home }, RbConfig.ruby, '-e', probe_script, chdir: root)
        raise "probe failed: #{stderr[-2000..]}" unless status.success?

        JSON.parse(stdout.lines.last)
      end
      expect(out['without_tab']['success']).to be false
      expect(out['staged']).to include('import_token')
      expect(out['real_session']).to include('SecureSessionHash')
      expect(out['keys']).not_to include('gemini3_last_image', 'current_notebook_filename')
      expect(out['messages']).to eq(['hello'])
      expect(out['ui_language']).to eq('ja')
      expect(out['context']).to eq('topic' => 'imported')
      expect(out['chat']).not_to eq(out['old_chat'])
      expect(out['stored_chat']).to eq(out['chat'])
      expect(out['stored_messages']).to eq(['hello'])
      expect(out['sent']).to include('parameters', 'past_messages', 'context_update', 'import_result')
      expect(out['second_try']).to eq([['import_result', false]]) # a staged import is taken once
      expect(out['exported_context']).to eq('topic' => 'imported')
      expect(out['exported_saved']).to eq('topic' => 'imported')
      expect(out['exported_unknown']).to be_nil
    end
  end
end
