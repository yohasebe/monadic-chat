# frozen_string_literal: true

require 'timeout'
require 'set'  # For session management with multiple connections
require 'net/http'
require 'uri'
require 'async'
require 'async/queue'
require 'async/websocket/adapters/rack'
require_relative '../agents/ai_user_agent'
require_relative 'boolean_parser'
require_relative 'ssl_configuration'
require_relative 'string_utils'

Monadic::Utils::SSLConfiguration.configure! if defined?(Monadic::Utils::SSLConfiguration)

module WebSocketHelper
  include AIUserAgent
  # Handle websocket connection

  # Access Rack session from thread-local storage in WebSocket context
  # This is necessary because WebSocket connections don't use the normal HTTP request/response cycle
  def session
    Thread.current[:rack_session] || (defined?(super) ? super : {})
  end

  # Safe session parameter access that handles both symbol and string keys
  # This ensures compatibility between import (uses :parameters) and runtime (uses "parameters")
  def get_session_params
    session[:parameters] || session["parameters"] || {}
  end

  def sync_session_state!
    session_id = Thread.current[:websocket_session_id]
    return unless session_id

    params = get_session_params || {}
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts "[#{Time.now}] [sync_session_state!] Saving session=#{session_id}: messages=#{session[:messages]&.size || 0}, app_name=#{params['app_name'] || 'nil'}, reasoning_effort=#{params['reasoning_effort'] || 'nil'}"
      extra_log.close
    end

    WebSocketHelper.update_session_state(
      session_id,
      messages: session[:messages] || [],
      parameters: params
    )
  end

  # Realtime TTS buffer configuration
  # Minimum character length for TTS processing:
  # - Sentences ≤ this length are buffered
  # - Buffer is flushed when total exceeds this length
  # Larger values (e.g., 50) reduce API calls and errors, improve fluency
  # but may slightly increase initial response delay
  # Configurable via AUTO_TTS_MIN_LENGTH environment variable (default: 50, range: 20-200)
  def self.realtime_tts_min_length
    value = (ENV['AUTO_TTS_MIN_LENGTH'] || '50').to_i
    # Enforce bounds: minimum 20, maximum 200
    [[value, 20].max, 200].min
  end

  # For backward compatibility and convenience
  REALTIME_TTS_MIN_LENGTH = realtime_tts_min_length

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
      rescue => e
        # Log WebSocket send error and remove dead connection
        puts "[WebSocket] Send error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
        remove_connection(ws)
      end
    end
  end

  # Broadcast to all connected clients (thread-safe)
  def self.broadcast_to_all(message)
    connections_copy = @@ws_mutex.synchronize { @@ws_connections.dup }

    connections_copy.each do |ws|
      begin
        # Synchronous send - removed Async do block for thread compatibility
        ws.write(message)
        ws.flush

        if CONFIG["EXTRA_LOGGING"]
          puts "[WebSocketHelper] Broadcasted: #{message[0..100]}..."
        end
      rescue => e
        # Log WebSocket send error and remove dead connection
        puts "[WebSocket] Send error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
        remove_connection(ws)
      end
    end
  end

  # ============= Progress Broadcasting Features =============

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
  rescue
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
  rescue => e
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[WebSocketHelper] Error broadcasting progress: #{e.message}"
    end
  end

  # Send message to specific session
  def self.send_to_session(message_json, session_id)
    return unless session_id

    websockets = @@session_mutex.synchronize { @@connections_by_session[session_id].dup }

    if websockets.empty?
      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        puts "[WebSocketHelper] No connections found for session #{session_id}"
      end
      return
    end

    # Collect connections to remove (avoid modification during iteration)
    to_remove = []

    websockets.each do |ws|
      begin
        # Synchronous send - removed Async do block for thread compatibility
        ws.write(message_json)
        ws.flush

        if CONFIG["EXTRA_LOGGING"]
          puts "[WebSocketHelper] Sent to session #{session_id}: #{message_json[0..100]}..."
        end
      rescue => e
        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[WebSocketHelper] Error sending to session #{session_id}: #{e.message}"
        end
        to_remove << ws
      end
    end

    # Remove dead connections after iteration
    unless to_remove.empty?
      @@session_mutex.synchronize do
        to_remove.each { |ws| @@connections_by_session[session_id].delete(ws) }
      end

      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        puts "[WebSocketHelper] Cleaned up #{to_remove.size} dead connections for session #{session_id}"
      end
    end
  end

  # Add WebSocket connection with session tracking
  def self.add_connection_with_session(ws, session_id = nil)
    # Add to regular connections list
    add_connection(ws)

    # Add to session tracking if session_id provided
    if session_id
      @@session_mutex.synchronize do
        @@connections_by_session[session_id].add(ws)
      end

      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        count = @@session_mutex.synchronize { @@connections_by_session[session_id].size }
        puts "[WebSocketHelper] Added connection for session #{session_id}, total: #{count}"
      end
    end
  end

  # Remove WebSocket connection with session tracking
  def self.remove_connection_with_session(ws, session_id = nil)
    # Remove from regular connections list
    remove_connection(ws)

    # Remove from session tracking if session_id provided
    if session_id
      @@session_mutex.synchronize do
        @@connections_by_session[session_id].delete(ws)

        # Remove empty session entries
        if @@connections_by_session[session_id].empty?
          @@connections_by_session.delete(session_id)
        end
      end

      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        remaining = @@session_mutex.synchronize { @@connections_by_session[session_id]&.size || 0 }
        puts "[WebSocketHelper] Removed connection for session #{session_id}, remaining: #{remaining}"
      end
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

  # Clean up stale sessions periodically
  def self.cleanup_stale_sessions
    @@session_mutex.synchronize do
      @@connections_by_session.each do |session_id, websockets|
        # Collect dead connections
        to_remove = []
        websockets.each do |connection|
          if connection.nil? || connection.closed?
            to_remove << connection
          end
        end

        # Remove after iteration
        to_remove.each { |connection| websockets.delete(connection) }

        # Remove empty sessions
        @@connections_by_session.delete(session_id) if websockets.empty?
      end
    end
  end
  
  # Initialize token counting in a background thread
  def initialize_token_counting(text, encoding_name="o200k_base")
    # Return immediately if no text
    return nil if text.nil? || text.empty?
    
    # Store in thread local variable to avoid creating too many threads
    Thread.current[:token_count_in_progress] = true
    
    # Use Thread.new with lower priority to avoid impacting TTS
    Thread.new do
      result = nil
      begin
        # Add a small delay to prioritize TTS thread startup if running concurrently
        sleep 0.05 if Thread.list.any? { |t| t[:type] == :tts }
        
        # Set thread type for identification
        Thread.current[:type] = :token_counter
        
        # Do the actual token counting - this now uses the caching mechanism
        # in FlaskAppClient for better performance
        result = MonadicApp::TOKENIZER.count_tokens(text, encoding_name)
        
        # Store for later use in check_past_messages
        Thread.current[:token_count_result] = result
      rescue => e
        # Log token counting errors for debugging
        if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
          logger.warn "Token counting error: #{e.message}"
        end
        # Continue without blocking the operation
      ensure
        Thread.current[:token_count_in_progress] = false
      end
      
      # Thread's return value
      result
    end
  end

  # check if the total tokens of past messages is less than max_tokens in obj
  # token count is calculated using tiktoken
  def check_past_messages(obj)
    # filter out any messages of type "search"
    # Filter messages by current app_name to prevent cross-app conversation leakage
    current_app_name = obj["app_name"] || session.dig("parameters", "app_name") || session.dig(:parameters, "app_name")
    messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }

    res = false
    max_input_tokens = obj["max_input_tokens"].to_i
    context_size = obj["context_size"].to_i
    tokenizer_available = true

    # Default to o200k_base encoding for GPT models
    encoding_name = "o200k_base"

    begin
      # Batch process messages that need token counting to reduce HTTP requests
      messages_to_count = []
      messages.each do |m|
        # Skip messages that already have token counts
        next if m["tokens"]
        
        # If this is the most recent message and we have precounted tokens, use them
        if m == messages.last && defined?(Thread.current[:token_count_result]) && Thread.current[:token_count_result]
          m["tokens"] = Thread.current[:token_count_result]
        else
          # Otherwise add to batch for counting
          messages_to_count << m
        end
        
        # Mark all messages as active initially
        m["active"] = true
      end
      
      # Now process any messages that still need token counts - these use the cache in FlaskAppClient
      messages_to_count.each do |m|
        m["tokens"] = MonadicApp::TOKENIZER.count_tokens(m["text"], encoding_name)
      end

      # Filter active messages and calculate total token count
      active_messages = messages.select { |m| m["active"] }.reverse
      total_tokens = active_messages.sum { |m| m["tokens"] || 0 }

      # Remove oldest messages until total token count and message count are within limits
      until active_messages.empty? || total_tokens <= max_input_tokens
        last_message = active_messages.pop
        last_message["active"] = false
        total_tokens -= last_message["tokens"] || 0
        res = true
        break if context_size.positive? && active_messages.size <= context_size
      end

      # Calculate total token counts for different roles
      count_total_system_tokens = messages.filter { |m| m["role"] == "system" }.sum { |m| m["tokens"] || 0 }
      count_total_input_tokens = messages.filter { |m| m["role"] == "user" }.sum { |m| m["tokens"] || 0 }
      count_total_output_tokens = messages.filter { |m| m["role"] == "assistant" }.sum { |m| m["tokens"] || 0 }
      count_active_tokens = active_messages.sum { |m| m["tokens"] || 0 }
      count_all_tokens = messages.sum { |m| m["tokens"] || 0 }
    rescue StandardError => e
      STDERR.puts "Error in token counting: #{e.message}"
      tokenizer_available = false
    end

    # Return information about the state of the messages array
    res = { changed: res,
            count_total_system_tokens: count_total_system_tokens,
            count_total_input_tokens: count_total_input_tokens,
            count_total_output_tokens: count_total_output_tokens,
            count_total_active_tokens: count_active_tokens,
            count_all_tokens: count_all_tokens,
            count_messages: messages.size,
            count_active_messages: active_messages.size,
            encoding_name: encoding_name }
    res[:error] = "Error: Token count not available" unless tokenizer_available
    res
  end

  # List available ElevenLabs voices
  # @param api_key [String, nil] Optional API key
  # @return [Array] Array of voice data
  def list_elevenlabs_voices(api_key = nil)
    # Use provided API key or default from config
    api_key ||= CONFIG["ELEVENLABS_API_KEY"] if defined?(CONFIG)
    return [] unless api_key
    
    # Direct implementation to avoid dependency issues with InteractionUtils
    begin
      url = URI("https://api.elevenlabs.io/v1/voices")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(url)
      request["xi-api-key"] = api_key
      response = http.request(request)
      
      return [] unless response.is_a?(Net::HTTPSuccess)
      
      voices = response.read_body
      
      begin
        parsed_voices = JSON.parse(voices)
      rescue JSON::ParserError => e
        DebugHelper.debug("Invalid JSON from ElevenLabs API: #{voices[0..200]}", "api", level: :error)
        return []
      end
      
      parsed_voices&.dig("voices")&.map do |voice|
        {
          "voice_id" => voice["voice_id"],
          "name" => voice["name"]
        }
      end || []
    rescue Net::ReadTimeout => e
      DebugHelper.debug("Timeout reading ElevenLabs voices", "api", level: :warning)
      []
    rescue StandardError => e
      []
    end
  end

  # Handle the LOAD message by preparing and sending relevant data
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  def handle_load_message(connection)
    # Handle error if present
    if session[:error]
      send_to_client(connection, { "type" => "error", "content" => session[:error] })
      session[:error] = nil
    end

    # Prepare app data
    apps_data = prepare_apps_data

    # Filter and prepare messages
    filtered_messages = prepare_filtered_messages

    # Send app data with from_initial_load flag to suppress Auto TTS
    push_apps_data(connection, apps_data, filtered_messages, from_initial_load: true)

    # Handle voice data
    push_voice_data(connection)

    # Send MCP server status if available
    if defined?(Monadic::MCP::Server)
      mcp_status = Monadic::MCP::Server.status
      send_to_client(connection, { "type" => "mcp_status", "content" => mcp_status })
    end

    # Update message status
    update_message_status(connection, filtered_messages)

    sync_session_state!
  end
  
  # Prepare apps data with settings
  # @return [Hash] Apps data with settings
  def prepare_apps_data(ui_language = nil)
    return {} unless defined?(APPS)

    # Get UI language from session parameters if not provided
    ui_language ||= session[:parameters]&.[]("ui_language") || "en"

    # Debug logging for language selection
    if CONFIG["EXTRA_LOGGING"]
      puts "[DEBUG] prepare_apps_data called with ui_language: #{ui_language}"
    end

    apps = {}
    largest_app_sizes = {}

    APPS.each do |k, v|
      apps[k] = {}
      v.settings.each do |p, m|
        # Debug log for reasoning_effort in all OpenAI apps
        if p == "reasoning_effort" && CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts("[#{Time.now}] WebSocket: #{k} reasoning_effort = #{m.inspect}")
          extra_log.close
        end
        
        # Handle description specially for multi-language support
        if p == "description"
          if m.is_a?(Hash)
            # Multi-language description: select the appropriate language
            # Fallback order: requested language -> English -> first available
            selected_desc = m[ui_language] || m["en"] || m.values.first || ""
            apps[k][p] = selected_desc
            
            # Debug logging for multi-language descriptions
            if CONFIG["EXTRA_LOGGING"] && k == "SampleMultilang"
              puts "[DEBUG] SampleMultilang description selection:"
              puts "  Requested language: #{ui_language}"
              puts "  Available languages: #{m.keys.join(', ')}"
              puts "  Selected description: #{selected_desc[0..50]}..."
            end
          else
            # Single string description (backward compatibility)
            apps[k][p] = m ? m.to_s : ""
          end
        # Special case for models array to ensure it's properly sent as JSON
        elsif p == "models" && m.is_a?(Array)
          apps[k][p] = m.to_json
        elsif p == "tools" && (m.is_a?(Array) || m.is_a?(Hash))
          # Tools need to be sent as proper JSON too
          apps[k][p] = m.to_json
        elsif p.to_s == "imported_tool_groups" && m.is_a?(Array)
          # Send imported tool groups metadata for UI display with real-time availability
          tool_groups_with_availability = m.map do |group|
            group_name = group[:name].to_sym
            # Check real-time availability using Registry
            available = MonadicSharedTools::Registry.available?(group_name)
            group.merge(available: available)
          end
          apps[k][p.to_s] = tool_groups_with_availability.to_json
          if CONFIG["EXTRA_LOGGING"]
            puts "[DEBUG WebSocket] #{k} imported_tool_groups: #{tool_groups_with_availability.to_json}"
          end
        elsif p == "disabled"
          # Keep disabled as a string for compatibility with frontend
          apps[k][p] = m.to_s
        elsif ["auto_speech", "easy_submit", "initiate_from_assistant", "mathjax", "mermaid", "abc", "monadic", "pdf_vector_storage", "websearch", "jupyter", "image_generation", "video"].include?(p.to_s)
          # Preserve boolean values for feature flags
          # These need to be actual booleans, not strings, for proper JavaScript evaluation
          apps[k][p] = m
        else
          apps[k][p] = m ? m.to_s : nil
        end
      end
      v.api_key = settings.api_key if v.respond_to?(:api_key=) && settings.respond_to?(:api_key)

      # Track size of this app's data
      if CONFIG["EXTRA_LOGGING"]
        app_json = apps[k].to_json
        app_size = app_json.bytesize
        largest_app_sizes[k] = app_size if app_size > 10_000 # Track apps > 10KB
      end
    end

    # Log largest apps
    if CONFIG["EXTRA_LOGGING"] && !largest_app_sizes.empty?
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts "[#{Time.now}] Apps data sizes:"
      largest_app_sizes.sort_by { |_, size| -size }.take(5).each do |name, size|
        extra_log.puts "  #{name}: #{size} bytes (#{(size / 1024.0).round(2)} KB)"
      end
      total_size = apps.to_json.bytesize
      extra_log.puts "  TOTAL: #{total_size} bytes (#{(total_size / 1024.0).round(2)} KB)"
      extra_log.close
    end

    apps
  end
  
  # Filter and prepare messages for display
  # @return [Array] Filtered and formatted messages
  def prepare_filtered_messages
    # Filter messages by current app_name and exclude search messages
    # Support both symbol and string keys for session parameters (import uses symbols, runtime uses strings)
    params = session[:parameters] || session["parameters"] || {}
    current_app_name = params["app_name"]

    # Only return messages for the current app
    # If no app is selected (empty current_app_name), return empty array
    # This ensures proper session isolation during page reloads
    if current_app_name && !current_app_name.to_s.empty?
      filtered_messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }
    else
      filtered_messages = []
    end

    # Debug logging for message filtering (only when EXTRA_LOGGING is enabled)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts "[#{Time.now}] prepare_filtered_messages: #{session[:messages]&.size || 0} total → #{filtered_messages.size} filtered (app=#{current_app_name || 'NONE'})"
      extra_log.close
    end

    params_for_render = params
    mathjax_enabled = params_for_render["mathjax"].to_s == "true"
    # Phase 2: Server-side HTML rendering disabled
    # Client-side MarkdownRenderer now handles all rendering
    # No longer generating m["html"] field to avoid Rouge SIGSEGV bug

    filtered_messages
  end
  
  # Log error with appropriate level based on environment
  # @param message [String] Error message prefix
  # @param error [StandardError] The error object
  # @param level [Symbol] Log level (:info, :warn, :error, etc)
  def log_error(message, error, level = :error)
    # Skip verbose logging in test environment
    return if defined?(RSpec)
    
    # Use Rails logger if available
    if defined?(Rails) && Rails.logger
      Rails.logger.send(level, "#{message}: #{error.message}")
      Rails.logger.debug(error.backtrace.join("\n")) if level == :error
    # Use Ruby logger if available
    elsif defined?(Logger) && instance_variable_defined?(:@logger)
      @logger.send(level, "#{message}: #{error.message}")
      @logger.debug(error.backtrace.join("\n")) if level == :error
    # Fallback to puts for development
    elsif ENV["RACK_ENV"] != "test"
      puts "#{level.to_s.upcase}: #{message}: #{error.message}"
      puts error.backtrace.join("\n") if level == :error
    end
  end
  
  # Push apps data to WebSocket
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param apps [Hash] Apps data
  # @param filtered_messages [Array] Filtered messages
  def push_apps_data(connection, apps, filtered_messages, from_initial_load: false)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Get session from thread context (set in handle_websocket_connection)
    rack_session = Thread.current[:rack_session] || {}

    # Debug logging (only when EXTRA_LOGGING is enabled)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      params_present = rack_session[:parameters] && !rack_session[:parameters].empty?
      extra_log.puts "[#{Time.now}] push_apps_data START: session=#{ws_session_id}, apps=#{apps.size}, params present=#{params_present}, messages=#{filtered_messages.size}, from_initial_load=#{from_initial_load}"
      extra_log.close
    end

    # Send apps message
    apps_message = {
      "type" => "apps",
      "content" => apps,
      "version" => rack_session[:version],
      "docker" => rack_session[:docker]
    }
    unless apps.empty?
      if ws_session_id
        WebSocketHelper.send_to_session(apps_message.to_json, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(apps_message.to_json)
      end
    end

    # Use sleep to delay subsequent messages, giving browser time to process large apps message
    # This prevents message loss when apps message is very large (>1MB)
    sleep(0.05)
    # Always send parameters message, even if empty, to ensure new tabs start with clean state
    # This prevents tabs from inheriting old parameters from localStorage
    if ws_session_id
      WebSocketHelper.send_to_session({ "type" => "parameters", "content" => rack_session[:parameters] || {} }.to_json, ws_session_id)
    else
      WebSocketHelper.broadcast_to_all({ "type" => "parameters", "content" => rack_session[:parameters] || {} }.to_json)
    end

    # Debug logging
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts "[#{Time.now}] push_apps_data: Sent parameters message to session #{ws_session_id}"
      extra_log.close
    end

    # Send past_messages with additional delay to ensure parameters is processed first
    # Add from_initial_load flag to suppress Auto TTS during automatic session restoration
    sleep(0.05)  # Additional 0.05s delay (total 0.1s from start)
    past_messages_data = { "type" => "past_messages", "content" => filtered_messages }
    past_messages_data["from_initial_load"] = true if from_initial_load
    if ws_session_id
      WebSocketHelper.send_to_session(past_messages_data.to_json, ws_session_id)
    else
      WebSocketHelper.broadcast_to_all(past_messages_data.to_json)
    end

    # Debug logging for past_messages (only when EXTRA_LOGGING is enabled)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts "[#{Time.now}] push_apps_data: Sent past_messages with #{filtered_messages.size} items to session #{ws_session_id}"
      extra_log.close
    end

    # Send info message to hide spinner and show "Ready" status
    # For initial load with no parameters, send minimal info data
    info_data = {
      changed: false,
      count_total_system_tokens: 0,
      count_total_input_tokens: 0,
      count_total_output_tokens: 0,
      count_total_active_tokens: 0,
      count_all_tokens: 0,
      count_messages: filtered_messages.size,
      count_active_messages: filtered_messages.size,
      encoding_name: "o200k_base"
    }
    if ws_session_id
      WebSocketHelper.send_to_session({ "type" => "info", "content" => info_data }.to_json, ws_session_id)
    else
      WebSocketHelper.broadcast_to_all({ "type" => "info", "content" => info_data }.to_json)
    end

    # Debug logging for info message (only when EXTRA_LOGGING is enabled)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts "[#{Time.now}] push_apps_data: Sent info message to hide spinner"
      extra_log.close
    end
  end
  
  # Push voice data to WebSocket
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  def push_voice_data(connection)
    elevenlabs_voices = list_elevenlabs_voices
    if elevenlabs_voices && !elevenlabs_voices.empty?
      WebSocketHelper.broadcast_to_all({ "type" => "elevenlabs_voices", "content" => elevenlabs_voices }.to_json)
    end
    
    # Send Gemini voices if API key is available
    if CONFIG["GEMINI_API_KEY"]
      gemini_voices = [
        { "voice_id" => "aoede", "name" => "Aoede" },
        { "voice_id" => "charon", "name" => "Charon" },
        { "voice_id" => "fenrir", "name" => "Fenrir" },
        { "voice_id" => "kore", "name" => "Kore" },
        { "voice_id" => "orus", "name" => "Orus" },
        { "voice_id" => "puck", "name" => "Puck" },
        { "voice_id" => "schedar", "name" => "Schedar" },
        { "voice_id" => "zephyr", "name" => "Zephyr" }
      ]
      WebSocketHelper.broadcast_to_all({ "type" => "gemini_voices", "content" => gemini_voices }.to_json)
    end
  end
  
  # Update message status and push info
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param filtered_messages [Array] Filtered messages
  def update_message_status(connection, filtered_messages)
    # Get session from thread context (set in handle_websocket_connection)
    rack_session = Thread.current[:rack_session] || {}
    past_messages_data = check_past_messages(rack_session[:parameters])

    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Send change_status if changed
    if past_messages_data[:changed]
      status_message = { "type" => "change_status", "content" => filtered_messages }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(status_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(status_message)
      end
    end

    # Send info message
    info_message = { "type" => "info", "content" => past_messages_data }.to_json
    if ws_session_id
      WebSocketHelper.send_to_session(info_message, ws_session_id)
    else
      WebSocketHelper.broadcast_to_all(info_message)
    end

    sync_session_state!
  end

  # Common TTS playback processing for PLAY_TTS and Auto Speech
  # This method handles text segmentation, prefetching, and threaded TTS generation
  # @param text [String] Text to convert to speech
  # @param provider [String] TTS provider (e.g., "elevenlabs-v3", "gemini-flash")
  # @param voice [String] Voice ID
  # @param speed [Float] Speech speed
  # @param response_format [String] Audio format (e.g., "mp3")
  # @param language [String] Language code
  def start_tts_playback(text:, provider:, voice:, speed:, response_format:, language:)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    if CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [DEBUG] start_tts_playback CALLED: text_length=#{text.length}, provider=#{provider}")
      end
    end

    # Strip Markdown markers and HTML tags before processing
    text = StringUtils.strip_markdown_for_tts(text)

    # Process text with PragmaticSegmenter to split into sentences
    ps = PragmaticSegmenter::Segmenter.new(text: text)
    segments = ps.segment

    if CONFIG["EXTRA_LOGGING"]
      puts "[TTS] Original text: '#{text[0..100]}...'"
      puts "[TTS] Segmented into #{segments.length} segments:"
      segments.each_with_index { |s, i| puts "[TTS]   [#{i}] '#{s}'" }
    end

    # For Gemini TTS, combine short segments to avoid API failures
    if provider == "gemini-flash" || provider == "gemini-pro"
      combined_segments = []
      current_segment = ""

      segments.each do |segment|
        # Clean and check text
        cleaned_text = segment.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '') # Remove emojis
        cleaned_text = cleaned_text.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ') # Remove special chars
        cleaned_text = cleaned_text.strip

        if current_segment.empty?
          # Start a new segment
          current_segment = segment
        elsif cleaned_text.length < 8  # Increased threshold for safety
          # Current segment is short, combine with existing
          current_segment += " " + segment
        else
          # Check if current accumulated segment should be finalized
          current_cleaned = current_segment.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
          current_cleaned = current_cleaned.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ').strip

          if current_cleaned.length < 8  # Combine if still short
            current_segment += " " + segment
          else
            # Finalize current segment and start new one
            combined_segments << current_segment if current_cleaned.length >= 3
            current_segment = segment
          end
        end
      end

      # Don't forget the last segment - but validate it first
      unless current_segment.empty?
        final_cleaned = current_segment.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
        final_cleaned = final_cleaned.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ').strip
        combined_segments << current_segment if final_cleaned.length >= 3
      end

      segments = combined_segments
      puts "Gemini TTS: #{ps.segment.length} -> #{segments.length} segments" if ENV["DEBUG_TTS"]
    end

    # Process each segment
    prev_texts_for_tts = []
    segments = Array(segments)

    # ElevenLabs V3: Check if segments should be combined (legacy behavior)
    # Default is false (use segment splitting for prefetch benefits)
    # Set ELEVENLABS_V3_COMBINE_SEGMENTS=true to combine all segments into one
    if provider == "elevenlabs-v3"
      combine_segments = defined?(CONFIG) && CONFIG["ELEVENLABS_V3_COMBINE_SEGMENTS"].to_s == "true"
      if combine_segments
        combined_text = segments.join(" ").strip
        segments = combined_text.empty? ? [] : [combined_text]
        puts "ElevenLabs V3: Combined all segments into one (legacy mode)" if CONFIG["EXTRA_LOGGING"]
      else
        puts "ElevenLabs V3: Using segment splitting for prefetch (#{segments.length} segments)" if CONFIG["EXTRA_LOGGING"]
      end
    end

    # Start a new thread for TTS processing with prefetching
    @tts_thread = Thread.new do
      Thread.current[:type] = :tts_playback

      # Filter and prepare segments
      valid_segments = []
      segments.each do |segment|
        next if segment.strip.empty?

        # Light filtering for Gemini TTS
        if provider == "gemini-flash" || provider == "gemini-pro"
          cleaned_segment = segment.strip
          next if cleaned_segment.length < 3
          valid_segments << cleaned_segment
        else
          valid_segments << segment
        end
      end

      if CONFIG["EXTRA_LOGGING"]
        puts "[TTS] After filtering: #{valid_segments.length} valid segments"
        valid_segments.each_with_index { |s, i| puts "[TTS]   Valid[#{i}] '#{s}'" }
      end

      # Prefetch pipeline: Start first 2 TTS requests in parallel
      # Limited to 2 to respect provider rate limits and concurrent request constraints
      # Most providers have strict limits: OpenAI (RPM), Gemini (QPM), ElevenLabs (concurrent)
      tts_futures = []
      # Store futures array in thread local for STOP_TTS cleanup
      Thread.current[:tts_futures] = tts_futures

      # Special handling for Web Speech API - no prefetching needed (no API calls)
      if provider == "webspeech" || provider == "web-speech"
        # Process synchronously for Web Speech API
        valid_segments.each_with_index do |segment, i|
          res_hash = { "type" => "web_speech", "content" => segment }

          prev_texts_for_tts << segment unless provider == "elevenlabs-v3"

          # Send audio and progress
          if ws_session_id
            WebSocketHelper.send_to_session(res_hash.to_json, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(res_hash.to_json)
          end

          progress_message = {
            "type" => "tts_progress",
            "segment_index" => i,
            "total_segments" => valid_segments.length,
            "progress" => ((i + 1) / valid_segments.length.to_f * 100).round
          }
          if ws_session_id
            WebSocketHelper.send_to_session(progress_message.to_json, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(progress_message.to_json)
          end
        end
      else
        # Prefetch mode for API-based TTS providers
        # Start first 2 requests to prevent gaps between short sentences
        [0, 1].each do |idx|
          break if idx >= valid_segments.length

          segment = valid_segments[idx]
          # Get previous_text directly from valid_segments for initial prefetch
          previous_text = if provider == "elevenlabs-v3"
                            nil
                          elsif idx > 0
                            valid_segments[idx - 1]
                          else
                            nil
                          end

          tts_futures << Thread.new do
            tts_api_request(segment,
                          previous_text: previous_text,
                          provider: provider,
                          voice: voice,
                          speed: speed,
                          response_format: response_format,
                          language: language)
          end
        end

        # Process segments in order
        valid_segments.each_with_index do |segment, i|
          if CONFIG["EXTRA_LOGGING"]
            puts "[TTS] Processing segment #{i}/#{valid_segments.length - 1}: '#{segment[0..50]}...'"
            puts "[TTS] tts_futures.length = #{tts_futures.length}, waiting for index #{i}"
          end

          # Wait for current segment's TTS to complete with error handling
          begin
            res_hash = tts_futures[i]&.value

            if CONFIG["EXTRA_LOGGING"]
              puts "[TTS] Segment #{i} result: #{res_hash ? res_hash["type"] : "nil"}"
            end
          rescue => e
            # Thread was killed or errored - create error response
            puts "[TTS] Segment #{i} failed with exception: #{e.message}"
            puts "[TTS] Backtrace: #{e.backtrace[0..3].join("\n")}" if CONFIG["EXTRA_LOGGING"]
            res_hash = {
              "type" => "error",
              "content" => "TTS generation failed for segment #{i + 1}"
            }
          end

          # Add segment information
          if res_hash && res_hash["type"] == "audio"
            res_hash["segment_index"] = i
            res_hash["total_segments"] = valid_segments.length
            res_hash["is_segment"] = true
          end

          # Store for context
          prev_texts_for_tts << segment unless provider == "elevenlabs-v3"

          # Start next segment's TTS request (prefetch i+2 to maintain 2-segment buffer)
          # This ensures we're always 1-2 segments ahead without overwhelming provider APIs
          next_idx = i + 2
          if next_idx < valid_segments.length
            next_segment = valid_segments[next_idx]
            # Get previous_text directly from valid_segments for prefetch
            next_previous_text = if provider == "elevenlabs-v3"
                                  nil
                                elsif next_idx > 0
                                  valid_segments[next_idx - 1]
                                else
                                  nil
                                end

            tts_futures << Thread.new do
              tts_api_request(next_segment,
                            previous_text: next_previous_text,
                            provider: provider,
                            voice: voice,
                            speed: speed,
                            response_format: response_format,
                            language: language)
            end
          end

          # Send audio and progress
          if res_hash && res_hash["type"] != "error"
            if ws_session_id
              WebSocketHelper.send_to_session(res_hash.to_json, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(res_hash.to_json)
            end

            progress_message = {
              "type" => "tts_progress",
              "segment_index" => i,
              "total_segments" => valid_segments.length,
              "progress" => ((i + 1) / valid_segments.length.to_f * 100).round
            }
            if ws_session_id
              WebSocketHelper.send_to_session(progress_message.to_json, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(progress_message.to_json)
            end
          else
            puts "TTS segment #{i} failed: #{res_hash&.dig("content") || "Unknown error"}"
          end
        end
      end

      # Signal completion
      if CONFIG["EXTRA_LOGGING"]
        puts "[TTS] All segments processed, sending tts_complete"
      end

      complete_message = {
        "type" => "tts_complete",
        "total_segments" => valid_segments.length
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(complete_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(complete_message)
      end

      if CONFIG["EXTRA_LOGGING"]
        puts "[TTS] tts_complete sent successfully"
      end
    end
  end
  
  # Handle DELETE message
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_delete_message(connection, obj)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Get session from thread context (set in handle_websocket_connection)
    rack_session = Thread.current[:rack_session] || {}

    # Delete the message
    rack_session[:messages]&.delete_if { |m| m["mid"] == obj["mid"] }

    # Check message status
    past_messages_data = check_past_messages(rack_session[:parameters])

    # Filter messages
    filtered_messages = prepare_filtered_messages

    # Update status - send to session only
    if past_messages_data[:changed]
      if ws_session_id
        WebSocketHelper.send_to_session({ "type" => "change_status", "content" => filtered_messages }.to_json, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all({ "type" => "change_status", "content" => filtered_messages }.to_json)
      end
    end
    if ws_session_id
      WebSocketHelper.send_to_session({ "type" => "info", "content" => past_messages_data }.to_json, ws_session_id)
    else
      WebSocketHelper.broadcast_to_all({ "type" => "info", "content" => past_messages_data }.to_json)
    end
    sync_session_state!
  end
  
  # Handle EDIT message
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_edit_message(connection, obj)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Get session from thread context (set in handle_websocket_connection)
    rack_session = Thread.current[:rack_session] || {}

    # Find the message index to edit
    messages = rack_session[:messages] || []
    message_index = messages.find_index { |m| m["mid"] == obj["mid"] }

    if message_index
      # Update the message directly in the array to ensure it's persisted
      messages[message_index]["text"] = obj["content"]

      # Update images if provided in the edit request
      if obj["images"] && obj["images"].is_a?(Array)
        messages[message_index]["images"] = obj["images"]
      end

      # Get the updated message for response
      message_to_edit = messages[message_index]

      # Generate HTML content if needed
      html_content = generate_html_for_message(message_to_edit, obj["content"])

      # Create response with updated HTML for the client
      response = {
        "type" => "edit_success",
        "content" => "Message updated successfully",
        "mid" => obj["mid"],
        "role" => message_to_edit["role"],
        "html" => html_content
      }

      # Include images if they exist
      if message_to_edit["images"] && message_to_edit["images"].is_a?(Array) && !message_to_edit["images"].empty?
        response["images"] = message_to_edit["images"]
      end

      # Push the response - send to session only
      if ws_session_id
        WebSocketHelper.send_to_session(response.to_json, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(response.to_json)
      end

      # Update message status
      update_message_status_after_edit

      sync_session_state!
    else
      # Message not found - send error to session only
      if ws_session_id
        WebSocketHelper.send_to_session({ "type" => "error", "content" => "message_not_found_for_editing" }.to_json, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all({ "type" => "error", "content" => "message_not_found_for_editing" }.to_json)
      end
    end
  end
  
  # Generate HTML content for a message
  # @param message [Hash] The message to generate HTML for
  # @param content [String] The text content
  # @return [String, nil] The HTML content or nil
  def generate_html_for_message(message, content)
    # Server-side HTML rendering disabled; client handles Markdown/Monadic rendering
    return nil
  end
  
  # Update message status after edit
  def update_message_status_after_edit
    params = get_session_params
    past_messages_data = check_past_messages(params)

    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Filter messages by current app_name and exclude search messages
    current_app_name = params["app_name"]
    filtered_messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }

    # Update status to reflect any changes (session-targeted)
    if past_messages_data[:changed]
      change_status_message = { "type" => "change_status", "content" => filtered_messages }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(change_status_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(change_status_message)
      end
    end

    # Send info message (session-targeted)
    info_message = { "type" => "info", "content" => past_messages_data }.to_json
    if ws_session_id
      WebSocketHelper.send_to_session(info_message, ws_session_id)
    else
      WebSocketHelper.broadcast_to_all(info_message)
    end

    sync_session_state!
  end
  
  # Handle AUDIO message
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_audio_message(connection, obj)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    if obj["content"].nil?
      error_message = { "type" => "error", "content" => "voice_input_empty" }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(error_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(error_message)
      end
      return
    end

    # Decode audio content
    blob = Base64.decode64(obj["content"])

    # Get STT model from Web UI (priority) or use default
    model = obj["stt_model"] || "gpt-4o-mini-transcribe"
    format = obj["format"] || "webm"

    # Store stt_model in session for use by other components (e.g., Video Describer)
    session[:parameters] ||= {}
    session[:parameters]["stt_model"] = model

    # Process the transcription
    process_transcription(connection, blob, format, obj["lang_code"], model, ws_session_id)
  end

  # Process audio transcription
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param blob [String] The decoded audio data
  # @param format [String] The audio format
  # @param lang_code [String] The language code
  # @param model [String] The model to use
  # @param ws_session_id [String] WebSocket session ID for targeted broadcasting
  def process_transcription(connection, blob, format, lang_code, model, ws_session_id = nil)
    begin
      # Request transcription
      res = stt_api_request(blob, format, lang_code, model)
      
      if res["text"] && res["text"] == ""
        empty_error = { "type" => "error", "content" => "text_input_empty" }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(empty_error, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(empty_error)
        end
      elsif res["type"] && res["type"] == "error"
        # Include format information in error message for debugging
        error_content = "#{res["content"]} (using format: #{format}, model: #{model})"
        api_error = { "type" => "error", "content" => error_content }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(api_error, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(api_error)
        end
      else
        send_transcription_result(connection, res, model)
      end
    rescue StandardError => e
      # Log the error but don't crash the application
      log_error("Error processing transcription", e)

      # Send a generic error message to the client
      rescue_error = {
        "type" => "error",
        "content" => "An error occurred while processing your audio"
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(rescue_error, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(rescue_error)
      end
    end
  end
  
  # Calculate confidence and send transcription result
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param res [Hash] The transcription result
  # @param model [String] The model used
  def send_transcription_result(connection, res, model)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    begin
      logprob = calculate_logprob(res, model)

      stt_message = {
        "type" => "stt",
        "content" => res["text"],
        "logprob" => logprob
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(stt_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(stt_message)
      end
    rescue StandardError => e
      # Handle errors in logprob calculation
      stt_message_no_logprob = {
        "type" => "stt",
        "content" => res["text"]
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(stt_message_no_logprob, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(stt_message_no_logprob)
      end
    end
  end
  
  # Calculate log probability for transcription confidence
  # @param res [Hash] The transcription result
  # @param model [String] The model used
  # @return [Float, nil] The calculated log probability or nil on error
  def calculate_logprob(res, model)
    # Gemini models do not support logprobs for STT
    return nil if model.start_with?("gemini-")

    case model
    when "whisper-1"
      avg_logprobs = res["segments"].map { |s| s["avg_logprob"].to_f }
    else
      avg_logprobs = res["logprobs"].map { |s| s["logprob"].to_f }
    end

    # Calculate average and convert to probability
    Math.exp(avg_logprobs.sum / avg_logprobs.size).round(2)
  rescue StandardError
    nil
  end

  def websocket_handler(env)
    # Falcon/Async handles the event loop automatically
    handle_websocket_connection(env)
  end

  def handle_websocket_connection(env)
    # Get Rack session from environment (or create empty hash if not available)
    session = env['rack.session'] || {}

    # Generate or retrieve session ID with tab isolation
    # Extract tab_id from query parameters for tab-specific session management
    query_params = Rack::Utils.parse_query(env["QUERY_STRING"])
    tab_id = query_params["tab_id"]

    ws_session_id = nil

    # If we have a tab_id, use it as part of the session identifier
    # This ensures each tab has its own isolated session
    if tab_id && !tab_id.empty?
      # Use tab_id as the session identifier directly
      # This ensures complete isolation between tabs
      ws_session_id = tab_id
    else
      # Fallback: For connections without tab_id (e.g., background connections),
      # use a consistent session ID stored in Rack session
      # This ensures page reload preserves the session
      ws_session_id = session[:websocket_session_id] if session.is_a?(Hash)

      if ws_session_id.nil?
        # Generate new UUID only if no session exists
        ws_session_id = SecureRandom.uuid
        session[:websocket_session_id] = ws_session_id if session.is_a?(Hash)

        if CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts "[#{Time.now}] [WebSocket] Generated new session ID for tab_id=nil: #{ws_session_id}"
          extra_log.close
        end
      elsif CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts "[#{Time.now}] [WebSocket] Reusing existing session ID for tab_id=nil: #{ws_session_id}"
        extra_log.close
      end
    end

    if CONFIG["EXTRA_LOGGING"]
      puts "[WebSocket] Using session ID: #{ws_session_id} for new connection (tab_id from query: #{tab_id.inspect})"
    end

    # Use async-websocket to handle the connection
    Async::WebSocket::Adapters::Rack.open(env) do |connection|
      WebSocketHelper.add_connection_with_session(connection, ws_session_id)

      if CONFIG["EXTRA_LOGGING"]
        puts "[WebSocket] Connection opened for session #{ws_session_id}"
      end

      Thread.current[:websocket_session_id] = ws_session_id
      Thread.current[:rack_session] = session

      # Tab isolation: Each tab must have completely independent session state
      # Always initialize with empty session first to clear any Rack session data from other tabs
      session[:messages] = []
      session[:parameters] = {}

      if CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts "[#{Time.now}] [WebSocket] Initialized empty session for tab_id=#{tab_id.inspect}, ws_session_id=#{ws_session_id}"
        extra_log.close
      end

      # Then restore saved state if it exists (for page refresh/reconnection)
      if (saved_state = WebSocketHelper.fetch_session_state(ws_session_id))
        if CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts "[#{Time.now}] [WebSocket] FOUND saved_state for #{ws_session_id}: messages=#{saved_state[:messages]&.size || 0}, app_name=#{saved_state[:parameters]&.[]('app_name') || 'nil'}, reasoning_effort=#{saved_state[:parameters]&.[]('reasoning_effort') || 'nil'}"
          extra_log.close
        end
        session[:messages] = saved_state[:messages] if saved_state[:messages]
        if saved_state[:parameters]
          session[:parameters] ||= {}
          saved_state[:parameters].each do |key, value|
            session[:parameters][key] = value
          end
        end
      elsif CONFIG["EXTRA_LOGGING"]
        extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
        extra_log.puts "[#{Time.now}] [WebSocket] NO saved_state for #{ws_session_id} (new tab or first connection)"
        extra_log.close
      end

      queue = Queue.new
      thread = nil

      # Send initial load message immediately after connection
      handle_load_message(connection)

      begin
        while message_data = connection.read
          begin
            obj = JSON.parse(message_data)
            obj = BooleanParser.parse_hash(obj)
          rescue JSON::ParserError => e
            DebugHelper.debug("Invalid JSON in WebSocket message: #{message_data[0..100]}", "websocket", level: :error)
            send_to_client(connection, { "type" => "error", "content" => "invalid_message_format" })
            next
          end

          msg = obj["message"] || ""

          # Debug logging for all messages when EXTRA_LOGGING is enabled
          if CONFIG["EXTRA_LOGGING"] && msg == "UPDATE_LANGUAGE"
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts("[#{Time.now}] WebSocket received UPDATE_LANGUAGE message")
            extra_log.puts("  Full obj: #{obj.inspect}")
            extra_log.close
          end

          # Debug logging for research assistant apps
          if CONFIG["EXTRA_LOGGING"] && obj["app_name"] && (obj["app_name"].include?("Perplexity") || obj["app_name"].include?("DeepSeek"))
            puts "[DEBUG WebSocket] Received message type: #{msg.inspect}"
            puts "[DEBUG WebSocket] App name from obj: #{obj["app_name"]}"
          end

      case msg
      when "TTS"
          # Get session ID for targeted broadcasting
          ws_session_id = Thread.current[:websocket_session_id]

          provider = obj["provider"]
          if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
            voice = obj["elevenlabs_voice"]
          elsif provider == "gemini-flash" || provider == "gemini-pro"
            voice = obj["gemini_voice"]
          else
            voice = obj["voice"]
          end
          text = obj["text"]
          elevenlabs_voice = obj["elevenlabs_voice"]
          speed = obj["speed"]
          response_format = obj["response_format"]
          language = obj["conversation_language"] || "auto"

          # Special handling for Web Speech API
          if provider == "webspeech" || provider == "web-speech"
            # Create a special response for Web Speech API
            res_hash = { "type" => "web_speech", "content" => text }
          else
            # Generate TTS content for other providers
            puts "TTS: About to call tts_api_request with voice='#{voice}', provider='#{provider}'"
            res_hash = tts_api_request(text,
                                      provider: provider,
                                      voice: voice,
                                      speed: speed,
                                      response_format: response_format,
                                      language: language)
          end

          # Send TTS response to session only
          if ws_session_id
            WebSocketHelper.send_to_session(res_hash.to_json, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(res_hash.to_json)
          end
        when "TTS_STREAM"
          # Get session ID for targeted broadcasting
          ws_session_id = Thread.current[:websocket_session_id]

          thread&.join
          provider = obj["provider"]
          if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
            voice = obj["elevenlabs_voice"]
          elsif provider == "gemini-flash" || provider == "gemini-pro"
            voice = obj["gemini_voice"]
          else
            voice = obj["voice"]
          end
          text = obj["text"]
          elevenlabs_voice = obj["elevenlabs_voice"]
          speed = obj["speed"]
          response_format = obj["response_format"]
          language = obj["conversation_language"] || "auto"
          # model = obj["model"]


          # Special handling for Web Speech API
          if provider == "webspeech" || provider == "web-speech"
            # Create a special response for Web Speech API
            web_speech_response = { "type" => "web_speech", "content" => text }
            if ws_session_id
              WebSocketHelper.send_to_session(web_speech_response.to_json, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(web_speech_response.to_json)
            end
          else
            # Generate TTS content for other providers (use captured ws_session_id in callback)
            tts_api_request(text,
                            provider: provider,
                            voice: voice,
                            speed: speed,
                            response_format: response_format,
                            language: language) do |fragment|
              if ws_session_id
                WebSocketHelper.send_to_session(fragment.to_json, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(fragment.to_json)
              end
          end
          end
        when "CANCEL"
          # Get session ID for targeted broadcasting
          ws_session_id = Thread.current[:websocket_session_id]

          thread&.kill
          thread = nil
          queue.clear

          cancel_message = { "type" => "cancel" }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(cancel_message, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(cancel_message)
          end
        when "PDF_TITLES"
          send_to_client(connection, {
            "type" => "pdf_titles",
            "content" => list_pdf_titles
          })
        when "DELETE_PDF"
          title = obj["contents"]
          res = EMBEDDINGS_DB.delete_by_title(title)
          if res
            send_to_client(connection, { "type" => "pdf_deleted", "res" => "success", "content" => "#{title} deleted successfully" })
            # Invalidate caches for mode/presence
            begin
              session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
            rescue StandardError; end
          else
            send_to_client(connection, { "type" => "pdf_deleted", "res" => "failure", "content" => "Error deleting #{title}" })
          end
        when "DELETE_ALL_PDFS"
          begin
            titles = EMBEDDINGS_DB.list_titles.map { |t| t[:title] }
            titles.each do |t|
              EMBEDDINGS_DB.delete_by_title(t)
            end
            send_to_client(connection, { "type" => "pdf_deleted", "res" => "success", "content" => "All local PDFs deleted" })
            send_to_client(connection, { "type" => "pdf_titles", "content" => [] })
            begin
              session[:pdf_cache_version] = (session[:pdf_cache_version] || 0) + 1
            rescue StandardError; end
          rescue StandardError => e
            send_to_client(connection, { "type" => "pdf_deleted", "res" => "failure", "content" => "Error clearing PDFs: #{e.message}" })
          end
        when "CHECK_TOKEN"
          # Store ui_language in session parameters if provided
          if obj["ui_language"]
            session[:parameters] ||= {}
            session[:parameters]["ui_language"] = obj["ui_language"]
          end
          
          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts "[#{Time.now}] CHECK_TOKEN handler started"
            extra_log.close
          end

          if CONFIG["ERROR"].to_s == "true"
            send_to_client(connection, { "type" => "error", "content" => "Error reading <code>~/monadic/config/env</code>" })
          else
            token = CONFIG["OPENAI_API_KEY"]

            if CONFIG["EXTRA_LOGGING"]
              extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
              extra_log.puts "[#{Time.now}] CHECK_TOKEN: token present=#{!token.nil?}"
              extra_log.close
            end

            res = nil
            begin
              res = check_api_key(token) if token

              if CONFIG["EXTRA_LOGGING"]
                extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                extra_log.puts "[#{Time.now}] CHECK_TOKEN: res=#{res.inspect}"
                extra_log.puts "[#{Time.now}] CHECK_TOKEN: res.is_a?(Hash)=#{res.is_a?(Hash)}, res.key?('type')=#{res.is_a?(Hash) && res.key?('type')}"
                extra_log.close
              end

              if token && res.is_a?(Hash) && res.key?("type")
                if res["type"] == "error"
                  if CONFIG["EXTRA_LOGGING"]
                    extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                    extra_log.puts "[#{Time.now}] CHECK_TOKEN: Sending token_not_verified (error)"
                    extra_log.close
                  end
                  send_to_client(connection, { "type" => "token_not_verified", "token" => "", "content" => "" })
                else
                  if CONFIG["EXTRA_LOGGING"]
                    extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                    extra_log.puts "[#{Time.now}] CHECK_TOKEN: Sending token_verified (success)"
                    extra_log.close
                  end
                  send_to_client(connection, { "type" => "token_verified",
                            "token" => token, "content" => res["content"],
                            # "models" => res["models"],
                            "ai_user_initial_prompt" => MonadicApp::AI_USER_INITIAL_PROMPT })
                  if CONFIG["EXTRA_LOGGING"]
                    extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                    extra_log.puts "[#{Time.now}] CHECK_TOKEN: token_verified message sent"
                    extra_log.close
                  end
                end
              else
                if CONFIG["EXTRA_LOGGING"]
                  extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                  extra_log.puts "[#{Time.now}] CHECK_TOKEN: Sending token_not_verified (invalid response)"
                  extra_log.close
                end
                send_to_client(connection, { "type" => "token_not_verified", "token" => "", "content" => "" })
              end
            rescue StandardError => e
              if CONFIG["EXTRA_LOGGING"]
                extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
                extra_log.puts "[#{Time.now}] CHECK_TOKEN: Exception caught - #{e.class}: #{e.message}"
                extra_log.close
              end
              send_to_client(connection, { "type" => "open_ai_api_error", "token" => "", "content" => "" })
            end
          end
        when "PING"
          # Send PONG only to the connection that sent PING (connection-specific keepalive)
          send_to_client(connection, { "type" => "pong" })
        when "RESET"
          session[:messages].clear
          session[:parameters].clear
          session[:progressive_tools]&.clear  # Reset Progressive Tool Disclosure state
          session[:error] = nil
          session[:obj] = nil
          sync_session_state!
        when "LOAD"
          # Store ui_language in session parameters if provided
          if obj["ui_language"]
            session[:parameters] ||= {}
            session[:parameters]["ui_language"] = obj["ui_language"]
          end
          handle_load_message(connection)
        when "DELETE"
          handle_delete_message(connection, obj)
        when "EDIT"
          handle_edit_message(connection, obj)
        when "UPDATE_MCP_CONFIG"
          handle_mcp_config_update(connection, obj)
        when "AI_USER_QUERY"
          # Get session ID for targeted broadcasting
          ws_session_id = Thread.current[:websocket_session_id]

          # Check if there are enough messages for AI User to work with
          if session[:messages].nil? || session[:messages].size < 2
            error_msg = {
              "type" => "error",
              "content" => "ai_user_requires_conversation"
            }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(error_msg, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(error_msg)
            end
            next
          end

          thread&.join

          # Get parameters
          params = obj["contents"]["params"]

          # UI feedback
          wait_msg = { "type" => "wait", "content" => "generating_ai_user_response" }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(wait_msg, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(wait_msg)
          end

          started_msg = { "type" => "ai_user_started" }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(started_msg, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(started_msg)
          end

          # Process the request
          begin
            # Get AI user response
            result = process_ai_user(session, params)

            # Handle result
            if result["type"] == "error"
              error_result = { "type" => "error", "content" => result["content"] }.to_json
              if ws_session_id
                WebSocketHelper.send_to_session(error_result, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(error_result)
              end
            else
              # Send response to client
              ai_user_msg = { "type" => "ai_user", "content" => result["content"] }.to_json
              if ws_session_id
                WebSocketHelper.send_to_session(ai_user_msg, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(ai_user_msg)
              end

              finished_msg = { "type" => "ai_user_finished", "content" => result["content"] }.to_json
              if ws_session_id
                WebSocketHelper.send_to_session(finished_msg, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(finished_msg)
              end
            end
          rescue => e
            # Error handling
            rescue_error = { "type" => "error", "content" => { "key" => "ai_user_error", "details" => e.message } }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(rescue_error, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(rescue_error)
            end
          end
        when "HTML"
          thread&.join
          until queue.empty?
            last_one = queue.shift
            begin
              content = last_one["choices"][0]

              # Always use message content - monadic apps will have JSON in content field
              text = content["text"] || content["message"]["content"]
              pp "[DEBUG] WebSocket - text extraction: content keys = #{content.keys}, text = #{text.class}:#{text.to_s[0..100]}..." if session["parameters"]["app_name"]&.include?("Perplexity")
              # Extract thinking content uniformly from message
              thinking = content["message"]["thinking"] || content["message"]["reasoning_content"] || content["thinking"]
              
              # Check if text contains citation HTML that needs to be extracted
              citation_html = nil
              if text && text.include?("<div data-title='Citations'")
                # Extract citation HTML from the text
                if match = text.match(/(\n\n<div data-title='Citations'[^>]*>.*?<\/div>)/m)
                  citation_html = match[1]
                  # Remove citation HTML from text so it doesn't get processed by markdown
                  text = text.sub(match[1], '')
                  
                  if CONFIG["EXTRA_LOGGING"]
                    DebugHelper.debug("WebSocket: Extracted citation HTML from text", category: :api, level: :info)
                    DebugHelper.debug("WebSocket: Citation HTML: #{citation_html[0..100]}...", category: :api, level: :debug)
                  end
                end
              elsif CONFIG["EXTRA_LOGGING"]
                if text && text.match(/\[\d+\]/)
                  DebugHelper.debug("WebSocket: Found citation references but no HTML: #{text.scan(/\[\d+\]/).join(', ')}", category: :api, level: :info)
                end
              end
              

              type_continue = "Press <button class='btn btn-secondary btn-sm contBtn'>continue</button> to get more results\n"
              code_truncated = "[CODE BLOCK TRUNCATED]"

              if content["finish_reason"] && content["finish_reason"] == "length"
                if text.scan(/(?:\A|\n)```/m).size.odd?
                  text += "\n```\n\n> #{type_continue}\n#{code_truncated}"
                else
                  text += "\n\n> #{type_continue}"
                end
              end

              if content["finish_reason"] && content["finish_reason"] == "safety"
                ws_session_id = Thread.current[:websocket_session_id]
                safety_error = { "type" => "error", "content" => "api_stopped_safety" }.to_json
                if ws_session_id
                  WebSocketHelper.send_to_session(safety_error, ws_session_id)
                else
                  WebSocketHelper.broadcast_to_all(safety_error)
                end
              end

              # Extract ABC blocks before markdown processing (they're already HTML)
              abc_blocks = []
              text_for_markdown = text.gsub(/<div class="abc-code">.*?<\/div>/m) do |match|
                abc_blocks << match
                "\n\nABC_PLACEHOLDER_#{abc_blocks.size - 1}\n\n"
              end

              params = get_session_params

              # Phase 2: Server-side HTML generation disabled
              # Client-side MarkdownRenderer handles all rendering
              # Keep text in original form with ABC blocks and citations intact

              # For ABC notation, keep the HTML blocks in the text
              # MarkdownRenderer will handle them properly
              final_text = text_for_markdown
              abc_blocks.each_with_index do |block, index|
                final_text = final_text.gsub("ABC_PLACEHOLDER_#{index}", block)
              end

              # Add response suffix if present
              if params["response_suffix"]
                final_text += "\n\n" + params["response_suffix"]
              end

              # Add citation HTML back to text
              if citation_html
                final_text += citation_html
                if CONFIG["EXTRA_LOGGING"]
                  DebugHelper.debug("WebSocket: Added citation HTML to final text", category: :api, level: :info)
                end
              end

             new_data = { "mid" => SecureRandom.hex(4),
                          "role" => "assistant",
                          "text" => final_text,
                          "lang" => detect_language(final_text),
                          "app_name" => params["app_name"],
                          "monadic" => params["monadic"],
                          "active" => true } # detect_language is called only once here

              if thinking && !thinking.to_s.strip.empty?
                new_data["thinking"] = thinking
                if CONFIG["EXTRA_LOGGING"]
                  DebugHelper.debug("WebSocket: Attaching thinking block (length=#{thinking.to_s.length})", category: :ui, level: :info)
                end
              end

              # Optional: Use provider-reported usage to set assistant tokens
              # This is disabled by default to avoid confusion and keep a
              # single source of truth (tiktoken/Flask) for token counting.
              # Enable via CONFIG["TOKEN_COUNT_SOURCE"] = "provider_only" or "hybrid".
              begin
                source = (defined?(CONFIG) && CONFIG && CONFIG["TOKEN_COUNT_SOURCE"]) ? CONFIG["TOKEN_COUNT_SOURCE"].to_s.downcase : ""
                provider_usage_enabled = %w[provider_only hybrid].include?(source)
              rescue
                provider_usage_enabled = false
              end

              if provider_usage_enabled
                usage = last_one["usage"] || last_one.dig("choices", 0, "usage")
                if usage && usage.is_a?(Hash)
                  tokens = usage["output_tokens"] || usage["completion_tokens"]
                  new_data["tokens"] = tokens.to_i if tokens
                end
              end

              # Get session ID for targeted broadcasting
              ws_session_id = Thread.current[:websocket_session_id]

              # Send HTML message (conversation content)
              html_message = {
                "type" => "html",
                "content" => new_data
              }.to_json
              if ws_session_id
                WebSocketHelper.send_to_session(html_message, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(html_message)
              end

              session[:messages] << new_data
              sync_session_state!
              # Filter messages by current app_name to prevent cross-app conversation leakage
              params = get_session_params
    current_app_name = obj["app_name"] || params["app_name"]
    messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }
              past_messages_data = check_past_messages(params)

              # Send status updates
              if past_messages_data[:changed]
                status_message = { "type" => "change_status", "content" => messages }.to_json
                if ws_session_id
                  WebSocketHelper.send_to_session(status_message, ws_session_id)
                else
                  WebSocketHelper.broadcast_to_all(status_message)
                end
              end

              info_message = { "type" => "info", "content" => past_messages_data }.to_json
              if ws_session_id
                WebSocketHelper.send_to_session(info_message, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(info_message)
              end
            rescue StandardError => e
              STDERR.puts "Error processing request: #{e.message}"
              ws_session_id = Thread.current[:websocket_session_id]
              error_message = { "type" => "error", "content" => "something_went_wrong" }.to_json
              if ws_session_id
                WebSocketHelper.send_to_session(error_message, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(error_message)
              end
            end
          end
        when "UPDATE_PARAMS"
          incoming = obj["params"]
          unless incoming.is_a?(Hash)
            send_to_client(connection, { "type" => "error", "content" => "invalid_parameters" })
            next
          end

          session[:parameters] ||= {}

          sanitized = {}
          incoming.each do |key, value|
            next if key.nil?
            normalized_key = key.to_s
            next if ["message", "images", "audio", "tts_request", "ws_session_id"].include?(normalized_key)
            sanitized[normalized_key] = value
          end

          sanitized["app_name"] = sanitized["app_name"].to_s if sanitized.key?("app_name")

          session[:parameters].merge!(sanitized)

          sync_session_state!

          # Get session ID for targeted broadcasting
          ws_session_id = Thread.current[:websocket_session_id]

          begin
            param_message = {
              "type" => "parameters",
              "content" => session[:parameters],
              "from_param_update" => true
            }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(param_message, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(param_message)
            end
          rescue StandardError => e
            DebugHelper.debug("Parameter broadcast failed: #{e.message}", "websocket", level: :error) if defined?(DebugHelper)
          end

        when "SYSTEM_PROMPT"
          text = obj["content"] || ""
          
          # Initialize runtime settings for this session
          session[:runtime_settings] ||= {
            language: "auto",
            language_updated_at: nil
          }
          
          # Store conversation language preference in runtime settings (not in system prompt)
          conversation_language = obj["conversation_language"]
          session[:runtime_settings][:language] = conversation_language || "auto"
          
          if CONFIG["EXTRA_LOGGING"]
            extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
            extra_log.puts("[#{Time.now}] SYSTEM_PROMPT: Set language to #{session[:runtime_settings][:language]}")
            extra_log.puts("  Full runtime_settings: #{session[:runtime_settings].inspect}")
            extra_log.close
          end
          
          # Don't add language to the stored system prompt
          # It will be injected dynamically during API calls
          # Note: MathJax prompts are now handled by SystemPromptInjector

          params = get_session_params
          new_data = { "mid" => SecureRandom.hex(4),
                       "role" => "system",
                       "text" => text,
                       "app_name" => params["app_name"],
                       "active" => true }
          # Initial prompt is added to messages but not shown as the first message
          # WebSocketHelper.broadcast_to_all({ "type" => "html", "content" => new_data }.to_json)
          session[:messages] << new_data
          sync_session_state!

        when "SAMPLE"
          # Get session ID for targeted broadcasting
          ws_session_id = Thread.current[:websocket_session_id]

          begin
            text = obj["content"]
            images = obj["images"]
            # Generate a unique message ID
            message_id = SecureRandom.hex(4)

            params = get_session_params
            # Create message data
            new_data = {
              "mid" => message_id,
              "role" => obj["role"],
              "text" => text,
              "app_name" => params["app_name"],
              "active" => true
            }

            # Add images if present
            new_data["images"] = images if images

            # Phase 2: Server-side HTML rendering disabled
            # Client-side MarkdownRenderer now handles all rendering
            # if obj["role"] == "assistant"
            #   mathjax_enabled = params["mathjax"].to_s == "true"
            #   new_data["html"] = markdown_to_html(text, mathjax: mathjax_enabled)
            # else
            #   # For user and system roles, preserve line breaks
            #   new_data["html"] = text
            # end

            # First add to session
            session[:messages] << new_data
            sync_session_state!
            
            # Phase 2: Send text content, client handles rendering
            # The display_sample message includes both text and role info
            if obj["role"] == "user"
              badge = "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>"
            elsif obj["role"] == "assistant"
              badge = "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>"
            else # system
              badge = "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>"
            end

            # Send a dedicated message for immediate display
            display_message = {
              "type" => "display_sample",
              "content" => {
                "mid" => message_id,
                "role" => obj["role"],
                "text" => text,
                "badge" => badge
              }
            }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(display_message, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(display_message)
            end
            
            # Also send HTML message for session history
            html_message = { "type" => "html", "content" => new_data }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(html_message, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(html_message)
            end
            
            # Add a success response to confirm message was processed
            success_message = { "type" => "sample_success", "role" => obj["role"] }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(success_message, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(success_message)
            end
          rescue => e
            # Log the error
            puts "Error processing SAMPLE message: #{e.message}"
            puts e.backtrace

            # Inform the client
            error_message = { "type" => "error", "content" => "error_processing_sample" }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(error_message, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(error_message)
            end
          end
        when "AUDIO"
          handle_audio_message(connection, obj)
        when "UPDATE_LANGUAGE"
          # Get session ID for targeted broadcasting
          ws_session_id = Thread.current[:websocket_session_id]

          # Handle language change during session
          old_language = session[:runtime_settings][:language] if session[:runtime_settings]
          new_language = obj["new_language"]

          # Update UI language in parameters as well
          session[:parameters] ||= {}
          session[:parameters]["ui_language"] = new_language
          
          # Initialize runtime_settings if not exists
          session[:runtime_settings] ||= {
            language: "auto",
            language_updated_at: nil
          }
          
          if old_language != new_language
            session[:runtime_settings][:language] = new_language
            session[:runtime_settings][:language_updated_at] = Time.now
            
            if CONFIG["EXTRA_LOGGING"]
              puts "[DEBUG] UPDATE_LANGUAGE: Changed from #{old_language} to #{new_language}"
              puts "[DEBUG] Session runtime_settings after update: #{session[:runtime_settings].inspect}"
              
              # Log to file as well
              extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
              extra_log.puts("[#{Time.now}] UPDATE_LANGUAGE: #{old_language} -> #{new_language}")
              extra_log.puts("  Runtime settings: #{session[:runtime_settings].inspect}")
              extra_log.close
            end
            
            # Resend apps data with updated language descriptions
            apps_data = prepare_apps_data(new_language)
            unless apps_data.empty?
              apps_message = { "type" => "apps", "content" => apps_data }.to_json
              if ws_session_id
                WebSocketHelper.send_to_session(apps_message, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(apps_message)
              end
            end
            
            # Notify client of successful update
            language_name = if new_language == "auto"
                              "Automatic"
                            else
                              Monadic::Utils::LanguageConfig::LANGUAGES[new_language][:english]
                            end

            language_updated_message = {
              "type" => "language_updated",
              "language" => new_language,
              "language_name" => language_name,
              "text_direction" => Monadic::Utils::LanguageConfig.text_direction(new_language)
            }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(language_updated_message, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(language_updated_message)
            end
          end
        when "STOP_TTS"
          # Get session ID for targeted broadcasting
          ws_session_id = Thread.current[:websocket_session_id]

          # Stop any running TTS thread and all prefetch threads
          if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
            # Kill all prefetch subthreads first
            begin
              tts_futures = @tts_thread[:tts_futures]
              if tts_futures && tts_futures.is_a?(Array)
                tts_futures.each do |future_thread|
                  future_thread.kill if future_thread && future_thread.alive?
                rescue => e
                  # Already dead or error during kill - safe to ignore
                end
              end
            rescue => e
              # Error accessing thread locals - continue with main thread cleanup
              puts "Error cleaning up TTS subthreads: #{e.message}" if CONFIG["EXTRA_LOGGING"]
            end

            # Kill main TTS thread
            @tts_thread.kill
            @tts_thread = nil
            puts "TTS thread and subthreads stopped by STOP_TTS message"
          end

          # Send confirmation
          tts_stopped_message = { "type" => "tts_stopped" }.to_json
          if ws_session_id
            WebSocketHelper.send_to_session(tts_stopped_message, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(tts_stopped_message)
          end
        when "PLAY_TTS"
          # Handle play TTS message
          # This is similar to auto_speech processing but for card playback

          # Stop any existing TTS thread first
          if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
            @tts_thread.kill
            @tts_thread = nil
          end

          thread&.join

          # Extract TTS parameters
          provider = obj["tts_provider"]
          if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
            voice = obj["elevenlabs_tts_voice"]
          elsif provider == "gemini-flash" || provider == "gemini-pro"
            voice = obj["gemini_tts_voice"]
          else
            voice = obj["tts_voice"]
          end
          text = obj["text"]
          speed = obj["tts_speed"]
          response_format = "mp3"
          language = obj["conversation_language"] || "auto"

          # Use common TTS playback method
          start_tts_playback(
            text: text,
            provider: provider,
            voice: voice,
            speed: speed,
            response_format: response_format,
            language: language
          )
        else # fragment
          # Get session ID for targeted broadcasting throughout streaming
          ws_session_id = Thread.current[:websocket_session_id]

          session[:parameters].merge! obj

          # Start background token counting for the user message immediately
          message_text = obj["message"].to_s
          if !message_text.empty?
            # Use o200k_base encoding for most LLMs
            token_count_thread = initialize_token_counting(message_text, "o200k_base")
            Thread.current[:token_count_thread] = token_count_thread
          end

          # Extract TTS parameters if auto_speech is enabled
          # Convert string "true" to boolean true for compatibility
          obj["auto_speech"] = true if obj["auto_speech"] == "true"

          # Get auto_tts_realtime_mode setting
          # TEMPORARILY DISABLED (2025-11-07): Realtime mode has a race condition where
          # LLM streaming can split words mid-character (e.g., "チャット" → "チャ" + "ット"),
          # causing PragmaticSegmenter to mark sentences as "complete" before all characters
          # arrive. This results in truncated TTS audio (e.g., "チャット" → "チャ").
          # The Async migration exposed this timing issue that was masked by EventMachine's
          # synchronous processing. Need to add fragment stabilization (wait 50-100ms after
          # sentence boundary) before re-enabling.
          # auto_tts_realtime_mode = obj["auto_tts_realtime_mode"]
          # if auto_tts_realtime_mode.nil?
          #   auto_tts_realtime_mode = defined?(CONFIG) && CONFIG["AUTO_TTS_REALTIME_MODE"].to_s == "true"
          # end
          auto_tts_realtime_mode = false  # Force POST-COMPLETION mode until race condition is fixed

          if obj["auto_speech"]
            provider = obj["tts_provider"]
            if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
              voice = obj["elevenlabs_tts_voice"]
            elsif provider == "gemini-flash" || provider == "gemini-pro"
              voice = obj["gemini_tts_voice"]
            else
              voice = obj["tts_voice"]
            end
            speed = obj["tts_speed"]
            response_format = "mp3"
            model = "tts-1"
            language = obj["conversation_language"] || "auto"
          end

          thread = Thread.new do
            # Set thread type for identification
            Thread.current[:type] = :tts
            
            # If we have a token counting thread, wait for it to complete and save result
            if defined?(token_count_thread) && token_count_thread
              begin
                # Don't wait forever, time out after 2 seconds
                Timeout.timeout(2) do
                  token_count_result = token_count_thread.value
                  if token_count_result
                    Thread.current[:token_count_result] = token_count_result 
                  end
                end
              rescue Timeout::Error
                # Log timeout and continue without precounted tokens
                if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
                  logger.warn "Token counting timeout - continuing without precount"
                end
              rescue => e
                # Log error but continue operation
                if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
                  logger.warn "Token counting error in WebSocket handler: #{e.message}"
                end
              end
            end
            
            buffer = []
            cutoff = false

            # Initialize sequence counter for realtime TTS (once per message)
            @realtime_tts_sequence_counter = 0

            # Initialize short sentence buffer for realtime TTS
            @realtime_tts_short_buffer = []

            # Save original auto_speech and monadic values before they might be overwritten
            # These will be used for final segment processing after streaming completes
            original_auto_speech = obj["auto_speech"]
            original_monadic = obj["monadic"]

            app_name = obj["app_name"]
            app_obj = APPS[app_name]
            
            # Debug logging for troubleshooting
            if CONFIG["EXTRA_LOGGING"] && app_name && (app_name.include?("Perplexity") || app_name.include?("DeepSeek"))
              puts "[DEBUG WebSocket] Processing message for app: #{app_name}"
              puts "[DEBUG WebSocket] App object found: #{!app_obj.nil?}"
              puts "[DEBUG WebSocket] ChatPlusPerplexity exists: #{APPS.key?("ChatPlusPerplexity")}"
              puts "[DEBUG WebSocket] All Chat Plus apps: #{APPS.keys.select { |k| k.include?("ChatPlus") }}"
              puts "[DEBUG WebSocket] Total apps count: #{APPS.keys.length}"
            end
            
            unless app_obj
              error_msg = "App '#{app_name}' not found in APPS"
              puts "[ERROR] #{error_msg}"
              error_message = { "type" => "error", "content" => error_msg }.to_json
              if ws_session_id
                WebSocketHelper.send_to_session(error_message, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(error_message)
              end
              next
            end

            prev_texts_for_tts = []
            responses = app_obj.api_request("user", session) do |fragment|
              # DEBUG: Log all fragment arrivals
              if CONFIG["EXTRA_LOGGING"]
                File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                  log.puts("[#{Time.now}] [DEBUG] Fragment arrived: type='#{fragment["type"]}', auto_speech=#{obj["auto_speech"]}, cutoff=#{cutoff}, monadic=#{obj["monadic"]}, auto_tts_realtime_mode=#{auto_tts_realtime_mode}")
                end
              end

              if fragment["type"] == "error"
                fragment_error = { "type" => "error", "content" => fragment }.to_json
                if ws_session_id
                  WebSocketHelper.send_to_session(fragment_error, ws_session_id)
                else
                  WebSocketHelper.broadcast_to_all(fragment_error)
                end
                break
              elsif fragment["type"] == "fragment"
                text = fragment["content"]
                buffer << text unless text.empty? || text == "DONE"

                ps = PragmaticSegmenter::Segmenter.new(text: buffer.join)
                segments = ps.segment

                if CONFIG["EXTRA_LOGGING"]
                  File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                    log.puts("[#{Time.now}] [DEBUG] Fragment received: buffer_text='#{buffer.join[0..100]}...', segments=#{segments.size}")
                    segments.each_with_index do |seg, i|
                      log.puts("[#{Time.now}] [DEBUG]   segment[#{i}]: '#{seg[0..50]}...'")
                    end
                  end
                end

                # Wait for complete sentences: PragmaticSegmenter returns 2+ segments when a sentence is complete
                # Process all complete sentences (all except the last incomplete one)
                if !cutoff && segments.size >= 2
                  complete_sentences = segments[0...-1]

                  if auto_tts_realtime_mode
                    # REALTIME MODE: Use http.rb async processing for non-blocking TTS
                    if CONFIG["EXTRA_LOGGING"]
                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                        log.puts("[#{Time.now}] [DEBUG] REALTIME MODE ACTIVE: auto_speech=#{obj["auto_speech"]}, cutoff=#{cutoff}, monadic=#{obj["monadic"]}, segments=#{segments.size}")
                        log.puts("[#{Time.now}] [DEBUG] complete_sentences count: #{segments[0...-1].size}")
                      end
                    end

                    # Process each complete sentence with buffering for short sentences
                    # This prevents pauses between short and long sentence TTS generation
                    complete_sentences.each_with_index do |sentence, idx|
                      split = sentence.split("---")
                      if split.empty?
                        cutoff = true
                        break
                      end

                      # Process sentence fragments for TTS if auto_speech is enabled
                      if obj["auto_speech"] && !cutoff && !obj["monadic"]
                        text = split[0] || ""

                        # Strip Markdown markers and HTML tags before TTS processing
                        text = StringUtils.strip_markdown_for_tts(text)

                        # Filter out very short or emoji-only segments
                        cleaned_text = text.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
                        cleaned_text = cleaned_text.gsub(/^\s*[-*]\s+/, '').gsub(/^\s*\d+\.\s+/, '')
                        cleaned_text = cleaned_text.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ')
                        cleaned_text = cleaned_text.strip

                        if CONFIG["EXTRA_LOGGING"]
                          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                            log.puts("[#{Time.now}] [BUFFER] ============================================")
                            log.puts("[#{Time.now}] [BUFFER] Sentence #{idx} received")
                            log.puts("[#{Time.now}] [BUFFER] Original text: '#{text}'")
                            log.puts("[#{Time.now}] [BUFFER] Cleaned text: '#{cleaned_text}'")
                            log.puts("[#{Time.now}] [BUFFER] Cleaned length: #{cleaned_text.length}")
                          end
                        end

                        # Skip only if text is empty
                        if text.strip != ""
                          # Check if this is a short sentence (≤REALTIME_TTS_MIN_LENGTH chars cleaned length)
                          if cleaned_text.length <= REALTIME_TTS_MIN_LENGTH
                            # Buffer short sentence instead of sending immediately
                            @realtime_tts_short_buffer << text

                            # Calculate total buffer length
                            total_buffer_length = @realtime_tts_short_buffer.map do |buffered_text|
                              cleaned = buffered_text.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
                              cleaned = cleaned.gsub(/^\s*[-*]\s+/, '').gsub(/^\s*\d+\.\s+/, '')
                              cleaned = cleaned.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ')
                              cleaned.strip.length
                            end.sum

                            if CONFIG["EXTRA_LOGGING"]
                              File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                log.puts("[#{Time.now}] [BUFFER] Decision: BUFFERING (≤#{REALTIME_TTS_MIN_LENGTH} chars)")
                                log.puts("[#{Time.now}] [BUFFER] Buffer size: #{@realtime_tts_short_buffer.size} sentence(s)")
                                log.puts("[#{Time.now}] [BUFFER] Total buffer length: #{total_buffer_length} chars")
                                log.puts("[#{Time.now}] [BUFFER] Buffer contents:")
                                @realtime_tts_short_buffer.each_with_index do |buf_text, buf_idx|
                                  log.puts("[#{Time.now}] [BUFFER]   [#{buf_idx}]: '#{buf_text}'")
                                end
                              end
                            end

                            # Check if total buffer length exceeds threshold
                            # This prevents long pauses while maintaining gap prevention
                            if total_buffer_length > REALTIME_TTS_MIN_LENGTH
                              # Flush buffer when accumulated length is sufficient
                              # Add space between sentences to prevent words from merging
                              combined_text = @realtime_tts_short_buffer.join(" ")
                              @realtime_tts_short_buffer.clear

                              if CONFIG["EXTRA_LOGGING"]
                                File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                  log.puts("[#{Time.now}] [BUFFER] *** FLUSHING BUFFER (total: #{total_buffer_length} > #{REALTIME_TTS_MIN_LENGTH}) ***")
                                  log.puts("[#{Time.now}] [BUFFER] Combined text to send to TTS: '#{combined_text}'")
                                  log.puts("[#{Time.now}] [BUFFER] Combined text length: #{combined_text.length}")
                                end
                              end

                              # Increment counters and create sequence ID
                              @realtime_tts_sequence_counter += 1
                              sequence_num = @realtime_tts_sequence_counter
                              sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

                              # Submit TTS request immediately
                              Async do
                                tts_api_request_em(
                                  combined_text,
                                  provider: provider,
                                  voice: voice,
                                  speed: speed,
                                  response_format: response_format,
                                  language: language,
                                  sequence_id: sequence_id
                                ) do |res_hash|
                                  if res_hash && res_hash["type"] != "error"
                                    if CONFIG["EXTRA_LOGGING"]
                                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                        log.puts("[#{Time.now}] [DEBUG] TTS async callback (flushed buffer): sequence_id=#{sequence_id}, type=#{res_hash["type"]}")
                                      end
                                    end
                                    # Use captured ws_session_id from outer scope
                                    if ws_session_id
                                      WebSocketHelper.send_to_session(res_hash.to_json, ws_session_id)
                                    else
                                      WebSocketHelper.broadcast_to_all(res_hash.to_json)
                                    end
                                  else
                                    if CONFIG["EXTRA_LOGGING"]
                                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                        log.puts("[#{Time.now}] [DEBUG] TTS failed for flushed buffer: #{res_hash&.[]("content")}")
                                      end
                                    end
                                  end
                                end
                              end
                            end
                          else
                            # This is a longer sentence - flush buffer and send combined text
                            if CONFIG["EXTRA_LOGGING"]
                              File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                log.puts("[#{Time.now}] [BUFFER] Decision: IMMEDIATE SEND (>#{REALTIME_TTS_MIN_LENGTH} chars)")
                                log.puts("[#{Time.now}] [BUFFER] Current buffer has #{@realtime_tts_short_buffer.size} sentence(s)")
                              end
                            end

                            combined_text = if @realtime_tts_short_buffer.empty?
                                             text
                                           else
                                             # Combine buffered short sentences with current sentence
                                             # Add space between sentences to prevent words from merging
                                             buffered = @realtime_tts_short_buffer.join(" ")
                                             @realtime_tts_short_buffer.clear
                                             "#{buffered} #{text}"
                                           end

                            # Increment counters and create sequence ID
                            @realtime_tts_sequence_counter += 1
                            sequence_num = @realtime_tts_sequence_counter
                            sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

                            if CONFIG["EXTRA_LOGGING"]
                              File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                log.puts("[#{Time.now}] [BUFFER] *** SENDING TO TTS (long sentence) ***")
                                log.puts("[#{Time.now}] [BUFFER] Sequence: #{sequence_num}, ID: #{sequence_id}")
                                log.puts("[#{Time.now}] [BUFFER] Combined text to send: '#{combined_text}'")
                                log.puts("[#{Time.now}] [BUFFER] Combined text length: #{combined_text.length}")
                              end
                            end

                            # Submit TTS request immediately
                            Async do
                              tts_api_request_em(
                                combined_text,
                                provider: provider,
                                voice: voice,
                                speed: speed,
                                response_format: response_format,
                                language: language,
                                sequence_id: sequence_id
                              ) do |res_hash|
                                # This callback runs when TTS completes
                                if res_hash && res_hash["type"] != "error"
                                  if CONFIG["EXTRA_LOGGING"]
                                    File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                      log.puts("[#{Time.now}] [DEBUG] TTS async callback: sequence_id=#{sequence_id}, type=#{res_hash["type"]}")
                                    end
                                  end

                                  # Send audio to client (use captured ws_session_id)
                                  if ws_session_id
                                    WebSocketHelper.send_to_session(res_hash.to_json, ws_session_id)
                                  else
                                    WebSocketHelper.broadcast_to_all(res_hash.to_json)
                                  end
                                else
                                  # TTS failed, just log it (fragment already sent)
                                  if CONFIG["EXTRA_LOGGING"]
                                    File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                                      log.puts("[#{Time.now}] [DEBUG] TTS failed for segment: #{res_hash&.[]("content")}")
                                    end
                                  end
                                end
                              end
                            end
                          end
                        end
                      end
                    end

                    # REALTIME MODE: Keep the last incomplete sentence in buffer
                    buffer = [segments.last]

                    # Send the fragment to display text (after TTS processing)
                    if ws_session_id
                      WebSocketHelper.send_to_session(fragment.to_json, ws_session_id)
                    else
                      WebSocketHelper.broadcast_to_all(fragment.to_json)
                    end
                  else
                    # POST-COMPLETION MODE: Just send fragments, keep everything in buffer
                    if ws_session_id
                      WebSocketHelper.send_to_session(fragment.to_json, ws_session_id)
                    else
                      WebSocketHelper.broadcast_to_all(fragment.to_json)
                    end
                  end
                else
                  # Just send the fragment without TTS processing
                  if ws_session_id
                    WebSocketHelper.send_to_session(fragment.to_json, ws_session_id)
                  else
                    WebSocketHelper.broadcast_to_all(fragment.to_json)
                  end
                end
              else
                # Handle other fragment types
                if ws_session_id
                  WebSocketHelper.send_to_session(fragment.to_json, ws_session_id)
                else
                  WebSocketHelper.broadcast_to_all(fragment.to_json)
                end
              end
              sleep 0.01
            end

            Thread.exit if !responses || responses.empty?

            # Process final segment for realtime mode
            # The last incomplete sentence in buffer needs to be processed after streaming completes
            # Check both auto_speech and auto_tts_realtime_mode to ensure TTS is intentionally enabled
            # auto_speech can be boolean true or string "true" from client
            # Use original_auto_speech saved before streaming started (obj may have been overwritten)
            auto_speech_enabled = original_auto_speech == true || original_auto_speech == "true"

            if CONFIG["EXTRA_LOGGING"]
              File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                log.puts("[#{Time.now}] [DEBUG] Checking final segment conditions:")
                log.puts("[#{Time.now}] [DEBUG]   original_auto_speech=#{original_auto_speech.inspect}, auto_speech_enabled=#{auto_speech_enabled}")
                log.puts("[#{Time.now}] [DEBUG]   cutoff=#{cutoff}, original_monadic=#{original_monadic}, auto_tts_realtime_mode=#{auto_tts_realtime_mode}")
                log.puts("[#{Time.now}] [DEBUG]   Buffer contents: #{buffer.inspect}")
                log.puts("[#{Time.now}] [DEBUG]   Short buffer: #{@realtime_tts_short_buffer.inspect}")
              end
            end

            if auto_speech_enabled && auto_tts_realtime_mode && !cutoff && !original_monadic
              # Get final text from buffer
              final_text = buffer.join.strip

              if CONFIG["EXTRA_LOGGING"]
                File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                  log.puts("[#{Time.now}] [DEBUG] Final text from buffer: '#{final_text}'")
                end
              end

              # Also check if there are any buffered short sentences that haven't been sent yet
              if !@realtime_tts_short_buffer.empty?
                # Combine buffered short sentences with final text
                # Add space between sentences to prevent words from merging
                buffered = @realtime_tts_short_buffer.join(" ")
                final_text = if final_text.empty?
                              buffered
                            else
                              "#{buffered} #{final_text}"
                            end
                @realtime_tts_short_buffer.clear

                if CONFIG["EXTRA_LOGGING"]
                  File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                    log.puts("[#{Time.now}] [DEBUG] REALTIME MODE: Flushing buffered short sentences into final segment")
                  end
                end
              end

              if final_text != ""
                if CONFIG["EXTRA_LOGGING"]
                  File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                    log.puts("[#{Time.now}] [DEBUG] REALTIME MODE: Processing final segment: '#{final_text[0..50]}...' (length=#{final_text.length})")
                  end
                end

                # Generate unique sequence ID for final segment (use same format as streaming segments)
                # Counter should already be initialized by streaming loop above
                @realtime_tts_sequence_counter += 1
                sequence_num = @realtime_tts_sequence_counter
                sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

                # Call async TTS for final segment
                tts_api_request_em(
                  final_text,
                  provider: provider,
                  voice: voice,
                  speed: speed,
                  response_format: response_format,
                  language: language,
                  sequence_id: sequence_id
                ) do |res_hash|
                  if res_hash && res_hash["type"] != "error"
                    if CONFIG["EXTRA_LOGGING"]
                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                        log.puts("[#{Time.now}] [DEBUG] TTS final segment callback: sequence_id=#{sequence_id}, type=#{res_hash["type"]}")
                      end
                    end
                    # Use captured ws_session_id from outer scope
                    if ws_session_id
                      WebSocketHelper.send_to_session(res_hash.to_json, ws_session_id)
                    else
                      WebSocketHelper.broadcast_to_all(res_hash.to_json)
                    end
                  else
                    if CONFIG["EXTRA_LOGGING"]
                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                        log.puts("[#{Time.now}] [DEBUG] TTS failed for final segment: #{res_hash&.[]("content")}")
                      end
                    end
                  end
                end
              end
            end

            # Post-completion TTS processing when realtime mode is FALSE
            # Use original_auto_speech (saved before fragment loop) because obj may be overwritten
            # Convert string "true" to boolean true for compatibility
            auto_speech_enabled = original_auto_speech == true || original_auto_speech == "true"

            # Check if monadic is nil or empty string (both should be treated as false/disabled)
            monadic_disabled = original_monadic.nil? || original_monadic.to_s.strip.empty?

            if CONFIG["EXTRA_LOGGING"]
              File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
                log.puts("[#{Time.now}] [DEBUG] POST-COMPLETION MODE conditions:")
                log.puts("[#{Time.now}] [DEBUG]   original_auto_speech=#{original_auto_speech.inspect}, auto_speech_enabled=#{auto_speech_enabled.inspect}")
                log.puts("[#{Time.now}] [DEBUG]   cutoff=#{cutoff.inspect}")
                log.puts("[#{Time.now}] [DEBUG]   original_monadic=#{original_monadic.inspect}, monadic_disabled=#{monadic_disabled.inspect}")
                log.puts("[#{Time.now}] [DEBUG]   auto_tts_realtime_mode=#{auto_tts_realtime_mode.inspect}")
                log.puts("[#{Time.now}] [DEBUG]   Combined condition=#{(auto_speech_enabled && !cutoff && monadic_disabled && !auto_tts_realtime_mode).inspect}")
              end
            end

            if auto_speech_enabled && !cutoff && monadic_disabled && !auto_tts_realtime_mode
              # Stop any existing TTS thread first
              if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
                @tts_thread.kill
                @tts_thread = nil
              end

              # Get complete text from buffer
              text = buffer.join

              # Only process if there's actual text
              if text.strip != ""
                # Use common TTS playback method
                start_tts_playback(
                  text: text,
                  provider: provider,
                  voice: voice,
                  speed: speed,
                  response_format: response_format,
                  language: language
                )
              end
            end

            responses.each do |response|
              # if response is not a hash, skip with error message
              unless response.is_a?(Hash)
                STDERR.puts "Invalid API response format: #{response.class}"
                next
              end

              if response.key?("type") && response["type"] == "error"
                # Extract error message if available, otherwise use the full response
                error_content = if response.key?("content") && !response["content"].to_s.empty?
                                 response["content"].to_s
                               else
                                 "API Error: " + response.to_s
                               end
                api_error_message = { "type" => "error", "content" => error_content }.to_json
                if ws_session_id
                  WebSocketHelper.send_to_session(api_error_message, ws_session_id)
                else
                  WebSocketHelper.broadcast_to_all(api_error_message)
                end
              else
                # Debug logging for response structure (only with EXTRA_LOGGING)
                if CONFIG["EXTRA_LOGGING"]
                  puts "WebSocket response structure:"
                  puts "Response class: #{response.class}"
                  puts "Response keys: #{response.keys.inspect}" if response.is_a?(Hash)
                  puts "Has choices?: #{response.key?("choices") if response.is_a?(Hash)}"
                  puts "Response: #{response.inspect[0..500]}..." # First 500 chars
                end
                
                # Check for content in standard format or responses API format
                raw_content = nil
                
                # Try standard format first
                raw_content = response.dig("choices", 0, "message", "content")
                
                # If not found, try responses API format
                if raw_content.nil? && response["output"]
                  if CONFIG["EXTRA_LOGGING"]
                    puts "Trying responses API format. Output items: #{response["output"].length}"
                  end
                  
                  # Look for message type in output array
                  response["output"].each do |item|
                    if CONFIG["EXTRA_LOGGING"]
                      puts "Output item type: #{item["type"]}, has content?: #{item.key?("content")}"
                    end
                    
                    if item["type"] == "message" && item["content"]
                      # Extract text from content array
                      if item["content"].is_a?(Array)
                        item["content"].each do |content_item|
                          # Handle both "text" and "output_text" types
                          if (content_item["type"] == "text" || content_item["type"] == "output_text") && content_item["text"]
                            raw_content ||= ""
                            raw_content += content_item["text"]
                          end
                        end
                      elsif item["content"].is_a?(String)
                        raw_content = item["content"]
                      end
                    end
                  end
                  
                  if CONFIG["EXTRA_LOGGING"]
                    puts "Extracted content length: #{raw_content&.length || 0}"
                  end
                end
                
                # If still no content found
                if raw_content.nil?
                  puts "ERROR: Content not found. Response structure: #{response.inspect[0..300]}..." if CONFIG["EXTRA_LOGGING"]
                  content_error = { "type" => "error", "content" => "content_not_found" }.to_json
                  if ws_session_id
                    WebSocketHelper.send_to_session(content_error, ws_session_id)
                  else
                    WebSocketHelper.broadcast_to_all(content_error)
                  end
                  break
                end
                if raw_content
                  # Fix sandbox URL paths with a more precise regex that ensures we only replace complete paths
                  content = raw_content.gsub(%r{\bsandbox:/([^\s"'<>]+)}, '/\1')
                  # Fix mount paths in the same way
                  content = content.gsub(%r{^/mnt/([^\s"'<>]+)}, '/\1')
                else
                  content = ""
                  empty_response_error = { "type" => "error", "content" => "empty_response" }.to_json
                  if ws_session_id
                    WebSocketHelper.send_to_session(empty_response_error, ws_session_id)
                  else
                    WebSocketHelper.broadcast_to_all(empty_response_error)
                  end
                end

                response.dig("choices", 0, "message")["content"] = content

                if obj["auto_speech"] && obj["monadic"]
                  begin
                    parsed_content = JSON.parse(content)
                    message = parsed_content["message"]
                    
                    if message && !message.empty?
                      res_hash = tts_api_request(message,
                                                provider: provider,
                                                voice: voice,
                                                speed: speed,
                                                response_format: response_format)
                      # Use captured ws_session_id for session-targeted broadcasting
                      if res_hash
                        if ws_session_id
                          WebSocketHelper.send_to_session(res_hash.to_json, ws_session_id)
                        else
                          WebSocketHelper.broadcast_to_all(res_hash.to_json)
                        end
                      end
                    end
                  rescue JSON::ParserError => e
                    # Log the error but don't crash
                    puts "[TTS] Failed to parse monadic response for TTS: #{e.message}"
                  end
                end

                queue.push(response)
              end
            end
            
            # Send streaming complete message after all responses are processed (session-targeted)
            streaming_complete = { "type" => "streaming_complete" }.to_json
            if ws_session_id
              WebSocketHelper.send_to_session(streaming_complete, ws_session_id)
            else
              WebSocketHelper.broadcast_to_all(streaming_complete)
            end
          end
        end
      end # end case
    end # end while

    rescue => e
      if CONFIG["EXTRA_LOGGING"]
        puts "[WebSocket] Error in message loop: #{e.class}: #{e.message}"
        puts e.backtrace.first(5)
      end
    ensure
      WebSocketHelper.remove_connection_with_session(connection, ws_session_id)

      if CONFIG["EXTRA_LOGGING"]
        puts "[WebSocket] Connection closed for session #{ws_session_id}"
      end

      sync_session_state!

      Thread.current[:websocket_session_id] = nil
      Thread.current[:rack_session] = nil

      thread&.kill
    end
  end

  def send_to_client(connection, message_hash)
    connection.write(message_hash.to_json)
    connection.flush
  rescue => e
    if CONFIG["EXTRA_LOGGING"]
      puts "[WebSocket] Error sending to client: #{e.message}"
    end
  end

  # Handle MCP configuration update
  def handle_mcp_config_update(connection, obj)
    # Update configuration
    CONFIG["MCP_SERVER_ENABLED"] = obj["enabled"] # Keep as boolean
    CONFIG["MCP_SERVER_PORT"] = obj["port"] if obj["port"]
    
    # Write updated config to file (optional - depends on persistence requirements)
    # This would require implementing a save_config method
    
    # Send updated MCP server status
    if defined?(Monadic::MCP::Server)
      mcp_status = Monadic::MCP::Server.status
      send_to_client(connection, { "type" => "mcp_status", "content" => mcp_status })
    end

    send_to_client(connection, { "type" => "info", "content" => "MCP configuration updated" })
  end
end
