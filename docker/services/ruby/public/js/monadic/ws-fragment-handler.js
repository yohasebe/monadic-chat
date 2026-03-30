/**
 * ws-fragment-handler.js
 *
 * Handles streaming fragment messages from WebSocket.
 * Creates/updates the temporary card (#temp-card) in the DOM as
 * fragments arrive, with duplicate detection (sequence, index, and
 * timestamp-based) and debug tooling.
 *
 * Extracted from websocket.js for modularity.
 */
(function() {
  'use strict';

  // Handle fragment message from streaming response
  // This function will be used by the fragment_with_audio handler and all vendor helpers
  function handleFragmentMessage(fragment) {
    console.log('[handleFragmentMessage] Called with:', fragment ? fragment.type : 'null', 'content length:', fragment?.content?.length || 0);
    if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
      // Skip streaming updates in background tabs to avoid duplicate rendering and TTS triggers
      window.__lastSkippedFragment = fragment;
      return;
    }
    if (fragment && fragment.type === 'fragment') {
      var tempCardEl = document.getElementById('temp-card');
      console.log('[handleFragmentMessage] Processing fragment, temp-card exists:', !!tempCardEl, 'visible:', tempCardEl ? tempCardEl.style.display !== 'none' : false, 'display:', tempCardEl ? tempCardEl.style.display : 'N/A');
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
      if (!tempCardEl) {
        // Initialize tracking
        window._lastProcessedSequence = -1;
        window._lastProcessedIndex = -1;

        // Only clear #chat if it exists and has content from old streaming approach
        var chatEl = document.getElementById("chat");
        if (chatEl && chatEl.innerHTML.trim() !== "") {
          chatEl.innerHTML = '';
        }

        // Create a new temporary card for streaming text
        tempCardEl = document.createElement('div');
        tempCardEl.id = 'temp-card';
        tempCardEl.className = 'card mt-3 streaming-card';
        tempCardEl.innerHTML =
          '<div class="card-header p-2 ps-3 d-flex justify-content-between align-items-center">' +
            '<div class="fs-5 card-title mb-0">' +
              '<span><i class="fas fa-robot" style="color: #DC4C64;"></i></span> <span class="fw-bold fs-6" style="color: #DC4C64;">Assistant</span>' +
            '</div>' +
          '</div>' +
          '<div class="card-body role-assistant">' +
            '<div class="card-text"></div>' +
          '</div>';

        var discourseEl = document.getElementById("discourse");
        if (discourseEl) discourseEl.appendChild(tempCardEl);
        tempCardEl.style.display = ''; // Ensure temp-card is visible after creation
      } else if (fragment.start === true || fragment.is_first === true) {
        // If this is marked as the first fragment of a streaming response, clear the existing content
        var cardTextClear = tempCardEl.querySelector('.card-text');
        if (cardTextClear) cardTextClear.innerHTML = '';
        window._lastProcessedSequence = -1;
        window._lastProcessedIndex = -1;

        // Move the temp card to the end of #discourse to ensure correct position
        var discourseReappend = document.getElementById("discourse");
        if (discourseReappend && tempCardEl.parentNode) {
          tempCardEl.parentNode.removeChild(tempCardEl);
          discourseReappend.appendChild(tempCardEl);
        }
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
      var tempText = tempCardEl.querySelector('.card-text');
      console.log('[handleFragmentMessage] .card-text exists:', !!tempText, 'adding text length:', text.length);
      if (tempText) {
        // Ensure temp-card is visible when adding content
        tempCardEl.style.display = '';
        // Debug: Log current text content before adding
        if (window.debugFragments) {
          console.log('[Fragment Debug] Before append - DOM text length:', tempText.textContent.length);
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
        tempText.appendChild(docFrag);
        console.log('[handleFragmentMessage] Appended to .card-text, new length:', tempText.textContent.length);

        // Debug: Log after append
        if (window.debugFragments) {
          console.log('[Fragment Debug] After append - DOM text length:', tempText.textContent.length);
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
  }

  // Debug function to check streaming fragment issues after a response
  // Usage: window.debugFragments = true; window.debugFragmentSummary()
  function debugFragmentSummary() {
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
  }

  // Reset debug tracking for new streaming response
  function resetFragmentDebug() {
    window._lastProcessedSequence = -1;
    window._lastProcessedIndex = -1;
    window._sequenceGaps = [];
    window._skippedFragments = [];
    window._lastFragmentTime = null;
    window._timeline = [];
    if (window.debugFragments) {
      console.log('[Fragment Debug] Tracking reset');
    }
  }

  // Export to window for browser usage
  window.handleFragmentMessage = handleFragmentMessage;
  window.debugFragmentSummary = debugFragmentSummary;
  window.resetFragmentDebug = resetFragmentDebug;

  window.WsFragmentHandler = {
    handleFragmentMessage: handleFragmentMessage,
    debugFragmentSummary: debugFragmentSummary,
    resetFragmentDebug: resetFragmentDebug
  };

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.WsFragmentHandler;
  }
})();
