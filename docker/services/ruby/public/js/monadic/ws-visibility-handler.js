/**
 * ws-visibility-handler.js
 *
 * Handles document visibility changes (tab switching, sleep/wake).
 * Manages WebSocket reconnection, TTS state reset, and spinner
 * recovery when the user returns to the tab.
 *
 * Shared mutable state accessed via window:
 *   window._wsIsConnecting   - guard against duplicate connection attempts
 *   window._wsReconnectionTimer - pending reconnection setTimeout id
 *   window.ws                - the active WebSocket instance
 *
 * Extracted from websocket.js for modularity.
 */
(function() {
  'use strict';

  function handleVisibilityChange() {
    // Only take action when tab becomes visible again
    if (!document.hidden) {
      try {
        // Check if actual processing (streaming/function calls) is happening
        const stillProcessing = window.streamingResponse === true || window.callingFunction === true ||
          (typeof window.isReasoningStreamActive === 'function' && window.isReasoningStreamActive());

        // Always reset TTS flags and hide stale spinners on visibility change
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
        if (typeof window.removeStopButtonHighlight === 'function') {
          window.removeStopButtonHighlight();
        }

        // Handle spinner visibility based on actual processing state
        var spinner = $id("monadic-spinner");
        if (spinner) {
          var isSpinnerVisible = spinner.style.display !== 'none' && spinner.offsetParent !== null;
          if (isSpinnerVisible) {
            // Spinner is visible - check if we should hide stale "Processing audio" spinners
            var spinnerSpan = spinner.querySelector("span");
            var spinnerText = spinnerSpan ? spinnerSpan.textContent : '';
            var isProcessingAudio = spinnerText.toLowerCase().includes('processing') &&
                                       spinnerText.toLowerCase().includes('audio');

            if (isProcessingAudio && !stillProcessing) {
              if (window.debugWebSocket) console.log('[handleVisibilityChange] Hiding stale Processing audio spinner');
              $hide(spinner);
              var spinnerIcon = spinner.querySelector("span i");
              if (spinnerIcon) {
                spinnerIcon.classList.remove("fa-headphones", "fa-brain", "fa-circle-nodes");
                spinnerIcon.classList.add("fa-comment");
              }
              if (spinnerSpan) {
                spinnerSpan.innerHTML = '<i class="fas fa-comment fa-pulse"></i> Starting';
              }
            }
          } else if (stillProcessing) {
            // Spinner was hidden (likely due to tab switch) but we're still processing
            if (window.debugWebSocket) console.log('[handleVisibilityChange] Restoring spinner - still processing');
            $show(spinner);

            var spinnerSpanRestore = spinner.querySelector("span");
            // Determine appropriate spinner state based on processing type
            if (window.callingFunction) {
              var processingToolsText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ?
                webUIi18n.t('ui.messages.spinnerProcessingTools') : 'Processing tools';
              if (spinnerSpanRestore) spinnerSpanRestore.innerHTML = '<i class="fas fa-cogs fa-pulse"></i> ' + processingToolsText;
            } else if (typeof window.isReasoningStreamActive === 'function' && window.isReasoningStreamActive()) {
              var thinkingText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ?
                webUIi18n.t('ui.messages.spinnerThinking') : 'Thinking...';
              if (spinnerSpanRestore) spinnerSpanRestore.innerHTML = '<i class="fas fa-brain fa-pulse"></i> ' + thinkingText;
            } else {
              var processingText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ?
                webUIi18n.t('ui.messages.spinnerProcessing') : 'Processing';
              if (spinnerSpanRestore) spinnerSpanRestore.innerHTML = '<i class="fas fa-spinner fa-pulse"></i> ' + processingText;
            }
          }
        }

        // Clear any existing reconnection timer to prevent duplicate reconnection attempts
        if (window._wsReconnectionTimer) {
          clearTimeout(window._wsReconnectionTimer);
          window._wsReconnectionTimer = null;
        }

        // Prevent duplicate connection attempts during rapid visibility changes
        if (window._wsIsConnecting) {
          if (window.debugWebSocket) console.log('[handleVisibilityChange] Connection attempt already in progress, skipping');
          return;
        }

        // Handle different WebSocket states
        const ws = window.ws;
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
            try {
              if (typeof window.clearAudioQueue === 'function') {
                window.clearAudioQueue();
              }
            } catch (e) {
              console.warn('[handleVisibilityChange] Error clearing audio queue:', e);
            }

            // CRITICAL: Close old WebSocket before creating new one to prevent connection accumulation
            if (typeof window.closeCurrentWebSocket === 'function') {
              window.closeCurrentWebSocket();
            }

            // Set connecting guard
            window._wsIsConnecting = true;

            // Establish a new connection with proper callback
            window.ws = window.connect_websocket((newWs) => {
              window._wsIsConnecting = false;  // Reset guard
              if (newWs && newWs.readyState === WebSocket.OPEN) {
                // Reload data from server
                newWs.send(JSON.stringify({ message: "LOAD" }));
                // Restart ping to keep connection alive
                if (typeof window.startPing === 'function') {
                  window.startPing();
                }
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
        window._wsIsConnecting = false;

        // Cleanup any pending timers
        if (window._wsReconnectionTimer) {
          clearTimeout(window._wsReconnectionTimer);
        }

        // Reset reconnection counter and attempt to reconnect on error
        const ws = window.ws;
        if (ws && ws._reconnectAttempts !== undefined) {
          ws._reconnectAttempts = 0;
        }

        // Start a new reconnection attempt with a fresh counter
        window._wsReconnectionTimer = setTimeout(() => {
          if (typeof window.reconnect_websocket === 'function') {
            window.reconnect_websocket(ws);
          }
        }, 1000); // Short delay before reconnection
      }
    }
  }

  // Register the visibility change listener
  document.addEventListener('visibilitychange', handleVisibilityChange);

  // Export to window for browser usage
  window.handleVisibilityChange = handleVisibilityChange;

  window.WsVisibilityHandler = {
    handleVisibilityChange: handleVisibilityChange
  };

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.WsVisibilityHandler;
  }
})();
