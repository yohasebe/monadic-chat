# frozen_string_literal: true

module Monadic
  module SharedTools
    # Helper module for tool-based apps to update the Context Panel.
    #
    # The Context Panel displays session context in the sidebar, with data
    # organized by fields defined in context_schema. This helper enables
    # tool-based apps (like Language Practice Plus, Translate) to update
    # the panel directly, complementing the automatic extraction done by
    # ContextExtractorAgent for non-tool apps.
    #
    # Usage in tool modules:
    #   include Monadic::SharedTools::ContextPanelHelper
    #
    #   def save_response(message:, language_advice: nil, session: nil)
    #     # ... save to session state ...
    #
    #     # Update Context Panel
    #     add_to_context_panel(field: :tips, items: language_advice, session: session)
    #   end
    #
    module ContextPanelHelper
      # Add item(s) to a context panel field and broadcast update.
      #
      # @param field [String, Symbol] Field name from context_schema (e.g., :tips, :vocabulary)
      # @param items [String, Array<String>] Item(s) to add to the field
      # @param session [Hash] Session object (contains ws_session_id and app info)
      # @return [Boolean] true if broadcast was sent, false otherwise
      def add_to_context_panel(field:, items:, session:)
        return false unless session

        # Get current context
        context = get_panel_context(session) || { "_turn_count" => 0 }
        turn = get_current_turn(session)

        # Update turn count
        context["_turn_count"] = [context["_turn_count"].to_i, turn].max

        # Normalize items to array
        items_array = normalize_items(items)
        return false if items_array.empty?

        # Add items with turn info
        field_key = field.to_s
        context[field_key] ||= []

        items_array.each do |item|
          # Avoid duplicates (same text in same turn)
          existing = context[field_key].find { |i| i["text"] == item && i["turn"] == turn }
          next if existing

          context[field_key] << { "text" => item, "turn" => turn }
        end

        # Save and broadcast
        save_panel_context(session, context)
        broadcast_panel_update(session, context)
      end

      # Set a context panel field to specific items (replaces existing).
      #
      # @param field [String, Symbol] Field name from context_schema
      # @param items [String, Array<String>] Item(s) to set
      # @param session [Hash] Session object
      # @return [Boolean] true if broadcast was sent, false otherwise
      def set_context_panel_field(field:, items:, session:)
        return false unless session

        context = get_panel_context(session) || { "_turn_count" => 0 }
        turn = get_current_turn(session)
        context["_turn_count"] = [context["_turn_count"].to_i, turn].max

        items_array = normalize_items(items)
        field_key = field.to_s

        # Replace field with new items
        context[field_key] = items_array.map { |item| { "text" => item, "turn" => turn } }

        save_panel_context(session, context)
        broadcast_panel_update(session, context)
      end

      # Clear a context panel field.
      #
      # @param field [String, Symbol] Field name to clear
      # @param session [Hash] Session object
      # @return [Boolean] true if broadcast was sent, false otherwise
      def clear_context_panel_field(field:, session:)
        return false unless session

        context = get_panel_context(session) || {}
        context[field.to_s] = []

        save_panel_context(session, context)
        broadcast_panel_update(session, context)
      end

      # Clear all context panel fields.
      #
      # @param session [Hash] Session object
      # @return [Boolean] true if broadcast was sent, false otherwise
      def clear_context_panel(session:)
        return false unless session

        context = { "_turn_count" => 0 }

        save_panel_context(session, context)
        broadcast_panel_update(session, context)
      end

      private

      # Get current turn number from session (based on message count).
      # @param session [Hash] Session object
      # @return [Integer] Current turn number (1-indexed)
      def get_current_turn(session)
        messages = session[:messages] || session["messages"] || []
        # Count assistant messages (each assistant message = 1 turn)
        count = messages.count { |m| m["role"] == "assistant" || m[:role] == "assistant" }
        # During processing, current turn is count + 1 (we're creating a new assistant message)
        count + 1
      end

      # Normalize items to array of strings.
      # @param items [String, Array, nil] Items to normalize
      # @return [Array<String>] Array of non-empty strings
      def normalize_items(items)
        return [] if items.nil?

        Array(items).map do |item|
          if item.is_a?(Hash)
            # Handle hash items (e.g., vocabulary entries)
            item["text"] || item[:text] || item.values.join(": ")
          else
            item.to_s
          end
        end.reject(&:empty?)
      end

      # Get current panel context from session.
      # @param session [Hash] Session object
      # @return [Hash, nil] Current context or nil
      def get_panel_context(session)
        return nil unless session

        state = session[:monadic_state] || session["monadic_state"]
        return nil unless state

        state[:conversation_context] || state["conversation_context"]
      end

      # Save panel context to session.
      # @param session [Hash] Session object
      # @param context [Hash] Context to save
      def save_panel_context(session, context)
        return unless session

        session[:monadic_state] ||= {}
        session[:monadic_state][:conversation_context] = context
      end

      # Broadcast panel update via WebSocket.
      # @param session [Hash] Session object
      # @param context [Hash] Context to broadcast
      # @return [Boolean] true if broadcast was sent, false otherwise
      def broadcast_panel_update(session, context)
        session_id = extract_session_id(session)
        return false unless session_id

        # Get schema from app settings
        app_name = session&.dig(:parameters, "app_name") ||
                   session&.dig("parameters", "app_name")
        schema = get_app_schema(app_name)

        message = {
          "type" => "context_update",
          "context" => context,
          "schema" => schema,
          "timestamp" => Time.now.to_f
        }

        if defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_to_session)
          WebSocketHelper.send_to_session(message.to_json, session_id)

          if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            puts "[ContextPanelHelper] Sent context_update to session #{session_id}"
          end

          true
        else
          if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            puts "[ContextPanelHelper] WebSocketHelper not available"
          end

          false
        end
      rescue StandardError => e
        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[ContextPanelHelper] Broadcast error: #{e.message}"
        end

        false
      end

      # Extract WebSocket session ID from session.
      # @param session [Hash] Session object
      # @return [String, nil] Session ID or nil
      def extract_session_id(session)
        return nil unless session

        session.dig(:parameters, "session_id") ||
          session.dig("parameters", "session_id") ||
          Thread.current[:websocket_session_id]
      end

      # Get app's context_schema from APPS registry.
      # @param app_name [String] App name
      # @return [Hash, nil] Schema or nil
      def get_app_schema(app_name)
        return nil unless app_name && defined?(APPS) && APPS[app_name]

        APPS[app_name].settings&.dig(:context_schema) ||
          APPS[app_name].settings&.dig("context_schema")
      end
    end
  end
end
