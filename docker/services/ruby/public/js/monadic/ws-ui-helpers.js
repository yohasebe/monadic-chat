/**
 * ws-ui-helpers.js
 *
 * Lightweight UI helper functions extracted from websocket.js:
 * getCookie, handleMCPStatus, updateAIUserButtonState.
 */
(function() {
  "use strict";

  // ── getCookie ──────────────────────────────────────────────────────
  function getCookie(name) {
    var value = '; ' + document.cookie;
    var parts = value.split('; ' + name + '=');
    if (parts.length === 2) return parts.pop().split(';').shift();
    return null;
  }

  // ── handleMCPStatus ────────────────────────────────────────────────
  function handleMCPStatus(status) {
    if (!status) return;

    var mcpStatusEl = document.getElementById("mcp-status");
    if (!mcpStatusEl) {
      var messagesEl = document.getElementById("messages");
      if (messagesEl) {
        messagesEl.insertAdjacentHTML('beforeend',
          '<div id="mcp-status" class="alert alert-info mt-2" style="display: none;">' +
          '<h6><i class="fas fa-server"></i> MCP Server Status</h6>' +
          '<div id="mcp-status-content"></div>' +
          '</div>'
        );
      }
      mcpStatusEl = document.getElementById("mcp-status");
    }

    if (!mcpStatusEl) return;

    if (status.enabled) {
      var apps = status.apps || [];
      var port = status.port || 3100;
      var statusText = status.status || (status.running ? "running" : "stopped");

      var content = '<div><strong>Status:</strong> ' + statusText + '</div>' +
        '<div><strong>Port:</strong> ' + port + '</div>' +
        '<div><strong>Enabled Apps:</strong> ' + (apps.length > 0 ? apps.join(", ") : "none") + '</div>';

      if (apps.includes("help")) {
        content += '<div class="mt-2"><small class="text-muted">' +
          'Configure in Claude Desktop settings:<br>' +
          '<code>http://localhost:' + port + '/mcp</code>' +
          '</small></div>';
      }

      var mcpContentEl = document.getElementById("mcp-status-content");
      if (mcpContentEl) mcpContentEl.innerHTML = content;
      mcpStatusEl.style.display = '';
    } else {
      mcpStatusEl.style.display = 'none';
    }
  }

  // ── updateAIUserButtonState ────────────────────────────────────────
  function updateAIUserButtonState(messages) {
    var aiUserBtn = document.getElementById("ai_user");
    if (!aiUserBtn) return;

    var hasConversation = Array.isArray(messages) && messages.length >= 2;
    var aiUserProviderEl = document.getElementById("ai-user-provider");
    var currentProvider = aiUserProviderEl ? aiUserProviderEl.value : "";
    var isPerplexity = currentProvider.toLowerCase() === "perplexity";

    if (hasConversation) {
      aiUserBtn.disabled = false;
      if (window.i18nReady) {
        window.i18nReady.then(function() {
          var aiUserTitle = webUIi18n.t('ui.generateAIUserResponse') || "Generate AI user response based on conversation";
          aiUserBtn.setAttribute("title", aiUserTitle);
        });
      } else {
        aiUserBtn.setAttribute("title", "Generate AI user response based on conversation");
      }
      aiUserBtn.classList.remove("disabled");

      if (isPerplexity) {
        if (window.i18nReady) {
          window.i18nReady.then(function() {
            var perplexityTitle = webUIi18n.t('ui.generateAIUserResponsePerplexity') ||
              "Generate AI user response (Perplexity requires alternating user/assistant messages)";
            aiUserBtn.setAttribute("title", perplexityTitle);
          });
        } else {
          aiUserBtn.setAttribute("title", "Generate AI user response (Perplexity requires alternating user/assistant messages)");
        }
      }
    } else {
      aiUserBtn.disabled = true;
      aiUserBtn.setAttribute("title", "Start a conversation first to enable AI User");
      aiUserBtn.classList.add("disabled");
    }
  }

  // ── Namespace export ───────────────────────────────────────────────
  var ns = {
    getCookie: getCookie,
    handleMCPStatus: handleMCPStatus,
    updateAIUserButtonState: updateAIUserButtonState
  };

  window.WsUiHelpers = ns;

  // Backward-compat individual exports
  window.getCookie = getCookie;
  window.handleMCPStatus = handleMCPStatus;
  window.updateAIUserButtonState = updateAIUserButtonState;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
