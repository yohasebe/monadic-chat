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
#
# Usage in MDSL:
#   tools do
#     import_shared_tools :session_context, visibility: "always"
#   end

require_relative 'context_panel_helper'
require_relative '../utils/extra_logger'

module MonadicSharedTools
  module SessionContext
    include MonadicHelper
    include Monadic::SharedTools::ContextPanelHelper

    FIELDS = %w[topics people notes].freeze

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
      { success: true, context: ChatContext.texts(ChatContext.read(session), FIELDS) }
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
      session ||= @session || Thread.current[:session]
      given = { "topics" => topics, "people" => people, "notes" => notes }.transform_values { |v| normalize_items(v) }
      turn = get_current_turn(session || {})

      changed_context(session, replace ? "replaced" : "merged") do |context|
        FIELDS.reduce(context) do |ctx, field|
          if replace
            ChatContext.set_texts(ctx, field, given[field].uniq, turn)
          else
            known = ChatContext.texts(ctx, [field])[field]
            ChatContext.add_texts(ctx, field, given[field].uniq - known, turn)
          end
        end
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
      given = { "topics" => topics, "people" => people, "notes" => notes }.transform_values { |v| normalize_items(v) }

      changed_context(session, "removed") do |context|
        FIELDS.reduce(context) { |ctx, field| ChatContext.remove_texts(ctx, field, given[field]) }
      end
    end

    # Clear all context
    #
    # @return [Hash] Empty context confirmation
    def clear_context(session: nil)
      update_context(replace: true, session: session)
    end

    private

    # The tool's change to the chat's context (see ContextPanelHelper), and
    # what the model is told of it.
    def changed_context(session, action, &change)
      if (change = change_panel(session) { |context| change.call(context) })
        { success: true, action: action, context: ChatContext.texts(change.context, FIELDS) }
      else
        { success: false, error: "The conversation this was for is no longer open; nothing was changed." }
      end
    end
  end
end
