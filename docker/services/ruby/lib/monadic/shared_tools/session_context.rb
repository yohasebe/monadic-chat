# frozen_string_literal: true

# Session Context Management Tools for Monadic Chat
#
# What a conversational app keeps of the conversation: topics, people and
# notes, each an item of the app's state (Monadic::TurnState), so deleting
# the turn that added or removed one takes that change back. The state is
# shown to the user as a page on the work screen (Monadic::TurnState::Notes).
#
# Usage in MDSL:
#   tools do
#     import_shared_tools :session_context, visibility: "always"
#   end

require_relative '../turn_state'

module MonadicSharedTools
  module SessionContext
    include MonadicHelper

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
      { success: true, context: context_texts(session) }
    end

    # Update context with new information
    # Merges with existing context (additive by default)
    #
    # @param topics [Array<String>, nil] Topics to add
    # @param people [Array<String>, nil] People to add
    # @param notes [Array<String>, nil] Notes to add
    # @param replace [Boolean] If true, the three fields hold what is given and nothing else (default: false)
    # @return [Hash] Updated context
    # @example
    #   update_context(topics: ["Machine Learning"], notes: ["User prefers Python"])
    #   # => { success: true, context: { topics: [...], people: [...], notes: [...] } }
    def update_context(topics: nil, people: nil, notes: nil, replace: false, session: nil)
      given = context_given(topics, people, notes)

      changed_context(session, replace ? "replaced" : "merged") do |now|
        FIELDS.flat_map do |field|
          added = (given[field] - now[field]).map { |text| context_change(field, text, 'set') }
          left_out = replace ? (now[field] - given[field]).map { |text| context_change(field, text, 'remove') } : []
          added + left_out
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
      given = context_given(topics, people, notes)

      changed_context(session, "removed") do |now|
        FIELDS.flat_map { |field| (given[field] & now[field]).map { |text| context_change(field, text, 'remove') } }
      end
    end

    # Clear all context
    #
    # @return [Hash] Empty context confirmation
    def clear_context(session: nil)
      update_context(replace: true, session: session)
    end

    private

    # The page that shows the context on the work screen.
    def state_notes
      { title: "Context", lists: { "topics" => { label: "Topics" }, "people" => { label: "People" },
                                   "notes" => { label: "Notes" } } }
    end

    def context_texts(session)
      FIELDS.to_h { |field| [field, Monadic::TurnState.items(session, field).map { |item| item[:data] }] }
    end

    def context_given(topics, people, notes)
      { "topics" => topics, "people" => people, "notes" => notes }.transform_values do |value|
        Array(value).map { |text| text.to_s.strip }.reject(&:empty?).uniq
      end
    end

    # A text is the same item wherever it is added again.
    def context_change(field, text, op)
      change = { 'kind' => 'item', 'collection' => field, 'id' => Monadic::TurnState.text_id(text), 'op' => op }
      op == 'set' ? change.merge('data' => text) : change
    end

    # One tool call's changes to the context, made together or not at all,
    # and what the model is told of it.
    def changed_context(session, action)
      session ||= @session || Thread.current[:session]
      changes = yield(context_texts(session))
      Monadic::TurnState.change_all!(session, changes) unless changes.empty?
      { success: true, action: action, context: context_texts(session) }
    rescue Monadic::TurnState::Refused => e
      { success: false, error: "Nothing was changed: #{e.message}." }
    end
  end
end
