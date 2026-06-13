# frozen_string_literal: true

require "json"
require_relative "../../dsl/configurations"

# xAI Context Compaction orchestration for the Grok Responses API.
#
# Unlike OpenAI's server-driven `context_management` (a declarative block the
# server acts on), xAI exposes compaction as a client-driven two-step flow:
#
#   1. POST /v1/responses/compact { model, input } -> a compaction item
#      ({ type: "compaction", id: "cmp_<uuid>", encrypted_content: <opaque> }).
#   2. Re-insert that item at the HEAD of the next request's input and append
#      the live turn after it.
#
# Design contract (see memory grok-context-compaction-handoff):
#   - session[:messages] is the single source of truth. The blob is a CACHE
#     (session[:grok_compaction]) derived from it. Every invalidation path
#     degrades to "send full history" — i.e. current behaviour, never worse.
#   - The blob is opaque: never parsed, edited, or hand-merged. Re-compaction
#     folds the previous blob plus new messages into a fresh blob.
#
# Empirically verified against the live API (2026-06-13):
#   - Input order MUST be [compaction_item, system, tail]. Placing the system
#     message BEFORE the blob silently drops the system instructions.
#   - A corrupted/foreign blob returns HTTP 400 invalid-argument
#     ("Could not decrypt the provided encrypted_content"); we treat that as a
#     cache miss and fall back to full history.
#   - The blob is not bound to a TTL, but model binding is undocumented, so we
#     invalidate the cache on model (and app) switch to stay conservative.
module GrokCompaction
  COMPACT_PATH = "/responses/compact"

  # Rough token estimate for the threshold decision only (not billing). The
  # compact endpoint itself costs tokens, so we compact lazily — a coarse
  # bytes/4 heuristic is sufficient to decide "is the uncompacted tail large
  # enough to be worth a compact call?".
  def self.estimate_tokens(input_items)
    return 0 unless input_items.is_a?(Array)
    JSON.generate(input_items).bytesize / 4
  rescue StandardError
    0
  end

  # Resolve the app's compaction policy. Mirrors the OpenAI helper decision
  # logic so the same MDSL `compaction` block means the same thing for Grok.
  # Returns:
  #   :disabled        -> `compaction false` opt-out
  #   Integer threshold -> default or custom compact_threshold
  #   nil              -> app not found / no settings (treated as disabled)
  def grok_compaction_threshold(app)
    app_instance = APPS[app] if defined?(APPS)
    return nil unless app_instance.respond_to?(:settings)

    settings = app_instance.settings
    raw = settings["compaction"]
    raw = settings[:compaction] if raw.nil?

    return nil if raw.nil?
    return :disabled if raw == false

    if raw.is_a?(Hash)
      threshold = raw[:compact_threshold] || raw["compact_threshold"]
      return threshold.to_i if threshold
    end

    MonadicDSL::CompactionConfiguration::DEFAULT_COMPACT_THRESHOLD
  end

  # Entry point. Given the already-converted Responses API `input` array (system
  # message first) plus the raw message history, return a possibly-rewritten
  # input array of the form [blob, system, *tail]. Never raises: any failure
  # returns the original input unchanged (degrade to full history).
  #
  # @param input [Array] converted input items (output of convert_messages_to_input)
  # @param session [Hash] the rack session
  # @param app [String] app name
  # @param model [String] resolved model id
  # @param api_key [String] xAI API key
  def apply_grok_compaction(input, session:, app:, model:, api_key:)
    return input unless input.is_a?(Array) && input.length > 1

    threshold = grok_compaction_threshold(app)
    return input if threshold.nil? || threshold == :disabled

    # Orchestration-history pruning (AutoForge image variations etc.) already
    # bounds context for the turn; running compaction on top would fight it.
    # The two context-reduction strategies are mutually exclusive.
    return input if @clear_orchestration_history

    cache = validated_compaction_cache(session, app, model, threshold)

    # input[0] is the converted system message; the rest is the conversation.
    system_item = input.first
    convo = input[1..] || []
    covered = cache ? cache["covered_count"].to_i : 0
    covered = 0 if covered > convo.length

    # Keep the current in-flight turn (from the last user message onward) out of
    # compaction so the model always sees the live exchange verbatim.
    live_start = last_user_index(convo) || convo.length

    pending = convo[covered...live_start] || []
    uncompacted_estimate = GrokCompaction.estimate_tokens(convo[covered..] || [])

    # Below threshold: reuse an existing blob if we have one, otherwise send the
    # full (un-windowed) history unchanged.
    if uncompacted_estimate < threshold || pending.empty?
      return cache ? [cache["blob"], system_item, *(convo[covered..] || [])] : input
    end

    # Re-compaction folds the previous blob plus the new pending messages.
    compact_input = []
    compact_input << cache["blob"] if cache
    compact_input.concat(pending)

    # Privacy Filter: mask PII before the compact call so xAI only ever sees
    # masked content here too — consistent with the masking applied to the final
    # request in execute_grok_api_call. The opaque blob carries no role and is
    # skipped by apply_privacy_to_messages.
    app_settings = (defined?(APPS) && APPS[app]) ? APPS[app].settings : nil
    if privacy_enabled_for?(app_settings, session)
      compact_input = apply_privacy_to_messages(compact_input, session, app_settings)
    end

    blob = request_compaction(compact_input, model: model, api_key: api_key)
    if blob.nil?
      # Compaction failed: invalidate and degrade to full history.
      session.delete(:grok_compaction)
      Monadic::Utils::ExtraLogger.log { "[Grok] compaction failed; falling back to full history" }
      return input
    end

    session[:grok_compaction] = {
      "blob" => blob,
      "covered_count" => live_start,
      "model" => model,
      "app" => app,
      "threshold" => threshold
    }
    Monadic::Utils::ExtraLogger.log {
      "[Grok] compaction ok (covered=#{live_start}, tail=#{(convo.length - live_start)}, threshold=#{threshold})"
    }

    [blob, system_item, *(convo[live_start..] || [])]
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Grok] compaction error (#{e.class}: #{e.message}); using full history" }
    input
  end

  private

  # Return the cached compaction entry only if it is still valid for the current
  # model/app/threshold; otherwise drop it (invalidation matrix). A stale cache
  # never corrupts a request — it just means we re-send and re-compact.
  def validated_compaction_cache(session, app, model, threshold)
    cache = session[:grok_compaction]
    return nil unless cache.is_a?(Hash) && cache["blob"].is_a?(Hash)

    if cache["model"] != model || cache["app"] != app || cache["threshold"].to_i != threshold.to_i
      Monadic::Utils::ExtraLogger.log {
        "[Grok] compaction cache invalidated (was model=#{cache['model']}/app=#{cache['app']}/threshold=#{cache['threshold']}, " \
          "now model=#{model}/app=#{app}/threshold=#{threshold}); re-deriving from full history"
      }
      session.delete(:grok_compaction)
      return nil
    end
    cache
  end

  # Index (within the conversation slice) of the last user message — the start
  # of the live turn that must stay uncompacted.
  def last_user_index(convo)
    idx = nil
    convo.each_with_index { |item, i| idx = i if item.is_a?(Hash) && item["role"] == "user" }
    idx
  end

  # Call POST /v1/responses/compact and return the compaction item hash, or nil
  # on any failure (non-200, decrypt error, malformed body).
  def request_compaction(compact_input, model:, api_key:)
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    body = { "model" => model, "input" => compact_input }
    http = HTTP.headers(headers)
    target_uri = "#{GrokHelper::API_ENDPOINT}#{COMPACT_PATH}"

    res = post_json_with_retries(http, target_uri, body,
                                 max_retries: GrokHelper::MAX_RETRIES,
                                 retry_delay: GrokHelper::RETRY_DELAY)
    return nil if res.nil? || res.status.nil?

    unless res.status.success?
      Monadic::Utils::ExtraLogger.log { "[Grok] compact endpoint HTTP #{res.status.code}: #{res.body.to_s[0..500]}" }
      return nil
    end

    parsed = JSON.parse(res.body)
    item = Array(parsed["output"]).find { |o| o.is_a?(Hash) && o["type"] == "compaction" }
    return nil unless item && item["encrypted_content"]
    item
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Grok] compact request error: #{e.class}: #{e.message}" }
    nil
  end
end
