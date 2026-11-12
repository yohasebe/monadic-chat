# frozen_string_literal: true

# Message editing and deletion handlers for WebSocket connections.
# Handles message deletion, editing, turn pair finding,
# HTML generation, and status updates after edits.

require_relative '../../workspace/folders'
require_relative '../../workspace/chats'
require_relative '../../workbench/board'
require_relative '../../workbench/channel'
require_relative '../../workbench/made'
require_relative '../../workbench/turn_trash'
require_relative '../../workbench/revision'
require_relative '../../workbench/document'

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

    # Delete the message, and move what it made to the chat's trash
    deleted = message_index && messages[message_index]
    rack_session[:messages]&.delete_if { |m| m["mid"] == obj["mid"] }
    later = deleted ? Array(rack_session[:messages])[message_index..] || [] : []
    rebuild_documents(rack_session) unless trash_made_files(rack_session, deleted, later).empty?

    # Invalidate any Grok compaction blob: it summarized the pre-edit history,
    # so a delete makes the cached covered_count and summary stale. Dropping it
    # degrades to full-history replay (and re-compaction) on the next turn.
    rack_session.delete(:grok_compaction)

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
      send_or_broadcast({ "type" => "change_status", "content" => filtered_messages }.to_json, ws_session_id)
    end
    send_or_broadcast({ "type" => "info", "content" => past_messages_data }.to_json, ws_session_id)
    sync_session_state!
  end
  
  # What a deleted message made in the chat's folder (workbench_made) goes
  # to the chat's trash and off the work screen, and what it changed in
  # place (its revisions) is put back as it was (Workbench::Revision);
  # later: the messages after it, whose revisions of the same things take
  # the earlier state over. Returns the paths moved or put back.
  def trash_made_files(rack_session, message, later = [])
    return [] unless message.is_a?(Hash)

    made = Monadic::Workbench::Made.clean(message["workbench_made"])
    revisions = Monadic::Workbench::Made.clean_revisions(message[Monadic::Workbench::Made::REVISIONS_KEY])
    return [] unless made || revisions

    folder = Monadic::Workspace::Folders.lookup(rack_session)
    return [] unless folder && folder[:status] == :ready

    label = Monadic::Workbench::TurnTrash.label(message["mid"])
    moved = made ? Monadic::Workbench::TurnTrash.move(folder[:relative_dir], made, label) : []
    put_back = revisions ? Monadic::Workbench::Revision.undo(folder[:relative_dir], revisions, label, later: later_revisions(later)) : []
    chat_id = rack_session[Monadic::Workspace::Chats::SESSION_KEY]
    board = !(moved + put_back).empty? && Monadic::Workbench::Board.existing(chat_id)
    Monadic::Workbench::Channel.changed(chat_id) if board && (!board.drop_files(moved).empty? || !put_back.empty?)
    moved + put_back
  rescue StandardError => e
    warn "[MessageEditor] what the deleted message made was not moved to the trash: #{e.class}"
    []
  end

  # The revisions the messages keep, in order, as the messages hold them
  # (a revision that takes an earlier state over is changed there).
  def later_revisions(messages)
    Array(messages).flat_map do |m|
      next [] unless m.is_a?(Hash)

      kept = Monadic::Workbench::Made.clean_revisions(m[Monadic::Workbench::Made::REVISIONS_KEY])
      m[Monadic::Workbench::Made::REVISIONS_KEY] = kept if kept
      kept || []
    end
  end

  # The documents of the chat, put together again from what is left
  # (Workbench::Document): a deleted turn's sections leave them.
  def rebuild_documents(rack_session)
    Monadic::Workbench::Document.rebuild_all(rack_session)
  rescue StandardError => e
    warn "[MessageEditor] the chat's documents were not put together again: #{e.class}"
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

      refusal = { "edit_refused" => true, "mid" => obj["mid"] }
      if edited_role == "system" && hidden_word_in_system_text?(obj["content"], rack_session)
        send_error(SYSTEM_TEXT_MARKED, ws_session_id, { "not_accepted" => true }.merge(refusal))
        return
      end
      content = obj["content"]

      # Update the message directly in the array to ensure it's persisted
      messages[message_index]["text"] = content

      # Invalidate any Grok compaction blob: the edited message may already be
      # folded into the opaque summary, so the cache is now stale. Dropping it
      # degrades to full-history replay (and re-compaction) on the next turn.
      rack_session.delete(:grok_compaction)

      # Update images if provided in the edit request
      if obj["images"] && obj["images"].is_a?(Array)
        messages[message_index]["images"] = obj["images"]
      end

      # Get the updated message for response
      message_to_edit = messages[message_index]

      # Generate HTML content if needed
      html_content = generate_html_for_message(message_to_edit, content)

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
      send_or_broadcast(response.to_json, ws_session_id)

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
      send_error("message_not_found_for_editing", ws_session_id)
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
      send_or_broadcast(change_status_message, ws_session_id)
    end

    # Send info message (session-targeted)
    info_message = { "type" => "info", "content" => past_messages_data }.to_json
    send_or_broadcast(info_message, ws_session_id)

    sync_session_state!
  end

end
