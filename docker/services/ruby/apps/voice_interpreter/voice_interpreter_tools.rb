# frozen_string_literal: true

# Voice Interpreter tools using Monadic Session State mechanism.
# Manages translation context (source/target languages) without embedding JSON in responses.
# Uses tts_target to extract translated message for TTS from save_translation tool.

module VoiceInterpreterTools
  include MonadicHelper
  include Monadic::SharedTools::MonadicSessionState

  STATE_KEY = "voice_interpreter_context"

  # Save translation result and context to session state.
  # The "message" parameter is extracted for TTS via tts_target feature.
  #
  # @param message [String] Translated message (used for TTS)
  # @param source_lang [String] Detected source language
  # @param target_lang [String] Target language for translation
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_translation(message:, source_lang: nil, target_lang: nil, session: nil)
    existing = load_context_internal(session)

    context = {
      source_lang: source_lang || existing[:source_lang],
      target_lang: target_lang || existing[:target_lang],
      last_translation: message
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Load translation context from session state.
  # Called by LLM to check current language settings.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_context(session: nil)
    default_context = {
      source_lang: nil,
      target_lang: nil,
      last_translation: nil
    }
    monadic_load_state(key: STATE_KEY, default: default_context, session: session)
  end

  # Set the target language for translation.
  # Called when user specifies or changes the target language.
  #
  # @param target_lang [String] The target language to translate into
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def set_target_language(target_lang:, session: nil)
    existing = load_context_internal(session)

    context = {
      source_lang: existing[:source_lang],
      target_lang: target_lang,
      last_translation: existing[:last_translation]
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  private

  # Internal helper to load context as Ruby hash (not JSON string)
  def load_context_internal(session)
    result = JSON.parse(monadic_load_state(key: STATE_KEY, default: {}, session: session))
    data = result["data"] || {}
    {
      source_lang: data["source_lang"],
      target_lang: data["target_lang"],
      last_translation: data["last_translation"]
    }
  rescue StandardError
    {
      source_lang: nil,
      target_lang: nil,
      last_translation: nil
    }
  end
end

# Class definition for Voice Interpreter app with OpenAI
class VoiceInterpreterOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include VoiceInterpreterTools
end

# Class definition for Voice Interpreter app with Cohere
class VoiceInterpreterCohere < MonadicApp
  include CohereHelper if defined?(CohereHelper)
  include VoiceInterpreterTools
end
