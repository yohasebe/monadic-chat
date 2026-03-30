/////////////////////////////
// set up the websocket
//////////////////////////////

// CRITICAL: Initialize window.apps if not already defined (by utilities.js)
// WebSocket handlers need to write to the global apps object
// Don't create a local variable - always use window.apps directly
if (typeof window.apps === 'undefined') {
  window.apps = {};
}
// Create a reference to window.apps for backward compatibility
// This ensures any writes to 'apps' actually modify window.apps
const apps = window.apps;

// Respect a cookie that suppresses noisy reconnects after intentional stop
try {
  if (document.cookie && document.cookie.includes('silent_reconnect=true')) {
    window.silentReconnectMode = true;
  }
} catch (_) { console.warn("[WebSocket] Silent reconnect cookie check failed:", _); }

// Note: WebSocket connection will be established after ensureMonadicTabId() is defined
// See bottom of this file for actual connection initialization
let ws;  // Will be set after tab ID is ready
// Shared mutable state - accessible via window for ws-visibility-handler.js
if (typeof window._wsIsConnecting === 'undefined') window._wsIsConnecting = false;
if (typeof window._wsReconnectionTimer === 'undefined') window._wsReconnectionTimer = null;

// Properly close WebSocket connection before creating new one
// This prevents connection accumulation after sleep/wake cycles
function closeCurrentWebSocket() {
  if (ws) {
    try {
      // Remove event handlers to prevent callbacks on old connection
      ws.onopen = null;
      ws.onclose = null;
      ws.onerror = null;
      ws.onmessage = null;

      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
        ws.close(1000, 'Creating new connection');
      }
    } catch (e) {
      console.warn('[WebSocket] Error closing old connection:', e);
    }
    ws = null;
  }
}
window.initialLoadComplete = false; // Flag to track initial load
if (typeof window.skipAssistantInitiation === 'undefined') {
  window.skipAssistantInitiation = false;
}
if (typeof window.isProcessingImport === 'undefined') {
  window.isProcessingImport = false;
}

// Lightweight timeline logger to trace initialization order
// Entries are stored in window._timeline for debugging (access via console)
// Capped at 200 entries to prevent unbounded memory growth in long sessions
if (!window.logTL) {
  const MAX_TIMELINE = window._timelineMaxSize || 200;
  window.logTL = function(event, payload) {
    try {
      const ts = new Date().toISOString();
      const entry = Object.assign({ ts, event }, payload || {});
      window._timeline = window._timeline || [];
      window._timeline.push(entry);
      if (window._timeline.length > MAX_TIMELINE) {
        window._timeline = window._timeline.slice(-MAX_TIMELINE);
      }
    } catch (_) { console.warn("[WebSocket] Timeline logging failed:", _); }
  };
}

// OpenAI API token verification
window.verified = null;

const { getMessageAppName, getMessageMonadicFlag, renderMessage } = window.WsContentRenderer || {};
const { registerAudioElement, stopAllActiveAudio } = window.WsAudioPlayback || {};

if (typeof window.suppressParamBroadcastCount === 'undefined') {
  window.suppressParamBroadcastCount = 0;
}


// Auto-speech suppression, TTS toast, foreground detection now in ws-auto-speech.js
const { setAutoSpeechSuppressed, isAutoSpeechSuppressed, isForegroundTab,
        resetAutoSpeechSpinner, showTtsNotice, hideTtsToast,
        ensureThinkingSpinnerVisible, scheduleAutoTtsSpinnerTimeout
      } = window.WsAutoSpeech || {};

// Constants from ws-audio-constants.js
const AUDIO_QUEUE_DELAY = (window.WsAudioConstants || {}).AUDIO_QUEUE_DELAY || 20;
const AUDIO_ERROR_DELAY = (window.WsAudioConstants || {}).AUDIO_ERROR_DELAY || 50;

// WebSocket timing constants - from ws-audio-constants.js
const PING_INTERVAL_MS = (window.WsAudioConstants || {}).PING_INTERVAL_MS || 30000;
const TOKEN_VERIFY_TIMEOUT_MS = (window.WsAudioConstants || {}).TOKEN_VERIFY_TIMEOUT_MS || 30000;
const VERIFY_CHECK_INTERVAL_MS = (window.WsAudioConstants || {}).VERIFY_CHECK_INTERVAL_MS || 1000;
const RESPONSE_TIMEOUT_MS = (window.WsAudioConstants || {}).RESPONSE_TIMEOUT_MS || 30000;
const RESPONSE_TIMEOUT_SLOW_MS = (window.WsAudioConstants || {}).RESPONSE_TIMEOUT_SLOW_MS || 60000;
// BUSY_CHECK_INTERVAL_MS, BUSY_CHECK_MAX_WAIT_MS now in ws-streaming-handler.js

// Stop-button highlighting, checkAndHideSpinner now in ws-auto-speech.js
const { highlightStopButton, removeStopButtonHighlight, checkAndHideSpinner } = window.WsAutoSpeech || {};

// message is submitted upon pressing enter
const message = document.getElementById("message");

message.addEventListener("compositionstart", function () {
  message.dataset.ime = "true";
});

message.addEventListener("compositionend", function () {
  message.dataset.ime = "false";
});

document.addEventListener("keydown", function (event) {
  // Right Arrow key - activate voice input when Easy Submit is enabled
  const easySubmitEl = document.getElementById("check-easy-submit");
  const messageEl = document.getElementById("message");
  const easySubmitChecked = easySubmitEl && easySubmitEl.checked;
  const messageHasFocus = document.activeElement === messageEl;

  if (easySubmitChecked && !messageHasFocus && event.key === "ArrowRight") {
    event.preventDefault();
    // Only activate voice button if session has begun (main panel is visible)
    const voiceEl = document.getElementById("voice");
    const mainPanelEl = document.getElementById("main-panel");
    if (voiceEl && !voiceEl.disabled && mainPanelEl && mainPanelEl.style.display !== "none") {
      voiceEl.click();
    }
  }

  // Enter key - submit message when focus is not in textarea
  if (easySubmitChecked && !messageHasFocus && event.key === "Enter" && message.dataset.ime !== "true") {
    // Only submit if message is not empty
    if (message.value.trim() !== "") {
      event.preventDefault();
      if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
        // Ignore auto-submit when tab is not in foreground
      } else {
        const sendEl = document.getElementById("send");
        if (sendEl) sendEl.click();
      }
    }
  }
});

const setCopyCodeButton = window.setCopyCodeButton;

//////////////////////////////
// WebSocket event handlers
//////////////////////////////

// In browser environments, wsHandlers is defined globally in websocket-handlers.js
let wsHandlers = window.wsHandlers;

let reconnectDelay = (window.WsAudioConstants || {}).baseReconnectDelay || 1000;

let pingInterval;

function startPing() {
  // Clear any existing ping interval to avoid duplicates
  stopPing();

  // Start new ping interval
  pingInterval = setInterval(() => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ message: 'PING' }));
    } else {
      // If the websocket is no longer open, stop pinging
      stopPing();
    }
  }, PING_INTERVAL_MS);
}

function stopPing() {
  if (pingInterval) {
    clearInterval(pingInterval);
    pingInterval = null; // Properly null out the reference
  }
}

window.chatBottom = document.getElementById("chat-bottom");
window.autoScroll = true;

const mainPanel = document.getElementById("main-panel");
window.mainPanel = mainPanel;

function ensureMonadicTabId() {
  try {
    if (typeof sessionStorage !== 'undefined') {
      let tabId = sessionStorage.getItem('monadicTabId');
      if (!tabId) {
        tabId = (typeof crypto !== 'undefined' && crypto.randomUUID) ?
          crypto.randomUUID() :
          `tab-${Date.now()}-${Math.random().toString(36).slice(2)}`;
        sessionStorage.setItem('monadicTabId', tabId);
      }
      window.monadicTabId = tabId;
      return tabId;
    }
  } catch (e) {
    console.warn('[Session] Unable to access sessionStorage for tab ID:', e);
  }
  if (!window.monadicTabId) {
    window.monadicTabId = `tab-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
  return window.monadicTabId;
}

window.getMonadicTabId = ensureMonadicTabId;
const MONADIC_TAB_ID = ensureMonadicTabId();

// handleFragmentMessage, debugFragmentSummary, resetFragmentDebug
// — extracted to ws-fragment-handler.js (window.WsFragmentHandler)

// Make defaultApp globally available
window.defaultApp = DEFAULT_APP;

// isElementInViewport now in ws-content-renderer.js
const isElementInViewport = window.isElementInViewport;

// applyMathJax (now KaTeX-based), mermaid_config, sanitizeMermaidSource, applyMermaid now in ws-content-renderer.js
const applyMathJax = window.applyMathJax;
const applyMermaid = window.applyMermaid;
const applyDrawIO = window.applyDrawIO;

// ABC notation, toggle, and source-code helpers now in ws-content-renderer.js
const applyToggle = window.applyToggle;
const addToggleSourceCode = window.addToggleSourceCode;
const formatSourceCode = window.formatSourceCode;
const cleanupListCodeBlocks = window.cleanupListCodeBlocks;
const applyAbc = window.applyAbc;

// Browser/feature detection and audio constants now in ws-audio-constants.js
const { isIOS, isIPad, isMobileIOS, isChrome, isSafari, isFirefox,
        hasMediaSourceSupport, hasAudioContextSupport,
        maxReconnectAttempts, baseReconnectDelay
      } = window.WsAudioConstants || {};

// audioContext, mediaSource, audio, sourceBuffer, audioDataQueue now in ws-audio-playback.js
// Local mutable aliases needed because connect_websocket reassigns these
let mediaSource = null;
let audio = null;
let sourceBuffer = null;
let audioDataQueue = [];
let mediaSourceOpenHandler = null;
let sourceBufferUpdateEndHandler = null;
let audioCanPlayHandler = null;
let processAudioDataQueue = function() {};
let audioContext = null;


// addToGlobalAudioQueue now in ws-audio-queue.js


// initializeMediaSourceForAudio, resetAudioElements, resetSessionState,
// playAudioDirectly, playWithAudioElement, parseSequenceNumber,
// addToAudioQueue, processSequentialAudio, processGlobalAudioQueue,
// clearAudioQueue, playAudioFromQueue, playAudioForIOSFromQueue,
// processIOSAudioBufferWithQueue, playAudioForIOS, processIOSAudioBuffer,
// playPCMAudio, createWAVFromPCM, processAudioDataQueue, processAudio
// — all extracted to ws-audio-playback.js and ws-audio-queue.js
const initializeMediaSourceForAudio = window.initializeMediaSourceForAudio;
const resetAudioElements = window.resetAudioElements;
const playAudioDirectly = window.playAudioDirectly;
const playWithAudioElement = window.playWithAudioElement;
const playAudioForIOS = window.playAudioForIOS;
const processIOSAudioBuffer = window.processIOSAudioBuffer;
const processAudio = window.processAudio;
// Queue functions from ws-audio-queue.js
const clearAudioQueue = window.clearAudioQueue;
const addToAudioQueue = window.addToAudioQueue;
const resetSessionState = window.resetSessionState;


window.responseStarted = false;
window.callingFunction = false;
// Track if we're currently streaming a response
window.streamingResponse = false;
// Track whether reasoning/thinking fragments are currently streaming
let reasoningStreamActive = false;
// Track tool execution progress across the full tool chain
window.toolCallCount = 0;
window.currentToolName = '';
// Track spinner check interval to prevent duplicates
window.spinnerCheckInterval = null;

// isSystemBusy, ensureThinkingSpinnerVisible, scheduleAutoTtsSpinnerTimeout now in ws-auto-speech.js
const { isSystemBusy } = window.WsAutoSpeech || {};
window.setReasoningStreamActive = function(value) {
  reasoningStreamActive = !!value;
};
window.isReasoningStreamActive = function() {
  return reasoningStreamActive;
};

// ── Tool execution progress helpers ──────────────────────────

function formatToolName(name) {
  if (!name) return '';
  return name.replace(/_/g, ' ').replace(/\b\w/g, function(c) { return c.toUpperCase(); });
}

function updateToolStatus(toolName, count) {
  const tempCard = document.getElementById("temp-card");
  if (!tempCard) return;

  let toolStatus = document.getElementById("tool-status");
  if (!toolStatus) {
    // Dynamically inject into the card header's right-side area
    const headerEl = tempCard.querySelector(".card-header");
    const flexAreas = headerEl ? headerEl.querySelectorAll(".d-flex.align-items-center") : [];
    let rightArea = flexAreas.length > 0 ? flexAreas[flexAreas.length - 1] : null;
    if (!rightArea || rightArea.classList.contains("card-title")) {
      rightArea = document.createElement("div");
      rightArea.className = "me-1 text-secondary d-flex align-items-center";
      if (headerEl) headerEl.appendChild(rightArea);
    }
    toolStatus = document.createElement("span");
    toolStatus.id = "tool-status";
    toolStatus.className = "tool-status-label me-2";
    const indicator = rightArea.querySelector("#indicator");
    if (indicator) {
      rightArea.insertBefore(toolStatus, indicator);
    } else {
      rightArea.insertBefore(toolStatus, rightArea.firstChild);
    }
  }

  if (toolName && count > 0) {
    toolStatus.innerHTML =
      '<i class="fas fa-cog fa-spin me-1"></i>' + formatToolName(toolName) + ' <span class="tool-call-count">(' + count + ')</span>';
    toolStatus.style.display = '';
  } else {
    toolStatus.style.display = 'none';
  }
}

function clearToolStatus() {
  window.toolCallCount = 0;
  window.currentToolName = '';
  const toolStatusEl = document.getElementById("tool-status");
  if (toolStatusEl) {
    toolStatusEl.style.display = 'none';
    toolStatusEl.innerHTML = '';
  }
}
window.clearToolStatus = clearToolStatus;

function connect_websocket(callback) {
  // Use current hostname if available, otherwise default to localhost
  let wsUrl = 'ws://localhost:4567';
  // Always use the function to get tab ID, never reference MONADIC_TAB_ID directly
  const tabId = window.getMonadicTabId ? window.getMonadicTabId() : null;

  // If accessing from a non-localhost address, use that instead
  if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
    const host = window.location.hostname;
    const port = window.location.port || '4567';
    wsUrl = `ws://${host}:${port}`;
    if (window.debugWebSocket) console.log(`[WebSocket] Using hostname from browser: ${wsUrl}`);
  }

  if (tabId) {
    const separator = wsUrl.includes('?') ? '&' : '?';
    wsUrl = `${wsUrl}${separator}tab_id=${encodeURIComponent(tabId)}`;
  }

  if (window.debugWebSocket) console.log(`[WebSocket] Connecting to: ${wsUrl}`);
  const ws = new WebSocket(wsUrl);

// Tracks which app was loaded from server parameters/import. Keep empty by default.
// Exposed on window for access from extracted handler modules (ws-app-data-handlers.js)
window.loadedApp = "Chat";

  // Restore session state on page load
  if (window.SessionState) {
    window.SessionState.restore();
    // If we have a saved app, restore it to window.lastApp
    if (window.SessionState.app && window.SessionState.app.current) {
      window.lastApp = window.SessionState.app.current;
      if (window.debugWebSocket) console.log('[Session Restore] Restored lastApp from SessionState:', window.lastApp);
    }
  }

  ws.onopen = function () {
    if (window.debugWebSocket) console.log(`[WebSocket] Connection established successfully to ${wsUrl}`);
    // Update state if available
    if (window.UIState) {
      window.UIState.set('wsConnected', true);
      window.UIState.set('wsReconnecting', false);
    }
    const verifyingText = typeof webUIi18n !== 'undefined' ?
      webUIi18n.t('ui.messages.verifyingToken') : 'Verifying token';
    setAlert(`<i class='fa-solid fa-bolt'></i> ${verifyingText}`, "warning");
    if (!isForegroundTab()) {
      const spinnerEl = document.getElementById('monadic-spinner');
      if (spinnerEl) spinnerEl.style.display = 'none';
    }
    // Get UI language from cookie or default to 'en'
    const uiLanguage = document.cookie.match(/ui-language=([^;]+)/)?.[1] || 'en';
    ws.send(JSON.stringify({
      message: "CHECK_TOKEN",
      initial: true,
      contents: (document.getElementById("token") || {}).value || '',
      ui_language: uiLanguage
    }));

    // Detect browser/device capabilities for audio handling
    const runningOnFirefox = navigator.userAgent.indexOf('Firefox') !== -1;

    if (window.debugWebSocket) console.log(`[Device Detection] Details - hasMediaSourceSupport: ${hasMediaSourceSupport}, isIOS: ${isIOS}, isIPad: ${isIPad}, isMobileIOS: ${isMobileIOS}, Firefox: ${runningOnFirefox}`);

    // Setup media handling based on browser capabilities
    if (hasMediaSourceSupport && !isMobileIOS) {
      // Full MediaSource support available (desktop browsers, iPad)
      if (!mediaSource) {

        try {
          // CRITICAL: Clean up existing handlers before creating new MediaSource
          // This prevents listener accumulation (same pattern as WebSocket fix)
          if (mediaSource && mediaSourceOpenHandler) {
            try {
              mediaSource.removeEventListener('sourceopen', mediaSourceOpenHandler);
            } catch (e) {
              // Ignore errors during cleanup
            }
          }
          if (sourceBuffer && sourceBufferUpdateEndHandler) {
            try {
              sourceBuffer.removeEventListener('updateend', sourceBufferUpdateEndHandler);
            } catch (e) {
              // Ignore errors during cleanup
            }
          }

          mediaSource = new MediaSource();
          window.mediaSource = mediaSource; // Sync to window for ws-audio-handler.js

          // Create named handler for sourceopen (stored for later removal)
          mediaSourceOpenHandler = function() {
            try {
              // Check if mediaSource is still valid and in correct state
              if (!mediaSource || mediaSource.readyState !== 'open') {
                // This is expected during sourceopen event - MediaSource transitions to 'open'
                // No warning needed as this is normal behavior
                if (mediaSource && mediaSource.readyState === 'closed') {
                  // MediaSource was closed, fall back to basic mode
                  window.basicAudioMode = true;
                  return;
                }
                // Otherwise, continue - sourceopen event means it's transitioning to open
              }

              if (runningOnFirefox) {
                // Firefox needs special handling
                window.firefoxAudioMode = true;
                window.firefoxAudioQueue = [];

                processAudioDataQueue = function() {
                  if (window.firefoxAudioQueue && window.firefoxAudioQueue.length > 0) {
                    const audioData = window.firefoxAudioQueue.shift();
                    try {
                      const blob = new Blob([audioData], { type: 'audio/mpeg' });
                      const url = URL.createObjectURL(blob);

                      const tempAudio = new Audio(url);
                      registerAudioElement(tempAudio); // Track for stop button
                      tempAudio.onended = function() {
                        URL.revokeObjectURL(url);
                        if (window.firefoxAudioQueue.length > 0) {
                          processAudioDataQueue();
                        }
                      };

                      tempAudio.play().catch(e => console.error("Firefox audio playback error:", e));
                    } catch (e) {
                      console.error("Firefox audio processing error:", e);
                    }
                  }
                };
                window.processAudioDataQueue = processAudioDataQueue; // Sync to window
              } else {
                // Chrome and others work well with mpeg
                // Check if mediaSource is valid before using it
                if (!mediaSource) {
                  console.warn("MediaSource is null, falling back to basic audio mode");
                  window.basicAudioMode = true;
                  return;
                }

                sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
                // Store handler reference for proper cleanup
                sourceBufferUpdateEndHandler = processAudioDataQueue;
                sourceBuffer.addEventListener('updateend', sourceBufferUpdateEndHandler);
                window.processAudioDataQueue = processAudioDataQueue; // Sync to window
              }
            } catch (e) {
              console.error("Error setting up MediaSource: ", e);
              // Fallback to basic audio mode if MediaSource setup fails
              window.basicAudioMode = true;
            }
          };

          mediaSource.addEventListener('sourceopen', mediaSourceOpenHandler);
        } catch (e) {
          console.error("Error creating MediaSource: ", e);
          // Fallback to basic audio mode if MediaSource creation fails
          window.basicAudioMode = true;
        }
      }

      if (!audio && mediaSource) {
        try {
          // Reset if switching from Web Speech API mode
          if (window.lastTTSMode === 'web_speech') {
            resetAudioElements();
            // Re-create MediaSource after reset
            if ('MediaSource' in window && !window.basicAudioMode) {
              try {
                mediaSource = new MediaSource();
                window.mediaSource = mediaSource;
              } catch (e) {
                console.error("Error creating MediaSource after reset: ", e);
                window.basicAudioMode = true;
              }
            }
          }

          audio = new Audio();
          registerAudioElement(audio); // Track for stop button
          audio.src = URL.createObjectURL(mediaSource);
          window.audio = audio; // Export to window for global access
          window.audioDataQueue = audioDataQueue; // Sync queue to window
        } catch (e) {
          console.error("Error creating audio element: ", e);
          // Fallback to basic audio mode

          window.basicAudioMode = true;
        }
      }
    } else {
      // No MediaSource support (iOS Safari) - use basic audio mode

      window.basicAudioMode = true;

      // Add a CSS class to body for iOS-specific styling if needed
      if (isIOS) {
        document.body.classList.add("ios-device");
        if (isMobileIOS) {
          document.body.classList.add("mobile-ios-device");
        } else if (isIPad) {
          document.body.classList.add("ipad-device");
        }
      }
    }

    // Note: CHECK_TOKEN is sent in ws.onopen handler (line 2112-2117)
    // No need to send it again here

    // Add timeout for token verification (30 seconds)
    let verificationTimeout = setTimeout(function() {
      if (!window.verified) {
        console.warn('[Token Verification] Timeout after 30 seconds');
        // Set to partial to allow proceeding with limited functionality
        window.verified = "partial";

        // Show timeout error message
        const timeoutText = typeof webUIi18n !== 'undefined' ?
          webUIi18n.t('ui.messages.tokenVerificationTimeout') :
          'Token verification timed out. Proceeding with limited functionality.';
        setAlert(`<i class='fa-solid fa-triangle-exclamation'></i> ${timeoutText}`, "warning");

        clearInterval(verificationCheckTimer);
      }
    }, TOKEN_VERIFY_TIMEOUT_MS);

    // Check verified status at a regular interval
    let verificationCheckTimer = setInterval(function () {
      if (window.verified) {
        if (!window.initialLoadComplete) {  // Only send LOAD on initial connection
          // Get UI language from cookie or default to 'en'
          const uiLanguage = document.cookie.match(/ui-language=([^;]+)/)?.[1] || 'en';
          ws.send(JSON.stringify({ "message": "LOAD", "ui_language": uiLanguage }));
          window.initialLoadComplete = true; // Set the flag after the initial load
        }
        startPing();
        if (callback) {
          callback(ws);
        }
        clearInterval(verificationCheckTimer);
        clearTimeout(verificationTimeout); // Clear timeout when verification succeeds
      }
    }, VERIFY_CHECK_INTERVAL_MS);
  }

  // Helper function to append a card to the discourse
  function appendCard(role, badge, html, lang, mid, status, images, turnNumber = null) {
    const htmlElement = createCard(role, badge, html, lang, mid, status, images, false, turnNumber);
    const discourseEl = document.getElementById("discourse");
    if (discourseEl) discourseEl.appendChild(htmlElement);

    // Defer applyRenderers to ensure DOM is fully ready
    if (window.MarkdownRenderer) {
      setTimeout(() => {
        window.MarkdownRenderer.applyRenderers(htmlElement);
      }, 0);
    }
    updateItemStates();

    // Use toBool helper for defensive boolean evaluation
    const toBool = window.toBool || ((value) => {
      if (typeof value === 'boolean') return value;
      if (typeof value === 'string') return value === 'true';
      return !!value;
    });

    if (toBool(params["toggle"])) {
      applyToggle(htmlElement);
    }

    // Phase 2: Disabled old applyMermaid/MathJax/ABC - now handled by MarkdownRenderer.applyRenderers()
    // if (toBool(params["mermaid"])) {
    //   applyMermaid(htmlElement);
    // }

    // if (toBool(params["mathjax"])) {
    //   applyMathJax(htmlElement);
    // }

    // if (toBool(params["abc"])) {
    //   applyAbc(htmlElement);
    // }

    formatSourceCode(htmlElement);
    cleanupListCodeBlocks(htmlElement);

    setCopyCodeButton(htmlElement);

    // Compact PDF metadata block: group elements after the first <hr> into a .pdf-meta wrapper
    try {
      const cardText = htmlElement.querySelector('.card-text');
      const hr = cardText ? cardText.querySelector('hr') : null;
      if (hr) {
        const metaElems = [];
        let sibling = hr.nextElementSibling;
        while (sibling) {
          if (!sibling.classList.contains('pdf-meta')) {
            metaElems.push(sibling);
          }
          sibling = sibling.nextElementSibling;
        }
        if (metaElems.length) {
          const wrap = document.createElement('div');
          wrap.className = 'pdf-meta';
          metaElems.forEach(el => wrap.appendChild(el));
          hr.insertAdjacentElement('afterend', wrap);
        }
      }
    } catch (_) { console.warn("[WebSocket] Reasoning block rendering failed:", _); }
  }

  // Expose appendCard for extracted handler modules
  window.appendCard = appendCard;

  // Helper function to display an error message
  function displayErrorMessage(message) {
    if (message === "") {
      message = "Something went wrong.";
    }
    setAlert(message, "error");
  }

  ws.onmessage = function (event) {
    // Register a safety timeout to prevent UI getting stuck in disabled state
    // This will be cleared for normal responses but will run if something goes wrong
    // Use longer timeout for providers known to have slower initial responses
    const currentProvider = window.currentLLMProvider || '';
    const isSlowProvider = ['deepseek', 'perplexity'].includes(currentProvider.toLowerCase());
    const timeoutDuration = isSlowProvider ? RESPONSE_TIMEOUT_SLOW_MS : RESPONSE_TIMEOUT_MS;

    const messageTimeout = setTimeout(function() {
      const userPanelEl = document.getElementById("user-panel");
      const sendBtnEl = document.getElementById("send");
      if (userPanelEl && userPanelEl.style.display !== "none" && sendBtnEl && sendBtnEl.disabled) {

        ["send", "clear", "image-file", "voice", "doc", "url", "pdf-import", "ai_user"].forEach(function(id) {
          const el = document.getElementById(id);
          if (el) el.disabled = false;
        });
        const msgEl = document.getElementById("message");
        if (msgEl) msgEl.disabled = false;
        const roleEl = document.getElementById("select-role");
        if (roleEl) roleEl.disabled = false;
        const spinnerEl = document.getElementById("monadic-spinner");
        if (spinnerEl) spinnerEl.style.display = 'none';
        const cancelEl = document.getElementById("cancel_query");
        if (cancelEl) cancelEl.style.display = 'none';

        // Reset state flags
        if (window.responseStarted !== undefined) window.responseStarted = false;
        if (window.callingFunction !== undefined) window.callingFunction = false;
        if (window.streamingResponse !== undefined) window.streamingResponse = false;

        const providerInfo = isSlowProvider ? ` (${currentProvider} may have slower initial responses)` : '';
        const timedOutText = typeof webUIi18n !== 'undefined' ?
          webUIi18n.t('ui.messages.operationTimedOut') : 'Operation timed out. UI reset.';
        setAlert(`<i class='fas fa-exclamation-triangle'></i> ${timedOutText}${providerInfo}`, "warning");
      }
    }, timeoutDuration);  // Dynamic timeout based on provider

    let data;
    try {
      data = JSON.parse(event.data);

      // Debug: Log all incoming WebSocket messages with additional context (only when debugging)
      if (window.debugWebSocket && data["type"]) {
        console.log(`[WS] Received message type: ${data["type"]}, content length: ${JSON.stringify(data).length}`);
        if (data["type"] === "info") {
          console.log(`[WS-INFO] Full info message:`, data);
        }
      }

      // Clear the safety timeout for valid responses
      clearTimeout(messageTimeout);
    } catch (error) {
      console.error("Error parsing WebSocket message:", error, event.data);
      clearTimeout(messageTimeout);
      return;
    }
    if (window.debugWebSocket) {
      console.log(`[WS-SWITCH] About to process message type: ${data["type"]}`);
    }
    switch (data["type"]) {
      case "fragment_with_audio": {
        const wah = window.WsAudioHandler;
        if (wah && typeof wah.handleFragmentWithAudio === 'function') {
          wah.handleFragmentWithAudio(data);
        }
        break;
      }

      case "wait": {
        const wtoolwh = window.WsToolHandler;
        if (wtoolwh && typeof wtoolwh.handleWait === 'function') {
          wtoolwh.handleWait(data);
        }
        break;
      }

      case "clear_fragments": {
        const wth = window.WsThinkingHandler;
        if (wth && typeof wth.handleClearFragments === 'function') {
          wth.handleClearFragments(data);
        }
        break;
      }

      case "tool_executing": {
        const wtoolh = window.WsToolHandler;
        if (wtoolh && typeof wtoolh.handleToolExecuting === 'function') {
          wtoolh.handleToolExecuting(data);
        }
        break;
      }

      case "thinking":
      case "reasoning": {
        const wthh = window.WsThinkingHandler;
        if (wthh && typeof wthh.handleThinking === 'function') {
          wthh.handleThinking(data);
        }
        break;
      }

      case "web_speech": {
        const tth = window.WsTTSHandler;
        if (tth && typeof tth.handleWebSpeech === 'function') {
          tth.handleWebSpeech(data);
        }
        break;
      }

      case "audio": {
        const wahAudio = window.WsAudioHandler;
        if (wahAudio && typeof wahAudio.handleAudio === 'function') {
          wahAudio.handleAudio(data);
        }
        break;
      }

      case "tts_progress": {
        const tth = window.WsTTSHandler;
        if (tth && typeof tth.handleTTSProgress === 'function') {
          tth.handleTTSProgress(data);
        }
        break;
      }

      case "tts_complete": {
        const tth = window.WsTTSHandler;
        if (tth && typeof tth.handleTTSComplete === 'function') {
          tth.handleTTSComplete(data);
        }
        break;
      }

      case "tts_stopped": {
        const ttsStopHandler = window.WsTTSHandler;
        if (ttsStopHandler && typeof ttsStopHandler.handleTTSStopped === 'function') {
          ttsStopHandler.handleTTSStopped(data);
        }
        break;
      }

      case "tts_notice": {
        const tth = window.WsTTSHandler;
        if (tth && typeof tth.handleTTSNotice === 'function') {
          tth.handleTTSNotice(data);
        }
        break;
      }

      case "pong": {
        break;
      }

      case "context_extraction_started": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handleContextExtractionStarted === 'function') {
          wsh.handleContextExtractionStarted(data);
        }
        break;
      }

      case "context_update": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handleContextUpdate === 'function') {
          wsh.handleContextUpdate(data);
        }
        break;
      }

      case "language_updated": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handleLanguageUpdated === 'function') {
          wsh.handleLanguageUpdated(data);
        }
        break;
      }

      case "processing_status": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handleProcessingStatus === 'function') {
          wsh.handleProcessingStatus(data);
        }
        break;
      }

      case "system_info": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handleSystemInfo === 'function') {
          wsh.handleSystemInfo(data);
        }
        break;
      }

      case "error": {
        const werr = window.WsErrorHandler;
        if (werr && typeof werr.handleError === 'function') {
          werr.handleError(data);
        }
        break;
      }

      case "token_verified": {
        const wch = window.WsConnectionHandler;
        if (wch && typeof wch.handleTokenVerified === 'function') {
          wch.handleTokenVerified(data);
        }
        break;
      }

      case "open_ai_api_error": {
        const wch = window.WsConnectionHandler;
        if (wch && typeof wch.handleOpenAIAPIError === 'function') {
          wch.handleOpenAIAPIError(data);
        }
        break;
      }
      case "token_not_verified": {
        const wch = window.WsConnectionHandler;
        if (wch && typeof wch.handleTokenNotVerified === 'function') {
          wch.handleTokenNotVerified(data);
        }
        break;
      }
      case "apps": {
        const adh = window.WsAppDataHandlers;
        if (adh && typeof adh.handleAppsMessage === 'function') {
          adh.handleAppsMessage(data);
        }
        break;
      }
      case "parameters": {
        const adh = window.WsAppDataHandlers;
        if (adh && typeof adh.handleParametersMessage === 'function') {
          adh.handleParametersMessage(data);
        }
        break;
      }
      case "elevenlabs_voices": {
        const adh = window.WsAppDataHandlers;
        if (adh && typeof adh.handleElevenLabsVoices === 'function') {
          adh.handleElevenLabsVoices(data);
        }
        break;
      }
      case "gemini_voices": {
        const adh = window.WsAppDataHandlers;
        if (adh && typeof adh.handleGeminiVoices === 'function') {
          adh.handleGeminiVoices(data);
        }
        break;
      }
      case "mistral_voices": {
        const adh = window.WsAppDataHandlers;
        if (adh && typeof adh.handleMistralVoices === 'function') {
          adh.handleMistralVoices(data);
        }
        break;
      }
      case "stt": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handleSTT === 'function') {
          wsh.handleSTT(data);
        }
        break;
      }
      case "info": {
        const wih = window.WsInfoHandler;
        if (wih && typeof wih.handleInfo === 'function') {
          wih.handleInfo(data);
        }
        break;
      }
      case "pdf_titles": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handlePDFTitles === 'function') {
          wsh.handlePDFTitles(data);
        }
        break;
      }
      case "pdf_deleted": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handlePDFDeleted === 'function') {
          wsh.handlePDFDeleted(data);
        }
        break;
      }
      case "change_status": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handleChangeStatus === 'function') {
          wsh.handleChangeStatus(data);
        }
        break;
      }
      case "past_messages": {
        const wmr = window.WsMessageRenderer;
        if (wmr && typeof wmr.handlePastMessages === 'function') {
          wmr.handlePastMessages(data);
        }
        break;
      }
      case "message": {
        const wtoolmh = window.WsToolHandler;
        if (wtoolmh && typeof wtoolmh.handleMessage === 'function') {
          wtoolmh.handleMessage(data);
        }
        break;
      }
      case "ai_user_started": {
        const auh = window.WsAIUserHandler;
        if (auh && typeof auh.handleAIUserStarted === 'function') {
          auh.handleAIUserStarted(data);
        }
        break;
      }
      case "ai_user": {
        const auh = window.WsAIUserHandler;
        if (auh && typeof auh.handleAIUser === 'function') {
          auh.handleAIUser(data);
        }
        break;
      }
      case "ai_user_finished": {
        const auh = window.WsAIUserHandler;
        if (auh && typeof auh.handleAIUserFinished === 'function') {
          auh.handleAIUserFinished(data);
        }
        break;
      }

      case "success": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handleSuccess === 'function') {
          wsh.handleSuccess(data);
        }
        break;
      }

      case "edit_success": {
        const wmr = window.WsMessageRenderer;
        if (wmr && typeof wmr.handleEditSuccess === 'function') {
          wmr.handleEditSuccess(data);
        }
        break;
      }

      case "html": {
        const wsh = window.WsHtmlHandler;
        if (wsh && typeof wsh.handleHtml === 'function') {
          wsh.handleHtml(data);
        }
        break;
      }
      case "user": {
        const wsu = window.WsStreamingHandler;
        if (wsu && typeof wsu.handleUser === 'function') {
          wsu.handleUser(data);
        }
        break;
      }

      case "display_sample": {
        const wmr = window.WsMessageRenderer;
        if (wmr && typeof wmr.handleDisplaySample === 'function') {
          wmr.handleDisplaySample(data);
        }
        break;
      }

      case "sample_success": {
        const wsh = window.WsSessionHandler;
        if (wsh && typeof wsh.handleSampleSuccess === 'function') {
          wsh.handleSampleSuccess(data);
        }
        break;
      }

      case "streaming_complete": {
        const wstream = window.WsStreamingHandler;
        if (wstream && typeof wstream.handleStreamingComplete === 'function') {
          wstream.handleStreamingComplete(data);
        }
        break;
      }

      case "cancel": {
        const wcancel = window.WsErrorHandler;
        if (wcancel && typeof wcancel.handleCancel === 'function') {
          wcancel.handleCancel(data);
        }
        break;
      }

      case "mcp_status": {
        // Handle MCP server status
        handleMCPStatus(data["content"]);
        break;
      }

      default: {
        const wsd = window.WsStreamingHandler;
        if (wsd && typeof wsd.handleDefaultMessage === 'function') {
          wsd.handleDefaultMessage(data);
        }
      }
    }
  }

  ws.onclose = function (_e) {
    window.initialLoadComplete = false;

    // CRITICAL: Reset isConnecting flag when connection closes
    // This prevents handleVisibilityChange from being permanently blocked
    // if connection fails before onopen callback fires
    window._wsIsConnecting = false;

    // Update state if available
    if (window.UIState) {
      window.UIState.set('wsConnected', false);
      window.UIState.set('wsReconnecting', true);
    }
    // Show message based on current mode: if Stop操作による明示停止（silentモード）なら"Stopped"、
    // それ以外は通常の Connection lost を案内
    if (window.silentReconnectMode || (document.cookie && document.cookie.includes('silent_reconnect=true'))) {
      const stoppedText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.stopped') : 'Stopped';
      setAlert(`<i class='fa-solid fa-circle-pause'></i> ${stoppedText}`, "warning");
      // Do not attempt reconnection in silent mode
      try { stopPing(); } catch(_) { console.warn("[WebSocket] Ping stop failed:", _); }
      return;
    } else {
      const lostText = getTranslation('ui.messages.connectionLost', 'Connection lost');
      setAlert(`<i class='fa-solid fa-server'></i> ${lostText}`, "warning");
    }
    reconnect_websocket(ws);
  }

  ws.onerror = function (err) {
    console.error(`[WebSocket] Socket error for ${wsUrl}:`, err.message || 'Unknown error');

    // Reset isConnecting flag on error (onclose will also reset, but be safe)
    window._wsIsConnecting = false;

    // Update state if available
    if (window.UIState) {
      window.UIState.set('wsConnected', false);
    }

    // Get connection details if not localhost
    if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
      const host = window.location.hostname;
      const port = window.location.port || "4567";

      // Show helpful error message
      const connectionFailedText = getTranslation('ui.messages.connectionFailed', 'Connection failed');
      setAlert(`<i class='fa-solid fa-circle-exclamation'></i> ${connectionFailedText} - ${host}:${port}`, "danger");
    } else {
      // Generic error for localhost
      const connectionFailedText = getTranslation('ui.messages.connectionFailed', 'Connection failed');
      setAlert(`<i class='fa-solid fa-circle-exclamation'></i> ${connectionFailedText}`, "danger");
    }

    ws.close();
  }
  return ws;
}

// reconnect_websocket — extracted to ws-reconnect-handler.js (window.WsReconnectHandler)
// Uses window._wsReconnectionTimer and window.ws for shared state
const reconnect_websocket = window.reconnect_websocket;

// handleVisibilityChange and visibilitychange listener
// — extracted to ws-visibility-handler.js (window.WsVisibilityHandler)
// Uses window._wsIsConnecting and window._wsReconnectionTimer for shared state

// Clean up WebSocket when page is unloaded
window.addEventListener('beforeunload', function() {
  stopPing();

  if (window._wsReconnectionTimer) {
    clearTimeout(window._wsReconnectionTimer);
    window._wsReconnectionTimer = null;
  }

  if (typeof clearAudioQueue === 'function') clearAudioQueue();
  if (window.firefoxAudioQueue) window.firefoxAudioQueue = [];

  // Release MediaSource/SourceBuffer/Audio via playback module
  const pb = window.WsAudioPlayback || {};
  const sb = pb.getSourceBuffer ? pb.getSourceBuffer() : null;
  const ms = pb.getMediaSource ? pb.getMediaSource() : null;
  const aud = pb.getAudio ? pb.getAudio() : null;
  const ac = pb.getAudioContext ? pb.getAudioContext() : null;

  if (sb) { try { if (sb.updating) sb.abort(); } catch (e) { console.warn("[Audio] SourceBuffer abort failed:", e); } }
  if (ms && ms.readyState === 'open') { try { ms.endOfStream(); } catch (e) { console.warn("[Audio] MediaSource.endOfStream failed:", e); } }
  if (aud) { aud.pause(); aud.src = ''; aud.load(); }
  if (ac && ac.state !== 'closed') { ac.close().catch(function(e) { console.warn("[Audio] AudioContext close failed:", e); }); }
  if (window.audioCtx && window.audioCtx.state !== 'closed') {
    window.audioCtx.close().catch(function(e) { console.warn("[Audio] Global AudioContext close failed:", e); });
  }

  closeCurrentWebSocket();
});

// Export functions for browser environment
window.connect_websocket = connect_websocket;
// reconnect_websocket is now in ws-reconnect-handler.js
window.closeCurrentWebSocket = closeCurrentWebSocket;
// handleVisibilityChange is now in ws-visibility-handler.js
window.startPing = startPing;
window.stopPing = stopPing;


// Support for Jest testing environment (CommonJS)
// Re-export from extracted modules for backward compatibility
if (typeof module !== 'undefined' && module.exports) {
  const _pb = (typeof window !== 'undefined' && window.WsAudioPlayback) || {};
  const _q = (typeof window !== 'undefined' && window.WsAudioQueue) || {};
  const _ui = (typeof window !== 'undefined' && window.WsUiHelpers) || {};
  module.exports = {
    connect_websocket,
    reconnect_websocket: (typeof window !== 'undefined' && window.reconnect_websocket) || function() {},
    handleVisibilityChange: (typeof window !== 'undefined' && window.handleVisibilityChange) || function() {},
    startPing,
    stopPing,
    updateAIUserButtonState: _ui.updateAIUserButtonState || updateAIUserButtonState,
    playAudioDirectly: _pb.playAudioDirectly || playAudioDirectly,
    playWithAudioElement: _pb.playWithAudioElement || playWithAudioElement,
    playAudioForIOS: _pb.playAudioForIOS || playAudioForIOS,
    processIOSAudioBuffer: _pb.processIOSAudioBuffer || processIOSAudioBuffer,
    clearAudioQueue: _q.clearAudioQueue || clearAudioQueue,
    resetAudioElements: _pb.resetAudioElements || resetAudioElements,
    resetSessionState: _q.resetSessionState || resetSessionState,
    initializeMediaSourceForAudio: _pb.initializeMediaSourceForAudio || initializeMediaSourceForAudio,
    addToAudioQueue: _q.addToAudioQueue || addToAudioQueue
  };
}

// Initialize WebSocket connection AFTER ensureMonadicTabId is defined
// This ensures tab_id is available when connecting
ws = connect_websocket();
window.ws = ws;  // Make ws globally accessible
