# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../../lib/monadic/utils/websocket'
require_relative '../../../../lib/monadic/utils/container_dependencies'

# Unit tests for the STS (speech-to-speech) audio routing decision in
# WebSocketHelper (websocket.rb). The STS bridge itself
# (lib/monadic/utils/websocket/sts_stream_handler.rb) is implemented by a
# parallel workstream; these specs stub the pinned interface names
# (sts_session_capable?, handle_sts_audio_chunk/commit/abort) and pin the
# three routing decisions plus the once-per-session privacy error:
#
#   1. :stt             — model is not STS-capable → legacy handlers
#   2. :sts             — model is STS-capable, privacy off → STS handlers
#   3. :privacy_blocked — model is STS-capable AND Privacy Filter is on
#                         → one error message per session, no audio routed
RSpec.describe "WebSocketHelper STS audio routing" do
  # Host including the helper with recording stubs for the pinned STS
  # interface (the real handler module does not exist yet).
  let(:host) do
    Class.new do
      include WebSocketHelper

      attr_reader :calls

      def initialize(sts_capable:)
        @sts_capable = sts_capable
        @calls = []
      end

      def sts_session_capable?(_session, _obj = nil)
        @sts_capable
      end

      def handle_sts_audio_chunk(_connection, _obj)
        @calls << :handle_sts_audio_chunk
      end

      def handle_sts_audio_commit(_connection, _obj)
        @calls << :handle_sts_audio_commit
      end

      def handle_sts_audio_abort(_connection, _obj)
        @calls << :handle_sts_audio_abort
      end

      def handle_sts_initiate(_connection, _obj)
        @calls << :handle_sts_initiate
      end
    end
  end

  # Fake connection capturing frames written by send_to_client.
  let(:writes) { [] }
  let(:connection) do
    c = Object.new
    writes_ref = writes
    c.define_singleton_method(:write) { |body| writes_ref << body }
    c.define_singleton_method(:flush) { nil }
    c
  end

  let(:obj) { { "message" => "AUDIO_CHUNK", "audio" => "AAAA" } }

  def make_session(privacy_toggle:, app_name: "VoiceChatOpenAI")
    {
      parameters: { "app_name" => app_name },
      _privacy_session_enabled: privacy_toggle
    }
  end

  def stub_apps(privacy_enabled:)
    app = double(:app, settings: { privacy: { enabled: privacy_enabled } })
    stub_const("APPS", { "VoiceChatOpenAI" => app })
  end

  describe "non-STS-capable model" do
    it "routes AUDIO_CHUNK to the legacy handler" do
      h = host.new(sts_capable: false)
      allow(h).to receive(:handle_audio_chunk) { h.calls << :handle_audio_chunk }
      h.send(:route_audio_event, connection, make_session(privacy_toggle: false), obj,
             sts_handler: :handle_sts_audio_chunk, fallback: :handle_audio_chunk)
      expect(h.calls).to eq([:handle_audio_chunk])
      expect(writes).to be_empty
    end

    it "never emits the privacy error even with the toggle on" do
      stub_apps(privacy_enabled: true)
      h = host.new(sts_capable: false)
      allow(h).to receive(:handle_audio_chunk) { h.calls << :handle_audio_chunk }
      h.send(:route_audio_event, connection, make_session(privacy_toggle: true), obj,
             sts_handler: :handle_sts_audio_chunk, fallback: :handle_audio_chunk)
      expect(h.calls).to eq([:handle_audio_chunk])
      expect(writes).to be_empty
    end
  end

  describe "STS-capable model without privacy" do
    it "routes AUDIO_CHUNK to the STS handler" do
      h = host.new(sts_capable: true)
      h.send(:route_audio_event, connection, make_session(privacy_toggle: false), obj,
             sts_handler: :handle_sts_audio_chunk, fallback: :handle_audio_chunk)
      expect(h.calls).to eq([:handle_sts_audio_chunk])
    end

    it "routes AUDIO_COMMIT to the STS handler" do
      h = host.new(sts_capable: true)
      h.send(:route_audio_event, connection, make_session(privacy_toggle: false), obj,
             sts_handler: :handle_sts_audio_commit, fallback: :handle_audio_commit)
      expect(h.calls).to eq([:handle_sts_audio_commit])
    end

    it "routes AUDIO_ABORT to the STS handler" do
      h = host.new(sts_capable: true)
      h.send(:route_audio_event, connection, make_session(privacy_toggle: false), obj,
             sts_handler: :handle_sts_audio_abort, fallback: :handle_audio_abort)
      expect(h.calls).to eq([:handle_sts_audio_abort])
    end

    it "routes to STS when the app does not declare privacy (two-gate)" do
      stub_apps(privacy_enabled: false)
      h = host.new(sts_capable: true)
      h.send(:route_audio_event, connection, make_session(privacy_toggle: true), obj,
             sts_handler: :handle_sts_audio_chunk, fallback: :handle_audio_chunk)
      expect(h.calls).to eq([:handle_sts_audio_chunk])
      expect(writes).to be_empty
    end
  end

  describe "STS-capable model with Privacy Filter enabled" do
    before { stub_apps(privacy_enabled: true) }

    it "blocks routing and sends a single explanatory error" do
      h = host.new(sts_capable: true)
      session = make_session(privacy_toggle: true)
      h.send(:route_audio_event, connection, session, obj,
             sts_handler: :handle_sts_audio_chunk, fallback: :handle_audio_chunk)

      expect(h.calls).to be_empty
      expect(writes.size).to eq(1)
      payload = JSON.parse(writes.first)
      expect(payload["type"]).to eq("error")
      expect(payload["content"]).to match(/Privacy Filter/i)
      expect(payload["content"]).to match(/speech-to-speech/i)
    end

    it "sends the error only once per session across repeated chunks" do
      h = host.new(sts_capable: true)
      session = make_session(privacy_toggle: true)
      3.times do
        h.send(:route_audio_event, connection, session, obj,
               sts_handler: :handle_sts_audio_chunk, fallback: :handle_audio_chunk)
      end
      expect(writes.size).to eq(1)
      expect(h.calls).to be_empty
    end

    it "blocks COMMIT and ABORT the same way" do
      h = host.new(sts_capable: true)
      session = make_session(privacy_toggle: true)
      h.send(:route_audio_event, connection, session, obj,
             sts_handler: :handle_sts_audio_commit, fallback: :handle_audio_commit)
      h.send(:route_audio_event, connection, session, obj,
             sts_handler: :handle_sts_audio_abort, fallback: :handle_audio_abort)
      expect(h.calls).to be_empty
      # First event emits the error; the second is suppressed by the flag.
      expect(writes.size).to eq(1)
    end

    it "allows STS again in a fresh session (flag is per-session)" do
      h = host.new(sts_capable: true)
      h.send(:route_audio_event, connection, make_session(privacy_toggle: true), obj,
             sts_handler: :handle_sts_audio_chunk, fallback: :handle_audio_chunk)
      h.send(:route_audio_event, connection, make_session(privacy_toggle: false), obj,
             sts_handler: :handle_sts_audio_chunk, fallback: :handle_audio_chunk)
      expect(h.calls).to eq([:handle_sts_audio_chunk])
      expect(writes.size).to eq(1)
    end
  end

  # UPDATE_PARAMS must tear the STS bridge down when app/model/voice
  # changes; otherwise the old bridge holds its upstream socket and
  # semaphore slot until the WebSocket closes.
  describe "UPDATE_PARAMS STS bridge teardown" do
    let(:plain_host) do
      Class.new do
        include WebSocketHelper
      end.new
    end

    def sts_fake_state
      {
        cmd_queue: Async::Queue.new,
        ready: Async::Condition.new,
        bridge_task: double(:bridge_task, stop: nil)
      }
    end

    def call_update_params(h, session, params)
      allow(h).to receive(:sync_session_state!)
      allow(h).to receive(:send_or_broadcast)
      h.send(:handle_ws_update_params, nil, { "params" => params }, session)
    end

    def sts_session_with_bridge(model: "gpt-realtime-2.1")
      { parameters: { "app_name" => "VoiceChatOpenAI", "model" => model },
        _sts: sts_fake_state }
    end

    it "tears the bridge down when the model changes" do
      session = sts_session_with_bridge
      call_update_params(plain_host, session, { "model" => "gpt-5.6-terra" })
      expect(session[:_sts]).to be_nil
    end

    it "tears the bridge down when the voice changes (bridge pins voice at creation)" do
      session = sts_session_with_bridge
      call_update_params(plain_host, session, { "tts_voice" => "nova" })
      expect(session[:_sts]).to be_nil
    end

    it "tears the bridge down when the app changes (instructions change)" do
      allow(Monadic::Utils::ContainerDependencies).to receive(:ensure_services_async)
      session = sts_session_with_bridge
      call_update_params(plain_host, session, { "app_name" => "ChatOpenAI" })
      expect(session[:_sts]).to be_nil
    end

    it "keeps the bridge when the update touches none of app/model/voice" do
      session = sts_session_with_bridge
      state = session[:_sts]
      call_update_params(plain_host, session, { "some_other" => "x" })
      expect(session[:_sts]).to equal(state)
    end

    it "no-ops when no bridge exists" do
      session = { parameters: { "app_name" => "VoiceChatOpenAI", "model" => "gpt-realtime-2.1" } }
      expect { call_update_params(plain_host, session, { "model" => "gpt-5.6-terra" }) }.not_to raise_error
    end
  end

  # Defense in depth: an STS realtime model must never reach the normal
  # chat-completions pipeline (raw provider 404). handle_ws_streaming
  # answers with a friendly error before doing any work.
  describe "normal-pipeline STS model guard (handle_ws_streaming)" do
    let(:plain_host) do
      Class.new do
        include WebSocketHelper
      end.new
    end

    it "rejects an STS model with a friendly error and does not start a turn" do
      h = plain_host
      broadcasts = []
      allow(h).to receive(:send_or_broadcast) { |msg, *_| broadcasts << JSON.parse(msg) }

      session = { parameters: {}, messages: [] }
      result = h.send(:handle_ws_streaming, nil,
                      { "message" => "hello", "model" => "gpt-realtime-2.1" }, session, nil)

      expect(result).to be_nil
      expect(broadcasts.length).to eq(1)
      expect(broadcasts.first["type"]).to eq("error")
      expect(broadcasts.first["content"]).to include("voice-only")
      expect(session[:messages]).to be_empty
    end

    it "does not guard a normal chat model (guard is a no-op for non-STS models)" do
      h = plain_host
      broadcasts = []
      allow(h).to receive(:send_or_broadcast) { |msg, *_| broadcasts << JSON.parse(msg) }
      # Stop right after the guard: the rest of the pipeline is out of scope
      # here, so make the first downstream step explode into a sentinel.
      allow(h).to receive(:initialize_token_counting) { raise StopIteration }

      session = { parameters: {}, messages: [] }
      expect do
        h.send(:handle_ws_streaming, nil,
               { "message" => "hello", "model" => "gpt-5.6-terra" }, session, nil)
      end.to raise_error(StopIteration)
      expect(broadcasts).to be_empty
    end
  end

  # STS_INITIATE routing: capability + privacy gates, ignored outside STS.
  describe "STS_INITIATE routing (route_sts_initiate)" do
    it "routes to handle_sts_initiate in an STS session" do
      h = host.new(sts_capable: true)
      h.send(:route_sts_initiate, connection, make_session(privacy_toggle: false), obj)
      expect(h.calls).to eq([:handle_sts_initiate])
    end

    it "is ignored outside STS sessions (no call, no error)" do
      h = host.new(sts_capable: false)
      expect do
        h.send(:route_sts_initiate, connection, make_session(privacy_toggle: false), obj)
      end.not_to raise_error
      expect(h.calls).to be_empty
      expect(writes).to be_empty
    end

    it "emits the privacy notice instead of initiating when privacy is on" do
      stub_apps(privacy_enabled: true)
      h = host.new(sts_capable: true)
      h.send(:route_sts_initiate, connection, make_session(privacy_toggle: true), obj)
      expect(h.calls).to be_empty
      expect(writes.size).to eq(1)
    end
  end
end

# The chat_model hint on inbound audio messages. Routing from session
# parameters alone races the client's UPDATE_PARAMS broadcast (silently
# dropped while the socket is not OPEN or a suppression window is active):
# in that state the session still holds the previous chat model, every chunk
# routes to the legacy STT bridge, and the user's STT model — possibly a
# non-OpenAI one — gets sent to the OpenAI realtime endpoint. Observed live
# as "Realtime STT: Invalid value: 'coh...026'".
RSpec.describe 'sts_session_capable? chat_model hint' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      public :sts_session_capable?
    end.new
  end

  before do
    allow(Monadic::Utils::ModelSpec).to receive(:supports_speech_to_speech?) do |model|
      model == 'gpt-realtime-2.1'
    end
  end

  it 'routes to STS on the hint even when the session copy is stale' do
    session = { parameters: { 'model' => 'gpt-5.6-terra' } }
    obj = { 'chat_model' => 'gpt-realtime-2.1' }

    expect(harness.sts_session_capable?(session, obj)).to be true
  end

  it 'capability-checks the hint rather than trusting it' do
    session = { parameters: { 'model' => 'gpt-5.6-terra' } }
    obj = { 'chat_model' => 'gpt-5.6-terra' }

    expect(harness.sts_session_capable?(session, obj)).to be false
  end

  it 'falls back to session parameters when no hint is present' do
    session = { parameters: { 'model' => 'gpt-realtime-2.1' } }

    expect(harness.sts_session_capable?(session, {})).to be true
    expect(harness.sts_session_capable?(session)).to be true
  end

  it 'ignores a blank hint' do
    session = { parameters: { 'model' => 'gpt-realtime-2.1' } }

    expect(harness.sts_session_capable?(session, { 'chat_model' => ' ' })).to be true
  end

  # Production Rack sessions (SecureSessionHash) are not Hash subclasses but
  # do support []. The gate must duck-type, mirroring
  # BaseVendorHelper#privacy_enabled_for? — an is_a?(Hash) check passes every
  # plain-Hash spec fixture while silently disabling the feature in
  # production.
  it 'reads a Hash-like session object that is not a Hash' do
    session_like = Class.new do
      def initialize(params) = @params = params
      def [](key) = key.to_s == 'parameters' || key == :parameters ? @params : nil
    end.new({ 'model' => 'gpt-realtime-2.1' })

    expect(harness.sts_session_capable?(session_like)).to be true
  end

  it 'returns false for a session that does not respond to []' do
    expect(harness.sts_session_capable?(nil)).to be false
    expect(harness.sts_session_capable?(:not_a_session)).to be false
  end
end
