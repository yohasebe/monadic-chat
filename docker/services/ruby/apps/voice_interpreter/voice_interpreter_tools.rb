# frozen_string_literal: true

# Voice Interpreter tools using Monadic Session State mechanism.
# Keeps the languages and the last translation as state, and the phrases
# translated as a log shown on the interpreter's notes.
# Uses tts_target to extract translated message for TTS from save_translation tool.

require_relative "../../lib/monadic/utils/tts_instruction_extractor"

module VoiceInterpreterTools
  include MonadicHelper
  include Monadic::SharedTools::MonadicSessionState

  STATE_KEY = "voice_interpreter_context"
  # The phrases translated, turn after turn: added to, shown on the notes,
  # not read back by the model.
  PHRASES = "phrases"

  # Save translation result and context to session state.
  # The "message" parameter is extracted for TTS via tts_target feature.
  #
  # @param message [String] Translated message (used for TTS)
  # @param original [String] The user's words the message translates; nil
  #   when the message is not a translation
  # @param source_lang [String] Detected source language
  # @param target_lang [String] Target language for translation
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_translation(message:, original: nil, source_lang: nil, target_lang: nil, session: nil)
    # What is kept is the translation as the user reads it, without the
    # speech directive the model may begin it with.
    message = Monadic::Utils::TtsInstructionExtractor.strip_from_history(message)
    existing = load_context_internal(session)
    context = { source_lang: source_lang || existing[:source_lang], target_lang: target_lang || existing[:target_lang],
                last_translation: message }

    result = monadic_save_state(key: STATE_KEY, payload: context, session: session)
    # The phrase list holds what was translated with its translation, not
    # the interpreter's own remarks.
    phrase = original.to_s.strip.empty? ? nil : "#{original.to_s.strip} → #{message.to_s.strip}"
    logged = JSON.parse(monadic_log(collection: PHRASES, entries: [phrase].compact, session: session))
    logged["success"] ? result : logged.to_json
  end

  # Load translation context from session state.
  # Called by LLM to check current language settings.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_context(session: nil)
    monadic_load_state(key: STATE_KEY, default: { source_lang: nil, target_lang: nil, last_translation: nil },
                       session: session)
  end

  # Set the target language for translation.
  # Called when user specifies or changes the target language.
  #
  # @param target_lang [String] The target language to translate into
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def set_target_language(target_lang:, session: nil)
    monadic_save_state(key: STATE_KEY, payload: load_context_internal(session).merge(target_lang: target_lang),
                       session: session)
  end

  private

  # The interpreter's notes on the work screen (Monadic::TurnState::Notes).
  def state_notes
    { title: "Interpreter notes", key: STATE_KEY, values: { "source_lang" => "From", "target_lang" => "To" },
      lists: { PHRASES => { label: "Phrases" } } }
  end

  # Internal helper to load context as Ruby hash (not JSON string)
  def load_context_internal(session)
    data = JSON.parse(monadic_load_state(key: STATE_KEY, default: {}, session: session))["data"] || {}
    { source_lang: data["source_lang"], target_lang: data["target_lang"], last_translation: data["last_translation"] }
  rescue StandardError
    { source_lang: nil, target_lang: nil, last_translation: nil }
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
