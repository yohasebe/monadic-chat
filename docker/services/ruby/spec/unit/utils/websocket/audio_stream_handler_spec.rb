# frozen_string_literal: true

require 'spec_helper'
require 'async'
require 'async/queue'
require 'async/condition'
require 'async/semaphore'
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

  describe "#handle_audio_abort fast-abort race" do
    # Regression for the 15s freeze observed when the user clicks Stop
    # before OpenAI's session.updated arrives. Before the fix, the
    # writer fiber was blocked inside wait_for_ready on
    # state[:ready].wait, and :abort enqueued on cmd_queue could not be
    # dequeued until the wait timed out. The fix:
    #   1. handle_audio_abort signals state[:ready] / state[:done] and
    #      sets state[:aborted] = true before enqueueing :abort, so
    #      any wait point wakes up immediately.
    #   2. wait_for_ready / wait_for_completion check :aborted on both
    #      sides of #wait to cover the signal-before-wait race
    #      (Async::Condition#signal is a no-op when no fiber waits).
    let(:host_with_session) do
      Class.new do
        include WebSocketHelper

        def initialize
          @session = {}
          @broadcasts = []
        end
        attr_reader :session, :broadcasts

        def send_or_broadcast(payload, _ws_session_id)
          @broadcasts << payload
        end
      end.new
    end

    def fresh_state
      {
        cmd_queue: Async::Queue.new,
        partial: +"",
        session_ready: false,
        aborted: false,
        ready: Async::Condition.new,
        done: Async::Condition.new
      }
    end

    it "sets :aborted, signals :ready / :done, and enqueues :abort" do
      state = fresh_state
      host_with_session.session[:_realtime_stt] = state

      host_with_session.handle_audio_abort(nil, {})

      expect(state[:aborted]).to be(true)
      expect(state[:cmd_queue].dequeue).to eq([:abort])
    end

    it "wakes a fiber blocked in #wait_for_ready when abort arrives" do
      state = fresh_state
      host_with_session.session[:_realtime_stt] = state

      result = nil
      elapsed = nil

      Async do |task|
        # Writer fiber: enters wait_for_ready before any signal arrives.
        # Without the abort fix, this would block for 15s (the commit
        # timeout). With the fix, handle_audio_abort signals :ready and
        # the call returns false within milliseconds.
        waiter = task.async do
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = host_with_session.send(:wait_for_ready, state, "ws-test")
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        end

        # Yield once so the waiter actually parks on state[:ready].wait
        # before we fire the abort signal. Without this, signal happens
        # while @waiting is still empty and the :aborted flag is what
        # rescues us — both paths are exercised across the two specs
        # in this group.
        task.sleep(0.005)

        host_with_session.handle_audio_abort(nil, {})

        waiter.wait
      end

      expect(result).to be(false)
      expect(elapsed).to be < 1.0 # was 15s before the fix
    end

    it "returns false from #wait_for_ready when :aborted was set before #wait" do
      # Covers the signal-before-wait race: the abort handler fires its
      # signal while no fiber is parked on state[:ready], so the signal
      # is dropped. The :aborted flag check on the front of the method
      # is what makes this safe.
      state = fresh_state
      state[:aborted] = true

      Async do
        result = host_with_session.send(:wait_for_ready, state, "ws-test")
        expect(result).to be(false)
      end
    end

    it "returns from #wait_for_completion silently when :aborted is set" do
      # commit was sent but the user aborted before .completed arrived.
      # The previous code path would have waited the full 15s and then
      # broadcast a "timed out waiting for transcript" error to the
      # client; with the fix the call returns immediately and no
      # spurious error reaches the UI.
      state = fresh_state
      state[:aborted] = true

      Async do
        host_with_session.send(:wait_for_completion, state, "ws-test")
      end

      expect(host_with_session.broadcasts).to be_empty
    end

    it "no-ops cleanly when no bridge state exists" do
      # abort can arrive on a stale page reload before any AUDIO_CHUNK.
      # The handler must tolerate session[:_realtime_stt] = nil.
      expect { host_with_session.handle_audio_abort(nil, {}) }.not_to raise_error
    end

    it "does NOT broadcast a session-setup-timeout error when abort races the timeout" do
      # Edge case: user clicks Stop just as the 15s wait_for_ready
      # timeout fires. Without this guard the user sees
      # "Realtime STT session setup timeout" on top of an intentional
      # abort, which is confusing UX. The aborted-flag check inside
      # the timeout rescue branch suppresses that broadcast.
      state = fresh_state
      state[:aborted] = true
      host_with_session.session[:_realtime_stt] = state

      stub_const(
        "WebSocketHelper::REALTIME_STT_COMMIT_TIMEOUT",
        0.01
      )

      Async do
        result = host_with_session.send(:wait_for_ready, state, "ws-test")
        expect(result).to be(false)
      end

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

    it "caps concurrent upstream WS connections at 8 by default" do
      expect(WebSocketHelper::REALTIME_STT_MAX_CONCURRENT).to eq(8)
    end
  end

  describe "upstream concurrency cap" do
    # The shared singleton across the process; we exercise it directly
    # instead of going through #run_realtime_stt_bridge! (which would
    # require a live OpenAI socket). This pins the wiring: the helper
    # returns a real Async::Semaphore with the documented limit.
    it "exposes a singleton Async::Semaphore with the configured limit" do
      sem = WebSocketHelper.realtime_stt_semaphore
      expect(sem).to be_an(Async::Semaphore)
      expect(sem.limit).to eq(WebSocketHelper::REALTIME_STT_MAX_CONCURRENT)
      # Singleton: every call returns the same object.
      expect(WebSocketHelper.realtime_stt_semaphore).to equal(sem)
    end

    it "queues acquires past the limit and releases them in order" do
      # End-to-end check that the cap actually serialises beyond limit.
      # Uses a local semaphore (limit=2) so the test does not interfere
      # with the production singleton and stays deterministic.
      sem = Async::Semaphore.new(2)
      events = []

      Async do |task|
        bridges = Array.new(4) do |i|
          task.async do
            sem.acquire do
              events << "start:#{i}"
              task.sleep(0.01)
              events << "end:#{i}"
            end
          end
        end
        bridges.each(&:wait)
      end

      # First two bridges enter together (cap=2). Bridges 2 and 3 only
      # see their "start" event after one of the earlier ones emits
      # its "end" — i.e. never more than two in-flight at once.
      in_flight = 0
      max_in_flight = 0
      events.each do |e|
        if e.start_with?("start:")
          in_flight += 1
          max_in_flight = in_flight if in_flight > max_in_flight
        else
          in_flight -= 1
        end
      end
      expect(max_in_flight).to eq(2)
      expect(events.length).to eq(8) # 4 starts + 4 ends
    end
  end
end
