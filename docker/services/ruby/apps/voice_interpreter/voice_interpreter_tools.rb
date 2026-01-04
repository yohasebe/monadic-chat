# frozen_string_literal: true

# Voice Interpreter tools using Monadic Session State mechanism.
# Manages translation context (source/target languages) without embedding JSON in responses.
# Uses tts_target to extract translated message for TTS from save_translation tool.
# Uses ContextPanelHelper to update the sidebar Context Panel.

module VoiceInterpreterTools
  include MonadicHelper
  include Monadic::SharedTools::MonadicSessionState
  include Monadic::SharedTools::ContextPanelHelper

  STATE_KEY = "voice_interpreter_context"

  # Save translation result and context to session state.
  # The "message" parameter is extracted for TTS via tts_target feature.
  # Also updates the Context Panel with language and phrase info.
  #
  # @param message [String] Translated message (used for TTS)
  # @param source_lang [String] Detected source language
  # @param target_lang [String] Target language for translation
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_translation(message:, source_lang: nil, target_lang: nil, session: nil)
    existing = load_context_internal(session)

    new_source = source_lang || existing[:source_lang]
    new_target = target_lang || existing[:target_lang]

    context = {
      source_lang: new_source,
      target_lang: new_target,
      last_translation: message
    }

    # Save to session state
    result = monadic_save_state(key: STATE_KEY, payload: context, session: session)

    # Update Context Panel with language settings
    if new_source && new_target
      lang_display = "#{new_source} → #{new_target}"
      set_context_panel_field(field: :languages, items: [lang_display], session: session)
    end

    # Add translated phrase to Context Panel
    if message && !message.strip.empty?
      # Truncate long messages for display
      phrase_display = message.length > 50 ? "#{message[0..47]}..." : message
      add_to_context_panel(field: :phrases, items: [phrase_display], session: session)
    end

    result
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
  # Also updates the Context Panel with language settings.
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

    result = monadic_save_state(key: STATE_KEY, payload: context, session: session)

    # Update Context Panel with language settings
    if existing[:source_lang] && target_lang
      lang_display = "#{existing[:source_lang]} → #{target_lang}"
      set_context_panel_field(field: :languages, items: [lang_display], session: session)
    elsif target_lang
      # Only target language is known
      set_context_panel_field(field: :languages, items: ["→ #{target_lang}"], session: session)
    end

    result
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
