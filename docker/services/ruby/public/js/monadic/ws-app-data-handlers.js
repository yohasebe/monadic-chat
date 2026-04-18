/**
 * WebSocket App Data Handlers for Monadic Chat
 *
 * Handles app/parameter/voice configuration messages:
 * - apps: Build app selector dropdown, classify apps, handle initial/update paths
 * - parameters: Load session parameters, handle model selection
 * - elevenlabs_voices: Populate ElevenLabs TTS voice selector
 * - gemini_voices: Populate Gemini TTS voice selector
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */

/**
 * Normalize group names to be HTML-id friendly.
 * @param {string} group - Group name (e.g., "OpenAI", "xAI")
 * @returns {string} Lowercase hyphenated id
 */
function normalizeGroupId(group) {
  return group.toLowerCase().replace(/[^a-z0-9]+/g, '-');
}

/**
 * Handle ElevenLabs voices message.
 * Populates voice selector, enables/disables provider options,
 * and restores saved cookie preferences.
 * @param {Object} data - Message data with content array of {voice_id, name}
 */
function handleElevenLabsVoices(data) {
  const cookieValue = getCookie("elevenlabs-tts-voice");
  const voices = data["content"];

  const ttsOptionIds = [
    "elevenlabs-flash-provider-option",
    "elevenlabs-multilingual-provider-option",
    "elevenlabs-v3-provider-option"
  ];
  const sttOptionIds = [
    "elevenlabs-stt-scribe-v2",
    "elevenlabs-stt-scribe",
    "elevenlabs-stt-scribe-experimental"
  ];

  const disabledState = !(voices.length > 0);
  ttsOptionIds.concat(sttOptionIds).forEach(id => {
    const el = $id(id);
    if (el) el.disabled = disabledState;
  });

  const voiceSelect = $id("elevenlabs-tts-voice");
  if (voiceSelect) {
    voiceSelect.innerHTML = '';
    voices.forEach((voice) => {
      const option = document.createElement('option');
      option.value = voice.voice_id;
      option.textContent = voice.name;
      if (cookieValue === voice.voice_id) {
        option.selected = true;
      }
      voiceSelect.appendChild(option);
    });

    // Restore saved cookie value for voice
    const savedVoice = getCookie("elevenlabs-tts-voice");
    if (savedVoice && voiceSelect.querySelector(`option[value="${savedVoice}"]`)) {
      voiceSelect.value = savedVoice;
    }
  }

  // Restore saved cookie value for provider if it was elevenlabs
  const savedProvider = getCookie("tts-provider");
  if (["elevenlabs", "elevenlabs-flash", "elevenlabs-multilingual", "elevenlabs-v3"].includes(savedProvider)) {
    const providerSelect = $id("tts-provider");
    if (providerSelect) {
      providerSelect.value = savedProvider;
      $dispatch(providerSelect, "change");
    }
  }
}

/**
 * Handle Gemini voices message.
 * Populates voice selector, enables/disables provider and STT options,
 * and restores saved cookie preferences.
 * @param {Object} data - Message data with content array of {voice_id, name}
 */
function handleGeminiVoices(data) {
  const cookieValue = getCookie("gemini-tts-voice");
  const voices = data["content"];

  if (voices.length > 0) {
    // Enable Gemini TTS provider options
    ["gemini-flash-provider-option", "gemini-pro-provider-option"].forEach(id => {
      const el = $id(id);
      if (el) el.disabled = false;
    });
    // Enable Gemini STT model
    const sttFlash = $id("gemini-stt-flash");
    if (sttFlash) sttFlash.disabled = false;

    // Populate the voice selector
    const voiceSelect = $id("gemini-tts-voice");
    if (voiceSelect) {
      voiceSelect.innerHTML = '';
      voices.forEach((voice) => {
        const option = document.createElement('option');
        option.value = voice.voice_id;
        option.textContent = voice.name;
        if (cookieValue === voice.voice_id) {
          option.selected = true;
        }
        voiceSelect.appendChild(option);
      });

      // Restore saved cookie value for voice
      const savedVoice = getCookie("gemini-tts-voice");
      if (savedVoice && voiceSelect.querySelector(`option[value="${savedVoice}"]`)) {
        voiceSelect.value = savedVoice;
      }
    }
  } else {
    // Disable Gemini TTS provider options
    ["gemini-flash-provider-option", "gemini-pro-provider-option"].forEach(id => {
      const el = $id(id);
      if (el) el.disabled = true;
    });
    // Disable Gemini STT model
    const sttFlash = $id("gemini-stt-flash");
    if (sttFlash) sttFlash.disabled = true;
  }

  // Restore saved cookie value for provider if it was gemini
  const savedProvider = getCookie("tts-provider");
  if (savedProvider === "gemini-flash" || savedProvider === "gemini-pro") {
    const providerSelect = $id("tts-provider");
    if (providerSelect) {
      providerSelect.value = savedProvider;
      $dispatch(providerSelect, "change");
    }
  }
}

/**
 * Handle Mistral voices message.
 * Populates voice selector and enables the TTS provider option.
 * @param {Object} data - Message data with content array of {voice_id, name}
 */
function handleMistralVoices(data) {
  const cookieValue = getCookie("mistral-tts-voice");
  const voices = data["content"];

  if (voices.length > 0) {
    // Enable Mistral TTS provider option
    const providerOption = $id("mistral-tts-provider-option");
    if (providerOption) providerOption.disabled = false;

    // Populate the voice selector
    const voiceSelect = $id("mistral-tts-voice");
    if (voiceSelect) {
      voiceSelect.innerHTML = '';
      voices.forEach((voice) => {
        const option = document.createElement('option');
        option.value = voice.voice_id;
        option.textContent = voice.name;
        if (cookieValue === voice.voice_id) {
          option.selected = true;
        }
        voiceSelect.appendChild(option);
      });

      // Restore saved cookie value for voice
      const savedVoice = getCookie("mistral-tts-voice");
      if (savedVoice && voiceSelect.querySelector(`option[value="${savedVoice}"]`)) {
        voiceSelect.value = savedVoice;
      }
    }
  } else {
    // Disable Mistral TTS provider option if no voices
    const providerOption = $id("mistral-tts-provider-option");
    if (providerOption) providerOption.disabled = true;
  }

  // Restore saved cookie value for provider if it was mistral
  const savedProvider = getCookie("tts-provider");
  if (savedProvider === "mistral") {
    const providerSelect = $id("tts-provider");
    if (providerSelect) {
      providerSelect.value = savedProvider;
      $dispatch(providerSelect, "change");
    }
  }
}

/**
 * Update app and model selection after import/session restore.
 * Marks import flow, updates dropdowns, and handles model selection.
 * Extracted from connect_websocket() closure.
 * @param {Object} parameters - Parameters with app_name and model
 */
function updateAppAndModelSelection(parameters) {
  // Mark import flow to preserve app/model/group during proceedWithAppChange
  if (typeof window !== 'undefined') {
    window.isImporting = true;
    window.lastImportTime = Date.now();
  }
  // Only update if the values are not already set correctly
  const appsSelect = $id("apps");
  if (parameters.app_name && appsSelect && appsSelect.value !== parameters.app_name) {
    appsSelect.value = parameters.app_name;
    $dispatch(appsSelect, 'change');
    // Update overlay icon immediately to avoid blank state until proceedWithAppChange runs
    if (typeof updateAppSelectIcon === 'function') {
      setTimeout(() => updateAppSelectIcon(parameters.app_name), 0);
    }
  }
  // Wait for app change to complete before setting model
  setTimeout(() => {
    const modelSelect = $id("model");
    if (parameters.model && modelSelect && modelSelect.value !== parameters.model) {
      modelSelect.value = parameters.model;
      $dispatch(modelSelect, 'change');
    }
    // End of import flow; allow normal app/model changes afterwards
    if (typeof window !== 'undefined') {
      setTimeout(() => { window.isImporting = false; }, 500);
    }
  }, 200);
}

/**
 * Handle "apps" WebSocket message.
 * Builds the app selector dropdown, classifies apps into provider groups,
 * handles initial load vs update paths, and manages app auto-selection.
 * @param {Object} data - Message data with content (app map), version, docker flag
 */
function handleAppsMessage(data) {
  const apps = window.apps || {};
  // Check if this message is from a parameter update (apps list refresh after settings change)
  const fromParamUpdate = data["from_param_update"] === true;

  window.appsMessageCount = (window.appsMessageCount || 0) + 1;
  const appsSelect = $id("apps");
  window.logTL && window.logTL('apps_received', {
    count: window.appsMessageCount,
    hasAppsKeys: Object.keys(apps).length,
    currentSelect: appsSelect ? appsSelect.value : null,
    fromParamUpdate
  });

  let version_string = data["version"];
  data["docker"] ? version_string += " (Docker)" : version_string += " (Local)";
  const versionEl = $id("monadic-version-number");
  if (versionEl) versionEl.innerHTML = version_string;

  // Check if this is an update to existing apps (e.g., from language change)
  const isUpdate = Object.keys(apps).length > 0;

  if (isUpdate) {
    // Update existing apps data with new content (for language updates or reset)
    for (const [key, value] of Object.entries(data["content"])) {
      apps[key] = value;  // Update or add the app data
    }

    // Update the currently displayed app description if needed
    const currentApp = appsSelect ? appsSelect.value : null;
    if (currentApp && apps[currentApp]) {
      const descriptionOnly = apps[currentApp]["description"] || "";
      if (typeof window.setBaseAppDescription === 'function') {
        window.setBaseAppDescription(descriptionOnly);
      } else {
        const descEl = $id("base-app-desc");
        if (descEl) descEl.innerHTML = descriptionOnly;
      }
      if (typeof window.updateAppBadges === 'function') {
        window.updateAppBadges(currentApp);
      }

      // If this is after a reset, re-initialize the app
      // Check if parameters message hasn't been received yet
      if (!data["from_parameters"] && !fromParamUpdate) {
        // Re-initialize the current app with proceedWithAppChange
        setTimeout(function() {
          if (typeof window.proceedWithAppChange === 'function') {
            window.proceedWithAppChange(currentApp);
          }
        }, 100);
      }
    }
  } else {
    // Persist full app data to the global map so downstream code can read system_prompt, etc.
    try {
      for (const [key, value] of Object.entries(data["content"])) {
        // Skip invalid entries
        if (!key || key === 'undefined' || key.trim() === '') {
          console.warn('[WebSocket] Skipping invalid app in global cache with key:', key);
          continue;
        }
        // Skip apps with missing display name and app name
        const displayName = value && (value["display_name"] || value["app_name"]);
        if (!displayName || displayName === 'undefined') {
          console.warn('[WebSocket] Skipping app with missing display name in cache:', key);
          continue;
        }
        apps[key] = value;
      }
      window.logTL && window.logTL('apps_cached_to_global', { keys: Object.keys(apps).length });
    } catch (_) { console.warn("[WebSocket] App caching failed:", _); }

    // Prepare arrays for app classification
    let regularApps = [];
    let specialApps = {};

    // Classify apps into regular and special groups
    for (const [key, value] of Object.entries(data["content"])) {
      // Skip invalid entries (undefined, null, or empty key)
      if (!key || key === 'undefined' || key.trim() === '') {
        console.warn('[WebSocket] Skipping invalid app entry with key:', key);
        continue;
      }

      // Skip apps with missing display name and app name (would show as "undefined")
      const displayName = value && (value["display_name"] || value["app_name"]);
      if (!displayName || displayName === 'undefined') {
        console.warn('[WebSocket] Skipping app with missing display name:', key, value);
        continue;
      }

      const group = value["group"];

      // Check if app belongs to OpenAI group (regular apps)
      if (group && group.trim().toLowerCase() === "openai") {
        regularApps.push([key, value]);
      } else if (group && group.trim() !== "") {
        // Other groups go to special apps
        if (!specialApps[group]) {
          specialApps[group] = [];
        }
        specialApps[group].push([key, value]);
      } else {
        // create a group called "Extra" for apps without a group
        if (!specialApps["Extra"]) {
          specialApps["Extra"] = [];
        }
        specialApps["Extra"].push([key, value]);
      }
    }

    // Sort regular apps: Chat first, then alphabetically
    regularApps.sort((a, b) => {
      const textA = a[1]["display_name"] || a[1]["app_name"];
      const textB = b[1]["display_name"] || b[1]["app_name"];

      // Put Chat first
      if (textA === "Chat") return -1;
      if (textB === "Chat") return 1;

      return textA.localeCompare(textB);
    });

    // Sort apps within each special group: Chat first, then alphabetically
    for (const group of Object.keys(specialApps)) {
      specialApps[group].sort((a, b) => {
        const textA = a[1]["display_name"] || a[1]["app_name"];
        const textB = b[1]["display_name"] || b[1]["app_name"];

        // Put Chat first
        if (textA === "Chat") return -1;
        if (textB === "Chat") return 1;

        return textA.localeCompare(textB);
      });
    }

    // Add apps to selector
    // First add the OpenAI Apps label and regular apps
    // Always show OpenAI apps, regardless of verification status

    // Check if all OpenAI apps are disabled
    const allOpenAIAppsDisabled = regularApps.every(([key, value]) => value.disabled === "true");

    const customDropdown = $id("custom-apps-dropdown");

    // Add OpenAI separator to standard select
    if (appsSelect) {
      const separator = document.createElement('option');
      separator.disabled = true;
      separator.textContent = '──OpenAI──';
      appsSelect.appendChild(separator);
    }
    // Add OpenAI separator to custom dropdown with conditional styling
    const openAIGroupClass = allOpenAIAppsDisabled ? ' all-disabled' : '';
    const openAIGroupTitle = allOpenAIAppsDisabled ? ' title="API key required for this provider"' : '';
    const openAIGroupId = normalizeGroupId("OpenAI");
    if (customDropdown) {
      customDropdown.insertAdjacentHTML('beforeend', `<div class="custom-dropdown-group${openAIGroupClass}" data-group="OpenAI"${openAIGroupTitle}>
      <span>──OpenAI──${allOpenAIAppsDisabled ? '<span class="api-key-required">(API key required)</span>' : ''}</span>
      <span class="group-toggle-icon"><i class="fas fa-chevron-down"></i></span>
    </div>`);
      // Create a container for the OpenAI apps (normalized id for toggle)
      customDropdown.insertAdjacentHTML('beforeend', `<div class="group-container" id="group-${openAIGroupId}"></div>`);
    }

    for (const [key, value] of regularApps) {
      apps[key] = value;
      // Use display_name if available, otherwise fall back to app_name
      const displayText = value["display_name"] || value["app_name"];
      const appIcon = value["icon"] || "";
      const isDisabled = value.disabled === "true";

      // Add option to standard select
      if (appsSelect) {
        const opt = document.createElement('option');
        opt.value = key;
        opt.textContent = displayText;
        if (isDisabled) opt.disabled = true;
        appsSelect.appendChild(opt);
      }

      // Add the same option to custom dropdown with icon
      const disabledClass = isDisabled ? ' disabled' : '';
      const disabledTitle = isDisabled ? ' title="API key required"' : '';
      const groupContainer = $id(`group-${openAIGroupId}`);
      if (groupContainer) {
        groupContainer.insertAdjacentHTML('beforeend', `<div class="custom-dropdown-option${disabledClass}" data-value="${key}"${disabledTitle}>
          <span style="margin-right: 8px;">${appIcon}</span>
          <span>${displayText}</span></div>`);
      }
    }

    // sort specialApps by group name in the order:
    // "Anthropic", "xAI", "Google", "Cohere", "Mistral", "Perplexity", "DeepSeek", "Ollama", "Extra"
    // and set it to the specialApps object
    specialApps = Object.fromEntries(Object.entries(specialApps).sort((a, b) => {
      const order = ["Anthropic", "xAI", "Google", "Cohere", "Mistral", "Perplexity", "DeepSeek", "Ollama", "Extra"];
      return order.indexOf(a[0]) - order.indexOf(b[0]);
    }));

      // Add special groups with their labels
      for (const group of Object.keys(specialApps)) {
        if (specialApps[group].length > 0) {
        // Check if all apps in this group are disabled
        const allAppsDisabled = specialApps[group].every(([key, value]) => value.disabled === "true");

        // Always show groups even if all apps are disabled
        // This allows users to see what apps exist but are unavailable

          // Add group header to standard select
          if (appsSelect) {
            const separator = document.createElement('option');
            separator.disabled = true;
            separator.textContent = `──${group}──`;
            appsSelect.appendChild(separator);
          }

          // Add group header to custom dropdown with conditional styling
          const groupClass = allAppsDisabled ? ' all-disabled' : '';
          // Special handling for Ollama - it doesn't require an API key
          const disabledMessage = group === "Ollama" ? "(Ollama is not running)" : "(API key required)";
          const groupTitle = allAppsDisabled ?
            (group === "Ollama" ? ' title="Ollama is not running"' : ' title="API key required for this provider"') : '';
          if (customDropdown) {
            customDropdown.insertAdjacentHTML('beforeend', `<div class="custom-dropdown-group${groupClass}" data-group="${group}"${groupTitle}>
            <span>──${group}──${allAppsDisabled ? `<span class="api-key-required">${disabledMessage}</span>` : ''}</span>
            <span class="group-toggle-icon"><i class="fas fa-chevron-down"></i></span>
          </div>`);

            // Create container for this group's apps
            const normalizedGId = normalizeGroupId(group);
            customDropdown.insertAdjacentHTML('beforeend', `<div class="group-container" id="group-${normalizedGId}"></div>`);
          }

          for (const [key, value] of specialApps[group]) {
            apps[key] = value;
            // Use display_name if available, otherwise fall back to app_name
            const displayText = value["display_name"] || value["app_name"];
            const appIcon = value["icon"] || "";
            const isDisabled = value.disabled === "true";

            // Add option to standard select
            if (appsSelect) {
              const opt = document.createElement('option');
              opt.value = key;
              opt.textContent = displayText;
              if (isDisabled) opt.disabled = true;
              appsSelect.appendChild(opt);
            }

            // Add the same option to custom dropdown with icon
            const disabledClass = isDisabled ? ' disabled' : '';
            // Special handling for Ollama apps
            const disabledTitle = isDisabled ?
              (group === "Ollama" ? ' title="Ollama is not running"' : ' title="API key required"') : '';
            const normalizedGId2 = normalizeGroupId(group);
            const groupContainer = $id(`group-${normalizedGId2}`);
            if (groupContainer) {
              groupContainer.insertAdjacentHTML('beforeend', `<div class="custom-dropdown-option${disabledClass}" data-value="${key}"${disabledTitle}>
              <span style="margin-right: 8px;">${appIcon}</span>
              <span>${displayText}</span></div>`);
            }
          }
      }
    }

    // Set up group toggle functionality via event delegation
    document.addEventListener("click", function(e) {
      const groupHeader = e.target.closest(".custom-dropdown-group");
      if (!groupHeader) return;
      const group = groupHeader.dataset.group;
      if (!group) return;
      const normalizedGId = normalizeGroupId(group);
      const container = $id(`group-${normalizedGId}`);
      if (!container) return;
      const icon = groupHeader.querySelector(".group-toggle-icon i");

      container.classList.toggle("collapsed");

      if (container.classList.contains("collapsed")) {
        if (icon) { icon.classList.remove("fa-chevron-down"); icon.classList.add("fa-chevron-right"); }
      } else {
        if (icon) { icon.classList.remove("fa-chevron-right"); icon.classList.add("fa-chevron-down"); }
      }
    });

    // Find the currently selected app's group and ensure it's expanded
    const currentApp = appsSelect ? appsSelect.value : null;
    if (currentApp) {
      setTimeout(() => {
        const currentAppOption = document.querySelector(`.custom-dropdown-option[data-value="${currentApp}"]`);
        if (currentAppOption) {
          const parentGroup = currentAppOption.closest(".group-container");
          if (parentGroup) {
            // Ensure this group is expanded
            parentGroup.classList.remove("collapsed");
            // Update the icon
            const groupId = parentGroup.id;
            const groupName = groupId.replace("group-", "");
            // Need to handle potential dashes in the group name for xAI Grok
            const groupHeader = document.querySelector(`.custom-dropdown-group[data-group="${groupName}"]`);
            if (groupHeader) {
              const icon = groupHeader.querySelector(".group-toggle-icon i");
              if (icon) { icon.classList.remove("fa-chevron-right"); icon.classList.add("fa-chevron-down"); }
            }
          }
        }
      }, 100);
    }

    // If import payload specifies an app_name, or there is already a valid selection in #apps,
    // skip auto-selection to avoid overriding an existing choice (import or user selection).
    const importRequestedApp = data && data["content"] && data["content"]["app_name"];
    const currentSelectVal = appsSelect ? appsSelect.value : null;
    const hasCurrentValidSelection = !!(currentSelectVal && appsSelect && appsSelect.querySelector(`option[value='${currentSelectVal}']`));
    // On initial load without session restore, ignore browser's auto-selection to prioritize Chat apps
    const hasSessionRestore = !!(window.lastApp && window.lastApp !== null);
    const isInitialLoad = window.appsMessageCount === 1 && !window.initialAppLoaded && !hasSessionRestore;
    window.logTL && window.logTL('app_selection_state', {
      importRequestedApp,
      currentSelectVal,
      hasCurrentValidSelection,
      isInitialLoad,
      lastApp: window.lastApp,
      isRestoringSession: window.isRestoringSession,
      initialAppLoaded: window.initialAppLoaded,
      appsMessageCount: window.appsMessageCount
    });
    // Select the default app only when not importing and no valid selection exists
    let firstValidApp;

    // PRIORITY 1: Check if window.lastApp exists (from session restoration)
    if (!firstValidApp && window.lastApp && appsSelect) {
      const lastAppOption = appsSelect.querySelector(`option[value='${window.lastApp}']`);
      if (lastAppOption && !lastAppOption.disabled) {
        firstValidApp = window.lastApp;
      } else if (!lastAppOption || lastAppOption.disabled) {
        window.logTL && window.logTL('restored_app_unavailable', { lastApp: window.lastApp });
      }
    }

    // PRIORITY 2: Try to find a Chat app from OpenAI (if API key is available)
    if (!firstValidApp && appsSelect) {
      const allOptions = Array.from(appsSelect.options);
      const openAIChatOption = allOptions.find(opt => opt.value === 'ChatOpenAI' && !opt.disabled);

      if (!importRequestedApp && (!hasCurrentValidSelection || isInitialLoad) && openAIChatOption) {
        firstValidApp = openAIChatOption.value;
      } else {
        // Look for any Chat app from other providers
        const anyChatOption = allOptions.find(opt => {
          return opt.value && opt.value.includes('Chat') && !opt.disabled && !opt.textContent.includes('──');
        });

        if (!importRequestedApp && (!hasCurrentValidSelection || isInitialLoad) && anyChatOption) {
          firstValidApp = anyChatOption.value;
        } else {
          // Fallback: select the first available non-disabled app
          if (!importRequestedApp && (!hasCurrentValidSelection || isInitialLoad)) {
            const fallbackApp = allOptions.find(opt => !opt.disabled && !opt.textContent.includes('──'));
            if (fallbackApp) firstValidApp = fallbackApp.value;
          }
        }
      }
    }

    // Set the app in dropdown if we have a valid app to select
    // During session restoration, we may already have a selection but still need to initialize
    const shouldSetApp = !importRequestedApp && firstValidApp && (!hasCurrentValidSelection || window.isRestoringSession);

    if (shouldSetApp) {
      if (appsSelect) appsSelect.value = firstValidApp;

      // Set lastApp to prevent confirmation dialog on initial load
      // Use window.lastApp to ensure it's accessible across all scopes
      window.lastApp = firstValidApp;

      // Ensure stop_apps_trigger is false so change event will be processed
      window.stop_apps_trigger = false;

      // Use display_name if available, otherwise fall back to app_name
      const selectedApp = apps[firstValidApp];
      if (selectedApp) {
        const displayText = selectedApp["display_name"] || selectedApp["app_name"];
        const titleEl = $id("base-app-title");
        if (titleEl) titleEl.textContent = displayText;

        // Update badges immediately
        const monadicBadge = $id("monadic-badge");
        $toggle(monadicBadge, selectedApp["monadic"]);

        const websearchBadge = $id("websearch-badge");
        $toggle(websearchBadge, selectedApp["websearch"]);

        const toolsBadge = $id("tools-badge");
        $toggle(toolsBadge, selectedApp["tools"]);

        const mathBadge = $id("math-badge");
        $toggle(mathBadge, selectedApp["math"]);

        const iconEl = $id("base-app-icon");
        if (iconEl) iconEl.innerHTML = selectedApp["icon"];

        const descriptionOnly = selectedApp["description"] || "";
        if (typeof window.setBaseAppDescription === 'function') {
          window.setBaseAppDescription(descriptionOnly);
        } else {
          const descEl = $id("base-app-desc");
          if (descEl) descEl.innerHTML = descriptionOnly;
        }
        if (typeof window.updateAppBadges === 'function') {
          window.updateAppBadges(firstValidApp);
        }

        if (firstValidApp === "PDF") {
          if (window.ws) {
            window.ws.send(JSON.stringify({ message: "PDF_TITLES" }));
          }
        }

        // Call proceedWithAppChange directly to ensure proper initialization
        // Use setTimeout to ensure DOM and all dependencies are ready
        if (!fromParamUpdate) {
          setTimeout(function() {
            const recentlyImported = (typeof window !== 'undefined' && window.lastImportTime) ? (Date.now() - window.lastImportTime < 1000) : false;
            const isImportingNotRestoring = window.isImporting && !window.isRestoringSession;
            window.logTL && window.logTL('apps_first_timeout', {
              recentlyImported,
              hasCurrentValidSelection,
              firstValidApp,
              isRestoringSession: window.isRestoringSession,
              isImportingNotRestoring,
              willProceed: !(isImportingNotRestoring || recentlyImported)
            });
            // Skip only during import (when NOT restoring session), not during session restoration
            if (typeof window !== 'undefined' && (isImportingNotRestoring || recentlyImported)) {
              return;
            }
            window.logTL && window.logTL('auto_select_app', { firstValidApp });
            if (typeof window.proceedWithAppChange === 'function') {
              // Ensure flag is set before calling proceedWithAppChange
              // This guarantees confirmation dialog is skipped when syncing from server
              // Check if variable is defined before using it
              if (typeof hasCurrentAppFromServer !== 'undefined' && hasCurrentAppFromServer) {
                window.currentAppFromServer = firstValidApp;
              }
              // Call proceedWithAppChange directly for reliable initialization
              window.proceedWithAppChange(firstValidApp);
              window.logTL && window.logTL('proceedWithAppChange_called_from_apps', { app: firstValidApp });

            } else {
              // Fallback to triggering change event if function not available
              $dispatch(appsSelect, 'change');
              window.logTL && window.logTL('apps_change_triggered');
            }
          }, 100);
        }
      }
    }

  // One-time initialization: if first APPS build resulted in a selected value but we didn't auto-select above
  // (e.g., because hasCurrentValidSelection was true due to default selection), explicitly initialize.
  if (!fromParamUpdate) {
    setTimeout(function() {
      try {
        const isImportingNotRestoring = window.isImporting && !window.isRestoringSession;
        const currentAppsVal = appsSelect ? appsSelect.value : null;
        window.logTL && window.logTL('apps_second_timeout_check', {
          appsMessageCount: window.appsMessageCount,
          importRequestedApp,
          initialAppLoaded: window.initialAppLoaded,
          selectedApp: currentAppsVal,
          isImporting: window.isImporting,
          isRestoringSession: window.isRestoringSession,
          isImportingNotRestoring,
          willProceed: (window.appsMessageCount === 1 && !importRequestedApp && !window.initialAppLoaded && !isImportingNotRestoring)
        });
        // Skip during import (when NOT restoring session), but allow during session restoration
        if (!fromParamUpdate && window.appsMessageCount === 1 && !importRequestedApp && !window.initialAppLoaded && !isImportingNotRestoring) {
          const sel = currentAppsVal;
          if (sel) {
            window.logTL && window.logTL('proceedWithAppChange_on_first_selected', { app: sel });
            if (typeof window.proceedWithAppChange === 'function') {
              window.proceedWithAppChange(sel);
              // Set flag AFTER proceedWithAppChange completes
              window.initialAppLoaded = true;
            } else {
              $dispatch(appsSelect, 'change');
              window.initialAppLoaded = true;
            }
          }
        } else {
          window.logTL && window.logTL('apps_second_timeout_skipped', {
            importRequestedApp,
            selectedApp: currentAppsVal,
            fromParamUpdate,
            appsMessageCount: window.appsMessageCount,
            initialAppLoaded: window.initialAppLoaded,
            isImportingNotRestoring
          });
        }
      } catch (e) {
        console.error('Error in second timeout:', e);
      }
    }, 150);
  }

    // Update the AI User provider dropdown if the function is available
    if (typeof window.updateAvailableProviders === 'function') {
      window.updateAvailableProviders();
    }
    // TTS/STT provider options may not have existed when the initial
    // enablement ran; re-apply now that app data has populated the DOM.
    if (typeof window.applyTtsSttEnablement === 'function') {
      window.applyTtsSttEnablement(window.aiUserDefaults);
    }
  }
  // Set originalParams to the first valid app or Chat if available
  window.originalParams = apps["Chat"] || apps[appsSelect ? appsSelect.value : null] || {};

  // Process pending parameters if any
  if (window.pendingParameters) {
    const params = window.pendingParameters;
    window.pendingParameters = null;

    // Process the stored parameters after a delay to ensure DOM is ready
    if (params.app_name) {
      window.loadedApp = params.app_name;
      window.logTL && window.logTL('pending_parameters_found', { app: params.app_name });
      // Add delay to ensure dropdown is fully populated
      setTimeout(() => {
        // Call loadParams which will handle the app and model selection
        if (typeof loadParams === 'function') {
          loadParams(params, "loadParams");
        } else if (typeof window.loadParams === 'function') {
          window.loadParams(params, "loadParams");
        }
      }, 100);
    }
  } else {
    // Only reset params if we don't have pending parameters to load
    // AND if we're not in a loaded session (after import)
    // AND if this is truly the first APPS message
    const currentApp = appsSelect ? appsSelect.value : null;
    const isFirstAppsMessage = window.appsMessageCount === 1;

    window.logTL && window.logTL('post_apps_maybe_reset', { currentApp, isFirstAppsMessage, loadedApp: window.loadedApp });

    // Only reset if this is the first apps message and no app is selected
    // OR if there's no loaded app from import
    if (isFirstAppsMessage && (!currentApp || currentApp === "") && !window.loadedApp) {
      if (typeof resetParams === 'function') {
        resetParams();
      }
      window.logTL && window.logTL('resetParams_called_after_apps');
    } else {
      // If app is already configured, update badges for initial display
      if (isFirstAppsMessage && currentApp && typeof window.updateAppBadges === 'function') {
        setTimeout(function() {
          window.updateAppBadges(currentApp);
        }, 200);
      }
    }
  }
  // Sync apps object back to window
  window.apps = apps;
}

/**
 * Handle "parameters" WebSocket message.
 * Loads session parameters, handles model selection, and manages import/restore flows.
 * @param {Object} data - Message data with content (parameters object)
 * @returns {string|undefined} Status string for testing: 'skip', 'param_update', 'pending'
 */
function handleParametersMessage(data) {
  const apps = window.apps || {};

  // Check if we have valid content
  if (!data["content"] || Object.keys(data["content"]).length === 0) {
    return 'skip';
  }

  const fromParamUpdate = data["from_param_update"] === true;

  // Skip full loadParams for param sync updates from the same session
  // These are echoes of our own changes and shouldn't reset UI state
  if (fromParamUpdate) {
    // Just update the local params object without resetting UI
    if (typeof params !== 'undefined') {
      Object.assign(params, data["content"]);
    }
    return 'param_update';
  }

  if (data["from_import"]) {
    if (typeof setAutoSpeechSuppressed === 'function') {
      setAutoSpeechSuppressed(true, { reason: 'parameters import' });
    }
    if (typeof window !== 'undefined') {
      window.isProcessingImport = true;
      window.skipAssistantInitiation = true;
    }
  }

  // Store parameters for later processing if apps not loaded yet
  // Also defer if apps data exists but DOM options haven't been built yet
  const appsSelect = $id("apps");
  const appsOptionCount = appsSelect ? appsSelect.options.length : 0;
  if (!apps || Object.keys(apps).length === 0 || (appsSelect && appsOptionCount === 0)) {
    window.pendingParameters = data["content"];
    return 'pending';
  }

  // Only process if we have an app_name
  if (data["content"]["app_name"]) {

    window.loadedApp = data["content"]["app_name"];

    // Call loadParams which will handle everything including model selection
    window.logTL && window.logTL('parameters_received', {
      app_name: data["content"]["app_name"],
      has_initial_prompt: !!data["content"]["initial_prompt"],
      model: data["content"]["model"],
      group: data["content"]["group"]
    });

    let releaseParamSuppression = false;
    if (typeof window !== "undefined") {
      window.suppressParamBroadcastCount = (window.suppressParamBroadcastCount || 0) + 1;
      releaseParamSuppression = true;
    }

    try {
      // Check if loadParams is defined
      if (typeof loadParams === 'function') {
        loadParams(data["content"], "loadParams");
        window.logTL && window.logTL('loadParams_called_from_parameters', { calledFor: 'loadParams' });

        // Call proceedWithAppChange to ensure model list is populated
        const requestedApp = data["content"]["app_name"];
        const currentAppSelection = appsSelect ? appsSelect.value : null;
        const needsAppSync =
          !window.initialAppLoaded ||
          window.isProcessingImport ||
          !currentAppSelection ||
          currentAppSelection !== requestedApp;

        if (requestedApp && typeof window.proceedWithAppChange === 'function' && needsAppSync && window.apps[requestedApp]) {
          // Use requestAnimationFrame to ensure DOM is ready (double-call for rendering completion)
          requestAnimationFrame(() => {
            requestAnimationFrame(() => {
              window.proceedWithAppChange(requestedApp);
              window.logTL && window.logTL('proceedWithAppChange_called_from_parameters', { app: requestedApp });
            });
          });
        }
      } else if (typeof window.loadParams === 'function') {
        window.loadParams(data["content"], "loadParams");

        // Call proceedWithAppChange for window.loadParams as well
        if (data["content"]["app_name"] && typeof window.proceedWithAppChange === 'function' && window.apps[data["content"]["app_name"]]) {
          // Use requestAnimationFrame to ensure DOM is ready (double-call for rendering completion)
          requestAnimationFrame(() => {
            requestAnimationFrame(() => {
              window.proceedWithAppChange(data["content"]["app_name"]);
              window.logTL && window.logTL('proceedWithAppChange_called_from_parameters', { app: data["content"]["app_name"] });
            });
          });
        }
      } else {
        // Direct fallback approach
        const appName = data["content"]["app_name"];
        const model = data["content"]["model"];

        // Set the app directly
        if (appName && appsSelect) {
          appsSelect.value = appName;
          // Trigger change to update model list
          $dispatch(appsSelect, 'change');

          // Set model after a delay
          setTimeout(() => {
            let targetModel = model;
            // Auto-migrate deprecated models to their successor
            if (targetModel && typeof isModelDeprecated === 'function' && isModelDeprecated(targetModel)) {
              const successor = typeof getModelSuccessor === 'function' ? getModelSuccessor(targetModel) : null;
              if (successor) {
                console.warn(`[Session] Model "${targetModel}" is deprecated, migrating to "${successor}"`);
                setTimeout(() => {
                  if (typeof setAlert === 'function') {
                    setAlert(`<i class="fas fa-exchange-alt"></i> Model "${targetModel}" has been replaced with "${successor}" (deprecated model).`, "warning");
                  }
                }, 1000);
                targetModel = successor;
              }
            }
            const modelSelect = $id("model");
            if (targetModel && modelSelect) {
              modelSelect.value = targetModel;
              if (modelSelect.value !== targetModel) {
                console.error("Failed to set model:", targetModel);
                // Try again with a longer delay
                setTimeout(() => {
                  modelSelect.value = targetModel;
                  $dispatch(modelSelect, 'change');
                }, 500);
              } else {
                $dispatch(modelSelect, 'change');
              }
            }
          }, 300);
        }
      }
    } finally {
      if (releaseParamSuppression) {
        setTimeout(() => {
          window.suppressParamBroadcastCount = Math.max(0, (window.suppressParamBroadcastCount || 1) - 1);
        }, 600);
      }
    }

    // Mark as initialized to prevent duplicate initialization from timeout blocks
    window.initialAppLoaded = true;
    return;
  }

  // This code should only run if there's no app_name in parameters
  // (which means it's not a loaded session)

  // All providers now support AI User functionality

  const currentApp = apps[appsSelect ? appsSelect.value : null] || apps[window.defaultApp];

  // Use shared utility function to get models for the app
  const showAllEl = $id("show-all-models");
  const showAll = showAllEl ? showAllEl.checked : false;
  let models = currentApp ? getModelsForApp(currentApp, showAll) : [];

  if (currentApp) {
    let openai = currentApp["group"] && currentApp["group"].toLowerCase() === "openai";
    let modelList = listModels(models, openai);
    const modelSelect = $id("model");
    if (modelSelect) modelSelect.innerHTML = modelList;
  }

  // Select the appropriate model using shared utility function
  let model;
  if (currentApp) {
    // Use the model from parameters if available, otherwise use default
    if (data["content"]["model"] && models.includes(data["content"]["model"])) {
      model = data["content"]["model"];
    } else {
      model = getDefaultModelForApp(currentApp, models);
    }
  }

    // Extract provider name from current app group using shared function if available
    let provider;
    if (typeof getProviderFromGroup === 'function' && currentApp && currentApp["group"]) {
      provider = getProviderFromGroup(currentApp["group"]);
    } else {
      // Fallback implementation if the function is not available
      provider = "OpenAI";
      if (currentApp && currentApp["group"]) {
        const group = currentApp["group"].toLowerCase();
      if (group.includes("anthropic") || group.includes("claude")) {
        provider = "Anthropic";
      } else if (group.includes("gemini") || group.includes("google")) {
        provider = "Google";
      } else if (group.includes("cohere")) {
        provider = "Cohere";
      } else if (group.includes("mistral") || group.includes("pixtral") || group.includes("ministral") || group.includes("magistral") || group.includes("devstral") || group.includes("voxtral") || group.includes("mixtral")) {
        provider = "Mistral";
      } else if (group.includes("perplexity")) {
        provider = "Perplexity";
      } else if (group.includes("deepseek")) {
        provider = "DeepSeek";
      } else if (group.includes("grok") || group.includes("xai")) {
        provider = "xAI";
      } else if (group.includes("ollama")) {
        provider = "Ollama";
      }
    }
    }

    // Update model display with Provider (Model) format
    const modelSelectedEl = $id("model-selected");
    if (modelSelectedEl) {
      if (typeof modelSpec !== 'undefined' && modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
        modelSelectedEl.textContent = `${provider} (${model} - ${modelSpec[model]["reasoning_effort"]})`;
      } else {
        modelSelectedEl.textContent = `${provider} (${model})`;
      }
    }

    const modelSelect = $id("model");
    if (modelSelect) modelSelect.value = model;

    // Use display_name if available, otherwise fall back to app_name
    if (currentApp) {
      const titleEl = $id("base-app-title");
      if (titleEl) titleEl.textContent = currentApp["display_name"] || currentApp["app_name"];
      const iconEl = $id("base-app-icon");
      if (iconEl) iconEl.innerHTML = currentApp["icon"];

      const monadicBadge = $id("monadic-badge");
      $toggle(monadicBadge, currentApp["monadic"]);

      const toolsBadge = $id("tools-badge");
      $toggle(toolsBadge, currentApp["tools"]);

      const descriptionOnly = currentApp["description"] || "";
      if (typeof window.setBaseAppDescription === 'function') {
        window.setBaseAppDescription(descriptionOnly);
      } else {
        const descEl = $id("base-app-desc");
        if (descEl) descEl.innerHTML = descriptionOnly;
      }

      // Trigger badge update after description is set
      if (typeof window.updateAppBadges === 'function') {
        setTimeout(function() {
          window.updateAppBadges(currentApp["app_name"]);
        }, 150);
      }
    }

  const startEl = $id("start");
  if (startEl) startEl.focus();

  updateAppAndModelSelection(data["content"]);
}

// Export for browser environment
window.WsAppDataHandlers = {
  handleElevenLabsVoices,
  handleGeminiVoices,
  handleMistralVoices,
  updateAppAndModelSelection,
  handleAppsMessage,
  handleParametersMessage,
  normalizeGroupId
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsAppDataHandlers;
}
