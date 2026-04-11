/**
 * ws-tool-status-ui.js
 *
 * Tool execution progress indicator for the temp-card header.
 * Extracted from websocket.js for modularity.
 *
 * The indicator shows a spinning gear, the current tool name, and
 * a call count across the tool chain. It is dynamically injected
 * into the temp-card's right-side flex area (above the session
 * indicator) on first use and reused across subsequent updates.
 */
(function() {
  'use strict';

  function formatToolName(name) {
    if (!name) return '';
    return name.replace(/_/g, ' ').replace(/\b\w/g, function(c) { return c.toUpperCase(); });
  }

  function updateToolStatus(toolName, count) {
    var tempCard = $id('temp-card');
    if (!tempCard) return;

    var toolStatus = $id('tool-status');
    if (!toolStatus) {
      // Dynamically inject into the card header's right-side area
      var headerEl = tempCard.querySelector('.card-header');
      var flexAreas = headerEl ? headerEl.querySelectorAll('.d-flex.align-items-center') : [];
      var rightArea = flexAreas.length > 0 ? flexAreas[flexAreas.length - 1] : null;
      if (!rightArea || rightArea.classList.contains('card-title')) {
        rightArea = document.createElement('div');
        rightArea.className = 'me-1 text-secondary d-flex align-items-center';
        if (headerEl) headerEl.appendChild(rightArea);
      }
      toolStatus = document.createElement('span');
      toolStatus.id = 'tool-status';
      toolStatus.className = 'tool-status-label me-2';
      var indicator = rightArea.querySelector('#indicator');
      if (indicator) {
        rightArea.insertBefore(toolStatus, indicator);
      } else {
        rightArea.insertBefore(toolStatus, rightArea.firstChild);
      }
    }

    if (toolName && count > 0) {
      toolStatus.innerHTML =
        '<i class="fas fa-cog fa-spin me-1"></i>' + formatToolName(toolName) +
        ' <span class="tool-call-count">(' + count + ')</span>';
      $show(toolStatus);
    } else {
      $hide(toolStatus);
    }
  }

  function clearToolStatus() {
    window.toolCallCount = 0;
    window.currentToolName = '';
    var toolStatusEl = $id('tool-status');
    if (toolStatusEl) {
      $hide(toolStatusEl);
      toolStatusEl.innerHTML = '';
    }
  }

  // Back-compat exports. `ws-tool-handler.js` checks
  // `typeof updateToolStatus === 'function'`, which resolves against
  // free-variable lookup on window. Keeping these globals avoids
  // touching tool handler internals.
  window.updateToolStatus = updateToolStatus;
  window.clearToolStatus = clearToolStatus;

  window.WsToolStatusUi = {
    formatToolName: formatToolName,
    updateToolStatus: updateToolStatus,
    clearToolStatus: clearToolStatus
  };

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.WsToolStatusUi;
  }
})();
