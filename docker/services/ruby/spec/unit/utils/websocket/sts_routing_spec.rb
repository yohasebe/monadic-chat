# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../../lib/monadic/utils/websocket'

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

      def sts_session_capable?(_session)
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
end
