# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'securerandom'
require 'logger'
require_relative '../../../lib/monadic/history'
require_relative '../../../lib/monadic/history/private_output'
require_relative '../../../lib/monadic/workspace'
require_relative '../../../lib/monadic/utils/privacy/egress_guard'
require_relative '../../../lib/monadic/utils/extra_logger'
require_relative '../../../lib/monadic/shell'
require_relative '../../../lib/monadic/utils/websocket/privacy_handler'
require_relative '../../../lib/monadic/utils/privacy/presidio_backend'

# Nothing of a Private chat's work is written to the server's logs: the
# extra log, the command log, or what the process prints. Work for a normal
# chat is logged as before (each check has that positive control).
RSpec.describe 'The logs and the work of a Private chat' do
  let(:policy) { Monadic::History::Policy }
  let(:chat_key) { Monadic::Workspace::Chats::SESSION_KEY }
  let(:marker) { "MARK#{SecureRandom.hex(16)}" }

  def chat(private: false)
    session = { chat_id: Monadic::Workspace::Ids.generate(:chat), messages: [], parameters: {} }
    policy.mark_private!(session) if private
    session
  end

  # The work runs as a connection's does: the chat it started in is kept for
  # the fibers and threads it starts.
  def working_for(session)
    Fiber.new(storage: {}) do
      Monadic::Utils::Privacy::EgressGuard.for_chat(session)
      yield
    end.resume
  end

  around do |example|
    saved = Thread.current[:rack_session]
    Thread.current[:rack_session] = nil
    example.run
  ensure
    Thread.current[:rack_session] = saved
  end

  describe 'whether the work is for a Private chat' do
    it 'follows the chat the work started in, into the threads it starts' do
      expect(working_for(chat) { policy.current_work_private? }).to be(false)
      expect(working_for(chat(private: true)) { policy.current_work_private? }).to be(true)
      expect(working_for(chat(private: true)) { Thread.new { policy.current_work_private? }.value }).to be(true)
    end

    it 'stays Private for work of a Private chat after the tab moved to a new chat' do
      session = chat(private: true)
      old_id = session[chat_key]
      result = working_for(session) do
        session.delete(policy::SESSION_KEY)
        session[chat_key] = Monadic::Workspace::Ids.generate(:chat)
        policy.current_work_private?
      end
      expect(result).to be(true)
      expect(policy.known_private?(old_id)).to be(true)
    end
  end

  describe 'the extra log' do
    let(:dir) { Dir.mktmpdir('private-log') }
    let(:log) { File.join(dir, 'extra.log') }

    before do
      Monadic::Utils::ExtraLogger.reset!
      stub_const('MonadicApp::EXTRA_LOG_FILE', log)
      allow(Monadic::Utils::ExtraLogger).to receive(:enabled?).and_return(true)
    end

    after do
      Monadic::Utils::ExtraLogger.reset!
      FileUtils.rm_rf(dir)
    end

    it 'writes nothing of a Private chat and goes on for a normal one' do
      working_for(chat(private: true)) do
        Monadic::Utils::ExtraLogger.log("private #{marker}")
        Monadic::Utils::ExtraLogger.log_json('query', { 'text' => marker })
        Thread.new { Monadic::Utils::ExtraLogger.log_raw("thread #{marker}") }.join
      end
      expect(File.exist?(log) ? File.read(log) : '').not_to include(marker)

      working_for(chat) { Monadic::Utils::ExtraLogger.log("normal #{marker}") }
      expect(File.read(log)).to include("normal #{marker}")
    end
  end

  describe 'the command log' do
    let(:dir) { Dir.mktmpdir('private-command-log') }
    let(:log) { File.join(dir, 'command.log') }

    before { allow(Monadic::Shell).to receive(:command_log_file).and_return(log) }
    after { FileUtils.rm_rf(dir) }

    it 'writes nothing of a Private chat and goes on for a normal one' do
      working_for(chat(private: true)) { Monadic::Shell.log_invocation(['echo', marker], marker, '') }
      expect(File.exist?(log) ? File.read(log) : '').not_to include(marker)

      working_for(chat) { Monadic::Shell.log_invocation(['echo', marker], marker, '') }
      expect(File.read(log)).to include(marker)
    end
  end

  describe 'what the process prints' do
    it 'prints nothing of a Private chat, from the chat or a thread it started' do
      reader, writer = IO.pipe
      Monadic::History::PrivateOutput.install!([writer])
      logger = Logger.new(writer)
      working_for(chat(private: true)) do
        writer.puts("private #{marker}")
        logger.info("logger #{marker}")
        Thread.new { writer.print("thread #{marker}\n") }.join
      end
      working_for(chat) { writer.puts("normal #{marker}") }
      writer.close
      printed = reader.read
      expect(printed).to eq("normal #{marker}\n")
    end
  end

  describe 'turning the filter off before the chat begins' do
    let(:host) do
      Class.new do
        include WebSocketHelper
        def sent = (@sent ||= [])
        def send_to_client(_connection, payload) = sent << payload
        def sync_session_state! = nil
        def send_privacy_state(*) = nil
      end.new
    end

    before { allow_any_instance_of(Monadic::Utils::Privacy::PresidioBackend).to receive(:health).and_return(true) }

    it 'makes the chat a normal one again, but not once it has begun' do
      session = chat
      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
      expect(host.sent.last).to include('private' => true)
      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => false })
      expect(host.sent.last).to include('private' => false)
      expect(policy.private?(session)).to be(false)
      expect(policy.known_private?(session[chat_key])).to be(false)

      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
      session[:messages] << { 'role' => 'system', 'text' => 'You are helpful.' }
      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => false })
      expect(host.sent.last).to include('private' => true)
      expect(policy.private?(session)).to be(true)
    end

    it 'changes neither the filter nor Private once a Private chat has begun, even with its messages removed' do
      session = chat
      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
      session[:messages] << { 'role' => 'system', 'text' => 'You are helpful.' }
      policy.note_begun!(session)

      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => false })
      expect(host.sent.last).to include('enabled' => true, 'error' => 'privacy_chat_started', 'private' => true)
      expect(session[:_privacy_session_enabled]).to be(true)

      session[:messages].clear
      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => false })
      expect(host.sent.last).to include('enabled' => true, 'private' => true)
      expect(policy.private?(session)).to be(true)
      expect(policy.known_private?(session[chat_key])).to be(true)

      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
      expect(host.sent.last).to include('enabled' => true, 'error' => nil, 'private' => true)
    end

    it 'keeps the chat Private when the filter could not be started' do
      allow_any_instance_of(Monadic::Utils::Privacy::PresidioBackend).to receive(:health).and_return(false)
      session = chat
      host.send(:handle_ws_privacy_toggle, nil, session, { 'enabled' => true })
      expect(host.sent.last).to include('enabled' => false, 'private' => true)
      expect(policy.private?(session)).to be(true)
    end
  end
end
