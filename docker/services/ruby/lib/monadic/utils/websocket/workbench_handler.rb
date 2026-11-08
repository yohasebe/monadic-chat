# frozen_string_literal: true

require_relative '../../workbench/channel'
require_relative '../../workbench/look'
require_relative '../../workbench/look/record'
require_relative '../../workbench/show'

# The workbench over the main socket (Monadic::Workbench::Channel): the
# view a page is sent, the user's removal of an item from the board, a file
# the user opens on it, the item a tab selects, and the address to save a
# copy of an image, always for this connection's tab,
# generation and chat, and sent back to this connection only. All of it
# runs in the connection's own loop, one message after another.
module WebSocketHelper
  # The generation of the connection a tab has now: an operation or a view
  # goes only to that connection, not to one a newer connection replaced.
  WORKBENCH_LIVE = ->(tab) { WebSocketHelper.live_generation(tab) }
  Monadic::Workbench::Board.live = WORKBENCH_LIVE
  # A look asks the page of the tab's connection what its work screen shows.
  Monadic::Workbench::Capture.transport = lambda do |tab, generation, chat_id, json|
    WebSocketHelper.send_to_connection(tab, generation, json, chat_id: chat_id)
  end

  # initial: the connection's first view (marked so: what it shows is not
  # new to the user). It is sent also for a chat without a board, so that a
  # page still showing another chat's board lets it go.
  def send_workbench_view(connection, session, initial: false)
    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    return unless WORKBENCH_LIVE.call(tab) == generation

    view = workbench_timed('view') do
      Monadic::Workbench::Channel.view(session, **workbench_connection(session), live: WORKBENCH_LIVE,
                                                initial: initial)
    end
    workbench_deliver(connection).call(view) if view
  rescue Monadic::Workbench::Store::Unreadable => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Board not shown: #{e.message}" }
  end

  # The reply's message was recorded: what the reply offered (the items
  # its final message names) becomes that message's, and the page is sent
  # the board.
  def workbench_reply_recorded(connection, session, mid, request_id, item_ids)
    return unless Monadic::Workbench::Channel.reply_recorded(session, mid, request_id, item_ids)

    send_workbench_view(connection, session)
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Board not sent after the reply: #{e.class}: #{e.message}" }
  end

  # The looks of the reply to request_id (Look::Ledger#records), let go
  # as the reply is recorded; nil when it looked at nothing.
  # What the user showed with the message (and how far it went) is kept on
  # the user's message, once, from the same take.
  def workbench_looks_of_reply(session, request_id)
    ledger = request_id && Monadic::Workbench::Look::Ledger.take(request_id)
    return nil unless ledger && ledger.chat_id == session[Monadic::Workspace::Chats::SESSION_KEY]

    turn = workbench_shown_settled(session, request_id, ledger)
    workbench_shown_told(turn, ledger.chat_id, Thread.current[:websocket_session_id]) if turn
    Monadic::Workbench::Look::Record.clean(ledger.records(origin: "tool"))
  end

  # The page is told how far what the user showed went (its message's
  # records), for the chat it belongs to.
  def workbench_shown_told(turn, chat_id, ws_session_id)
    send_or_broadcast({ "type" => "workbench_shown_records", "mid" => turn["mid"], "chat_id" => chat_id,
                        "shown" => turn["workbench_shown"] }.to_json, ws_session_id)
  end

  # The user's message of request_id gets the records of what the user
  # showed with it, as far as it went now. Returns the turn changed, or nil.
  def workbench_shown_settled(session, request_id, ledger)
    shown = Monadic::Workbench::Look::Record.clean(ledger.records(origin: "user"))
    return nil unless shown

    turn = Array(session[:messages]).find { |m| m.is_a?(Hash) && m["role"] == "user" && m["request_id"] == request_id }
    return nil unless turn

    turn["workbench_shown"] = shown
    turn
  end

  # A reply ended without its message: what it looked at in the work
  # screen (and how far that went) is kept on the user's message of the
  # request, in the session the looks were made for (the thread that ends
  # the reply may have none), and the page draws it there. Nothing when
  # that session is in another chat now.
  def workbench_looks_without_reply(request_id, ws_session_id)
    ledger = Monadic::Workbench::Look::Ledger.take(request_id)
    session = ledger&.session
    return unless session && session[Monadic::Workspace::Chats::SESSION_KEY] == ledger.chat_id

    shown_turn = workbench_shown_settled(session, request_id, ledger)
    workbench_shown_told(shown_turn, ledger.chat_id, ws_session_id) if shown_turn
    records = Monadic::Workbench::Look::Record.clean(ledger.records(origin: "tool"))
    turn = Array(session[:messages]).find { |m| m.is_a?(Hash) && m["role"] == "user" && m["request_id"] == request_id }
    return unless turn && (records || shown_turn)

    if records
      turn["workbench_looks"] = records
      send_or_broadcast({ "type" => "workbench_looks", "mid" => turn["mid"], "looks" => records }.to_json, ws_session_id)
    end
    # Saved now, as any change of the chat is (the tab's connection and the
    # history's rules decide), not left for the next one: the reply may
    # have ended with the connection.
    saved_as(session, ledger.tab || ws_session_id) { sync_session_state! }
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Workbench] Looks not kept after the reply: #{e.class}: #{e.message}" }
  end

  # Runs the block as the work of session's tab (what sync_session_state!
  # reads), from a thread that may be another's.
  def saved_as(session, tab)
    was = [Thread.current[:rack_session], Thread.current[:websocket_session_id]]
    Thread.current[:rack_session] = session
    Thread.current[:websocket_session_id] = tab
    yield
  ensure
    Thread.current[:rack_session], Thread.current[:websocket_session_id] = was
  end

  def handle_ws_workbench_action(connection, obj, session)
    result = workbench_timed('operation') do
      Monadic::Workbench::Channel.act(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    end
    workbench_deliver(connection).call(result)
    send_workbench_view(connection, session)
  end

  # A file the user opens on the workbench: the result, then the board.
  def handle_ws_workbench_open(connection, obj, session)
    result = workbench_timed('open') do
      Monadic::Workbench::Channel.open_file(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    end
    workbench_deliver(connection).call(result)
    send_workbench_view(connection, session) unless result['status'] == 'refused'
  end

  # "Show to the assistant" pressed on this connection's page: accepted
  # (the page is told when what it shows is ready) or refused at once.
  def handle_ws_workbench_show(connection, obj, session)
    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
    deliver = lambda do |message|
      WebSocketHelper.send_to_connection(tab, generation, message.to_json, chat_id: chat_id)
    end
    accepted = Monadic::Workbench::Show.press(
      session: session, tab: tab, generation: generation, op_id: obj['op_id'].to_s, item_id: obj['item_id'],
      version: obj['version'], serial: obj['serial'], deliver: deliver
    )
    return if accepted == true

    workbench_deliver(connection).call({ 'type' => 'workbench_shown', 'op_id' => obj['op_id'].to_s,
                                         'status' => 'refused', 'reason' => accepted })
  end

  def handle_ws_workbench_show_remove(obj, session)
    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    Monadic::Workbench::Show.remove(tab: tab, generation: generation, op_id: obj['op_id'].to_s)
  end

  def handle_ws_workbench_select(connection, obj, session)
    result = Monadic::Workbench::Channel.select(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    workbench_deliver(connection).call(result)
  end

  def handle_ws_workbench_download(connection, obj, session)
    result = Monadic::Workbench::Channel.download(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE)
    workbench_deliver(connection).call(result)
  end

  private

  def workbench_timed(what)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Monadic::Utils::ExtraLogger.log { "[Workbench] #{what} took #{ms} ms" } if ms >= 50
  end

  def workbench_connection(session)
    { tab: Thread.current[:websocket_session_id], generation: session[:_ws_generation] }
  end

  # To this connection; without one (a reply recorded outside a connection's
  # loop), to the tab.
  def workbench_deliver(connection)
    tab = Thread.current[:websocket_session_id]
    connection ? ->(message) { send_to_client(connection, message) } : ->(message) { send_or_broadcast(message.to_json, tab) }
  end
end
