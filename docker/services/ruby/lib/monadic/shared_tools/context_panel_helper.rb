# frozen_string_literal: true

require_relative '../workspace/chat_context'

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
      ChatContext = Monadic::Workspace::ChatContext

      # Add item(s) to a context panel field and broadcast update.
      #
      # @param field [String, Symbol] Field name from context_schema (e.g., :tips, :vocabulary)
      # @param items [String, Array<String>] Item(s) to add to the field
      # @param session [Hash] Session object (contains ws_session_id and app info)
      # @return [Boolean] true when the chat's context was changed
      def add_to_context_panel(field:, items:, session:)
        items_array = normalize_items(items)
        return false if items_array.empty?

        turn = get_current_turn(session || {})
        !!change_panel(session) { |context| ChatContext.add_texts(context, field, items_array, turn) }
      end

      # Set a context panel field to specific items (replaces existing).
      #
      # @param field [String, Symbol] Field name from context_schema
      # @param items [String, Array<String>] Item(s) to set
      # @param session [Hash] Session object
      # @return [Boolean] true when the chat's context was changed
      def set_context_panel_field(field:, items:, session:)
        turn = get_current_turn(session || {})
        !!change_panel(session) { |context| ChatContext.set_texts(context, field, normalize_items(items), turn) }
      end

      # Clear a context panel field.
      #
      # @param field [String, Symbol] Field name to clear
      # @param session [Hash] Session object
      # @return [Boolean] true when the chat's context was changed
      def clear_context_panel_field(field:, session:)
        !!change_panel(session) { |context| ChatContext.set_texts(context, field, [], 0) }
      end

      # Clear all context panel fields.
      #
      # @param session [Hash] Session object
      # @return [Boolean] true when the chat's context was changed
      def clear_context_panel(session:)
        !!change_panel(session) { |_context| { ChatContext::TURN_KEY => 0 } }
      end

      private

      # Changes the context of the chat the tool runs for (the block gets
      # the context now and returns the new one) and sends it to the tab.
      # The change made, or nil when that chat was left.
      def change_panel(session)
        return nil unless session

        change = ChatContext.update(session) { |context| yield context }
        return nil unless change

        app_name = session.dig(:parameters, "app_name") || session.dig("parameters", "app_name")
        ChatContext.send_change(extract_session_id(session), change, schema: get_app_schema(app_name))
        change
      end

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
