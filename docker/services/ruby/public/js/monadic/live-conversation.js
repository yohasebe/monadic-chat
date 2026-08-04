/**
 * live-conversation.js
 *
 * UI and capture driver for Live Conversation — the dedicated speech-to-speech
 * app family. An app declares `speech_to_speech true` in MDSL; this module
 * then replaces the text-input panel with Start/Stop controls and runs a
 * continuous microphone stream. Turn detection, response creation and
 * barge-in all happen upstream (server VAD); the client's whole job is:
 *
 *   Start  → STS_START {greet} + stream AUDIO_CHUNK until Stop
 *   Stop   → STS_STOP + release the mic + unlock cards
 *   render → user temp-card for live transcripts; status line from
 *            sts_vad / sts_session / audio-delta activity
 *
 * Cards themselves arrive on the ordinary paths (stt/user html/fragment/html)
 * and are content-final per turn; this module only locks their edit controls
 * while a conversation is active.
 */
(function() {
  "use strict";

  // Capture sample rate. Providers differ (OpenAI/xAI: 24000, Gemini Live:
  // 16000) — each Live Conversation app declares sts_input_rate in MDSL and
  // setAppMode picks it up; 24000 remains the default.
  const DEFAULT_REALTIME_RATE = 24000;
  let captureRate = DEFAULT_REALTIME_RATE;

  let lcMode = false;        // current app is a speech-to-speech app
  let active = false;        // a conversation is running (Start pressed)
  let capture = null;        // { stream, audioCtx, workletNode, source, silentGain }
  let userTempEl = null;     // live user-transcript card
  let assistantTalking = false;

  // Test seam: capture is hardware-bound (getUserMedia + AudioWorklet), so
  // tests replace the factory rather than faking half the Web Audio API.
  let captureFactory = defaultCaptureFactory;

  // UI surface that a realtime session does not consume. The same set is
  // hidden by CSS (.lc-app rules in monadic.css); this JS enforcement exists
  // because the two files can skew — a cached stylesheet against fresh
  // markup left the AI User row operable in dogfood. Inline style wins over
  // any stylesheet state.
  const HIDDEN_IN_LC = [
    'ai-user-row', 'ai-status-panel', 'auto-speech-form', 'easy-submit-form',
    'voice-panel', 'websearch-form', 'math-form', 'reasoning-effort-container',
    'thinking-display-container', 'model_parameters',
    'context-size-col', 'max-tokens-col', 'show-all-models-form'
  ];

  function t(key, fallback) {
    return (typeof webUIi18n !== 'undefined') ? (webUIi18n.t(key) || fallback) : fallback;
  }

  function currentChatModel() {
    const el = $id('model');
    return (el && el.value) ? el.value : '';
  }

  // ── Panel ──────────────────────────────────────────────────────────
  // Injected INSIDE #user-panel so its visibility follows the existing
  // session lifecycle ($show/$hide of the panel); CSS hides the sibling
  // input rows while body.lc-app is set.
  function ensurePanel() {
    if ($id('lc-panel')) return;
    const userPanel = $id('user-panel');
    if (!userPanel) return;

    // Styled like the other user-panel control rows (left-aligned, small
    // buttons) but with a hue of its own: this button opens a LIVE audio
    // channel, not a typed submit — btn-lc (violet, defined in monadic.css)
    // keeps it visually distinct from the primary/confirm blue.
    const panel = document.createElement('div');
    panel.id = 'lc-panel';
    panel.className = 'py-3';
    panel.innerHTML =
      '<div id="lc-instruction" class="text-secondary mb-3" style="display:none !important;"></div>' +
      '<div id="lc-controls-row" class="d-flex align-items-center flex-wrap mb-3"></div>' +
      '<div class="d-flex align-items-center mt-1">' +
      '<span class="me-3"><i class="fas fa-tower-broadcast me-1"></i><span id="lc-app-label"></span></span>' +
      '<button id="lc-toggle" class="btn btn-sm btn-lc text-nowrap" type="button">' +
      '<span id="lc-toggle-label"></span>' +
      '<i id="lc-action-icon" class="fas fa-play ms-1"></i></button>' +
      '<div id="lc-status" class="text-secondary small ms-3"></div>' +
      '</div>';
    userPanel.prepend(panel);

    $on($id('lc-toggle'), 'click', function() {
      if (active) { stopConversation(); } else { startConversation(); }
    });
    renderControls();
  }

  // ── Voice / speed controls (LC-specific, NOT part of HIDDEN_IN_LC) ──
  // Voice lists come from model_spec (SSOT: sts_voices / sts_voice); the
  // selector writes params.sts_voice and the change applies from the next
  // Start (the bridge pins voice at creation). sts_speed exists only for
  // providers whose spec marks sts_speed_capability (OpenAI) — it is never
  // offered, let alone sent, for others.
  function ensureVoiceControls() {
    const panel = $id('lc-panel');
    const controlsRow = $id('lc-controls-row');
    if (!panel || !controlsRow || $id('lc-voice-select')) return;
    // The voice/speed/websearch/cardview row lives in #lc-controls-row,
    // ABOVE the Start/Stop button (layout request).
    controlsRow.innerHTML =
      '<label for="lc-voice-select" class="text-secondary me-2" id="lc-voice-label"></label>' +
      '<select id="lc-voice-select" class="form-select form-select-sm" style="max-width: 160px;"></select>' +
      // NO d-flex here: Bootstrap's .d-flex is `display:flex !important`
      // and would beat the inline `display:none` used to hide this wrap on
      // xAI/Gemini (the same trap as the AI User row). Visibility is
      // driven exclusively by renderVoiceControls via setProperty.
      '<span id="lc-speed-wrap" class="text-secondary align-items-center ms-3" style="display:none !important;">' +
      '<label for="lc-speed-range" class="text-secondary me-2" id="lc-speed-label"></label>' +
      '<input type="range" id="lc-speed-range" min="0.25" max="1.5" step="0.05" value="1.0" style="width: 90px;">' +
      '<span id="lc-speed-value" class="text-secondary small ms-1">1.0</span>' +
      '</span>' +
      '<span id="lc-cardview-wrap" class="text-secondary align-items-center ms-3">' +
      '<input type="checkbox" id="lc-cardview-toggle" class="form-check-input me-1">' +
      '<label for="lc-cardview-toggle" class="text-secondary" id="lc-cardview-label"></label>' +
      '</span>' +
      '<span id="lc-tools-wrap" class="text-secondary align-items-center ms-3" style="display:none !important;">' +
      '<input type="checkbox" id="lc-tools-toggle" class="form-check-input me-1">' +
      '<label for="lc-tools-toggle" class="text-secondary" id="lc-tools-label"></label>' +
      '</span>' +
      // Turn-detection selector (§37-16): ONE folded control — separate
      // type/eagerness controls would show eagerness for a mode that does
      // not use it. Capability-gated to OpenAI (semantic_vad + eagerness
      // support, live-probed). Labels name WHAT is judged, never API terms.
      '<span id="lc-turn-wrap" class="text-secondary align-items-center ms-3" style="display:none !important;">' +
      // text-nowrap: this label is the longest in the row, and without it the
      // label itself breaks mid-word ("ターン / 判定") once the row fills up.
      // The row already wraps as a whole (flex-wrap), so the control moves to
      // the next line instead — which reads correctly.
      '<label for="lc-turn-select" class="text-secondary text-nowrap me-2" id="lc-turn-label"></label>' +
      '<select id="lc-turn-select" class="form-select form-select-sm" style="max-width: 200px;">' +
      '<option value="" id="lc-turn-opt-silence"></option>' +
      '<option value="low" id="lc-turn-opt-low"></option>' +
      '<option value="medium" id="lc-turn-opt-medium"></option>' +
      '<option value="high" id="lc-turn-opt-high"></option>' +
      '</select>' +
      '</span>';

    $id('lc-app-label').textContent = currentAppDisplayName();

    $id('lc-voice-label').textContent = t('ui.messages.lcVoice', 'Voice');
    $id('lc-speed-label').textContent = t('ui.messages.lcSpeed', 'Speed');
    // The label names the SCOPE of the setting ("while talking"), not just
    // the mode: the toggle only governs the in-conversation display, and a
    // bare "Card view" read as broken once the session ended, where cards
    // are the only display there is (dogfood).
    $id('lc-cardview-label').textContent = t('ui.messages.lcCardView', 'Cards while talking');
    $id('lc-tools-label').textContent = t('ui.messages.lcTools', 'Tools');
    $id('lc-turn-label').textContent = t('ui.messages.lcTurnDetection', 'Turn detection');
    $id('lc-turn-opt-silence').textContent = t('ui.messages.lcTurnSilence', 'By silence (default)');
    $id('lc-turn-opt-low').textContent = t('ui.messages.lcTurnLow', 'By meaning — patient');
    $id('lc-turn-opt-medium').textContent = t('ui.messages.lcTurnMedium', 'By meaning — balanced');
    $id('lc-turn-opt-high').textContent = t('ui.messages.lcTurnHigh', 'By meaning — quick');

    $on($id('lc-voice-select'), 'change', function() {
      if (typeof params !== 'undefined') {
        params['sts_voice'] = $id('lc-voice-select').value;
        // §37-14A: remember the choice per provider in a cookie (same
        // pattern as the TTS voice) — the voice sets are disjoint
        // (10/26/30), so a shared key would fall back to the default on
        // every provider switch.
        const modelElNow = $id('model');
        const specNow = (window.modelSpec && modelElNow && modelElNow.value)
          ? (window.modelSpec[modelElNow.value] || {}) : {};
        if (typeof setCookie === 'function' && specNow.sts_provider) {
          setCookie('lc-voice-' + specNow.sts_provider, params['sts_voice'], 30);
        }
        if (typeof window.broadcastParamsUpdate === 'function') window.broadcastParamsUpdate('sts_voice_change');
      }
    });
    // Re-render when the model select is (re)built: at setAppMode time the
    // async dropdown may not hold the LC model yet, leaving the voice
    // selector empty (bug: OpenAI/Gemini never populated on first load).
    const modelEl = $id('model');
    if (modelEl) $on(modelEl, 'change', renderVoiceControls);
    $on($id('lc-cardview-toggle'), 'change', function() {
      if (typeof params !== 'undefined') {
        params['sts_card_view'] = $id('lc-cardview-toggle').checked;
        if (typeof window.broadcastParamsUpdate === 'function') window.broadcastParamsUpdate('sts_card_view_toggle');
      }
      applyViewMode();
    });
    $on($id('lc-tools-toggle'), 'change', function() {
      if (typeof params !== 'undefined') {
        params['sts_tools'] = $id('lc-tools-toggle').checked;
        if (typeof window.broadcastParamsUpdate === 'function') window.broadcastParamsUpdate('sts_tools_toggle');
      }
    });
    $on($id('lc-turn-select'), 'change', function() {
      if (typeof params !== 'undefined') {
        const v = $id('lc-turn-select').value;
        // §37-16: one folded control drives BOTH wire keys; the silence
        // choice removes them so the MDSL default applies again.
        if (v === '') {
          delete params['sts_vad_type'];
          delete params['sts_vad_eagerness'];
        } else {
          params['sts_vad_type'] = 'semantic_vad';
          params['sts_vad_eagerness'] = v;
        }
        // Remember like the voice (per-provider key — §37-14A pattern).
        const modelElNow = $id('model');
        const specNow = (window.modelSpec && modelElNow && modelElNow.value)
          ? (window.modelSpec[modelElNow.value] || {}) : {};
        if (typeof setCookie === 'function' && specNow.sts_provider) {
          setCookie('lc-turn-' + specNow.sts_provider, v, 30);
        }
        if (typeof window.broadcastParamsUpdate === 'function') window.broadcastParamsUpdate('sts_vad_turn_change');
      }
    });
    $on($id('lc-speed-range'), 'change', function() {
      const v = parseFloat($id('lc-speed-range').value);
      $id('lc-speed-value').textContent = String(v);
      if (typeof params !== 'undefined') {
        params['sts_speed'] = String(v);
        if (typeof window.broadcastParamsUpdate === 'function') window.broadcastParamsUpdate('sts_speed_change');
      }
    });
  }

  function renderVoiceControls() {
    const modelEl = $id('model');
    const model = modelEl ? modelEl.value : null;
    const spec = (window.modelSpec && model) ? (window.modelSpec[model] || {}) : {};
    const sel = $id('lc-voice-select');
    if (!sel) return;

    const appLabel = $id('lc-app-label');
    if (appLabel) appLabel.textContent = currentAppDisplayName();

    const voices = Array.isArray(spec.sts_voices) ? spec.sts_voices : [];
    // §37-14A: resolve the voice in order — session param, the remembered
    // cookie for THIS provider (only if the value is still offered by the
    // current model: model changes and retired voices must not resurrect
    // it), then the model_spec default.
    // EVERY candidate is checked against the current model's voice list,
    // the session param included: switching provider leaves the previous
    // provider's voice in params (the lists share no names — 10/26/30
    // distinct ids), and an unchecked param would win over this provider's
    // remembered voice and then be rejected server-side anyway.
    const offered = function(v) { return !!v && voices.indexOf(v) !== -1; };
    let current = '';
    const fromParams = (typeof params !== 'undefined' && params['sts_voice']) || '';
    if (offered(fromParams)) current = fromParams;
    if (!current && typeof getCookie === 'function' && spec.sts_provider) {
      const remembered = getCookie('lc-voice-' + spec.sts_provider);
      if (offered(remembered)) current = remembered;
    }
    if (!current) current = spec.sts_voice || voices[0] || '';
    // Realign the session param ONLY when we overrode a value this provider
    // cannot use — Start sends params.sts_voice, so leaving the foreign
    // value there would make the UI show one voice and the session speak
    // another. Writing it unconditionally would be worse: the default would
    // stick into params on first render and no remembered cookie could ever
    // win again (caught by the cookie-restore spec).
    if (typeof params !== 'undefined' && fromParams && !offered(fromParams) && current) {
      params['sts_voice'] = current;
    }
    sel.replaceChildren();
    voices.forEach(function(v) {
      const opt = document.createElement('option');
      opt.value = v;
      opt.textContent = v;
      if (v === current) opt.selected = true;
      sel.appendChild(opt);
    });

    const wrap = $id('lc-speed-wrap');
    const speedCapable = spec.sts_speed_capability === true;
    if (wrap) {
      if (speedCapable) {
        wrap.style.removeProperty('display');
        // inline-flex, not flex: the sibling cardview wrap is a plain inline
        // span, and a block-level flex next to it shifts the baseline
        // (dogfood: vertically misaligned checkboxes).
        wrap.style.setProperty('display', 'inline-flex');
      } else {
        // 'important' is load-bearing: without it, an important stylesheet
        // declaration could resurrect the control on non-capable providers.
        wrap.style.setProperty('display', 'none', 'important');
      }
    }
    if (speedCapable) {
      const s = (typeof params !== 'undefined' && params['sts_speed']) || '1.0';
      $id('lc-speed-range').value = s;
      $id('lc-speed-value').textContent = s;
    }

    // Tools toggle (function calling wave 1): capability-gated, default
    // OFF. Available on all three providers — the shared search_web tool
    // covers web search everywhere (the native search toggles were removed
    // as duplicates, 2026-08-03).
    const toolsWrap = $id('lc-tools-wrap');
    if (toolsWrap) {
      const toolsCapable = spec.sts_tools_capability === true;
      if (toolsCapable) {
        toolsWrap.style.removeProperty('display');
        toolsWrap.style.setProperty('display', 'inline-flex'); // see lc-speed-wrap
        $id('lc-tools-toggle').checked =
          typeof params !== 'undefined' &&
          (params['sts_tools'] === true || params['sts_tools'] === 'true');
      } else {
        toolsWrap.style.setProperty('display', 'none', 'important');
      }
    }

    // Turn-detection selector (§37-16): capability-gated to providers whose
    // semantic mode is probe-verified (OpenAI only). Restore order: session
    // params (validated) → remembered cookie (validated) → silence default.
    const turnWrap = $id('lc-turn-wrap');
    if (turnWrap) {
      const turnCapable = spec.sts_semantic_vad_capability === true;
      if (turnCapable) {
        turnWrap.style.removeProperty('display');
        turnWrap.style.setProperty('display', 'inline-flex'); // see lc-speed-wrap
        const CHOICES = ['', 'low', 'medium', 'high'];
        const pType = (typeof params !== 'undefined' && params['sts_vad_type']) || '';
        const pEager = (typeof params !== 'undefined' && params['sts_vad_eagerness']) || '';
        let choice = '';
        if (pType === 'semantic_vad' && CHOICES.indexOf(pEager) > 0) {
          choice = pEager;
        } else if (!pType && typeof getCookie === 'function' && spec.sts_provider) {
          const remembered = getCookie('lc-turn-' + spec.sts_provider);
          if (remembered !== null && remembered !== undefined &&
              CHOICES.indexOf(remembered) !== -1) {
            choice = remembered;
          }
        }
        $id('lc-turn-select').value = choice;
        // Restoring from the cookie fires no `change`, so the params the
        // bridge actually reads stayed empty and the session fell back to
        // the MDSL default — the UI showed a setting that was not in
        // effect (dogfood: selector said "by meaning" while the wire
        // carried server_vad). Write the restored choice through.
        if (typeof params !== 'undefined') {
          if (choice === '') {
            delete params['sts_vad_type'];
            delete params['sts_vad_eagerness'];
          } else {
            params['sts_vad_type'] = 'semantic_vad';
            params['sts_vad_eagerness'] = choice;
          }
        }
      } else {
        // A provider without the capability must not carry a stale semantic
        // choice into its session either.
        if (typeof params !== 'undefined') {
          delete params['sts_vad_type'];
          delete params['sts_vad_eagerness'];
        }
        turnWrap.style.setProperty('display', 'none', 'important');
      }
    }

    const cv = $id('lc-cardview-toggle');
    if (cv) {
      cv.checked = typeof params !== 'undefined' &&
        (params['sts_card_view'] === true || params['sts_card_view'] === 'true');
    }
  }

  // ── Live view (non-card, default during active conversation) ──────
  // A pure DISPLAY alternative to the card stream: #discourse is hidden
  // and two zones show the previous partner utterance and the in-flight
  // one. Canon and card accumulation are UNCHANGED — Stop always
  // returns to the normal (merged) card list. All display switches use
  // setProperty('important') because Bootstrap utilities beat plain
  // inline styles (the d-flex trap).
  let livePrev = { role: null, text: '', badges: [] };
  let liveCurrent = { role: null, text: '', badges: [] };
  // Text of the last FINAL user transcript (stt). Partials are cumulative
  // prefixes of their eventual final, so a partial that is a prefix of this
  // is a late re-stream of an already-finalized utterance — display-only
  // noise (dogfood round 6: the whole partial stream can lag the response).
  let lastUserFinal = '';

  function cardViewEnabled() {
    return typeof params !== 'undefined' &&
      (params['sts_card_view'] === true || params['sts_card_view'] === 'true');
  }

  function liveViewWanted() {
    return lcMode && active && !cardViewEnabled();
  }

  function ensureLiveView() {
    if ($id('lc-liveview')) return;
    const discourse = $id('discourse');
    if (!discourse || !discourse.parentNode) return;
    const lv = document.createElement('div');
    lv.id = 'lc-liveview';
    lv.style.setProperty('display', 'none', 'important');
    lv.innerHTML =
      '<div id="lc-live-prev" class="lc-live-zone lc-live-prev">' +
      '<div class="lc-live-role"></div><div class="lc-live-text"></div></div>' +
      '<div id="lc-live-current" class="lc-live-zone">' +
      '<div class="lc-live-role"></div><div class="lc-live-text"></div></div>';
    discourse.parentNode.insertBefore(lv, discourse);
  }

  function applyViewMode() {
    const discourse = $id('discourse');
    ensureLiveView();
    const lv = $id('lc-liveview');
    if (!discourse || !lv) return;
    if (liveViewWanted()) {
      discourse.style.setProperty('display', 'none', 'important');
      lv.style.removeProperty('display');
      lv.style.setProperty('display', 'block');
      renderLiveView();
    } else {
      lv.style.setProperty('display', 'none', 'important');
      discourse.style.removeProperty('display');
    }
  }

  function zoneText(role) {
    return role === 'user'
      ? t('ui.messages.lcRoleUser', 'You')
      : t('ui.messages.lcRoleAssistant', 'Assistant');
  }

  // Tool badges in the live view (§37-5): the same semantics as the folded
  // card — a tool-bridged exchange accumulates as ONE text with "\n\n"
  // paragraph breaks, and each tool badge anchors at the paragraph boundary
  // where the call happened. Calls awaiting their answer's first fragment
  // sit in liveToolPending; the boundary is only fixed then, because the
  // bridge utterance keeps growing until the answer response starts.
  // Badges live ON the zone entry so promotion to prev carries them along.
  let liveToolPending = []; // [{name, status}]

  function renderZone(zone, entry, highlightChar) {
    const roleEl = zone.querySelector('.lc-live-role');
    const textEl = zone.querySelector('.lc-live-text');
    if (roleEl) {
      roleEl.textContent = entry.role ? zoneText(entry.role) : '';
    }
    if (textEl) {
      // Paragraph split (§37-5): same "\n\n" semantics as the folded card.
      // The CURRENT zone may also carry the speech-highlight span (§37-13C).
      const paras = String(entry.text || '').split('\n\n');
      textEl.replaceChildren();
      let offset = 0;
      paras.forEach(function(para) {
        if (highlightChar !== null && highlightChar !== undefined) {
          appendParagraphWithHighlight(textEl, para, offset, highlightChar);
        } else {
          const p = document.createElement('p');
          p.textContent = para;
          textEl.appendChild(p);
        }
        offset += para.length + 2;
      });
      // Inline badges at the paragraph boundary — same helper as the card.
      if (entry.role === 'assistant' && Array.isArray(entry.badges) && entry.badges.length > 0 &&
          typeof window.insertInlineToolBadge === 'function') {
        window.insertInlineToolBadge(textEl, entry.badges);
      }
    }
  }

  function renderLiveView() {
    const prev = $id('lc-live-prev');
    const cur = $id('lc-live-current');
    let prevEntry = livePrev;
    // Invariant (b) (§37-6): never show one utterance in both zones — a
    // same-role prev whose text is a prefix of (or equal to) the current
    // zone's text is a stale copy, so the prev zone stays empty.
    if (prevEntry.role && prevEntry.role === liveCurrent.role &&
        liveCurrent.text.startsWith(prevEntry.text)) {
      prevEntry = { role: null, text: '', badges: [] };
    }
    if (prev) renderZone(prev, prevEntry);
    if (cur) renderZone(cur, liveCurrent,
      liveCurrent.role === 'assistant' ? lastHighlightChar : null);
  }

  // Replace semantics (each stt_partial / stt carries the whole utterance
  // so far); a role change promotes the finished side to prev.
  // isFinal marks the completed transcript (stt) vs a streaming partial.
  function liveSet(role, text, isFinal) {
    // Late-duplicate guard: a partial that is a prefix of the last FINAL
    // transcript is a re-stream of that same (already shown) utterance.
    // Acting on it would promote the in-flight assistant zone for no reason
    // (the original resume-swap bug: assistant text lost its beginning).
    if (role === 'user' && !isFinal && liveCurrent.role === 'assistant' &&
        lastUserFinal && text && lastUserFinal.startsWith(text)) {
      return;
    }
    if (liveCurrent.role && liveCurrent.role !== role) livePromote();
    liveCurrent = { role: role, text: text, badges: [],
                    final: role === 'user' ? !!isFinal : true };
    if (role === 'user' && isFinal) lastUserFinal = text;
    // A new current zone invalidates the segment map and the highlight.
    liveSegments = [];
    lastHighlightChar = null;
    highlightSegmentId = null;
    if (liveViewWanted()) renderLiveView();
  }

  // Append semantics for assistant streaming fragments; is_first starts a
  // fresh accumulation (barge-in / new response) — EXCEPT the first
  // fragment of a tool's ANSWER, which continues the same accumulation as
  // a new paragraph (mirroring the server-side fold).
  //
  // segmentId (§37-13C) marks the upstream response this text belongs to;
  // liveSegments records where each segment starts in the zone text so the
  // speech highlight can map playback time onto characters.
  let liveSegments = [];       // [{id, startChar}]
  let lastHighlightChar = null; // freeze target during silence / barge-in
  let highlightSegmentId = null; // segment the floor above belongs to

  function noteSegment(segmentId, startChar, reset) {
    if (!segmentId) return;
    if (reset) liveSegments = [];
    const last = liveSegments[liveSegments.length - 1];
    if (!last || last.id !== segmentId) {
      liveSegments.push({ id: segmentId, startChar: startChar });
    }
  }

  function liveAppend(role, delta, isFirst, segmentId) {
    if (isFirst) {
      // §37-13A: the tool-continuation zone can also sit in PREV — on
      // Gemini the late user-final arrives between the call and the answer
      // and promotes the badge-only zone out of current. Pull it back so
      // the answer continues in the zone that holds the badges.
      let zone = null;
      if (role === 'assistant' && liveToolPending.length > 0) {
        if (liveCurrent.role === 'assistant' &&
            (liveCurrent.text.trim() !== '' || liveCurrent.badges.length > 0)) {
          zone = liveCurrent;
        } else if (livePrev.role === 'assistant' && livePrev.badges.length > 0 &&
                   livePrev.text.trim() === '') {
          zone = livePrev;
          livePrev = liveCurrent.role ? liveCurrent : { role: null, text: '', badges: [] };
          liveCurrent = zone;
        }
      }
      if (zone) {
        // Tool-bridged continuation (§37-5): the wire order is tool done →
        // response.create → the answer's is_first. Anchor each pending call
        // at the boundary (= the bridge paragraph count) and keep
        // accumulating instead of resetting — otherwise the live view would
        // show only the answer while the card shows the folded whole.
        const hasText = zone.text.trim() !== '';
        const at = hasText ? zone.text.split('\n\n').length : 0;
        liveToolPending.forEach(function(p) {
          // §37-12: a badge drawn when the call STARTED already sits at this
          // boundary — update its status rather than adding a second badge.
          // §37-14B: its `at` was fixed when the call started, but the live
          // view appends the answer to the SAME paragraph first, so the
          // paragraph count only settles now — refresh the position too.
          const existing = p.call_id &&
            zone.badges.find(function(b) { return b.call_id === p.call_id; });
          if (existing) {
            existing.status = p.status;
            existing.at = at;
          } else {
            zone.badges.push({ name: p.name, status: p.status, at: at, call_id: p.call_id });
          }
        });
        liveToolPending = [];
        noteSegment(segmentId, hasText ? zone.text.length + 2 : 0, false);
        zone.text = hasText ? zone.text + '\n\n' + delta : delta;
      } else {
        // Not the tool's answer (user barged in first, or an unrelated
        // response): the anchor is lost, discard the pending calls.
        liveToolPending = [];
        if (liveCurrent.role && liveCurrent.role !== role) livePromote();
        noteSegment(segmentId, 0, true);
        lastHighlightChar = null; // a new response starts a new highlight
        highlightSegmentId = null;
        liveCurrent = { role: role, text: delta, badges: [] };
      }
    } else if (liveCurrent.role === role) {
      noteSegment(segmentId, liveCurrent.text.length, false);
      liveCurrent.text += delta;
    } else if (livePrev.role === role && livePrev.text !== '') {
      if (liveCurrent.role === 'user' && !liveCurrent.final) {
        // The partial stream of the CURRENT turn is still arriving (it lags
        // the response — dogfood round 6). Moving a NON-FINAL user zone to
        // prev would (a) put a partial in the final-only prev slot and
        // (b) ping-pong on every fragment/partial pair. Instead the
        // response keeps accumulating in prev and the user's transcript
        // stays in current until its stt (final) lands.
        livePrev.text += delta;
      } else {
        // Resume-swap: a LATE stt_partial for a FINALIZED utterance briefly
        // promoted the in-flight assistant stream to prev (dogfood:
        // assistant text lost its beginning). The response is still in
        // flight — swap prev back into current and keep accumulating instead
        // of restarting from this fragment. The interleaved user text moves
        // to prev, so nothing is lost.
        const resumed = { role: role, text: livePrev.text + delta, badges: livePrev.badges || [] };
        livePrev = { role: liveCurrent.role, text: liveCurrent.text, badges: liveCurrent.badges || [] };
        liveCurrent = resumed;
        noteSegment(segmentId, 0, false);
      }
    } else {
      if (liveCurrent.role) livePromote();
      noteSegment(segmentId, 0, true);
      liveCurrent = { role: role, text: delta, badges: [] };
    }
    if (liveViewWanted()) renderLiveView();
  }

  function livePromote() {
    if (liveCurrent.role) livePrev = liveCurrent;
    liveCurrent = { role: null, text: '', badges: [] };
  }

  function liveReset() {
    livePrev = { role: null, text: '', badges: [] };
    liveCurrent = { role: null, text: '', badges: [] };
    liveToolPending = [];
    lastUserFinal = '';
    liveSegments = [];
    lastHighlightChar = null;
    highlightSegmentId = null;
  }

  function renderControls() {
    const label = $id('lc-toggle-label');
    const btn = $id('lc-toggle');
    if (!label || !btn) return;
    // The button carries only the ACTION (start/stop label + trailing
    // action icon); the app identity (tower + name) is the plain-text
    // lc-app-label next to it (layout request).
    const action = $id('lc-action-icon');
    if (active) {
      label.textContent = t('ui.messages.lcStop', 'End live conversation');
      btn.classList.add('btn-lc-live');
      if (action) action.className = 'fas fa-stop ms-2';
    } else {
      label.textContent = t('ui.messages.lcStart', 'Start live conversation');
      btn.classList.remove('btn-lc-live');
      if (action) action.className = 'fas fa-play ms-2';
    }
  }

  function setStatus(text) {
    const el = $id('lc-status');
    if (el) el.textContent = text || '';
  }

  // ── App-mode switch ────────────────────────────────────────────────
  let currentAppConfig = null;

  function currentAppDisplayName() {
    return (currentAppConfig && (currentAppConfig.display_name || currentAppConfig.app_name)) ||
      'Live Conversation';
  }

  function setAppMode(appConfig) {
    const on = !!(appConfig && (appConfig.speech_to_speech === true || appConfig.speech_to_speech === 'true'));
    if (lcMode && !on && active) stopConversation();
    lcMode = on;
    if (on) currentAppConfig = appConfig;
    const rate = parseInt(appConfig && appConfig.sts_input_rate, 10);
    captureRate = (Number.isFinite(rate) && rate > 0) ? rate : DEFAULT_REALTIME_RATE;
    const idleSec = parseInt(appConfig && appConfig.sts_idle_stop_seconds, 10);
    idleStopMs = Number.isFinite(idleSec) && idleSec >= 0 ? idleSec * 1000 : DEFAULT_IDLE_STOP_MS;
    document.body.classList.toggle('lc-app', on);
    HIDDEN_IN_LC.forEach(function(id) {
      const el = $id(id);
      if (!el) return;
      if (on) {
        // 'important' is load-bearing: Bootstrap utility classes like
        // .d-flex are `display: flex !important`, and an important
        // stylesheet declaration beats a normal inline style — a plain
        // `style.display = 'none'` left the AI User row visible.
        el.style.setProperty('display', 'none', 'important');
      } else if (el.style.getPropertyValue('display') === 'none' &&
                 el.style.getPropertyPriority('display') === 'important') {
        // Restore ONLY what LC itself hid (none!important is LC's
        // signature). setAppMode(off) runs at the end of EVERY loadParams,
        // and an unconditional removeProperty stripped hides that other
        // code had just applied — e.g. loadParams' own $hide of
        // #model_parameters in ordinary apps (review P1-B).
        el.style.removeProperty('display');
      }
    });
    if (on) {
      ensurePanel();
      renderInstruction();
      ensureVoiceControls();
      renderVoiceControls();
      // Hiding the toggles is not enough: a checked auto-speech carried over
      // from another app would TTS the assistant card on top of the realtime
      // audio (double speech), and easy-submit belongs to the typed pipeline.
      ['check-auto-speech', 'check-easy-submit'].forEach(function(id) {
        const el = $id(id);
        if (el && el.checked) {
          el.checked = false;
          $dispatch(el, 'change');
        }
      });
    }
    applyViewMode();
  }

  // ── Panel instruction ──────────────────────────────────────────────
  // Client-only usage note pinned ABOVE the Start button (the old
  // discourse card was invisible in the session-start flow — dogfood).
  // Shown only while the conversation is empty; never part of the canon.
  function renderInstruction() {
    const el = $id('lc-instruction');
    if (!el) return;
    const show = lcMode && !active && (window.messages || []).length === 0;
    if (show) {
      el.textContent = t('ui.messages.lcIntro',
        'Press "Start live conversation" to begin. Speaking then continues hands-free — ' +
        'turns are detected automatically. Press "End live conversation" to finish. ' +
        'Headphones are recommended.');
      el.style.removeProperty('display');
    } else {
      el.style.setProperty('display', 'none', 'important');
    }
  }

  // ── Idle auto-stop ─────────────────────────────────────────────────
  // With no speech in either direction for this long, the conversation
  // ends by itself — both a courtesy (the user walked away) and a cost
  // guard (xAI bills idle session minutes too). MDSL can override via
  // sts_idle_stop_seconds; 0 disables.
  const DEFAULT_IDLE_STOP_MS = 180000;
  let idleStopMs = DEFAULT_IDLE_STOP_MS;
  let lastActivityAt = 0;
  let idleTimer = null;

  function noteActivity() {
    lastActivityAt = Date.now();
  }

  function startIdleWatch() {
    stopIdleWatch();
    if (!idleStopMs) return;
    noteActivity();
    idleTimer = setInterval(function() {
      if (!active) return;
      if (Date.now() - lastActivityAt < idleStopMs) return;
      stopConversation();
      if (typeof setAlert === 'function') {
        setAlert("<i class='fas fa-hourglass-end'></i> " +
          t('ui.messages.lcIdleStopped', 'No speech for a while — the live conversation ended.'),
          'warning');
      }
    }, 10000);
  }

  function stopIdleWatch() {
    if (idleTimer) { clearInterval(idleTimer); idleTimer = null; }
  }

  // ── Capture ────────────────────────────────────────────────────────
  async function defaultCaptureFactory(onChunk, targetRate) {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
    });
    const AudioCtor = window.AudioContext || window.webkitAudioContext;
    const audioCtx = new AudioCtor();
    await audioCtx.audioWorklet.addModule('/js/monadic/audio-pcm-encoder-worklet.js');
    const source = audioCtx.createMediaStreamSource(stream);
    const workletNode = new AudioWorkletNode(audioCtx, 'pcm-encoder', {
      processorOptions: { targetRate: targetRate || DEFAULT_REALTIME_RATE, frameMs: 100 }
    });
    const silentGain = audioCtx.createGain();
    silentGain.gain.value = 0;
    source.connect(workletNode);
    workletNode.connect(silentGain);
    silentGain.connect(audioCtx.destination);
    workletNode.port.onmessage = function(event) {
      const buf = event.data;
      if (buf && buf.byteLength) onChunk(buf);
    };
    return {
      stop() {
        try { workletNode.port.onmessage = null; } catch (_) { /* noop */ }
        try { source.disconnect(); } catch (_) { /* noop */ }
        try { workletNode.disconnect(); } catch (_) { /* noop */ }
        try { silentGain.disconnect(); } catch (_) { /* noop */ }
        try { if (audioCtx.state !== 'closed') audioCtx.close(); } catch (_) { /* noop */ }
        try { stream.getTracks().forEach(tr => tr.stop()); } catch (_) { /* noop */ }
      }
    };
  }

  // ── Echo gate ──────────────────────────────────────────────────────
  // With speakers (no headphones) the assistant's own voice leaks into the
  // mic; browser AEC does not reliably cancel WebAudio output, so the
  // upstream VAD hears the leak as user speech and answers itself — the
  // dogfood failure mode was a self-talk cascade ("a" cards, overlapping
  // responses). While assistant audio is actually audible (playback state,
  // not delta-arrival state), quiet chunks are dropped; direct speech is
  // louder than leakage and passes, so barge-in still works.
  // Tunable from the console for dogfooding: window.LC_ECHO_GATE_RMS
  // (0 disables).
  const DEFAULT_ECHO_GATE_RMS = 0.015;
  let gatedChunks = 0;

  function chunkRms(buf) {
    const samples = new Int16Array(buf);
    if (samples.length === 0) return 0;
    let sum = 0;
    for (let i = 0; i < samples.length; i++) {
      const s = samples[i] / 32768;
      sum += s * s;
    }
    return Math.sqrt(sum / samples.length);
  }

  function echoGateBlocks(buf) {
    const threshold = (typeof window.LC_ECHO_GATE_RMS === 'number')
      ? window.LC_ECHO_GATE_RMS : DEFAULT_ECHO_GATE_RMS;
    if (threshold <= 0) return false;
    const sts = window.WsStsPlayback;
    if (!sts || typeof sts.isPlaying !== 'function' || !sts.isPlaying()) return false;
    if (chunkRms(buf) >= threshold) return false;
    gatedChunks += 1;
    if (gatedChunks % 50 === 1) {
      console.debug('[LiveConversation] echo gate dropped ' + gatedChunks + ' quiet chunks during playback');
    }
    return true;
  }

  function bufToBase64(buf) {
    const bytes = new Uint8Array(buf);
    const CHUNK = 0x8000;
    let binary = '';
    for (let i = 0; i < bytes.length; i += CHUNK) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK));
    }
    return btoa(binary);
  }

  // ── Session lifecycle ──────────────────────────────────────────────
  async function startConversation() {
    if (active || !lcMode) return;
    const chatModel = currentChatModel();

    // The app-switch reset confirmation keys on this flag ("the user built a
    // conversation in this tab"), but it is only set by the TEXT submit
    // paths — a voice-only Live Conversation never passes through them, so
    // switching apps after a voice session wiped the conversation with no
    // confirmation (§37-7). Starting a voice conversation is a user action
    // too.
    window.userHasInteractedInTab = true;

    // The greet flag carries only the toggle state. Whether this is a FRESH
    // conversation (greeting) or a resume (silent seeding) is decided
    // server-side against the canonical session[:messages] — the client-side
    // messages array proved stale in dogfood and silently suppressed the
    // greeting on a genuinely fresh conversation.
    const initiateEl = $id('initiate-from-assistant');
    const greet = !!(initiateEl && initiateEl.checked);

    active = true;
    renderControls();
    setStatus(t('ui.messages.lcConnecting', 'Connecting…'));
    lockCards(true);
    liveReset();
    applyViewMode();

    let cap;
    try {
      cap = await captureFactory(function(buf) {
        // Guard against a Stop that landed while capture was starting up:
        // orphaned worklet callbacks must not stream into a stopped bridge.
        if (!active) return;
        if (echoGateBlocks(buf)) return;
        window.safeWsSend({
          message: 'AUDIO_CHUNK',
          content: bufToBase64(buf),
          chat_model: chatModel
        });
      }, captureRate);
    } catch (err) {
      // No silent degradation: without the mic there is no conversation.
      console.error('[LiveConversation] capture failed:', err);
      active = false;
      renderControls();
      lockCards(false);
      setStatus('');
      if (typeof setAlert === 'function') {
        setAlert(`<i class='fas fa-circle-exclamation'></i> ${t('ui.messages.lcMicFailed', 'Microphone access failed. Check permissions and try again.')}`, 'error');
      }
      return;
    }

    // Stop (or RESET) can land during the await above; getUserMedia's
    // permission prompt is arbitrarily long. In that case the capture we
    // just built is an orphan: release it and do NOT open the bridge.
    if (!active) {
      try { cap.stop(); } catch (_) { /* noop */ }
      return;
    }
    capture = cap;

    renderInstruction();
    startIdleWatch();
    startHighlightWatch();
    window.safeWsSend({ message: 'STS_START', chat_model: chatModel, greet: greet });
  }

  function stopConversation() {
    if (!active) return;
    active = false;
    stopIdleWatch();
    stopHighlightWatch();
    try { window.safeWsSend({ message: 'STS_STOP' }); } catch (_) { /* socket may be gone */ }
    if (capture) { try { capture.stop(); } catch (_) { /* noop */ } capture = null; }
    const sts = window.WsStsPlayback;
    if (sts && typeof sts.stopAll === 'function') sts.stopAll();
    removeUserTemp();
    removeAbsorbedTempCard();
    resetStreamingIndicators();
    assistantTalking = false;
    renderControls();
    setStatus('');
    lockCards(false);
    applyViewMode(); // always returns to the normal (merged) card list
  }

  // ── Card locking ───────────────────────────────────────────────────
  // Content is final per turn; what Stop unlocks is editability. The lock is
  // a body class so CSS can disable every card's edit/delete controls at
  // once without touching individual cards.
  function lockCards(on) {
    document.body.classList.toggle('lc-locked', on);
  }

  // ── Live user transcript (temp card) ───────────────────────────────
  // The ordinary partial display lives on the text input's overlay, which
  // this app does not have — so partials get a temp card, symmetric with the
  // assistant's streaming temp-card, replaced by the server-rendered user
  // card when the turn's transcription completes.
  function ensureUserTemp() {
    if (userTempEl && userTempEl.isConnected) return userTempEl;
    if (liveViewWanted()) return null; // live view renders user speech itself
    const discourse = $id('discourse');
    if (!discourse) return null;
    userTempEl = document.createElement('div');
    userTempEl.id = 'lc-user-temp';
    userTempEl.className = 'card mt-3 lc-user-temp';
    userTempEl.innerHTML =
      '<div class="card-header p-2 ps-3">' +
      '<span class="text-secondary"><i class="fas fa-face-smile"></i></span> ' +
      '<span class="fw-bold fs-6 user-color">User</span></div>' +
      '<div class="card-body"><div class="card-text lc-user-temp-text"></div></div>';
    discourse.appendChild(userTempEl);
    return userTempEl;
  }

  function removeUserTemp() {
    if (userTempEl) { try { userTempEl.remove(); } catch (_) { /* noop */ } userTempEl = null; }
  }

  // Ghost suppression (§37-3): a streaming temp-card whose content was
  // already folded into a finalized card must not linger as a display-only
  // duplicate. A merged:false Stop skips the LOAD re-render that would
  // otherwise clear it, so Stop itself removes it. Containment is checked
  // against the card BODY (the temp-card header's "Assistant" label is not
  // part of the streamed text). A temp-card with genuinely un-absorbed
  // content (an unfinished response) stays — hiding it would lose text.
  function removeAbsorbedTempCard() {
    const temp = $id('temp-card');
    if (!temp) return;
    const tempBody = temp.querySelector('.card-text');
    const tempText = ((tempBody ? tempBody.textContent : '') || '').trim();
    if (!tempText) { temp.remove(); return; } // empty streaming shell
    const discourse = $id('discourse');
    if (!discourse) return;
    const absorbed = Array.prototype.some.call(
      discourse.querySelectorAll('.card:not(#temp-card) .card-text'),
      function(el) { return (el.textContent || '').includes(tempText); }
    );
    if (absorbed) temp.remove();
  }

  // Streaming-indicator reset (§37-5): assistant text arrives as "fragment"
  // messages, and the typed pipeline's fragment path sets the RESPONDING
  // alert plus responseStarted/streamingResponse — flags only its own
  // completion path clears. Stop (user, server-side, or mirrored) IS the
  // end of the response cycle here, so clear them or the status corner
  // stays "RESPONDING" after the conversation ended. The READY alert fires
  // only when RESPONDING was actually up, so a silent Start→Stop does not
  // manufacture a status change.
  function resetStreamingIndicators() {
    const wasResponding = window.responseStarted === true;
    window.responseStarted = false;
    window.streamingResponse = false;
    if (window.UIState) {
      window.UIState.set('streamingResponse', false);
      window.UIState.set('isStreaming', false);
    }
    if (wasResponding && typeof setAlert === 'function') {
      const readyText = t('ui.messages.readyForInput', 'Ready for input');
      setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, 'success');
    }
  }

  // ── Inbound message hooks (wired from websocket.js) ────────────────
  function onSttPartial(data) {
    if (!lcMode || !active) return;
    noteActivity();
    if (liveViewWanted()) {
      // Empty carries no bubble: the server sends blank stt when it
      // suppresses a hallucinated transcript, and a blank must neither
      // promote the assistant zone nor draw an empty You bubble.
      const text = (data && data.content) || '';
      if (text.trim() !== '') liveSet('user', text, false);
      return;
    }
    const el = ensureUserTemp();
    if (!el) return;
    const textEl = el.querySelector('.lc-user-temp-text');
    if (textEl) textEl.textContent = (data && data.content) || '';
    scrollLatestIntoView();
  }

  function onStt(data) {
    if (!lcMode) return;
    if (liveViewWanted()) {
      // Same empty-guard as onSttPartial (hallucination-suppressed blank).
      const text = (data && data.content) || '';
      if (text.trim() !== '') liveSet('user', text, true);
      return;
    }
    // The finalized user card arrives from the server as html; the live
    // preview has served its purpose.
    removeUserTemp();
    if (active) setStatus(t('ui.messages.lcListening', 'Listening…'));
  }

  function onStsVad(data) {
    if (!lcMode || !active) return;
    noteActivity();
    if (data.event === 'speech_started') {
      setStatus(t('ui.messages.lcUserSpeaking', 'You are speaking…'));
    } else if (data.event === 'speech_stopped' && !assistantTalking) {
      setStatus(t('ui.messages.lcListening', 'Listening…'));
    }
  }

  function onStsSession(data) {
    if (!lcMode) return;
    switch (data.state) {
      case 'started':
        if (active) setStatus(t('ui.messages.lcListening', 'Listening…'));
        break;
      case 'reconnecting':
        if (active) setStatus(t('ui.messages.lcReconnecting', 'Reconnecting…'));
        break;
      case 'stopped':
        // Server-side stop (error give-up, teardown). Mirror locally so the
        // mic is not left streaming into a dead bridge.
        if (active) stopConversation();
        // Stop-time consolidation folded VAD-split fragments into
        // alternating turns — re-render the discourse from the canon.
        // Exception: an edit already in progress must not be wiped by the
        // re-render (the canon is merged either way; the next reload shows
        // the folded form).
        if (data.merged && !document.querySelector('.inline-edit-textarea')) {
          const uiLanguage = document.cookie.match(/ui-language=([^;]+)/)?.[1] || 'en';
          window.safeWsSend({ message: 'LOAD', ui_language: uiLanguage });
        }
        break;
      default:
        break;
    }
  }

  // ── Ordering + auto-scroll invariant ───────────────────────────────
  // Called by appendCard whenever a finalized card lands while in LC mode.
  // Invariant: streaming surfaces stay below every finalized card — the
  // assistant temp-card (current response) and, below it, the live user
  // transcript (an interrupting utterance is always newer than the
  // response it interrupts).
  function onCardAppended() {
    const discourse = $id('discourse');
    if (!discourse) return;
    const temp = $id('temp-card');
    if (temp && temp.parentElement === discourse && temp.style.display !== 'none') {
      discourse.appendChild(temp);
    }
    if (userTempEl && userTempEl.parentElement === discourse) {
      discourse.appendChild(userTempEl);
    }
    scrollLatestIntoView();
  }

  // The typed pipeline's auto-scroll anchors on #chat-bottom INSIDE the
  // streaming temp-card, so card-only updates (most of LC's traffic: user
  // cards, finalized assistant cards, merges) never scrolled — the newest
  // card drifted out of view. Anchor on the last discourse element instead,
  // honoring the same auto-scroll toggle.
  function scrollLatestIntoView() {
    if (window.autoScroll === false) return;
    const discourse = $id('discourse');
    const last = discourse && discourse.lastElementChild;
    if (!last) return;
    if (typeof isElementInViewport === 'function' && isElementInViewport(last)) return;
    if (typeof last.scrollIntoView === 'function') last.scrollIntoView(false);
  }

  // In-place card text refresh: a barge-in freezes the interrupted card at
  // the transcript received so far, but the late transcript.done carries
  // the fuller text of what was actually generated (audio deltas run ahead
  // of transcript deltas). Position is preserved — re-sending html would
  // move the card to the bottom.
  function onCardText(data) {
    // Only the STS bridge emits this type; outside LC mode it is noise.
    if (!lcMode) return;
    if (!data || !data.mid) return;
    const text = String(data.content || '');
    const card = $id(data.mid);
    if (!card) return;
    const body = card.querySelector('.card-text');
    if (!body) return;
    const hasTools = Array.isArray(data.tools_used) && data.tools_used.length > 0;
    const grows = text.length > body.textContent.trim().length;
    // Mirror the server's grow-only rule as a client-side belt — for the
    // TEXT only. A badge-carrying update is processed even without growth
    // (§39: a suppressed unspoken continuation can arrive as tools_used
    // alone, and the badge must still render).
    if (!grows && !hasTools) return;
    if (grows) {
      // Paragraph split (§37-3): folded text joins utterances with "\n\n" —
      // render each as its own paragraph so position-aware tool badges can
      // sit at the boundary. textContent is inherently injection-safe.
      const paraEls = text.split('\n\n').map(function(para) {
        const p = document.createElement('p');
        p.textContent = para;
        return p;
      });
      body.replaceChildren.apply(body, paraEls);
      // Mirror into the live view's assistant zone (interrupted card refresh).
      if (livePrev.role === 'assistant') { livePrev.text = text; }
      if (liveCurrent.role === 'assistant') {
        liveCurrent.text = text;
        // Positioned tool entries from the fold double as the live zone's
        // badges (§37-5) — keeps the live view correct even when onToolCall
        // anchoring missed (e.g. live view toggled on mid-exchange).
        if (Array.isArray(data.tools_used)) {
          liveCurrent.badges = data.tools_used.filter(function(tool) {
            return tool && typeof tool.at === 'number';
          });
        }
      }
      if (liveViewWanted()) renderLiveView();
    } else if (hasTools) {
      // No text growth, but the badge set may have changed (§39 suppress
      // path) — keep the live zone's badges in sync too.
      if (liveCurrent.role === 'assistant') {
        liveCurrent.badges = data.tools_used.filter(function(tool) {
          return tool && typeof tool.at === 'number';
        });
        if (liveViewWanted()) renderLiveView();
      }
    }

    // Tools used this turn (§37-2/§37-4): positioned entries (`at`) render
    // as inline badges at the paragraph boundary via insertInlineToolBadge;
    // entries WITHOUT a position (older canon) fall back to a single header
    // badge — exclusive per entry, so no tool shows twice or vanishes.
    if (hasTools) {
      const unpositioned = data.tools_used.filter((t) => !t || typeof t.at !== 'number');
      if (unpositioned.length > 0) {
        const title = card.querySelector('.card-title');
        if (title && !title.querySelector('.lc-tools-badge')) {
          const names = [...new Set(unpositioned.map((t) => t.name))];
          const hasError = unpositioned.some((t) => t.status === 'error');
          const span = document.createElement('span');
          span.className = 'mc-badge ' + (hasError ? 'mc-badge--red' : 'mc-badge--grey') +
            ' ms-1 align-middle lc-tools-badge';
          span.innerHTML = "<i class='fas fa-tools'></i> ";
          span.appendChild(document.createTextNode(names.join(', ')));
          title.appendChild(span);
        }
      }
      // §37-3: entries with `at` get an inline badge at the paragraph
      // boundary where the tool ran (display layer only; canon stays plain).
      // Clear the previous inline badges first: the server re-sends the
      // UNION of tools_used on every fold, and only the growth path rebuilds
      // the body — a badge-only update (§39 suppressed continuation) would
      // otherwise append the same badge again on each arrival.
      if (typeof window.insertInlineToolBadge === 'function') {
        body.querySelectorAll(':scope > .lc-tools-badge').forEach(function(el) { el.remove(); });
        window.insertInlineToolBadge(card, data.tools_used);
      }
    }

    // Duplicate suppression: the temp-card accumulates the same
    // continuation fragments that were just folded into this card — when
    // its content is contained in the folded text, it must not linger as
    // a second, identical card (dogfood: two identical cards after Stop).
    const temp = $id('temp-card');
    if (temp) {
      const tempBody = temp.querySelector('.card-text');
      const tempText = ((tempBody ? tempBody.textContent : temp.textContent) || '').trim();
      if (tempText && text.includes(tempText)) temp.remove();
    }
  }

  // Assistant streaming hook (called from websocket.js on each fragment).
  // is_first marks the first fragment of a response so accumulation restarts
  // — except the first fragment of a tool's ANSWER, which liveAppend folds
  // into the same zone as a new paragraph (see liveAppend).
  function onAssistantFragment(data) {
    if (!liveViewWanted()) return;
    liveAppend('assistant', (data && data.content) || '', !!(data && data.is_first),
               data && data.segment_id);
  }

  // ── Speech highlight (§37-13C) ──────────────────────────────────────
  // Driven ONLY by the playback clock (WsStsPlayback.getPlaybackPosition) —
  // provider timing is never consulted. A SEGMENT is one upstream response
  // (a tool-bridged turn is two: bridge, silence, answer); the silence
  // between segments covers no playback range, so the highlight cannot
  // advance through it. Within a segment the position maps linearly onto
  // the segment's characters and the sentence containing that character is
  // marked. Live view only; card view never highlights.
  let highlightTimer = null;

  function startHighlightWatch() {
    stopHighlightWatch();
    highlightTimer = setInterval(tickHighlight, 250);
  }

  function stopHighlightWatch() {
    if (highlightTimer) { clearInterval(highlightTimer); highlightTimer = null; }
  }

  // Split `text` into sentence ranges [start, end). Delimiters follow the
  // transcript conventions of all three providers; a paragraph break also
  // ends a sentence (so a sentence never spans paragraphs).
  function sentenceRanges(text) {
    const ranges = [];
    const re = /[^。！？!?\n]+[。！？!?]?|[^\n]/g;
    let m;
    while ((m = re.exec(text)) !== null) {
      if (m[0].length > 0 && m[0].trim().length > 0) ranges.push([m.index, m.index + m[0].length]);
    }
    if (ranges.length === 0 && text.length > 0) ranges.push([0, text.length]);
    return ranges;
  }

  // Map a playback position onto a character offset in the current zone.
  function highlightCharFor(pos) {
    if (!pos || liveCurrent.role !== 'assistant') return null;
    const text = liveCurrent.text;
    if (!text) return null;
    let segIndex = -1;
    for (let i = liveSegments.length - 1; i >= 0; i--) {
      if (liveSegments[i].id === pos.segmentId) { segIndex = i; break; }
    }
    if (segIndex < 0) return null; // audio for text we have not seen — freeze
    const start = liveSegments[segIndex].startChar;
    const end = segIndex + 1 < liveSegments.length
      ? liveSegments[segIndex + 1].startChar : text.length;
    const span = Math.max(end - start, 1);
    const fraction = pos.total > 0 ? Math.min(Math.max(pos.offset / pos.total, 0), 1) : 0;
    return Math.min(start + Math.floor(fraction * span), end - 1);
  }

  function tickHighlight() {
    if (!liveViewWanted() || liveCurrent.role !== 'assistant') return;
    const pb = window.WsStsPlayback;
    if (!pb || typeof pb.getPlaybackPosition !== 'function') return;
    const pos = pb.getPlaybackPosition();
    const char = pos ? highlightCharFor(pos) : null;
    // pos null (silence / barge-in): keep the last position — freeze.
    //
    // Monotonic within a segment: `total` is the audio SCHEDULED so far, and
    // deltas arrive ~3-5x faster than playback (measured), so early in a
    // response the denominator is far too small and the fraction too large.
    // As more audio lands, total grows and a raw fraction would move the
    // highlight BACKWARD — visible as a jump back over text already spoken.
    // Speech only moves forward, so the highlight only moves forward too;
    // the reset points (new response / new zone) clear the floor.
    if (char !== null) {
      const seg = pos && pos.segmentId;
      if (seg !== highlightSegmentId) {
        highlightSegmentId = seg;
        lastHighlightChar = char;
      } else {
        lastHighlightChar = lastHighlightChar === null
          ? char : Math.max(lastHighlightChar, char);
      }
    }
    if (lastHighlightChar === null) return;
    renderLiveView();
  }

  // Wrap the sentence containing `charPos` in a .lc-speaking span during
  // paragraph construction (called from renderZone for the CURRENT zone).
  function appendParagraphWithHighlight(body, para, paraStart, charPos) {
    const ranges = sentenceRanges(para);
    let target = null;
    for (let i = 0; i < ranges.length; i++) {
      const s = paraStart + ranges[i][0];
      const e = paraStart + ranges[i][1];
      if (charPos >= s && charPos < e) { target = [ranges[i][0], ranges[i][1]]; break; }
    }
    const p = document.createElement('p');
    if (!target) {
      p.textContent = para;
    } else {
      p.appendChild(document.createTextNode(para.slice(0, target[0])));
      const span = document.createElement('span');
      span.className = 'lc-speaking';
      span.textContent = para.slice(target[0], target[1]);
      p.appendChild(span);
      p.appendChild(document.createTextNode(para.slice(target[1])));
    }
    body.appendChild(p);
  }

  // Find a tool badge by call_id in either zone (promotion can move it).
  function findToolBadge(callId) {
    if (!callId) return null;
    const zones = [liveCurrent, livePrev];
    for (let i = 0; i < zones.length; i++) {
      const badge = zones[i].badges &&
        zones[i].badges.find(function(b) { return b.call_id === callId; });
      if (badge) return badge;
    }
    return null;
  }

  // Tool-use visibility (§37/§37-12): running → status line + an immediate
  // badge (spinning) at the current paragraph boundary; done/error → update
  // THAT badge (spin off, red on error). The call_id correlates the two —
  // a name alone is ambiguous when one response repeats a tool. The badge's
  // `at` equals the anchor the answer's is_first would compute (the bridge
  // utterance does not grow between the call and the answer), so the
  // anchoring path only flips its status, never adds a second badge.
  // liveToolPending (the fold-continuation decision) is a separate concern
  // and unchanged.
  function onToolCall(data) {
    if (!lcMode || !active) return;
    noteActivity();
    const name = (data && data.name) || '';
    if (!name) return;
    const callId = (data && data.call_id) || '';
    if (data.status === 'running') {
      liveToolPending.push({ name: name, status: 'done', call_id: callId });
      if (callId && !findToolBadge(callId)) {
        // §37-13A: Gemini finalizes the user turn only when the model starts
        // answering, so during the call the current zone is still USER —
        // there is no assistant zone to hold the badge (OpenAI/xAI open one
        // with a bridge utterance). Open an empty assistant zone for the
        // badge alone; the answer continues into this same zone.
        if (liveCurrent.role !== 'assistant') {
          if (liveCurrent.role) livePromote();
          liveCurrent = { role: 'assistant', text: '', badges: [] };
        }
        liveCurrent.badges.push({
          name: name, status: 'running', call_id: callId,
          at: liveCurrent.text.trim() !== '' ? liveCurrent.text.split('\n\n').length : 0
        });
      }
      setStatus(t('ui.messages.lcToolUsing', 'Using {tool}…').replace('{tool}', name));
    } else {
      const newStatus = data.status === 'error' ? 'error' : 'done';
      const entry = (callId && liveToolPending.find(function(p) { return p.call_id === callId; })) ||
        liveToolPending.find(function(p) { return p.name === name; });
      if (entry) entry.status = newStatus;
      // The badge may live in either zone (promotion can have moved it).
      const badge = findToolBadge(callId);
      if (badge) badge.status = newStatus;
    }
    if (liveViewWanted()) renderLiveView();
  }

  function onAssistantAudio() {
    if (!lcMode || !active) return;
    noteActivity();
    assistantTalking = true;
    setStatus(t('ui.messages.lcAssistantSpeaking', 'Assistant is speaking…'));
  }

  function onAssistantAudioEnd() {
    if (!lcMode) return;
    assistantTalking = false;
    if (active) setStatus(t('ui.messages.lcListening', 'Listening…'));
  }

  const ns = {
    setAppMode: setAppMode,
    startConversation: startConversation,
    stopConversation: stopConversation,
    onSttPartial: onSttPartial,
    onStt: onStt,
    onStsVad: onStsVad,
    onStsSession: onStsSession,
    onCardText: onCardText,
    onCardAppended: onCardAppended,
    onAssistantFragment: onAssistantFragment,
    onToolCall: onToolCall,
    refreshControls: renderVoiceControls,
    onAssistantAudio: onAssistantAudio,
    onAssistantAudioEnd: onAssistantAudioEnd,
    isActive: function() { return active; },
    isLcMode: function() { return lcMode; },
    // Test seams
    _setCaptureFactory: function(fn) { captureFactory = fn || defaultCaptureFactory; },
    _reset: function() {
      if (capture) { try { capture.stop(); } catch (_) { /* noop */ } }
      capture = null; active = false; lcMode = false; assistantTalking = false;
      stopIdleWatch();
      stopHighlightWatch();
      removeUserTemp();
      idleStopMs = DEFAULT_IDLE_STOP_MS;
      liveReset();
      applyViewMode(); // restore discourse on teardown paths too
      document.body.classList.remove('lc-app', 'lc-locked');
    },
    // §37-13C test seams
    _tickHighlight: tickHighlight,
    _highlightCharFor: highlightCharFor,
    _liveSegments: function() { return liveSegments; }
  };

  window.LiveConversation = ns;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
