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
let isConnecting = false;  // Guard to prevent duplicate connection attempts

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
const BUSY_CHECK_INTERVAL_MS = (window.WsAudioConstants || {}).BUSY_CHECK_INTERVAL_MS || 500;
const BUSY_CHECK_MAX_WAIT_MS = (window.WsAudioConstants || {}).BUSY_CHECK_MAX_WAIT_MS || 10000;

// Stop-button highlighting, checkAndHideSpinner now in ws-auto-speech.js
const { highlightStopButton, removeStopButtonHighlight, checkAndHideSpinner } = window.WsAutoSpeech || {};

// message is submitted upon pressing enter
const message = $("#message")[0];

message.addEventListener("compositionstart", function () {
  message.dataset.ime = "true";
});

message.addEventListener("compositionend", function () {
  message.dataset.ime = "false";
});

document.addEventListener("keydown", function (event) {
  // Right Arrow key - activate voice input when Easy Submit is enabled
  if ($("#check-easy-submit").is(":checked") && !$("#message").is(":focus") && event.key === "ArrowRight") {
    event.preventDefault();
    // Only activate voice button if session has begun (config is hidden and main panel is visible)
    if ($("#voice").prop("disabled") === false && !$("#config").is(":visible") && $("#main-panel").is(":visible")) {
      $("#voice").click();
    }
  }

  // Enter key - submit message when focus is not in textarea
  if ($("#check-easy-submit").is(":checked") && !$("#message").is(":focus") && event.key === "Enter" && message.dataset.ime !== "true") {
    // Only submit if message is not empty
    if (message.value.trim() !== "") {
      event.preventDefault();
      if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
        // Ignore auto-submit when tab is not in foreground
      } else {
        $("#send").click();
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

window.chatBottom = $("#chat-bottom").get(0);
window.autoScroll = true;

const mainPanel = $("#main-panel").get(0);
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

// Handle fragment message from streaming response
// This function will be used by the fragment_with_audio handler and all vendor helpers
window.handleFragmentMessage = function(fragment) {
  console.log('[handleFragmentMessage] Called with:', fragment ? fragment.type : 'null', 'content length:', fragment?.content?.length || 0);
  if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
    // Skip streaming updates in background tabs to avoid duplicate rendering and TTS triggers
    window.__lastSkippedFragment = fragment;
    return;
  }
  if (fragment && fragment.type === 'fragment') {
    console.log('[handleFragmentMessage] Processing fragment, temp-card exists:', $('#temp-card').length, 'visible:', $('#temp-card').is(':visible'), 'display:', $('#temp-card').css('display'));
    const text = fragment.content || '';

    // Debug logging for streaming fragment ordering
    if (window.debugFragments) {
      const now = performance.now();
      console.log('[Fragment Debug]', {
        content: text.substring(0, 50) + (text.length > 50 ? '...' : ''),
        sequence: fragment.sequence,
        index: fragment.index,
        timestamp: fragment.timestamp || Date.now(),
        is_first: fragment.is_first,
        lastSequence: window._lastProcessedSequence,
        lastIndex: window._lastProcessedIndex,
        processingTime: now,
        timeSinceLast: window._lastFragmentTime ? (now - window._lastFragmentTime).toFixed(2) + 'ms' : 'N/A'
      });
      window._lastFragmentTime = now;
    }

    // Skip empty fragments
    if (!text) return;

    // Create or get temporary card
    let tempCard = $("#temp-card");
    if (!tempCard.length) {
      // Initialize tracking
      window._lastProcessedSequence = -1;
      window._lastProcessedIndex = -1;

      // Only clear #chat if it exists and has content from old streaming approach
      if ($("#chat").length && $("#chat").html().trim() !== "") {
        $("#chat").empty();
      }

      // Create a new temporary card for streaming text
      tempCard = $(`
        <div id="temp-card" class="card mt-3 streaming-card">
          <div class="card-header p-2 ps-3 d-flex justify-content-between align-items-center">
            <div class="fs-5 card-title mb-0">
              <span><i class="fas fa-robot" style="color: #DC4C64;"></i></span> <span class="fw-bold fs-6" style="color: #DC4C64;">Assistant</span>
            </div>
          </div>
          <div class="card-body role-assistant">
            <div class="card-text"></div>
          </div>
        </div>
      `);
      $("#discourse").append(tempCard);
      tempCard.show(); // Ensure temp-card is visible after creation
    } else if (fragment.start === true || fragment.is_first === true) {
      // If this is marked as the first fragment of a streaming response, clear the existing content
      $("#temp-card .card-text").empty();
      window._lastProcessedSequence = -1;
      window._lastProcessedIndex = -1;

      // Move the temp card to the end of #discourse to ensure correct position
      // This handles cases where the card was left in an old position from previous streaming
      tempCard.detach();
      $("#discourse").append(tempCard);
    }

    // Prefer sequence number over index for duplicate detection
    // Sequence is more reliable as it's incremented for each fragment sent
    if (fragment.sequence !== undefined) {
      // Track sequence gaps for debugging
      if (window.debugFragments && window._lastProcessedSequence !== undefined && window._lastProcessedSequence !== -1) {
        const expectedSequence = window._lastProcessedSequence + 1;
        if (fragment.sequence !== expectedSequence) {
          console.warn('[Fragment Debug] SEQUENCE GAP DETECTED:', {
            expected: expectedSequence,
            received: fragment.sequence,
            gap: fragment.sequence - expectedSequence,
            content: text.substring(0, 30)
          });
          // Track gap history for later analysis
          window._sequenceGaps = window._sequenceGaps || [];
          window._sequenceGaps.push({ expected: expectedSequence, received: fragment.sequence, time: performance.now() });
        }
      }

      if (window._lastProcessedSequence !== undefined && window._lastProcessedSequence >= fragment.sequence) {
        // Skip duplicate or out-of-order fragments
        console.warn('[handleFragmentMessage] SKIPPING fragment - sequence:', fragment.sequence, 'lastSequence:', window._lastProcessedSequence);
        if (window.debugFragments) {
          window._skippedFragments = window._skippedFragments || [];
          window._skippedFragments.push({ sequence: fragment.sequence, content: text.substring(0, 30), time: performance.now() });
        }
        return;
      }
      window._lastProcessedSequence = fragment.sequence;
    } else if (fragment.index !== undefined) {
      // Fallback to index-based detection for backwards compatibility
      if (window._lastProcessedIndex !== undefined && window._lastProcessedIndex >= fragment.index) {
        // Skip duplicate or out-of-order fragments
        console.warn('[handleFragmentMessage] SKIPPING fragment - index:', fragment.index, 'lastIndex:', window._lastProcessedIndex);
        return;
      }
      window._lastProcessedIndex = fragment.index;
    } else {
      // If no index is provided, use timestamp-based duplicate detection
      // This is a fallback for providers that don't send index
      const now = Date.now();
      const fragmentKey = `${text}_${fragment.timestamp || now}`;

      // Check if we've seen this exact fragment (content + timestamp) recently
      if (window._recentFragments && window._recentFragments[fragmentKey]) {
        if (window.debugFragments) {
          console.log('[Fragment Debug] Skipping duplicate fragment - content:', text);
        }
        return;
      }

      // Store this fragment temporarily
      window._recentFragments = window._recentFragments || {};
      window._recentFragments[fragmentKey] = now;

      // Clean up old entries after 1 second
      setTimeout(() => {
        delete window._recentFragments[fragmentKey];
      }, 1000);
    }

    // Add to streaming text display
    const tempText = $("#temp-card .card-text");
    console.log('[handleFragmentMessage] .card-text exists:', tempText.length, 'adding text length:', text.length);
    if (tempText.length) {
      // Ensure temp-card is visible when adding content
      $("#temp-card").show();
      // Debug: Log current text content before adding
      if (window.debugFragments) {
        console.log('[Fragment Debug] Before append - DOM text length:', tempText[0].textContent.length);
        console.log('[Fragment Debug] Adding fragment:', text);
      }

      // Use DocumentFragment for efficient DOM manipulation while preserving newlines
      const docFrag = document.createDocumentFragment();
      const lines = text.split('\n');

      lines.forEach((line, index) => {
        // Add line break for all lines except the first
        if (index > 0) {
          docFrag.appendChild(document.createElement('br'));
        }
        // Add text node for each line (automatically escapes HTML)
        if (line) {
          docFrag.appendChild(document.createTextNode(line));
        }
      });

      // Append all at once for better performance
      tempText[0].appendChild(docFrag);
      console.log('[handleFragmentMessage] Appended to .card-text, new length:', tempText[0].textContent.length);

      // Debug: Log after append
      if (window.debugFragments) {
        console.log('[Fragment Debug] After append - DOM text length:', tempText[0].textContent.length);
      }
    } else {
      console.warn('[handleFragmentMessage] WARNING: .card-text not found, cannot append fragment');
    }

    // If this is a final fragment, clean up
    if (fragment.final) {
      window._lastProcessedIndex = -1;
      window._lastProcessedSequence = -1;
    }
  }
};

// Debug function to check streaming fragment issues after a response
// Usage: window.debugFragments = true; window.debugFragmentSummary()
window.debugFragmentSummary = function() {
  if (!window.debugFragments) {
    console.log('Enable debug mode first: window.debugFragments = true');
    return;
  }
  console.log('=== Fragment Debug Summary ===');
  console.log('Last processed sequence:', window._lastProcessedSequence);
  console.log('Last processed index:', window._lastProcessedIndex);

  if (window._sequenceGaps && window._sequenceGaps.length > 0) {
    console.warn('Sequence gaps detected:', window._sequenceGaps.length);
    window._sequenceGaps.forEach(gap => console.warn('  Gap:', gap));
  } else {
    console.log('No sequence gaps detected ✓');
  }

  if (window._skippedFragments && window._skippedFragments.length > 0) {
    console.warn('Skipped fragments:', window._skippedFragments.length);
    window._skippedFragments.forEach(f => console.warn('  Skipped:', f));
  } else {
    console.log('No skipped fragments ✓');
  }

  console.log('==============================');
};

// Reset debug tracking for new streaming response
window.resetFragmentDebug = function() {
  window._lastProcessedSequence = -1;
  window._lastProcessedIndex = -1;
  window._sequenceGaps = [];
  window._skippedFragments = [];
  window._lastFragmentTime = null;
  window._timeline = [];
  if (window.debugFragments) {
    console.log('[Fragment Debug] Tracking reset');
  }
};

// Make defaultApp globally available
window.defaultApp = DEFAULT_APP;

// isElementInViewport now in ws-content-renderer.js
const isElementInViewport = window.isElementInViewport;

// applyMathJax, mermaid_config, sanitizeMermaidSource, applyMermaid now in ws-content-renderer.js
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
  const tempCard = $("#temp-card");
  if (!tempCard.length) return;

  let toolStatus = tempCard.find("#tool-status");
  if (!toolStatus.length) {
    // Dynamically inject into the card header's right-side area
    let rightArea = tempCard.find(".card-header .d-flex.align-items-center").last();
    if (!rightArea.length || rightArea.hasClass("card-title")) {
      rightArea = $('<div class="me-1 text-secondary d-flex align-items-center"></div>');
      tempCard.find(".card-header").append(rightArea);
    }
    toolStatus = $('<span id="tool-status" class="tool-status-label me-2"></span>');
    const indicator = rightArea.find("#indicator");
    if (indicator.length) {
      toolStatus.insertBefore(indicator);
    } else {
      rightArea.prepend(toolStatus);
    }
  }

  if (toolName && count > 0) {
    toolStatus.html(
      '<i class="fas fa-cog fa-spin me-1"></i>' + formatToolName(toolName) + ' <span class="tool-call-count">(' + count + ')</span>'
    ).show();
  } else {
    toolStatus.hide();
  }
}

function clearToolStatus() {
  window.toolCallCount = 0;
  window.currentToolName = '';
  $("#tool-status").hide().empty();
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
      $('#monadic-spinner').hide();
    }
    // Get UI language from cookie or default to 'en'
    const uiLanguage = document.cookie.match(/ui-language=([^;]+)/)?.[1] || 'en';
    ws.send(JSON.stringify({
      message: "CHECK_TOKEN",
      initial: true,
      contents: $("#token").val(),
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
        $("body").addClass("ios-device");
        if (isMobileIOS) {
          $("body").addClass("mobile-ios-device");
        } else if (isIPad) {
          $("body").addClass("ipad-device");
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
    $("#discourse").append(htmlElement);

    // Defer applyRenderers to ensure DOM is fully ready
    if (window.MarkdownRenderer) {
      setTimeout(() => {
        window.MarkdownRenderer.applyRenderers(htmlElement[0]);
      }, 0);
    }
    updateItemStates();

    const htmlContent = $("#discourse div.card:last");

    // Use toBool helper for defensive boolean evaluation
    const toBool = window.toBool || ((value) => {
      if (typeof value === 'boolean') return value;
      if (typeof value === 'string') return value === 'true';
      return !!value;
    });

    if (toBool(params["toggle"])) {
      applyToggle(htmlContent);
    }

    // Phase 2: Disabled old applyMermaid/MathJax/ABC - now handled by MarkdownRenderer.applyRenderers()
    // if (toBool(params["mermaid"])) {
    //   applyMermaid(htmlContent);
    // }

    // if (toBool(params["mathjax"])) {
    //   applyMathJax(htmlContent);
    // }

    // if (toBool(params["abc"])) {
    //   applyAbc(htmlContent);
    // }

    formatSourceCode(htmlContent);
    cleanupListCodeBlocks(htmlContent);

    setCopyCodeButton(htmlContent);

    // Compact PDF metadata block: group elements after the first <hr> into a .pdf-meta wrapper
    try {
      const $ct = htmlContent.find('.card-text');
      const $hr = $ct.find('hr').first();
      if ($hr.length) {
        const $metaElems = $hr.nextAll().not('.pdf-meta');
        if ($metaElems.length) {
          const $wrap = $('<div class="pdf-meta"></div>');
          $metaElems.detach().appendTo($wrap);
          $hr.after($wrap);
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
      if ($("#user-panel").is(":visible") && $("#send").prop("disabled")) {

        $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import, #ai_user").prop("disabled", false);
        $("#message").prop("disabled", false);
        $("#select-role").prop("disabled", false);
        $("#monadic-spinner").hide();
        $("#cancel_query").hide();

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
    isConnecting = false;

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
    isConnecting = false;

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

// WebSocket connection management - constants from ws-audio-constants.js
let reconnectionTimer = null; // Store the timer to allow cancellation

// Improved WebSocket reconnection logic with proper cleanup and retry handling
// Note: Parameter renamed from 'ws' to 'currentWs' to avoid shadowing the module-level 'ws' variable
function reconnect_websocket(currentWs, callback) {
  // In silent mode (intentional stop), suppress reconnection attempts
  try {
    if (window.silentReconnectMode || (document.cookie && document.cookie.includes('silent_reconnect=true'))) {
      return;
    }
  } catch (_) { console.warn("[WebSocket] Silent reconnect check failed:", _); }
  // Prevent multiple reconnection attempts for the same WebSocket
  if (currentWs && currentWs._isReconnecting) {
    if (window.debugWebSocket) console.log("Already attempting to reconnect, skipping duplicate attempt");
    return;
  }

  // Store reconnection attempts in the WebSocket object itself
  // This ensures each WebSocket manages its own reconnection state
  if (currentWs && currentWs._reconnectAttempts === undefined) {
    currentWs._reconnectAttempts = 0;
  }

  // Limit maximum reconnection attempts
  if (currentWs && currentWs._reconnectAttempts >= maxReconnectAttempts) {
    console.error(`Maximum reconnection attempts (${maxReconnectAttempts}) reached.`);
    // In silent mode, keep showing 'Stopped'; otherwise show failure
    if (!window.silentReconnectMode) {
      const connectionFailedRefreshText = getTranslation('ui.messages.connectionFailedRefresh', 'Connection failed - please refresh page');
      setAlert(`<i class='fa-solid fa-server'></i> ${connectionFailedRefreshText}`, "danger");
    }

    // Properly clean up any pending timers
    currentWs._isReconnecting = false;
    if (reconnectionTimer) {
      clearTimeout(reconnectionTimer);
      reconnectionTimer = null;
    }
    return;
  }

  // Mark as reconnecting
  if (currentWs) {
    currentWs._isReconnecting = true;
  }

  // Calculate exponential backoff delay (use currentWs for attempt tracking, fallback to 0)
  const attemptCount = (currentWs && currentWs._reconnectAttempts) || 0;
  const delay = baseReconnectDelay * Math.pow(1.5, attemptCount);

  // Clear any existing reconnection timer
  if (reconnectionTimer) {
    clearTimeout(reconnectionTimer);
    reconnectionTimer = null;
  }

  try {
    // Check WebSocket state (use currentWs if provided, otherwise check module-level ws)
    const wsToCheck = currentWs || ws;
    const currentState = wsToCheck ? wsToCheck.readyState : WebSocket.CLOSED;

    switch (currentState) {
      case WebSocket.CLOSED:
        // Socket is closed, create a new one
        if (currentWs) {
          currentWs._reconnectAttempts = (currentWs._reconnectAttempts || 0) + 1;
        }

        // Stop any active ping interval
        stopPing();

        // After maximum attempts, just show final error and don't reconnect
        const currentAttempts = currentWs ? currentWs._reconnectAttempts : 0;
        if (currentAttempts >= maxReconnectAttempts) {
          const connectionFailedRefreshText = getTranslation('ui.messages.connectionFailedRefresh', 'Connection failed - please refresh page');
          setAlert(`<i class='fa-solid fa-server'></i> ${connectionFailedRefreshText}`, "danger");
          return; // Exit without creating new connection
        }

        // Get connection details
        let connectionDetails = "";
        let host = "localhost";
        let port = "4567";

        // Get hostname from browser URL if not localhost
        if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
          host = window.location.hostname;
          port = window.location.port || "4567";
          connectionDetails = ` to ${host}:${port}`;
        }

        // In silent mode, do not spam connection messages
        if (!window.silentReconnectMode) {
          const message = `<i class='fa-solid fa-sync fa-spin'></i> Connecting${connectionDetails}...`;
          setAlert(message, "warning");
        }

        // Clear audio state before reconnection to prevent stale sequences
        try {
          clearAudioQueue();
        } catch (e) {
          console.warn('[reconnect_websocket] Error clearing audio queue:', e);
        }

        // CRITICAL: Close old WebSocket before creating new one to prevent connection accumulation
        closeCurrentWebSocket();

        // Create new connection and assign to module-level ws (no shadowing now)
        ws = connect_websocket(callback);
        window.ws = ws;  // Update global reference
        break;

      case WebSocket.CLOSING:
        // Wait for socket to fully close before reconnecting
        if (window.debugWebSocket) console.log(`Socket is closing. Waiting ${delay}ms before reconnection attempt.`);
        reconnectionTimer = setTimeout(() => {
          if (currentWs) {
            currentWs._isReconnecting = false; // Reset flag before next attempt
          }
          reconnect_websocket(currentWs, callback);
        }, delay);
        break;

      case WebSocket.CONNECTING:
        // Socket is still trying to connect, wait a bit before checking again
        if (window.debugWebSocket) console.log(`Socket is connecting. Checking again in ${delay}ms.`);
        reconnectionTimer = setTimeout(() => {
          if (currentWs) {
            currentWs._isReconnecting = false; // Reset flag before next attempt
          }
          reconnect_websocket(currentWs, callback);
        }, delay);
        break;

      case WebSocket.OPEN:
        // Connection is successful, reset counters on the active connection
        if (ws) {
          ws._reconnectAttempts = 0;
          ws._isReconnecting = false;
        }

        // Start ping to keep connection alive
        startPing();

        // Update UI
        const connectedMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.connected') : 'Connected';
        // Clear silent mode and cookie when successfully connected again
        try {
          window.silentReconnectMode = false;
          document.cookie = 'silent_reconnect=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT';
        } catch(_) { console.warn("[WebSocket] Silent reconnect cleanup failed:", _); }
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${connectedMsg}`, "info");

        // Execute callback if provided
        if (callback && typeof callback === 'function') {
          callback(ws);
        }
        break;
    }
  } catch (error) {
    console.error("Error during WebSocket reconnection:", error);

    // Schedule another attempt with backoff on error
    reconnectionTimer = setTimeout(() => {
      // Increment attempt counter on error
      if (currentWs) {
        currentWs._reconnectAttempts = (currentWs._reconnectAttempts || 0) + 1;
        currentWs._isReconnecting = false; // Reset flag before next attempt
      }
      reconnect_websocket(currentWs, callback);
    }, delay);
  }
}

function handleVisibilityChange() {
  // Only take action when tab becomes visible again
  if (!document.hidden) {
    try {
      // Check if actual processing (streaming/function calls) is happening
      const stillProcessing = window.streamingResponse === true || window.callingFunction === true ||
        (typeof window.isReasoningStreamActive === 'function' && window.isReasoningStreamActive());

      // Always reset TTS flags and hide stale spinners on visibility change
      // Note: We intentionally do NOT restore spinner here to prevent stale "Processing audio" after sleep/wake
      // If actual processing is happening, the processing code will show/update the spinner appropriately
      if (window.debugWebSocket) console.log('[handleVisibilityChange] Tab visible, resetting TTS state (stillProcessing=' + stillProcessing + ')');

      // Reset TTS flags to "completed" state to prevent stale audio processing
      window.autoSpeechActive = false;
      window.autoPlayAudio = false;
      if (typeof window.setTtsPlaybackStarted === 'function') {
        window.setTtsPlaybackStarted(true);
      }
      if (typeof window.setTextResponseCompleted === 'function') {
        window.setTextResponseCompleted(true);
      }

      // Stop any ongoing Web Speech API
      if (typeof window.speechSynthesis !== 'undefined') {
        try {
          window.speechSynthesis.cancel();
        } catch (e) {
          console.warn('[handleVisibilityChange] Error stopping speech synthesis:', e);
        }
      }

      // Clear any pending Auto TTS timeout
      if (window.autoTTSSpinnerTimeout) {
        clearTimeout(window.autoTTSSpinnerTimeout);
        window.autoTTSSpinnerTimeout = null;
      }

      // Remove TTS button highlight if active
      if (typeof removeStopButtonHighlight === 'function') {
        removeStopButtonHighlight();
      }

      // Handle spinner visibility based on actual processing state
      if ($("#monadic-spinner").is(":visible")) {
        // Spinner is visible - check if we should hide stale "Processing audio" spinners
        const spinnerText = $("#monadic-spinner").find("span").text();
        const isProcessingAudio = spinnerText.toLowerCase().includes('processing') &&
                                   spinnerText.toLowerCase().includes('audio');

        if (isProcessingAudio && !stillProcessing) {
          if (window.debugWebSocket) console.log('[handleVisibilityChange] Hiding stale Processing audio spinner');
          $("#monadic-spinner").hide();
          $("#monadic-spinner")
            .find("span i")
            .removeClass("fa-headphones fa-brain fa-circle-nodes")
            .addClass("fa-comment");
          $("#monadic-spinner")
            .find("span")
            .html('<i class="fas fa-comment fa-pulse"></i> Starting');
        }
      } else if (stillProcessing) {
        // Spinner was hidden (likely due to tab switch) but we're still processing
        // Restore the spinner to indicate ongoing processing
        if (window.debugWebSocket) console.log('[handleVisibilityChange] Restoring spinner - still processing');
        $("#monadic-spinner").show();

        // Determine appropriate spinner state based on processing type
        if (window.callingFunction) {
          const processingToolsText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ?
            webUIi18n.t('ui.messages.spinnerProcessingTools') : 'Processing tools';
          $("#monadic-spinner span").html(`<i class="fas fa-cogs fa-pulse"></i> ${processingToolsText}`);
        } else if (typeof window.isReasoningStreamActive === 'function' && window.isReasoningStreamActive()) {
          const thinkingText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ?
            webUIi18n.t('ui.messages.spinnerThinking') : 'Thinking...';
          $("#monadic-spinner span").html(`<i class="fas fa-brain fa-pulse"></i> ${thinkingText}`);
        } else {
          const processingText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ?
            webUIi18n.t('ui.messages.spinnerProcessing') : 'Processing';
          $("#monadic-spinner span").html(`<i class="fas fa-spinner fa-pulse"></i> ${processingText}`);
        }
      }

      // Clear any existing reconnection timer to prevent duplicate reconnection attempts
      if (reconnectionTimer) {
        clearTimeout(reconnectionTimer);
        reconnectionTimer = null;
      }

      // Prevent duplicate connection attempts during rapid visibility changes
      if (isConnecting) {
        if (window.debugWebSocket) console.log('[handleVisibilityChange] Connection attempt already in progress, skipping');
        return;
      }

      // Handle different WebSocket states
      switch (ws ? ws.readyState : WebSocket.CLOSED) {
        case WebSocket.CLOSED:
        case WebSocket.CLOSING:

          // Reset reconnection attempts for a fresh start when user returns to tab
          if (ws && ws._reconnectAttempts !== undefined) {
            ws._reconnectAttempts = 0;
          }

          // Get connection details if not using localhost
          let connectionMessage = "";
          if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
            const host = window.location.hostname;
            const port = window.location.port || "4567";
            connectionMessage = ` to ${host}:${port}`;
          }

          // Show reconnection message unless in silent stopped mode
          if (!window.silentReconnectMode) {
            const alertMessage = `<i class='fa-solid fa-server'></i> ${getTranslation('ui.messages.connectionLost','Connection lost')}${connectionMessage}`;
            setAlert(alertMessage, "warning");
          } else {
            const stoppedText = getTranslation('ui.messages.stopped', 'Stopped');
            setAlert(`<i class='fa-solid fa-circle-pause'></i> ${stoppedText}`, "warning");
          }

          // Clear audio state before reconnection to prevent stale sequences
          // This ensures new TTS sessions start fresh without waiting for old sequence numbers
          try {
            clearAudioQueue();
          } catch (e) {
            console.warn('[handleVisibilityChange] Error clearing audio queue:', e);
          }

          // CRITICAL: Close old WebSocket before creating new one to prevent connection accumulation
          closeCurrentWebSocket();

          // Set connecting guard
          isConnecting = true;

          // Establish a new connection with proper callback
          ws = connect_websocket((newWs) => {
            isConnecting = false;  // Reset guard
            window.ws = ws;  // Update global reference for other files (utilities.js, cards.js)
            if (newWs && newWs.readyState === WebSocket.OPEN) {
              // Reload data from server
              newWs.send(JSON.stringify({ message: "LOAD" }));
              // Restart ping to keep connection alive
              startPing();
              // Update UI with connection info if appropriate
              const successMessage = connectionMessage
                ? `<i class='fa-solid fa-circle-check'></i> Connected${connectionMessage}`
                : "<i class='fa-solid fa-circle-check'></i> Connected";

              setAlert(successMessage, "info");
              try { window.silentReconnectMode = false; } catch(_) { console.warn("[WebSocket] Silent mode reset failed:", _); }
            }
          });
          break;

        case WebSocket.CONNECTING:
          // Already attempting to connect, let the process continue
          break;

        case WebSocket.OPEN:
          // Connection is already open, verify it's still active
          ws.send(JSON.stringify({ message: "PING" }));
          const connectedMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.connected') : 'Connected';
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${connectedMsg}`, "info");
          break;
      }
    } catch (error) {
      console.error("Error handling visibility change:", error);

      // Reset connecting guard on error
      isConnecting = false;

      // Cleanup any pending timers
      if (reconnectionTimer) {
        clearTimeout(reconnectionTimer);
      }

      // Reset reconnection counter and attempt to reconnect on error
      if (ws && ws._reconnectAttempts !== undefined) {
        ws._reconnectAttempts = 0;
      }

      // Start a new reconnection attempt with a fresh counter
      reconnectionTimer = setTimeout(() => {
        reconnect_websocket(ws);
      }, 1000); // Short delay before reconnection
    }
  }
}

document.addEventListener('visibilitychange', handleVisibilityChange);

// Clean up WebSocket when page is unloaded
window.addEventListener('beforeunload', function() {
  stopPing();

  if (reconnectionTimer) {
    clearTimeout(reconnectionTimer);
    reconnectionTimer = null;
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
window.reconnect_websocket = reconnect_websocket;
window.closeCurrentWebSocket = closeCurrentWebSocket;
window.handleVisibilityChange = handleVisibilityChange;
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
    reconnect_websocket,
    handleVisibilityChange,
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
