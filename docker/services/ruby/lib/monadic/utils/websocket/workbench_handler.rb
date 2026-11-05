# frozen_string_literal: true

require_relative '../../workbench/channel'

# The workbench over the main socket (Monadic::Workbench::Channel): the
# view a page is sent and the user's operation on an image (save it to the
# shared folder, or remove it from the board), always for
# this connection's tab, generation and chat, and sent back to this
# connection only.
#
# All of it runs in the connection's own loop, one message after another,
# the saves included: a Reset, an import or a chat taken from the history
# comes before or after a save, never in the middle of it. A save copies
# one image and syncs it, and its time is logged.
module WebSocketHelper
  # The generation of the connection a tab has now: an operation or a view
  # goes only to that connection, not to one a newer connection replaced.
  WORKBENCH_LIVE = ->(tab) { WebSocketHelper.live_generation(tab) }

  # only_existing: nothing is sent for a chat without a board (a page that
  # has not asked). Saves left unfinished, and records the history missed,
  # are settled first.
  def send_workbench_view(connection, session, only_existing: false)
    tab, generation = workbench_connection(session).values_at(:tab, :generation)
    return unless WORKBENCH_LIVE.call(tab) == generation

    workbench_timed('settle') do
      Monadic::Workbench::Channel.settle(session, recorder: workbench_recorder(connection, session))
    end
    view = Monadic::Workbench::Channel.view(session, **workbench_connection(session), live: WORKBENCH_LIVE,
                                                     only_existing: only_existing)
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
      Monadic::Workbench::Channel.act(obj, session, **workbench_connection(session), live: WORKBENCH_LIVE,
                                                    recorder: workbench_recorder(connection, session))
    end
    workbench_deliver(connection).call(result)
    send_workbench_view(connection, session)
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

  def workbench_recorder(connection, session)
    Monadic::Workbench::Channel.recorder_for(session, sync: -> { sync_session_state! },
                                                      deliver: workbench_deliver(connection))
  end
end
