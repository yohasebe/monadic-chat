/**
 * WebSocket Info Handler for Monadic Chat
 *
 * Handles the "info" WebSocket message which delivers system status,
 * stats, spinner management, and app selector fallback rebuild.
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

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
    const spinnerEl = document.getElementById("monadic-spinner");
    if (spinnerEl) {
      spinnerEl.style.display = 'none';
      const spanIcon = spinnerEl.querySelector("span i");
      if (spanIcon) {
        spanIcon.classList.remove("fa-headphones", "fa-brain", "fa-circle-nodes", "fa-cogs");
        spanIcon.classList.add("fa-comment");
      }
      const spanEl = spinnerEl.querySelector("span");
      if (spanEl) spanEl.innerHTML = '<i class="fas fa-comment fa-pulse"></i> Starting';
    }
  }
  // For non-initial loads, follow standard logic
  else if (!window.callingFunction && !window.streamingResponse) {
    if (typeof window.setTextResponseCompleted === 'function') {
      window.setTextResponseCompleted(true);
    }
    if (typeof window.checkAndHideSpinner === 'function') {
      window.checkAndHideSpinner();
    } else {
      const fallbackSpinner = document.getElementById("monadic-spinner");
      if (fallbackSpinner) fallbackSpinner.style.display = 'none';
    }
  }

  // Update status message after spinner is hidden
  const apps = window.apps || {};
  const hasAppsData = Object.keys(apps).length > 0;
  const appsSelect = document.getElementById("apps");
  const hasDOMOptions = appsSelect ? appsSelect.querySelectorAll("option").length > 0 : false;

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
  if (hasAppsData && appsSelect && appsSelect.querySelectorAll("option").length === 0) {
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
    const appsEl = document.getElementById("apps");
    const customDropdown = document.getElementById("custom-apps-dropdown");
    if (appsEl) appsEl.innerHTML = '';
    if (customDropdown) customDropdown.innerHTML = '';

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
    if (appsEl) appsEl.insertAdjacentHTML('beforeend', '<option disabled>──OpenAI──</option>');
    const openAIGroupClass = allOpenAIAppsDisabled ? ' all-disabled' : '';
    const openAIGroupTitle = allOpenAIAppsDisabled ? ' title="API key required for this provider"' : '';
    const openAIGroupId = normalizeGroupId("OpenAI");
    if (customDropdown) {
      customDropdown.insertAdjacentHTML('beforeend', `<div class="custom-dropdown-group${openAIGroupClass}" data-group="OpenAI"${openAIGroupTitle}>
        <span>──OpenAI──${allOpenAIAppsDisabled ? '<span class="api-key-required">(API key required)</span>' : ''}</span>
        <span class="group-toggle-icon"><i class="fas fa-chevron-down"></i></span>
      </div>`);
      customDropdown.insertAdjacentHTML('beforeend', `<div class="group-container" id="group-${openAIGroupId}"></div>`);
    }

    for (const [key, value] of regularApps) {
      _appendAppOption(key, value, openAIGroupId);
    }

    // Special groups
    for (const group of Object.keys(specialApps)) {
      if (specialApps[group].length > 0) {
        const allAppsDisabled = specialApps[group].every(([, value]) => value.disabled === "true");
        if (appsEl) appsEl.insertAdjacentHTML('beforeend', `<option disabled>──${group}──</option>`);
        const groupClass = allAppsDisabled ? ' all-disabled' : '';
        const disabledMessage = group === "Ollama" ? "(Ollama is not running)" : "(API key required)";
        const groupTitle = allAppsDisabled ?
          (group === "Ollama" ? ' title="Ollama is not running"' : ' title="API key required for this provider"') : '';
        if (customDropdown) {
          customDropdown.insertAdjacentHTML('beforeend', `<div class="custom-dropdown-group${groupClass}" data-group="${group}"${groupTitle}>
            <span>──${group}──${allAppsDisabled ? `<span class="api-key-required">${disabledMessage}</span>` : ''}</span>
            <span class="group-toggle-icon"><i class="fas fa-chevron-down"></i></span>
          </div>`);
          const normalizedGroupId = normalizeGroupId(group);
          customDropdown.insertAdjacentHTML('beforeend', `<div class="group-container" id="group-${normalizedGroupId}"></div>`);
          for (const [key, value] of specialApps[group]) {
            _appendAppOption(key, value, normalizedGroupId, group);
          }
        }
      }
    }

    // Collapse/expand handlers
    document.querySelectorAll(".custom-dropdown-group").forEach(function(groupEl) {
      groupEl.addEventListener("click", function() {
        const group = this.dataset.group;
        const nGroupId = normalizeGroupId(group);
        const container = document.getElementById(`group-${nGroupId}`);
        const icon = this.querySelector(".group-toggle-icon i");
        if (container) container.classList.toggle("collapsed");
        if (icon) {
          if (container && container.classList.contains("collapsed")) {
            icon.classList.remove("fa-chevron-down");
            icon.classList.add("fa-chevron-right");
          } else {
            icon.classList.remove("fa-chevron-right");
            icon.classList.add("fa-chevron-down");
          }
        }
      });
    });

    // Select first available app
    if (appsEl) {
      const firstApp = appsEl.querySelector("option:not(:disabled)");
      if (firstApp) {
        appsEl.value = firstApp.value;
        appsEl.dispatchEvent(new Event('change', {bubbles: true}));
      }
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

  const appsEl = document.getElementById("apps");
  if (appsEl) {
    const opt = document.createElement("option");
    opt.value = key;
    opt.textContent = displayText;
    if (isDisabled) opt.disabled = true;
    appsEl.appendChild(opt);
  }

  const disabledClass = isDisabled ? ' disabled' : '';
  let disabledTitle = '';
  if (isDisabled) {
    disabledTitle = group === "Ollama" ? ' title="Ollama is not running"' : ' title="API key required"';
  }
  const groupContainer = document.getElementById(`group-${groupId}`);
  if (groupContainer) {
    groupContainer.insertAdjacentHTML('beforeend', `<div class="custom-dropdown-option${disabledClass}" data-value="${key}"${disabledTitle}>
      <span style="margin-right: 8px;">${appIcon}</span>
      <span>${displayText}</span></div>`);
  }
}

// Export for browser environment
window.WsInfoHandler = {
  handleInfo
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsInfoHandler;
}
})();
