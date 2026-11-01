# frozen_string_literal: true

# PRIVACY_TOGGLE handler: backend-authoritative session toggle.
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

RSpec.describe 'WebSocketHelper PRIVACY_TOGGLE' do
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

    it 'sends privacy_toggle_ack{ enabled: true, error: nil } followed by privacy_state' do
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => true })
      # The handler emits the ack first (frontend confirms toggle state),
      # then a privacy_state push so the indicator becomes visible without
      # waiting for the next assistant turn.
      expect(harness.sent.size).to eq(2)
      expect(harness.sent[0]).to include('type' => 'privacy_toggle_ack', 'enabled' => true, 'error' => nil)
      expect(harness.sent[1]).to include('type' => 'privacy_state', 'enabled' => true, 'registry_count' => 0)
    end
  end

  # A container that does not answer stays off either way; the reason
  # says whether it is still starting (it starts when an app that needs it
  # is chosen) or not coming up.
  context 'when the user enables privacy but the container does not answer' do
    let(:deps) { Monadic::Utils::ContainerDependencies }

    before do
      require_relative '../../../../lib/monadic/utils/container_dependencies'
      allow_any_instance_of(Monadic::Utils::Privacy::PresidioBackend).to receive(:health).and_return(false)
    end

    def toggle_on
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => true })
      harness.sent.last
    end

    it 'keeps backend session state false to avoid silent unmasked sends, and drops a cached pipeline' do
      allow(deps).to receive_messages(starting?: false, container_running?: false)
      session[:_privacy_pipeline] = double('Pipeline')
      toggle_on
      expect(session[:_privacy_session_enabled]).to be false
      expect(session.key?(:_privacy_pipeline)).to be false
    end

    it 'says the container is starting when its start is scheduled or it is running' do
      allow(deps).to receive_messages(starting?: true, container_running?: false)
      expect(toggle_on).to include('type' => 'privacy_toggle_ack', 'enabled' => false, 'error' => 'privacy_container_starting')
      allow(deps).to receive_messages(starting?: false, container_running?: true)
      expect(toggle_on).to include('error' => 'privacy_container_starting')
    end

    it 'says the container cannot be reached when it is not coming up' do
      allow(deps).to receive_messages(starting?: false, container_running?: false)
      expect(toggle_on).to include('type' => 'privacy_toggle_ack', 'enabled' => false, 'error' => 'privacy_container_unreachable')
    end
  end

  describe 'services scheduled to start' do
    let(:deps) { Monadic::Utils::ContainerDependencies }

    before { require_relative '../../../../lib/monadic/utils/container_dependencies' }

    it 'stay starting until every start that scheduled them has handled them' do
      deps.mark_starting(%i[privacy], true)
      deps.mark_starting(%i[privacy], true)
      deps.mark_starting(%i[privacy], false)
      expect(deps.starting?(:privacy)).to be true
      deps.mark_starting(%i[privacy], false)
      expect(deps.starting?(:privacy)).to be false
    end

    it 'are not left marked when the start cannot begin' do
      stub_const('APPS', { 'PrivApp' => double(settings: {}) })
      allow(deps).to receive(:required_services).and_return(%i[privacy])
      allow(Thread).to receive(:new).and_raise(ThreadError, 'cannot create thread')
      expect { deps.ensure_services_async('PrivApp') }.to raise_error(ThreadError)
      expect(deps.starting?(:privacy)).to be false
    end

    it 'are seen as starting from the moment they are scheduled until each is handled' do
      gate = Queue.new
      stub_const('APPS', { 'PrivApp' => double(settings: {}) })
      allow(deps).to receive(:required_services).and_return(%i[qdrant privacy])
      allow(deps).to receive(:container_running?).and_return(false)
      allow(deps).to receive(:start_service) { |service| gate.pop if service == :qdrant; :started }
      deps.ensure_services_async('PrivApp')
      expect(deps.starting?(:privacy)).to be true # still waiting behind qdrant
      gate << :go
      deadline = Time.now + 2
      sleep 0.01 while deps.starting?(:privacy) && Time.now < deadline
      expect(deps.starting?(:privacy)).to be false
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

    it 'follows the ack with a privacy_state{ enabled: false } so the indicator hides immediately' do
      harness.send(:handle_ws_privacy_toggle, connection, session, { 'enabled' => false })
      expect(harness.sent.size).to eq(2)
      expect(harness.sent[1]).to include('type' => 'privacy_state', 'enabled' => false)
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
