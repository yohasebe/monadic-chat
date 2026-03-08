# frozen_string_literal: true

# Message editing and deletion handlers for WebSocket connections.
# Handles message deletion, editing, turn pair finding,
# HTML generation, and status updates after edits.

module WebSocketHelper
  # Handle DELETE message
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_delete_message(connection, obj)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Get session from thread context (set in handle_websocket_connection)
    rack_session = Thread.current[:rack_session] || {}

    messages = rack_session[:messages] || []
    message_index = messages.find_index { |m| m["mid"] == obj["mid"] }

    # Calculate turn number before deletion (if it's an assistant message)
    deleted_turn = nil
    if message_index
      deleted_turn = calculate_turn_number(messages, message_index)
    end

    # Delete the message
    rack_session[:messages]&.delete_if { |m| m["mid"] == obj["mid"] }

    # Update Session Context if a turn was deleted
    if deleted_turn
      schema = get_context_schema(rack_session)
      handle_message_deletion(rack_session, deleted_turn, schema, ws_session_id)
    end

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
  
  # Find the user-assistant pair for a given turn
  # @param messages [Array] The messages array
  # @param turn [Integer] The turn number (1-indexed)
  # @return [Hash, nil] Hash with :user and :assistant messages, or nil
  def find_turn_pair(messages, turn)
    return nil unless messages && turn && turn > 0

    assistant_count = 0
    assistant_index = nil

    # Find the assistant message for this turn
    messages.each_with_index do |m, idx|
      if m["role"] == "assistant"
        assistant_count += 1
        if assistant_count == turn
          assistant_index = idx
          break
        end
      end
    end

    return nil unless assistant_index

    # Find the preceding user message
    user_message = nil
    (assistant_index - 1).downto(0) do |idx|
      if messages[idx]["role"] == "user"
        user_message = messages[idx]
        break
      end
    end

    {
      user: user_message,
      assistant: messages[assistant_index]
    }
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
      edited_message = messages[message_index]
      edited_role = edited_message["role"]

      # Calculate turn number if this is an assistant message, or find the associated turn for user message
      turn_to_update = nil
      if edited_role == "assistant"
        turn_to_update = calculate_turn_number(messages, message_index)
      elsif edited_role == "user"
        # Find the next assistant message to determine the turn
        (message_index + 1...messages.length).each do |idx|
          if messages[idx]["role"] == "assistant"
            turn_to_update = calculate_turn_number(messages, idx)
            break
          end
        end
      end

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

      # Re-extract Session Context for the affected turn
      if turn_to_update
        # Get the updated turn pair (after the edit)
        turn_pair = find_turn_pair(messages, turn_to_update)

        if turn_pair && turn_pair[:user] && turn_pair[:assistant]
          schema = get_context_schema(rack_session)
          provider = rack_session.dig(:parameters, "ai_provider") || "openai"
          language = rack_session.dig(:runtime_settings, :language) || rack_session.dig("runtime_settings", "language")

          # Re-extract context for this turn with edited flag
          handle_message_edit(
            rack_session,
            turn_to_update,
            turn_pair[:user]["text"],
            turn_pair[:assistant]["text"],
            provider,
            schema,
            ws_session_id,
            language
          )
        end
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

end
