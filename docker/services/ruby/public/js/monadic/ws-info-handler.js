/**
 * WebSocket Info Handler for Monadic Chat
 *
 * Handles the "info" WebSocket message which delivers system status,
 * stats, spinner management, and app selector fallback rebuild.
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */

/**
 * Handle "info" WebSocket message.
 * Updates stats display, manages spinner visibility, checks app availability,
 * and rebuilds app selectors if needed (race condition fallback).
 * @param {Object} data - Message data with content (info object)
 */
function handleInfo(data) {
  if (typeof formatInfo === 'function') {
    const infoHtml = formatInfo(data["content"]);
    if (infoHtml !== "") {
      setStats(infoHtml);
    }
  }

  const messages = window.messages || [];

  // CRITICAL: For initial load (no messages), ALWAYS hide spinner immediately
  if (messages.length === 0) {
    if (typeof window.setTextResponseCompleted === 'function') {
      window.setTextResponseCompleted(true);
    }
    if (typeof window.setTtsPlaybackStarted === 'function') {
      window.setTtsPlaybackStarted(true);
    }

    // FORCE hide spinner unconditionally - new tabs should never show spinner
    $("#monadic-spinner").hide();

    // Reset to default spinner state
    $("#monadic-spinner")
      .find("span i")
      .removeClass("fa-headphones fa-brain fa-circle-nodes fa-cogs")
      .addClass("fa-comment");
    $("#monadic-spinner")
      .find("span")
      .html('<i class="fas fa-comment fa-pulse"></i> Starting');
  }
  // For non-initial loads, follow standard logic
  else if (!window.callingFunction && !window.streamingResponse) {
    if (typeof window.setTextResponseCompleted === 'function') {
      window.setTextResponseCompleted(true);
    }
    if (typeof window.checkAndHideSpinner === 'function') {
      window.checkAndHideSpinner();
    } else {
      $("#monadic-spinner").hide();
    }
  }

  // Update status message after spinner is hidden
  const apps = window.apps || {};
  const hasAppsData = Object.keys(apps).length > 0;
  const hasDOMOptions = $("#apps option").length > 0;

  if (!hasAppsData && !hasDOMOptions) {
    const noAppsMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.noAppsAvailable') : 'No apps available - check API keys in settings';
    setAlert(`<i class='fa-solid fa-bolt'></i> ${noAppsMsg}`, "warning");
  } else {
    // Show "Ready" unless we're calling functions or streaming
    if (!window.callingFunction && !window.streamingResponse) {
      const readyMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.ready') : 'Ready';
      setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyMsg}`, "success");
    }
  }

  // Fallback: if DOM options are empty but apps data exists (race on Electron startup), rebuild
  if (hasAppsData && $("#apps option").length === 0) {
    console.warn('[WARN] Apps data present but DOM options empty. Rebuilding selectors with standard builder.');
    _rebuildAppSelectors(apps);
  }

  if (window.debugWebSocket) console.log('[INFO-END] Exiting info handler');
}

/**
 * Rebuild app selectors when DOM options are empty but apps data exists.
 * This handles a race condition on Electron startup.
 * @param {Object} apps - The apps data object
 * @private
 */
function _rebuildAppSelectors(apps) {
  try {
    $("#apps").empty();
    $("#custom-apps-dropdown").empty();

    let regularApps = [];
    let specialApps = {};

    for (const [key, value] of Object.entries(apps)) {
      if (!key || key === 'undefined' || key.trim() === '') continue;
      const displayName = value && (value["display_name"] || value["app_name"]);
      if (!displayName || displayName === 'undefined') continue;

      const group = value["group"];
      if (group && group.trim().toLowerCase() === "openai") {
        regularApps.push([key, value]);
      } else if (group && group.trim() !== "") {
        if (!specialApps[group]) specialApps[group] = [];
        specialApps[group].push([key, value]);
      } else {
        if (!specialApps["Extra"]) specialApps["Extra"] = [];
        specialApps["Extra"].push([key, value]);
      }
    }

    regularApps.sort((a, b) => {
      const textA = a[1]["display_name"] || a[1]["app_name"];
      const textB = b[1]["display_name"] || b[1]["app_name"];
      if (textA === "Chat") return -1;
      if (textB === "Chat") return 1;
      return textA.localeCompare(textB);
    });

    const groupOrder = ["Anthropic", "xAI", "Google", "Cohere", "Mistral", "Perplexity", "DeepSeek", "Ollama", "Extra"];
    specialApps = Object.fromEntries(
      Object.entries(specialApps).sort((a, b) => groupOrder.indexOf(a[0]) - groupOrder.indexOf(b[0]))
    );

    const normalizeGroupId = (name) => name.toLowerCase().replace(/[^a-z0-9]+/g, '-');

    // OpenAI group
    const allOpenAIAppsDisabled = regularApps.every(([, value]) => value.disabled === "true");
    $("#apps").append('<option disabled>──OpenAI──</option>');
    const openAIGroupClass = allOpenAIAppsDisabled ? ' all-disabled' : '';
    const openAIGroupTitle = allOpenAIAppsDisabled ? ' title="API key required for this provider"' : '';
    const openAIGroupId = normalizeGroupId("OpenAI");
    $("#custom-apps-dropdown").append(`<div class="custom-dropdown-group${openAIGroupClass}" data-group="OpenAI"${openAIGroupTitle}>
      <span>──OpenAI──${allOpenAIAppsDisabled ? '<span class="api-key-required">(API key required)</span>' : ''}</span>
      <span class="group-toggle-icon"><i class="fas fa-chevron-down"></i></span>
    </div>`);
    $("#custom-apps-dropdown").append(`<div class="group-container" id="group-${openAIGroupId}"></div>`);

    for (const [key, value] of regularApps) {
      _appendAppOption(key, value, openAIGroupId);
    }

    // Special groups
    for (const group of Object.keys(specialApps)) {
      if (specialApps[group].length > 0) {
        const allAppsDisabled = specialApps[group].every(([, value]) => value.disabled === "true");
        $("#apps").append(`<option disabled>──${group}──</option>`);
        const groupClass = allAppsDisabled ? ' all-disabled' : '';
        const disabledMessage = group === "Ollama" ? "(Ollama is not running)" : "(API key required)";
        const groupTitle = allAppsDisabled ?
          (group === "Ollama" ? ' title="Ollama is not running"' : ' title="API key required for this provider"') : '';
        $("#custom-apps-dropdown").append(`<div class="custom-dropdown-group${groupClass}" data-group="${group}"${groupTitle}>
          <span>──${group}──${allAppsDisabled ? `<span class="api-key-required">${disabledMessage}</span>` : ''}</span>
          <span class="group-toggle-icon"><i class="fas fa-chevron-down"></i></span>
        </div>`);
        const normalizedGroupId = normalizeGroupId(group);
        $("#custom-apps-dropdown").append(`<div class="group-container" id="group-${normalizedGroupId}"></div>`);
        for (const [key, value] of specialApps[group]) {
          _appendAppOption(key, value, normalizedGroupId, group);
        }
      }
    }

    // Collapse/expand handlers
    $(".custom-dropdown-group").on("click", function() {
      const group = $(this).data("group");
      const nGroupId = normalizeGroupId(group);
      const container = $(`#group-${nGroupId}`);
      const icon = $(this).find(".group-toggle-icon i");
      container.toggleClass("collapsed");
      if (container.hasClass("collapsed")) {
        icon.removeClass("fa-chevron-down").addClass("fa-chevron-right");
      } else {
        icon.removeClass("fa-chevron-right").addClass("fa-chevron-down");
      }
    });

    // Select first available app
    const firstApp = $("#apps option:not(:disabled)").first().val();
    if (firstApp) {
      $("#apps").val(firstApp).trigger('change');
    }
  } catch (e) {
    console.error('Failed to rebuild selectors from apps data:', e);
  }
}

/**
 * Append an app option to the dropdown and custom dropdown.
 * @private
 */
function _appendAppOption(key, value, groupId, group) {
  const apps = window.apps || {};
  apps[key] = value;
  const displayText = value["display_name"] || value["app_name"];
  const appIcon = value["icon"] || "";
  const isDisabled = value.disabled === "true";

  if (isDisabled) {
    $("#apps").append(`<option value="${key}" disabled>${displayText}</option>`);
  } else {
    $("#apps").append(`<option value="${key}">${displayText}</option>`);
  }

  const disabledClass = isDisabled ? ' disabled' : '';
  let disabledTitle = '';
  if (isDisabled) {
    disabledTitle = group === "Ollama" ? ' title="Ollama is not running"' : ' title="API key required"';
  }
  const $option = $(`<div class="custom-dropdown-option${disabledClass}" data-value="${key}"${disabledTitle}>
    <span style="margin-right: 8px;">${appIcon}</span>
    <span>${displayText}</span></div>`);
  $(`#group-${groupId}`).append($option);
}

// Export for browser environment
window.WsInfoHandler = {
  handleInfo
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsInfoHandler;
}
