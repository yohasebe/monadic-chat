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
    panel.className = 'py-2';
    panel.innerHTML =
      '<div class="d-flex align-items-center">' +
      '<button id="lc-toggle" class="btn btn-sm btn-lc text-nowrap" type="button">' +
      '<i class="fas fa-tower-broadcast me-2"></i><span id="lc-toggle-label"></span>' +
      '<i id="lc-action-icon" class="fas fa-play ms-2"></i></button>' +
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
    if (!panel || $id('lc-voice-select')) return;
    const row = document.createElement('div');
    row.className = 'd-flex align-items-center mt-2 flex-wrap';
    row.innerHTML =
      '<label for="lc-voice-select" class="text-secondary small me-2" id="lc-voice-label"></label>' +
      '<select id="lc-voice-select" class="form-select form-select-sm" style="max-width: 160px;"></select>' +
      '<span id="lc-voice-note" class="text-secondary small ms-2"></span>' +
      // NO d-flex here: Bootstrap's .d-flex is `display:flex !important`
      // and would beat the inline `display:none` used to hide this wrap on
      // xAI/Gemini (the same trap as the AI User row). Visibility is
      // driven exclusively by renderVoiceControls via setProperty.
      '<span id="lc-speed-wrap" class="text-secondary small align-items-center ms-3" style="display:none !important;">' +
      '<label for="lc-speed-range" class="text-secondary small me-2" id="lc-speed-label"></label>' +
      '<input type="range" id="lc-speed-range" min="0.25" max="1.5" step="0.05" value="1.0" style="width: 90px;">' +
      '<span id="lc-speed-value" class="text-secondary small ms-1">1.0</span>' +
      '</span>' +
      '<span id="lc-websearch-wrap" class="text-secondary small align-items-center ms-3" style="display:none !important;">' +
      '<input type="checkbox" id="lc-websearch-toggle" class="form-check-input me-1">' +
      '<label for="lc-websearch-toggle" class="text-secondary small me-1" id="lc-websearch-label"></label>' +
      '<span id="lc-websearch-note" class="text-secondary small"></span>' +
      '</span>';
    panel.appendChild(row);

    $id('lc-voice-label').textContent = t('ui.messages.lcVoice', 'Voice');
    $id('lc-voice-note').textContent = t('ui.messages.lcVoiceNextStart', '(applies from the next Start)');
    $id('lc-speed-label').textContent = t('ui.messages.lcSpeed', 'Speed');
    $id('lc-websearch-label').textContent = t('ui.messages.lcWebsearch', 'Web search');

    $on($id('lc-voice-select'), 'change', function() {
      if (typeof params !== 'undefined') {
        params['sts_voice'] = $id('lc-voice-select').value;
        if (typeof window.broadcastParamsUpdate === 'function') window.broadcastParamsUpdate('sts_voice_change');
      }
    });
    $on($id('lc-websearch-toggle'), 'change', function() {
      if (typeof params !== 'undefined') {
        params['websearch'] = $id('lc-websearch-toggle').checked;
        if (typeof window.broadcastParamsUpdate === 'function') window.broadcastParamsUpdate('websearch_toggle');
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

    const voices = Array.isArray(spec.sts_voices) ? spec.sts_voices : [];
    const current = (typeof params !== 'undefined' && params['sts_voice']) || spec.sts_voice || voices[0] || '';
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
        wrap.style.setProperty('display', 'flex');
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

    // Native search toggle (xAI/Gemini only — model_spec capability gate,
    // same shape as the speed control). Default OFF (billing); the note is
    // provider-specific honesty about cost.
    const wsWrap = $id('lc-websearch-wrap');
    if (wsWrap) {
      const wsCapable = spec.sts_websearch_capability === true;
      if (wsCapable) {
        wsWrap.style.removeProperty('display');
        wsWrap.style.setProperty('display', 'flex');
        const provider = spec.sts_provider;
        $id('lc-websearch-note').textContent = provider === 'gemini'
          ? t('ui.messages.lcWebsearchCostGemini', '(free monthly quota, then paid)')
          : t('ui.messages.lcWebsearchCostXai', '(may incur additional charges)');
        $id('lc-websearch-toggle').checked =
          typeof params !== 'undefined' &&
          (params['websearch'] === true || params['websearch'] === 'true');
      } else {
        wsWrap.style.setProperty('display', 'none', 'important');
      }
    }
  }

  function renderControls() {
    const label = $id('lc-toggle-label');
    const btn = $id('lc-toggle');
    if (!label || !btn) return;
    // Leading icon = app identity (broadcast tower, constant); trailing
    // icon = the ACTION this press performs (play/stop), after the label.
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
  function setAppMode(appConfig) {
    const on = !!(appConfig && (appConfig.speech_to_speech === true || appConfig.speech_to_speech === 'true'));
    if (lcMode && !on && active) stopConversation();
    lcMode = on;
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
      ensureIntroCard();
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
  }

  // ── Intro card ─────────────────────────────────────────────────────
  // Client-only usage note shown while the conversation is still empty:
  // this app needs an EXPLICIT Start (and Stop) press, unlike the typed
  // apps where the input box invites action by itself. Never part of the
  // canon — removed the moment the conversation begins.
  function ensureIntroCard() {
    if (!lcMode) return;
    if ($id('lc-intro')) return;
    if ((window.messages || []).length > 0) return;
    const discourse = $id('discourse');
    if (!discourse || discourse.querySelector('.card')) return;
    const el = document.createElement('div');
    el.id = 'lc-intro';
    el.className = 'card mt-3 lc-intro-card';
    const body = document.createElement('div');
    body.className = 'card-body text-secondary';
    const p = document.createElement('p');
    p.className = 'mb-0';
    p.textContent = t('ui.messages.lcIntro',
      'Press "Start live conversation" to begin. Speaking then continues hands-free — ' +
      'turns are detected automatically. Press "End live conversation" to finish. ' +
      'Headphones are recommended.');
    body.appendChild(p);
    el.appendChild(body);
    discourse.appendChild(el);
  }

  function removeIntroCard() {
    const el = $id('lc-intro');
    if (el) { try { el.remove(); } catch (_) { /* noop */ } }
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

    removeIntroCard();
    startIdleWatch();
    window.safeWsSend({ message: 'STS_START', chat_model: chatModel, greet: greet });
  }

  function stopConversation() {
    if (!active) return;
    active = false;
    stopIdleWatch();
    try { window.safeWsSend({ message: 'STS_STOP' }); } catch (_) { /* socket may be gone */ }
    if (capture) { try { capture.stop(); } catch (_) { /* noop */ } capture = null; }
    const sts = window.WsStsPlayback;
    if (sts && typeof sts.stopAll === 'function') sts.stopAll();
    removeUserTemp();
    assistantTalking = false;
    renderControls();
    setStatus('');
    lockCards(false);
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

  // ── Inbound message hooks (wired from websocket.js) ────────────────
  function onSttPartial(data) {
    if (!lcMode || !active) return;
    noteActivity();
    const el = ensureUserTemp();
    if (!el) return;
    const textEl = el.querySelector('.lc-user-temp-text');
    if (textEl) textEl.textContent = (data && data.content) || '';
    scrollLatestIntoView();
  }

  function onStt(_data) {
    if (!lcMode) return;
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
    // Mirror the server's grow-only rule as a client-side belt.
    if (text.length <= body.textContent.trim().length) return;
    // textContent is inherently injection-safe — no escaping dependency.
    const p = document.createElement('p');
    p.textContent = text;
    body.replaceChildren(p);
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
      removeUserTemp();
      removeIntroCard();
      idleStopMs = DEFAULT_IDLE_STOP_MS;
      document.body.classList.remove('lc-app', 'lc-locked');
    }
  };

  window.LiveConversation = ns;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
