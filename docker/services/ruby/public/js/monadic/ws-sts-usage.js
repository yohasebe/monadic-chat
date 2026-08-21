/**
 * ws-sts-usage.js
 *
 * Session-cumulative cost readout for speech-to-speech turns.
 *
 * Why it exists: STS is billed by audio token and runs an order of magnitude
 * or two above the ordinary STT → LLM → TTS pipeline. A conversation left
 * running is a real charge, and the only honest way to opt someone into that
 * is to keep the running total in front of them.
 *
 * Why the numbers come from the server: `sts_stream_handler.rb` computes the
 * estimate from its own rate constants and sends it on `sts_audio_done`. This
 * module only accumulates and formats — duplicating the rates here would mean
 * a price change silently updating one side and not the other.
 *
 * Labeling depends on the provider's billing basis (accounting.billing_basis):
 *   - token-based (OpenAI): the figure is an UPPER BOUND — all audio input is
 *     priced at the full rate even though cached input bills far lower.
 *   - per_minute (xAI): the figure is an ESTIMATE, not a bound — the tail
 *     between the last response and Stop is not captured, so it can
 *     understate slightly. The label must not promise "upper bound" there.
 */
(function() {
  "use strict";

  let sessionCostUsd = 0;
  let turnCount = 0;
  let perMinuteBilling = false;
  // Whether any turn actually reported a usable cost. Without this a session
  // whose accounting never arrived would read "$0.00", i.e. free — the one
  // thing a cost readout must never imply by accident.
  let hasCostData = false;

  function indicator() {
    return document.getElementById('sts-usage-indicator');
  }

  function t(key, fallback) {
    return (typeof webUIi18n !== 'undefined') ? webUIi18n.t(key) : fallback;
  }

  // Sub-cent amounts are the norm for a single turn, so a flat 2-decimal
  // format would show "$0.00" and read as free.
  function formatUsd(amount) {
    if (!(amount > 0)) return '$0.00';
    if (amount < 0.01) return '<$0.01';
    return '$' + amount.toFixed(2);
  }

  function render() {
    const el = indicator();
    if (!el) return;

    if (turnCount === 0) {
      el.style.display = 'none';
      el.innerHTML = '';
      return;
    }

    const label = perMinuteBilling
      ? t('ui.messages.stsEstimatedCostPerMinute', 'Estimated cost (per-minute billing)')
      : t('ui.messages.stsEstimatedCost', 'Estimated cost (upper bound)');
    el.style.display = '';
    // Keep the layout class the markup was created with; replacing className
    // outright would drop the navbar spacing.
    el.className = 'me-2 sts-usage-indicator';
    el.setAttribute('title', label);

    // "—" rather than "$0.00" when nothing usable was reported: an unknown
    // charge and a zero charge must not look the same.
    const amount = hasCostData ? formatUsd(sessionCostUsd) : '—';
    el.innerHTML = "<i class='fas fa-microphone-lines'></i> " +
                   window.escapeHtml(amount) +
                   " <span class='text-secondary'>" + window.escapeHtml(t('ui.messages.stsEstimateShort', 'est.')) + "</span>";
  }

  /**
   * Record one completed STS turn.
   * @param {Object} accounting - server-computed accounting from sts_audio_done
   */
  function record(accounting) {
    if (!accounting) return;

    const cost = Number(accounting.estimated_cost_usd);
    // Unpriced providers (Gemini Live: token counts but no pinned audio
    // rate) get NO cost line — a fabricated figure is worse than none.
    if (accounting.billing_basis !== 'unpriced' && Number.isFinite(cost) && cost >= 0) {
      sessionCostUsd += cost;
      hasCostData = true;
    }
    if (accounting.billing_basis === 'per_minute') perMinuteBilling = true;
    turnCount += 1;
    render();
  }

  function handleStsAudioDone(data) {
    if (!data) return;
    record(data.accounting);
  }

  // Called when the conversation is cleared. The figure is per-conversation,
  // not per-page: leaving it standing after a reset would attribute the old
  // conversation's spend to the new one.
  function reset() {
    sessionCostUsd = 0;
    turnCount = 0;
    hasCostData = false;
    render();
  }

  const ns = {
    handleStsAudioDone: handleStsAudioDone,
    record: record,
    reset: reset,
    formatUsd: formatUsd,
    getSessionCostUsd: function() { return sessionCostUsd; },
    getTurnCount: function() { return turnCount; }
  };

  window.WsStsUsage = ns;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
