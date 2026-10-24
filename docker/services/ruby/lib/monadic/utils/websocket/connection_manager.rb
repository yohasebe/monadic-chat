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

  # A tab's state is kept while it has no connection, so a reload or a
  # reconnect gets its chat back. A tab with an open connection keeps its
  # state; the others are dropped after STATE_IDLE_TTL without use, and
  # beyond STATE_MAX_IDLE the least recently used go first. A tab that comes
  # back after that starts with an empty chat.
  STATE_IDLE_TTL = 7 * 86_400 # seconds
  STATE_MAX_IDLE = 50

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

  # Each value copied on its own, so one that cannot be copied whole does
  # not leave the others shared.
  def self.deep_clone_each(hash)
    hash.each_with_object({}) { |(key, value), out| out[key] = deep_clone_session_state(value) }
  end

  # A tab can briefly have two connections: the one it is reconnecting from
  # and the new one. Each connection claims a generation when it opens, and
  # a write from an older generation is ignored, so the old connection's
  # last save as it closes cannot undo what the new one did (such as a Reset
  # that moved the tab to a new chat).
  def self.claim_session_state(session_id)
    @@session_state_mutex.synchronize do
      state = (@@session_state[session_id] ||= {})
      state[:used_at] = monotonic_now
      prune_session_state(keep: session_id)
      state[:generation] = state[:generation].to_i + 1
    end
  end

  # chat_id and chat_state are kept as they are when not given, so callers
  # that only carry messages and parameters do not move a tab to another
  # chat. chat_state is the rest of the chat's data (tool results, the
  # Session Context, the privacy registry...). It is copied in and out, so
  # a replaced connection still running cannot change what the tab's next
  # connection gets. Returns false when the write came from a connection
  # that has been replaced.
  def self.update_session_state(session_id, messages:, parameters:, chat_id: nil, chat_state: nil, generation: nil)
    return unless session_id

    @@session_state_mutex.synchronize do
      @@session_state[session_id] ||= {}
      state = @@session_state[session_id]
      return false if generation && state[:generation] && generation < state[:generation]

      state[:used_at] = monotonic_now
      state[:messages] = deep_clone_session_state(messages || [])
      state[:parameters] = deep_clone_session_state(parameters || {})
      state[:chat_id] = chat_id if chat_id
      state[:chat_state] = deep_clone_each(chat_state) if chat_state
      true
    end
  end

  def self.fetch_session_state(session_id)
    return nil unless session_id

    @@session_state_mutex.synchronize do
      state = @@session_state[session_id]
      if state
        state[:used_at] = monotonic_now
        {
          messages: deep_clone_session_state(state[:messages] || []),
          parameters: deep_clone_session_state(state[:parameters] || {}),
          chat_id: state[:chat_id],
          chat_state: deep_clone_each(state[:chat_state] || {})
        }
      else
        nil
      end
    end
  end

  # The session object each tab's open connection runs its chat in. HTTP
  # requests that read a tab's chat (export, the app's graph) read it here:
  # the cookie's session is shared by all tabs and is not the chat.
  @@live_sessions = {}

  def self.register_live_session(session_id, session, generation)
    @@session_state_mutex.synchronize do
      @@live_sessions[session_id] = { session: session, generation: generation }
    end
  end

  # Only the connection that registered it removes it, so an old
  # connection closing does not hide the new one's chat.
  def self.unregister_live_session(session_id, generation)
    @@session_state_mutex.synchronize do
      entry = @@live_sessions[session_id]
      @@live_sessions.delete(session_id) if entry && entry[:generation] == generation
    end
  end

  # The chats open in some tab now, and those a tab is taking from the
  # history (reserved until the tab has it open).
  def self.live_chat_ids
    @@session_state_mutex.synchronize { open_chat_ids_locked + @@reserved_chats.keys }
  end

  @@reserved_chats = {}

  # Reserves a chat for the tab that resumes it: true only when no tab has
  # it open and no other tab is taking it, checked and reserved at once.
  def self.reserve_chat(chat_id)
    @@session_state_mutex.synchronize do
      next false if @@reserved_chats.key?(chat_id) || open_chat_ids_locked.include?(chat_id)

      @@reserved_chats[chat_id] = true
    end
  end

  def self.release_chat(chat_id)
    @@session_state_mutex.synchronize { @@reserved_chats.delete(chat_id) }
  end

  def self.open_chat_ids_locked
    @@live_sessions.values.map { |entry| entry[:session][Monadic::Workspace::Chats::SESSION_KEY] }.compact
  end
  private_class_method :open_chat_ids_locked

  def self.live_session(session_id)
    return nil if session_id.nil? || session_id.to_s.empty?

    @@session_state_mutex.synchronize { @@live_sessions[session_id.to_s]&.dig(:session) }
  end

  # A conversation read from a file waits here until the tab it was sent
  # from takes it over its WebSocket. The tab's own connection replaces its
  # chat with it (stopping the reply and speech first, as Reset does): a
  # request outside that connection cannot change the chat it is running.
  # A staged import can be taken for IMPORT_TTL. It is held in memory until
  # it is taken, replaced by the tab's next import, dropped when the tab has
  # no connection left, or found expired by the next stage or take; at most
  # IMPORT_MAX are held at once (each is one saved conversation, which /load
  # caps in size).
  IMPORT_TTL = 600 # seconds
  IMPORT_MAX = 20
  @@pending_imports = {}

  def self.stage_import(session_id, payload)
    token = SecureRandom.hex(16)
    @@session_state_mutex.synchronize do
      prune_imports
      # A tab has one import waiting at most; the oldest go beyond the cap.
      @@pending_imports.delete_if { |_, entry| entry[:session_id] == session_id }
      @@pending_imports.shift while @@pending_imports.size >= IMPORT_MAX
      @@pending_imports[token] = { session_id: session_id, payload: payload, at: monotonic_now }
    end
    token
  end

  # The staged import, once, and only for the tab it was staged for.
  def self.take_import(session_id, token)
    @@session_state_mutex.synchronize do
      prune_imports
      entry = @@pending_imports[token.to_s]
      return nil unless entry && entry[:session_id] == session_id

      @@pending_imports.delete(token.to_s)[:payload]
    end
  end

  # A tab that closes leaves nothing staged behind.
  def self.drop_imports(session_id)
    @@session_state_mutex.synchronize do
      @@pending_imports.delete_if { |_, entry| entry[:session_id] == session_id }
    end
  end

  # Called with the mutex held.
  def self.prune_session_state(keep: nil)
    now = monotonic_now
    idle = @@session_state.reject { |id, _| id == keep || @@live_sessions.key?(id) }
    expired = idle.select { |_, state| now - state[:used_at].to_f > STATE_IDLE_TTL }.keys
    expired.each { |id| @@session_state.delete(id) }
    rest = idle.reject { |id, _| expired.include?(id) }
    excess = rest.size - STATE_MAX_IDLE
    return unless excess.positive?

    rest.sort_by { |_, state| state[:used_at].to_f }.first(excess).each { |id, _| @@session_state.delete(id) }
  end

  def self.prune_imports
    now = monotonic_now
    @@pending_imports.delete_if { |_, entry| now - entry[:at] > IMPORT_TTL }
  end

  def self.monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
