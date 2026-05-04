# frozen_string_literal: true

# PRIVACY_TOGGLE handler (Phase 3): backend-authoritative session toggle.
#
# The frontend sends PRIVACY_TOGGLE { enabled: bool } and trusts the
# backend's privacy_toggle_ack reply as the source of truth. The handler
# must probe the privacy container's health before accepting an enable,
# and must surface a clear error to the frontend when the container is
# down so the toggle can be reverted visually. A separate message type
# from privacy_state avoids races with unrelated indicator updates
# (app change / reset / import all emit privacy_state).

require_relative '../../../../lib/monadic/utils/websocket/privacy_handler'
require_relative '../../../../lib/monadic/utils/privacy/presidio_backend'

RSpec.describe 'WebSocketHelper PRIVACY_TOGGLE (Phase 3)' do
  let(:harness_class) do
    Class.new do
      include WebSocketHelper
      attr_reader :sent

      def initialize
        @sent = []
      end

      def send_to_client(_connection, payload)
        @sent << payload
      end
    end
  end

  let(:harness) { harness_class.new }
  let(:connection) { Object.new }
  let(:session) { {} }

  context 'when the user enables privacy and the container is healthy' do
    before do
      allow_any_instance_of(Monadic::Utils::Privacy::PresidioBackend)
        .to receive(:health).and_return(true)
    end

    it 'sets backend session state to true' do
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => true })
      expect(session[:_privacy_session_enabled]).to be true
    end

    it 'sends privacy_toggle_ack{ enabled: true, error: nil }' do
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => true })
      expect(harness.sent.size).to eq(1)
      expect(harness.sent.first).to include('type' => 'privacy_toggle_ack', 'enabled' => true, 'error' => nil)
    end
  end

  context 'when the user enables privacy but the container is unreachable' do
    before do
      allow_any_instance_of(Monadic::Utils::Privacy::PresidioBackend)
        .to receive(:health).and_return(false)
    end

    it 'keeps backend session state false to avoid silent unmasked sends' do
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => true })
      expect(session[:_privacy_session_enabled]).to be false
    end

    it 'replies with the privacy_container_unreachable error' do
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => true })
      msg = harness.sent.first
      expect(msg['type']).to eq('privacy_toggle_ack')
      expect(msg['enabled']).to be false
      expect(msg['error']).to eq('privacy_container_unreachable')
    end

    it 'drops any cached pipeline so a stale enabled state cannot persist' do
      session[:_privacy_pipeline] = double('Pipeline')
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => true })
      expect(session.key?(:_privacy_pipeline)).to be false
    end
  end

  context 'when the user disables privacy' do
    before do
      session[:_privacy_session_enabled] = true
      session[:_privacy_pipeline] = double('Pipeline')
    end

    it 'flips backend state off and clears the cached pipeline' do
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => false })
      expect(session[:_privacy_session_enabled]).to be false
      expect(session.key?(:_privacy_pipeline)).to be false
    end

    it 'does not require a health check to disable (no probe call)' do
      expect_any_instance_of(Monadic::Utils::Privacy::PresidioBackend).not_to receive(:health)
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => false })
    end

    it 'sends privacy_toggle_ack{ enabled: false, error: nil }' do
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => false })
      expect(harness.sent.first).to include('type' => 'privacy_toggle_ack', 'enabled' => false, 'error' => nil)
    end
  end

  context 'with truthy variants of the enabled flag' do
    before do
      allow_any_instance_of(Monadic::Utils::Privacy::PresidioBackend)
        .to receive(:health).and_return(true)
    end

    it 'accepts the literal string "true" alongside the boolean' do
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => 'true' })
      expect(session[:_privacy_session_enabled]).to be true
    end

    it 'treats any other value as disable (defensive)' do
      session[:_privacy_session_enabled] = true
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => 'maybe' })
      expect(session[:_privacy_session_enabled]).to be false
    end
  end
end
