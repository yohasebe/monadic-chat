# frozen_string_literal: true

# Application data preparation and loading for WebSocket connections.
# Handles initial page load, app settings preparation,
# message filtering, and status updates.

module WebSocketHelper
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
    Monadic::Utils::ExtraLogger.log { "[DEBUG] prepare_apps_data called with ui_language: #{ui_language}" }

    apps = {}
    largest_app_sizes = {}

    # Pre-fetch Ollama models once (not per-app) to avoid redundant API calls
    ollama_models = if defined?(OllamaHelper) && OllamaHelper.find_endpoint
                      OllamaHelper.list_models
                    else
                      nil
                    end

    APPS.each do |k, v|
      apps[k] = {}
      v.settings.each do |p, m|
        # Debug log for reasoning_effort in all OpenAI apps
        Monadic::Utils::ExtraLogger.log { "WebSocket: #{k} reasoning_effort = #{m.inspect}" } if p == "reasoning_effort"
        
        # Handle description specially for multi-language support
        if p == "description"
          if m.is_a?(Hash)
            # Multi-language description: select the appropriate language
            # Fallback order: requested language -> English -> first available
            selected_desc = m[ui_language] || m["en"] || m.values.first || ""
            apps[k][p] = selected_desc
            
            # Debug logging for multi-language descriptions
            if k == "SampleMultilang"
              Monadic::Utils::ExtraLogger.log { "[DEBUG] SampleMultilang description selection:\n  Requested language: #{ui_language}\n  Available languages: #{m.keys.join(', ')}\n  Selected description: #{selected_desc[0..50]}..." }
            end
          else
            # Single string description (backward compatibility)
            apps[k][p] = m ? m.to_s : ""
          end
        # Special case for models array to ensure it's properly sent as JSON.
        # For Ollama apps, always refresh the model list from the live Ollama
        # service so that newly pulled/removed models appear without a server
        # restart. Other providers have stable model lists from their APIs.
        elsif p == "models" && m.is_a?(Array)
          if v.settings["provider"]&.downcase == "ollama" && ollama_models && !ollama_models.empty?
            v.settings["models"] = ollama_models
            apps[k][p] = ollama_models.to_json
            next
          end
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
          Monadic::Utils::ExtraLogger.log { "[DEBUG WebSocket] #{k} imported_tool_groups: #{tool_groups_with_availability.to_json}" }
        elsif p == "disabled"
          # Keep disabled as a string for compatibility with frontend
          apps[k][p] = m.to_s
        elsif ["auto_speech", "easy_submit", "initiate_from_assistant", "math", "mermaid", "abc", "monadic", "pdf_vector_storage", "websearch", "jupyter", "image_generation", "video", "audio_upload"].include?(p.to_s)
          # Preserve boolean values for feature flags
          # These need to be actual booleans, not strings, for proper JavaScript evaluation
          apps[k][p] = m
        else
          apps[k][p] = m ? m.to_s : nil
        end
      end

      # Track size of this app's data
      if Monadic::Utils::ExtraLogger.enabled?
        app_json = apps[k].to_json
        app_size = app_json.bytesize
        largest_app_sizes[k] = app_size if app_size > 10_000 # Track apps > 10KB
      end
    end

    # Log largest apps
    if !largest_app_sizes.empty?
      Monadic::Utils::ExtraLogger.log {
        lines = ["Apps data sizes:"]
        largest_app_sizes.sort_by { |_, size| -size }.take(5).each do |name, size|
          lines << "  #{name}: #{size} bytes (#{(size / 1024.0).round(2)} KB)"
        end
        total_size = apps.to_json.bytesize
        lines << "  TOTAL: #{total_size} bytes (#{(total_size / 1024.0).round(2)} KB)"
        lines.join("\n")
      }
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
    Monadic::Utils::ExtraLogger.log { "prepare_filtered_messages: #{session[:messages]&.size || 0} total → #{filtered_messages.size} filtered (app=#{current_app_name || 'NONE'})" }

    params_for_render = params
    math_enabled = params_for_render["math"].to_s == "true"

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
    Monadic::Utils::ExtraLogger.log {
      params_present = rack_session[:parameters] && !rack_session[:parameters].empty?
      "push_apps_data START: session=#{ws_session_id}, apps=#{apps.size}, params present=#{params_present}, messages=#{filtered_messages.size}, from_initial_load=#{from_initial_load}"
    }

    # Send apps message
    apps_message = {
      "type" => "apps",
      "content" => apps,
      "version" => rack_session[:version],
      "docker" => rack_session[:docker]
    }
    unless apps.empty?
      send_or_broadcast(apps_message.to_json, ws_session_id)
    end

    # Use sleep to delay subsequent messages, giving browser time to process large apps message
    # This prevents message loss when apps message is very large (>1MB)
    sleep(0.05)
    # Always send parameters message, even if empty, to ensure new tabs start with clean state
    # This prevents tabs from inheriting old parameters from localStorage
    send_or_broadcast({ "type" => "parameters", "content" => rack_session[:parameters] || {} }.to_json, ws_session_id)

    # Debug logging
    Monadic::Utils::ExtraLogger.log { "push_apps_data: Sent parameters message to session #{ws_session_id}" }

    # Send past_messages with additional delay to ensure parameters is processed first
    # Add from_initial_load flag to suppress Auto TTS during automatic session restoration
    sleep(0.05)  # Additional 0.05s delay (total 0.1s from start)
    past_messages_data = { "type" => "past_messages", "content" => filtered_messages }
    past_messages_data["from_initial_load"] = true if from_initial_load
    send_or_broadcast(past_messages_data.to_json, ws_session_id)

    # Debug logging for past_messages (only when EXTRA_LOGGING is enabled)
    Monadic::Utils::ExtraLogger.log { "push_apps_data: Sent past_messages with #{filtered_messages.size} items to session #{ws_session_id}" }

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
    send_or_broadcast({ "type" => "info", "content" => info_data }.to_json, ws_session_id)

    # Debug logging for info message (only when EXTRA_LOGGING is enabled)
    Monadic::Utils::ExtraLogger.log { "push_apps_data: Sent info message to hide spinner" }
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
      send_or_broadcast(status_message, ws_session_id)
    end

    # Send info message
    info_message = { "type" => "info", "content" => past_messages_data }.to_json
    send_or_broadcast(info_message, ws_session_id)

    sync_session_state!
  end

end
