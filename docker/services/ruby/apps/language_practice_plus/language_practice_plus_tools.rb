# frozen_string_literal: true

# Language Practice Plus tools using Monadic Session State mechanism.
# Manages language learning context (target language, advice) without embedding JSON in responses.
# Uses tts_target to extract message for TTS from save_response tool.
# Uses ContextPanelHelper to update the sidebar Context Panel.

module LanguagePracticePlusTools
  include MonadicHelper
  include Monadic::SharedTools::MonadicSessionState
  include Monadic::SharedTools::ContextPanelHelper

  STATE_KEY = "language_practice_context"

  # Save response and context to session state.
  # The "message" parameter is extracted for TTS via tts_target feature.
  # Language advice is also displayed in the Context Panel (mapped to "tips" field).
  #
  # @param message [String] Response message to the user (used for TTS)
  # @param target_lang [String] Target language being practiced
  # @param language_advice [Array<String>] Array of language advice items
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_response(message:, target_lang: nil, language_advice: nil, session: nil)
    existing = load_context_internal(session)

    context = {
      target_lang: target_lang || existing[:target_lang],
      language_advice: language_advice || existing[:language_advice] || [],
      last_message: message
    }

    # Save to session state (for persistence)
    result = monadic_save_state(key: STATE_KEY, payload: context, session: session)

    # Update Context Panel with language advice (mapped to "tips" field in context_schema)
    if language_advice&.any?
      add_to_context_panel(field: :tips, items: language_advice, session: session)
    end

    result
  end

  # Load language practice context from session state.
  # Called by LLM to check current learning state.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_context(session: nil)
    default_context = {
      target_lang: nil,
      language_advice: [],
      last_message: nil
    }
    monadic_load_state(key: STATE_KEY, default: default_context, session: session)
  end

  # Update target language.
  # Called when user specifies or changes the language to practice.
  #
  # @param target_lang [String] The target language to practice
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def set_target_language(target_lang:, session: nil)
    existing = load_context_internal(session)

    context = {
      target_lang: target_lang,
      language_advice: existing[:language_advice] || [],
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
      target_lang: data["target_lang"],
      language_advice: data["language_advice"] || [],
      last_message: data["last_message"]
    }
  rescue StandardError
    {
      target_lang: nil,
      language_advice: [],
      last_message: nil
    }
  end
end

# Class definition for Language Practice Plus app with OpenAI
class LanguagePracticePlusOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include LanguagePracticePlusTools
end

# Class definition for Language Practice Plus app with Claude
class LanguagePracticePlusClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include LanguagePracticePlusTools
end
