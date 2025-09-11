// In browser environment, modules are imported via script tags
// These will be assigned when DOM is loaded
let uiUtils;
let formHandlers;

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

document.addEventListener("DOMContentLoaded", function () {
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
      $("#ai_user").attr("title", aiUserTitle);
      
      // Update role selector options with translations
      const roleOptions = $("#select-role option");
      if (roleOptions.length > 0) {
        $(roleOptions[0]).text(webUIi18n.t('ui.roleOptions.user') || 'User');
        $(roleOptions[1]).text(webUIi18n.t('ui.roleOptions.sampleUser') || 'User (to add to past messages)');
        $(roleOptions[2]).text(webUIi18n.t('ui.roleOptions.sampleAssistant') || 'Assistant (to add to past messages)');
        $(roleOptions[3]).text(webUIi18n.t('ui.roleOptions.sampleSystem') || 'System (to provide additional direction)');
      }
    });
  } else {
    $("#ai_user").attr("title", "Generate AI user response based on conversation");
  }
  // Ensure cancel button is hidden on page load using setTimeout for more reliability
  setTimeout(function() {
    document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
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
      console.log('UI utilities loaded dynamically');
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
      console.log('Form handlers loaded dynamically');
      if (typeof window.formHandlers !== 'undefined') {
        formHandlers = window.formHandlers;
      }
    };
    document.head.appendChild(script);
  }

  // Apply visibility for URL/Doc buttons based on backend capabilities
  try {
    $.getJSON('/api/capabilities')
      .done(function (cap) {
        if (!cap || cap.success === false) return;
        var seleniumEnabled = cap.selenium && cap.selenium.enabled === true;
        var tavily = cap.providers && cap.providers.tavily === true;

        if (!seleniumEnabled && !tavily) {
          $('#doc').hide();
          $('#url').hide();
        } else if (!seleniumEnabled && tavily) {
          $('#url').show();
          $('#doc').show();
        } else {
          $('#doc').show();
          $('#url').show();
        }
      });
  } catch (e) { /* ignore */ }
  
  // Directly get textareas and set them up - avoid storing array reference
  const initialHeight = 100;
  
  // Process each textarea individually to avoid keeping references
  const messageTextarea = document.getElementById('message');
  if (messageTextarea) {
    uiUtils.setupTextarea(messageTextarea, initialHeight);
  }
  
  const initialPromptTextarea = document.getElementById('initial-prompt');
  if (initialPromptTextarea) {
    uiUtils.setupTextarea(initialPromptTextarea, initialHeight);
  }
  
  const aiUserInitialPromptTextarea = document.getElementById('ai-user-initial-prompt');
  if (aiUserInitialPromptTextarea) {
    uiUtils.setupTextarea(aiUserInitialPromptTextarea, initialHeight);
  }

  document.addEventListener('hide.bs.modal', function (_event) {
    if (document.activeElement) {
      document.activeElement.blur();
    }
  });

  // if on Firefox, disable the #tts-panel
  if (runningOnFirefox) {
    $("#tts-panel").hide();
  }
});

// Fallback implementations are now in shims.js

$(function () {
  
  // Make alert draggable immediately when needed instead of storing reference
  $("#alert").draggable({ cursor: "move" });

  // Don't store persistent references to DOM elements
  // Access them only when needed

  // button#browser is disabled when the system has started
  $("#browser").prop("disabled", true);

  $("#send, #clear, #voice, #tts-voice, #ui-language, #ai-user-initial-prompt-toggle, #ai-user-toggle, #check-auto-speech, #check-easy-submit").prop("disabled", true);
  // Keep TTS speed control always enabled as it's used by multiple TTS providers
  $("#tts-speed").prop("disabled", false);

  //////////////////////////////
  // UI event handlers
  //////////////////////////////

  // Use "Chat" as the default app if not defined elsewhere
  let lastApp = typeof defaultApp !== 'undefined' ? defaultApp : "Chat";

  // Common UI operations - centralized for consistency
  const UIOperations = {
    showMain: function() {
      $("#main").show();
      return this;
    },
    hideMain: function() {
      $("#main").hide();
      return this;
    },
    showMenu: function() {
      $("#menu").show();
      return this;
    },
    hideMenu: function() {
      $("#menu").hide();
      return this;
    },
    showBoth: function() {
      this.showMain().showMenu();
      return this;
    },
    setMainColumns: function(removeClass, addClass) {
      $("#main").removeClass(removeClass).addClass(addClass);
      return this;
    }
  };
  
  // Make available globally for reuse
  window.UIOperations = UIOperations;

  // Consolidate event handlers for toggles
  function setupToggleHandlers() {
    $("#auto-scroll-toggle").on("change", function () {
      autoScroll = $(this).is(":checked");
    });

    $("#max-tokens-toggle").on("change", function () {
      $("#max-tokens").prop("disabled", !$(this).is(":checked"));
    });

    $("#context-size-toggle").on("change", function () {
      $("#context-size").prop("disabled", !$(this).is(":checked"));
    });
    
    // Add handler for AI User toggle to ensure the value gets set in params
    $("#ai-user-toggle").on("change", function () {
      // Update the params directly when the checkbox changes
      params["ai_user"] = $(this).is(":checked") ? "true" : "false";
    });
  }

  // Setup optimized event listeners
  function setupEventListeners() {
    // Make AI User button always visible
    setTimeout(function() {
      $("#ai_user").show();
    }, 1000);
    
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
    $("#ai_user_provider").on("change", function() {
      const provider = $(this).val();
      setCookie("ai_user_provider", provider, 30);
      updateProviderStyle(provider);
      // Update badge with model and reasoning effort when available
      if (!setAiUserBadge()) {
        const providerName = $("#ai_user_provider option:selected").text();
        const fallbackModel = getDefaultModelFromSSOT(provider) || $("#model").val() || getTranslation('ui.notConfigured','Not configured');
        $("#ai-user-model").text(`${providerName} (${fallbackModel})`);
      }
    });
    
    // Function that does nothing now - we're keeping the default btn-warning style
    function updateProviderStyle(provider) {
      // Intentionally left empty - we want to maintain the original btn-warning style
    }
    
    // Removed hardcoded getDefaultModelForProvider; use SSOT via /api/ai_user_defaults instead
    
    
    // Function to update available providers in dropdown based on API keys
    // Export to window scope for access from websocket.js
    window.updateAvailableProviders = function() {
      // Hide all options first
      $("#ai_user_provider option").hide();
      
      // Loop through providers to check which ones have API keys available
      // Show by apps groups first (backward compatibility)
      
      // Check for other providers' API keys
      for (const [key, app] of Object.entries(apps)) {
        if (!app.group) continue;
        
        const group = app.group.toLowerCase();
        
        // Match provider dropdown options to available app groups
        if (group.includes("anthropic")) {
          $("#ai_user_provider option[value='anthropic']").show();
        } else if (group.includes("gemini") || group.includes("google")) {
          $("#ai_user_provider option[value='gemini']").show();
        } else if (group.includes("cohere")) {
          $("#ai_user_provider option[value='cohere']").show();
        } else if (group.includes("mistral") || group.includes("pixtral") || group.includes("ministral") || group.includes("magistral") || group.includes("devstral") || group.includes("voxtral") || group.includes("mixtral")) {
          // Mistral now supports AI User
          $("#ai_user_provider option[value='mistral']").show();
        } else if (group.includes("deepseek")) {
          $("#ai_user_provider option[value='deepseek']").show();
        } else if (group.includes("grok") || group.includes("xai")) {
          $("#ai_user_provider option[value='grok']").show();
        } else if (group.includes("perplexity")) {
          $("#ai_user_provider option[value='perplexity']").show();
        }
      }

      // Additionally filter by SSOT has_key if available
      if (aiUserDefaults) {
        const map = {
          'openai':'openai','anthropic':'anthropic','gemini':'gemini','cohere':'cohere','mistral':'mistral','deepseek':'deepseek','grok':'grok','perplexity':'perplexity'
        };
        Object.keys(map).forEach(val => {
          const ent = aiUserDefaults[val];
          if (ent && ent.has_key) {
            $("#ai_user_provider option[value='"+val+"']").show();
          } else {
            $("#ai_user_provider option[value='"+val+"']").hide();
          }
        });
      }
      
      // If the currently selected provider is not available, select first available
      const currentProvider = $("#ai_user_provider").val();
      if ($("#ai_user_provider option[value='" + currentProvider + "']:visible").length === 0) {
        // Select first visible option
        const firstVisible = $("#ai_user_provider option:visible").first().val();
        if (firstVisible) {
          $("#ai_user_provider").val(firstVisible);
          setCookie("ai_user_provider", firstVisible, 30);
        }
      }
    }
    
    // Helper to compute and set the AI User badge text robustly
    function setAiUserBadge() {
      const provider = $("#ai_user_provider").val();
      if (!provider) return false;
      const providerName = $("#ai_user_provider option:selected").text();
      const ssotModel = getDefaultModelFromSSOT(provider);
      const currentModel = $("#model").val();
      const model = ssotModel || currentModel;
      if (model && providerName) {
        // Compute reasoning effort default for this provider/model when supported
        let effortSuffix = '';
        try {
          if (window.ReasoningMapper) {
            // Map provider value to display name expected by ReasoningMapper
            const map = { openai:'OpenAI', anthropic:'Anthropic', gemini:'Google', cohere:'Cohere', mistral:'Mistral', deepseek:'DeepSeek', grok:'xAI', perplexity:'Perplexity' };
            const provDisplay = map[provider] || providerName;
            if (ReasoningMapper.isSupported(provDisplay, model)) {
              const opts = ReasoningMapper.getAvailableOptions(provDisplay, model) || [];
              let defv = ReasoningMapper.getDefaultValue(provDisplay, model);
              if (!defv || (opts.length && !opts.includes(defv))) {
                defv = opts[0] || null;
              }
              if (defv) effortSuffix = ' - ' + defv;
            }
          }
        } catch(_) {}
        $("#ai-user-model").text(providerName + ' (' + model + effortSuffix + ')');
        return true;
      }
      return false;
    }

    // Load SSOT defaults then initialize provider and badge (no async IIFE for compatibility)
    fetchAiUserDefaults().then(function(defs){
      aiUserDefaults = defs || null;
      window.updateAvailableProviders();
      const savedProvider = getCookie('ai_user_provider');
      var chosen = savedProvider;
      if (!chosen || $("#ai_user_provider option[value='"+chosen+"']:visible").length === 0) {
        var firstVisible = $("#ai_user_provider option:visible").first().val();
        if (firstVisible) {
          chosen = firstVisible;
          $("#ai_user_provider").val(firstVisible);
          setCookie('ai_user_provider', firstVisible, 30);
        }
      } else {
        $("#ai_user_provider").val(chosen);
      }
      if (chosen) {
        if (!setAiUserBadge()) {
          $("#ai-user-model").text(getTranslation('ui.notConfigured','Not configured'));
        }
      } else {
        $("#ai-user-model").text(getTranslation('ui.notConfigured','Not configured'));
      }
    }).catch(function(){
      // fallback: just update available providers based on apps
      window.updateAvailableProviders();
      // Best-effort label update using current app model
      var chosen = $("#ai_user_provider option:visible").first().val();
      if (chosen) {
        $("#ai_user_provider").val(chosen);
        if (!setAiUserBadge()) {
          $("#ai-user-model").text(getTranslation('ui.notConfigured','Not configured'));
        }
      }
    });

    // Robust initialization: observe #model for population and update badge when ready
    (function ensureBadgeOnModelReady(){
      try {
        const modelSel = document.getElementById('model');
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
            try { observer.disconnect(); } catch(_) {}
          }
        }, 300);
      } catch (e) {
        // Last resort timed attempt without observer
        setTimeout(setAiUserBadge, 1200);
      }
    })();
    
    // Set up model change handler to update the AI Assistant info badge
    $("#model").on("change", function() {
      const selectedModel = $(this).val();
      // Extract provider from params.group first (synced in proceedWithAppChange), fallback to current app group
      let provider = "OpenAI";
      const currentApp = $("#apps").val();
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
      $("#ai-assistant-info").html('<span style="color: #DC4C64;" data-i18n="ui.aiAssistant">' + aiAssistantText + '</span> &nbsp;<span class="ai-assistant-provider" style="display: inline-block; padding: 0.25rem 0.5rem; border: 1px solid #dee2e6; border-radius: 0.375rem; background-color: #f8f9fa; font-weight: normal; min-width: 120px; text-align: left; font-size: 0.875rem; line-height: 1.5; height: calc(1.5em + 0.5rem + 2px); vertical-align: middle;">' + provider + '</span>').attr("data-model", selectedModel);

      // Update model-selected text to follow the new multiline format
      if (modelSpec[selectedModel] && modelSpec[selectedModel].hasOwnProperty("reasoning_effort")) {
        const reasoningEffort = $("#reasoning-effort").val();
        $("#model-selected").text(`${provider} (${selectedModel} - ${reasoningEffort})`);
      } else {
        $("#model-selected").text(`${provider} (${selectedModel})`);
      }
    });
    
    // Initial availability update will be done when models are loaded
    
    // Setup AI User button
    $("#ai_user").off("click").on("click", function () {
      // Force enable AI User
      params["ai_user"] = "true";
      
      // Get the provider from the selector
      const provider = $("#ai_user_provider").val();
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
      $(this).show();
      
      // Disable the button temporarily to prevent double-clicking
      $(this).prop("disabled", true);
      
      // Provide better user feedback
      const providerName = $("#ai_user_provider option:selected").text();
      const analyzingText = getTranslation('ui.messages.analyzingConversation', 'Analyzing conversation');
      const alertMessage = `<i class='fas fa-spinner fa-spin'></i> ${analyzingText}`;
      setAlert(alertMessage, "warning");
      
      // Disable UI elements manually here to ensure they're disabled even if websocket events fail
      $("#message").prop("disabled", true);
      $("#send").prop("disabled", true);
      $("#clear").prop("disabled", true);
      $("#image-file").prop("disabled", true);
      $("#voice").prop("disabled", true);
      $("#doc").prop("disabled", true);
      $("#url").prop("disabled", true);
      $("#select-role").prop("disabled", true);
      document.getElementById('cancel_query').style.setProperty('display', 'flex', 'important');
      
      // Show the spinner with robot icon animation
      $("#monadic-spinner").css("display", "block");
      const aiUserText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ? 
        webUIi18n.t('ui.messages.spinnerGeneratingAIUser') : 'Generating AI user response';
      $("#monadic-spinner span").html(`<i class="fas fa-robot fa-pulse"></i> ${aiUserText}`);
      
      // Show a tooltip explaining the process
      $("#status-message").attr("title", "AI User is analyzing the entire conversation to generate a natural user response");
      
      // Enable button after a delay to prevent rapid clicking
      setTimeout(() => {
        $("#ai_user").prop("disabled", false);
      }, 3000);
    });
  
    const $document = $(document);
    const $main = $("#main");

    // Event delegation for dynamically added elements
    $document.on("click", ".contBtn", function () {
      $("#message").val("Continue");
      $("#send").trigger("click");
    });

    // Add MutationObserver for handling image errors
    // Store the observer in the window object to ensure it can be accessed globally for cleanup
    window.imageErrorObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.addedNodes.length) {
          mutation.addedNodes.forEach((node) => {
            if (node.nodeType === 1 && node.classList.contains('card')) {
              $(node).find(".generated_image img").each(function() {
                const $img = $(this);

                // Use one-time event handler to avoid memory leak from multiple handlers
                $img.one("error", function() {
                  const $errorMessage = $("<div>", {
                    class: "image-error-message",
                    text: "NO IMAGE GENERATED"
                  }).css({
                    'color': '#dc3545',
                  });
                  $img.replaceWith($errorMessage);
                });
              });
            }
          });
        }
      });
    });

    // Start observing the discourse element
    const discourseElement = document.getElementById('discourse');
    if (discourseElement) {
      window.imageErrorObserver.observe(discourseElement, {
        childList: true,
        subtree: true
      });
    }
    
    // Clean up the observer when the page is unloaded
    $(window).on("beforeunload", function() {
      if (window.imageErrorObserver) {
        window.imageErrorObserver.disconnect();
      }
    });

    $document.on("click", ".yesBtn", function () {
      $("#message").val("Yes");
      $("#send").trigger("click");
    });

    $document.on("click", ".noBtn", function () {
      $("#message").val("No");
      $("#send").trigger("click");
    });

    $document.on("click", ".card-text img", function () {
      window.open().document.write(this.outerHTML);
    });
    // Improved scroll event - store timer in data attribute to prevent leaks
    $main.on("scroll", function () {
      const $this = $(this);
      // Clear any existing timer stored in the element's data
      const existingTimer = $this.data('scrollTimer');
      if (existingTimer) {
        clearTimeout(existingTimer);
      }
      // Store new timer reference in the element's data
      $this.data('scrollTimer', setTimeout(function() {
        // Use the UI utilities module if available, otherwise fall back
        if (uiUtils && uiUtils.adjustScrollButtons) {
          uiUtils.adjustScrollButtons();
        } else {
          adjustScrollButtonsFallback();
        }
      }, 100));
    });

    // Track previous window width to detect significant changes
    let previousWidth = $(window).width();
    
    // Improved resize event with immediate and delayed response
    $(window).on("resize", function () {
      const $window = $(window);
      const currentWidth = $window.width();
      const existingTimer = $window.data('resizeTimer');
      
      // Check if we crossed the mobile/desktop boundary (600px)
      const wasMobile = previousWidth < 600;
      const isMobile = currentWidth < 600;
      const crossedBoundary = wasMobile !== isMobile;
      
      // Immediate fix if we crossed the mobile/desktop boundary
      if (crossedBoundary) {
        fixLayoutAfterResize();
      }
      
      // Clear existing timer
      if (existingTimer) {
        clearTimeout(existingTimer);
      }
      
      // Set new timer for final adjustments
      $window.data('resizeTimer', setTimeout(function() {
        // Final layout fix
        fixLayoutAfterResize();
        
        // Force nav reflow to apply correct styles
        const $nav = $('#main-nav');
        $nav.hide();
        $nav[0].offsetHeight; // force reflow
        $nav.show();
        
        // Update previous width
        previousWidth = currentWidth;
      }, 250));
    });
    
    // Clean up timers when window is unloaded
    $(window).on("beforeunload", function() {
      // Clean up any stored timers
      const $main = $("#main");
      const $window = $(window);
      
      const mainScrollTimer = $main.data('scrollTimer');
      if (mainScrollTimer) {
        clearTimeout(mainScrollTimer);
        $main.removeData('scrollTimer');
      }
      
      const windowResizeTimer = $window.data('resizeTimer');
      if (windowResizeTimer) {
        clearTimeout(windowResizeTimer);
        $window.removeData('resizeTimer');
      }
    });
  }

  // Function to fix layout after window resize
  function fixLayoutAfterResize() {
    try {
      const windowWidth = $(window).width();
      const isMobile = window.UIConfig ? window.UIConfig.isMobileView() : windowWidth < 600;
      const toggleBtn = $("#toggle-menu");
      const mainPanel = $("#main");
      const menuPanel = $("#menu");
      
      // Check if essential elements exist
      if (!toggleBtn.length || !mainPanel.length || !menuPanel.length) {
        console.warn("fixLayoutAfterResize: Required elements not found");
        return;
      }
    
    if (isMobile) {
      // Mobile layout
      const isMenuHidden = toggleBtn.hasClass("menu-hidden");
      
      if (isMenuHidden) {
        // Menu should be hidden, main should be visible
        menuPanel.hide();
        mainPanel.show().removeClass("col-md-8").addClass("col-md-12");
        $("body").removeClass("menu-visible");
        toggleBtn.html('<i class="fas fa-bars"></i>');
      } else {
        // Menu should be visible, main should be hidden
        menuPanel.show();
        mainPanel.hide();
        $("body").addClass("menu-visible");
        toggleBtn.html('<i class="fas fa-times"></i>');
      }
      
      // Reset any inline styles that might have been applied
      toggleBtn.css({
        "position": "",
        "top": "",
        "right": "",
        "display": ""
      });
    } else {
      // Desktop layout
      $("body").removeClass("menu-visible");
      
      if (menuPanel.is(":visible")) {
        // Both panels visible
        mainPanel.removeClass("col-md-12").addClass("col-md-8").show();
        menuPanel.show();
        toggleBtn.removeClass("menu-hidden").html('<i class="fas fa-times"></i>');
      } else {
        // Only main panel visible
        mainPanel.removeClass("col-md-8").addClass("col-md-12").show();
        menuPanel.hide();
        toggleBtn.addClass("menu-hidden").html('<i class="fas fa-bars"></i>');
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
      $("#main").show();
      $("#toggle-menu").show();
    }
  }

  // Fallback function for scroll buttons when uiUtils is not available
  function adjustScrollButtonsFallback() {
    const mainPanel = $("#main");
    const windowWidth = $(window).width();
    const isMobile = windowWidth < 600;
    const isMedium = windowWidth < 768; // Bootstrap md breakpoint
    
    // On mobile and medium screens where menu/content are exclusive, check toggle state
    if (isMobile || isMedium) {
      // Check if toggle button has menu-hidden class
      // When menu-hidden class is present, menu is hidden and main is showing
      // When menu-hidden class is absent, menu is showing and main is hidden
      const toggleBtn = $("#toggle-menu");
      const isMenuHidden = toggleBtn.hasClass("menu-hidden");
      
      if (!isMenuHidden) {
        // Menu is showing (toggle button doesn't have menu-hidden class), hide scroll buttons
        $("#back_to_top").hide();
        $("#back_to_bottom").hide();
        return;
      }
    }
    
    // Also check for menu-visible class (mobile menu state)
    if ($("body").hasClass("menu-visible")) {
      $("#back_to_top").hide();
      $("#back_to_bottom").hide();
      return;
    }
    
    const mainHeight = mainPanel.height() || 0;
    const mainScrollHeight = mainPanel.prop("scrollHeight") || 0;
    const mainScrollTop = mainPanel.scrollTop() || 0;
    
    // Position buttons relative to main panel
    const mainOffset = mainPanel.offset();
    const mainWidth = mainPanel.width();
    if (mainOffset) {
      const buttonRight = $(window).width() - (mainOffset.left + mainWidth) + 30;
      $("#back_to_top").css("right", buttonRight + "px");
      $("#back_to_bottom").css("right", buttonRight + "px");
    }
    
    // Calculate thresholds (100px minimum scroll to show buttons)
    const scrollThreshold = 100;
    
    // Show top button when scrolled down enough from the top
    if (mainScrollTop > scrollThreshold) {
      $("#back_to_top").fadeIn(window.UIConfig ? window.UIConfig.TIMING.TOGGLE_ANIMATION : 200);
    } else {
      $("#back_to_top").fadeOut(window.UIConfig ? window.UIConfig.TIMING.TOGGLE_ANIMATION : 200);
    }
    
    // Show bottom button when not near the bottom
    const distanceFromBottom = mainScrollHeight - mainScrollTop - mainHeight;
    if (distanceFromBottom > scrollThreshold) {
      $("#back_to_bottom").fadeIn(window.UIConfig ? window.UIConfig.TIMING.TOGGLE_ANIMATION : 200);
    } else {
      $("#back_to_bottom").fadeOut(window.UIConfig ? window.UIConfig.TIMING.TOGGLE_ANIMATION : 200);
    }
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
      
      const mainPanel = document.getElementById('main');
      const menuPanel = document.getElementById('menu');
      
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
      $(window).off("beforeunload.resizeObserver").on("beforeunload.resizeObserver", function() {
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
      
      // Remove window event listeners
      $(window).off('.resizeHandler');
      $(window).off('.resizeObserver');
      $(window).off('.scrollHandler');
      
      // Clean up tooltips
      if (window.uiUtils && window.uiUtils.cleanupAllTooltips) {
        window.uiUtils.cleanupAllTooltips();
      }
      
      // Clear UIState listeners if available
      if (window.UIState && window.UIState.reset) {
        // Don't reset state, just clear listeners
        // window.UIState.reset();
      }
      
      console.log('Event handlers cleaned up successfully');
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
  $(window).on('beforeunload', cleanupEventHandlers);
  
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
  
  // Call these functions on document ready
  $(function () {
    setupToggleHandlers();
    setupEventListeners();
    setupResizeObserver();
  });

  $("#model").on("change", function() {
    const selectedModel = $("#model").val();
    const defaultModel = apps[$("#apps").val()]["model"];
    if (selectedModel !== defaultModel) {
      $("#model-non-default").show();
    } else {
      $("#model-non-default").hide();
    }

    // Handle reasoning effort dropdown with ReasoningMapper
    const currentApp = $("#apps").val();
    const provider = getProviderFromGroup(apps[currentApp]["group"]);
    
    // Update UI with provider-specific components and labels
    if (window.reasoningUIManager) {
      window.reasoningUIManager.updateUI(provider, selectedModel);
    }
    
    if (window.ReasoningMapper && ReasoningMapper.isSupported(provider, selectedModel)) {
      const availableOptions = ReasoningMapper.getAvailableOptions(provider, selectedModel);
      const defaultValue = ReasoningMapper.getDefaultValue(provider, selectedModel);
      
      if (availableOptions && availableOptions.length > 0) {
        $("#reasoning-effort").prop("disabled", false);
        
        // Store current value before clearing options
        const previousValue = $("#reasoning-effort").val();
        
        // Clear current options
        $("#reasoning-effort").empty();
        
        // Add options from ReasoningMapper with provider-specific labels
        availableOptions.forEach(option => {
          const label = window.ReasoningLabels ? 
            window.ReasoningLabels.getOptionLabel(provider, option) : 
            option;
          $("#reasoning-effort").append($('<option>', {
            value: option,
            text: label
          }));
        });
        
        // Don't override reasoning_effort if we're loading from params
        if (!window.isLoadingParams) {
          // Set the value - preserve existing value if present, otherwise use default
          if (previousValue && availableOptions.includes(previousValue)) {
            // Keep the previous value if it's valid for this model
            $("#reasoning-effort").val(previousValue);
          } else {
            // Use the default value from ReasoningMapper
            $("#reasoning-effort").val(defaultValue || availableOptions[0]);
          }
        }
        
        console.log(`Updated reasoning options for ${provider}/${selectedModel}: [${availableOptions.join(', ')}]`);
      } else {
        $("#reasoning-effort").prop("disabled", true);
      }
    } else {
      $("#reasoning-effort").prop("disabled", true);
      console.log(`Provider ${provider} with model ${selectedModel} does not support reasoning/thinking`);
    }
    
    // Always restore default options when disabled (for consistency)
    if ($("#reasoning-effort").prop("disabled")) {
      $("#reasoning-effort").empty();
      const defaultOptions = ['minimal', 'low', 'medium', 'high'];
      defaultOptions.forEach(option => {
        const label = window.ReasoningLabels ? 
          window.ReasoningLabels.getOptionLabel('default', option) : 
          option;
        $("#reasoning-effort").append($('<option>', { 
          value: option, 
          text: label 
        }));
      });
      $("#reasoning-effort").val('medium');
    }

    // Update labels and description after options are generated
    if (window.ReasoningLabels) {
      window.ReasoningLabels.updateUILabels(provider, selectedModel);
      
      // Update description text
      const description = window.ReasoningLabels.getDescription(provider, selectedModel);
      const descElement = document.getElementById('reasoning-description');
      if (descElement) {
        if (description && !$("#reasoning-effort").prop("disabled")) {
          descElement.textContent = description;
          descElement.style.display = 'inline';
        } else {
          descElement.style.display = 'none';
        }
      }
    }

    if (modelSpec[selectedModel]) {
      const supportsWeb = (modelSpec[selectedModel]["supports_web_search"] === true) ||
                          (modelSpec[selectedModel]["tool_capability"] === true); // fallback for tool-based providers
      if (supportsWeb) {
        $("#websearch").prop("disabled", false).removeAttr('title');
      } else {
        $("#websearch-badge").hide();
        const tt = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.webSearchModelDisabled') : 'Model does not support Web Search';
        $("#websearch").prop("disabled", true).attr('title', tt);
      }

      if (modelSpec[selectedModel].hasOwnProperty("temperature")) {
        $("#temperature").prop("disabled", false);
        // temperature is kept unchanged even if the model is changed
        ;
        // const temperature = modelSpec[selectedModel]["temperature"][1];
        // $("#temperature").val(temperature);
        // $("#temperature-value").text(parseFloat(temperature).toFixed(1));
      } else {
        $("#temperature").prop("disabled", true);
      }

      if (modelSpec[selectedModel].hasOwnProperty("presence_penalty")) {
        $("#presence-penalty").prop("disabled", false);
        // presence penalty is kept unchanged even if the model is changed
        ;
        // const presencePenalty = modelSpec[selectedModel]["presence_penalty"][1];
        // $("#presence-penalty").val(presencePenalty);
        // $("#presence-penalty-value").text(parseFloat(presencePenalty).toFixed(1));
      } else {
        $("#presence-penalty").prop("disabled", true);
      }

      if (modelSpec[selectedModel].hasOwnProperty("frequency_penalty")) {
        $("#frequency-penalty").prop("disabled", false);
        // frequency penalty is kept unchanged even if the model is changed
        ;
        // const frequencyPenalty = modelSpec[selectedModel]["frequency_penalty"][1];
        // $("#frequency-penalty").val(frequencyPenalty);
        // $("#frequency-penalty-value").text(parseFloat(frequencyPenalty).toFixed(1));
      } else {
        $("#frequency-penalty").prop("disabled", true);
      }

      if (modelSpec[selectedModel].hasOwnProperty("max_output_tokens")) {
        $("#max-tokens-toggle").prop("checked", true).trigger("change");
        const maxOutputTokens = modelSpec[selectedModel]["max_output_tokens"][1];
        $("#max-tokens").val(maxOutputTokens);
      } else {
        $("#max-tokens").val(DEFAULT_MAX_OUTPUT_TOKENS)
        $("#max-tokens-toggle").prop("checked", false).trigger("change");
      }
    } else {
      $("#reasoning-effort").prop("disabled", true);
      $("#temperature").prop("disabled", true);
      $("#presence-penalty").prop("disabled", true);
      $("#frequency-penalty").prop("disabled", true);
      $("#max-tokens-toggle").prop("checked", false).trigger("change");
      $("#max-tokens").val(DEFAULT_MAX_OUTPUT_TOKENS)
    }

    // check if selected mode has data-model-type attribute and its value is "reasoning"
    // Use existing currentApp and provider variables from above
    
    if (modelSpec[selectedModel] && modelSpec[selectedModel].hasOwnProperty("reasoning_effort")) {
      const reasoningEffort = $("#reasoning-effort").val();
      $("#max-tokens").prop("disabled", true);
      $("#max-tokens-toggle").prop("checked", false).prop("disabled", true);
      $("#model-selected").text(`${provider} (${selectedModel} - ${reasoningEffort})`);
    } else {
      $("#max-tokens").prop("disabled", false)
      $("#max-tokens-toggle").prop("disabled", false).prop("checked", true)
      $("#model-selected").text(`${provider} (${selectedModel})`);
    }
    // Use UI utilities module if available, otherwise fallback
    if (uiUtils && uiUtils.adjustImageUploadButton) {
      uiUtils.adjustImageUploadButton(selectedModel);
    } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
      window.shims.uiUtils.adjustImageUploadButton(selectedModel);
    }
  });

  $("#reasoning-effort").on("change", function () {
    const selectedModel = $("#model").val();
    // Get current app's provider
    const currentApp = $("#apps").val();
    const provider = getProviderFromGroup(apps[currentApp]["group"]);
    
    if (modelSpec[selectedModel] && modelSpec[selectedModel].hasOwnProperty("reasoning_effort")) {
      const reasoningEffort = $("#reasoning-effort").val();
      $("#model-selected").text(`${provider} (${selectedModel} - ${reasoningEffort})`);
    }
  });


  $("#apps").on("change", function (event) {
    if (stop_apps_trigger) {
      stop_apps_trigger = false;
      return;
    }

    // Store selected app
    const selectedAppValue = $(this).val();
    const previousAppValue = lastApp;
    
    // Update app icon immediately on selection change
    updateAppSelectIcon(selectedAppValue);
    
    // With customizable select, the selected item styling is handled natively by the browser
    
    // If there are messages and app is changing, show confirmation dialog
    if (messages.length > 0 && selectedAppValue !== previousAppValue) {
      // Prevent the dropdown from changing yet
      event.preventDefault();
      // Set dropdown back to previous value temporarily
      $(this).val(previousAppValue);
      // Restore previous icon
      updateAppSelectIcon(previousAppValue);
      
      // Show confirmation dialog
      $("#appChangeConfirmation").data("newApp", selectedAppValue).modal("show");
      return;
    }

    // No messages or same app, proceed with change
    proceedWithAppChange(selectedAppValue);
  });
  
  // Handle confirmation of app change
  $("#appChangeConfirmed").on("click", function() {
    const newAppValue = $("#appChangeConfirmation").data("newApp");
    // Close the modal
    $("#appChangeConfirmation").modal("hide");
    // Apply the app change
    $("#apps").val(newAppValue);
    // Reset messages via SessionState API (no direct assignment)
    if (window.SessionState && typeof window.SessionState.clearMessages === 'function') {
      window.SessionState.clearMessages();
    } else {
      try { window.messages = []; } catch (_) {}
    }
    // Clear the discourse area
    $("#discourse").html("");
    // Reset to settings panel instead of continuing session
    $("#config").show();
    $("#back-to-settings").hide();
    $("#main-panel").hide();
    $("#parameter-panel").hide();
    // Wait for i18n to be ready before updating button text
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        const startText = webUIi18n.t('ui.session.startSession');
        $("#start-label").text(startText);
      });
    } else {
      // Fallback if i18nReady is not available
      const startText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
        webUIi18n.t('ui.session.startSession') : 'Start Session';
      $("#start-label").text(startText);
    }
    proceedWithAppChange(newAppValue);
  });
  
  // Function to handle the actual app change
  // Make it globally accessible for initialization from websocket.js
  window.proceedWithAppChange = function proceedWithAppChange(appValue) {
    try {
      if (window.logTL) {
        const hasApp = !!(apps && apps[appValue]);
        const sys = hasApp ? !!apps[appValue]["system_prompt"] : null;
        window.logTL('proceedWithAppChange_enter', { appValue, hasApp, hasSystemPrompt: sys });
      }
    } catch (_) {}
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
    
    // Always enable AI User toggle for all providers
    $("#ai-user-toggle").prop("disabled", false);
    
    // Always enable AI User button (error message will be shown if conversation not started)
    $("#ai_user").prop("disabled", false);
    // Set title with translation when available
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        const aiUserTitle = webUIi18n.t('ui.generateAIUserResponse') || "Generate AI user response based on conversation";
        $("#ai_user").attr("title", aiUserTitle);
      });
    } else {
      $("#ai_user").attr("title", "Generate AI user response based on conversation");
    }

    if (messages.length > 0) {
      if (appValue === lastApp) {
        return;
      }
    }
    lastApp = appValue;
    // Check if the app exists
    if (!apps[appValue]) {
      console.warn(`App '${appValue}' not found in apps object`);
      return;
    }
    // Preserve important values before Object.assign overwrites them
    const currentMathjax = $("#mathjax").prop('checked');
    // Preserve previous values only during import flows
    const preservedModel = (typeof window !== 'undefined' && window.isImporting) ? params["model"] : null;  // Preserve the model that was set by loadParams
    const preservedAppName = (typeof window !== 'undefined' && window.isImporting) ? params["app_name"] : null; // Preserve the app_name
    // Do not carry over previous group's provider across app changes.
    // If importing, we handle app selection earlier based on provider.
    const preservedGroup = null;
    
    Object.assign(params, apps[appValue]);
    
    // Fill initial_prompt from system_prompt if not present (common for Chat apps)
    if (!params["initial_prompt"] && apps[appValue]["system_prompt"]) {
      params["initial_prompt"] = apps[appValue]["system_prompt"];
    }

    // Restore the preserved values if they were set (during import)
    if (preservedModel && (typeof window !== 'undefined' && window.isImporting)) {
      params["model"] = preservedModel;
    }
    if (preservedAppName && (typeof window !== 'undefined' && window.isImporting)) {
      params["app_name"] = preservedAppName;
    }
    // Always align params.group to the selected app's group to avoid stale provider labels
    params["group"] = apps[appValue]["group"];
    
    // Only set initiate_from_assistant to false if the app explicitly defines it as false
    // Don't override if it's already been set by setParams()
    if (apps[appValue] && apps[appValue].hasOwnProperty('initiate_from_assistant') && apps[appValue]['initiate_from_assistant'] === false) {
      params['initiate_from_assistant'] = false;
    }
    // Restore mathjax state if not explicitly set in app parameters
    if (apps[appValue] && !apps[appValue].hasOwnProperty('mathjax')) {
      params['mathjax'] = currentMathjax;
    }
    
    // Ensure loadParams runs even if another async selection is in progress
    // If a prior flow (e.g., provider auto-select) set isLoadingParams, defer and retry briefly
    (function ensureLoadParams(retries = 0) {
      if (!window.isLoadingParams) {
        loadParams(params, "changeApp");
        if (window.logTL) window.logTL('loadParams_called_from_proceed', { app: appValue, calledFor: 'changeApp' });
        return;
      }
      if (retries >= 10) {
        // As a last resort, proceed anyway to avoid missing initial prompt
        loadParams(params, "changeApp");
        if (window.logTL) window.logTL('loadParams_called_from_proceed_force', { app: appValue, calledFor: 'changeApp' });
        return;
      }
      setTimeout(() => ensureLoadParams(retries + 1), 100);
    })();
    
    // Update app icon in the select dropdown
    updateAppSelectIcon(appValue);

    if (apps[appValue]["pdf"] || apps[appValue]["pdf_vector_storage"]) {
      $("#file-import-row").show();
      $("#pdf-panel").show();
      ws.send(JSON.stringify({ message: "PDF_TITLES" }));
    } else {
      $("#file-import-row").hide();
      $("#pdf-panel").hide();
    }

    if (apps[appValue]["image"]) {
      $("#image-file").show();
    } else {
      $("#image-file").hide();
    }

    let model;
    // Never mutate apps[appValue].group here; app definitions are authoritative.
    
    // Use shared utility function to get models for the app
    let models = getModelsForApp(apps[appValue]);

    if (models.length > 0) {
      let openai = apps[appValue]["group"].toLowerCase() === "openai";
      let modelList = listModels(models, openai);
      $("#model").html(modelList);
      
      // Use shared utility function to get default model
      model = getDefaultModelForApp(apps[appValue], models);
      
      // Override with params if available
      if (params["model"] && models.includes(params["model"])) {
        model = params["model"];
      }

      // Get provider from app group
      const provider = getProviderFromGroup(apps[appValue]["group"]);
      
      if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
        $("#model-selected").text(`${provider} (${model} - ${$("#reasoning-effort").val()})`);
      } else {
        $("#model-selected").text(`${provider} (${model})`);
      }

      if (modelSpec[model] && ((modelSpec[model]["supports_web_search"] === true) || (modelSpec[model]["tool_capability"] === true))) {
        $("#websearch").prop("disabled", false).removeAttr('title');
      } else {
        $("#websearch-badge").hide();
        const tt2 = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.webSearchModelDisabled') : 'Model does not support Web Search';
        $("#websearch").prop("disabled", true).attr('title', tt2);
      }

      $("#model").val(model);
      
      if ($("#model").val() !== model) {
        // Try again after a delay
        setTimeout(() => {
          $("#model").val(model);
          if ($("#model").val() === model) {
            $("#model").trigger("change");
          }
        }, 100);
      } else {
        $("#model").trigger("change");
      }
      // Use UI utilities module if available, otherwise fallback
      if (uiUtils && uiUtils.adjustImageUploadButton) {
        uiUtils.adjustImageUploadButton(model);
      } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
        window.shims.uiUtils.adjustImageUploadButton(model);
      }

    } else if (!apps[appValue]["model"] || apps[appValue]["model"].length === 0) {
      $("#model_and_file").hide();
      $("#model_parameters").hide();
    } else {
      // The following code is for backward compatibility

      let models_text = apps[appValue]["models"];
      let models = JSON.parse(models_text);
      model = params["model"];

      if (params["model"] && models && models.includes(params["model"])) {
        $("#model").html(model_options);
        $("#model").val(params["model"]).trigger("change");
      } else {
        let model_options = `<option disabled="disabled" selected="selected">Models not available</option>`;
        $("#model").html(model_options);
      }

      // Get provider from app group
      const provider = getProviderFromGroup(apps[appValue]["group"]);
      
      if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
        $("#model-selected").text(`${provider} (${model} - ${$("#reasoning-effort").val()})`);
      } else {
        $("#model-selected").text(`${provider} (${params["model"]})`);
      }

      $("#model_and_file").show();
      $("#model_parameters").show();
      // Use UI utilities module if available, otherwise fallback
      if (uiUtils && uiUtils.adjustImageUploadButton) {
        uiUtils.adjustImageUploadButton(model);
      } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
        window.shims.uiUtils.adjustImageUploadButton(model);
      }
    }

    if (apps[appValue]["context_size"]) {
      $("#context-size-toggle").prop("checked", true);
      $("#context-size").prop("disabled", false);
    } else {
      $("#context-size-toggle").prop("checked", false);
      $("#context-size").prop("disabled", true);
    }

    // Use display_name if available, otherwise fall back to app_name
    const displayText = apps[appValue]["display_name"] || apps[appValue]["app_name"];
    $("#base-app-title").text(displayText);
    $("#base-app-icon").html(apps[appValue]["icon"]);

    if (apps[appValue]["monadic"]) {
      $("#monadic-badge").show();
    } else {
      $("#monadic-badge").hide();
    }

    if (apps[appValue]["tools"]) {
      $("#tools-badge").show();
    } else {
      $("#tools-badge").hide();
    }

    if (apps[appValue]["websearch"]) {
      $("#websearch").prop("checked", true);
      $("#websearch-badge").show();
    } else {
      $("#websearch").prop("checked", false);
      $("#websearch-badge").hide();
    }

    if (apps[appValue]["mathjax"]) {
      $("#mathjax").prop("checked", true);
      $("#math-badge").show();
    } else {
      $("#mathjax").prop("checked", false);
      $("#math-badge").hide();
    }

    $("#base-app-desc").html(apps[appValue]["description"]);

    $("#initial-prompt-toggle").prop("checked", false).trigger("change");
    $("#ai-user-initial-prompt-toggle").prop("checked", false).trigger("change");

    // Ensure reasoning-effort dropdown is updated after app change
    setTimeout(function() {
      const currentModel = $("#model").val();
      if (currentModel) {
        $("#model").trigger("change");
      }
    }, 100);

    $("#apps").focus();
  }

  $("#websearch").on("change", function () {
    if ($(this).is(":checked")) {
      params["websearch"] = true;
      $("#websearch-badge").show();
    } else {
      params["websearch"] = false;
      $("#websearch-badge").hide();
    }
  })

  $("#check-auto-speech").on("change", function () {
    if ($(this).is(":checked")) {
      params["auto_speech"] = true;
      console.log("Auto speech enabled");
    } else {
      params["auto_speech"] = false;
      console.log("Auto speech disabled");
    }
  })

  $("#check-easy-submit").on("change", function () {
    if ($(this).is(":checked")) {
      params["easy_submit"] = true;
    } else {
      params["easy_submit"] = false;
    }
  })

  $("#mathjax").on("change", function () {
    if ($(this).is(":checked")) {
      params["mathjax"] = true;
      $("#math-badge").show();
    } else {
      params["mathjax"] = false;
      $("#math-badge").hide();
    }
  });

  // Initialize page state based on screen width when document is ready
  $(document).ready(function() {
    // Initialize UIState if available
    if (window.UIState && window.UIState.initialize) {
      try {
        window.UIState.initialize();
        console.log('UIState initialized successfully');
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
    if ($(window).width() < 600) {
      // Set proper classes and hide menu on mobile
      $("#toggle-menu").addClass("menu-hidden").html('<i class="fas fa-bars"></i>');
      $("#menu").hide();
      $("#main").show();
      $("body").removeClass("menu-visible");
      $("#main").removeClass("col-md-8").addClass("col-md-12");
      // Note: Removed inline CSS injection for toggle-menu in document.ready
    } else {
      // On desktop, menu is visible by default, so set the appropriate icon and style
      $("#toggle-menu").removeClass("menu-hidden").html('<i class="fas fa-times"></i>');
    }
    
    // Initialize scroll buttons state
    setTimeout(function() {
      if (uiUtils && uiUtils.adjustScrollButtons) {
        uiUtils.adjustScrollButtons();
      } else if (typeof adjustScrollButtonsFallback === 'function') {
        adjustScrollButtonsFallback();
      }
    }, 100);
  });
  
  // Also ensure positions are set on load event
  $(window).on("load", function() {
    // Fix layout on load to ensure proper state
    setTimeout(function() {
      fixLayoutAfterResize();
    }, 100);
  });
  
  // Function to ensure navbar elements are perfectly centered
  function centerNavbarElements() {
    // Only run on mobile
    if ($(window).width() >= 600) return;
    
    // Set logo with fixed positioning left-aligned, aligning with toggle menu button
    $(".navbar-brand").css({
      "position": "fixed",
      "top": "0",
      "left": "15px",
      "height": "52px", // Updated to match navbar height
      "display": "flex",
      "align-items": "center",
      "justify-content": "flex-start",
      "margin": "0",
      "width": "auto",
      "transform": "none"
    });
    
    // Completely override the first div inside navbar-brand to precisely control positioning
    $(".navbar-brand > div:first-child").css({
      "margin": "0", // Reset all margins
      "margin-left": "6px", // Maintain the 6px left margin
      "margin-top": "0", // Remove the negative top margin 
      "padding-top": "0", // Reset padding
      "font-weight": "500",
      "font-family": "'Montserrat', sans-serif",
      "letter-spacing": "0.12em",
      "display": "flex",
      "align-items": "center",
      "position": "relative",
      "top": "1px" // Fine-tuned for vertical alignment with toggle button
    });
    
    // Fine tune the image and text elements for perfect vertical alignment
    $(".navbar-brand img").css({
      "width": "1.6em", // Slightly smaller logo to match toggle button
      "vertical-align": "middle",
      "margin-top": "0",
      "margin-right": "8px" // More space between icon and text
    });
    
    // Apply consistent vertical alignment to text spans
    $(".navbar-brand .reset-area").css({
      "vertical-align": "middle",
      "position": "relative",
      "top": "0px"
    });
    
    // Ensure the content inside navbar-brand is aligned
    $(".navbar-brand div").css({
      "display": "flex",
      "align-items": "center"
    });
    
      // Removed inline CSS injection for toggle-menu in centerNavbarElements
    
    // Optimize scrollable areas for mobile
    optimizeMobileScrolling();
  }
  
  // Function to optimize scrollable areas on mobile devices
  function optimizeMobileScrolling() {
    // Only run on mobile
    if ($(window).width() >= 600) return;
    
    // Ensure the main content area takes maximum available space
    $("#main").css({
      "padding-bottom": "0",
      "margin-bottom": "0"
    });
    
    // Optimize scrollable container to use full height
    $(".scrollable").css({
      "height": "calc(100vh - 80px)", // Match the CSS height calculation
      "padding-bottom": "0", // No bottom padding needed
      "margin-bottom": "0 !important",
      "overflow-y": "auto"
    });
    
    // Ensure content container has correct height
    $("#contents").css({
      "height": "calc(100vh - 80px)", // Match the scrollable height
      "min-height": "calc(100vh - 80px)", // Ensure at least this height
      "padding-bottom": "12px", // Consistent padding all around
      "padding-top": "0", // Keep top padding removed for mobile
      "margin-bottom": "0", // No additional margin needed
      "box-sizing": "border-box"
    });
    
    // Make user panel more space-efficient
    $("#user-panel").css({
      "margin-bottom": "0",
      "padding-bottom": "0"
    });
    
    // Fix iOS-specific scroll issues
    if (/iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream) {
      $(".scrollable").css({
        "-webkit-overflow-scrolling": "touch",
        "transform": "translateZ(0)",
        "-webkit-transform": "translateZ(0)"
      });
    }
  }

  // Listen for window resize events
  $(window).on("resize", function() {
    const wasMenuVisible = $("#menu").is(":visible");
    const windowWidth = $(window).width();
    
    // Only reposition on mobile
    if (windowWidth < 600) {
      centerNavbarElements();
    } else if (windowWidth >= 600 && !wasMenuVisible) {
      // We've changed from mobile to desktop view with hidden menu
      // Restore proper column layout and show menu
      $("#main").removeClass("col-md-12").addClass("col-md-8");
      $("#menu").show();
      $("#toggle-menu").removeClass("menu-hidden");
    }
  });

  // Handle toggle-menu button click with comprehensive error handling
  $("#toggle-menu").on("click", function (e) {
    try {
      // Prevent any default behavior
      e.preventDefault();
      e.stopPropagation();
      
      // Get required elements with safety checks
      const $toggleBtn = $(this);
      const $menu = $("#menu");
      const $main = $("#main");
      const $spinner = $("#monadic-spinner");
      
      if (!$toggleBtn.length || !$menu.length || !$main.length) {
        console.error('Required elements missing for menu toggle');
        return false;
      }
      
      // Check if AI is currently responding
      const isStreaming = window.streamingResponse || 
                         (window.UIConfig && window.UIConfig.STATE && window.UIConfig.STATE.isStreaming);
      
      if ($spinner.is(":visible") || isStreaming) {
        // Don't allow toggle during AI response
        // Add visual feedback that the button is disabled
        $toggleBtn.css("opacity", "0.5").attr("aria-disabled", "true");
        setTimeout(() => {
          $toggleBtn.css("opacity", "1").attr("aria-disabled", "false");
        }, 200);
        return false;
      }
      
      // Check if we're on mobile with fallback
      const isMobile = window.UIConfig ? 
        window.UIConfig.isMobileView() : 
        $(window).width() < 600;
      
      // Toggle menu visibility and change icon to indicate state
      const menuVisible = $menu.is(":visible");
      
      if (menuVisible) {
        // Menu is visible, will be hidden
        $toggleBtn.addClass("menu-hidden")
                  .attr("aria-expanded", "false")
                  .html('<i class="fas fa-bars"></i>'); // Change to bars when menu closed
        
        if (isMobile) {
          // On mobile: hide menu and show main
          $menu.hide();
          $main.show();
          $("body").removeClass("menu-visible");
        } else {
          // On desktop: normal column behavior
          $main.removeClass("col-md-8").addClass("col-md-12");
          $menu.hide();
        }
      } else {
        // Menu is hidden, will be shown
        $toggleBtn.removeClass("menu-hidden")
                  .attr("aria-expanded", "true")
                  .html('<i class="fas fa-times"></i>'); // Change to X when menu open
        
        if (isMobile) {
          // On mobile: show menu and hide main completely
          $menu.show();
          $main.hide();
          $("body").addClass("menu-visible"); 
        } else {
          // On desktop: normal column behavior
          $main.removeClass("col-md-12").addClass("col-md-8");
          $menu.show();
        }
      }
      
      // Update UI state if available
      if (window.UIConfig && window.UIConfig.STATE) {
        window.UIConfig.STATE.isMenuVisible = !menuVisible;
      }
      
      // Reset scroll position
      $("body, html").animate({ scrollTop: 0 }, 0);
      
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
      $("#main, #menu").scrollTop(0);
      
      // On mobile, force elements to maintain their positions
      if (isMobile) {
        // Fix logo position using fixed positioning - left aligned
        $(".navbar-brand").css({
          "position": "fixed",
          "top": "0",
          "left": "15px",
          "height": "54px", 
          "display": "flex",
          "align-items": "center",
          "justify-content": "flex-start",
          "margin": "0",
          "width": "auto",
          "transform": "none"
        });
        
        // Ensure the content inside navbar-brand is left aligned
        $(".navbar-brand div").css({
          "display": "flex",
          "align-items": "center"
        });
        
        // Fix toggle button position with exact coordinates
        $("#toggle-menu").css({
          "position": "fixed",
          "top": "12px", // Match the value used elsewhere
          "right": "10px",
          "height": "30px", // Match the size used elsewhere
          "width": "30px", // Match the size used elsewhere
          "padding": "6px", // Match the padding used elsewhere
          "transform": "none"
        });
      }
      
      // Run scrollable area optimization for all mobile devices
      if ($(window).width() < 768) {
        optimizeMobileScrolling();
      }
      
      // iOS Safari specific fix to ensure proper layout after toggle
      if (/iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream) {
        // Force a repaint
        $("#main, #menu").css("transform", "translateZ(0)");
        
        // Run optimization again after a short delay for iOS
        setTimeout(optimizeMobileScrolling, window.UIConfig ? window.UIConfig.TIMING.LAYOUT_FIX_DELAY : 100);
      }
      }, 10); // Very small timeout
      
      return false; // Prevent event bubbling
      
    } catch (error) {
      console.error('Error in menu toggle:', error);
      // Attempt recovery
      try {
        $("#main").show();
        $("#toggle-menu").show();
        $("body").removeClass("menu-visible");
      } catch (recoveryError) {
        console.error('Recovery failed:', recoveryError);
      }
      return false;
    }
  });

  // Function to update toggle button text based on checkbox states
  function updateToggleButtonText() {
    const autoSpeechChecked = $("#check-auto-speech").prop("checked");
    const easySubmitChecked = $("#check-easy-submit").prop("checked");
    const $toggleButton = $("#interaction-toggle-all");
    
    if (typeof webUIi18n !== 'undefined' && webUIi18n.initialized) {
      // Show appropriate text based on current state
      if (autoSpeechChecked && easySubmitChecked) {
        $toggleButton.text(webUIi18n.t('ui.uncheckAll'));
      } else if (!autoSpeechChecked && !easySubmitChecked) {
        $toggleButton.text(webUIi18n.t('ui.checkAll'));
      } else {
        $toggleButton.text(webUIi18n.t('ui.toggleAll'));
      }
    }
  }
  
  // Toggle all interaction checkboxes
  $("#interaction-toggle-all").on("click", function () {
    const autoSpeechChecked = $("#check-auto-speech").prop("checked");
    const easySubmitChecked = $("#check-easy-submit").prop("checked");
    
    // If any checkbox is unchecked, check all. Otherwise, uncheck all.
    const shouldCheck = !autoSpeechChecked || !easySubmitChecked;
    
    $("#check-auto-speech").prop("checked", shouldCheck);
    $("#check-easy-submit").prop("checked", shouldCheck);
    
    // Update the button text after toggling
    updateToggleButtonText();
  });
  
  // Update toggle button text when individual checkboxes change
  $("#check-auto-speech, #check-easy-submit").on("change", function() {
    updateToggleButtonText();
  });
  
  // Initialize toggle button text on page load
  $(document).ready(function() {
    updateToggleButtonText();
  });

  $("#start").on("click", function () {
    audioInit();
    $("#asr-p-value").text("").hide();

    if (checkParams()) {
      params = setParams();
    } else {
      return;
    }
    

    // Ensure UI controls are properly enabled by default
    // This prevents UI getting stuck in disabled state
    function ensureControlsEnabled() {
      $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import").prop("disabled", false);
      $("#message").prop("disabled", false);
      $("#select-role").prop("disabled", false);
      $("#monadic-spinner").hide();
      $("#cancel_query").hide();
    }

    // Set a safety timeout to re-enable controls if they remain disabled
    const safetyTimeout = setTimeout(function() {
      // Only run if user panel is visible but controls are disabled
      if ($("#user-panel").is(":visible") && $("#send").prop("disabled")) {
        console.log("Safety timeout: Re-enabling controls that were left in disabled state");
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
      $("#config").hide();
      $("#back-to-settings").show();
      $("#main-panel").show();
      $("#discourse").show();
      $("#chat").html("")
      $("#temp-card").hide();
      $("#parameter-panel").show();
      $("#user-panel").show();
      setInputFocus();
      ensureControlsEnabled();
    } else {
      // create secure random 4-digit number
      ws.send(JSON.stringify({
        message: "SYSTEM_PROMPT",
        content: $("#initial-prompt").val(),
        mathjax: $("#mathjax").is(":checked"),
        monadic: params["monadic"],
        websearch: params["websearch"],
        jupyter: params["jupyter"],
        conversation_language: params["conversation_language"] || "auto",
      }));

      // Initialize audio before showing the UI
      audioInit();
      
      $("#config").hide();
      $("#back-to-settings").show();
      $("#parameter-panel").show();
      $("#main-panel").show();
      $("#discourse").show();

      // Only initiate from assistant if it's a fresh conversation (no existing messages)
      // This prevents auto-generation when importing conversations
      if ($("#initiate-from-assistant").is(":checked") && messages.length === 0) {
        $("#temp-card").show();
        $("#user-panel").hide();
        $("#monadic-spinner").show(); // Show spinner for initial assistant message
        setAlert(`<i class='fas fa-spinner fa-spin'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.generatingResponse') : 'Generating response from assistant...'}`, "info");
        document.getElementById('cancel_query').style.setProperty('display', 'flex', 'important');
        reconnect_websocket(ws, function (ws) {
          // Ensure critical parameters are correctly set based on checkboxes
          params["auto_speech"] = $("#check-auto-speech").is(":checked");
          params["initiate_from_assistant"] = true;
              ws.send(JSON.stringify(params));
        });
      } else {
        $("#user-panel").show();
        ensureControlsEnabled();
        setInputFocus();
      }
    }
  });

  // if $ai-user-toggle is enabled, $ai-user-initial-prompt will be automatically disabled
  $("#ai-user-toggle").on("change", function () {
    if ($(this).is(":checked")) {
      $("#initiate-from-assistant").prop("checked", false).trigger("change");
    }
  });

  // if $ai-user-initial-prompt is enabled, $ai-user-toggle will be automatically disabled
  $("#initiate-from-assistant").on("change", function () {
    if ($(this).is(":checked")) {
      $("#ai-user-toggle").prop("checked", false);
    }
  });

  $("#cancel_query").on("click", function () {
    setAlert(`<i class='fa-solid fa-ban' style='color: #ffc107;'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.operationCanceled') : 'Operation canceled'}`, "warning");
    ttsStop();

    responseStarted = false;
    callingFunction = false;
    streamingResponse = false;  // Reset streaming flag
    
    // Re-enable toggle menu
    $("#toggle-menu").removeClass("streaming-active").css("cursor", "");

    // Clear spinner check interval if it exists
    if (window.spinnerCheckInterval) {
      clearInterval(window.spinnerCheckInterval);
      window.spinnerCheckInterval = null;
    }

    // Reset AI user state if active
    const placeholderText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
      webUIi18n.t('ui.messagePlaceholder') : "Type your message . . .";
    $("#message").attr("placeholder", placeholderText);
    $("#message").prop("disabled", false);
    $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import").prop("disabled", false);
    $("#ai_user_provider").prop("disabled", false);
    $("#ai_user").prop("disabled", false);
    $("#select-role").prop("disabled", false);

    // Send cancel message to server
    ws.send(JSON.stringify({ message: "CANCEL" }));
    
    // Reset UI completely
    $("#chat").html("");
    $("#temp-card").hide();
    $("#user-panel").show();
    $("#monadic-spinner").hide();  // Hide spinner
    $("#indicator").hide();  // Hide indicator
    document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');  // Force hide cancel button
    
    // Set focus back to input
    setInputFocus();
  });

  $("#send").on("click", function (event) {
    event.preventDefault();
    if (message.value === "") {
      return;
    }
    audioInit();
    setAlert(`<i class='fas fa-robot'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.thinking') : 'THINKING'}`, "warning");
    params = setParams();
    const userMessageText = $("#message").val();
    params["message"] = userMessageText;
    
    // This is handled already in setParams(), no need to override here

    document.getElementById('cancel_query').style.setProperty('display', 'flex', 'important');
    
    $("#monadic-spinner").show();

    // Temporarily push a placeholder message to prevent double display
    // This will be replaced by the actual message from the server
    if (messages.length === 0) {
      // Add a temporary object to messages array to prevent duplicates
      const tempMid = "temp_" + Math.floor(Math.random() * 100000);
      // Use SessionState for centralized state management
      window.SessionState.addMessage({ role: "user", text: userMessageText, mid: tempMid, temp: true });
      
      // Show loading indicators but don't create a card yet
      // The actual card will be created when server responds
      $("#temp-card").show();
      $("#temp-card .status").hide();
      $("#indicator").show();
    }

    if ($("#select-role").val() !== "user") {
      // Show spinner to indicate processing
      setAlert(`<i class='fas fa-spinner fa-spin'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.processingMessage') : 'Processing sample message'}`, "warning");
      
      // Set a reasonable timeout to avoid UI getting stuck
      let sampleTimeoutId = setTimeout(function() {
        $("#monadic-spinner").hide();
        $("#cancel_query").hide();
        setAlert(typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.sampleTimeout') : 'Sample message timed out. Please try again.', "error");
      }, 5000);
      
      // Store timeout ID in window object so it can be cleared in the websocket listener
      window.currentSampleTimeout = sampleTimeoutId;
      
      reconnect_websocket(ws, function (ws) {
        const role = $("#select-role").val().split("-")[1];
        const msg_object = { message: "SAMPLE", content: userMessageText, role: role }
        ws.send(JSON.stringify(msg_object));
        
        // Clear input field and reset role selector immediately
        $("#message").css("height", "96px").val("");
        $("#select-role").val("user").trigger("change");
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
        $("#message").css("height", "96px").val("");

        // Clear all images including PDFs after sending
        images = [];
        updateFileDisplay(images);
      });
    }
    $("#select-role").val("user");
    $("#role-icon i").removeClass("fa-robot fa-bars").addClass("fa-face-smile");
  });

  $("#clear").on("click", function (event) {
    event.preventDefault();
    $("#message").css("height", "100px").val("");
    setInputFocus()
  });

  $("#settings").on("click", function () {
    ttsStop();
    audioInit();
    $("#config").show();
    $("#back-to-settings").hide();
    $("#main-panel").hide();
    $("#parameter-panel").hide();
    // Wait for i18n to be ready before updating button text
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        if (messages.length > 0) {
          const continueText = webUIi18n.t('ui.session.continueSession');
          $("#start-label").text(continueText);
        } else {
          const startText = webUIi18n.t('ui.session.startSession');
          $("#start-label").text(startText);
        }
      });
    } else {
      // Fallback if i18nReady is not available
      if (messages.length > 0) {
        const continueText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
          webUIi18n.t('ui.session.continueSession') : 'Continue Session';
        $("#start-label").text(continueText);
      } else {
        const startText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
        webUIi18n.t('ui.session.startSession') : 'Start Session';
      $("#start-label").text(startText);
      }
    }
    adjustScrollButtons();
    setInputFocus()
  });


  // Regular reset button - keeps current app
  $("#reset").on("click", function (event) {
    ttsStop();
    audioInit();
    resetEvent(event, false); // false = keep current app
    $("#select-role").val("user").trigger("change");
    // Wait for i18n to be ready before updating button text
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        const startText = webUIi18n.t('ui.session.startSession');
        $("#start-label").text(startText);
      });
    } else {
      // Fallback if i18nReady is not available
      const startText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
        webUIi18n.t('ui.session.startSession') : 'Start Session';
      $("#start-label").text(startText);
    }
    $("#model").prop("disabled", false);
  });
  
  // Logo click - resets conversation but keeps current app
  $(".reset-area").on("click", function (event) {
    ttsStop();
    audioInit();
    resetEvent(event, false); // false = keep current app
    $("#select-role").val("user").trigger("change");
    // Wait for i18n to be ready before updating button text
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        const startText = webUIi18n.t('ui.session.startSession');
        $("#start-label").text(startText);
      });
    } else {
      // Fallback if i18nReady is not available
      const startText = typeof webUIi18n !== 'undefined' && webUIi18n.ready ? 
        webUIi18n.t('ui.session.startSession') : 'Start Session';
      $("#start-label").text(startText);
    }
    $("#model").prop("disabled", false);
  });

  $("#save").on("click", function () {
    const allMessages = [];
    const initial_prompt = $("#initial-prompt").val();
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

    obj = {
      "parameters": setParams(),
      "messages": allMessages
    };
    saveObjToJson(obj, "monadic.json");
  });

  $("#load").on("click", function (event) {
    event.preventDefault();
    // Reset the file input and disable the import button
    $("#file-load").val('');
    $("#import-button").prop('disabled', true);
    
    // Use the form handlers module if available, otherwise fallback
    if (formHandlers && formHandlers.showModalWithFocus) {
      const cleanupFn = function() {
        $('#file-load').val('');
        $('#import-button').prop('disabled', true);
      };
      formHandlers.showModalWithFocus('loadModal', 'file-load', cleanupFn);
    } else {
      // Show the modal using the fallback
      $("#loadModal").modal("show");
      
      // Store focus timer in modal's data to ensure cleanup
      const $modal = $("#loadModal");
      const existingTimer = $modal.data('focusTimer');
      
      // Clear any existing timer
      if (existingTimer) {
        clearTimeout(existingTimer);
      }
      
      // Set new timer and store reference
      $modal.data('focusTimer', setTimeout(function () {
        $("#file-load").focus();
        // Clear reference after use
        $modal.removeData('focusTimer');
      }, 500));
    }
  });

  $("#loadModal").on("shown.bs.modal", function () {
    $("#file-title").focus();
  });
  
  $("#loadModal").on("hidden.bs.modal", function () {
    // Reset form state when modal is closed
    $('#file-load').val('');
    $('#import-button').prop('disabled', true);
    $("#load-spinner").hide();
  });

  $("#pdf-import").on("click", function (event) {
    event.preventDefault();
    $("#file-title").val("");
    $("#fileFile").val("");
    $("#fileModal").modal("show");

    // Initialize storage mode radios based on current provider/model
    try {
      const appName = $("#apps").val();
      const group = (window.apps && appName && window.apps[appName]) ? window.apps[appName]["group"] : '';
      const isOpenAI = group.toLowerCase() === 'openai';
      const model = $("#model").val();
      const supportsPdfUpload = (typeof window.isPdfSupportedForModel === 'function') ? window.isPdfSupportedForModel(model) : false;

      // Fetch server defaults and availability
      $.getJSON('/api/pdf_storage_defaults').done(function(info) {
        const pgAvailable = !!info.pgvector_available;
        const defaultStorage = (info.default_storage || 'local').toLowerCase();

        // Enable/disable by availability
        $("#storage-local").prop('disabled', !pgAvailable);
        // Always allow selecting Cloud to experiment; routing will still guard by provider
        $("#storage-cloud").prop('disabled', false);

        // Decide selection
        let select = 'local';
        if (defaultStorage === 'cloud' || !pgAvailable) select = 'cloud';
        if (select === 'cloud' && $("#storage-cloud").prop('disabled')) select = 'local';
        if (select === 'local' && $("#storage-local").prop('disabled')) select = 'cloud';

        if (select === 'cloud') {
          $("#storage-cloud").prop('checked', true);
        } else {
          $("#storage-local").prop('checked', true);
        }
      }).fail(function() {
        // Fallback: prefer local if enabled, else cloud
        const pgAvailable = true;
        $("#storage-local").prop('disabled', false);
        $("#storage-cloud").prop('disabled', false);
        $("#storage-local").prop('checked', true);
      });
    } catch (_) {}

    // Set a friendly placeholder for file title
    try {
      const ph = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.fileTitlePlaceholder') : 'File name will be used if not provided';
      $("#file-title").attr('placeholder', ph);
    } catch (_) {}
  });

  let fileTitle = "";

  // Ensure event handler is properly attached when document is ready
  $(document).on("click", "#uploadFile", async function (e) {
    e.preventDefault();
    
    const fileInput = $("#fileFile")[0];
    const file = fileInput.files[0];
    
    // Check if formHandlers is available
    if (typeof formHandlers === 'undefined' || !formHandlers.uploadPdf) {
      setAlert(typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.uploadNotAvailable') : 'Upload functionality not available', "error");
      return;
    }
    
    try {
      // Disable UI elements during upload
      $("#fileModal button").prop("disabled", true);
      $("#file-spinner").show();
      
      fileTitle = $("#file-title").val();
      
      // Use the form handlers module if available, otherwise fallback
      const response = await formHandlers.uploadPdf(file, fileTitle);
      
      // Process the response
      if (response && response.success) {
        // Clean up UI
        $("#file-spinner").hide();
        $("#fileModal button").prop('disabled', false);
        $("#fileModal").modal("hide");
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
        $("#file-spinner").hide();
        $("#fileModal button").prop('disabled', false);
        $("#fileModal").modal("hide");
        
        setAlert(`${errorMessage}`, "error");
      }
      
    } catch (error) {
      console.error("Error uploading PDF:", error);
      
      // Clean up UI on error
      $("#file-spinner").hide();
      $("#fileModal button").prop("disabled", false);
      $("#fileModal").modal("hide");
      
      // Show appropriate error message
      const errorMessage = error.statusText || error.message || "Unknown error";
      const uploadErrorMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.uploadError') : 'Error uploading file';
      setAlert(`${uploadErrorMsg}: ${errorMessage}`, "error");
    }
  });

  $("#doc").on("click", function (event) {
    event.preventDefault();
    $("#docLabel").val("");
    $("#docFile").val("");
    
    // Use the form handlers module if available, otherwise fallback
    if (formHandlers && formHandlers.showModalWithFocus) {
      const cleanupFn = function() {
        $('#docFile').val('');
        $('#convertDoc').prop('disabled', true);
      };
      formHandlers.showModalWithFocus('docModal', 'docFile', cleanupFn);
    } else {
      // Show the modal using fallback
      $("#docModal").modal("show");
      
      // Store focus timer in modal's data to ensure cleanup
      const $modal = $("#docModal");
      const existingTimer = $modal.data('focusTimer');
      
      // Clear any existing timer
      if (existingTimer) {
        clearTimeout(existingTimer);
      }
      
      // Set new timer and store reference
      $modal.data('focusTimer', setTimeout(function () {
        $("#docFile").focus();
        // Clear reference after use
        $modal.removeData('focusTimer');
      }, 500));
    }
  });

  $("#docModal").on("hidden.bs.modal", function () {
    $('#docFile').val('');
    $('#convertDoc').prop('disabled', true);
    
    // Ensure any remaining timers are cleared
    const $modal = $(this);
    const existingTimer = $modal.data('focusTimer');
    if (existingTimer) {
      clearTimeout(existingTimer);
      $modal.removeData('focusTimer');
    }
  });

  // Use the form handlers module for file input validation
  if (formHandlers && formHandlers.setupFileValidation) {
    formHandlers.setupFileValidation(
      document.getElementById('docFile'), 
      document.getElementById('convertDoc')
    );
  } else {
    // Fallback to direct event handler
    $("#docFile").on("change", function() {
      const file = this.files[0];
      $('#convertDoc').prop('disabled', !file);
    });
  }

  $("#convertDoc").on("click", async function () {
    const docInput = $("#docFile")[0];
    const doc = docInput.files[0];
    
    try {
      const docLabel = $("#doc-label").val() || "";
      
      // Disable UI elements during processing
      $("#docModal button").prop("disabled", true);
      $("#doc-spinner").show();
      
      // Use the form handlers module if available, otherwise fallback
      const response = await formHandlers.convertDocument(doc, docLabel);
      
      // Process the response
      if (response && response.success) {
        // Extract content and append it to the message
        const content = response.content;
        const message = $("#message").val().replace(/\n+$/, "");
        $("#message").val(`${message}\n\n${content}`);
        
        // Use the UI utilities module for resizing
        if (uiUtils && uiUtils.autoResize) {
          uiUtils.autoResize(document.getElementById('message'), 100);
        } else {
          autoResizeFallback(document.getElementById('message'), 100);
        }
        
        // Clean up UI
        $("#doc-spinner").hide();
        $("#docModal button").prop('disabled', false);
        $("#docModal").modal("hide");
        $("#back_to_bottom").trigger("click");
        $("#message").focus();
      } else {
        // Show error message from API
        const errorMessage = response && response.error ? response.error : "Failed to convert document";
        
        // Clean up UI
        $("#doc-spinner").hide();
        $("#docModal button").prop('disabled', false);
        $("#docModal").modal("hide");
        
        setAlert(`${errorMessage}`, "error");
      }
      
    } catch (error) {
      console.error("Error converting document:", error);
      
      // Clean up UI on error
      $("#doc-spinner").hide();
      $("#docModal button").prop("disabled", false);
      $("#docModal").modal("hide");
      
      // Show appropriate error message
      const errorMessage = error.statusText || error.message || "Unknown error";
      const convertErrorMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.convertError') : 'Error converting document';
      setAlert(`${convertErrorMsg}: ${errorMessage}`, "error");
    }
  });

  // Cloud PDF list handlers
  async function refreshCloudPdfList() {
    try {
      const $list = $("#cloud-pdf-list");
      if (!$list.length) return;
      $list.html('<span class="text-secondary">Loading...</span>');
      const res = await $.getJSON('/openai/pdf?action=list');
      if (!res || !res.success) {
        $list.html('<span class="text-danger">Failed to load</span>');
        return;
      }
      // Update Cloud meta (move Vector Store ID to footer; keep header clean)
      try {
        const vs = res.vector_store_id || '';
        $("#cloud-pdf-meta").text(vs ? `Vector Store ID: ${vs}` : '');
        // Do not show VS in header to avoid confusion
        // Leave #cloud-pdf-info handling to status refresher
      } catch (_) {}
      const files = res.files || [];
      if (files.length === 0) {
        $list.html('<span class="text-secondary">(none)</span>');
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
      $list.html(rows.join(''));
    } catch (e) {
      $("#cloud-pdf-list").html('<span class="text-danger">Failed to load</span>');
    }
  }

  $(document).on('click', '#cloud-pdf-refresh', function(e) {
    e.preventDefault();
    refreshCloudPdfList();
  });

  $(document).on('click', '#cloud-pdf-clear', async function(e) {
    e.preventDefault();
    try {
      const msg = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.clearAllCloudPdfs') : 'Clear all Cloud PDFs?';
      if (!confirm(msg)) return;
      await $.ajax({ url: '/openai/pdf?action=clear', type: 'DELETE' });
      refreshCloudPdfList();
      setAlert('<i class="fa-solid fa-circle-check"></i> Cloud PDFs cleared', 'success');
    } catch (err) {
      setAlert('Failed to clear Cloud PDFs', 'error');
    }
  });

  $(document).on('click', 'button[data-action="cloud-delete-file"]', async function(e) {
    e.preventDefault();
    const fid = $(this).data('file-id');
    const fname = $(this).data('file-name') || $(this).closest('.cloud-pdf-row').find('.cloud-pdf-name').text().trim();
    if (!fid) return;
    // Detect iOS/iPadOS
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
                  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    if (isIOS) {
      const base = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.pdfDeleteConfirmation') : 'Are you sure you want to delete';
      if (!confirm(`${base} ${fname}?`)) return;
      try {
        await $.ajax({ url: `/openai/pdf?action=delete&file_id=${encodeURIComponent(fid)}`, type: 'DELETE' });
        refreshCloudPdfList();
        setAlert('<i class="fa-solid fa-circle-check"></i> Cloud PDF deleted', 'success');
      } catch (err) {
        setAlert('Failed to delete Cloud PDF', 'error');
      }
    } else {
      // Reuse the same Bootstrap modal as local delete
      $("#pdfDeleteConfirmation").modal("show");
      $("#pdfToDelete").text(fname);
      $("#pdfDeleteConfirmed").off("click").on("click", async function (event) {
        event.preventDefault();
        try {
          await $.ajax({ url: `/openai/pdf?action=delete&file_id=${encodeURIComponent(fid)}`, type: 'DELETE' });
          $("#pdfDeleteConfirmation").modal("hide");
          $("#pdfToDelete").text("");
          refreshCloudPdfList();
          setAlert('<i class="fa-solid fa-circle-check"></i> Cloud PDF deleted', 'success');
        } catch (err) {
          $("#pdfDeleteConfirmation").modal("hide");
          $("#pdfToDelete").text("");
          setAlert('Failed to delete Cloud PDF', 'error');
        }
      });
    }
  });

  // Initial fetch when pdf panel is present
  setTimeout(refreshCloudPdfList, 500);

  // Fetch and display overall PDF storage status (mode/local/cloud presence)
  async function refreshPdfStorageStatus() {
    try {
      const res = await $.getJSON('/api/pdf_storage_status');
      if (!res || !res.success) return;
      const mode = res.mode || 'local';
      const vs = res.vector_store_id || '';
      // Footer: full Vector Store ID when available
      $("#cloud-pdf-meta").text(vs ? `Vector Store ID: ${vs}` : '');
      // Local header: show ready only; remove redundant (empty)
      $("#local-pdf-info").text(res.local_present ? '(ready)' : '');

      // Toggle sections based on current mode
      const showCloud = (mode === 'cloud');
      $('#cloud-pdf-section').toggle(showCloud);
      $('#local-pdf-section').toggle(!showCloud);
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
  $(document).on('click', '#local-pdf-refresh', function(e) {
    e.preventDefault();
    if (window.ws) ws.send(JSON.stringify({ message: "PDF_TITLES" }));
  });
  $(document).on('click', '#local-pdf-clear', function(e) {
    e.preventDefault();
    const msg = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.modals.clearAllLocalPdfs') : 'Clear all Local PDFs?';
    if (!confirm(msg)) return;
    if (window.ws) ws.send(JSON.stringify({ message: "DELETE_ALL_PDFS" }));
  });

  $("#url").on("click", function (event) {
    event.preventDefault();
    $("#urlLabel").val("");
    $("#pageURL").val("");
    
    // Use the form handlers module if available, otherwise fallback
    if (formHandlers && formHandlers.showModalWithFocus) {
      const cleanupFn = function() {
        $('#pageURL').val('');
        $('#fetchPage').prop('disabled', true);
      };
      formHandlers.showModalWithFocus('urlModal', 'pageURL', cleanupFn);
    } else {
      // Show the modal using fallback
      $("#urlModal").modal("show");
      
      // Store focus timer in modal's data to ensure cleanup
      const $modal = $("#urlModal");
      const existingTimer = $modal.data('focusTimer');
      
      // Clear any existing timer
      if (existingTimer) {
        clearTimeout(existingTimer);
      }
      
      // Set new timer and store reference
      $modal.data('focusTimer', setTimeout(function () {
        $("#pageURL").focus();
        // Clear reference after use
        $modal.removeData('focusTimer');
      }, 500));
    }
  });

  $("#urlModal").on("hidden.bs.modal", function () {
    $('#pageURL').val('');
    $('#fetchPage').prop('disabled', true);
    
    // Ensure any remaining timers are cleared
    const $modal = $(this);
    const existingTimer = $modal.data('focusTimer');
    if (existingTimer) {
      clearTimeout(existingTimer);
      $modal.removeData('focusTimer');
    }
  });

  // Use the form handlers module for URL input validation
  if (formHandlers && formHandlers.setupUrlValidation) {
    formHandlers.setupUrlValidation(
      document.getElementById('pageURL'), 
      document.getElementById('fetchPage')
    );
  } else {
    // Fallback to direct event handler
    $("#pageURL").on("change keyup input", function() {
      const url = this.value;
      // check if url is a valid url starting with http or https
      const validUrl = url.match(/^(http|https):\/\/[^ "]+$/);
      $('#fetchPage').prop('disabled', !validUrl);
    });
  }

  $("#fetchPage").on("click", async function () {
    const url = $("#pageURL").val();
    
    try {
      const urlLabel = $("#urlLabel").val() || "";
      
      // Disable UI elements during processing
      $("#urlModal button").prop("disabled", true);
      $("#url-spinner").show();
      
      // Use the form handlers module if available, otherwise fallback
      const response = await formHandlers.fetchWebpage(url, urlLabel);
      
      // Process the response
      if (response && response.success) {
        // Extract content and append it to the message
        const content = response.content;
        const message = $("#message").val().replace(/\n+$/, "");
        $("#message").val(`${message}\n\n${content}`);
        
        // Use the UI utilities module for resizing
        if (uiUtils && uiUtils.autoResize) {
          uiUtils.autoResize(document.getElementById('message'), 100);
        } else {
          autoResizeFallback(document.getElementById('message'), 100);
        }
        
        // Clean up UI
        $("#url-spinner").hide();
        $("#urlModal button").prop('disabled', false);
        $("#urlModal").modal("hide");
        $("#back_to_bottom").trigger("click");
        $("#message").focus();
      } else {
        // Show error message from API
        const errorMessage = response && response.error ? response.error : "Failed to fetch webpage";
        
        // Clean up UI
        $("#url-spinner").hide();
        $("#urlModal button").prop('disabled', false);
        $("#urlModal").modal("hide");
        
        setAlert(`${errorMessage}`, "error");
      }
      
    } catch (error) {
      console.error("Error fetching webpage:", error);
      
      // Clean up UI on error
      $("#url-spinner").hide();
      $("#urlModal button").prop("disabled", false);
      $("#urlModal").modal("hide");
      
      // Show appropriate error message
      const errorMessage = error.statusText || error.message || "Unknown error";
      const fetchErrorMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.fetchError') : 'Error fetching webpage';
      setAlert(`${fetchErrorMsg}: ${errorMessage}`, "error");
    }
  });

  $("#temperature").on("input", function () {
    $("#temperature-value").text(parseFloat($(this).val()).toFixed(1));
  });

  $("#presence-penalty").on("input", function () {
    $("#presence-penalty-value").text(parseFloat($(this).val()).toFixed(1));
  });

  $("#frequency-penalty").on("input", function () {
    $("#frequency-penalty-value").text(parseFloat($(this).val()).toFixed(1));
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
    $("#main").animate({ scrollTop: 0 }, scrollTime);
  }
  
  function scrollToBottom(e) {
    if (e) e.preventDefault();
    const scrollTime = window.UIConfig ? 
      window.UIConfig.TIMING.SCROLL_ANIMATION : 500;
    $("#main").animate({ scrollTop: $("#main").prop("scrollHeight") }, scrollTime);
  }
  
  // Click handlers
  $("#back_to_top").on("click", scrollToTop);
  $("#back_to_bottom").on("click", scrollToBottom);
  
  // Keyboard handlers (Enter and Space)
  $("#back_to_top").on("keydown", function(e) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      scrollToTop();
    }
  });
  
  $("#back_to_bottom").on("keydown", function(e) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      scrollToBottom();
    }
  });

  // Define originalParams globally to avoid reference errors
  window.originalParams = {};
  resetParams();

  $("#tts-provider").on("change", function () {
    const oldProvider = params["tts_provider"];
    params["tts_provider"] = $("#tts-provider option:selected").val();
    
    // Reset audio elements when switching TTS providers
    if (oldProvider !== params["tts_provider"] && typeof window.resetAudioElements === 'function') {
      console.log(`[TTS] Switching provider from ${oldProvider} to ${params["tts_provider"]}`);
      window.resetAudioElements();
    }
    
    // Hide all voice selection elements first
    $("#elevenlabs-voices").hide();
    $("#openai-voices").hide();
    $("#gemini-voices").hide();
    $("#webspeech-voices").hide();
    
    // Show the appropriate voice selection based on provider
    if (params["tts_provider"] === "elevenlabs" || params["tts_provider"] === "elevenlabs-flash" || params["tts_provider"] === "elevenlabs-multilingual") {
      $("#elevenlabs-voices").show();
    } else if (params["tts_provider"] === "gemini-flash" || params["tts_provider"] === "gemini-pro") {
      $("#gemini-voices").show();
    } else if (params["tts_provider"] === "webspeech") {
      $("#webspeech-voices").show();
      // Initialize Web Speech API voices if they haven't been loaded
      if (typeof initWebSpeech === 'function') {
        initWebSpeech();
      }
    } else {
      // Default for OpenAI providers
      $("#openai-voices").show();
    }

    setCookie("tts-provider", params["tts_provider"], 30);
  });

  $("#tts-voice").on("change", function () {
    params["tts_voice"] = $("#tts-voice option:selected").val();
    setCookie("tts-voice", params["tts_voice"], 30);
  });

  $("#elevenlabs-tts-voice").on("change", function () {
    params["elevenlabs_tts_voice"] = $("#elevenlabs-tts-voice option:selected").val();
    setCookie("elevenlabs-tts-voice", params["elevenlabs_tts_voice"], 30);
  });

  $("#gemini-tts-voice").on("change", function () {
    params["gemini_tts_voice"] = $("#gemini-tts-voice option:selected").val();
    setCookie("gemini-tts-voice", params["gemini_tts_voice"], 30);
  });

  $("#conversation-language").on("change", function () {
    params["conversation_language"] = $("#conversation-language option:selected").val();
    setCookie("conversation-language", params["conversation_language"], 30);
    // Also update asr_lang for STT/TTS
    params["asr_lang"] = params["conversation_language"];
    
    // Update RTL/LTR for message display based on conversation language
    updateRTLInterface(params["conversation_language"]);
    
    // Update image button visibility to ensure correct translations
    if (typeof window.checkAndUpdateImageButtonVisibility === 'function') {
      window.checkAndUpdateImageButtonVisibility();
    }
    
    console.log("Conversation language changed to:", params["conversation_language"]);
    console.log("WebSocket state:", window.ws ? window.ws.readyState : "null");
    
    // If WebSocket is open, send UPDATE_LANGUAGE message to server
    if (window.ws && window.ws.readyState === WebSocket.OPEN) {
      const message = {
        message: "UPDATE_LANGUAGE",
        new_language: params["conversation_language"]
      };
      console.log("Sending UPDATE_LANGUAGE:", message);
      window.ws.send(JSON.stringify(message));
    } else {
      console.log("Cannot send UPDATE_LANGUAGE - WebSocket not open");
      if (window.ws) {
        console.log("WebSocket readyState:", window.ws.readyState);
      }
    }
  });

  $("#tts-speed").on("input", function () {
    $("#tts-speed-value").text(parseFloat($(this).val()).toFixed(2));
    params["tts_speed"] = parseFloat($(this).val());
    setCookie("tts-speed", params["tts_speed"], 30);
  });

  $("#error-close").on("click", function (event) {
    event.preventDefault();
  })

  $("#alert-close").on("click", function (event) {
    event.preventDefault();
    $("#alert-box").hide();
  })

  $("#initial-prompt-toggle").on("click", function () {
    const $prompt = $("#initial-prompt");
    const $icon = $("#initial-prompt-icon");
    
    if ($prompt.is(":visible")) {
      $prompt.slideUp(200);
      $icon.removeClass("fa-chevron-up").addClass("fa-chevron-down");
    } else {
      $prompt.slideDown(200, function() {
        autoResize(document.getElementById('initial-prompt'), 100);
      });
      $icon.removeClass("fa-chevron-down").addClass("fa-chevron-up");
    }
  });

  $("#ai-user-initial-prompt-toggle").on("click", function () {
    const $prompt = $("#ai-user-initial-prompt");
    const $icon = $("#ai-user-initial-prompt-icon");
    
    if ($prompt.is(":visible")) {
      $prompt.slideUp(200);
      $icon.removeClass("fa-chevron-up").addClass("fa-chevron-down");
    } else {
      $prompt.slideDown(200, function() {
        autoResize(document.getElementById('ai-user-initial-prompt'), 100);
      });
      $icon.removeClass("fa-chevron-down").addClass("fa-chevron-up");
    }
  });

  // Disable voice features for browsers that don't support them, and for iOS/iPadOS
  if (!runningOnChrome && !runningOnEdge && !runningOnSafari || 
     /iPad|iPhone|iPod/.test(navigator.userAgent)) {
    // Hide the entire voice input row instead of just the button
    $("#voice-input-row").hide();
    $("#auto-speech").hide();
    $("#auto-speech-form").hide();
    // Set message placeholder to standard text - simplified without voice
    // Will be properly translated when i18n initializes
  } else {
    // Show voice input row
    $("#voice-input-row").show();
    // Set message placeholder will be handled by i18n initialization
  }

  $("#select-role").on("change", function () {
    const role = $("#select-role option:selected").val();
    if (role === "user" || role === "sample-user") {
      $("#role-icon i").removeClass("fa-robot fa-bars").addClass("fa-face-smile");
    } else if (role === "sample-assistant") {
      $("#role-icon i").removeClass("fa-face-smile fa-bars").addClass("fa-robot");
    } else if (role === "sample-system") {
      $("#role-icon i").removeClass("fa-face-smile fa-robot").addClass("fa-bars");
    }
  });

  const selectedApp = $('#apps');
  if (selectedApp.prop('selectedIndex') === -1) {
    selectedApp.prop('selectedIndex', 0);
  }

  const fileInput = $('#file-load');
  const loadButton = $('#import-button');
  const loadForm = $('#loadModal form');

  // Handle form submission with async/await pattern
  loadForm.on('submit', async function(event) {
    event.preventDefault();
    
    const file = fileInput[0].files[0];
    if (!file) {
      setAlert(typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.selectFileImport') : 'Please select a file to import', "error");
      return;
    }
    
    try {
      $("#monadic-spinner").show();
      $("#loadModal button").prop("disabled", true);
      $("#load-spinner").show();
      
      // Use the form handlers module if available, otherwise fallback
      const response = await formHandlers.importSession(file);
      
      // Process the response
      if (response && response.success) {
        // Clean up UI after successful import
        $("#loadModal").modal("hide");
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.sessionImported') : 'Session imported successfully'}`, "success");
        
        // Force reload page to load the imported session
        window.location.reload();
      } else {
        // Show error message from API
        const errorMessage = response && response.error ? response.error : "Unknown error occurred";
        setAlert(`${errorMessage}`, "error");
        
        // Keep modal open to allow another attempt
        $("#loadModal button").prop("disabled", false);
        $("#load-spinner").hide();
      }
      
    } catch (error) {
      console.error("Error importing session:", error);
      
      // Show error message
      const errorMessage = error.statusText || error.message || "Unknown error";
      const importErrorMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.importError') : 'Error importing session';
      setAlert(`${importErrorMsg}: ${errorMessage}`, "error");
      
      // Hide modal since there was an AJAX error
      $("#loadModal").modal("hide");
      
    } finally {
      // Always clean up UI elements
      $("#monadic-spinner").hide();
      $("#loadModal button").prop("disabled", false);
      $("#load-spinner").hide();
      fileInput.val('');
    }
  });
  
  // Enable/disable load button based on file selection
  if (formHandlers && formHandlers.setupFileValidation) {
    formHandlers.setupFileValidation(
      document.getElementById('file-load'), 
      document.getElementById('import-button')
    );
  } else {
    // Fallback to direct event handler
    fileInput.on('change', function () {
      if (fileInput[0].files.length > 0) {
        loadButton.prop('disabled', false);
      } else {
        loadButton.prop('disabled', true);
      }
    });
  }

  const fileFile = $('#fileFile');
  const fileButton = $('#uploadFile');

  // Use the form handlers module for file upload validation
  if (formHandlers && formHandlers.setupFileValidation) {
    formHandlers.setupFileValidation(
      document.getElementById('fileFile'), 
      document.getElementById('uploadFile')
    );
  } else {
    // Fallback to direct event handler
    fileFile.on('change', function () {
      if (fileFile[0].files.length > 0) {
        fileButton.prop('disabled', false);
      } else {
        fileButton.prop('disabled', true);
      }
    });
  }

  // Initialize tooltips with better configuration
  $("#discourse").tooltip({
    selector: '.card-header [title]',
    delay: { show: 0, hide: 0 },
    show: 100,
    container: 'body' // Place tooltips in body for easier management
  });

  // Add global function to clean up all tooltips
  window.cleanupAllTooltips = function() {
    $('.tooltip').remove(); // Directly remove all tooltip elements
    $('[data-bs-original-title]').tooltip('dispose'); // Bootstrap 5
    $('[data-original-title]').tooltip('dispose'); // Bootstrap 4
  };

  // Remove tooltips when clicking anywhere in the document
  $(document).on('click', function(e) {
    if (!$(e.target).closest('.func-play, .func-stop, .func-copy, .func-delete, .func-edit').length) {
      cleanupAllTooltips();
    }
  });

  $("#message").on("keydown", function (event) {
    if (event.key === "Tab") {
      event.preventDefault();
      $("#send").focus();
    }
  });

  $("#select-role").on("keydown", function (event) {
    if (event.key === "Tab") {
      event.preventDefault();
      $("#send").focus();
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
      $("body").addClass("rtl-messages");
      console.log("RTL messages enabled for:", langCode);
    } else {
      $("body").removeClass("rtl-messages");
      console.log("LTR messages enabled for:", langCode);
    }
  }
  
  $(document).ready(function () {
    $("#initial-prompt").css("display", "none");
    $("#initial-prompt-toggle").prop("checked", false);
    $("#ai-user-initial-prompt").css("display", "none");
    $("#ai-user-initial-prompt-toggle").prop("checked", false);
    $("#ai-user-toggle").prop("checked", false);
    
    // Initialize interface language from cookie
    // Load saved conversation language
    const savedConversationLanguage = getCookie("conversation-language");
    if (savedConversationLanguage) {
      $("#conversation-language").val(savedConversationLanguage);
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
      $("#message").on("focus", function() {
        if (uiUtils.simulateEscapeKey) {
          uiUtils.simulateEscapeKey();
        }
      });
    }
    
    // Set focus to the apps dropdown instead of start button
    $("#apps").focus();
    
    // Common viewport setup for all devices
    const viewportMeta = document.querySelector('meta[name="viewport"]');
    if (viewportMeta && !viewportMeta.content.includes('viewport-fit=cover')) {
      viewportMeta.setAttribute('content', 'width=device-width, initial-scale=1, shrink-to-fit=no, viewport-fit=cover');
    }
    
    // Apply only minimum iOS class without special behavior
    if (/iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream) {
      $("body").addClass("ios-device");
      
      // Special handling for iOS to ensure proper scrolling
      if ($(window).width() < 600) {
        // Run optimization immediately and after a small delay
        optimizeMobileScrolling();
        setTimeout(optimizeMobileScrolling, window.UIConfig ? window.UIConfig.TIMING.SCROLL_ANIMATION : 500);
      }
    }
    
    // Always run mobile optimization on page load for small screens
    if ($(window).width() < 600) {
      // Initial optimization
      optimizeMobileScrolling();
      
      // Run again after load is complete to ensure proper sizing
      $(window).on('load', function() {
        optimizeMobileScrolling();
      });
    }
    
    // Run customizable select setup before other UI operations
    setupCustomDropdown();
    
    // Apply enhanced styling to other select elements
    setupEnhancedSelects();
    
    // Ensure consistent height between the apps select and the custom dropdown group headers
    setTimeout(function() {
      const appsHeight = $("#apps").outerHeight();
      $(".custom-dropdown-group").css("height", appsHeight + "px");
    }, 100);
    
    // Initialize app icon in select dropdown
    updateAppSelectIcon();
    
    function setupCustomDropdown() {
      const $select = $("#apps");
      const $customDropdown = $("#custom-apps-dropdown");
      let isDropdownOpen = false;
      
      // Function to close the dropdown
      function closeDropdown() {
        if (isDropdownOpen) {
          $customDropdown.hide();
          isDropdownOpen = false;
          // Remove the document click handler
          $(document).off("click.customDropdown");
        }
      }
      
      // Function to open the dropdown
      function openDropdown() {
        if (!isDropdownOpen) {
          $customDropdown.show();
          isDropdownOpen = true;
          
          // Get current selected value
          const currentValue = $select.val();
          
          // Clear any existing highlights
          $(".custom-dropdown-option.highlighted").removeClass("highlighted");
          
          // First, collapse all group containers
          $(".group-container").addClass("collapsed");
          $(".custom-dropdown-group .group-toggle-icon i")
            .removeClass("fa-chevron-down")
            .addClass("fa-chevron-right");
          
          // Find and highlight the option matching the current selection
          const $selectedOption = $(`.custom-dropdown-option[data-value="${currentValue}"]`);
          if ($selectedOption.length) {
            $selectedOption.addClass("highlighted");
            
            // Find the parent group container and expand it
            const $parentGroup = $selectedOption.closest(".group-container");
            if ($parentGroup.length) {
              $parentGroup.removeClass("collapsed");
              
              // Update the toggle icon
              const groupId = $parentGroup.attr("id");
              const groupName = groupId.replace("group-", "");
              const $groupHeader = $(`.custom-dropdown-group[data-group="${groupName}"]`);
              $groupHeader.find(".group-toggle-icon i")
                .removeClass("fa-chevron-right")
                .addClass("fa-chevron-down");
            }
            
            // Ensure the selected option is visible in the dropdown
            ensureVisibleInDropdown($selectedOption, $customDropdown);
          }
          
          // Position the dropdown relative to the select
          positionDropdown();
          
          // Update the height of group headers to match the apps select
          const appsHeight = $("#apps").outerHeight();
          $(".custom-dropdown-group").css("height", appsHeight + "px");
          
          // Set up click outside handler with a small delay to avoid immediate closing
          setTimeout(function() {
            $(document).on("click.customDropdown", function(e) {
              // Check if click is outside the dropdown and trigger elements
              // Also check if the click is not on a group header (which toggles group expansion)
              if (!$(e.target).closest("#custom-apps-dropdown, #app-select-overlay, .app-select-wrapper").length) {
                closeDropdown();
              }
            });
          }, 10);
        }
      }
      
      // Show custom dropdown when clicking on the overlay div
      $("#app-select-overlay").on("click", function(e) {
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
      $(".app-select-wrapper").on("click", function(e) {
        if ($(e.target).is("#app-select-overlay")) {
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
      });
      
      // Add global ESC key handler that works regardless of focus
      $(document).on("keydown.customDropdownEsc", function(e) {
        if (e.key === "Escape" && isDropdownOpen) {
          e.preventDefault();
          e.stopPropagation();
          closeDropdown();
          return false;
        }
      });
      
      // Add keyboard navigation to the custom dropdown
      $(document).on("keydown", function(e) {
        if (isDropdownOpen) {
          const $options = $(".custom-dropdown-option:not(.disabled)");
          const $highlighted = $(".custom-dropdown-option.highlighted");
          let index = $options.index($highlighted);
          
          switch (e.key) {
            case "ArrowDown":
              e.preventDefault();
              e.stopPropagation(); // Prevent event from bubbling up
              // Move to next non-disabled option
              if (index < $options.length - 1) {
                if ($highlighted.length) {
                  $highlighted.removeClass("highlighted");
                }
                const $next = $options.eq(index + 1);
                $next.addClass("highlighted");
                
                // Ensure the element is visible in the dropdown
                ensureVisibleInDropdown($next, $customDropdown);
              } else if (index === -1) {
                // No selection yet, select first non-disabled
                const $first = $options.first();
                $first.addClass("highlighted");
                ensureVisibleInDropdown($first, $customDropdown);
              } else {
                // Already at the bottom, circle back to the first non-disabled item
                $highlighted.removeClass("highlighted");
                const $first = $options.first();
                $first.addClass("highlighted");
                ensureVisibleInDropdown($first, $customDropdown);
              }
              return false; // Prevent default and stop propagation
              break;
              
            case "ArrowUp":
              e.preventDefault();
              e.stopPropagation(); // Prevent event from bubbling up
              // Move to previous non-disabled option
              if (index > 0) {
                $highlighted.removeClass("highlighted");
                const $prev = $options.eq(index - 1);
                $prev.addClass("highlighted");
                
                // Ensure the element is visible in the dropdown
                ensureVisibleInDropdown($prev, $customDropdown);
              } else if (index === 0) {
                // At first item, circle to the last non-disabled one
                $highlighted.removeClass("highlighted");
                const $last = $options.last();
                $last.addClass("highlighted");
                ensureVisibleInDropdown($last, $customDropdown);
              }
              break;
              
            case "Enter":
            case " ": // Space key
              e.preventDefault();
              e.stopPropagation(); // Prevent event from bubbling up
              if ($highlighted.length) {
                // Trigger click on the highlighted option
                $highlighted.click();
              }
              return false; // Prevent default and stop propagation
              break;
              
            case "Escape":
              e.preventDefault();
              e.stopPropagation(); // Prevent event from bubbling up
              closeDropdown();
              return false; // Prevent default and stop propagation
              break;
          }
          return true;
        }
      });
      
      // Helper function to ensure the highlighted element is visible in the dropdown
      function ensureVisibleInDropdown($element, $container) {
        if (!$element.length || !$container.length) return;
        
        const containerHeight = $container.height();
        const containerScrollTop = $container.scrollTop();
        const elementTop = $element.position().top;
        const elementHeight = $element.outerHeight();
        
        // If element is above the visible area
        if (elementTop < 0) {
          $container.scrollTop(containerScrollTop + elementTop);
        }
        // If element is below the visible area
        else if (elementTop + elementHeight > containerHeight) {
          $container.scrollTop(containerScrollTop + elementTop + elementHeight - containerHeight);
        }
      }
      
      // Handle option selection
      $(document).on("click", ".custom-dropdown-option", function() {
        // Check if this option is disabled
        if ($(this).hasClass("disabled")) {
          return; // Don't do anything for disabled options
        }
        
        const value = $(this).data("value");
        
        // Update the real select value
        $select.val(value).trigger("change");
        
        // Close dropdown using the proper method
        closeDropdown();
      });
      
      // Add mouse hover functionality to highlight options
      $(document).on("mouseenter", ".custom-dropdown-option", function() {
        // Don't highlight disabled options
        if ($(this).hasClass("disabled")) {
          return;
        }
        $(".custom-dropdown-option.highlighted").removeClass("highlighted");
        $(this).addClass("highlighted");
      });
      
      // Update dropdown position on window resize
      $(window).on("resize", function() {
        if (isDropdownOpen) {
          positionDropdown();
        }
        
        // Ensure group headers maintain the same height as the apps select
        const appsHeight = $("#apps").outerHeight();
        $(".custom-dropdown-group").css("height", appsHeight + "px");
      });
      
      // Helper function to position the dropdown
      function positionDropdown() {
        // Get the select wrapper and its position
        const $selectWrapper = $(".app-select-wrapper");
        const $parent = $selectWrapper.parent();
        const wrapperRect = $selectWrapper[0].getBoundingClientRect();
        
        // Set dropdown position accurately based on the wrapper's position
        $customDropdown.css({
          top: $selectWrapper.outerHeight() + "px",
          left: "0px",
          width: $selectWrapper.outerWidth() + "px",
          zIndex: 1100
        });
      }
      
      // Clean up event handlers when the page is unloaded
      $(window).on("beforeunload", function() {
        if (isDropdownOpen) {
          closeDropdown();
        }
        // Remove the global ESC key handler
        $(document).off("keydown.customDropdownEsc");
      });
    }
    
    // Function to set up enhanced styling for other select elements
    function setupEnhancedSelects() {
      // Apply to all form-select elements except #apps (which has its own custom dropdown)
      $(".form-select").not("#apps").each(function() {
        const $select = $(this);
        
        // Skip if select already has custom styling
        if ($select.data("enhanced") === true) {
          return;
        }
        
        // Mark as enhanced to avoid double processing
        $select.data("enhanced", true);
        
        // Apply compact styling to all options
        $select.find("option").addClass("enhanced-option");
        
        // Apply special styling for optgroup labels if any
        $select.find("optgroup").addClass("enhanced-optgroup");
        
        // Apply special styling for disabled options (like separators)
        $select.find("option[disabled]").addClass("enhanced-separator");
      });
    }
    
    // Load AI User provider from cookie
    const savedProvider = getCookie("ai_user_provider");
    if (savedProvider) {
      $("#ai_user_provider").val(savedProvider);
      
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
      uiUtils.adjustImageUploadButton($("#model").val());
    } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
      window.shims.uiUtils.adjustImageUploadButton($("#model").val());
    }
    $("#monadic-spinner").show();
    
    // Event handlers for the message deletion confirmation dialog
    $("#deleteMessageOnly").on("click", function() {
      const data = $("#deleteConfirmation").data();
      if (data && data.mid) {
        // Check if it's a system message that needs special handling
        if (data.isSystemMessage) {
          deleteSystemMessage(data.mid, data.messageIndex !== undefined ? data.messageIndex : -1);
        } else {
          deleteMessageOnly(data.mid, data.messageIndex !== undefined ? data.messageIndex : -1);
        }
        $("#deleteConfirmation").modal("hide");
      }
    });
    
    // Handle deletion of the current message and all subsequent messages
    $("#deleteMessageAndSubsequent").on("click", function() {
      const data = $("#deleteConfirmation").data();
      if (data && data.mid) {
        // Check if it's a system message that needs special handling
        if (data.isSystemMessage) {
          deleteSystemMessage(data.mid, data.messageIndex !== undefined ? data.messageIndex : -1);
        } else {
          deleteMessageAndSubsequent(data.mid, data.messageIndex !== undefined ? data.messageIndex : -1);
        }
        $("#deleteConfirmation").modal("hide");
      }
    });
  });
});
