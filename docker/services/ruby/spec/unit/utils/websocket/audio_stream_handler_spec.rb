# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'monadic/utils/extra_logger'
require 'monadic/utils/websocket/audio_stream_handler'

# Unit tests for the synchronous, side-effect-free parts of the Realtime
# STT bridge in WebSocketHelper. The full bridge (Async fibers, OpenAI WS
# connection, session.update → session.updated ack → flush → commit →
# completed) is exercised end-to-end by manual dogfood (see memo
# tmp/memo/realtime-transcription-plan.md Phase 2 verification block);
# the integration suite covers it with a real WS mock if/when we add
# one. These tests pin the wire contract — the `session.update` payload
# shape and the message-parsing edges — that any future refactor must
# preserve.
RSpec.describe "WebSocketHelper realtime STT bridge — wire contract" do
  let(:host) do
    Class.new do
      include WebSocketHelper
    end.new
  end

  describe "#parse_realtime_payload" do
    it "parses a JSON string message" do
      payload = host.send(:parse_realtime_payload, '{"type":"session.updated"}')
      expect(payload).to eq({ "type" => "session.updated" })
    end

    it "uses #buffer when the message responds to it (async-websocket frame)" do
      frame = double(:frame, buffer: '{"type":"session.updated","session":{"id":"sess_1"}}')
      payload = host.send(:parse_realtime_payload, frame)
      expect(payload["type"]).to eq("session.updated")
      expect(payload.dig("session", "id")).to eq("sess_1")
    end

    it "returns nil on malformed JSON instead of raising" do
      expect(host.send(:parse_realtime_payload, "not json")).to be_nil
    end
  end

  describe "#send_realtime_session_update" do
    let(:writes) { [] }
    let(:conn) do
      c = Object.new
      writes_ref = writes
      c.define_singleton_method(:write) { |body| writes_ref << body }
      c.define_singleton_method(:flush) { nil }
      c
    end

    def parsed_audio_input(model:, lang:)
      host.send(:send_realtime_session_update, conn, { model: model, lang: lang })
      JSON.parse(writes.first).dig("session", "audio", "input")
    end

    it "emits a session.update envelope with type=transcription" do
      host.send(:send_realtime_session_update, conn, { model: "gpt-realtime-whisper", lang: nil })
      body = JSON.parse(writes.first)
      expect(body["type"]).to eq("session.update")
      expect(body.dig("session", "type")).to eq("transcription")
    end

    it "pins the audio format to audio/pcm @ 24kHz" do
      audio_in = parsed_audio_input(model: "gpt-realtime-whisper", lang: nil)
      expect(audio_in["format"]).to eq({ "type" => "audio/pcm", "rate" => 24_000 })
    end

    it "carries the transcription model in transcription.model" do
      audio_in = parsed_audio_input(model: "gpt-4o-transcribe", lang: nil)
      expect(audio_in.dig("transcription", "model")).to eq("gpt-4o-transcribe")
    end

    it "omits turn_detection entirely for gpt-realtime-whisper (server rejects it)" do
      audio_in = parsed_audio_input(model: "gpt-realtime-whisper", lang: nil)
      expect(audio_in.key?("turn_detection")).to be(false)
    end

    it "sends turn_detection: null for gpt-4o-transcribe to disable server VAD" do
      audio_in = parsed_audio_input(model: "gpt-4o-transcribe", lang: nil)
      expect(audio_in.key?("turn_detection")).to be(true)
      expect(audio_in["turn_detection"]).to be_nil
    end

    it "sends turn_detection: null for gpt-4o-mini-transcribe" do
      audio_in = parsed_audio_input(model: "gpt-4o-mini-transcribe", lang: nil)
      expect(audio_in["turn_detection"]).to be_nil
    end

    it "omits transcription.language when lang is nil ('auto')" do
      audio_in = parsed_audio_input(model: "gpt-realtime-whisper", lang: nil)
      expect(audio_in["transcription"].key?("language")).to be(false)
    end

    it "sets transcription.language when lang is provided" do
      audio_in = parsed_audio_input(model: "gpt-realtime-whisper", lang: "ja")
      expect(audio_in.dig("transcription", "language")).to eq("ja")
    end

    it "always requests near_field noise reduction" do
      audio_in = parsed_audio_input(model: "gpt-realtime-whisper", lang: nil)
      expect(audio_in.dig("noise_reduction", "type")).to eq("near_field")
    end
  end

  describe "#handle_audio_commit (defensive surface)" do
    # Host with a stubbed session hash so we can exercise the commit
    # handler without the full Async bridge.
    let(:host_with_session) do
      Class.new do
        include WebSocketHelper

        def initialize
          @session = {}
          @broadcasts = []
        end
        attr_reader :session, :broadcasts

        # Capture instead of broadcasting over a real WS.
        def send_or_broadcast(payload, _ws_session_id)
          @broadcasts << payload
        end
      end.new
    end

    it "broadcasts a no-audio error when no bridge exists (commit without prior chunk)" do
      # session[:_realtime_stt] is nil — bridge was never opened.
      host_with_session.handle_audio_commit(nil, {})

      expect(host_with_session.broadcasts.length).to eq(1)
      payload = JSON.parse(host_with_session.broadcasts.first)
      expect(payload["type"]).to eq("error")
      expect(payload["content"]).to match(/no audio/i)
    end

    it "broadcasts a no-audio error when state exists but cmd_queue is missing" do
      host_with_session.session[:_realtime_stt] = { partial: "" } # malformed; no cmd_queue

      host_with_session.handle_audio_commit(nil, {})

      expect(host_with_session.broadcasts.length).to eq(1)
      payload = JSON.parse(host_with_session.broadcasts.first)
      expect(payload["type"]).to eq("error")
    end

    it "enqueues :commit when the bridge state is healthy (no error broadcast)" do
      queue = double(:queue)
      expect(queue).to receive(:enqueue).with([:commit])
      host_with_session.session[:_realtime_stt] = { cmd_queue: queue }

      host_with_session.handle_audio_commit(nil, {})

      expect(host_with_session.broadcasts).to be_empty
    end
  end

  describe "constants" do
    it "uses the documented OpenAI Realtime transcription endpoint" do
      expect(WebSocketHelper::REALTIME_STT_URL).to eq(
        "wss://api.openai.com/v1/realtime?intent=transcription"
      )
    end

    it "defaults to gpt-realtime-whisper (the natively-streaming variant)" do
      expect(WebSocketHelper::REALTIME_STT_DEFAULT_MODEL).to eq("gpt-realtime-whisper")
    end

    it "bounds the commit-completion wait to 15 seconds" do
      expect(WebSocketHelper::REALTIME_STT_COMMIT_TIMEOUT).to eq(15)
    end
  end
end
