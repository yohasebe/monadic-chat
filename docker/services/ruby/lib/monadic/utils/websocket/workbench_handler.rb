# frozen_string_literal: true

require_relative '../../workbench/channel'

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

  # only_existing: nothing is sent for a chat without a board (a page that
  # has not asked).
  def send_workbench_view(connection, session, only_existing: false)
    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    return unless WORKBENCH_LIVE.call(tab) == generation

    view = workbench_timed('view') do
      Monadic::Workbench::Channel.view(session, **workbench_connection(session), live: WORKBENCH_LIVE,
                                                only_existing: only_existing)
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
