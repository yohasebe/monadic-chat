require 'spec_helper'
require 'set'
require 'faye/websocket'

RSpec.describe WebSocketHelper do
  describe "progress broadcasting" do
    let(:session_id) { "test_session_123" }
    let(:ws_mock) { double("WebSocket", ready_state: Faye::WebSocket::OPEN) }

    before do
      # Reset class variables for clean tests
      described_class.instance_variable_set(:@connections_by_session, nil)
      allow(ws_mock).to receive(:send)
    end

    describe "#progress_broadcast_enabled?" do
      it "returns false when CONFIG not defined" do
        hide_const("CONFIG")
        expect(described_class.progress_broadcast_enabled?).to be false
      end

      it "returns true by default when CONFIG defined" do
        stub_const("CONFIG", {})
        expect(described_class.progress_broadcast_enabled?).to be true
      end

      it "respects WEBSOCKET_PROGRESS_ENABLED setting" do
        stub_const("CONFIG", { "WEBSOCKET_PROGRESS_ENABLED" => false })
        expect(described_class.progress_broadcast_enabled?).to be false
      end
    end

    describe "#send_progress_fragment" do
      before do
        stub_const("CONFIG", { "WEBSOCKET_PROGRESS_ENABLED" => true })
      end

      it "filters non-wait fragments" do
        fragment = { "type" => "message", "content" => "test" }

        expect(described_class).not_to receive(:broadcast_progress)
        described_class.send_progress_fragment(fragment)
      end

      it "passes wait fragments" do
        fragment = { "type" => "wait", "content" => "Processing..." }

        allow(described_class).to receive(:broadcast_progress)
        expect(described_class).to receive(:broadcast_progress).with(fragment, nil)

        described_class.send_progress_fragment(fragment)
      end

      it "passes fragment type fragments" do
        fragment = { "type" => "fragment", "content" => "Still working..." }

        allow(described_class).to receive(:broadcast_progress)
        expect(described_class).to receive(:broadcast_progress).with(fragment, nil)

        described_class.send_progress_fragment(fragment)
      end
    end

    describe "session management" do
      it "allows multiple connections per session" do
        ws1 = double("WebSocket1", ready_state: Faye::WebSocket::OPEN)
        ws2 = double("WebSocket2", ready_state: Faye::WebSocket::OPEN)

        described_class.add_connection_with_session(ws1, session_id)
        described_class.add_connection_with_session(ws2, session_id)

        connections = described_class.connections_by_session[session_id]
        expect(connections.size).to eq(2)
        expect(connections).to include(ws1, ws2)
      end

      it "broadcasts to all connections in a session" do
        ws1 = double("WebSocket1", ready_state: Faye::WebSocket::OPEN)
        ws2 = double("WebSocket2", ready_state: Faye::WebSocket::OPEN)

        allow(ws1).to receive(:send)
        allow(ws2).to receive(:send)

        described_class.add_connection_with_session(ws1, session_id)
        described_class.add_connection_with_session(ws2, session_id)

        stub_const("CONFIG", { "WEBSOCKET_PROGRESS_ENABLED" => true })

        fragment = { "type" => "wait", "content" => "test" }

        expect(ws1).to receive(:send).once
        expect(ws2).to receive(:send).once

        described_class.broadcast_progress(fragment, session_id)
      end

      it "cleans up disconnected websockets" do
        ws1 = double("WebSocket1", ready_state: Faye::WebSocket::CLOSED)
        ws2 = double("WebSocket2", ready_state: Faye::WebSocket::OPEN)

        allow(ws1).to receive(:send)
        allow(ws2).to receive(:send)

        described_class.add_connection_with_session(ws1, session_id)
        described_class.add_connection_with_session(ws2, session_id)

        stub_const("CONFIG", { "WEBSOCKET_PROGRESS_ENABLED" => true })

        fragment = { "type" => "wait", "content" => "test" }

        expect(ws1).not_to receive(:send)
        expect(ws2).to receive(:send).once

        described_class.broadcast_progress(fragment, session_id)

        # ws1 should be removed
        connections = described_class.connections_by_session[session_id]
        expect(connections.size).to eq(1)
        expect(connections).not_to include(ws1)
        expect(connections).to include(ws2)
      end
    end

    describe "safe deletion during iteration" do
      it "safely removes closed connections during broadcast" do
        open_ws = double("OpenWS", ready_state: Faye::WebSocket::OPEN)
        closed_ws = double("ClosedWS", ready_state: Faye::WebSocket::CLOSED)

        allow(open_ws).to receive(:send)

        described_class.add_connection_with_session(open_ws, session_id)
        described_class.add_connection_with_session(closed_ws, session_id)

        initial_count = described_class.connections_by_session[session_id].size
        expect(initial_count).to eq(2)

        stub_const("CONFIG", { "WEBSOCKET_PROGRESS_ENABLED" => true })

        fragment = { "type" => "wait", "content" => "test" }
        expect(open_ws).to receive(:send).once

        described_class.broadcast_progress(fragment, session_id)

        # closed_ws should be removed
        final_count = described_class.connections_by_session[session_id].size
        expect(final_count).to eq(1)
        expect(described_class.connections_by_session[session_id]).to include(open_ws)
        expect(described_class.connections_by_session[session_id]).not_to include(closed_ws)
      end

      it "handles errors during send without breaking iteration" do
        error_ws = double("ErrorWS", ready_state: Faye::WebSocket::OPEN)
        open_ws = double("OpenWS", ready_state: Faye::WebSocket::OPEN)

        allow(error_ws).to receive(:send).and_raise("Network error")
        allow(open_ws).to receive(:send)

        described_class.add_connection_with_session(open_ws, session_id)
        described_class.add_connection_with_session(error_ws, session_id)

        stub_const("CONFIG", { "WEBSOCKET_PROGRESS_ENABLED" => true })

        fragment = { "type" => "wait", "content" => "test" }

        # Error should not prevent open_ws from receiving
        expect(open_ws).to receive(:send).once

        expect {
          described_class.broadcast_progress(fragment, session_id)
        }.not_to raise_error

        # error_ws should be removed
        expect(described_class.connections_by_session[session_id]).to include(open_ws)
        expect(described_class.connections_by_session[session_id]).not_to include(error_ws)
      end
    end

    describe "#cleanup_stale_sessions" do
      it "removes stale connections and empty sessions" do
        stale_ws = double("StaleWS", ready_state: Faye::WebSocket::CLOSED)
        active_ws = double("ActiveWS", ready_state: Faye::WebSocket::OPEN)
        empty_session_ws = double("EmptyWS", ready_state: Faye::WebSocket::CLOSED)

        described_class.add_connection_with_session(stale_ws, "session1")
        described_class.add_connection_with_session(active_ws, "session1")
        described_class.add_connection_with_session(empty_session_ws, "session2")

        described_class.cleanup_stale_sessions

        # session1 should still exist with only active_ws
        expect(described_class.connections_by_session["session1"]).to include(active_ws)
        expect(described_class.connections_by_session["session1"]).not_to include(stale_ws)

        # session2 should be completely removed
        expect(described_class.connections_by_session.key?("session2")).to be false
      end
    end
  end
end