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

    # Each step is tried even when one before it failed: what the request
    # holds is let go and the page is told in any case.
    ending_step("shown") do
      # What it showed on the work screen and wrote there is not added to
      # later (a message that took it already has it).
      Monadic::Workbench::Shown.close(request_id) if defined?(Monadic::Workbench::Shown)
      Monadic::Workbench::Put.release(request_id) if defined?(Monadic::Workbench::Put)
    end
    ending_step("capture") do
      # What it asked the work screen is not taken now.
      Monadic::Workbench::Capture.revoke_request(request_id) if defined?(Monadic::Workbench::Capture)
    end
    if outcome == "no_reply"
      # A reply that ends without its message offers nothing more: a
      # candidate it put on the workbench stops waiting (Workbench::Offer).
      ending_step("offer") { Monadic::Workbench::Offer.close(request_id) }
      # What it looked at in the work screen is said on the user's message.
      ending_step("looks") { workbench_looks_without_reply(request_id, ws_session_id) }
    end
    ending_step("notice") do
      send_or_broadcast({ "type" => "reply_state", "state" => "finished", "outcome" => outcome,
                          "request_id" => request_id }.to_json, ws_session_id)
    end
  end

  private def ending_step(name)
    yield
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Reply] ending step #{name} failed: #{e.class}" }
  end

  # Stops the thread doing a piece of work and ends it, also when the thread
  # was stopped before it ran (its own ensure never runs then). An answer
  # (a thread with a ReplyHandle) is not ended here: it is cancelled and
  # waited for until its worker ended it (Replies.stop_and_settle).
  private def stop_reply_work(thread, ws_session_id = Thread.current[:websocket_session_id])
    return unless thread

    if (handle = thread[:reply_handle])
      Replies.stop_and_settle(handle)
      return
    end

    thread.kill if thread.alive?
    finish_reply(thread[:reply_request_id], "no_reply", ws_session_id)
  end

  # Whether a new answer must wait (one answer at a time): an answer that
  # is being written or stopped; an answer made and not cancelled waits for
  # its HTML only.
  private def reply_busy?(thread)
    return false unless thread

    handle = thread[:reply_handle]
    handle ? handle.busy? : thread.alive?
  end

  # Empties the queue of answers the page has not taken yet (Cancel, Reset,
  # another app, a closed connection): each of them ends without being
  # recorded (an answer's worker ends it once woken; it is waited for).
  private def drop_queued_replies(queue, ws_session_id = Thread.current[:websocket_session_id])
    return unless queue

    loop do
      item = queue.pop(true)
      next unless item.is_a?(Hash)

      if item["_answer"]
        handle = Replies.find(item["_request_id"])
        Replies.stop_and_settle(handle) if handle
      else
        finish_reply(item["_request_id"], "no_reply", ws_session_id)
      end
    rescue ThreadError
      break
    end
  end
end
