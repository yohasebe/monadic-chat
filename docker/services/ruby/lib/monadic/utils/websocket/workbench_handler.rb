# frozen_string_literal: true

require_relative '../../workbench/channel'
require_relative '../../workbench/look'
require_relative '../../workbench/look/record'

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
  def workbench_looks_of_reply(session, request_id)
    ledger = request_id && Monadic::Workbench::Look::Ledger.take(request_id)
    return nil unless ledger && ledger.chat_id == session[Monadic::Workspace::Chats::SESSION_KEY]

    Monadic::Workbench::Look::Record.clean(ledger.records)
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

    records = Monadic::Workbench::Look::Record.clean(ledger.records)
    turn = Array(session[:messages]).find { |m| m.is_a?(Hash) && m["role"] == "user" && m["request_id"] == request_id }
    return unless turn && records

    turn["workbench_looks"] = records
    send_or_broadcast({ "type" => "workbench_looks", "mid" => turn["mid"], "looks" => records }.to_json, ws_session_id)
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
