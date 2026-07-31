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

  const REALTIME_RATE = 24000;

  let lcMode = false;        // current app is a speech-to-speech app
  let active = false;        // a conversation is running (Start pressed)
  let capture = null;        // { stream, audioCtx, workletNode, source, silentGain }
  let userTempEl = null;     // live user-transcript card
  let assistantTalking = false;

  // Test seam: capture is hardware-bound (getUserMedia + AudioWorklet), so
  // tests replace the factory rather than faking half the Web Audio API.
  let captureFactory = defaultCaptureFactory;

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

    const panel = document.createElement('div');
    panel.id = 'lc-panel';
    panel.className = 'text-center py-2';
    panel.innerHTML =
      '<button id="lc-toggle" class="btn btn-primary btn-lg px-4" type="button">' +
      '<i class="fas fa-play me-2"></i><span id="lc-toggle-label"></span></button>' +
      '<div id="lc-status" class="text-secondary small mt-2"></div>';
    userPanel.prepend(panel);

    $on($id('lc-toggle'), 'click', function() {
      if (active) { stopConversation(); } else { startConversation(); }
    });
    renderControls();
  }

  function renderControls() {
    const label = $id('lc-toggle-label');
    const btn = $id('lc-toggle');
    if (!label || !btn) return;
    if (active) {
      label.textContent = t('ui.messages.lcStop', 'Stop');
      btn.classList.remove('btn-primary');
      btn.classList.add('btn-danger');
      btn.querySelector('i').className = 'fas fa-stop me-2';
    } else {
      label.textContent = t('ui.messages.lcStart', 'Start');
      btn.classList.remove('btn-danger');
      btn.classList.add('btn-primary');
      btn.querySelector('i').className = 'fas fa-play me-2';
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
    document.body.classList.toggle('lc-app', on);
    if (on) ensurePanel();
  }

  // ── Capture ────────────────────────────────────────────────────────
  async function defaultCaptureFactory(onChunk) {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
    });
    const AudioCtor = window.AudioContext || window.webkitAudioContext;
    const audioCtx = new AudioCtor();
    await audioCtx.audioWorklet.addModule('/js/monadic/audio-pcm-encoder-worklet.js');
    const source = audioCtx.createMediaStreamSource(stream);
    const workletNode = new AudioWorkletNode(audioCtx, 'pcm-encoder', {
      processorOptions: { targetRate: REALTIME_RATE, frameMs: 100 }
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

    // Greeting only opens a FRESH conversation; resume seeds silently.
    // The initiate-from-assistant checkbox keeps its ordinary meaning.
    const initiateEl = $id('initiate-from-assistant');
    const msgs = (window.messages || []);
    const greet = !!(initiateEl && initiateEl.checked) && msgs.length === 0;

    active = true;
    renderControls();
    setStatus(t('ui.messages.lcConnecting', 'Connecting…'));
    lockCards(true);

    try {
      capture = await captureFactory(function(buf) {
        window.safeWsSend({
          message: 'AUDIO_CHUNK',
          content: bufToBase64(buf),
          chat_model: chatModel
        });
      });
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

    window.safeWsSend({ message: 'STS_START', chat_model: chatModel, greet: greet });
  }

  function stopConversation() {
    if (!active) return;
    active = false;
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
    const el = ensureUserTemp();
    if (!el) return;
    const textEl = el.querySelector('.lc-user-temp-text');
    if (textEl) textEl.textContent = (data && data.content) || '';
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
        break;
      default:
        break;
    }
  }

  function onAssistantAudio() {
    if (!lcMode || !active) return;
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
    onAssistantAudio: onAssistantAudio,
    onAssistantAudioEnd: onAssistantAudioEnd,
    isActive: function() { return active; },
    isLcMode: function() { return lcMode; },
    // Test seams
    _setCaptureFactory: function(fn) { captureFactory = fn || defaultCaptureFactory; },
    _reset: function() {
      if (capture) { try { capture.stop(); } catch (_) { /* noop */ } }
      capture = null; active = false; lcMode = false; assistantTalking = false;
      removeUserTemp();
      document.body.classList.remove('lc-app', 'lc-locked');
    }
  };

  window.LiveConversation = ns;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
