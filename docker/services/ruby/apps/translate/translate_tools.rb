# frozen_string_literal: true

# Translation context management tools using Monadic Session State mechanism.
# These tools allow the LLM to save and load translation context (source/target languages, vocabulary)
# without embedding JSON in responses.

module TranslateTools
  include MonadicHelper
  include Monadic::SharedTools::MonadicSessionState

  STATE_KEY = "translation_context"

  # Save translation context to session state.
  # Called by LLM when language settings or vocabulary changes.
  #
  # @param source_lang [String] Source language (e.g., "Japanese", "English")
  # @param target_lang [String] Target language (e.g., "English", "Japanese")
  # @param vocabulary [Array] Array of vocabulary entries: [{original_text: "...", translation: "..."}, ...]
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_translation_context(source_lang: nil, target_lang: nil, vocabulary: nil, session: nil)
    # Load existing context first to merge with updates
    existing = load_translation_context_internal(session)

    # Update only provided fields, preserving existing values
    context = {
      source_lang: source_lang || existing[:source_lang],
      target_lang: target_lang || existing[:target_lang],
      vocabulary: vocabulary || existing[:vocabulary] || []
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Load translation context from session state.
  # Called by LLM when it needs to check current language settings or vocabulary.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_translation_context(session: nil)
    default_context = {
      source_lang: nil,
      target_lang: nil,
      vocabulary: []
    }
    monadic_load_state(key: STATE_KEY, default: default_context, session: session)
  end

  # Add vocabulary entry to the translation context.
  # Accumulates vocabulary entries without overwriting existing ones.
  #
  # @param original_text [String] Original text/expression
  # @param translation [String] Preferred translation for the expression
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with updated vocabulary
  def add_vocabulary_entry(original_text:, translation:, session: nil)
    existing = load_translation_context_internal(session)
    vocabulary = existing[:vocabulary] || []

    # Check for duplicate (update if exists, add if not)
    entry_index = vocabulary.find_index { |v| v[:original_text] == original_text }
    if entry_index
      vocabulary[entry_index][:translation] = translation
    else
      vocabulary << { original_text: original_text, translation: translation }
    end

    save_translation_context(
      source_lang: existing[:source_lang],
      target_lang: existing[:target_lang],
      vocabulary: vocabulary,
      session: session
    )
  end

  # Clear all vocabulary entries from translation context.
  # Called when user wants to start fresh with vocabulary.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response confirming vocabulary cleared
  def clear_vocabulary(session: nil)
    existing = load_translation_context_internal(session)

    save_translation_context(
      source_lang: existing[:source_lang],
      target_lang: existing[:target_lang],
      vocabulary: [],
      session: session
    )
  end

  private

  # Internal helper to load context as Ruby hash (not JSON string)
  def load_translation_context_internal(session)
    result = JSON.parse(monadic_load_state(key: STATE_KEY, default: {}, session: session))
    data = result["data"] || {}
    {
      source_lang: data["source_lang"],
      target_lang: data["target_lang"],
      vocabulary: (data["vocabulary"] || []).map { |v| v.transform_keys(&:to_sym) }
    }
  rescue StandardError
    { source_lang: nil, target_lang: nil, vocabulary: [] }
  end
end

# Class definition for Translate app with OpenAI
# Must come AFTER the module definition
class TranslateOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include TranslateTools
end
