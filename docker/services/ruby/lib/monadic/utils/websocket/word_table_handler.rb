# frozen_string_literal: true

require_relative '../privacy/words'
require_relative '../privacy/presidio_backend'
require_relative '../privacy/language_detector'
require_relative '../container_dependencies'

# The page's side of a chat's word table: finding the words a message might
# want hidden, and the user's decisions about them. Finding changes nothing
# (what is found stays on the page until the user decides).
module WebSocketHelper
  WORDS_FIND_MAX_CHARS = 100_000

  private def handle_ws_words_find(connection, session, obj)
    reply = { "type" => "words_found", "request" => obj["request"], "chat" => chat_token(session) }
    text = obj["text"].to_s
    return send_to_client(connection, reply.merge("error" => "words_text_too_long")) if text.length > WORDS_FIND_MAX_CHARS

    table = Monadic::Utils::Privacy::Words.table(session)
    return send_to_client(connection, reply.merge("candidates" => [])) if text.strip.empty?

    backend = Monadic::Utils::Privacy::PresidioBackend.new
    unless backend.health
      return send_to_client(connection, reply.merge("error" => privacy_container_started_for_words))
    end

    language = Monadic::Utils::Privacy::LanguageDetector.language_of(text, session)
    found = backend.anonymize(text: text, languages: [language], registry: {})
    send_to_client(connection, reply.merge("candidates" => Monadic::Utils::Privacy::Words.candidates(table, found[:entities])))
  rescue Monadic::Utils::Privacy::Outbound::Refused => e
    send_to_client(connection, reply.merge("error" => "words_refused", "detail" => e.message))
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Words] finding failed: #{e.class}" }
    send_to_client(connection, reply.merge("error" => "words_find_failed"))
  end

  # The reason finding could not be done; the container is started when it
  # is not on its way, unless the user turned it off (PRIVACY_FILTER=false).
  private def privacy_container_started_for_words
    return "privacy_container_unreachable" if name_finder_off?
    return "privacy_container_starting" if privacy_container_coming_up?

    Monadic::Utils::ContainerDependencies.start_service_async(:privacy, reason: "finding words to hide")
    "privacy_container_starting"
  rescue StandardError
    "privacy_container_unreachable"
  end

  private def name_finder_off?
    setting = (defined?(CONFIG) && CONFIG.is_a?(Hash) ? CONFIG["PRIVACY_FILTER"] : nil) || ENV.fetch("PRIVACY_FILTER", nil)
    setting.to_s.downcase == "false"
  end

  # The user's decisions, for the chat they were made in: words to hide (a
  # word hidden before takes the type given), words to leave as they are, and
  # words left as they are put back.
  private def handle_ws_words_change(connection, session, obj)
    reply = { "type" => "words_changed", "request" => obj["request"] }
    if obj["chat"] != chat_token(session)
      return send_to_client(connection, reply.merge("success" => false, "error" => "words_other_chat"))
    end

    hide = Array(obj["hide"]).map { |item| item.is_a?(Hash) ? [item["word"], item["type"]] : [item, nil] }
    keep = Array(obj["keep"])
    show = Array(obj["show"])
    unless hide.empty? && keep.empty? && show.empty?
      apply_word_changes(connection, session, hide, keep, show)
      sync_session_state!
    end
    send_word_table(connection, session)
    send_to_client(connection, reply.merge("success" => true))
  rescue Monadic::Utils::Privacy::WordTable::Invalid, Monadic::Utils::Privacy::Outbound::Refused => e
    send_to_client(connection, reply.merge("success" => false, "error" => "words_refused", "detail" => e.message))
  end

  private def apply_word_changes(connection, session, hide, keep, show)
    # Checked first: a change that cannot be made does not begin a table.
    words_table = Monadic::Utils::Privacy::WordTable
    unless hide.all? { |word, type| words_table.word?(word) && words_table.type?(type) } && keep.all? { |word| words_table.word?(word) }
      raise words_table::Invalid, "a word or a type that cannot be hidden"
    end

    table = Monadic::Utils::Privacy::Words.start!(session)
    stop_live_conversation_for_words(connection, session)
    table.confirm_all!(hide) unless hide.empty?
    keep.each { |word| table.keep!(word) }
    show.each { |word| table.unkeep!(word) }
  end

  # Live Conversation sends the voice as it is, so it ends when the chat
  # begins to hide its words.
  private def stop_live_conversation_for_words(connection, session)
    return unless session[:_sts]

    teardown_sts_session(session)
    send_to_client(connection, { "type" => "sts_session", "state" => "stopped" })
    notify_sts_privacy_blocked(connection, session)
  end

  # What the page shows of the chat's table.
  private def send_word_table(connection, session)
    send_to_client(connection, { "type" => "word_table", "chat" => chat_token(session) }
                                 .merge(Monadic::Utils::Privacy::Words.shown(session)))
  end
end
