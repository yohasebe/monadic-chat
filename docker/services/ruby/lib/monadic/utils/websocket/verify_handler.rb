# frozen_string_literal: true

# Confidence-via-agreement "Verify" handler. The Verify button on an assistant
# message re-asks the original question to a diverse cross-provider panel and
# reports how much they corroborate the answer (Monadic::MCP::Conduit's
# confidence primitive, which auto-selects the panel and degrades honestly).
#
# The panel makes N+1 blocking model calls, so the work runs in a background
# thread — a synchronous call here would freeze the single Falcon reactor (and
# with it the whole Web UI). Thread-locals (session id, rack session) are
# captured before the thread because a fresh thread does not inherit them.
module WebSocketHelper
  def handle_ws_verify_confidence(connection, obj, _session)
    ws_session_id = Thread.current[:websocket_session_id]
    rack_session = Thread.current[:rack_session] || {}
    messages = rack_session[:messages] || []
    mid = obj["mid"]

    idx = messages.find_index { |m| m["mid"] == mid }
    ai = idx ? messages[idx] : nil
    unless ai && ai["role"] == "assistant"
      return send_to_client(connection, verify_error(mid, "Message not found or not an assistant response"))
    end

    # Give the panel the SAME conversation context the original answer saw, so a
    # contextual answer ("and the second one?") is verified faithfully rather
    # than re-asked context-free. We pass the prior user/assistant turns (active,
    # same app) up to — but NOT including — the answer under review:
    #   - excluding the reviewed answer keeps the panel independent (it answers
    #     fresh; the original is sent only as `review_answer` for corroboration);
    #   - excluding the app's system prompt preserves panel diversity (a shared
    #     persona would homogenise answers and inflate agreement);
    #   - `active` bounds cost to the user's context window (no summarisation —
    #     a lossy summary would itself diverge from what the original saw).
    panel_messages = messages[0...idx].filter_map do |m|
      next unless %w[user assistant].include?(m["role"])
      next if m["active"] == false || m["type"] == "search" || m["app_name"] != ai["app_name"]

      text = m["text"].to_s
      next if text.strip.empty?

      { "role" => m["role"], "content" => text }
    end
    if panel_messages.empty? || panel_messages.last["role"] != "user"
      return send_to_client(connection, verify_error(mid, "No preceding user question to verify against"))
    end

    review_answer = ai["text"].to_s

    # Let the UI show a spinner immediately while the panel runs.
    send_to_client(connection, { "type" => "verify_confidence_start", "mid" => mid })

    Thread.new do
      Thread.current[:websocket_session_id] = ws_session_id
      Thread.current[:rack_session] = rack_session
      begin
        # We deliberately do NOT set temperature here. A model at its standard
        # setting should not fabricate; chasing factuality with a low
        # temperature is a band-aid (and some recent models don't expose the
        # parameter at all). Each provider uses its own default; if a model
        # still fabricates, that surfaces as a panel outlier rather than being
        # masked. (Within-provider self-consistency keeps its own temperature
        # via the panel selector, since that mode needs sampling variety.)
        result = Monadic::MCP::Conduit.call(
          "monadic_confidence",
          { "messages" => panel_messages, "review_answer" => review_answer }
        )
        send_or_broadcast(result.merge(type: "verify_confidence", mid: mid).to_json, ws_session_id)
        persist_verify_result(rack_session, mid, result)
      rescue StandardError => e
        send_or_broadcast(verify_error(mid, "Error: #{e.message}").to_json, ws_session_id)
      end
    end
  end

  def verify_error(mid, note)
    { "type" => "verify_confidence", "mid" => mid, "confidence" => "unavailable",
      "recommendation" => "verify", "note" => note }
  end

  # Cap each persisted panel answer so a verified message's stored verdict stays
  # bounded (the live render shows the full text; only the persisted copy that
  # rides in the session — and a JSON export — is capped).
  VERIFY_PERSIST_TEXT_CAP = 4000

  # Store the verdict ON the message so it survives a reload (LOAD re-renders it).
  # Slims to display-relevant fields only: drops `budget`/usage and trims long
  # panel answers, so persistence doesn't bloat the session unbounded. The
  # KB-save path strips "verify" so a persisted verdict never pollutes the
  # Knowledge Base (verify is meta-commentary about an answer, not knowledge).
  def persist_verify_result(rack_session, mid, result)
    msgs = rack_session && rack_session[:messages]
    return unless msgs.is_a?(Array)

    idx = msgs.find_index { |m| m["mid"] == mid }
    return unless idx

    msgs[idx]["verify"] = slim_verify_for_persist(result)
    sync_session_state!
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Verify] persist failed: #{e.class}: #{e.message}" }
  end

  def slim_verify_for_persist(result)
    slim = result.reject { |k, _| k == :budget }
    responses = slim[:responses]
    return slim unless responses.is_a?(Array)

    slim.merge(responses: responses.map do |r|
      text = r[:text].to_s
      text = "#{text[0, VERIFY_PERSIST_TEXT_CAP]}…" if text.length > VERIFY_PERSIST_TEXT_CAP
      # Keep only what the renderer needs (provider/model/success/text), dropping
      # usage/error/index noise.
      { provider: r[:provider], model: r[:model], success: r[:success], text: text }
    end)
  end
end
