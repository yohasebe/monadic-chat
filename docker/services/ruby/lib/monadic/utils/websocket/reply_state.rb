# frozen_string_literal: true

# The page is told when work it waits for (an answer, an AI User suggestion)
# is running and, once, how it ended: "done" when the answer was recorded in
# the chat (or the suggestion was given), "no_reply" when it ended without
# one. The desktop app keeps the Web UI window while such work runs and
# notices its end (app/background_reply.js).
module WebSocketHelper
  REPLY_STATE_LOCK = Mutex.new
  # Request ids already ended, oldest first: an end is sent once however
  # many places reach it.
  REPLY_ENDED = {}
  REPLY_ENDED_LIMIT = 1000

  private def reply_running(request_id, ws_session_id = Thread.current[:websocket_session_id])
    return unless request_id

    send_or_broadcast({ "type" => "reply_state", "state" => "running", "request_id" => request_id }.to_json,
                      ws_session_id)
  end

  private def finish_reply(request_id, outcome, ws_session_id = Thread.current[:websocket_session_id])
    return unless request_id

    first = REPLY_STATE_LOCK.synchronize do
      next false if REPLY_ENDED.key?(request_id)

      REPLY_ENDED[request_id] = true
      REPLY_ENDED.shift while REPLY_ENDED.size > REPLY_ENDED_LIMIT
      true
    end
    return unless first

    # A reply that ends without its message offers nothing more: a candidate
    # it put on the workbench stops waiting (Monadic::Workbench::Offer).
    Monadic::Workbench::Offer.close(request_id) if outcome == "no_reply"
    # What it looked at in the work screen is said on the user's message.
    workbench_looks_without_reply(request_id, ws_session_id) if outcome == "no_reply"
    send_or_broadcast({ "type" => "reply_state", "state" => "finished", "outcome" => outcome,
                        "request_id" => request_id }.to_json, ws_session_id)
  end

  # Stops the thread doing a piece of work and ends it, also when the thread
  # was stopped before it ran (its own ensure never runs then).
  private def stop_reply_work(thread, ws_session_id = Thread.current[:websocket_session_id])
    return unless thread

    thread.kill if thread.alive?
    finish_reply(thread[:reply_request_id], "no_reply", ws_session_id)
  end

  # Empties the queue of answers the page has not taken yet (Cancel, Reset,
  # another app): each of them ends without being recorded.
  private def drop_queued_replies(queue, ws_session_id = Thread.current[:websocket_session_id])
    return unless queue

    loop do
      item = queue.pop(true)
      finish_reply(item["_request_id"], "no_reply", ws_session_id) if item.is_a?(Hash)
    rescue ThreadError
      break
    end
  end
end
