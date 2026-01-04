# frozen_string_literal: true

# Translation context management tools using Monadic Session State mechanism.
# These tools allow the LLM to save and load translation context (source/target languages, vocabulary)
# without embedding JSON in responses.
# Uses ContextPanelHelper to update the sidebar Context Panel.

module TranslateTools
  include MonadicHelper
  include Monadic::SharedTools::MonadicSessionState
  include Monadic::SharedTools::ContextPanelHelper

  STATE_KEY = "translation_context"

  # Save translation context to session state.
  # Called by LLM when language settings or vocabulary changes.
  # Also updates the Context Panel with language and vocabulary info.
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
    new_source = source_lang || existing[:source_lang]
    new_target = target_lang || existing[:target_lang]

    context = {
      source_lang: new_source,
      target_lang: new_target,
      vocabulary: vocabulary || existing[:vocabulary] || []
    }

    # Save to session state
    result = monadic_save_state(key: STATE_KEY, payload: context, session: session)

    # Update Context Panel with language settings
    if new_source && new_target
      lang_display = "#{new_source} → #{new_target}"
      set_context_panel_field(field: :languages, items: [lang_display], session: session)
    end

    result
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
  # Also updates the Context Panel vocabulary field.
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

    # Save to session state (this also updates languages in Context Panel)
    result = save_translation_context(
      source_lang: existing[:source_lang],
      target_lang: existing[:target_lang],
      vocabulary: vocabulary,
      session: session
    )

    # Update Context Panel with the new vocabulary entry
    vocab_display = "#{original_text}: #{translation}"
    add_to_context_panel(field: :vocabulary, items: [vocab_display], session: session)

    result
  end

  # Clear all vocabulary entries from translation context.
  # Called when user wants to start fresh with vocabulary.
  # Also clears the Context Panel vocabulary field.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response confirming vocabulary cleared
  def clear_vocabulary(session: nil)
    existing = load_translation_context_internal(session)

    result = save_translation_context(
      source_lang: existing[:source_lang],
      target_lang: existing[:target_lang],
      vocabulary: [],
      session: session
    )

    # Clear vocabulary from Context Panel
    clear_context_panel_field(field: :vocabulary, session: session)

    result
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
