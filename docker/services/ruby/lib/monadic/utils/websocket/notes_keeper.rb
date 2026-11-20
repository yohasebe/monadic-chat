# frozen_string_literal: true

require_relative '../../turn_state/keeper'
require_relative '../../turn_state/notes'
require_relative '../privacy/outbound'
require_relative '../privacy/words'
require_relative '../error_formatter'
require_relative '../content_free_logging'

# The notes added after each reply (Monadic::TurnState::Keeper): the reply
# is recorded and the page is ready for the next message; new notes follow
# from one more request to the reply's own app and the model its request was
# sent with.
#
# One worker per chat takes the chat's jobs in order. It runs in a thread
# started where the reply was recorded, so it carries that chat's privacy
# scope (EgressGuard), and keeps the session id and the rack session as the
# Verify handler does. A job is sent and applied only while the chat, its
# epoch and app, and the tab's live connection are the ones it was made for,
# and the exchange is as it was recorded; otherwise it is let go (the reply
# keeps no new notes). Nothing of what is sent or comes back is logged.
module WebSocketHelper
  NOTES_APPLY_LOCK = Mutex.new

  # Takes a recorded reply's notes as a job of its chat, and starts the
  # chat's worker unless one runs. sent: the model the request was sent with
  # and the user's text it carried (Keeper.sent).
  def keep_notes(session, user, reply, sent, model_text)
    keeper = Monadic::TurnState::Keeper
    chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
    tab = Thread.current[:websocket_session_id]
    return unless chat_id && tab && user && reply && sent && user['text'].to_s == sent[:text]

    keeper.enqueue(keeper::Job.new(
                     session: session, chat_id: chat_id, epoch: Monadic::Workspace::Chats.epoch(chat_id), tab: tab,
                     generation: session[:_ws_generation], app_name: reply['app_name'].to_s, model: sent[:model],
                     user_mid: user['mid'], reply_mid: reply['mid'], user_text: sent[:text],
                     reply_text: plain_reply(model_text), source: keeper.source_of(user, reply),
                     voids: keeper.voids(chat_id)
                   ))
    changed = -> { Monadic::Workbench::Channel.changed(chat_id) }
    keeper.start(chat_id, on_change: changed) do
      # Each job carries the session and the tab it was made for (a newer
      # connection's job is taken by the same worker).
      while (job = keeper.next_job(chat_id))
        Thread.current[:websocket_session_id] = job.tab
        Thread.current[:rack_session] = job.session
        keep_notes_for(job.session, job)
      end
    end
  end

  private

  # The reply as text: what the model wrote, with any markup it held left out.
  def plain_reply(text)
    text.to_s.gsub(/<[^>]*>/, ' ').gsub(/[ \t]+/, ' ').strip
  end

  def keep_notes_for(session, job)
    keeper = Monadic::TurnState::Keeper
    return unless notes_live?(session, job) && notes_exchange?(session, job)

    app = defined?(APPS) ? APPS[job.app_name] : nil
    return unless app.respond_to?(:send_query) && notes_model_ok?(app, job.model)

    words = Monadic::Utils::Privacy::Words
    table = words.table(session)
    snapshot = nil
    user_text = job.user_text
    reply_text = job.reply_text
    snapshot, (user_text, reply_text) = words.hide_texts(table, [user_text, reply_text]) if table
    body = keeper.request_body(job.model, user_text, reply_text)
    Monadic::Utils::Privacy::Outbound.check_no_marked_words!(session, body)
    return unless notes_live?(session, job) && notes_exchange?(session, job)

    raw = Monadic::Utils::ContentFreeLogging.during do
      words.sending(table, snapshot) do
        # Checked here too: a local model's request does not pass the
        # transport check that does it for a host outside.
        words.check_sending!
        app.send_query(body, model: job.model)
      end
    end
    return if Monadic::Utils::ErrorFormatter.error_reply?(raw)
    # The words changed while it was asked (a table made, changed or
    # replaced): what came back is not used.
    table_now = words.table(session)
    return if table_now != table || (table && table.revision != snapshot.revision)

    changes = keeper.additions(keeper.parse(raw), notes_now(session))
    notes_apply(session, job, changes) unless changes.empty?
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Notes] not kept: #{e.class}" }
  end

  # The new items given to the reply's message, when it fits the reply's and
  # the chat's limits, and the chat, the connection and the exchange are
  # still the ones the job was made for.
  def notes_apply(session, job, changes)
    form = Monadic::TurnState::Form
    key = form::STATE_CHANGES_KEY
    applied = NOTES_APPLY_LOCK.synchronize do
      next false unless notes_live?(session, job)

      next false unless notes_exchange?(session, job)

      reply = session[:messages].find { |m| m.is_a?(Hash) && m['mid'] == job.reply_mid }

      now = notes_now(session)
      fresh = changes.reject { |change| Array(now[change['collection']]).include?(change['data']) }
      next false if fresh.empty?

      before = Array(reply[key])
      combined = form.clean_changes(before + fresh.map { |c| c.merge('app' => job.app_name) }, limit: form::SAVE_BYTES)
      next false unless combined

      grown = JSON.generate(combined).bytesize - (before.empty? ? 0 : JSON.generate(before).bytesize)
      next false if Monadic::TurnState.chat_bytes(session) + grown > form::CHAT_BYTES

      reply[key] = combined
      true
    end
    return unless applied

    Monadic::TurnState.refresh!(job.chat_id)
    sync_session_state!
    Monadic::TurnState::Notes.refresh(session, show: :quiet, tab: job.tab)
  end

  # The exchange is still there as recorded, and no notes were removed
  # since the job was made.
  def notes_exchange?(session, job)
    reply = session[:messages].find { |m| m.is_a?(Hash) && m['mid'] == job.reply_mid }
    user = session[:messages].find { |m| m.is_a?(Hash) && m['role'] == 'user' && m['mid'] == job.user_mid }
    reply && Monadic::TurnState::Keeper.source_of(user, reply) == job.source &&
      Monadic::TurnState::Keeper.voids(job.chat_id) == job.voids
  end

  # The notes held now, as stored: { field => [text] }.
  def notes_now(session)
    Monadic::TurnState::Keeper::FIELDS.to_h do |field|
      [field, Monadic::TurnState.items(session, field).map { |item| item[:data].to_s }]
    end
  end

  # The chat, its epoch and app, and the tab's live connection are the ones
  # the job was made for.
  def notes_live?(session, job)
    session[Monadic::Workspace::Chats::SESSION_KEY] == job.chat_id &&
      Monadic::Workspace::Chats.epoch(job.chat_id) == job.epoch &&
      Monadic::TurnState.app_of(session) == job.app_name &&
      session[:_ws_generation] == job.generation &&
      WebSocketHelper.live_generation(job.tab) == job.generation
  end

  # With Ollama, only a model with the tools capability adds notes (one
  # local model answers in turn; a plain-chat model is left to the
  # conversation alone). Asked in the worker, not while the reply is shown.
  def notes_model_ok?(app, model)
    provider = app.respond_to?(:settings) ? app.settings[:provider].to_s.downcase : ''
    return true unless provider == 'ollama'

    caps = defined?(OllamaHelper) && OllamaHelper.respond_to?(:fetch_model_capabilities) &&
           OllamaHelper.fetch_model_capabilities(model)
    caps.is_a?(Hash) && Array(caps[:capabilities]).include?('tools')
  rescue StandardError
    false
  end
end
