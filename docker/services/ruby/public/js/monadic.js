// In browser environment, modules are imported via script tags
// These will be assigned when DOM is loaded
let uiUtils;
let formHandlers;

// CRITICAL: Initialize import flags EARLY (before any app change handlers are defined)
// These flags control whether app defaults override imported values during loadParams/proceedWithAppChange
if (typeof window.isProcessingImport === 'undefined') {
  window.isProcessingImport = false;
}
if (typeof window.skipAssistantInitiation === 'undefined') {
  window.skipAssistantInitiation = false;
}

// Shared flag counters to suppress parameter synchronization during server-driven updates
if (typeof window.suppressParamBroadcastCount === 'undefined') {
  window.suppressParamBroadcastCount = 0;
}

function isParamBroadcastSuppressed() {
  return (window.suppressParamBroadcastCount || 0) > 0;
}

function sanitizeParamsForSync(source) {
  if (!source || typeof source !== 'object') return null;
  let clone;
  try {
    clone = JSON.parse(JSON.stringify(source));
  } catch (e) {
    clone = Object.assign({}, source);
  }
  if (!clone || typeof clone !== 'object') return null;
  const blacklist = new Set(["message", "images", "audio", "tts_request", "ws_session_id"]);
  Object.keys(clone).forEach((key) => {
    if (blacklist.has(key)) {
      delete clone[key];
    }
  });
  // Ensure app_name is set so other tabs know which app to load
  if (!clone.app_name) {
    const appsEl = $id("apps");
    if (appsEl && appsEl.value) clone.app_name = appsEl.value;
  }
  // Sync checkbox states to ensure params reflect current UI state
  // This prevents stale values from being broadcast
  // Boolean checkboxes
  const websearchEl = $id("websearch");
  clone.websearch = (websearchEl && websearchEl.checked) || false;
  const easySubmitEl = $id("check-easy-submit");
  clone.easy_submit = (easySubmitEl && easySubmitEl.checked) || false;
  const autoSpeechEl = $id("check-auto-speech");
  clone.auto_speech = (autoSpeechEl && autoSpeechEl.checked) || false;
  const mathEl = $id("math");
  clone.math = (mathEl && mathEl.checked) || false;
  const initiateEl = $id("initiate-from-assistant");
  clone.initiate_from_assistant = (initiateEl && initiateEl.checked) || false;

  // Handle toggle-controlled values
  // If max-tokens-toggle is OFF, don't include max_tokens (use model default)
  const maxTokensToggleEl = $id("max-tokens-toggle");
  if (!maxTokensToggleEl || !maxTokensToggleEl.checked) {
    delete clone.max_tokens;
  } else {
    const maxTokensEl = $id("max-tokens");
    const maxTokensVal = maxTokensEl ? maxTokensEl.value : null;
    if (maxTokensVal) {
      clone.max_tokens = parseInt(maxTokensVal) || maxTokensVal;
    }
  }

  // If context-size-toggle is OFF, don't include context_size (use default)
  const contextSizeToggleEl = $id("context-size-toggle");
  if (!contextSizeToggleEl || !contextSizeToggleEl.checked) {
    delete clone.context_size;
  } else {
    const contextSizeEl = $id("context-size");
    const contextSizeVal = contextSizeEl ? contextSizeEl.value : null;
    if (contextSizeVal) {
      clone.context_size = parseInt(contextSizeVal) || contextSizeVal;
    }
  }

  // Sync current model selection
  const modelEl = $id("model");
  const currentModel = modelEl ? modelEl.value : null;
  if (currentModel) {
    clone.model = currentModel;
  }

  // Sync reasoning effort if enabled
  const reasoningEffortEl = $id("reasoning-effort");
  if (reasoningEffortEl && !reasoningEffortEl.disabled) {
    const reasoningVal = reasoningEffortEl.value;
    if (reasoningVal) {
      clone.reasoning_effort = reasoningVal;
    }
  }
  return clone;
}

function broadcastParamsUpdate(reason = null) {
  if (isParamBroadcastSuppressed()) return;
  if (typeof window.ws === 'undefined' || !window.ws || window.ws.readyState !== WebSocket.OPEN) return;
  if (typeof params === 'undefined' || !params) return;

  const payloadParams = sanitizeParamsForSync(params);
  if (!payloadParams) return;

  const payload = {
    message: "UPDATE_PARAMS",
    params: payloadParams
  };
  if (reason) {
    payload.reason = reason;
  }

  try {
    window.ws.send(JSON.stringify(payload));
  } catch (error) {
    console.warn('[Params Sync] Failed to broadcast params update:', error);
  }
}

window.broadcastParamsUpdate = broadcastParamsUpdate;

// Helper function to get formatted provider name from group
function getProviderFromGroup(group) {
  if (!group) return "OpenAI";
  
  const groupLower = group.toLowerCase();
  if (groupLower.includes("anthropic") || groupLower.includes("claude")) {
    return "Anthropic";
  } else if (groupLower.includes("gemini") || groupLower.includes("google")) {
    return "Google";
  } else if (groupLower.includes("cohere")) {
    return "Cohere";
  } else if (groupLower.includes("mistral")) {
    return "Mistral";
  } else if (groupLower.includes("perplexity")) {
    return "Perplexity";
  } else if (groupLower.includes("deepseek")) {
    return "DeepSeek";
  } else if (groupLower.includes("grok") || groupLower.includes("xai")) {
    return "xAI";
  } else if (groupLower.includes("ollama")) {
    return "Ollama";
  } else {
    return "OpenAI";
  }
}

// Make the function available globally
window.getProviderFromGroup = getProviderFromGroup;

document.addEventListener("DOMContentLoaded", async function () {
  // CRITICAL: Forcefully hide spinner and reset Auto Speech flags on page load
  // This prevents "Processing Audio" from appearing in new tabs
  // New tabs have empty sessionStorage, so should NEVER show processing spinner on load
  try {
    // Hide spinner immediately
    $hide($id("monadic-spinner"));

    // Reset Auto Speech completion flags to prevent sticky spinner
    if (typeof window.setTextResponseCompleted === 'function') {
      window.setTextResponseCompleted(true);
    }
    if (typeof window.setTtsPlaybackStarted === 'function') {
      window.setTtsPlaybackStarted(true);
    }

  } catch (e) {
    console.error('[DOMContentLoaded] Failed to initialize tab state:', e);
  }

  // Restore menu visibility state from localStorage on page load
  // This ensures the menu state persists across zoom operations and page reloads
  try {
    const savedMenuHidden = localStorage.getItem('monadic-menu-hidden');
    if (savedMenuHidden !== null) {
      // Use setTimeout to ensure DOM elements are ready
      setTimeout(() => {
        const toggleBtn = $id("toggle-menu");
        const menuPanel = $id("menu");
        const mainPanel = $id("main");

        if (toggleBtn && menuPanel && mainPanel) {
          const windowWidth = window.innerWidth;
          const isMobile = windowWidth < 600;

          if (savedMenuHidden === 'true') {
            // Restore hidden state
            toggleBtn.classList.add("menu-hidden");
            toggleBtn.setAttribute("aria-expanded", "false");
            toggleBtn.innerHTML = '<i class="fas fa-bars"></i>';

            if (isMobile) {
              $hide(menuPanel);
              $show(mainPanel);
              document.body.classList.remove("menu-visible");
            } else {
              mainPanel.classList.remove("col-md-8");
              mainPanel.classList.add("col-md-12");
              $hide(menuPanel);
            }
          } else {
            // Restore visible state
            toggleBtn.classList.remove("menu-hidden");
            toggleBtn.setAttribute("aria-expanded", "true");
            toggleBtn.innerHTML = '<i class="fas fa-bars"></i>';

            if (isMobile) {
              $show(menuPanel);
              $hide(mainPanel);
              document.body.classList.add("menu-visible");
            } else {
              mainPanel.classList.remove("col-md-12");
              mainPanel.classList.add("col-md-8");
              $show(menuPanel);
            }
          }
        }
      }, 50);
    }
  } catch (e) {
    console.warn('Failed to restore menu state from localStorage on page load:', e);
  }

  // Restore session state and render saved messages
  // Note: Using sessionStorage (not localStorage) for tab isolation
  // Each tab maintains its own independent state
  try {
    if (window.SessionState && typeof window.SessionState.restore === 'function') {
      // Load configuration from API before restoring state
      if (typeof window.SessionState.loadConfig === 'function') {
        await window.SessionState.loadConfig();
      }

      // Restore SessionState from sessionStorage (tab-specific)
      window.SessionState.restore();

      // Set flag to prevent app change confirmation during restoration
      window.isRestoringSession = true;

      // Reset app initialization flags to allow re-initialization
      window.initialAppLoaded = false;
      window.appsMessageCount = 0;

      // Clear import flag to prevent it from interfering with restoration
      window.isImporting = false;
      window.lastImportTime = null;

      // Check if user requested a reset - if so, skip message restoration only
      const shouldSkipMessageRestoration = window.SessionState.shouldForceNewSession();

      // Get restored app name and update lastApp to prevent confirmation dialog
      const restoredApp = window.SessionState.getCurrentApp();
      if (restoredApp) {
        window.lastApp = restoredApp;
        // Also set the app selection if apps dropdown exists
        const appsDropdown = $id("apps");
        if (appsDropdown && appsDropdown.querySelector(`option[value="${restoredApp}"]`)) {
          appsDropdown.value = restoredApp;
        }
      }

      // Get restored model
      const restoredModel = window.SessionState.app.model;
      if (restoredModel) {
        // Store for later use when model dropdown is populated
        window.restoredModel = restoredModel;
      }

      // Render restored messages to UI (skip if reset was requested)
      const restoredMessages = window.SessionState.getMessages();

      if (!shouldSkipMessageRestoration && restoredMessages && restoredMessages.length > 0) {
        restoredMessages.forEach(msg => {
          if (!msg || !msg.role) {
            console.warn('[Session] Skipping invalid message:', msg);
            return;
          }

          // Determine badge (role label) for the message
          let badge = '';
          if (msg.role === 'user') {
            badge = "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>";
          } else if (msg.role === 'assistant') {
            badge = "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>";
          } else if (msg.role === 'system') {
            badge = "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 text-success'>System</span>";
          }

          // Create and append the card
          if (typeof window.createCard === 'function') {
            const cardElement = window.createCard(
              msg.role,
              badge,
              msg.html || msg.content || '',
              msg.lang || 'en',
              msg.mid || '',
              msg.active !== false,  // Default to true if not specified
              msg.images || []
            );
            const discourseEl = $id("discourse");
            if (discourseEl) discourseEl.appendChild(cardElement);
          } else {
            console.warn('[Session] createCard function not available yet, message will not be rendered');
          }
        });

        // Update START button label to "Continue Session" when messages exist
        if (window.i18nReady) {
          window.i18nReady.then(() => {
            const continueText = webUIi18n.t('ui.session.continueSession') || 'Continue Session';
            const startLabelEl = $id("start-label");
            if (startLabelEl) startLabelEl.textContent = continueText;
          });
        } else {
          const startLabelEl = $id("start-label");
          if (startLabelEl) startLabelEl.textContent = 'Continue Session';
        }
      }

      // Clear restoration flag after a delay to allow all UI updates and WebSocket initialization to complete
      setTimeout(() => {
        window.isRestoringSession = false;
      }, 3000);  // Extended to 3 seconds to ensure WebSocket connection is established
    }
  } catch (e) {
    console.error('[Session] Failed to restore session state:', e);
    window.isRestoringSession = false;
  }

  // Initialize Web UI translations if available
  if (typeof webUIi18n !== 'undefined') {
    // Try to get saved language from cookie
    const cookieMatch = document.cookie.match(/ui-language=([^;]+)/);
    if (cookieMatch && cookieMatch[1] && cookieMatch[1] !== 'en') {
      webUIi18n.setLanguage(cookieMatch[1]);
    }
  }
  
  // No longer disable AI User button initially - we'll show an error message if conversation hasn't started
  // Set title with translation when available
  if (window.i18nReady) {
    window.i18nReady.then(() => {
      const aiUserTitle = webUIi18n.t('ui.generateAIUserResponse') || "Generate AI user response based on conversation";
      const aiUserBtn = $id("ai_user");
      if (aiUserBtn) aiUserBtn.setAttribute("title", aiUserTitle);

      // Update role selector options with translations
      const roleSelect = $id("select-role");
      const roleOptions = roleSelect ? roleSelect.querySelectorAll("option") : [];
      if (roleOptions.length > 0) {
        roleOptions[0].textContent = webUIi18n.t('ui.roleOptions.user') || 'User';
        roleOptions[1].textContent = webUIi18n.t('ui.roleOptions.sampleUser') || 'User (to add to past messages)';
        roleOptions[2].textContent = webUIi18n.t('ui.roleOptions.sampleAssistant') || 'Assistant (to add to past messages)';
        roleOptions[3].textContent = webUIi18n.t('ui.roleOptions.sampleSystem') || 'System (to provide additional direction)';
      }
    });
  } else {
    const aiUserBtn = $id("ai_user");
    if (aiUserBtn) aiUserBtn.setAttribute("title", "Generate AI user response based on conversation");
  }
  // Ensure cancel button is hidden on page load using setTimeout for more reliability
  setTimeout(function() {
    $id('cancel_query').style.setProperty('display', 'none', 'important');
  }, 100);
  
  // Get modules from window if available or install shims
  if (typeof uiUtils === 'undefined') {
    if (typeof window.uiUtils !== 'undefined') {
      uiUtils = window.uiUtils;
    } else if (window.shims && window.shims.uiUtils) {
      console.warn('Using UI utilities shim');
      uiUtils = window.shims.uiUtils;
    }
  }
  
  if (typeof formHandlers === 'undefined') {
    if (typeof window.formHandlers !== 'undefined') {
      formHandlers = window.formHandlers;
    } else if (window.shims && window.shims.formHandlers) {
      console.warn('Using form handlers shim');
      formHandlers = window.shims.formHandlers;
    }
  }
  
  // Use installShims function if available (comprehensive approach)
  if (window.installShims && (!uiUtils || !formHandlers)) {
    window.installShims();
    
    // Get the modules after installing shims
    if (!uiUtils && window.uiUtils) {
      uiUtils = window.uiUtils;
    }
    
    if (!formHandlers && window.formHandlers) {
      formHandlers = window.formHandlers;
    }
  }
  
  // Final fallback - load modules dynamically if still not available
  if (!uiUtils || !uiUtils.setupTextarea) {
    console.warn('UI utilities still not available, attempting dynamic import');
    
    // Try to dynamically load the missing module
    const script = document.createElement('script');
    script.src = 'js/monadic/ui-utilities.js?' + (new Date().getTime());
    script.onload = function() {
      if (typeof window.uiUtils !== 'undefined') {
        uiUtils = window.uiUtils;
      }
    };
    document.head.appendChild(script);
  }
  
  if (!formHandlers) {
    console.warn('Form handlers still not available, attempting dynamic import');
    
    // Try to dynamically load the missing module
    const script = document.createElement('script');
    script.src = 'js/monadic/form-handlers.js?' + (new Date().getTime());
    script.onload = function() {
      if (typeof window.formHandlers !== 'undefined') {
        formHandlers = window.formHandlers;
      }
    };
    document.head.appendChild(script);
  }

  // Apply visibility for URL/Doc buttons based on backend capabilities
  try {
    fetch('/api/capabilities')
      .then(function (res) { return res.ok ? res.json() : null; })
      .then(function (cap) {
        if (!cap || cap.success === false) return;
        // Always show #url and #doc buttons - backend handles Selenium/Tavily routing
        const urlBtn = $id('url');
        $show(urlBtn); const docBtn = $id('doc');
        $show(docBtn); // Mistral/Cohere TTS/STT are enabled via /api/ai_user_defaults (more reliable)
      })
      .catch(function () { /* ignore */ });
  } catch (e) { /* ignore */ }
  
  // Directly get textareas and set them up - avoid storing array reference
  const initialHeight = 100;
  
  // Process each textarea individually to avoid keeping references
  const messageTextarea = $id('message');
  if (messageTextarea) {
    uiUtils.setupTextarea(messageTextarea, initialHeight);
  }
  
  const initialPromptTextarea = $id('initial-prompt');
  if (initialPromptTextarea) {
    uiUtils.setupTextarea(initialPromptTextarea, initialHeight);
  }
  
  const aiUserInitialPromptTextarea = $id('ai-user-initial-prompt');
  if (aiUserInitialPromptTextarea) {
    uiUtils.setupTextarea(aiUserInitialPromptTextarea, initialHeight);
  }

  document.addEventListener('hide.bs.modal', function (_event) {
    if (document.activeElement) {
      document.activeElement.blur();
    }
  });

  // if on Firefox, disable the #voice-panel
  if (runningOnFirefox) {
    const voicePanel = $id("voice-panel");
    $hide(voicePanel); }
});

// Fallback implementations are now in shims.js

// ============================================================================
// Screenshot Lightbox state
// (file-level scope to ensure accessibility from all event handlers)
// ============================================================================
var lightboxImages = [];
var lightboxIndex = 0;

function updateLightbox() {
  if (lightboxImages.length === 0) return;
  const lightboxImage = $id("lightboxImage");
  if (lightboxImage) lightboxImage.setAttribute("src", lightboxImages[lightboxIndex]);
  const lightboxCounter = $id("lightboxCounter");
  const lightboxPrev = $id("lightboxPrev");
  const lightboxNext = $id("lightboxNext");
  if (lightboxImages.length > 1) {
    if (lightboxCounter) {
      lightboxCounter.textContent = (lightboxIndex + 1) + " / " + lightboxImages.length;
      $show(lightboxCounter);
    }
    $toggle(lightboxPrev, lightboxIndex > 0);
    $toggle(lightboxNext, lightboxIndex < lightboxImages.length - 1);
  } else {
    $hide(lightboxCounter); $hide(lightboxPrev); $hide(lightboxNext); }
}

// --- Perceptual hash helpers for visual image dedup ---
function imagePerceptualHash(imgEl, size) {
  size = size || 16;
  try {
    var c = document.createElement("canvas");
    c.width = size;
    c.height = size;
    var ctx = c.getContext("2d");
    ctx.drawImage(imgEl, 0, 0, size, size);
    var data = ctx.getImageData(0, 0, size, size).data;
    var grays = [];
    for (var i = 0; i < data.length; i += 4) {
      grays.push(0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]);
    }
    var avg = grays.reduce(function(a, b) { return a + b; }, 0) / grays.length;
    return grays.map(function(g) { return g > avg ? "1" : "0"; }).join("");
  } catch (e) {
    return null;
  }
}

function hashSimilarity(h1, h2) {
  if (!h1 || !h2 || h1.length !== h2.length) return 0;
  var match = 0;
  for (var i = 0; i < h1.length; i++) {
    if (h1[i] === h2[i]) match++;
  }
  return match / h1.length;
}

document.addEventListener("DOMContentLoaded", function () {

  // ── Collapsible Settings Header helpers ─────────────────

  // Update the summary bar content with current settings
  function updateConfigSummary() {
    var appsSelect = $id("apps");
    var appText = (appsSelect && appsSelect.options[appsSelect.selectedIndex]) ? appsSelect.options[appsSelect.selectedIndex].text : "Chat";
    var appIcon = "";
    var iconEl = document.querySelector("#app-select-icon");
    if (iconEl) appIcon = iconEl.innerHTML;
    var modelSelect = $id("model");
    var modelName = modelSelect ? modelSelect.value : "";

    var summaryAppIcon = $id("summary-app-icon");
    if (summaryAppIcon) summaryAppIcon.innerHTML = appIcon;
    var summaryAppName = $id("summary-app-name");
    if (summaryAppName) summaryAppName.textContent = appText;
    var summaryModelName = $id("summary-model-name");
    if (summaryModelName) summaryModelName.textContent = modelName;

    var indicators = "";
    var websearchCb = $id("websearch");
    if (websearchCb && websearchCb.checked) indicators += '<span class="badge bg-info me-1">Web</span>';
    var mathCb = $id("math");
    if (mathCb && mathCb.checked) indicators += '<span class="badge bg-secondary me-1">Math</span>';
    var reasoningEffortSel = $id("reasoning-effort");
    var re = reasoningEffortSel ? reasoningEffortSel.value : "";
    if (reasoningEffortSel && !reasoningEffortSel.disabled && re && re !== "none" && re !== "disabled") {
      indicators += '<span class="badge bg-warning text-dark me-1">' + re + '</span>';
    }
    var summaryIndicators = $id("summary-indicators");
    if (summaryIndicators) summaryIndicators.innerHTML = indicators;
  }

  // Lock settings that should not change during an active session
  function lockSessionSettings() {
    var appsEl = $id("apps");
    if (appsEl) appsEl.disabled = true;
    var initialPromptEl = $id("initial-prompt");
    if (initialPromptEl) initialPromptEl.disabled = true;
    var aiUserPromptEl = $id("ai-user-initial-prompt");
    if (aiUserPromptEl) aiUserPromptEl.disabled = true;
    var initiateEl = $id("initiate-from-assistant");
    if (initiateEl) initiateEl.disabled = true;
  }

  // Unlock settings when session is reset
  function unlockSessionSettings() {
    var appsEl = $id("apps");
    if (appsEl) appsEl.disabled = false;
    var initialPromptEl = $id("initial-prompt");
    if (initialPromptEl) initialPromptEl.disabled = false;
    var aiUserPromptEl = $id("ai-user-initial-prompt");
    if (aiUserPromptEl) aiUserPromptEl.disabled = false;
    var initiateEl = $id("initiate-from-assistant");
    if (initiateEl) initiateEl.disabled = false;
  }

  // Collapse settings and show conversation (used when starting/continuing session)
  function enterConversationMode() {
    var bsCollapse = bootstrap.Collapse.getOrCreateInstance($id("config-body"), { toggle: false });
    bsCollapse.hide();
    var configSummary = $id("config-summary");
    $show(configSummary); var configActions = $id("config-actions");
    $hide(configActions); var mainPanelEl = $id("main-panel");
    if (mainPanelEl) { mainPanelEl.classList.remove("d-none"); $show(mainPanelEl); }
    lockSessionSettings();
    updateConfigSummary();
  }

  // Expand settings and hide conversation (used when resetting)
  function enterSettingsMode() {
    var bsCollapse = bootstrap.Collapse.getOrCreateInstance($id("config-body"), { toggle: false });
    bsCollapse.show();
    var configSummary = $id("config-summary");
    $hide(configSummary); var configActions = $id("config-actions");
    $show(configActions); var mainPanelEl = $id("main-panel");
    if (mainPanelEl) { mainPanelEl.classList.add("d-none"); $hide(mainPanelEl); }
    unlockSessionSettings();
  }

  // Expose for use in other modules
  window.updateConfigSummary = updateConfigSummary;
  window.enterConversationMode = enterConversationMode;
  window.enterSettingsMode = enterSettingsMode;

  // Don't store persistent references to DOM elements
  // Access them only when needed

  // button#browser is disabled when the system has started
  var browserBtn = $id("browser");
  if (browserBtn) browserBtn.disabled = true;

  ["send", "clear", "voice", "tts-voice", "ui-language", "prompt-toggle-assistant", "prompt-toggle-aiuser", "check-auto-speech", "check-easy-submit"].forEach(function(id) {
    var el = $id(id);
    if (el) el.disabled = true;
  });
  // Keep TTS speed control always enabled as it's used by multiple TTS providers
  var ttsSpeedEl = $id("tts-speed");
  if (ttsSpeedEl) ttsSpeedEl.disabled = false;

  //////////////////////////////
  // UI event handlers
  //////////////////////////////

  // Use restored app if available, otherwise use default
  let lastApp = window.lastApp || (typeof defaultApp !== 'undefined' ? defaultApp : "Chat");

  // Common UI operations - centralized for consistency
  const UIOperations = {
    showMain: function() {
      var el = $id("main");
      $show(el); return this;
    },
    hideMain: function() {
      var el = $id("main");
      $hide(el); return this;
    },
    showMenu: function() {
      var el = $id("menu");
      $show(el); return this;
    },
    hideMenu: function() {
      var el = $id("menu");
      $hide(el); return this;
    },
    showBoth: function() {
      this.showMain().showMenu();
      return this;
    },
    setMainColumns: function(removeClass, addClass) {
      var el = $id("main");
      if (el) {
        el.classList.remove(removeClass);
        el.classList.add(addClass);
      }
      return this;
    }
  };
  
  // Make available globally for reuse
  window.UIOperations = UIOperations;

  // Consolidate event handlers for toggles
  function setupToggleHandlers() {
    var autoScrollToggle = $id("auto-scroll-toggle");
    if (autoScrollToggle) {
      autoScrollToggle.addEventListener("change", function () {
        autoScroll = this.checked;
      });
    }

    var maxTokensToggle = $id("max-tokens-toggle");
    if (maxTokensToggle) {
      maxTokensToggle.addEventListener("change", function () {
        var maxTokensInput = $id("max-tokens");
        if (maxTokensInput) maxTokensInput.disabled = !this.checked;
      });
    }

    var contextSizeToggle = $id("context-size-toggle");
    if (contextSizeToggle) {
      contextSizeToggle.addEventListener("change", function () {
        var contextSizeInput = $id("context-size");
        if (contextSizeInput) contextSizeInput.disabled = !this.checked;
      });
    }
  }

  // Setup optimized event listeners
  function setupEventListeners() {
    // Make AI User button always visible
    setTimeout(function() {
      var aiUserEl = $id("ai_user");
      $show(aiUserEl); }, 1000);
    
    // --- AI User defaults (SSOT) ---
    let aiUserDefaults = null;
    async function fetchAiUserDefaults() {
      try {
        const resp = await fetch('/api/ai_user_defaults');
        if (!resp.ok) return null;
        const data = await resp.json();
        if (data && data.success) return data.defaults;
        return null;
      } catch (_) { return null; }
    }

    function getDefaultModelFromSSOT(provider) {
      if (!aiUserDefaults) return null;
      const ent = aiUserDefaults[provider];
      return ent && ent.default_model ? ent.default_model : null;
    }

    // Setup AI User provider selector - updated to filter by available API keys
    var aiUserProviderEl = $id("ai_user_provider");
    if (aiUserProviderEl) {
      aiUserProviderEl.addEventListener("change", function() {
        const provider = this.value;
        setCookie("ai_user_provider", provider, 30);
        updateProviderStyle(provider);
        // Update badge with model and reasoning effort when available
        if (!setAiUserBadge()) {
          const providerName = this.options[this.selectedIndex].text;
          const modelEl = $id("model");
          const fallbackModel = getDefaultModelFromSSOT(provider) || (modelEl ? modelEl.value : '') || getTranslation('ui.notConfigured','Not configured');
          const aiUserModelEl = $id("ai-user-model");
          if (aiUserModelEl) aiUserModelEl.textContent = `${providerName} (${fallbackModel})`;
        }
      });
    }
    
    // Function that does nothing now - we're keeping the default btn-warning style
    function updateProviderStyle(provider) {
      // Intentionally left empty - we want to maintain the original btn-warning style
    }
    
    // Removed hardcoded getDefaultModelForProvider; use SSOT via /api/ai_user_defaults instead
    
    
    // Function to update available providers in dropdown based on API keys
    // Export to window scope for access from websocket.js
    window.updateAvailableProviders = function() {
      // Hide all options first
      var providerSelect = $id("ai_user_provider");
      if (!providerSelect) return;
      var allOptions = providerSelect.querySelectorAll("option");
      allOptions.forEach(function(opt) { $hide(opt); });

      // Loop through providers to check which ones have API keys available
      // Show by apps groups first (backward compatibility)

      // Check for other providers' API keys
      for (const [key, app] of Object.entries(apps)) {
        if (!app.group) continue;

        const group = app.group.toLowerCase();

        // Match provider dropdown options to available app groups
        var optVal = null;
        if (group.includes("anthropic")) {
          optVal = 'anthropic';
        } else if (group.includes("gemini") || group.includes("google")) {
          optVal = 'gemini';
        } else if (group.includes("cohere")) {
          optVal = 'cohere';
        } else if (group.includes("mistral") || group.includes("pixtral") || group.includes("ministral") || group.includes("magistral") || group.includes("devstral") || group.includes("voxtral") || group.includes("mixtral")) {
          optVal = 'mistral';
        } else if (group.includes("deepseek")) {
          optVal = 'deepseek';
        } else if (group.includes("grok") || group.includes("xai")) {
          optVal = 'grok';
        } else if (group.includes("perplexity")) {
          optVal = 'perplexity';
        }
        if (optVal) {
          var opt = providerSelect.querySelector("option[value='" + optVal + "']");
          $show(opt); }
      }

      // Additionally filter by SSOT has_key if available
      if (aiUserDefaults) {
        const map = {
          'openai':'openai','anthropic':'anthropic','gemini':'gemini','cohere':'cohere','mistral':'mistral','deepseek':'deepseek','grok':'grok','perplexity':'perplexity'
        };
        Object.keys(map).forEach(val => {
          const ent = aiUserDefaults[val];
          var opt = providerSelect.querySelector("option[value='" + val + "']");
          if (opt) {
            $toggle(opt, ent && ent.has_key);
          }
        });
      }

      // If the currently selected provider is not available, select first available
      const currentProvider = providerSelect.value;
      var currentOpt = providerSelect.querySelector("option[value='" + currentProvider + "']");
      if (!currentOpt || currentOpt.style.display === 'none') {
        // Select first visible option
        var firstVisible = providerSelect.querySelector("option:not([style*='display: none'])");
        if (!firstVisible) {
          // Fallback: find option without inline display style
          firstVisible = Array.from(providerSelect.querySelectorAll("option")).find(function(o) { return o.style.display !== 'none'; });
        }
        if (firstVisible) {
          providerSelect.value = firstVisible.value;
          setCookie("ai_user_provider", firstVisible.value, 30);
        }
      }

    };

    // Enable TTS/STT provider options whose backing API keys are configured.
    // Kept separate from updateAvailableProviders so that it still runs even
    // when the ai_user_provider element is absent (which would cause that
    // function to early-return before reaching these options).
    window.applyTtsSttEnablement = function(defs) {
      if (!defs) return;
      if (defs.mistral && defs.mistral.has_key) {
        var mistralTtsOpt = $id("mistral-tts-provider-option");
        if (mistralTtsOpt) mistralTtsOpt.disabled = false;
        var mistralSttOpt = $id("mistral-stt-voxtral");
        if (mistralSttOpt) mistralSttOpt.disabled = false;
      }
      if (defs.cohere && defs.cohere.has_key) {
        var cohereSttOpt = $id("cohere-stt-transcribe");
        if (cohereSttOpt) cohereSttOpt.disabled = false;
      }
      if (defs.grok && defs.grok.has_key) {
        var grokTtsOpt = $id("grok-tts-provider-option");
        if (grokTtsOpt) grokTtsOpt.disabled = false;
      }
    };
    
    // Helper to compute and set the AI User badge text robustly
    function setAiUserBadge() {
      var providerSel = $id("ai_user_provider");
      if (!providerSel) return false;
      const provider = providerSel.value;
      if (!provider) return false;
      const providerName = providerSel.options[providerSel.selectedIndex].text;
      const ssotModel = getDefaultModelFromSSOT(provider);
      var modelSel = $id("model");
      const currentModel = modelSel ? modelSel.value : '';
      const model = ssotModel || currentModel;
      if (model && providerName) {
        // NOTE: Reasoning effort is intentionally NOT displayed for AI User
        // AI User has thinking/reasoning disabled for faster, simpler responses
        var aiUserModelEl = $id("ai-user-model");
        if (aiUserModelEl) aiUserModelEl.textContent = providerName + ' (' + model + ')';
        return true;
      }
      return false;
    }

    // Load SSOT defaults then initialize provider and badge (no async IIFE for compatibility)
    fetchAiUserDefaults().then(function(defs){
      aiUserDefaults = defs || null;
      window.aiUserDefaults = aiUserDefaults;
      window.updateAvailableProviders();
      window.applyTtsSttEnablement(aiUserDefaults);
      var providerSel = $id("ai_user_provider");
      const savedProvider = getCookie('ai_user_provider');
      var chosen = savedProvider;
      if (providerSel) {
        var chosenOpt = chosen ? providerSel.querySelector("option[value='"+chosen+"']") : null;
        if (!chosen || !chosenOpt || chosenOpt.style.display === 'none') {
          var firstVisible = Array.from(providerSel.querySelectorAll("option")).find(function(o) { return o.style.display !== 'none'; });
          if (firstVisible) {
            chosen = firstVisible.value;
            providerSel.value = firstVisible.value;
            setCookie('ai_user_provider', firstVisible.value, 30);
          }
        } else {
          providerSel.value = chosen;
        }
      }
      var aiUserModelEl = $id("ai-user-model");
      if (chosen) {
        if (!setAiUserBadge()) {
          if (aiUserModelEl) aiUserModelEl.textContent = getTranslation('ui.notConfigured','Not configured');
        }
      } else {
        if (aiUserModelEl) aiUserModelEl.textContent = getTranslation('ui.notConfigured','Not configured');
      }
    }).catch(function(){
      // fallback: just update available providers based on apps
      window.updateAvailableProviders();
      // Best-effort label update using current app model
      var providerSel = $id("ai_user_provider");
      if (providerSel) {
        var firstVisible = Array.from(providerSel.querySelectorAll("option")).find(function(o) { return o.style.display !== 'none'; });
        if (firstVisible) {
          providerSel.value = firstVisible.value;
          if (!setAiUserBadge()) {
            var aiUserModelEl = $id("ai-user-model");
            if (aiUserModelEl) aiUserModelEl.textContent = getTranslation('ui.notConfigured','Not configured');
          }
        }
      }
    });

    // Robust initialization: observe #model for population and update badge when ready
    (function ensureBadgeOnModelReady(){
      try {
        const modelSel = $id('model');
        if (!modelSel || typeof MutationObserver === 'undefined') return; // Defensive
        const observer = new MutationObserver(() => {
          // Attempt to set badge whenever options or value change
          if (setAiUserBadge()) {
            observer.disconnect();
          }
        });
        observer.observe(modelSel, { childList: true, subtree: true, attributes: true, attributeFilter: ['value'] });
        // Also do a few timed retries in case observer misses
        let tries = 0;
        const tick = setInterval(() => {
          tries += 1;
          if (setAiUserBadge() || tries >= 10) {
            clearInterval(tick);
            try { observer.disconnect(); } catch(_) { console.warn("[MutationObserver] Disconnect failed:", _); }
          }
        }, 300);
      } catch (e) {
        // Last resort timed attempt without observer
        setTimeout(setAiUserBadge, 1200);
      }
    })();
    
    // Set up model change handler to update the AI Assistant info badge
    var modelChangeEl = $id("model");
    if (modelChangeEl) {
      modelChangeEl.addEventListener("change", function() {
        const selectedModel = this.value;
        // Extract provider from params.group first (synced in proceedWithAppChange), fallback to current app group
        let provider = "OpenAI";
        var appsEl = $id("apps");
        const currentApp = appsEl ? appsEl.value : '';
        const grp = (typeof params !== 'undefined' && params && params["group"]) ? params["group"] : (apps[currentApp] && apps[currentApp].group ? apps[currentApp].group : null);
        if (grp) {
          const group = grp.toLowerCase();
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
          }
        }
        // Update the badge in the AI User section with provider name and model
        const aiAssistantText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.aiAssistant') : 'AI Assistant';
        var aiAssistantInfo = $id("ai-assistant-info");
        if (aiAssistantInfo) {
          aiAssistantInfo.innerHTML = '<span style="color: #DC4C64;" data-i18n="ui.aiAssistant">' + aiAssistantText + '</span> &nbsp;<span class="ai-assistant-provider" style="display: inline-block; padding: 0.25rem 0.5rem; border: 1px solid #dee2e6; border-radius: 0.375rem; background-color: #f8f9fa; font-weight: normal; min-width: 120px; text-align: left; font-size: 0.875rem; line-height: 1.5; height: calc(1.5em + 0.5rem + 2px); vertical-align: middle;">' + provider + '</span>';
          aiAssistantInfo.setAttribute("data-model", selectedModel);
        }

        // Update model-selected text to follow the new multiline format
        var modelSelectedEl = $id("model-selected");
        if (modelSelectedEl) {
          if (modelSpec[selectedModel] && modelSpec[selectedModel].hasOwnProperty("reasoning_effort")) {
            var reasoningEffortEl = $id("reasoning-effort");
            const reasoningEffort = reasoningEffortEl ? reasoningEffortEl.value : '';
            modelSelectedEl.textContent = `${provider} (${selectedModel} - ${reasoningEffort})`;
          } else {
            modelSelectedEl.textContent = `${provider} (${selectedModel})`;
          }
        }
      });
    }
    
    // Initial availability update will be done when models are loaded
    
    // Setup AI User button
    var aiUserButton = $id("ai_user");
    if (aiUserButton) {
      aiUserButton.onclick = function () {
        // Force enable AI User
        params["ai_user"] = "true";

        // Get the provider from the selector
        var providerSel = $id("ai_user_provider");
        const provider = providerSel ? providerSel.value : '';
        params["ai_user_provider"] = provider;

        // Create an AI User query
        let ai_user_query = {
          message: "AI_USER_QUERY",
          contents: {
            params: params,
            messages: messages.map(msg => {
              return { "role": msg["role"], "text": msg["text"] }
            })
          }
        };

        // Send the request via WebSocket
        ws.send(JSON.stringify(ai_user_query));

        // Ensure the button stays visible
        $show(this);

        // Disable the button temporarily to prevent double-clicking
        this.disabled = true;

        // Provide better user feedback
        const providerName = providerSel ? providerSel.options[providerSel.selectedIndex].text : '';
        const analyzingText = getTranslation('ui.messages.analyzingConversation', 'Analyzing conversation');
        const alertMessage = `<i class='fas fa-spinner fa-spin'></i> ${analyzingText}`;
        setAlert(alertMessage, "warning");

        // Disable UI elements manually here to ensure they're disabled even if websocket events fail
        ["message", "send", "clear", "image-file", "voice", "doc", "url", "audio-upload", "select-role"].forEach(function(id) {
          var el = $id(id);
          if (el) el.disabled = true;
        });
        $id('cancel_query').style.setProperty('display', 'flex', 'important');

        // Show the spinner with robot icon animation
        var spinnerEl = $id("monadic-spinner");
        if (spinnerEl) spinnerEl.style.display = "block";
        const aiUserText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ?
          webUIi18n.t('ui.messages.spinnerGeneratingAIUser') : 'Generating AI user response';
        var spinnerSpan = spinnerEl ? spinnerEl.querySelector("span") : null;
        if (spinnerSpan) spinnerSpan.innerHTML = `<i class="fas fa-robot fa-pulse"></i> ${aiUserText}`;

        // Enable button after a delay to prevent rapid clicking
        setTimeout(() => {
          var btn = $id("ai_user");
          if (btn) btn.disabled = false;
        }, 3000);
      };
    }
  
    // Event delegation for dynamically added elements
    document.addEventListener("click", function (e) {
      var t = e.target.closest(".contBtn");
      if (t) {
        var msgEl = $id("message");
        if (msgEl) msgEl.value = "Continue";
        var sendBtn = $id("send");
        if (sendBtn) sendBtn.click();
      }
    });

    // Add MutationObserver for handling image errors, dedup, and screenshot lightbox
    // Store the observer in the window object to ensure it can be accessed globally for cleanup
    window.imageErrorObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.addedNodes.length) {
          mutation.addedNodes.forEach((node) => {
            if (node.nodeType === 1 && node.classList.contains('card')) {
              // Phase 1: Deduplicate images with the same src (URL) within this card
              const seenSrcs = new Set();
              node.querySelectorAll(".generated_image img").forEach(function(imgNode) {
                const src = imgNode.getAttribute("src");
                if (src && seenSrcs.has(src)) {
                  var parentGenImg = imgNode.closest(".generated_image");
                  if (parentGenImg) parentGenImg.remove();
                  return; // continue to next
                }
                if (src) seenSrcs.add(src);
              });

              // Phase 2: Set up load handlers for visual dedup, DPR sizing, errors, click
              const cardHashes = [];
              node.querySelectorAll(".generated_image img").forEach(function(imgEl) {

                // Error handler (one-time)
                imgEl.addEventListener("error", function onError() {
                  var errorDiv = document.createElement("div");
                  errorDiv.className = "image-error-message";
                  errorDiv.textContent = "NO IMAGE GENERATED";
                  errorDiv.style.color = '#dc3545';
                  imgEl.replaceWith(errorDiv);
                  imgEl.removeEventListener("error", onError);
                }, { once: true });

                // On load: visual dedup + DPR-aware sizing (one-time)
                imgEl.addEventListener("load", function onLoad() {
                  // Visual similarity dedup using perceptual hash
                  var hash = imagePerceptualHash(imgEl);
                  if (hash) {
                    for (var i = 0; i < cardHashes.length; i++) {
                      if (hashSimilarity(hash, cardHashes[i]) >= 0.90) {
                        // Near-duplicate — remove this image
                        var parentGenImg = imgEl.closest(".generated_image");
                        if (parentGenImg) parentGenImg.remove();
                        return;
                      }
                    }
                    cardHashes.push(hash);
                  }

                  // DPR-aware display width for screenshot images
                  var dpr = parseInt(imgEl.dataset.screenshotDpr) || 0;
                  if (dpr > 1 && imgEl.naturalWidth > 0) {
                    imgEl.style.width = (imgEl.naturalWidth / dpr) + "px";
                  }
                  imgEl.removeEventListener("load", onLoad);
                }, { once: true });

                // Handle already-cached images (browser may not fire load)
                if (imgEl.complete && imgEl.naturalWidth > 0) {
                  $dispatch(imgEl, "load");
                }

                // Screenshot lightbox: add click handler directly to each image
                // Skip images marked by image_generation apps (data-action="open")
                if (!imgEl.getAttribute("data-action")) {
                  imgEl.addEventListener("click", function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    var cardEl = this.closest(".card");
                    lightboxImages = [];
                    if (cardEl) {
                      cardEl.querySelectorAll(".generated_image img:not([data-action])").forEach(function(img) {
                        lightboxImages.push(img.getAttribute("src"));
                      });
                    }
                    lightboxIndex = lightboxImages.indexOf(this.getAttribute("src"));
                    if (lightboxIndex < 0) lightboxIndex = 0;
                    updateLightbox();
                    var lightboxEl = $id("screenshotLightbox");
                    if (lightboxEl) bootstrap.Modal.getOrCreateInstance(lightboxEl).show();
                  });
                }
              });
            }
          });
        }
      });
    });

    // Start observing the discourse element
    const discourseElement = $id('discourse');
    if (discourseElement) {
      window.imageErrorObserver.observe(discourseElement, {
        childList: true,
        subtree: true
      });
    }
    
    // Clean up the observer when the page is unloaded
    window.addEventListener("beforeunload", function() {
      if (window.imageErrorObserver) {
        window.imageErrorObserver.disconnect();
      }
      // Clean up all other observers
      if (window.monadicObservers && window.monadicObservers.length > 0) {
        window.monadicObservers.forEach(observer => {
          if (observer && typeof observer.disconnect === 'function') {
            observer.disconnect();
          }
        });
        window.monadicObservers = [];
      }
    });

    document.addEventListener("click", function (e) {
      var yesTarget = e.target.closest(".yesBtn");
      if (yesTarget) {
        var msgEl = $id("message");
        if (msgEl) msgEl.value = "Yes";
        var sendBtn = $id("send");
        if (sendBtn) sendBtn.click();
        return;
      }
      var noTarget = e.target.closest(".noBtn");
      if (noTarget) {
        var msgEl = $id("message");
        if (msgEl) msgEl.value = "No";
        var sendBtn = $id("send");
        if (sendBtn) sendBtn.click();
        return;
      }
      var imgTarget = e.target.closest(".card-text img");
      if (imgTarget) {
        window.open().document.write(imgTarget.outerHTML);
        return;
      }
    });
    // Improved scroll event - store timer in dataset to prevent leaks
    var _mainScrollTimer = null;
    var mainPanelScroll = $id("main");
    if (mainPanelScroll) {
      mainPanelScroll.addEventListener("scroll", function () {
        // Clear any existing timer
        if (_mainScrollTimer) {
          clearTimeout(_mainScrollTimer);
        }
        // Store new timer reference
        _mainScrollTimer = setTimeout(function() {
          // Use the UI utilities module if available, otherwise fall back
          if (uiUtils && uiUtils.adjustScrollButtons) {
            uiUtils.adjustScrollButtons();
          } else {
            adjustScrollButtonsFallback();
          }
        }, 100);
      });
    }

    // Track previous window width to detect significant changes
    let previousWidth = window.innerWidth;
    
    // Improved resize event with immediate and delayed response
    var _windowResizeTimer = null;
    window.addEventListener("resize", function () {
      const currentWidth = window.innerWidth;

      // Check if we crossed the mobile/desktop boundary (600px)
      const wasMobile = previousWidth < 600;
      const isMobile = currentWidth < 600;
      const crossedBoundary = wasMobile !== isMobile;

      // Immediate fix if we crossed the mobile/desktop boundary
      if (crossedBoundary) {
        fixLayoutAfterResize();
      }

      // Clear existing timer
      if (_windowResizeTimer) {
        clearTimeout(_windowResizeTimer);
      }

      // Set new timer for final adjustments
      _windowResizeTimer = setTimeout(function() {
        // Final layout fix
        fixLayoutAfterResize();

        // Force nav reflow to apply correct styles
        var navEl = $id('main-nav');
        if (navEl) {
          $hide(navEl);
          navEl.offsetHeight; // force reflow
          $show(navEl);
        }

        // Update previous width
        previousWidth = currentWidth;
      }, 250);
    });

    // Clean up timers when window is unloaded
    window.addEventListener("beforeunload", function() {
      // Clean up any stored timers
      if (_mainScrollTimer) {
        clearTimeout(_mainScrollTimer);
        _mainScrollTimer = null;
      }

      if (_windowResizeTimer) {
        clearTimeout(_windowResizeTimer);
        _windowResizeTimer = null;
      }
    });
  }

  // Function to fix layout after window resize
  function fixLayoutAfterResize() {
    try {
      const windowWidth = window.innerWidth;
      const isMobile = window.UIConfig ? window.UIConfig.isMobileView() : windowWidth < 600;
      const toggleBtn = $id("toggle-menu");
      const mainPanel = $id("main");
      const menuPanel = $id("menu");

      // Check if essential elements exist
      if (!toggleBtn || !mainPanel || !menuPanel) {
        console.warn("fixLayoutAfterResize: Required elements not found");
        return;
      }

      // Restore menu state from localStorage to persist across zoom operations
      // This ensures the menu visibility state is independent of zoom operations
      try {
        const savedMenuHidden = localStorage.getItem('monadic-menu-hidden');
        if (savedMenuHidden === 'true') {
          toggleBtn.classList.add("menu-hidden");
        } else if (savedMenuHidden === 'false') {
          toggleBtn.classList.remove("menu-hidden");
        }
        // If null (not set), keep current class state
      } catch (e) {
        console.warn('Failed to restore menu state from localStorage:', e);
      }

    if (isMobile) {
      // Mobile layout
      const isMenuHidden = toggleBtn.classList.contains("menu-hidden");

      if (isMenuHidden) {
        // Menu should be hidden, main should be visible
        $hide(menuPanel);
        $show(mainPanel);
        mainPanel.classList.remove("col-md-8");
        mainPanel.classList.add("col-md-12");
        document.body.classList.remove("menu-visible");
        // icon stays the same; active style controlled by menu-hidden class
      } else {
        // Menu should be visible, main should be hidden
        $show(menuPanel);
        $hide(mainPanel);
        document.body.classList.add("menu-visible");
      }

      // Reset any inline styles that might have been applied
      toggleBtn.style.position = "";
      toggleBtn.style.top = "";
      toggleBtn.style.right = "";
      $show(toggleBtn);
    } else {
      // Desktop layout
      document.body.classList.remove("menu-visible");

      if (menuPanel.style.display !== 'none') {
        // Both panels visible
        mainPanel.classList.remove("col-md-12");
        mainPanel.classList.add("col-md-8");
        $show(mainPanel);
        $show(menuPanel);
        toggleBtn.classList.remove("menu-hidden");
      } else {
        // Only main panel visible
        mainPanel.classList.remove("col-md-8");
        mainPanel.classList.add("col-md-12");
        $show(mainPanel);
        $hide(menuPanel);
        toggleBtn.classList.add("menu-hidden");
      }
    }

    // Force reflow to ensure proper rendering
    document.body.offsetHeight;

      // Update scroll buttons position
      if (uiUtils && uiUtils.adjustScrollButtons) {
        uiUtils.adjustScrollButtons();
      } else if (typeof adjustScrollButtonsFallback === 'function') {
        adjustScrollButtonsFallback();
      }
    } catch (error) {
      if (window.ErrorHandler) {
        window.ErrorHandler.log({
          category: window.ErrorHandler.CATEGORIES.UI,
          message: 'Error in fixLayoutAfterResize',
          details: error.message
        });
      } else {
        console.error("Error in fixLayoutAfterResize:", error);
      }
      // Attempt basic recovery
      var mainEl = $id("main");
      $show(mainEl); var toggleEl = $id("toggle-menu");
      $show(toggleEl); }
  }

  // Fallback function for scroll buttons when uiUtils is not available
  function adjustScrollButtonsFallback() {
    const mainPanel = $id("main");
    const windowWidth = window.innerWidth;
    const isMobile = windowWidth < 600;
    const isMedium = windowWidth < 768; // Bootstrap md breakpoint
    var backToTop = $id("back_to_top");
    var backToBottom = $id("back_to_bottom");

    // On mobile and medium screens where menu/content are exclusive, check toggle state
    if (isMobile || isMedium) {
      // Check if toggle button has menu-hidden class
      const toggleBtn = $id("toggle-menu");
      const isMenuHidden = toggleBtn && toggleBtn.classList.contains("menu-hidden");

      if (!isMenuHidden) {
        // Menu is showing, hide scroll buttons
        $hide(backToTop); $hide(backToBottom); return;
      }
    }

    // Also check for menu-visible class (mobile menu state)
    if (document.body.classList.contains("menu-visible")) {
      $hide(backToTop); $hide(backToBottom); return;
    }

    if (!mainPanel) return;
    const mainHeight = mainPanel.clientHeight || 0;
    const mainScrollHeight = mainPanel.scrollHeight || 0;
    const mainScrollTop = mainPanel.scrollTop || 0;

    // Position buttons relative to main panel
    const mainRect = mainPanel.getBoundingClientRect();
    const mainWidth = mainRect.width;
    const buttonRight = window.innerWidth - (mainRect.left + mainWidth) + 30;
    if (backToTop) backToTop.style.right = buttonRight + "px";
    if (backToBottom) backToBottom.style.right = buttonRight + "px";

    // Calculate thresholds (100px minimum scroll to show buttons)
    const scrollThreshold = 100;

    // Show top button when scrolled down enough from the top
    if (mainScrollTop > scrollThreshold) {
      $show(backToTop); } else {
      $hide(backToTop); }

    // Show bottom button when not near the bottom
    const distanceFromBottom = mainScrollHeight - mainScrollTop - mainHeight;
    if (distanceFromBottom > scrollThreshold) {
      $show(backToBottom); } else {
      $hide(backToBottom); }
  }

  // Store ResizeObserver instance for cleanup
  let layoutResizeObserver = null;
  let resizeObserverTimeout = null;
  let lastObservedTime = 0;
  
  // Setup ResizeObserver for more reliable resize detection with performance optimizations
  function setupResizeObserver() {
    try {
      if (typeof ResizeObserver === 'undefined') {
        console.warn('ResizeObserver not supported in this browser');
        return;
      }
      
      // Clean up existing observer and timeout
      if (layoutResizeObserver) {
        layoutResizeObserver.disconnect();
        layoutResizeObserver = null;
      }
      if (resizeObserverTimeout) {
        clearTimeout(resizeObserverTimeout);
        resizeObserverTimeout = null;
      }
      
      const mainPanel = $id('main');
      const menuPanel = $id('menu');
      
      if (!mainPanel || !menuPanel) {
        console.warn('Required panels not found for ResizeObserver');
        return;
      }
      
      // Create ResizeObserver with performance optimizations
      layoutResizeObserver = new ResizeObserver(entries => {
        // Rate limiting: ignore events that happen too frequently
        const now = Date.now();
        const timeSinceLastObserve = now - lastObservedTime;
        
        // Skip if less than 50ms since last observation (high-frequency filtering)
        if (timeSinceLastObserve < 50) {
          return;
        }
        
        lastObservedTime = now;
        
        // Check if any entry has meaningful size change (more than 1px)
        const hasMeaningfulChange = entries.some(entry => {
          const { width, height } = entry.contentRect;
          const target = entry.target;
          const lastWidth = target.dataset.lastWidth ? parseFloat(target.dataset.lastWidth) : 0;
          const lastHeight = target.dataset.lastHeight ? parseFloat(target.dataset.lastHeight) : 0;
          
          // Store new dimensions
          target.dataset.lastWidth = width.toString();
          target.dataset.lastHeight = height.toString();
          
          // Check if change is significant (more than 1px)
          return Math.abs(width - lastWidth) > 1 || Math.abs(height - lastHeight) > 1;
        });
        
        // Only proceed if there's a meaningful change
        if (!hasMeaningfulChange) {
          return;
        }
        
        // Debounce to prevent excessive calls
        if (resizeObserverTimeout) {
          clearTimeout(resizeObserverTimeout);
        }
        
        const debounceTime = window.UIConfig ? 
          window.UIConfig.TIMING.RESIZE_OBSERVER_DEBOUNCE : 200;
        
        resizeObserverTimeout = setTimeout(() => {
          try {
            fixLayoutAfterResize();
          } catch (error) {
            if (window.ErrorHandler) {
              window.ErrorHandler.log({
                category: window.ErrorHandler.CATEGORIES.UI,
                message: 'Error in fixLayoutAfterResize',
                details: error.message
              });
            } else {
              console.error('Error in fixLayoutAfterResize:', error);
            }
          }
          resizeObserverTimeout = null;
        }, debounceTime);
      });
      
      // Observe both panels with specific options
      const observerOptions = {
        box: 'content-box'  // Only observe content size changes, not border/padding
      };
      
      layoutResizeObserver.observe(mainPanel, observerOptions);
      layoutResizeObserver.observe(menuPanel, observerOptions);
      
      // Clean up on page unload
      window.addEventListener("beforeunload", function() {
        if (layoutResizeObserver) {
          layoutResizeObserver.disconnect();
          layoutResizeObserver = null;
        }
        if (resizeObserverTimeout) {
          clearTimeout(resizeObserverTimeout);
          resizeObserverTimeout = null;
        }
      });
      
    } catch (error) {
      if (window.ErrorHandler) {
        window.ErrorHandler.log({
          category: window.ErrorHandler.CATEGORIES.UI,
          message: 'Error setting up ResizeObserver',
          details: error.message,
          level: window.ErrorHandler.LEVELS.WARNING
        });
      } else {
        console.error('Error setting up ResizeObserver:', error);
      }
      // Fall back to window resize only
      if (layoutResizeObserver) {
        try {
          layoutResizeObserver.disconnect();
        } catch (e) {
          // Ignore cleanup errors
        }
        layoutResizeObserver = null;
      }
    }
  }

  // Cleanup function to prevent memory leaks
  function cleanupEventHandlers() {
    try {
      // Clear all timeouts
      if (window.resizeTimeout) {
        clearTimeout(window.resizeTimeout);
        window.resizeTimeout = null;
      }
      if (window.resizeObserverTimeout) {
        clearTimeout(window.resizeObserverTimeout);
        window.resizeObserverTimeout = null;
      }
      if (window.spinnerCheckInterval) {
        clearInterval(window.spinnerCheckInterval);
        window.spinnerCheckInterval = null;
      }
      
      // Disconnect ResizeObserver
      if (layoutResizeObserver) {
        layoutResizeObserver.disconnect();
        layoutResizeObserver = null;
      }
      
      // Note: Named event listeners removed via vanilla JS are handled by
      // the individual beforeunload handlers above
      
      // Clean up tooltips
      if (window.uiUtils && window.uiUtils.cleanupAllTooltips) {
        window.uiUtils.cleanupAllTooltips();
      }
      
      // Clear UIState listeners if available
      if (window.UIState && window.UIState.reset) {
        // Don't reset state, just clear listeners
        // window.UIState.reset();
      }
    } catch (error) {
      if (window.ErrorHandler) {
        window.ErrorHandler.log({
          category: window.ErrorHandler.CATEGORIES.SYSTEM,
          message: 'Error during cleanup',
          details: error.message,
          level: window.ErrorHandler.LEVELS.WARNING
        });
      } else {
        console.error('Error during cleanup:', error);
      }
    }
  }
  
  // Setup cleanup on page unload
  window.addEventListener('beforeunload', cleanupEventHandlers);
  
  // Also handle visibility changes to prevent issues when tab is hidden
  document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
      // Page is hidden, pause non-critical updates
      if (window.UIState) {
        window.UIState.set('pageHidden', true);
      }
    } else {
      // Page is visible again, resume updates
      if (window.UIState) {
        window.UIState.set('pageHidden', false);
      }
      // Force layout update when becoming visible
      setTimeout(function() {
        if (typeof fixLayoutAfterResize === 'function') {
          fixLayoutAfterResize();
        }
        if (window.uiUtils && window.uiUtils.adjustScrollButtons) {
          window.uiUtils.adjustScrollButtons();
        }
      }, 100);
    }
  });
  
  // We are already inside a DOMContentLoaded listener (opened at the top of
  // this file), so the DOM is ready by the time this runs. Registering a
  // nested DOMContentLoaded listener here would never fire because the
  // event has already dispatched.
  setupToggleHandlers();
  setupEventListeners();
  setupResizeObserver();

  // Store previous model value for confirmation revert
  let previousModelValue = null;

  // Capture previous value on focus
  const modelEl = $id("model");
  if (modelEl) {
    modelEl.addEventListener("focus", function() {
      previousModelValue = this.value;
    });
  }

  if (modelEl) modelEl.addEventListener("change", function() {
    const selectedModel = modelEl.value;

    // Check if the selected model requires confirmation (expensive models)
    if (typeof window.modelRequiresConfirmation === 'function' &&
        window.modelRequiresConfirmation(selectedModel) &&
        previousModelValue !== selectedModel) {

      // Get translated confirmation message
      const confirmTitle = typeof webUIi18n !== 'undefined'
        ? webUIi18n.t('ui.expensiveModelConfirm.title')
        : 'Expensive Model Warning';
      const confirmMessage = typeof webUIi18n !== 'undefined'
        ? webUIi18n.t('ui.expensiveModelConfirm.message').replace('{{model}}', selectedModel)
        : `"${selectedModel}" is a premium model with significantly higher API costs. Are you sure you want to use this model?`;

      if (!confirm(`${confirmTitle}\n\n${confirmMessage}`)) {
        // User cancelled - revert to previous model
        if (previousModelValue) {
          this.value = previousModelValue;
          return; // Exit without processing the change
        }
      }
    }

    // Update previous value after confirmation
    previousModelValue = selectedModel;

    const appsEl = $id("apps");
    const defaultModel = apps[appsEl ? appsEl.value : ""]["model"];
    const modelNonDefault = $id("model-non-default");
    if (selectedModel !== defaultModel) {
      $show(modelNonDefault); } else {
      $hide(modelNonDefault); }

    // Handle reasoning effort dropdown with ReasoningMapper
    const currentApp = appsEl ? appsEl.value : "";
    const provider = getProviderFromGroup(apps[currentApp]["group"]);
    
    // Update UI with provider-specific components and labels
    if (window.reasoningUIManager) {
      window.reasoningUIManager.updateUI(provider, selectedModel);
    }
    
    if (window.ReasoningMapper && ReasoningMapper.isSupported(provider, selectedModel)) {
      const availableOptions = ReasoningMapper.getAvailableOptions(provider, selectedModel);
      const defaultValue = ReasoningMapper.getDefaultValue(provider, selectedModel);
      
      if (availableOptions && availableOptions.length > 0) {
        { const el = $id("reasoning-effort"); if (el) el.disabled = false; }
        
        // Store current value before clearing options
        const previousValue = ($id("reasoning-effort") || {}).value;
        
        // Clear current options
        { const el = $id("reasoning-effort"); if (el) el.innerHTML = ""; }
        
        // Add options from ReasoningMapper with provider-specific labels
        availableOptions.forEach(option => {
          const label = window.ReasoningLabels ? 
            window.ReasoningLabels.getOptionLabel(provider, option) : 
            option;
          { const el = $id("reasoning-effort"); if (el) { const _opt = document.createElement("option"); _opt.value = option; _opt.textContent = label; el.appendChild(_opt); } }
        });
        
        // Don't override reasoning_effort if we're loading from params
        if (!window.isLoadingParams) {
          // Set the value - preserve existing value if present, otherwise use default
          if (previousValue && availableOptions.includes(previousValue)) {
            // Keep the previous value if it's valid for this model
            { const el = $id("reasoning-effort"); if (el) el.value = previousValue; }
          } else {
            // Use the default value from ReasoningMapper
            { const el = $id("reasoning-effort"); if (el) el.value = defaultValue || availableOptions[0]; }
          }
        }
      } else {
        { const el = $id("reasoning-effort"); if (el) el.disabled = true; }
      }
    } else {
      { const el = $id("reasoning-effort"); if (el) el.disabled = true; }
    }
    
    // Always restore default options when disabled (for consistency)
    if (($id("reasoning-effort") || {}).disabled) {
      { const el = $id("reasoning-effort"); if (el) el.innerHTML = ""; }
      const defaultOptions = ['minimal', 'low', 'medium', 'high'];
      defaultOptions.forEach(option => {
        const label = window.ReasoningLabels ? 
          window.ReasoningLabels.getOptionLabel('default', option) : 
          option;
        { const el = $id("reasoning-effort"); if (el) { const _opt = document.createElement("option"); _opt.value = option; _opt.textContent = label; el.appendChild(_opt); } }
      });
      { const el = $id("reasoning-effort"); if (el) el.value = 'medium'; }
    }

    // Update labels after options are generated
    if (window.ReasoningLabels) {
      window.ReasoningLabels.updateUILabels(provider, selectedModel);
    }

    if (modelSpec[selectedModel]) {
      const supportsWeb = (modelSpec[selectedModel]["supports_web_search"] === true) ||
                          (modelSpec[selectedModel]["tool_capability"] === true); // fallback for tool-based providers
      if (supportsWeb) {
        { const el = $id("websearch"); if (el) { el.disabled = false; el.removeAttribute("title"); } }
      } else {
        $hide($id("websearch-badge"));
        const tt = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.webSearchModelDisabled') : 'Model does not support Web Search';
        { const el = $id("websearch"); if (el) { el.disabled = true; el.setAttribute("title", tt); } }
      }

      if (modelSpec[selectedModel].hasOwnProperty("temperature")) {
        { const el = $id("temperature"); if (el) el.disabled = false; }
      } else {
        { const el = $id("temperature"); if (el) el.disabled = true; }
      }

      if (modelSpec[selectedModel].hasOwnProperty("presence_penalty")) {
        { const el = $id("presence-penalty"); if (el) el.disabled = false; }
      } else {
        { const el = $id("presence-penalty"); if (el) el.disabled = true; }
      }

      if (modelSpec[selectedModel].hasOwnProperty("frequency_penalty")) {
        { const el = $id("frequency-penalty"); if (el) el.disabled = false; }
      } else {
        { const el = $id("frequency-penalty"); if (el) el.disabled = true; }
      }

      const isReasoningModel = modelSpec[selectedModel]["reasoning_effort"] || modelSpec[selectedModel]["supports_thinking"];
      if (modelSpec[selectedModel].hasOwnProperty("max_output_tokens")) {
        const maxOutputTokens = modelSpec[selectedModel]["max_output_tokens"][1];
        { const el = $id("max-tokens"); if (el) el.value = maxOutputTokens; }
        if (isReasoningModel) {
          // Reasoning models: lock max_tokens to maximum
          { const el = $id("max-tokens-toggle"); if (el) { el.checked = true; el.disabled = true; } }
          { const el = $id("max-tokens"); if (el) el.disabled = true; }
        } else {
          { const el = $id("max-tokens-toggle"); if (el) { el.checked = true; el.disabled = false; $dispatch(el, "change"); } }
        }
      } else {
        { const el = $id("max-tokens"); if (el) el.value = DEFAULT_MAX_OUTPUT_TOKENS; }
        { const el = $id("max-tokens-toggle"); if (el) { el.checked = false; el.disabled = false; $dispatch(el, "change"); } }
      }
      // Show Thinking toggle: only for models with supports_thinking
      if (modelSpec[selectedModel]["supports_thinking"]) {
        $show($id("thinking-display-container"));
      } else {
        $hide($id("thinking-display-container"));
      }
    } else {
      { const el = $id("reasoning-effort"); if (el) el.disabled = true; }
      { const el = $id("temperature"); if (el) el.disabled = true; }
      { const el = $id("presence-penalty"); if (el) el.disabled = true; }
      { const el = $id("frequency-penalty"); if (el) el.disabled = true; }
      { const el = $id("max-tokens-toggle"); if (el) { el.checked = false; el.disabled = false; $dispatch(el, "change"); } }
      { const el = $id("max-tokens"); if (el) el.value = DEFAULT_MAX_OUTPUT_TOKENS; }
      $hide($id("thinking-display-container"));
    }

    // Update model-selected display text
    if (modelSpec[selectedModel] && (modelSpec[selectedModel].hasOwnProperty("reasoning_effort") || modelSpec[selectedModel]["supports_thinking"])) {
      { const el = $id("model-selected"); if (el) el.textContent = `${provider} (${selectedModel} - ${$id("reasoning-effort") ? $id("reasoning-effort").value : ''})`; }
    } else {
      { const el = $id("model-selected"); if (el) el.textContent = `${provider} (${selectedModel})`; }
    }
    // Use UI utilities module if available, otherwise fallback
    if (uiUtils && uiUtils.adjustImageUploadButton) {
      uiUtils.adjustImageUploadButton(selectedModel);
    } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
      window.shims.uiUtils.adjustImageUploadButton(selectedModel);
    }

    if (typeof params === 'object') {
      params["model"] = selectedModel;
    }
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('model_change');
    }
    // Update collapsed summary bar if visible
    if (typeof updateConfigSummary === 'function' && ($id("config-summary") && $id("config-summary").offsetParent !== null)) {
      updateConfigSummary();
    }
  });

  $on($id("reasoning-effort"), "change", function() {
    const selectedModel = ($id("model") || {}).value;
    // Get current app's provider
    const currentApp = ($id("apps") || {}).value;
    const provider = getProviderFromGroup(apps[currentApp]["group"]);
    
    if (modelSpec[selectedModel] && modelSpec[selectedModel].hasOwnProperty("reasoning_effort")) {
      const reasoningEffort = ($id("reasoning-effort") || {}).value;
      { const el = $id("model-selected"); if (el) el.textContent = `${provider} (${selectedModel} - ${reasoningEffort})`; }
    }

    if (typeof params === 'object') {
      params["reasoning_effort"] = ($id("reasoning-effort") || {}).value;
    }
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('reasoning_effort_change');
    }
  });


  $on($id("apps"), "change", function(event) {
    if (stop_apps_trigger) {
      stop_apps_trigger = false;
      return;
    }

    // Skip confirmation during session restoration
    if (window.isRestoringSession) {
      const selectedAppValue = this.value;
      proceedWithAppChange(selectedAppValue);
      return;
    }

    // Store selected app
    const selectedAppValue = this.value;
    const previousAppValue = lastApp;

    // Update app icon immediately on selection change
    updateAppSelectIcon(selectedAppValue);

    // With customizable select, the selected item styling is handled natively by the browser

    // If there are messages and app is changing, show confirmation dialog
    // Skip if loading parameters from server (new tab initialization)
    // Also skip if user hasn't actively sent messages in this tab (messages loaded from session)
    if (messages.length > 0 && selectedAppValue !== previousAppValue && !window.isLoadingParams && window.userHasInteractedInTab) {
      // Prevent the dropdown from changing yet
      event.preventDefault();
      // Set dropdown back to previous value temporarily
      this.value = previousAppValue;
      // Restore previous icon
      updateAppSelectIcon(previousAppValue);

      // Show confirmation dialog
      { const el = $id("appChangeConfirmation"); if (el) { el.dataset.newApp = selectedAppValue; bootstrap.Modal.getOrCreateInstance(el).show(); } }
      return;
    }

    // No messages or same app, proceed with change
    // However, if there are messages from session (not user interaction), clear them first
    // IMPORTANT: Don't clear during import process
    if (messages.length > 0 && selectedAppValue !== previousAppValue && !window.userHasInteractedInTab && !window.isProcessingImport) {
      // Clear messages via SessionState API
      if (window.SessionState && typeof window.SessionState.clearMessages === 'function') {
        window.SessionState.clearMessages();
      } else {
        try { window.messages = []; } catch (_) { console.warn("[Session] Failed to clear messages:", _); }
      }

      // Clear images and mask data from previous app
      if (typeof window.clearAllImages === 'function') {
        window.clearAllImages();
      }

      // Clear the discourse area
      { const el = $id("discourse"); if (el) el.innerHTML = ""; }

      // Clear error cards
      if (typeof clearErrorCards === 'function') {
        clearErrorCards();
      }

      // Clear temp cards
      { const el = $id("temp-card"); if (el) el.remove(); }
      { const el = $id("temp-reasoning-card"); if (el) el.remove(); }

      // Send server-side RESET to clear session
      ws.send(JSON.stringify({ "message": "RESET" }));
    }

    proceedWithAppChange(selectedAppValue);
  });
  
  // Handle cancellation of app change
  $on($id("appChangeConfirmation"), "hidden.bs.modal", function() {
    // If user cancelled (not confirmed), restore the original app selection
    const newAppValue = this.dataset.newApp;
    const currentAppValue = ($id("apps") || {}).value;

    // If modal closed but app wasn't changed (user cancelled), ensure selection is correct
    if (currentAppValue !== newAppValue && currentAppValue !== lastApp) {
      // Restore to lastApp
      { const el = $id("apps"); if (el) el.value = lastApp; }
      updateAppSelectIcon(lastApp);
    }
  });

  // Handle confirmation of app change
  $on($id("appChangeConfirmed"), "click", function() {
    const newAppValue = ($id("appChangeConfirmation") || {}).dataset.newApp;
    // Close the modal
    bootstrap.Modal.getOrCreateInstance($id("appChangeConfirmation")).hide();
    // Apply the app change
    { const el = $id("apps"); if (el) el.value = newAppValue; }

    // COMPREHENSIVE STATE CLEARING
    // Reset messages via SessionState API (no direct assignment)
    if (window.SessionState && typeof window.SessionState.clearMessages === 'function') {
      window.SessionState.clearMessages();
    } else {
      try { window.messages = []; } catch (_) { console.warn("[Session] Failed to clear messages on reset:", _); }
    }

    // Clear images and mask data from previous app
    if (typeof window.clearAllImages === 'function') {
      window.clearAllImages();
    }

    // Clear user interaction flag (for app change confirmation)
    window.userHasInteractedInTab = false;

    // Clear the discourse area
    { const el = $id("discourse"); if (el) el.innerHTML = ""; }

    // Clear error cards specifically
    if (typeof clearErrorCards === 'function') {
      clearErrorCards();
    }

    // Clear status message
    if (typeof clearStatusMessage === 'function') {
      clearStatusMessage();
    }

    // Clear temp cards
    { const el = $id("temp-card"); if (el) el.remove(); }
    { const el = $id("temp-reasoning-card"); if (el) el.remove(); }

    // Send server-side RESET to clear session
    ws.send(JSON.stringify({ "message": "RESET" }));

    // Reset to settings panel
    enterSettingsMode();
    // Wait for i18n to be ready before updating button text
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        const startText = webUIi18n.t('ui.session.startSession');
        { const el = $id("start-label"); if (el) el.textContent = startText; }
      });
    } else {
      // Fallback if i18nReady is not available
      const startText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
        webUIi18n.t('ui.session.startSession') : 'Start Session';
      { const el = $id("start-label"); if (el) el.textContent = startText; }
    }
    proceedWithAppChange(newAppValue);
  });
  
  // Function to handle the actual app change
  // Make it globally accessible for initialization from websocket.js
  window.proceedWithAppChange = function proceedWithAppChange(appValue) {
    // Guard: skip if appValue is null/undefined or app not found in apps object
    if (!appValue || !apps || !apps[appValue]) {
      console.warn(`[AppChange] App '${appValue}' not found in apps object, skipping`);
      return;
    }

    try {
      if (window.logTL) {
        const hasApp = !!(apps && apps[appValue]);
        const sys = hasApp ? !!apps[appValue]["system_prompt"] : null;
        window.logTL('proceedWithAppChange_enter', { appValue, hasApp, hasSystemPrompt: sys });
      }
    } catch (_) { console.warn("[AppChange] Timeline logging failed:", _); }
    // Ensure params is initialized
    if (typeof params === 'undefined') {
      window.params = {};
    }

    // All providers now support AI User functionality
    const selectedApp = apps[appValue];

    // Store current provider for timeout handling
    if (selectedApp && selectedApp.group) {
      window.currentLLMProvider = getProviderFromGroup(selectedApp.group).toLowerCase();
    }

    // Always enable AI User button (error message will be shown if conversation not started)
    { const el = $id("ai_user"); if (el) el.disabled = false; }
    // Set title with translation when available
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        const aiUserTitle = webUIi18n.t('ui.generateAIUserResponse') || "Generate AI user response based on conversation";
        { const el = $id("ai_user"); if (el) el.setAttribute("title", aiUserTitle); }
      });
    } else {
      { const el = $id("ai_user"); if (el) el.setAttribute("title", "Generate AI user response based on conversation"); }
    }

    // Update the UI dropdown to match the appValue parameter
    if (($id("apps") || {}).value !== appValue) {
      { const el = $id("apps"); if (el) el.value = appValue; }
    }

    // Skip early return during initial load or session restoration
    // to ensure proper initialization even if messages already exist
    if (messages.length > 0) {
      if (appValue === lastApp && window.initialAppLoaded) {
        return;
      }
    }
    lastApp = appValue;
    // Also update window.lastApp to keep them in sync
    window.lastApp = appValue;
    // Check if the app exists
    if (!apps[appValue]) {
      console.warn(`App '${appValue}' not found in apps object`);
      return;
    }
    // Preserve important values before Object.assign overwrites them
    const currentMathjax = ($id("math") || {}).checked;
    // Preserve previous values only during import flows
    const importingFlow = (typeof window !== 'undefined') && (window.isImporting || window.isProcessingImport);

    const preservedModel = importingFlow ? params["model"] : null;  // Preserve the model that was set by loadParams
    const preservedAppName = importingFlow ? params["app_name"] : null; // Preserve the app_name
    // CRITICAL: Preserve initiate_from_assistant and auto_speech during import to prevent app defaults from overriding
    const preservedInitiateFromAssistant = importingFlow ? params["initiate_from_assistant"] : null;
    const preservedAutoSpeech = importingFlow ? params["auto_speech"] : null;
    // Do not carry over previous group's provider across app changes.
    // If importing, we handle app selection earlier based on provider.
    const preservedGroup = null;

    Object.assign(params, apps[appValue]);
    params["app_name"] = appValue;
    
    // Fill initial_prompt from system_prompt if not present (common for Chat apps)
    if (!params["initial_prompt"] && apps[appValue]["system_prompt"]) {
      params["initial_prompt"] = apps[appValue]["system_prompt"];
    }

    // Restore the preserved values if they were set (during import)
    if (preservedModel && importingFlow) {
      params["model"] = preservedModel;
    } else {
      // NOT importing: Explicitly reset model to new app's default
      // This ensures switching apps always resets to the correct model
      if (apps[appValue]["model"]) {
        params["model"] = apps[appValue]["model"];
        { const el = $id("model"); if (el) el.value = apps[appValue]["model"]; }
      }
    }
    if (preservedAppName && importingFlow) {
      params["app_name"] = preservedAppName;
    }
    // Always align params.group to the selected app's group to avoid stale provider labels
    params["group"] = apps[appValue]["group"];

    // CRITICAL: Restore initiate_from_assistant and auto_speech during import
    // This prevents app defaults from overriding the imported (forced-false) values
    if (importingFlow) {
      // During import: restore preserved values (which were set to false by import handler)
      if (preservedInitiateFromAssistant !== null) {
        params['initiate_from_assistant'] = preservedInitiateFromAssistant;
      }
      if (preservedAutoSpeech !== null) {
        params['auto_speech'] = preservedAutoSpeech;
      }
    } else {
      // NOT importing: Use app defaults
      if (apps[appValue] && Object.prototype.hasOwnProperty.call(apps[appValue], 'initiate_from_assistant')) {
        params['initiate_from_assistant'] = !!apps[appValue]['initiate_from_assistant'];
      } else {
        // Default back to user-first conversations when the app does not specify the flag.
        params['initiate_from_assistant'] = false;
      }
    }
    // Restore math state if not explicitly set in app parameters
    if (apps[appValue] && !apps[appValue].hasOwnProperty('math')) {
      params['math'] = currentMathjax;
    }
    
    // Ensure loadParams runs even if another async selection is in progress
    // If a prior flow (e.g., provider auto-select) set isLoadingParams, defer and retry briefly
    (function ensureLoadParams(retries = 0) {
      if (!window.isLoadingParams) {
        loadParams(params, "changeApp");
        if (window.logTL) window.logTL('loadParams_called_from_proceed', { app: appValue, calledFor: 'changeApp' });

        // DON'T clear isProcessingImport here - it must stay active through the entire import flow
        // It will be cleared in the past_messages WebSocket handler after all import processing is complete
        return;
      }
      if (retries >= 10) {
        // As a last resort, proceed anyway to avoid missing initial prompt
        loadParams(params, "changeApp");
        if (window.logTL) window.logTL('loadParams_called_from_proceed_force', { app: appValue, calledFor: 'changeApp' });

        // DON'T clear isProcessingImport even on forced execution
        return;
      }
      setTimeout(() => ensureLoadParams(retries + 1), 100);
    })();
    
    // Update app icon in the select dropdown
    updateAppSelectIcon(appValue);

    // Use toBool helper for defensive boolean evaluation
    const toBool = window.toBool || ((value) => {
      if (typeof value === 'boolean') return value;
      if (typeof value === 'string') return value === 'true';
      return !!value;
    });

    if (toBool(apps[appValue]["pdf_vector_storage"])) {
      $show($id("pdf-panel"));
      ws.send(JSON.stringify({ message: "PDF_TITLES" }));
    } else {
      $hide($id("pdf-panel"));
    }

    if (toBool(apps[appValue]["audio_upload"])) {
      $show($id("audio-upload"));
    } else {
      $hide($id("audio-upload"));
    }

    // Image button visibility is handled by adjustImageUploadButton() based on model capabilities

    let model;
    // Never mutate apps[appValue].group here; app definitions are authoritative.

    // Use shared utility function to get models for the app
    const showAll = ($id("show-all-models") || {}).checked;
    let models = getModelsForApp(apps[appValue], showAll);

    if (models.length > 0) {
      let openai = apps[appValue]["group"].toLowerCase() === "openai";
      let modelList = listModels(models, openai);
      { const el = $id("model"); if (el) el.innerHTML = modelList; }

      // Use shared utility function to get default model
      model = getDefaultModelForApp(apps[appValue], models);

      // Override with params if available
      if (params["model"] && models.includes(params["model"])) {
        model = params["model"];
      }

      // Override with restored model if available (from session restoration)
      if (window.restoredModel && models.includes(window.restoredModel)) {
        model = window.restoredModel;
        // Clear the restored model flag so it's only used once
        delete window.restoredModel;
      }

      // Get provider from app group
      const provider = getProviderFromGroup(apps[appValue]["group"]);
      
      if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
        { const el = $id("model-selected"); if (el) el.textContent = `${provider} (${model} - ${$id("reasoning-effort") ? $id("reasoning-effort").value : ''})` };
      } else {
        { const el = $id("model-selected"); if (el) el.textContent = `${provider} (${model})`; }
      }

      if (modelSpec[model] && ((modelSpec[model]["supports_web_search"] === true) || (modelSpec[model]["tool_capability"] === true))) {
        { const el = $id("websearch"); if (el) { el.disabled = false; el.removeAttribute("title"); } }
      } else {
        $hide($id("websearch-badge"));
        const tt2 = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.webSearchModelDisabled') : 'Model does not support Web Search';
        { const el = $id("websearch"); if (el) { el.disabled = true; el.setAttribute("title", tt2); } }
      }

      { const el = $id("model"); if (el) el.value = model; }

      if (($id("model") || {}).value !== model) {
        // Try again after a delay
        setTimeout(() => {
          { const el = $id("model"); if (el) el.value = model; }
          if (($id("model") || {}).value === model) {
            $dispatch($id("model"), "change");
          } else {
            // Defensive fallback: select first available (non-disabled) option
            const firstOption = (document.querySelector("#model option:not(:disabled)") || {}).value;
            if (firstOption) {
              { const el = $id("model"); if (el) { el.value = firstOption; $dispatch(el, "change"); } }
            }
          }
        }, 100);
      } else {
        $dispatch($id("model"), "change");
      }
      // Use UI utilities module if available, otherwise fallback
      if (uiUtils && uiUtils.adjustImageUploadButton) {
        uiUtils.adjustImageUploadButton(model);
      } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
        window.shims.uiUtils.adjustImageUploadButton(model);
      }

    } else if (!apps[appValue]["model"] || apps[appValue]["model"].length === 0) {
      // Models not available - show placeholder instead of hiding the row
      { const el = $id("model"); if (el) el.innerHTML = '<option disabled selected>Models not available</option>'; }
      $hide($id("model_parameters"));
    } else {
      // The following code is for backward compatibility

      let models_text = apps[appValue]["models"];
      let models = JSON.parse(models_text);
      model = params["model"];

      if (params["model"] && models && models.includes(params["model"])) {
        { const el = $id("model"); if (el) el.innerHTML = model_options; }
        { const el = $id("model"); if (el) { el.value = params["model"]; $dispatch(el, "change"); } }
      } else {
        let model_options = `<option disabled="disabled" selected="selected">Models not available</option>`;
        { const el = $id("model"); if (el) el.innerHTML = model_options; }
      }

      // Get provider from app group
      const provider = getProviderFromGroup(apps[appValue]["group"]);
      
      if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
        { const el = $id("model-selected"); if (el) el.textContent = `${provider} (${model} - ${$id("reasoning-effort") ? $id("reasoning-effort").value : ''})` };
      } else {
        { const el = $id("model-selected"); if (el) el.textContent = `${provider} (${params["model"]})`; }
      }

      $show($id("model_and_file"));
      $show($id("model_parameters"));
      // Use UI utilities module if available, otherwise fallback
      if (uiUtils && uiUtils.adjustImageUploadButton) {
        uiUtils.adjustImageUploadButton(model);
      } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
        window.shims.uiUtils.adjustImageUploadButton(model);
      }
    }

    if (apps[appValue]["context_size"]) {
      { const el = $id("context-size-toggle"); if (el) el.checked = true; }
      { const el = $id("context-size"); if (el) el.disabled = false; }
    } else {
      { const el = $id("context-size-toggle"); if (el) el.checked = false; }
      { const el = $id("context-size"); if (el) el.disabled = true; }
    }

    // Use display_name if available, otherwise fall back to app_name
    const displayText = apps[appValue]["display_name"] || apps[appValue]["app_name"];
    { const el = $id("base-app-title"); if (el) el.textContent = displayText; }
    { const el = $id("base-app-icon"); if (el) el.innerHTML = apps[appValue]["icon"]; }

    if (toBool(apps[appValue]["monadic"])) {
      $show($id("monadic-badge"));
    } else {
      $hide($id("monadic-badge"));
    }

    if (apps[appValue]["tools"]) {
      $show($id("tools-badge"));
    } else {
      $hide($id("tools-badge"));
    }

    if (toBool(apps[appValue]["websearch"])) {
      { const el = $id("websearch"); if (el) el.checked = true; }
      $show($id("websearch-badge"));
    } else {
      { const el = $id("websearch"); if (el) el.checked = false; }
      $hide($id("websearch-badge"));
    }

    if (toBool(apps[appValue]["math"])) {
      { const el = $id("math"); if (el) el.checked = true; }
      $show($id("math-badge"));
    } else {
      { const el = $id("math"); if (el) el.checked = false; }
      $hide($id("math-badge"));
    }

    if (typeof window.setBaseAppDescription === 'function') {
      window.setBaseAppDescription(apps[appValue]["description"] || "");
    } else {
      { const el = $id("base-app-desc"); if (el) el.innerHTML = apps[appValue]["description"]; }
    }

    if (typeof window.setPromptView === 'function') window.setPromptView('hidden', false);

    // Ensure reasoning-effort dropdown is updated after app change
    setTimeout(function() {
      const currentModel = ($id("model") || {}).value;
      if (currentModel) {
        $dispatch($id("model"), "change");
      }
    }, 100);

    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('app_change');
    }

    // Final enforcement: keep checkboxes OFF during import to prevent auto-behaviors
    if (importingFlow) {
      { const el = $id("check-auto-speech"); if (el) el.checked = false; }
      { const el = $id("initiate-from-assistant"); if (el) el.checked = false; }
    }

    { const el = $id("apps"); if (el) el.focus(); }
  }

  $on($id("websearch"), "change", function() {
    if (this.checked) {
      params["websearch"] = true;
    } else {
      params["websearch"] = false;
    }
    // Update badges to reflect toggle state
    const selectedApp = ($id("apps") || {}).value;
    if (selectedApp && typeof window.updateAppBadges === 'function') {
      window.updateAppBadges(selectedApp);
    }
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('websearch_toggle');
    }
  })

  $on($id("check-auto-speech"), "change", function() {
    if (this.checked) {
      params["auto_speech"] = true;
    } else {
      params["auto_speech"] = false;
    }
    // Update badges to reflect toggle state
    const selectedApp = ($id("apps") || {}).value;
    if (selectedApp && typeof window.updateAppBadges === 'function') {
      window.updateAppBadges(selectedApp);
    }
    // Update toggle button text
    if (typeof window.updateToggleButtonText === 'function') {
      window.updateToggleButtonText();
    }
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('auto_speech_toggle');
    }
  })

  $on($id("check-easy-submit"), "change", function() {
    if (this.checked) {
      params["easy_submit"] = true;
    } else {
      params["easy_submit"] = false;
    }
    // Update badges to reflect toggle state
    const selectedApp = ($id("apps") || {}).value;
    if (selectedApp && typeof window.updateAppBadges === 'function') {
      window.updateAppBadges(selectedApp);
    }
    // Update toggle button text
    if (typeof window.updateToggleButtonText === 'function') {
      window.updateToggleButtonText();
    }
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('easy_submit_toggle');
    }
  })

  $on($id("math"), "change", function() {
    if (this.checked) {
      params["math"] = true;
    } else {
      params["math"] = false;
    }
    // Update badges to reflect toggle state
    const selectedApp = ($id("apps") || {}).value;
    if (selectedApp && typeof window.updateAppBadges === 'function') {
      window.updateAppBadges(selectedApp);
    }
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('math_toggle');
    }
  });

  // Initialize page state based on screen width when document is ready
  (function() {
    // Initialize UIState if available
    if (window.UIState && window.UIState.initialize) {
      try {
        window.UIState.initialize();
      } catch (error) {
        if (window.ErrorHandler) {
          window.ErrorHandler.log({
            category: window.ErrorHandler.CATEGORIES.SYSTEM,
            message: 'Error initializing UIState',
            details: error.message
          });
        } else {
          console.error('Error initializing UIState:', error);
        }
      }
    }
    
    // On mobile, initialize with menu hidden on first load
    if (window.innerWidth < 600) {
      // Set proper classes and hide menu on mobile
      { const el = $id("toggle-menu"); if (el) el.classList.add("menu-hidden"); }
      $hide($id("menu"));
      $show($id("main"));
      document.body.classList.remove("menu-visible");
      { const el = $id("main"); if (el) { el.classList.remove("col-md-8"); el.classList.add("col-md-12"); } }
      // Note: Removed inline CSS injection for toggle-menu in document.ready
    } else {
      // On desktop, menu is visible by default, so set the appropriate icon and style
      { const el = $id("toggle-menu"); if (el) el.classList.remove("menu-hidden"); }
    }
    
    // Initialize scroll buttons state
    setTimeout(function() {
      if (uiUtils && uiUtils.adjustScrollButtons) {
        uiUtils.adjustScrollButtons();
      } else if (typeof adjustScrollButtonsFallback === 'function') {
        adjustScrollButtonsFallback();
      }
    }, 100);
  })();

  // Also ensure positions are set on load event
  window.addEventListener("load", function() {
    // Fix layout on load to ensure proper state
    setTimeout(function() {
      fixLayoutAfterResize();
    }, 100);
  });
  
  // Function to ensure navbar elements are perfectly centered
  function centerNavbarElements() {
    if (window.innerWidth >= 600) return;
    optimizeMobileScrolling();
  }
  
  // Function to optimize scrollable areas on mobile devices
  function optimizeMobileScrolling() {
    // Only run on mobile
    if (window.innerWidth >= 600) return;
    
    // Ensure the main content area takes maximum available space
    { const el = $id("main"); if (el) { el.style.paddingBottom = "0"; el.style.marginBottom = "0"; } }

    // Optimize scrollable container to use full height
    document.querySelectorAll(".scrollable").forEach(function(_el) {
      _el.style.height = "calc(100vh - 80px)";
      _el.style.paddingBottom = "0";
      _el.style.marginBottom = "0";
      _el.style.overflowY = "auto";
    });

    // Ensure content container has correct height
    { const el = $id("contents"); if (el) {
      el.style.height = "calc(100vh - 80px)";
      el.style.minHeight = "calc(100vh - 80px)";
      el.style.paddingBottom = "12px";
      el.style.paddingTop = "0";
      el.style.marginBottom = "0";
      el.style.boxSizing = "border-box";
    } }

    // Make user panel more space-efficient
    { const el = $id("user-panel"); if (el) { el.style.marginBottom = "0"; el.style.paddingBottom = "0"; } }

    // Fix iOS-specific scroll issues
    if (/iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream) {
      document.querySelectorAll(".scrollable").forEach(function(_el) {
        _el.style.webkitOverflowScrolling = "touch";
        _el.style.transform = "translateZ(0)";
        _el.style.webkitTransform = "translateZ(0)";
      });
    }
  }

  // Listen for window resize events
  window.addEventListener("resize", function() {
    const wasMenuVisible = ($id("menu") && $id("menu").offsetParent !== null);
    const windowWidth = window.innerWidth;
    // Check if user explicitly hid the menu (respect user preference)
    const userHidMenu = StorageHelper.safeGetItem('monadic-menu-hidden') === 'true';

    // Only reposition on mobile
    if (windowWidth < 600) {
      centerNavbarElements();
    } else if (windowWidth >= 600 && !wasMenuVisible && !userHidMenu) {
      // We've changed from mobile to desktop view with hidden menu
      // Restore proper column layout and show menu ONLY if user didn't explicitly hide it
      { const el = $id("main"); if (el) { el.classList.remove("col-md-12"); el.classList.add("col-md-8"); } }
      $show($id("menu"));
      { const el = $id("toggle-menu"); if (el) el.classList.remove("menu-hidden"); }
    }
  });

  // Handle toggle-menu button click with comprehensive error handling
  $on($id("toggle-menu"), "click", function(e) {
    try {
      // Prevent any default behavior
      e.preventDefault();
      e.stopPropagation();
      
      // Get required elements with safety checks
      const $toggleBtn = this;
      const $menu = $id("menu");
      const $main = $id("main");
      const $spinner = $id("monadic-spinner");

      if (!$toggleBtn || !$menu || !$main) {
        console.error('Required elements missing for menu toggle');
        return false;
      }

      // Check if we're on mobile with fallback
      const isMobile = window.UIConfig ?
        window.UIConfig.isMobileView() :
        window.innerWidth < 600;

      // Toggle menu visibility and change icon to indicate state
      const menuVisible = ($menu.offsetParent !== null);

      if (menuVisible) {
        // Menu is visible, will be hidden
        $toggleBtn.classList.add("menu-hidden");
        $toggleBtn.setAttribute("aria-expanded", "false");

        // Save menu state to localStorage to persist across zoom operations
        if (!StorageHelper.safeSetItem('monadic-menu-hidden', 'true')) {
          console.warn('Failed to save menu state to localStorage');
        }

        if (isMobile) {
          // On mobile: hide menu and show main
          $hide($menu);
          $show($main);
          document.body.classList.remove("menu-visible");
        } else {
          // On desktop: normal column behavior
          $main.classList.remove("col-md-8"); $main.classList.add("col-md-12");
          $hide($menu);
        }
      } else {
        // Menu is hidden, will be shown
        $toggleBtn.classList.remove("menu-hidden");
        $toggleBtn.setAttribute("aria-expanded", "true");

        // Save menu state to localStorage to persist across zoom operations
        if (!StorageHelper.safeSetItem('monadic-menu-hidden', 'false')) {
          console.warn('Failed to save menu state to localStorage');
        }

      if (isMobile) {
        // On mobile: show menu and hide main completely
        $show($menu);
        $hide($main);
        document.body.classList.add("menu-visible");
        } else {
          // On desktop: normal column behavior
          $main.classList.remove("col-md-12"); $main.classList.add("col-md-8");
          $show($menu);
        }
      }
      
      // Update UI state if available
      if (window.UIConfig && window.UIConfig.STATE) {
        window.UIConfig.STATE.isMenuVisible = !menuVisible;
      }
      
      // Reset scroll position
      window.scrollTo({ top: 0 });
      
      // Update scroll buttons visibility after menu toggle (with slight delay for DOM update)
      const updateDelay = window.UIConfig ? 
        window.UIConfig.TIMING.LAYOUT_FIX_DELAY : 50;
      
      setTimeout(function() {
        try {
          if (window.uiUtils && window.uiUtils.adjustScrollButtons) {
            window.uiUtils.adjustScrollButtons();
          } else if (typeof adjustScrollButtonsFallback === 'function') {
            adjustScrollButtonsFallback();
          }
        } catch (error) {
          console.error('Error adjusting scroll buttons:', error);
        }
      }, updateDelay);
      
      // Basic scroll position maintenance - use a very small timeout
      setTimeout(function() {
        // Reset scroll positions
      document.querySelectorAll("#main, #menu").forEach(function(_el) { _el.scrollTop = 0; });

      // On mobile, force elements to maintain their positions
      if (isMobile) {
        // Fix toggle button position with exact coordinates
        var _tmEl = $id("toggle-menu");
        if (_tmEl) {
          _tmEl.style.position = "fixed";
          _tmEl.style.top = "12px";
          _tmEl.style.right = "10px";
          _tmEl.style.height = "30px";
          _tmEl.style.width = "30px";
          _tmEl.style.padding = "6px";
          _tmEl.style.transform = "none";
        }
      }

      // Run scrollable area optimization for all mobile devices
      if (window.innerWidth < 768) {
        optimizeMobileScrolling();
      }

      // iOS Safari specific fix to ensure proper layout after toggle
      if (/iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream) {
        // Force a repaint
        document.querySelectorAll("#main, #menu").forEach(function(_el) { _el.style.transform = "translateZ(0)"; });
        
        // Run optimization again after a short delay for iOS
        setTimeout(optimizeMobileScrolling, window.UIConfig ? window.UIConfig.TIMING.LAYOUT_FIX_DELAY : 100);
      }
      }, 10); // Very small timeout
      
      return false; // Prevent event bubbling
      
    } catch (error) {
      console.error('Error in menu toggle:', error);
      // Attempt recovery
      try {
        $show($id("main"));
        $show($id("toggle-menu"));
        document.body.classList.remove("menu-visible");
      } catch (recoveryError) {
        console.error('Recovery failed:', recoveryError);
      }
      return false;
    }
  });

  // Function to update toggle button text based on checkbox states
  window.updateToggleButtonText = function() {
    const autoSpeechChecked = ($id("check-auto-speech") || {}).checked;
    const easySubmitChecked = ($id("check-easy-submit") || {}).checked;
    const $toggleButton = $id("interaction-toggle-all");

    if (typeof webUIi18n !== 'undefined' && webUIi18n.initialized) {
      // Show appropriate text based on current state
      if (autoSpeechChecked && easySubmitChecked) {
        if ($toggleButton) $toggleButton.textContent = (webUIi18n.t('ui.uncheckAll'));
      } else if (!autoSpeechChecked && !easySubmitChecked) {
        if ($toggleButton) $toggleButton.textContent = (webUIi18n.t('ui.checkAll'));
      } else {
        if ($toggleButton) $toggleButton.textContent = (webUIi18n.t('ui.toggleAll'));
      }
    }
  };
  
  // Toggle all interaction checkboxes - use event delegation for reliability
  document.addEventListener("click", function(e) { const _delegateTarget = e.target.closest("#interaction-toggle-all"); if (!_delegateTarget) return;
    const autoSpeechChecked = ($id("check-auto-speech") || {}).checked;
    const easySubmitChecked = ($id("check-easy-submit") || {}).checked;

    // If any checkbox is unchecked, check all. Otherwise, uncheck all.
    const shouldCheck = !autoSpeechChecked || !easySubmitChecked;

    // Suppress broadcasts during toggle to prevent state reset from server sync
    window.suppressParamBroadcastCount = (window.suppressParamBroadcastCount || 0) + 1;
    try {
      // Set checkbox values and trigger change events to update params
      { const el = $id("check-auto-speech"); if (el) { el.checked = shouldCheck; $dispatch(el, "change"); } }
      { const el = $id("check-easy-submit"); if (el) { el.checked = shouldCheck; $dispatch(el, "change"); } }
    } finally {
      window.suppressParamBroadcastCount = Math.max(0, (window.suppressParamBroadcastCount || 0) - 1);
    }

    // Update the button text after toggling
    window.updateToggleButtonText();
  });

  // Initialize toggle button text on page load
  (function() {
    window.updateToggleButtonText();
  })();

  $on($id("start"), "click", function() {
    audioInit();
    { const el = $id("asr-p-value"); if (el) { el.textContent = ""; $hide(el); } }

    // Mark that user has interacted with this tab (for app change confirmation)
    window.userHasInteractedInTab = true;

    // Clear import/initial load flag when user manually starts/continues session
    // This allows Auto TTS to work normally after user interaction
    if (window.isProcessingImport) {
      window.isProcessingImport = false;
    }

    if (checkParams()) {
      params = setParams();
    } else {
      return;
    }

    const shouldSkipAssistant = (typeof window !== 'undefined') && window.skipAssistantInitiation === true;
    

    // Ensure UI controls are properly enabled by default
    // This prevents UI getting stuck in disabled state
    function ensureControlsEnabled() {
      document.querySelectorAll("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import, #audio-upload").forEach(function(_el) { _el.disabled = false; });
      { const el = $id("message"); if (el) el.disabled = false; }
      { const el = $id("select-role"); if (el) el.disabled = false; }
      $hide($id("monadic-spinner"));
      $hide($id("cancel_query"));
    }

    // Set a safety timeout to re-enable controls if they remain disabled
    const safetyTimeout = setTimeout(function() {
      // Only run if user panel is visible but controls are disabled
      if (($id("user-panel") && $id("user-panel").offsetParent !== null) && ($id("send") || {}).disabled) {
        ensureControlsEnabled();
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input'}`, "success");
      }
    }, 3000); // 3 second timeout is enough for normal operations to complete

    // Clear messages if we just reset to ensure fresh start
    if (window.SessionState.shouldForceNewSession()) {
      window.SessionState.clearMessages();
      window.SessionState.clearForceNewSession();
    }
    
    if (messages.length > 0) {
      enterConversationMode();
      $show($id("discourse"));
      { const el = $id("chat"); if (el) el.innerHTML = ""; }
      $hide($id("temp-card"));
      $show($id("user-panel"));
      setInputFocus();
      ensureControlsEnabled();
    } else {
      // create secure random 4-digit number
      ws.send(JSON.stringify({
        message: "SYSTEM_PROMPT",
        content: ($id("initial-prompt") || {}).value,
        math: ($id("math") || {}).checked,
        monadic: params["monadic"],
        websearch: params["websearch"],
        jupyter: params["jupyter"],
        conversation_language: params["conversation_language"] || "auto",
      }));

      // Initialize audio before showing the UI
      audioInit();
      
      enterConversationMode();
      $show($id("discourse"));

      // Only initiate from assistant if it's a fresh conversation (no existing messages)
      // This prevents auto-generation when importing conversations
      if (($id("initiate-from-assistant") || {}).checked && messages.length === 0 && !shouldSkipAssistant) {
        $show($id("temp-card"));
        $hide($id("user-panel"));
        $show($id("monadic-spinner")); // Show spinner for initial assistant message
        setAlert(`<i class='fas fa-spinner fa-spin'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.generatingResponse') : 'Generating response from assistant...'}`, "info");
        $id('cancel_query').style.setProperty('display', 'flex', 'important');
        reconnect_websocket(ws, function (ws) {
          // Ensure critical parameters are correctly set based on checkboxes
          params["auto_speech"] = ($id("check-auto-speech") || {}).checked;
          params["initiate_from_assistant"] = true;
              ws.send(JSON.stringify(params));
        });
      } else {
        $show($id("user-panel"));
        ensureControlsEnabled();
        setInputFocus();
      }
    }

    // Clear skipAssistantInitiation after processing (important for imports)
    // This ensures the flag only affects the FIRST session start after import
    if (window.skipAssistantInitiation) {
      window.skipAssistantInitiation = false;
    }
  });


  $on($id("cancel_query"), "click", function() {
    setAlert(`<i class='fa-solid fa-ban' style='color: #ffc107;'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.operationCanceled') : 'Operation canceled'}`, "warning");
    ttsStop();

    responseStarted = false;
    callingFunction = false;
    streamingResponse = false;  // Reset streaming flag

    // Clear spinner check interval if it exists
    if (window.spinnerCheckInterval) {
      clearInterval(window.spinnerCheckInterval);
      window.spinnerCheckInterval = null;
    }

    // Reset AI user state if active
    const placeholderText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
      webUIi18n.t('ui.messagePlaceholder') : "Type your message . . .";
    { const el = $id("message"); if (el) el.setAttribute("placeholder", placeholderText); }
    { const el = $id("message"); if (el) el.disabled = false; }
    document.querySelectorAll("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import").forEach(function(_el) { _el.disabled = false; });
    { const el = $id("ai_user_provider"); if (el) el.disabled = false; }
    { const el = $id("ai_user"); if (el) el.disabled = false; }
    { const el = $id("select-role"); if (el) el.disabled = false; }

    // Send cancel message to server
    ws.send(JSON.stringify({ message: "CANCEL" }));
    
    // Reset UI completely
    { const el = $id("chat"); if (el) el.innerHTML = ""; }
    $hide($id("temp-card"));
    $show($id("user-panel"));
    $hide($id("monadic-spinner"));  // Hide spinner
    $hide($id("indicator"));  // Hide indicator
    $id('cancel_query').style.setProperty('display', 'none', 'important');  // Force hide cancel button
    
    // Set focus back to input
    setInputFocus();
  });

  $on($id("send"), "click", function(event) {
    event.preventDefault();
    if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
      return;
    }
    if (message.value === "") {
      return;
    }
    // Auto-collapse settings when sending a message
    var configBody = $id("config-body");
    if (configBody && configBody.classList.contains("show")) {
      bootstrap.Collapse.getOrCreateInstance(configBody, { toggle: false }).hide();
    }
    audioInit();

    // Reset sequence tracking for realtime TTS (new message starts new sequence)
    if (typeof clearAudioQueue === 'function') {
      clearAudioQueue();
    }

    setAlert(`<i class='fas fa-robot'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.thinking') : 'THINKING'}`, "warning");
    params = setParams();
    const userMessageText = ($id("message") || {}).value;
    params["message"] = userMessageText;

    // Mark that user has interacted with this tab (for app change confirmation)
    window.userHasInteractedInTab = true;

    // This is handled already in setParams(), no need to override here

    $id('cancel_query').style.setProperty('display', 'flex', 'important');

    $show($id("monadic-spinner"));

    // Temporarily push a placeholder message to prevent double display
    // This will be replaced by the actual message from the server
    if (messages.length === 0) {
      // Add a temporary object to messages array to prevent duplicates
      const tempMid = "temp_" + Math.floor(Math.random() * 100000);
      // Use SessionState for centralized state management
      window.SessionState.addMessage({ role: "user", text: userMessageText, mid: tempMid, temp: true });

      // Show loading indicators but don't create a card yet
      // The actual card will be created when server responds
      $show($id("temp-card"));
      { const el = document.querySelector("#temp-card .status"); $hide(el); }
      $show($id("indicator"));
    }

    if (($id("select-role") || {}).value !== "user") {
      // Show spinner to indicate processing
      setAlert(`<i class='fas fa-spinner fa-spin'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.processingMessage') : 'Processing sample message'}`, "warning");
      
      // Set a reasonable timeout to avoid UI getting stuck
      let sampleTimeoutId = setTimeout(function() {
        $hide($id("monadic-spinner"));
        $hide($id("cancel_query"));
        setAlert(typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.sampleTimeout') : 'Sample message timed out. Please try again.', "error");
      }, 5000);
      
      // Store timeout ID in window object so it can be cleared in the websocket listener
      window.currentSampleTimeout = sampleTimeoutId;
      
      reconnect_websocket(ws, function (ws) {
        const role = ($id("select-role") || {}).value.split("-")[1];
        const msg_object = { message: "SAMPLE", content: userMessageText, role: role }
        ws.send(JSON.stringify(msg_object));
        
        // Clear input field and reset role selector immediately
        { const el = $id("message"); if (el) { el.style.height = "96px"; el.value = ""; } }
        { const el = $id("select-role"); if (el) { el.value = "user"; $dispatch(el, "change"); } }
      });
    } else {
      reconnect_websocket(ws, function (ws) {
        // Create a copy of the current images array to preserve the state
        let currentImages = [...images];

        // Set the images parameter for the request
        if (currentImages.length > 0) {
          params.images = currentImages;
        } else {
          params.images = [];
        }

        ws.send(JSON.stringify(params));
        if (typeof WorkflowViewer !== 'undefined' && WorkflowViewer.setStage) {
          WorkflowViewer.setStage('input');
        }
        { const el = $id("message"); if (el) { el.style.height = "96px"; el.value = ""; } }

        // Clear all images including PDFs after sending
        images = [];
        updateFileDisplay(images);
      });
    }
    { const el = $id("select-role"); if (el) el.value = "user"; }
    { const el = document.querySelector("#role-icon i"); if (el) { el.classList.remove("fa-robot", "fa-bars"); el.classList.add("fa-face-smile"); } }
  });

  $on($id("clear"), "click", function(event) {
    event.preventDefault();
    { const el = $id("message"); if (el) { el.style.height = "100px"; el.value = ""; } }
    setInputFocus()
  });

  // #settings button removed — settings are now collapsible via #config-summary


  // Regular reset button - keeps current app
  $on($id("reset"), "click", function(event) {
    ttsStop();
    audioInit();
    resetEvent(event, false); // false = keep current app
    { const el = $id("select-role"); if (el) { el.value = "user"; $dispatch(el, "change"); } }
    // Wait for i18n to be ready before updating button text
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        const startText = webUIi18n.t('ui.session.startSession');
        { const el = $id("start-label"); if (el) el.textContent = startText; }
      });
    } else {
      // Fallback if i18nReady is not available
      const startText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
        webUIi18n.t('ui.session.startSession') : 'Start Session';
      { const el = $id("start-label"); if (el) el.textContent = startText; }
    }
    { const el = $id("model"); if (el) el.disabled = false; }
  });
  
  // Logo click - resets conversation but keeps current app
  document.querySelectorAll(".reset-area").forEach(function(_el) { _el.addEventListener("click", function(event) {
    ttsStop();
    audioInit();
    resetEvent(event, false); // false = keep current app
    { const el = $id("select-role"); if (el) { el.value = "user"; $dispatch(el, "change"); } }
    // Wait for i18n to be ready before updating button text
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        const startText = webUIi18n.t('ui.session.startSession');
        { const el = $id("start-label"); if (el) el.textContent = startText; }
      });
    } else {
      // Fallback if i18nReady is not available
      const startText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
        webUIi18n.t('ui.session.startSession') : 'Start Session';
      { const el = $id("start-label"); if (el) el.textContent = startText; }
    }
    { const el = $id("model"); if (el) el.disabled = false; }
  }); });

  $on($id("save"), "click", async function () {
    const allMessages = [];
    const initial_prompt = ($id("initial-prompt") || {}).value;
    const sysid = Math.floor(1000 + Math.random() * 9000);

    allMessages.push({"role": "system", "text": initial_prompt, "mid": sysid});

    messages.forEach(function (message, index) {
      if (index === 0 && message.role === "system") {
        return;
      }

      let message_obj;
      if (message.role === "assistant") {
        message_obj = {
          "role": message.role,
          "text": message.text,
          "mid": message.mid,
          "thinking": message.thinking
        };
      } else {
        message_obj = {
          "role": message.role,
          "text": message.text,
          "mid": message.mid
        };
      }

      if (message.image) {
        message_obj.image = message.image;
      }
      allMessages.push(message_obj);
    });

    // Get parameters but exclude initiate_from_assistant
    // (prevents automatic assistant message on import)
    const exportParams = setParams();
    delete exportParams.initiate_from_assistant;

    // Fetch monadic_state and session_context from server
    let monadicState = null;
    let serverSessionContext = null;
    let serverContextSchema = null;
    try {
      const response = await fetch('/monadic_state');
      if (!response.ok) throw new Error(`/monadic_state failed: ${response.status}`);
      const data = await response.json();
      if (data.success) {
        if (data.monadic_state) {
          monadicState = data.monadic_state;
        }
        // Get session_context from server (more reliable than frontend state)
        if (data.session_context) {
          serverSessionContext = data.session_context;
        }
        if (data.context_schema) {
          serverContextSchema = data.context_schema;
        }
      }
    } catch (e) {
      console.warn('Failed to fetch monadic_state:', e);
    }

    obj = {
      "parameters": exportParams,
      "messages": allMessages
    };

    // Include monadic_state in export if available
    if (monadicState) {
      obj.monadic_state = monadicState;
    }

    // Include session_context - prefer server-side, fallback to frontend ContextPanel
    const sessionContext = serverSessionContext ||
      (typeof ContextPanel !== 'undefined' ? ContextPanel.currentContext : null);
    const contextSchema = serverContextSchema ||
      (typeof ContextPanel !== 'undefined' ? ContextPanel.currentSchema : null);

    if (sessionContext) {
      obj.session_context = sessionContext;
    }
    if (contextSchema) {
      obj.context_schema = contextSchema;
    }

    saveObjToJson(obj, "monadic.json");
  });

  $on($id("export-pdf"), "click", function() {
    if (typeof window.exportConversationToPDF === 'function') {
      window.exportConversationToPDF();
    } else {
      console.error('PDF export function not available');
      const errorText = webUIi18n ? webUIi18n.t('ui.messages.exportError') : 'PDF export not available';
      alert(errorText);
    }
  });

  $on($id("load"), "click", function(event) {
    event.preventDefault();
    // Reset the file input and disable the import button
    { const el = $id("file-load"); if (el) el.value = ''; }
    { const el = $id("import-button"); if (el) el.disabled = true; }
    
    // Use the form handlers module if available, otherwise fallback
    if (formHandlers && formHandlers.showModalWithFocus) {
      const cleanupFn = function() {
        { const el = $id('file-load'); if (el) el.value = ''; }
        { const el = $id('import-button'); if (el) el.disabled = true; }
      };
      formHandlers.showModalWithFocus('loadModal', 'file-load', cleanupFn);
    } else {
      // Show the modal using the fallback
      bootstrap.Modal.getOrCreateInstance($id("loadModal")).show();
      
      // Store focus timer in modal's data to ensure cleanup
      const $modal = $id("loadModal");
      const existingTimer = $modal.dataset.focusTimer;

      // Clear any existing timer
      if (existingTimer) {
        clearTimeout(parseInt(existingTimer));
      }

      // Set new timer and store reference
      $modal.dataset.focusTimer = setTimeout(function () {
        { const el = $id("file-load"); if (el) el.focus(); }
        // Clear reference after use
        delete $modal.dataset.focusTimer;
      }, 500);
    }
  });

  $on($id("loadModal"), "shown.bs.modal", function () {
    { const el = $id("file-title"); if (el) el.focus(); }
  });
  
  $on($id("loadModal"), "hidden.bs.modal", function () {
    // Reset form state when modal is closed
    { const el = $id('file-load'); if (el) el.value = ''; }
    { const el = $id('import-button'); if (el) el.disabled = true; }
    $hide($id("load-spinner"));
  });

  $on($id("pdf-import"), "click", function(event) {
    event.preventDefault();
    { const el = $id("file-title"); if (el) el.value = ""; }
    { const el = $id("fileFile"); if (el) el.value = ""; }
    bootstrap.Modal.getOrCreateInstance($id("fileModal")).show();

    // Initialize storage mode radios based on current provider/model
    try {
      const appName = ($id("apps") || {}).value;
      const group = (window.apps && appName && window.apps[appName]) ? window.apps[appName]["group"] : '';
      const isOpenAI = group.toLowerCase() === 'openai';
      const model = ($id("model") || {}).value;
      const supportsPdfUpload = (typeof window.isPdfSupportedForModel === 'function') ? window.isPdfSupportedForModel(model) : false;

      // Fetch server defaults and availability
      fetch('/api/pdf_storage_defaults')
        .then(function(res) { return res.ok ? res.json() : Promise.reject(res); })
        .then(function(info) {
          const pgAvailable = !!info.pgvector_available;
          const defaultStorage = (info.default_storage || 'local').toLowerCase();

          // Enable/disable by availability
          { const el = $id("storage-local"); if (el) el.disabled = !pgAvailable; }
          // Always allow selecting Cloud to experiment; routing will still guard by provider
          { const el = $id("storage-cloud"); if (el) el.disabled = false; }

          // Decide selection
          let select = 'local';
          if (defaultStorage === 'cloud' || !pgAvailable) select = 'cloud';
          if (select === 'cloud' && ($id("storage-cloud") || {}).disabled) select = 'local';
          if (select === 'local' && ($id("storage-local") || {}).disabled) select = 'cloud';

          if (select === 'cloud') {
            { const el = $id("storage-cloud"); if (el) el.checked = true; }
          } else {
            { const el = $id("storage-local"); if (el) el.checked = true; }
          }
        }).catch(function() {
          // Fallback: prefer local if enabled, else cloud
          { const el = $id("storage-local"); if (el) el.disabled = false; }
          { const el = $id("storage-cloud"); if (el) el.disabled = false; }
          { const el = $id("storage-local"); if (el) el.checked = true; }
        });
    } catch (_) { console.warn("[PDF Modal] Storage option init failed:", _); }

    // Set a friendly placeholder for file title
    try {
      const ph = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.fileTitlePlaceholder') : 'File name will be used if not provided';
      { const el = $id("file-title"); if (el) el.setAttribute('placeholder', ph); }
    } catch (_) { console.warn("[PDF Modal] Placeholder setup failed:", _); }
  });

  let fileTitle = "";

  // Ensure event handler is properly attached when document is ready
  document.addEventListener("click", async function (e) { const _delegateTarget = e.target.closest("#uploadFile"); if (!_delegateTarget) return;
    e.preventDefault();
    
    const fileInput = $id("fileFile");
    const file = fileInput.files[0];
    
    // Check if formHandlers is available
    if (typeof formHandlers === 'undefined' || !formHandlers.uploadPdf) {
      setAlert(typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.uploadNotAvailable') : 'Upload functionality not available', "error");
      return;
    }
    
    try {
      // Disable UI elements during upload
      document.querySelectorAll("#fileModal button").forEach(function(_el) { _el.disabled = true; });
      $show($id("file-spinner"));
      
      fileTitle = ($id("file-title") || {}).value;
      
      // Use the form handlers module if available, otherwise fallback
      const response = await formHandlers.uploadPdf(file, fileTitle);
      
      // Process the response
      if (response && response.success) {
        // Clean up UI
        $hide($id("file-spinner"));
        document.querySelectorAll("#fileModal button").forEach(function(_el) { _el.disabled = false; });
        bootstrap.Modal.getOrCreateInstance($id("fileModal")).hide();
        // Decide if this was uploaded to OpenAI or local DB
        const isOpenAIUpload = !!(response.vector_store_id);
        // Refresh local PDF DB titles only for local ingestion
        if (!isOpenAIUpload) {
          ws.send(JSON.stringify({ message: "PDF_TITLES" }));
        } else {
          // Auto-refresh cloud list on successful OpenAI upload
          if (typeof refreshCloudPdfList === 'function') refreshCloudPdfList();
        }
        const uploadedFilename = response.filename || "PDF file";
        const uploadMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.uploadSuccess') : 'uploaded successfully';
        const providerNote = isOpenAIUpload ? ' (OpenAI)' : '';
        const dedupNote = (isOpenAIUpload && response.deduplicated) ? ' (deduplicated)' : '';
        setAlert(`<i class='fa-solid fa-circle-check'></i> "${uploadedFilename}" ${uploadMsg}${providerNote}${dedupNote}`, "success");
      } else {
        // Show error message from API
        const errorMessage = response && response.error ? response.error : "Failed to process PDF";
        
        // Clean up UI
        $hide($id("file-spinner"));
        document.querySelectorAll("#fileModal button").forEach(function(_el) { _el.disabled = false; });
        bootstrap.Modal.getOrCreateInstance($id("fileModal")).hide();
        
        setAlert(`${errorMessage}`, "error");
      }
      
    } catch (error) {
      console.error("Error uploading PDF:", error);
      
      // Clean up UI on error
      $hide($id("file-spinner"));
      document.querySelectorAll("#fileModal button").forEach(function(_el) { _el.disabled = false; });
      bootstrap.Modal.getOrCreateInstance($id("fileModal")).hide();
      
      // Show appropriate error message
      const errorMessage = error.statusText || error.message || "Unknown error";
      const uploadErrorMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.uploadError') : 'Error uploading file';
      setAlert(`${uploadErrorMsg}: ${errorMessage}`, "error");
    }
  });

  $on($id("doc"), "click", function(event) {
    event.preventDefault();
    { const el = $id("docLabel"); if (el) el.value = ""; }
    { const el = $id("docFile"); if (el) el.value = ""; }
    
    // Use the form handlers module if available, otherwise fallback
    if (formHandlers && formHandlers.showModalWithFocus) {
      const cleanupFn = function() {
        { const el = $id('docFile'); if (el) el.value = ''; }
        { const el = $id('convertDoc'); if (el) el.disabled = true; }
      };
      formHandlers.showModalWithFocus('docModal', 'docFile', cleanupFn);
    } else {
      // Show the modal using fallback
      bootstrap.Modal.getOrCreateInstance($id("docModal")).show();
      
      // Store focus timer in modal's data to ensure cleanup
      const $modal = $id("docModal");
      const existingTimer = $modal.dataset.focusTimer;

      // Clear any existing timer
      if (existingTimer) {
        clearTimeout(parseInt(existingTimer));
      }

      // Set new timer and store reference
      $modal.dataset.focusTimer = setTimeout(function () {
        { const el = $id("docFile"); if (el) el.focus(); }
        // Clear reference after use
        delete $modal.dataset.focusTimer;
      }, 500);
    }
  });

  $on($id("docModal"), "hidden.bs.modal", function () {
    { const el = $id('docFile'); if (el) el.value = ''; }
    { const el = $id('convertDoc'); if (el) el.disabled = true; }

    // Ensure any remaining timers are cleared
    const modalEl = this;
    const existingTimer = modalEl.dataset.focusTimer;
    if (existingTimer) {
      clearTimeout(parseInt(existingTimer));
      delete modalEl.dataset.focusTimer;
    }
  });

  // Use the form handlers module for file input validation
  if (formHandlers && formHandlers.setupFileValidation) {
    formHandlers.setupFileValidation(
      $id('docFile'), 
      $id('convertDoc')
    );
  } else {
    // Fallback to direct event handler
    $on($id("docFile"), "change", function() {
      const file = this.files[0];
      { const el = $id('convertDoc'); if (el) el.disabled = !file; }
    });
  }

  $on($id("convertDoc"), "click", async function () {
    const docInput = $id("docFile");
    const doc = docInput.files[0];
    
    try {
      const docLabel = ($id("doc-label") || {}).value || "";
      
      // Disable UI elements during processing
      document.querySelectorAll("#docModal button").forEach(function(_el) { _el.disabled = true; });
      $show($id("doc-spinner"));
      
      // Use the form handlers module if available, otherwise fallback
      const response = await formHandlers.convertDocument(doc, docLabel);
      
      // Process the response
      if (response && response.success) {
        // Extract content and append it to the message
        const content = response.content;
        const message = ($id("message") || {}).value.replace(/\n+$/, "");
        { const el = $id("message"); if (el) el.value = `${message}\n\n${content}`; }
        
        // Use the UI utilities module for resizing
        if (uiUtils && uiUtils.autoResize) {
          uiUtils.autoResize($id('message'), 100);
        } else {
          autoResizeFallback($id('message'), 100);
        }
        
        // Clean up UI
        $hide($id("doc-spinner"));
        document.querySelectorAll("#docModal button").forEach(function(_el) { _el.disabled = false; });
        bootstrap.Modal.getOrCreateInstance($id("docModal")).hide();
        $dispatch($id("back_to_bottom"), "click");
        { const el = $id("message"); if (el) el.focus(); }
      } else {
        // Show error message from API
        const errorMessage = response && response.error ? response.error : "Failed to convert document";
        
        // Clean up UI
        $hide($id("doc-spinner"));
        document.querySelectorAll("#docModal button").forEach(function(_el) { _el.disabled = false; });
        bootstrap.Modal.getOrCreateInstance($id("docModal")).hide();
        
        setAlert(`${errorMessage}`, "error");
      }
      
    } catch (error) {
      console.error("Error converting document:", error);
      
      // Clean up UI on error
      $hide($id("doc-spinner"));
      document.querySelectorAll("#docModal button").forEach(function(_el) { _el.disabled = false; });
      bootstrap.Modal.getOrCreateInstance($id("docModal")).hide();
      
      // Show appropriate error message
      const errorMessage = error.statusText || error.message || "Unknown error";
      const convertErrorMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.convertError') : 'Error converting document';
      setAlert(`${convertErrorMsg}: ${errorMessage}`, "error");
    }
  });

  // Audio/MIDI upload button
  $on($id("audio-upload"), "click", function(event) {
    event.preventDefault();
    { const el = $id("audioFile"); if (el) el.value = ""; }
    if (formHandlers && formHandlers.showModalWithFocus) {
      formHandlers.showModalWithFocus('audioUploadModal', 'audioFile', function() {
        { const el = $id('audioFile'); if (el) el.value = ''; }
        { const el = $id('uploadAudioBtn'); if (el) el.disabled = true; }
      });
    } else {
      bootstrap.Modal.getOrCreateInstance($id("audioUploadModal")).show();
    }
  });

  // Audio file input validation
  if (formHandlers && formHandlers.setupFileValidation) {
    formHandlers.setupFileValidation(
      $id('audioFile'),
      $id('uploadAudioBtn')
    );
  } else {
    $on($id("audioFile"), "change", function() {
      { const el = $id('uploadAudioBtn'); if (el) el.disabled = !this.files || this.files.length === 0; }
    });
  }

  // Audio/MIDI upload submit
  $on($id("uploadAudioBtn"), "click", async function () {
    const file = $id("audioFile").files[0];
    if (!file) return;
    try {
      document.querySelectorAll("#audioUploadModal button").forEach(function(_el) { _el.disabled = true; });
      $show($id("audio-upload-spinner"));
      const response = await formHandlers.uploadAudioFile(file);
      if (response && response.success) {
        const filename = response.filename;
        const message = ($id("message") || {}).value.replace(/\n+$/, "");
        const instruction = `Please analyze the file: ${filename}`;
        { const el = $id("message"); if (el) el.value = message ? `${message}\n\n${instruction}` : instruction; }
        if (uiUtils && uiUtils.autoResize) {
          uiUtils.autoResize($id('message'), 100);
        }
        $hide($id("audio-upload-spinner"));
        document.querySelectorAll("#audioUploadModal button").forEach(function(_el) { _el.disabled = false; });
        bootstrap.Modal.getOrCreateInstance($id("audioUploadModal")).hide();
        { const el = $id("message"); if (el) el.focus(); }
      } else {
        const errorMsg = response && response.error ? response.error : "Upload failed";
        $hide($id("audio-upload-spinner"));
        document.querySelectorAll("#audioUploadModal button").forEach(function(_el) { _el.disabled = false; });
        bootstrap.Modal.getOrCreateInstance($id("audioUploadModal")).hide();
        setAlert(errorMsg, "error");
      }
    } catch (error) {
      $hide($id("audio-upload-spinner"));
      document.querySelectorAll("#audioUploadModal button").forEach(function(_el) { _el.disabled = false; });
      bootstrap.Modal.getOrCreateInstance($id("audioUploadModal")).hide();
      setAlert("Upload error: " + (error.statusText || error.message || "Unknown error"), "error");
    }
  });

  // Cloud PDF list handlers
  async function refreshCloudPdfList() {
    try {
      const $list = $id("cloud-pdf-list");
      if (!$list) return;
      if ($list) $list.innerHTML = ('<span class="text-secondary">Loading...</span>');
      const listResp = await fetch('/openai/pdf?action=list');
      const res = listResp.ok ? await listResp.json() : null;
      if (!res || !res.success) {
        if ($list) $list.innerHTML = ('<span class="text-danger">Failed to load</span>');
        return;
      }
      // Update Cloud meta (move Vector Store ID to footer; keep header clean)
      try {
        const vs = res.vector_store_id || '';
        { const el = $id("cloud-pdf-meta"); if (el) el.textContent = vs ? `Vector Store ID: ${vs}` : ''; }
        // Do not show VS in header to avoid confusion
        // Leave #cloud-pdf-info handling to status refresher
      } catch (_) { console.warn("[PDF Listing] Metadata update failed:", _); }
      const files = res.files || [];
      if (files.length === 0) {
        if ($list) $list.innerHTML = (`<span class="text-secondary">${getTranslation('ui.noPdfsCloud', 'No cloud PDFs')}</span>`);
        return;
      }
      const rows = files.map(f => {
        const name = (f.filename || f.id || '').replace(/</g,'&lt;');
        const attrName = name.replace(/"/g,'&quot;').replace(/'/g,'&#39;');
        const status = f.status || '';
        return `<div class="d-flex align-items-center justify-content-between py-1 border-bottom cloud-pdf-row">
          <span class="cloud-pdf-name">${name} <span class="text-muted">${status ? '('+status+')' : ''}</span></span>
          <button class="btn btn-sm btn-outline-secondary" data-action="cloud-delete-file" data-file-id="${f.id}" data-file-name="${attrName}"><i class="fa-regular fa-trash-can text-secondary"></i></button>
        </div>`;
      });
      if ($list) $list.innerHTML = (rows.join(''));
    } catch (e) {
      { const el = $id("cloud-pdf-list"); if (el) el.innerHTML = '<span class="text-danger">Failed to load</span>'; }
    }
  }

  document.addEventListener('click', function(e) { if (!e.target.closest('#cloud-pdf-refresh')) return;
    e.preventDefault();
    refreshCloudPdfList();
  });

  document.addEventListener('click', async function(e) { if (!e.target.closest('#cloud-pdf-clear')) return;
    e.preventDefault();
    try {
      const msg = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.clearAllCloudPdfs') : 'Clear all Cloud PDFs?';
      if (!confirm(msg)) return;
      const clearRes = await fetch('/openai/pdf?action=clear', { method: 'DELETE' });
      if (!clearRes.ok) throw new Error(`Clear failed: ${clearRes.status}`);
      refreshCloudPdfList();
      setAlert('<i class="fa-solid fa-circle-check"></i> Cloud PDFs cleared', 'success');
    } catch (err) {
      setAlert('Failed to clear Cloud PDFs', 'error');
    }
  });

  document.addEventListener('click', async function(e) { const _delegateTarget = e.target.closest('button[data-action="cloud-delete-file"]'); if (!_delegateTarget) return;
    e.preventDefault();
    const fid = _delegateTarget.dataset.fileId;
    const fname = _delegateTarget.dataset.fileName || _delegateTarget.closest('.cloud-pdf-row').querySelector('.cloud-pdf-name').textContent.trim();
    if (!fid) return;
    // Detect iOS/iPadOS
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
                  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    if (isIOS) {
      const base = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.pdfDeleteConfirmation') : 'Are you sure you want to delete';
      if (!confirm(`${base} ${fname}?`)) return;
      try {
        const delRes = await fetch(`/openai/pdf?action=delete&file_id=${encodeURIComponent(fid)}`, { method: 'DELETE' });
        if (!delRes.ok) throw new Error(`Delete failed: ${delRes.status}`);
        refreshCloudPdfList();
        setAlert('<i class="fa-solid fa-circle-check"></i> Cloud PDF deleted', 'success');
      } catch (err) {
        setAlert('Failed to delete Cloud PDF', 'error');
      }
    } else {
      // Reuse the same Bootstrap modal as local delete
      bootstrap.Modal.getOrCreateInstance($id("pdfDeleteConfirmation")).show();
      { const el = $id("pdfToDelete"); if (el) el.textContent = fname; }
      { const el2 = $id("pdfDeleteConfirmed"); if (el2) el2.onclick = async function (event) {
        event.preventDefault();
        try {
          const delRes2 = await fetch(`/openai/pdf?action=delete&file_id=${encodeURIComponent(fid)}`, { method: 'DELETE' });
          if (!delRes2.ok) throw new Error(`Delete failed: ${delRes2.status}`);
          bootstrap.Modal.getOrCreateInstance($id("pdfDeleteConfirmation")).hide();
          { const el3 = $id("pdfToDelete"); if (el3) el3.textContent = ""; }
          refreshCloudPdfList();
          setAlert('<i class="fa-solid fa-circle-check"></i> Cloud PDF deleted', 'success');
        } catch (err) {
          bootstrap.Modal.getOrCreateInstance($id("pdfDeleteConfirmation")).hide();
          { const el3 = $id("pdfToDelete"); if (el3) el3.textContent = ""; }
          setAlert('Failed to delete Cloud PDF', 'error');
        }
      }; }
    }
  });

  // Initial fetch when pdf panel is present
  setTimeout(refreshCloudPdfList, 500);

  // Fetch and display overall PDF storage status (mode/local/cloud presence)
  async function refreshPdfStorageStatus() {
    try {
      const statusResp = await fetch('/api/pdf_storage_status');
      const res = statusResp.ok ? await statusResp.json() : null;
      if (!res || !res.success) return;
      const mode = res.mode || 'local';
      const vs = res.vector_store_id || '';
      // Footer: full Vector Store ID when available
      { const el = $id("cloud-pdf-meta"); if (el) el.textContent = vs ? `Vector Store ID: ${vs}` : ''; }
      // Local header: show ready only; remove redundant (empty)
      { const el = $id("local-pdf-info"); if (el) el.textContent = res.local_present ? '(ready)' : ''; }

      // Toggle sections based on current mode
      const showCloud = (mode === 'cloud');
      $toggle($id("cloud-pdf-section"), showCloud);
      $toggle($id("local-pdf-section"), !showCloud);
      // Auto-refresh the visible list to keep UI fresh
      if (showCloud) {
        refreshCloudPdfList();
      } else {
        if (window.ws) ws.send(JSON.stringify({ message: "PDF_TITLES" }));
      }
    } catch (_) { /* ignore */ }
  }
  setTimeout(refreshPdfStorageStatus, 700);

  // Local PDF controls
  document.addEventListener('click', function(e) { if (!e.target.closest('#local-pdf-refresh')) return;
    e.preventDefault();
    if (window.ws) ws.send(JSON.stringify({ message: "PDF_TITLES" }));
  });
  document.addEventListener('click', function(e) { if (!e.target.closest('#local-pdf-clear')) return;
    e.preventDefault();
    const msg = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.clearAllLocalPdfs') : 'Clear all Local PDFs?';
    if (!confirm(msg)) return;
    if (window.ws) ws.send(JSON.stringify({ message: "DELETE_ALL_PDFS" }));
  });

  $on($id("url"), "click", function(event) {
    event.preventDefault();
    { const el = $id("urlLabel"); if (el) el.value = ""; }
    { const el = $id("pageURL"); if (el) el.value = ""; }
    
    // Use the form handlers module if available, otherwise fallback
    if (formHandlers && formHandlers.showModalWithFocus) {
      const cleanupFn = function() {
        { const el = $id('pageURL'); if (el) el.value = ''; }
        { const el = $id('fetchPage'); if (el) el.disabled = true; }
      };
      formHandlers.showModalWithFocus('urlModal', 'pageURL', cleanupFn);
    } else {
      // Show the modal using fallback
      bootstrap.Modal.getOrCreateInstance($id("urlModal")).show();
      
      // Store focus timer in modal's data to ensure cleanup
      const $modal = $id("urlModal");
      const existingTimer = $modal.dataset.focusTimer;

      // Clear any existing timer
      if (existingTimer) {
        clearTimeout(parseInt(existingTimer));
      }

      // Set new timer and store reference
      $modal.dataset.focusTimer = setTimeout(function () {
        { const el = $id("pageURL"); if (el) el.focus(); }
        // Clear reference after use
        delete $modal.dataset.focusTimer;
      }, 500);
    }
  });

  $on($id("urlModal"), "hidden.bs.modal", function () {
    { const el = $id('pageURL'); if (el) el.value = ''; }
    { const el = $id('fetchPage'); if (el) el.disabled = true; }

    // Ensure any remaining timers are cleared
    const modalEl = this;
    const existingTimer = modalEl.dataset.focusTimer;
    if (existingTimer) {
      clearTimeout(parseInt(existingTimer));
      delete modalEl.dataset.focusTimer;
    }
  });

  // Use the form handlers module for URL input validation
  if (formHandlers && formHandlers.setupUrlValidation) {
    formHandlers.setupUrlValidation(
      $id('pageURL'), 
      $id('fetchPage')
    );
  } else {
    // Fallback to direct event handler
    var _urlEl = $id("pageURL");
    if (_urlEl) {
      ["change", "keyup", "input"].forEach(function(_evt) {
        _urlEl.addEventListener(_evt, function() {
          var url = this.value;
          // check if url is a valid url starting with http or https
          var validUrl = url.match(/^(http|https):\/\/[^ "]+$/);
          var _fetchEl = $id('fetchPage');
          if (_fetchEl) _fetchEl.disabled = !validUrl;
        });
      });
    }
  }

  $on($id("fetchPage"), "click", async function () {
    const url = ($id("pageURL") || {}).value;
    
    try {
      const urlLabel = ($id("urlLabel") || {}).value || "";
      
      // Disable UI elements during processing
      document.querySelectorAll("#urlModal button").forEach(function(_el) { _el.disabled = true; });
      $show($id("url-spinner"));
      
      // Use the form handlers module if available, otherwise fallback
      const response = await formHandlers.fetchWebpage(url, urlLabel);
      
      // Process the response
      if (response && response.success) {
        // Extract content and append it to the message
        const content = response.content;
        const message = ($id("message") || {}).value.replace(/\n+$/, "");
        { const el = $id("message"); if (el) el.value = `${message}\n\n${content}`; }
        
        // Use the UI utilities module for resizing
        if (uiUtils && uiUtils.autoResize) {
          uiUtils.autoResize($id('message'), 100);
        } else {
          autoResizeFallback($id('message'), 100);
        }
        
        // Clean up UI
        $hide($id("url-spinner"));
        document.querySelectorAll("#urlModal button").forEach(function(_el) { _el.disabled = false; });
        bootstrap.Modal.getOrCreateInstance($id("urlModal")).hide();
        $dispatch($id("back_to_bottom"), "click");
        { const el = $id("message"); if (el) el.focus(); }
      } else {
        // Show error message from API
        const errorMessage = response && response.error ? response.error : "Failed to fetch webpage";
        
        // Clean up UI
        $hide($id("url-spinner"));
        document.querySelectorAll("#urlModal button").forEach(function(_el) { _el.disabled = false; });
        bootstrap.Modal.getOrCreateInstance($id("urlModal")).hide();
        
        setAlert(`${errorMessage}`, "error");
      }
      
    } catch (error) {
      console.error("Error fetching webpage:", error);
      
      // Clean up UI on error
      $hide($id("url-spinner"));
      document.querySelectorAll("#urlModal button").forEach(function(_el) { _el.disabled = false; });
      bootstrap.Modal.getOrCreateInstance($id("urlModal")).hide();
      
      // Show appropriate error message
      const errorMessage = error.statusText || error.message || "Unknown error";
      const fetchErrorMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.fetchError') : 'Error fetching webpage';
      setAlert(`${fetchErrorMsg}: ${errorMessage}`, "error");
    }
  });

  $on($id("temperature"), "input", function() {
    { const el = $id("temperature-value"); if (el) el.textContent = parseFloat(this.value).toFixed(1); }
  });

  $on($id("presence-penalty"), "input", function() {
    { const el = $id("presence-penalty-value"); if (el) el.textContent = parseFloat(this.value).toFixed(1); }
  });

  $on($id("frequency-penalty"), "input", function() {
    { const el = $id("frequency-penalty-value"); if (el) el.textContent = parseFloat(this.value).toFixed(1); }
  });

  //////////////////////////////
  // Set up the initial state of the UI
  //////////////////////////////

  // Direct DOM access without storing references
  // Scroll button handlers with keyboard support
  function scrollToTop(e) {
    if (e) e.preventDefault();
    const scrollTime = window.UIConfig ? 
      window.UIConfig.TIMING.SCROLL_ANIMATION : 500;
    { const el = $id("main"); if (el) el.scrollTo({ top: 0, behavior: "smooth" }); }
  }
  
  function scrollToBottom(e) {
    if (e) e.preventDefault();
    const scrollTime = window.UIConfig ? 
      window.UIConfig.TIMING.SCROLL_ANIMATION : 500;
    { const el = $id("main"); if (el) el.scrollTo({ top: el.scrollHeight, behavior: "smooth" }); }
  }

  // Click handlers
  $on($id("back_to_top"), "click", scrollToTop);
  $on($id("back_to_bottom"), "click", scrollToBottom);
  
  // Keyboard handlers (Enter and Space)
  $on($id("back_to_top"), "keydown", function(e) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      scrollToTop();
    }
  });
  
  $on($id("back_to_bottom"), "keydown", function(e) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      scrollToBottom();
    }
  });

  // Define originalParams globally to avoid reference errors
  window.originalParams = {};
  resetParams();

  // Restore STT model from cookie
  const savedSTTModel = getCookie("stt-model");
  if (savedSTTModel) {
    { const el = $id("stt-model"); if (el) el.value = savedSTTModel; }
    params["stt_model"] = savedSTTModel;
  }

  $on($id("tts-provider"), "change", function() {
    const oldProvider = params["tts_provider"];
    params["tts_provider"] = ($id("tts-provider") || {}).value;
    
    // Reset audio elements when switching TTS providers
    if (oldProvider !== params["tts_provider"] && typeof window.resetAudioElements === 'function') {
      window.resetAudioElements();
    }
    
    // Hide all voice selection elements first
    $hide($id("elevenlabs-voices"));
    $hide($id("openai-voices"));
    $hide($id("gemini-voices"));
    $hide($id("mistral-voices"));
    $hide($id("grok-voices"));
    $hide($id("webspeech-voices"));
    $show($id("tts-speed-container")); // Show speed slider by default (hidden for providers that don't support it)

    // Show the appropriate voice selection based on provider
    if (params["tts_provider"] === "elevenlabs" || params["tts_provider"] === "elevenlabs-flash" || params["tts_provider"] === "elevenlabs-multilingual" || params["tts_provider"] === "elevenlabs-v3") {
      $show($id("elevenlabs-voices"));
    } else if (params["tts_provider"] === "gemini-flash" || params["tts_provider"] === "gemini-pro") {
      $show($id("gemini-voices"));
    } else if (params["tts_provider"] === "mistral") {
      $show($id("mistral-voices"));
      $hide($id("tts-speed-container"));
    } else if (params["tts_provider"] === "grok") {
      // Grok TTS does not support speed control (no server-side speed param;
      // playback rate handled client-side via AVAudioPlayer in native clients).
      $show($id("grok-voices"));
      $hide($id("tts-speed-container"));
    } else if (params["tts_provider"] === "webspeech") {
      $show($id("webspeech-voices"));
      // Initialize Web Speech API voices if they haven't been loaded
      if (typeof initWebSpeech === 'function') {
        initWebSpeech();
      }
    } else {
      // Default for OpenAI providers
      $show($id("openai-voices"));
    }

    setCookie("tts-provider", params["tts_provider"], 30);
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('tts_provider_change');
    }
  });

  $on($id("tts-voice"), "change", function() {
    params["tts_voice"] = ($id("tts-voice") || {}).value;
    setCookie("tts-voice", params["tts_voice"], 30);
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('tts_voice_change');
    }
  });

  $on($id("elevenlabs-tts-voice"), "change", function() {
    params["elevenlabs_tts_voice"] = ($id("elevenlabs-tts-voice") || {}).value;
    setCookie("elevenlabs-tts-voice", params["elevenlabs_tts_voice"], 30);
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('elevenlabs_voice_change');
    }
  });

  $on($id("gemini-tts-voice"), "change", function() {
    params["gemini_tts_voice"] = ($id("gemini-tts-voice") || {}).value;
    setCookie("gemini-tts-voice", params["gemini_tts_voice"], 30);
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('gemini_voice_change');
    }
  });

  $on($id("grok-tts-voice"), "change", function() {
    params["grok_tts_voice"] = ($id("grok-tts-voice") || {}).value;
    setCookie("grok-tts-voice", params["grok_tts_voice"], 30);
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('grok_voice_change');
    }
  });

  $on($id("stt-model"), "change", function() {
    params["stt_model"] = ($id("stt-model") || {}).value;
    setCookie("stt-model", params["stt_model"], 30);
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('stt_model_change');
    }
  });

  $on($id("conversation-language"), "change", function() {
    params["conversation_language"] = ($id("conversation-language") || {}).value;
    setCookie("conversation-language", params["conversation_language"], 30);
    // Also update asr_lang for STT/TTS
    params["asr_lang"] = params["conversation_language"];
    
    // Update RTL/LTR for message display based on conversation language
    updateRTLInterface(params["conversation_language"]);
    
    // Update image button visibility to ensure correct translations
    if (typeof window.checkAndUpdateImageButtonVisibility === 'function') {
      window.checkAndUpdateImageButtonVisibility();
    }

    // If WebSocket is open, send UPDATE_LANGUAGE message to server
    if (window.ws && window.ws.readyState === WebSocket.OPEN) {
      const message = {
        message: "UPDATE_LANGUAGE",
        new_language: params["conversation_language"]
      };
      window.ws.send(JSON.stringify(message));
    } else {
      console.warn("Cannot send UPDATE_LANGUAGE - WebSocket not open");
    }

    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('conversation_language_change');
    }
  });

  $on($id("tts-speed"), "input", function() {
    { const el = $id("tts-speed-value"); if (el) el.textContent = parseFloat(this.value).toFixed(2); }
    params["tts_speed"] = parseFloat(this.value);
    setCookie("tts-speed", params["tts_speed"], 30);
    if (!isParamBroadcastSuppressed()) {
      broadcastParamsUpdate('tts_speed_change');
    }
  });

  $on($id("error-close"), "click", function(event) {
    event.preventDefault();
  })

  $on($id("alert-close"), "click", function(event) {
    event.preventDefault();
    $hide($id("alert-box"));
  })

  // Prompt toggle buttons (mutually exclusive, both can be off)
  window.setPromptView = function(view, animate) {
    const speed = animate ? 100 : 0;

    // Update button active state and chevron icons
    { const el = $id("prompt-toggle-assistant"); if (el) el.classList.toggle("active", view === 'assistant'); }
    { const el = $id("prompt-icon-assistant"); if (el) { el.classList.toggle("fa-chevron-down", view === 'assistant'); el.classList.toggle("fa-chevron-right", view !== 'assistant'); } }
    { const el = $id("prompt-toggle-aiuser"); if (el) el.classList.toggle("active", view === 'aiuser'); }
    { const el = $id("prompt-icon-aiuser"); if (el) { el.classList.toggle("fa-chevron-down", view === 'aiuser'); el.classList.toggle("fa-chevron-right", view !== 'aiuser'); } }

    // Show/hide textareas
    if (view === 'assistant') {
      $hide($id("ai-user-initial-prompt"));
      { const el = $id("initial-prompt"); if (el) { $show(el); autoResize(el, 0); } }
    } else if (view === 'aiuser') {
      $hide($id("initial-prompt"));
      { const el = $id("ai-user-initial-prompt"); if (el) { $show(el); autoResize(el, 0); } }
    } else {
      $hide($id("initial-prompt"));
      $hide($id("ai-user-initial-prompt"));
    }
  };

  $on($id("prompt-toggle-assistant"), "click", function() {
    window.setPromptView(this.classList.contains("active") ? 'hidden' : 'assistant', true);
  });
  $on($id("prompt-toggle-aiuser"), "click", function() {
    window.setPromptView(this.classList.contains("active") ? 'hidden' : 'aiuser', true);
  });

  // Disable voice features for browsers that don't support them, and for iOS/iPadOS
  if (!runningOnChrome && !runningOnEdge && !runningOnSafari || 
     /iPad|iPhone|iPod/.test(navigator.userAgent)) {
    // Hide the entire voice input row instead of just the button
    $hide($id("voice-input-row"));
    $hide($id("auto-speech"));
    $hide($id("auto-speech-form"));
    // Set message placeholder to standard text - simplified without voice
    // Will be properly translated when i18n initializes
  } else {
    // Show voice input row
    $show($id("voice-input-row"));
    // Set message placeholder will be handled by i18n initialization
  }

  $on($id("select-role"), "change", function() {
    const role = this.value;
    const _icon = document.querySelector("#role-icon i");
    if (!_icon) return;
    if (role === "user" || role === "sample-user") {
      _icon.classList.remove("fa-robot", "fa-bars"); _icon.classList.add("fa-face-smile");
    } else if (role === "sample-assistant") {
      _icon.classList.remove("fa-face-smile", "fa-bars"); _icon.classList.add("fa-robot");
    } else if (role === "sample-system") {
      _icon.classList.remove("fa-face-smile", "fa-robot"); _icon.classList.add("fa-bars");
    }
  });

  const selectedApp = $id('apps');
  if (selectedApp && selectedApp.selectedIndex === -1) {
    selectedApp.selectedIndex = 0;
  }

  const fileInput = $id('file-load');
  const loadButton = $id('import-button');
  const loadForm = document.querySelector('#loadModal form');

  // Handle form submission with async/await pattern
  loadForm.addEventListener('submit', async function(event) {
    event.preventDefault();

    const file = fileInput.files[0];
    if (!file) {
      setAlert(typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.selectFileImport') : 'Please select a file to import', "error");
      return;
    }
    
    try {
      // Set import flags before processing to prevent auto-assistant and auto-speech
      window.isProcessingImport = true;
      window.skipAssistantInitiation = true;

      $show($id("monadic-spinner"));
      document.querySelectorAll("#loadModal button").forEach(function(_el) { _el.disabled = true; });
      $show($id("load-spinner"));

      // Use the form handlers module if available, otherwise fallback
      const response = await formHandlers.importSession(file);

      // Process the response
      if (response && response.success) {
        // Clean up UI after successful import
        bootstrap.Modal.getOrCreateInstance($id("loadModal")).hide();
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.sessionImported') : 'Session imported successfully'}`, "success");

        // Don't clear messages here - let WebSocket 'past_messages' handler do it
        // This prevents race condition where user clicks "Continue Session" before messages arrive

        // Server will push data via WebSocket - no reload needed
        // The WebSocket 'parameters' handler will set the app name via loadParams
      } else {
        // Clear import flags on server error
        window.isProcessingImport = false;
        window.skipAssistantInitiation = false;

        // Show error message from API
        const errorMessage = response && response.error ? response.error : "Unknown error occurred";
        setAlert(`${errorMessage}`, "error");

        // Keep modal open to allow another attempt
        document.querySelectorAll("#loadModal button").forEach(function(_el) { _el.disabled = false; });
        $hide($id("load-spinner"));
      }
      
    } catch (error) {
      console.error("Error importing session:", error);

      // Clear import flags on error
      window.isProcessingImport = false;
      window.skipAssistantInitiation = false;

      // Show error message
      const errorMessage = error.statusText || error.message || "Unknown error";
      const importErrorMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.importError') : 'Error importing session';
      setAlert(`${importErrorMsg}: ${errorMessage}`, "error");

      // Hide modal since there was an AJAX error
      bootstrap.Modal.getOrCreateInstance($id("loadModal")).hide();

    } finally {
      // Always clean up UI elements
      $hide($id("monadic-spinner"));
      document.querySelectorAll("#loadModal button").forEach(function(_el) { _el.disabled = false; });
      $hide($id("load-spinner"));
      if (fileInput) fileInput.value = '';
    }
  });

  // Enable/disable load button based on file selection
  if (formHandlers && formHandlers.setupFileValidation) {
    formHandlers.setupFileValidation(
      $id('file-load'),
      $id('import-button')
    );
  } else {
    // Fallback to direct event handler
    fileInput.addEventListener('change', function () {
      if (fileInput.files.length > 0) {
        if (loadButton) loadButton.disabled = false;
      } else {
        if (loadButton) loadButton.disabled = true;
      }
    });
  }

  const fileFile = $id('fileFile');
  const fileButton = $id('uploadFile');

  // Use the form handlers module for file upload validation
  if (formHandlers && formHandlers.setupFileValidation) {
    formHandlers.setupFileValidation(
      $id('fileFile'),
      $id('uploadFile')
    );
  } else {
    // Fallback to direct event handler
    fileFile.addEventListener('change', function () {
      if (fileFile.files.length > 0) {
        if (fileButton) fileButton.disabled = false;
      } else {
        if (fileButton) fileButton.disabled = true;
      }
    });
  }

  // Initialize tooltips with delegated observation for dynamically added elements
  {
    const discourseEl = $id("discourse");
    if (discourseEl) {
      // Initialize tooltips on existing elements
      discourseEl.querySelectorAll('.card-header [title]').forEach(function(el) {
        new bootstrap.Tooltip(el, { delay: { show: 0, hide: 0 }, container: 'body' });
      });
      // Observe for new elements and initialize tooltips on them
      const tooltipObserver = new MutationObserver(function() {
        discourseEl.querySelectorAll('.card-header [title]').forEach(function(el) {
          if (!bootstrap.Tooltip.getInstance(el)) {
            new bootstrap.Tooltip(el, { delay: { show: 0, hide: 0 }, container: 'body' });
          }
        });
      });
      tooltipObserver.observe(discourseEl, { childList: true, subtree: true });
    }
  }

  // Add global function to clean up all tooltips
  window.cleanupAllTooltips = function() {
    document.querySelectorAll('.tooltip').forEach(function(_el) { _el.remove(); }); // Directly remove all tooltip elements
    document.querySelectorAll("[data-bs-original-title]").forEach(function(_el) { var _tip = bootstrap.Tooltip.getInstance(_el); if (_tip) _tip.dispose(); }); // Bootstrap 5
    document.querySelectorAll("[data-original-title]").forEach(function(_el) { var _tip = bootstrap.Tooltip.getInstance(_el); if (_tip) _tip.dispose(); }); // Bootstrap 4
  };

  // Remove tooltips when clicking anywhere in the document
  document.addEventListener('click', function(e) {
    if (!e.target.closest('.func-play, .func-stop, .func-copy, .func-delete, .func-edit')) {
      cleanupAllTooltips();
    }
  });

  $on($id("message"), "keydown", function(event) {
    if (event.key === "Tab") {
      event.preventDefault();
      { const el = $id("send"); if (el) el.focus(); }
    }
  });

  $on($id("select-role"), "keydown", function(event) {
    if (event.key === "Tab") {
      event.preventDefault();
      { const el = $id("send"); if (el) el.focus(); }
    }
  });

  // Helper function to check if a language is RTL (defined globally)
  function isRTLLanguage(langCode) {
    const rtlLanguages = ["ar", "he", "fa", "ur"];
    return rtlLanguages.includes(langCode);
  }
  
  // Helper function to update RTL for message areas only (defined globally)
  function updateRTLInterface(langCode) {
    if (isRTLLanguage(langCode)) {
      document.body.classList.add("rtl-messages");
    } else {
      document.body.classList.remove("rtl-messages");
    }
  }
  
  (function () {
    if (typeof window.setPromptView === 'function') window.setPromptView('hidden', false);
    
    // Initialize interface language from cookie
    // Load saved conversation language
    const savedConversationLanguage = getCookie("conversation-language");
    if (savedConversationLanguage) {
      { const el = $id("conversation-language"); if (el) el.value = savedConversationLanguage; }
      params["conversation_language"] = savedConversationLanguage;
      params["asr_lang"] = savedConversationLanguage;
      // Set RTL/LTR on page load
      updateRTLInterface(savedConversationLanguage);
    } else {
      // Default to auto if no cookie
      params["conversation_language"] = "auto";
      params["asr_lang"] = "auto";
    }
    
    // Setup search dialog close handlers - UI elements will close search on click
    if (uiUtils && uiUtils.setupSearchCloseHandlers) {
      // Register the handlers on main UI elements
      uiUtils.setupSearchCloseHandlers();
      
      // Also register special handler for message text input
      // This ensures search is closed when focusing the input field
      $on($id("message"), "focus", function() {
        if (uiUtils.simulateEscapeKey) {
          uiUtils.simulateEscapeKey();
        }
      });
    }
    
    // Set focus to the apps dropdown instead of start button
    { const el = $id("apps"); if (el) el.focus(); }
    
    // Common viewport setup for all devices
    const viewportMeta = document.querySelector('meta[name="viewport"]');
    if (viewportMeta && !viewportMeta.content.includes('viewport-fit=cover')) {
      viewportMeta.setAttribute('content', 'width=device-width, initial-scale=1, shrink-to-fit=no, viewport-fit=cover');
    }
    
    // Apply only minimum iOS class without special behavior
    if (/iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream) {
      document.body.classList.add("ios-device");
      
      // Special handling for iOS to ensure proper scrolling
      if (window.innerWidth < 600) {
        // Run optimization immediately and after a small delay
        optimizeMobileScrolling();
        setTimeout(optimizeMobileScrolling, window.UIConfig ? window.UIConfig.TIMING.SCROLL_ANIMATION : 500);
      }
    }
    
    // Always run mobile optimization on page load for small screens
    if (window.innerWidth < 600) {
      // Initial optimization
      optimizeMobileScrolling();
      
      // Run again after load is complete to ensure proper sizing
      window.addEventListener('load', function() {
        optimizeMobileScrolling();
      });
    }
    
    // Run customizable select setup before other UI operations
    setupCustomDropdown();
    
    // Apply enhanced styling to other select elements
    setupEnhancedSelects();
    
    // Ensure consistent height between the apps select and the custom dropdown group headers
    setTimeout(function() {
      const appsHeight = ($id("apps") || {}).offsetHeight;
      document.querySelectorAll(".custom-dropdown-group").forEach(function(_el) { _el.style.height = appsHeight + "px"; });
    }, 100);
    
    // Initialize app icon in select dropdown
    updateAppSelectIcon();
    
    function setupCustomDropdown() {
      const $select = $id("apps");
      const $customDropdown = $id("custom-apps-dropdown");
      let isDropdownOpen = false;
      
      // Function to close the dropdown
      function closeDropdown() {
        if (isDropdownOpen) {
          $hide($customDropdown);
          isDropdownOpen = false;
          // Remove the document click handler
          /* removed: document off "click.customDropdown" */;
        }
      }
      
      // Function to open the dropdown
      function openDropdown() {
        if (!isDropdownOpen) {
          $show($customDropdown);
          isDropdownOpen = true;
          
          // Get current selected value
          const currentValue = $select.value;
          
          // Clear any existing highlights
          document.querySelectorAll(".custom-dropdown-option.highlighted").forEach(function(_el) { _el.classList.remove("highlighted"); });
          
          // First, collapse all group containers
          document.querySelectorAll(".group-container").forEach(function(_el) { _el.classList.add("collapsed"); });
          document.querySelectorAll(".custom-dropdown-group .group-toggle-icon i").forEach(function(_el) { _el.classList.remove("fa-chevron-down"); _el.classList.add("fa-chevron-right"); });
          
          // Find and highlight the option matching the current selection
          const $selectedOption = document.querySelector(`.custom-dropdown-option[data-value="${currentValue}"]`);
          if ($selectedOption) {
            $selectedOption.classList.add("highlighted");

            // Find the parent group container and expand it
            const $parentGroup = $selectedOption.closest(".group-container");
            if ($parentGroup) {
              $parentGroup.classList.remove("collapsed");

              // Update the toggle icon
              const groupId = $parentGroup.id;
              const groupName = groupId.replace("group-", "");
              const $groupHeader = document.querySelector(`.custom-dropdown-group[data-group="${groupName}"]`);
              if ($groupHeader) { const _icon = $groupHeader.querySelector(".group-toggle-icon i"); if (_icon) { _icon.classList.remove("fa-chevron-right"); _icon.classList.add("fa-chevron-down"); } }
            }
            
            // Ensure the selected option is visible in the dropdown
            ensureVisibleInDropdown($selectedOption, $customDropdown);
          }
          
          // Position the dropdown relative to the select
          positionDropdown();
          
          // Update the height of group headers to match the apps select
          const appsHeight = ($id("apps") || {}).offsetHeight;
          document.querySelectorAll(".custom-dropdown-group").forEach(function(_el) { _el.style.height = appsHeight + "px"; });
          
          // Set up click outside handler with a small delay to avoid immediate closing
          setTimeout(function() {
            document.addEventListener("click", function _customDropdownClick(e) {
              // Check if click is outside the dropdown and trigger elements
              // Also check if the click is not on a group header (which toggles group expansion)
              if (!e.target.closest("#custom-apps-dropdown, #app-select-overlay, .app-select-wrapper")) {
                closeDropdown();
              }
            });
          }, 10);
        }
      }
      
      // Show custom dropdown when clicking on the overlay div
      $on($id("app-select-overlay"), "click", function(e) {
        e.preventDefault();
        e.stopPropagation();
        
        // Toggle custom dropdown
        if (isDropdownOpen) {
          closeDropdown();
        } else {
          openDropdown();
        }
      });
      
      // Also add click handler to the wrapper as a fallback
      { const _wrapEl = document.querySelector(".app-select-wrapper"); if (_wrapEl) _wrapEl.addEventListener("click", function(e) {
        if (e.target.matches("#app-select-overlay")) {
          // Already handled by the overlay click handler
          return;
        }
        e.preventDefault();
        e.stopPropagation();

        // Toggle custom dropdown
        if (isDropdownOpen) {
          closeDropdown();
        } else {
          openDropdown();
        }
      }); }
      
      // Add global ESC key handler that works regardless of focus
      document.addEventListener("keydown", function(e) {
        if (e.key === "Escape" && isDropdownOpen) {
          e.preventDefault();
          e.stopPropagation();
          closeDropdown();
          return false;
        }
      });
      
      // Add keyboard navigation to the custom dropdown
      document.addEventListener("keydown", function(e) {
        if (isDropdownOpen) {
          const $options = Array.from(document.querySelectorAll(".custom-dropdown-option:not(.disabled)"));
          const $highlighted = document.querySelector(".custom-dropdown-option.highlighted");
          let index = $highlighted ? $options.indexOf($highlighted) : -1;

          switch (e.key) {
            case "ArrowDown":
              e.preventDefault();
              e.stopPropagation();
              // Move to next non-disabled option
              if (index < $options.length - 1) {
                if ($highlighted) {
                  $highlighted.classList.remove("highlighted");
                }
                const $next = $options[index + 1];
                if ($next) $next.classList.add("highlighted");

                // Ensure the element is visible in the dropdown
                ensureVisibleInDropdown($next, $customDropdown);
              } else if (index === -1) {
                // No selection yet, select first non-disabled
                const $first = $options[0];
                if ($first) $first.classList.add("highlighted");
                ensureVisibleInDropdown($first, $customDropdown);
              } else {
                // Already at the bottom, circle back to the first non-disabled item
                if ($highlighted) $highlighted.classList.remove("highlighted");
                const $first = $options[0];
                if ($first) $first.classList.add("highlighted");
                ensureVisibleInDropdown($first, $customDropdown);
              }
              return false;
              break;

            case "ArrowUp":
              e.preventDefault();
              e.stopPropagation();
              // Move to previous non-disabled option
              if (index > 0) {
                if ($highlighted) $highlighted.classList.remove("highlighted");
                const $prev = $options[index - 1];
                if ($prev) $prev.classList.add("highlighted");

                // Ensure the element is visible in the dropdown
                ensureVisibleInDropdown($prev, $customDropdown);
              } else if (index === 0) {
                // At first item, circle to the last non-disabled one
                if ($highlighted) $highlighted.classList.remove("highlighted");
                const $last = $options[$options.length - 1];
                if ($last) $last.classList.add("highlighted");
                ensureVisibleInDropdown($last, $customDropdown);
              }
              break;

            case "Enter":
            case " ": // Space key
              e.preventDefault();
              e.stopPropagation();
              if ($highlighted) {
                // Trigger click on the highlighted option
                $highlighted.click();
              }
              return false;
              break;

            case "Escape":
              e.preventDefault();
              e.stopPropagation();
              closeDropdown();
              return false;
              break;
          }
          return true;
        }
      });
      
      // Helper function to ensure the highlighted element is visible in the dropdown
      function ensureVisibleInDropdown($element, $container) {
        if (!$element || !$container) return;

        const containerHeight = $container.clientHeight;
        const containerScrollTop = $container.scrollTop;
        const elementTop = $element.offsetTop - $container.scrollTop;
        const elementHeight = $element.offsetHeight;

        // If element is above the visible area
        if (elementTop < 0) {
          $container.scrollTop = containerScrollTop + elementTop;
        }
        // If element is below the visible area
        else if (elementTop + elementHeight > containerHeight) {
          $container.scrollTop = containerScrollTop + elementTop + elementHeight - containerHeight;
        }
      }
      
      // Handle option selection
      document.addEventListener("click", function(e) { const _delegateTarget = e.target.closest(".custom-dropdown-option"); if (!_delegateTarget) return;
        // Check if this option is disabled
        if (_delegateTarget.classList.contains("disabled")) {
          return; // Don't do anything for disabled options
        }

        const value = _delegateTarget.dataset.value;

        // Update the real select value
        $select.value = value;
        $dispatch($select, "change");

        // Close dropdown using the proper method
        closeDropdown();
      });

      // Add mouse hover functionality to highlight options
      document.addEventListener("mouseover", function(e) { const _delegateTarget = e.target.closest(".custom-dropdown-option"); if (!_delegateTarget) return;
        // Don't highlight disabled options
        if (_delegateTarget.classList.contains("disabled")) {
          return;
        }
        document.querySelectorAll(".custom-dropdown-option.highlighted").forEach(function(_el) { _el.classList.remove("highlighted"); });
        _delegateTarget.classList.add("highlighted");
      });
      
      // Update dropdown position on window resize
      window.addEventListener("resize", function() {
        if (isDropdownOpen) {
          positionDropdown();
        }
        
        // Ensure group headers maintain the same height as the apps select
        const appsHeight = ($id("apps") || {}).offsetHeight;
        document.querySelectorAll(".custom-dropdown-group").forEach(function(_el) { _el.style.height = appsHeight + "px"; });
      });
      
      // Helper function to position the dropdown
      function positionDropdown() {
        // Get the select wrapper and its position
        const $selectWrapper = document.querySelector(".app-select-wrapper");
        if (!$selectWrapper) return;

        // Set dropdown position accurately based on the wrapper's position
        $customDropdown.style.top = $selectWrapper.offsetHeight + "px";
        $customDropdown.style.left = "0px";
        $customDropdown.style.width = $selectWrapper.offsetWidth + "px";
        $customDropdown.style.zIndex = 1100;
      }
      
      // Clean up event handlers when the page is unloaded
      window.addEventListener("beforeunload", function() {
        if (isDropdownOpen) {
          closeDropdown();
        }
        // Remove the global ESC key handler
        /* removed: document off "keydown.customDropdownEsc" */;
      });
    }
    
    // Function to set up enhanced styling for other select elements
    function setupEnhancedSelects() {
      // Apply to all form-select elements except #apps (which has its own custom dropdown)
      document.querySelectorAll(".form-select:not(#apps)").forEach(function(_el) {
        // Skip if select already has custom styling
        if (_el.dataset.enhanced === "true") {
          return;
        }

        // Mark as enhanced to avoid double processing
        _el.dataset.enhanced = "true";

        // Apply compact styling to all options
        _el.querySelectorAll("option").forEach(function(opt) { opt.classList.add("enhanced-option"); });

        // Apply special styling for optgroup labels if any
        _el.querySelectorAll("optgroup").forEach(function(og) { og.classList.add("enhanced-optgroup"); });

        // Apply special styling for disabled options (like separators)
        _el.querySelectorAll("option[disabled]").forEach(function(opt) { opt.classList.add("enhanced-separator"); });
      });
    }
    
    // Load AI User provider from cookie
    const savedProvider = getCookie("ai_user_provider");
    if (savedProvider) {
      { const el = $id("ai_user_provider"); if (el) el.value = savedProvider; }
      
      // Apply provider styling if updateProviderStyle is available
      if (typeof updateProviderStyle === 'function') {
        updateProviderStyle(savedProvider);
      }
    } else if (typeof updateProviderStyle === 'function') {
      updateProviderStyle("openai");
    }
    // Use UI utilities module if available, otherwise fallback
    if (uiUtils && uiUtils.adjustScrollButtons) {
      uiUtils.adjustScrollButtons();
    } else {
      adjustScrollButtonsFallback();
    }
    setCookieValues();
    // Use UI utilities module if available, otherwise fallback
    if (uiUtils && uiUtils.adjustImageUploadButton) {
      uiUtils.adjustImageUploadButton(($id("model") || {}).value);
    } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
      window.shims.uiUtils.adjustImageUploadButton(($id("model") || {}).value);
    }
    $show($id("monadic-spinner"));
    
    // Event handlers for the message deletion confirmation dialog
    $on($id("deleteMessageOnly"), "click", function() {
      const data = ($id("deleteConfirmation") || {}).dataset;
      if (data && data.mid) {
        // Check if it's a system message that needs special handling
        if (data.isSystemMessage) {
          deleteSystemMessage(data.mid, data.messageIndex !== undefined ? data.messageIndex : -1);
        } else {
          deleteMessageOnly(data.mid, data.messageIndex !== undefined ? data.messageIndex : -1);
        }
        bootstrap.Modal.getOrCreateInstance($id("deleteConfirmation")).hide();
      }
    });
    
    // Handle deletion of the current message and all subsequent messages
    $on($id("deleteMessageAndSubsequent"), "click", function() {
      const data = ($id("deleteConfirmation") || {}).dataset;
      if (data && data.mid) {
        // Check if it's a system message that needs special handling
        if (data.isSystemMessage) {
          deleteSystemMessage(data.mid, data.messageIndex !== undefined ? data.messageIndex : -1);
        } else {
          deleteMessageAndSubsequent(data.mid, data.messageIndex !== undefined ? data.messageIndex : -1);
        }
        bootstrap.Modal.getOrCreateInstance($id("deleteConfirmation")).hide();
      }
    });

    // Lightbox modal controls (state variables are in the outer scope near MutationObserver)
    $on($id("lightboxImage"), "click", function() {
      bootstrap.Modal.getOrCreateInstance($id("screenshotLightbox")).hide();
    });

    $on($id("lightboxPrev"), "click", function(e) {
      e.stopPropagation();
      if (lightboxIndex > 0) { lightboxIndex--; updateLightbox(); }
    });

    $on($id("lightboxNext"), "click", function(e) {
      e.stopPropagation();
      if (lightboxIndex < lightboxImages.length - 1) { lightboxIndex++; updateLightbox(); }
    });

    // Arrow key navigation for lightbox (Escape is handled by Bootstrap's keyboard: true default)
    document.addEventListener("keydown", function(e) {
      if (!($id("screenshotLightbox") && $id("screenshotLightbox").classList.contains("show"))) return;
      if (e.key === "ArrowLeft" && lightboxIndex > 0) { lightboxIndex--; updateLightbox(); }
      if (e.key === "ArrowRight" && lightboxIndex < lightboxImages.length - 1) { lightboxIndex++; updateLightbox(); }
    });
  })();
});
