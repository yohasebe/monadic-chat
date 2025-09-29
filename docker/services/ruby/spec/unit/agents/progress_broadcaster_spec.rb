# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/agents/progress_broadcaster'

RSpec.describe Monadic::Agents::ProgressBroadcaster do
  # Test class that includes the module
  class TestBroadcaster
    include Monadic::Agents::ProgressBroadcaster
  end

  let(:broadcaster) { TestBroadcaster.new }

  describe '#broadcast_progress' do
    context 'with block callback' do
      it 'calls the block with progress data' do
        received_data = nil

        broadcaster.broadcast_progress(
          app_name: "TestApp",
          message: "Processing",
          elapsed_minutes: 2,
          i18n_key: "testKey"
        ) do |data|
          received_data = data
        end

        expect(received_data).to eq({
          "type" => "wait",
          "content" => "Processing",
          "source" => "TestBroadcaster",
          "minutes" => 2,
          "i18n" => { "testKey" => true }
        })
      end

      it 'handles initial message with 0 minutes' do
        received_data = nil

        broadcaster.broadcast_progress(
          app_name: "TestApp",
          message: "Starting",
          elapsed_minutes: 0
        ) do |data|
          received_data = data
        end

        expect(received_data["minutes"]).to eq(0)
        expect(received_data["content"]).to eq("Starting")
      end
    end

    context 'without block callback' do
      before do
        # Mock WebSocketHelper
        stub_const("WebSocketHelper", double("WebSocketHelper"))
        allow(WebSocketHelper).to receive(:respond_to?).with(:send_progress_fragment).and_return(true)
        allow(WebSocketHelper).to receive(:send_progress_fragment)
      end

      it 'uses WebSocketHelper when available' do
        expect(WebSocketHelper).to receive(:send_progress_fragment).with(
          hash_including("type" => "wait", "content" => "Processing"),
          nil
        )

        broadcaster.broadcast_progress(
          app_name: "TestApp",
          message: "Processing"
        )
      end

      it 'passes session ID when available' do
        Thread.current[:websocket_session_id] = "session123"

        expect(WebSocketHelper).to receive(:send_progress_fragment).with(
          anything,
          "session123"
        )

        broadcaster.broadcast_progress(
          app_name: "TestApp",
          message: "Processing"
        )

        Thread.current[:websocket_session_id] = nil
      end
    end
  end

  describe '#send_initial_progress' do
    it 'sends initial progress with 0 minutes' do
      received_data = nil

      broadcaster.send_initial_progress(
        app_name: "TestApp",
        message: "Starting task"
      ) do |data|
        received_data = data
      end

      expect(received_data["minutes"]).to eq(0)
      expect(received_data["content"]).to eq("Starting task")
    end

    it 'uses default message when not provided' do
      received_data = nil

      broadcaster.send_initial_progress(app_name: "TestApp") do |data|
        received_data = data
      end

      expect(received_data["content"]).to eq("Processing request")
    end
  end

  describe '#with_progress_tracking' do
    it 'executes block and returns result' do
      result = broadcaster.with_progress_tracking(
        app_name: "TestApp",
        message: "Processing",
        interval: 1,
        timeout: 5
      ) do
        "test result"
      end

      expect(result).to eq("test result")
    end

    it 'handles exceptions and re-raises them' do
      expect {
        broadcaster.with_progress_tracking(
          app_name: "TestApp",
          message: "Processing"
        ) do
          raise "Test error"
        end
      }.to raise_error("Test error")
    end

    it 'sends initial progress message' do
      received_messages = []

      broadcaster.with_progress_tracking(
        app_name: "TestApp",
        message: "Starting",
        progress_callback: ->(data) { received_messages << data if data }
      ) do
        "test result"
      end

      expect(received_messages).not_to be_empty
      expect(received_messages.first["minutes"]).to eq(0)
      expect(received_messages.first["content"]).to eq("Starting")
    end

    context 'with long timeout' do
      it 'starts progress thread for operations > 120 seconds' do
        thread_started = false

        allow(broadcaster).to receive(:start_progress_thread) do |**args|
          thread_started = true
          # Return mock thread
          thread = Thread.new { sleep }
          thread[:should_stop] = false
          thread
        end

        broadcaster.with_progress_tracking(
          app_name: "TestApp",
          timeout: 150
        ) { "done" }

        expect(thread_started).to be true
      end

      it 'does not start thread for short operations' do
        thread_started = false

        allow(broadcaster).to receive(:start_progress_thread) do
          thread_started = true
        end

        broadcaster.with_progress_tracking(
          app_name: "TestApp",
          timeout: 60
        ) { "done" }

        expect(thread_started).to be false
      end
    end
  end

  describe 'error handling' do
    it 'handles errors gracefully when broadcasting' do
      # Force an error by passing invalid data
      expect {
        broadcaster.broadcast_progress(
          app_name: "TestApp",
          message: "Test"
        ) do |data|
          raise "Block error"
        end
      }.not_to raise_error
    end

    it 'logs errors when EXTRA_LOGGING is enabled' do
      stub_const("CONFIG", { "EXTRA_LOGGING" => true })

      expect {
        broadcaster.broadcast_progress(
          app_name: "TestApp",
          message: "Test"
        ) do
          raise "Test error"
        end
      }.to output(/Error broadcasting progress/).to_stdout
    end
  end
end