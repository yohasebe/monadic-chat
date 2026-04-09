# frozen_string_literal: true

# WebSocket connection tracking and session state management.
# Handles thread-safe connection lifecycle, multi-tab session isolation,
# and progress broadcasting.

require 'set'

module WebSocketHelper
  # ============= Connection Tracking =============

  # Class variable to store WebSocket connections with thread safety
  # Now stores Async::WebSocket::Connection objects
  @@ws_connections = []
  @@ws_mutex = Mutex.new

  # Add a connection to the list (thread-safe)
  def self.add_connection(ws)
    @@ws_mutex.synchronize do
      @@ws_connections << ws unless @@ws_connections.include?(ws)
    end
  end

  # Remove a connection from the list (thread-safe)
  def self.remove_connection(ws)
    @@ws_mutex.synchronize do
      @@ws_connections.delete(ws)
    end
  end

  # Broadcast MCP status to all connected clients (thread-safe)
  def self.broadcast_mcp_status(status)
    message = {
      event: "mcp_status",
      data: status
    }.to_json

    # Create a copy of connections to avoid holding lock during I/O
    connections_copy = @@ws_mutex.synchronize { @@ws_connections.dup }

    connections_copy.each do |ws|
      begin
        # Synchronous send - removed Async do block for thread compatibility
        ws.write(message)
        ws.flush
      rescue StandardError => e
        # Log WebSocket send error and remove dead connection
        Monadic::Utils::ExtraLogger.log { "[WebSocket] Send error: #{e.message}" }
        remove_connection(ws)
      end
    end
  end

  # Broadcast to all connected clients (thread-safe)
  def self.broadcast_to_all(message)
    connections_copy = @@ws_mutex.synchronize { @@ws_connections.dup }

    Monadic::Utils::ExtraLogger.log { "[WebSocketHelper] Broadcasting to #{connections_copy.size} connection(s)" }

    connections_copy.each do |ws|
      begin
        # Synchronous send - removed Async do block for thread compatibility
        ws.write(message)
        ws.flush

        Monadic::Utils::ExtraLogger.log { "[WebSocketHelper] Broadcasted: #{message[0..100]}..." }
      rescue StandardError => e
        # Log WebSocket send error and remove dead connection
        Monadic::Utils::ExtraLogger.log { "[WebSocket] Send error: #{e.message}" }
        remove_connection(ws)
      end
    end
  end

  # ============= Session State Management =============

  # Session management for progress updates
  # One session ID can have multiple WebSocket connections (e.g., multiple tabs)
  @@connections_by_session = Hash.new { |h, k| h[k] = Set.new }
  @@session_mutex = Mutex.new
  @@session_state_mutex = Mutex.new
  @@session_state = {}

  # Feature Flag for progress broadcasting
  def self.progress_broadcast_enabled?
    return false unless defined?(CONFIG)
    CONFIG["WEBSOCKET_PROGRESS_ENABLED"] != false  # Default true
  end

  def self.deep_clone_session_state(obj)
    return nil if obj.nil?

    Marshal.load(Marshal.dump(obj))
  rescue TypeError
    obj.respond_to?(:dup) ? obj.dup : obj
  rescue StandardError
    obj
  end

  def self.update_session_state(session_id, messages:, parameters:)
    return unless session_id

    @@session_state_mutex.synchronize do
      @@session_state[session_id] ||= {}
      state = @@session_state[session_id]
      state[:messages] = deep_clone_session_state(messages || [])
      state[:parameters] = deep_clone_session_state(parameters || {})
    end
  end

  def self.fetch_session_state(session_id)
    return nil unless session_id

    @@session_state_mutex.synchronize do
      state = @@session_state[session_id]
      if state
        {
          messages: deep_clone_session_state(state[:messages] || []),
          parameters: deep_clone_session_state(state[:parameters] || {})
        }
      else
        nil
      end
    end
  end

  # Broadcast progress message to specific session or all
  # @param fragment [Hash] Complete fragment object with progress info
  # @param target_session_id [String, nil] Specific session to target
  def self.broadcast_progress(fragment, target_session_id = nil)
    return unless progress_broadcast_enabled?

    # Build complete message
    message = if fragment.is_a?(Hash)
      fragment.merge("timestamp" => Time.now.to_f)
    else
      {
        "type" => "wait",
        "content" => fragment.to_s,
        "timestamp" => Time.now.to_f
      }
    end

    message_json = message.to_json

    # Send to specific session or broadcast to all
    if target_session_id
      send_to_session(message_json, target_session_id)
    else
      broadcast_to_all(message_json)
    end
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[WebSocketHelper] Error broadcasting progress: #{e.message}" }
  end

  # Send message to specific session
  # @param message_json [String] JSON message to send
  # @param session_id [String] Session ID to send to
  # @param single_connection [Boolean] If true, send to only one connection (for audio to prevent duplicates)
  def self.send_to_session(message_json, session_id, single_connection: false)
    return unless session_id

    websockets = @@session_mutex.synchronize { @@connections_by_session[session_id].dup }

    if websockets.empty?
      Monadic::Utils::ExtraLogger.log { "[WebSocketHelper] No connections found for session #{session_id}" }
      return
    end

    # For audio messages, only send to the first active connection to prevent duplicate playback
    # when multiple tabs are open
    if single_connection
      websockets = [websockets.first]
      Monadic::Utils::ExtraLogger.log { "[WebSocketHelper] Single connection mode: sending to 1 of #{@@connections_by_session[session_id].size} connections" }
    end

    # Collect connections to remove (avoid modification during iteration)
    to_remove = []

    websockets.each do |ws|
      begin
        # Synchronous send - removed Async do block for thread compatibility
        ws.write(message_json)
        ws.flush

        Monadic::Utils::ExtraLogger.log { "[WebSocketHelper] Sent to session #{session_id}: #{message_json[0..100]}..." }
      rescue StandardError => e
        Monadic::Utils::ExtraLogger.log { "[WebSocketHelper] Error sending to session #{session_id}: #{e.message}" }
        to_remove << ws
      end
    end

    # Remove dead connections after iteration
    unless to_remove.empty?
      @@session_mutex.synchronize do
        to_remove.each { |ws| @@connections_by_session[session_id].delete(ws) }
      end

      Monadic::Utils::ExtraLogger.log { "[WebSocketHelper] Cleaned up #{to_remove.size} dead connections for session #{session_id}" }
    end
  end

  # Send audio message to only one connection per session
  # This prevents duplicate audio playback when multiple tabs are open
  def self.send_audio_to_session(message_json, session_id)
    send_to_session(message_json, session_id, single_connection: true)
  end

  # ============= Connection + Session Bridge =============

  # Add WebSocket connection with session tracking
  def self.add_connection_with_session(ws, session_id = nil)
    # Add to regular connections list
    add_connection(ws)

    # Add to session tracking if session_id provided
    if session_id
      @@session_mutex.synchronize do
        @@connections_by_session[session_id].add(ws)
      end

      Monadic::Utils::ExtraLogger.log {
        count = @@session_mutex.synchronize { @@connections_by_session[session_id].size }
        "[WebSocketHelper] Added connection for session #{session_id}, total: #{count}"
      }
    end
  end

  # Remove WebSocket connection with session tracking
  def self.remove_connection_with_session(ws, session_id = nil)
    # Remove from regular connections list
    remove_connection(ws)

    # Remove from session tracking if session_id provided
    if session_id
      remaining = 0
      @@session_mutex.synchronize do
        if @@connections_by_session.key?(session_id)
          @@connections_by_session[session_id].delete(ws)
          remaining = @@connections_by_session[session_id].size

          # Remove empty session entries
          if @@connections_by_session[session_id].empty?
            @@connections_by_session.delete(session_id)
          end
        end
      end

      Monadic::Utils::ExtraLogger.log { "[WebSocketHelper] Removed connection for session #{session_id}, remaining: #{remaining}" }
    end
  end

  # Send progress fragment with type checking
  def self.send_progress_fragment(fragment, target_session_id = nil)
    return unless fragment.is_a?(Hash)

    # Only send wait or fragment type messages
    if fragment["type"] == "wait" || fragment["type"] == "fragment"
      broadcast_progress(fragment, target_session_id)
    end
  end
end
