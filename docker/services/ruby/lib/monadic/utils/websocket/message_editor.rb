# frozen_string_literal: true

# Message editing and deletion handlers for WebSocket connections.
# Handles message deletion, editing, turn pair finding,
# HTML generation, and status updates after edits.

require_relative '../../workspace/folders'
require_relative '../../workspace/chats'
require_relative '../../workbench/board'
require_relative '../../workbench/channel'
require_relative '../../workbench/made'
require_relative '../../workbench/draw'
require_relative '../../workbench/turn_trash'
require_relative '../../workbench/picture'
require_relative '../../workbench/sent'
require_relative '../../workbench/revision'
require_relative '../../workbench/document'
require_relative '../../turn_state'
require_relative '../../turn_state/notes'

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

    # Delete the message, and move what it made to the chat's trash
    deleted = message_index && messages[message_index]
    # The marks a user's message recorded on the work screen are taken out
    # with it (always: a message can be deleted whatever its marks).
    undo_message_marks(rack_session, deleted, ws_session_id)

    rack_session[:messages]&.delete_if { |m| m["mid"] == obj["mid"] }
    # The app state is made again without the deleted turn's changes.
    Monadic::TurnState.changed!(rack_session[Monadic::Workspace::Chats::SESSION_KEY]) if defined?(Monadic::TurnState)
    Monadic::TurnState::Notes.refresh(rack_session)
    later = deleted ? Array(rack_session[:messages])[message_index..] || [] : []
    # Unless the user chose to keep them.
    take_off_drawn(rack_session, deleted) unless obj["keep_drawn"] == true
    rebuild_documents(rack_session) unless trash_made_files(rack_session, deleted, later).empty?
    # The picture of the work screen the message was sent with goes with it,
    # and the images sent that no message names any more.
    remove_workbench_picture(rack_session, deleted)
    release_sent_images(rack_session)

    # Invalidate any Grok compaction blob: it summarized the pre-edit history,
    # so a delete makes the cached covered_count and summary stale. Dropping it
    # degrades to full-history replay (and re-compaction) on the next turn.
    rack_session.delete(:grok_compaction)

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
  
  # Takes out what the user's message recorded of the marks on the work
  # screen; the page is told how many marks it erased stayed erased.
  def undo_message_marks(rack_session, message, ws_session_id)
    return unless message.is_a?(Hash) && message["role"] == "user" && message["request_id"]

    chat_id = rack_session[Monadic::Workspace::Chats::SESSION_KEY]
    board = chat_id && Monadic::Workbench::Board.existing(chat_id)
    return unless board

    stayed = board.undo_marks(message["request_id"])
    send_or_broadcast({ "type" => "workbench_marks_kept_erased", "count" => stayed }.to_json, ws_session_id) if stayed.positive?
    Monadic::Workbench::Channel.changed(chat_id)
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Marks not taken out: #{e.class}" }
  end

  def remove_workbench_picture(rack_session, message)
    chat_id = rack_session[Monadic::Workspace::Chats::SESSION_KEY]
    return unless chat_id

    Monadic::Workbench::Picture.references_of(message).each do |ref|
      Monadic::Workbench::Picture.remove(chat_id, ref["id"]) if ref["id"]
    end
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Picture not removed: #{e.class}" }
  end

  def release_sent_images(rack_session)
    chat_id = rack_session[Monadic::Workspace::Chats::SESSION_KEY]
    Monadic::Workbench::Sent.release(chat_id, Array(rack_session[:messages])) if chat_id
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Sent images not released: #{e.class}" }
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

  # What a deleted message drew on whiteboards (Workbench::Draw) is taken
  # off them; what else is on them stays.
  def take_off_drawn(rack_session, message)
    drawn = message.is_a?(Hash) && Monadic::Workbench::Draw.clean(message[Monadic::Workbench::Draw::KEY])
    chat_id = rack_session[Monadic::Workspace::Chats::SESSION_KEY]
    return unless drawn && chat_id

    Monadic::Workbench::Draw.undo(chat_id, drawn, app_name: rack_session.dig(:parameters, 'app_name').to_s)
  rescue StandardError => e
    warn "[MessageEditor] what the deleted message drew was not taken off: #{e.class}"
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
