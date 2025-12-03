# frozen_string_literal: true

# Chat Plus application tools for shared folder operations and session state management.
# Uses Monadic Session State mechanism for context tracking.

module ChatPlusTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::SharedTools::MonadicSessionState

  STATE_KEY = "chat_plus_context"

  # Save response and conversation context to session state.
  #
  # @param message [String] Response message to the user
  # @param reasoning [String] The reasoning behind the response
  # @param topics [Array<String>] Topics discussed in the conversation
  # @param people [Array<String>] People mentioned and their relationships
  # @param notes [Array<String>] Important information, dates, preferences
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_context(message:, reasoning: nil, topics: nil, people: nil, notes: nil, session: nil)
    existing = load_context_internal(session)

    context = {
      reasoning: reasoning || existing[:reasoning],
      topics: topics || existing[:topics] || [],
      people: people || existing[:people] || [],
      notes: notes || existing[:notes] || [],
      last_message: message
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Load conversation context from session state.
  # Called by LLM to check current conversation state.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_context(session: nil)
    default_context = {
      reasoning: nil,
      topics: [],
      people: [],
      notes: [],
      last_message: nil
    }
    monadic_load_state(key: STATE_KEY, default: default_context, session: session)
  end

  # Add topics to the conversation context.
  # Accumulates topics without overwriting existing ones.
  #
  # @param topics [Array<String>] Topics to add
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_topics(topics:, session: nil)
    existing = load_context_internal(session)
    all_topics = (existing[:topics] || []) + (topics || [])
    all_topics = all_topics.uniq

    context = {
      reasoning: existing[:reasoning],
      topics: all_topics,
      people: existing[:people],
      notes: existing[:notes],
      last_message: existing[:last_message]
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Add people to the conversation context.
  # Accumulates people without overwriting existing ones.
  #
  # @param people [Array<String>] People to add (with their relationships)
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_people(people:, session: nil)
    existing = load_context_internal(session)
    all_people = (existing[:people] || []) + (people || [])
    all_people = all_people.uniq

    context = {
      reasoning: existing[:reasoning],
      topics: existing[:topics],
      people: all_people,
      notes: existing[:notes],
      last_message: existing[:last_message]
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Add notes to the conversation context.
  # Accumulates notes without overwriting existing ones.
  #
  # @param notes [Array<String>] Notes to add
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_notes(notes:, session: nil)
    existing = load_context_internal(session)
    all_notes = (existing[:notes] || []) + (notes || [])
    all_notes = all_notes.uniq

    context = {
      reasoning: existing[:reasoning],
      topics: existing[:topics],
      people: existing[:people],
      notes: all_notes,
      last_message: existing[:last_message]
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  private

  # Internal helper to load context as Ruby hash (not JSON string)
  def load_context_internal(session)
    result = JSON.parse(monadic_load_state(key: STATE_KEY, default: {}, session: session))
    data = result["data"] || {}
    {
      reasoning: data["reasoning"],
      topics: data["topics"] || [],
      people: data["people"] || [],
      notes: data["notes"] || [],
      last_message: data["last_message"]
    }
  rescue StandardError
    {
      reasoning: nil,
      topics: [],
      people: [],
      notes: [],
      last_message: nil
    }
  end
end

# Class definitions for Chat Plus apps
# These must come AFTER the module definition

# Chat Plus apps with file operations
class ChatPlusOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include ChatPlusTools
end

class ChatPlusClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include ChatPlusTools
end

class ChatPlusGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include ChatPlusTools
end

class ChatPlusGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include ChatPlusTools
end

class ChatPlusMistral < MonadicApp
  include MistralHelper if defined?(MistralHelper)
  include ChatPlusTools
end

class ChatPlusDeepSeek < MonadicApp
  include DeepSeekHelper if defined?(DeepSeekHelper)
  include ChatPlusTools
end

class ChatPlusCohere < MonadicApp
  include CohereHelper if defined?(CohereHelper)
  include ChatPlusTools
end

# Note: Ollama tool support varies by model.
# Some models (e.g., llama3) support tools, others don't.
# The MDSL defines tools but they may not be invoked depending on the model.
class ChatPlusOllama < MonadicApp
  include OllamaHelper if defined?(OllamaHelper)
  include ChatPlusTools
end
