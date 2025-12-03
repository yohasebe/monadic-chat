# frozen_string_literal: true

# Session Context Management Tools for Monadic Chat
#
# Provides on-demand context tracking for conversational AI apps.
# Context is stored server-side and displayed in the sidebar panel.
#
# Features:
# - Normal text responses by default (faster, fewer tokens)
# - Server-side context storage (reliable, persistent within session)
# - Real-time sidebar display via WebSocket
# - User can edit context directly in the sidebar
#
# Usage in MDSL:
#   tools do
#     import_shared_tools :session_context, visibility: "always"
#   end

require_relative 'monadic_session_state'

module MonadicSharedTools
  module SessionContext
    include MonadicHelper
    include Monadic::SharedTools::MonadicSessionState

    CONTEXT_KEY = :conversation_context

    # Get current context from session
    #
    # @return [Hash] Current context with topics, people, notes
    # @example
    #   get_context
    #   # => {
    #   #      success: true,
    #   #      context: {
    #   #        topics: ["AI", "Ruby programming"],
    #   #        people: ["John - project manager"],
    #   #        notes: ["Meeting scheduled for Friday"]
    #   #      }
    #   #    }
    def get_context(session: nil)
      session ||= @session || Thread.current[:session]
      result = JSON.parse(monadic_load_state(key: CONTEXT_KEY, default: default_context, session: session))

      if result["success"]
        {
          success: true,
          context: result["data"] || default_context
        }
      else
        {
          success: false,
          error: result["error"],
          context: default_context
        }
      end
    end

    # Update context with new information
    # Merges with existing context (additive by default)
    #
    # @param topics [Array<String>, nil] Topics to add
    # @param people [Array<String>, nil] People to add
    # @param notes [Array<String>, nil] Notes to add
    # @param replace [Boolean] If true, replace instead of merge (default: false)
    # @return [Hash] Updated context
    # @example
    #   update_context(topics: ["Machine Learning"], notes: ["User prefers Python"])
    #   # => { success: true, context: { topics: [...], people: [...], notes: [...] } }
    def update_context(topics: nil, people: nil, notes: nil, replace: false, session: nil)
      # Always log when update_context is called (for debugging)
      puts "[SessionContext] update_context called with topics=#{topics.inspect}, people=#{people.inspect}, notes=#{notes.inspect}, replace=#{replace}"
      puts "[SessionContext] session parameter received: #{session.nil? ? 'nil' : 'present'}"

      session ||= @session || Thread.current[:session]
      puts "[SessionContext] session after fallback: #{session.nil? ? 'nil' : 'present'}"

      # Get current context (pass session to ensure consistency)
      current = get_context(session: session)
      current_ctx = current[:context] || default_context

      # Build new context
      new_context = if replace
                      {
                        "topics" => topics || [],
                        "people" => people || [],
                        "notes" => notes || []
                      }
                    else
                      {
                        "topics" => ((current_ctx["topics"] || []) + (topics || [])).uniq,
                        "people" => ((current_ctx["people"] || []) + (people || [])).uniq,
                        "notes" => ((current_ctx["notes"] || []) + (notes || [])).uniq
                      }
                    end

      # Save to session
      result = JSON.parse(monadic_save_state(key: CONTEXT_KEY, payload: new_context, session: session))

      if result["success"]
        # Broadcast context update to sidebar via WebSocket
        broadcast_context_update(session, new_context)

        {
          success: true,
          action: replace ? "replaced" : "merged",
          context: new_context
        }
      else
        {
          success: false,
          error: result["error"]
        }
      end
    end

    # Remove specific items from context
    #
    # @param topics [Array<String>, nil] Topics to remove
    # @param people [Array<String>, nil] People to remove
    # @param notes [Array<String>, nil] Notes to remove
    # @return [Hash] Updated context
    def remove_from_context(topics: nil, people: nil, notes: nil, session: nil)
      session ||= @session || Thread.current[:session]

      current = get_context(session: session)
      current_ctx = current[:context] || default_context

      new_context = {
        "topics" => (current_ctx["topics"] || []) - (topics || []),
        "people" => (current_ctx["people"] || []) - (people || []),
        "notes" => (current_ctx["notes"] || []) - (notes || [])
      }

      result = JSON.parse(monadic_save_state(key: CONTEXT_KEY, payload: new_context, session: session))

      if result["success"]
        # Broadcast context update to sidebar via WebSocket
        broadcast_context_update(session, new_context)

        {
          success: true,
          action: "removed",
          context: new_context
        }
      else
        {
          success: false,
          error: result["error"]
        }
      end
    end

    # Clear all context
    #
    # @return [Hash] Empty context confirmation
    def clear_context(session: nil)
      update_context(replace: true, session: session)
    end

    private

    # Broadcast context update to the client via WebSocket
    # Sends only to the specific session, not to all clients
    #
    # @param session [Hash] The session object
    # @param context [Hash] The updated context data
    def broadcast_context_update(session, context)
      session_id = session&.dig(:parameters, "session_id") ||
                   session&.dig("parameters", "session_id") ||
                   Thread.current[:websocket_session_id]

      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        puts "[SessionContext] broadcast_context_update called"
        puts "[SessionContext] session_id: #{session_id.inspect}"
        puts "[SessionContext] context: #{context.inspect}"
      end

      unless session_id
        puts "[SessionContext] No session_id found, skipping broadcast" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        return
      end

      message = {
        "type" => "context_update",
        "context" => context,
        "timestamp" => Time.now.to_f
      }

      # Use WebSocketHelper to send to specific session only
      if defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_to_session)
        WebSocketHelper.send_to_session(message.to_json, session_id)
        puts "[SessionContext] Sent context_update to session #{session_id}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      else
        puts "[SessionContext] WebSocketHelper not available" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      end
    rescue StandardError => e
      # Log error but don't fail the context update
      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        puts "[SessionContext] WebSocket broadcast error: #{e.message}"
        puts "[SessionContext] Backtrace: #{e.backtrace.first(5).join("\n")}"
      end
    end

    def default_context
      {
        "topics" => [],
        "people" => [],
        "notes" => []
      }
    end
  end
end
