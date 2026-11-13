# frozen_string_literal: true

# Language Practice Plus tools using Monadic Session State mechanism.
# Keeps the practice's settings (target language, last message) as state, and
# the advice given as a log shown on the practice's notes.
# Uses tts_target to extract message for TTS from save_response tool.

require_relative "../../lib/monadic/utils/tts_instruction_extractor"

module LanguagePracticePlusTools
  include MonadicHelper
  include Monadic::SharedTools::MonadicSessionState

  STATE_KEY = "language_practice_context"
  # The advice given, turn after turn: added to, shown on the notes, not
  # read back by the model.
  ADVICE = "language_advice"

  # Save response and context to session state.
  # The "message" parameter is extracted for TTS via tts_target feature.
  #
  # @param message [String] Response message to the user (used for TTS)
  # @param target_lang [String] Target language being practiced
  # @param language_advice [Array<String>] Language advice of this turn
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_response(message:, target_lang: nil, language_advice: nil, session: nil)
    # What is kept is the message as the user reads it, without the speech
    # directive the model may begin it with.
    message = Monadic::Utils::TtsInstructionExtractor.strip_from_history(message)
    existing = load_context_internal(session)
    context = { target_lang: target_lang || existing[:target_lang], last_message: message }

    result = monadic_save_state(key: STATE_KEY, payload: context, session: session)
    logged = JSON.parse(monadic_log(collection: ADVICE, entries: language_advice, session: session))
    logged["success"] ? result : logged.to_json
  end

  # Load language practice context from session state.
  # Called by LLM to check current learning state.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_context(session: nil)
    monadic_load_state(key: STATE_KEY, default: { target_lang: nil, last_message: nil }, session: session)
  end

  # Update target language.
  # Called when user specifies or changes the language to practice.
  #
  # @param target_lang [String] The target language to practice
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def set_target_language(target_lang:, session: nil)
    context = { target_lang: target_lang, last_message: load_context_internal(session)[:last_message] }
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  private

  # The practice's notes on the work screen (Monadic::TurnState::Notes).
  def state_notes
    { title: "Practice notes", key: STATE_KEY, values: { "target_lang" => "Language" },
      lists: { ADVICE => { label: "Advice" } } }
  end

  # Internal helper to load context as Ruby hash (not JSON string)
  def load_context_internal(session)
    data = JSON.parse(monadic_load_state(key: STATE_KEY, default: {}, session: session))["data"] || {}
    { target_lang: data["target_lang"], last_message: data["last_message"] }
  rescue StandardError
    { target_lang: nil, last_message: nil }
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
