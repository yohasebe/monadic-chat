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

document.addEventListener("DOMContentLoaded", function () {
  // No longer disable AI User button initially - we'll show an error message if conversation hasn't started
  $("#ai_user").attr("title", "Generate AI user response based on conversation");
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

  $("#send, #clear, #voice, #tts-voice, #asr-lang, #ai-user-initial-prompt-toggle, #ai-user-toggle, #check-auto-speech, #check-easy-submit").prop("disabled", true);
  // Keep TTS speed control always enabled as it's used by multiple TTS providers
  $("#tts-speed").prop("disabled", false);

  //////////////////////////////
  // UI event handlers
  //////////////////////////////

  // Use "Chat" as the default app if not defined elsewhere
  let lastApp = typeof defaultApp !== 'undefined' ? defaultApp : "Chat";

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
    
    // Setup AI User provider selector - updated to filter by available API keys
    $("#ai_user_provider").on("change", function() {
      const provider = $(this).val();
      setCookie("ai_user_provider", provider, 30);
      updateProviderStyle(provider);
      // Get provider name from the dropdown
      const providerName = $("#ai_user_provider option:selected").text();
      // Get model for the selected provider
      const model = getDefaultModelForProvider(provider);
      // Update the UI to show selected provider and model
      $("#ai-user-model").text(`${providerName} (${model})`);
    });
    
    // Function that does nothing now - we're keeping the default btn-warning style
    function updateProviderStyle(provider) {
      // Intentionally left empty - we want to maintain the original btn-warning style
    }
    
    // Helper function to get default model for AI User based on provider
    function getDefaultModelForProvider(provider) {
      // Match this with the server-side model selection in ai_user_agent.rb
      const providerLower = provider.toLowerCase();
      
      if (providerLower.includes("anthropic") || providerLower.includes("claude")) {
        return "claude-3-5-sonnet-20241022";
      } else if (providerLower.includes("openai") || providerLower.includes("gpt")) {
        return "gpt-4.1";
      } else if (providerLower.includes("cohere") || providerLower.includes("command")) {
        return "command-r-plus";
      } else if (providerLower.includes("gemini") || providerLower.includes("google")) {
        return "mini-2.0-flash";
      } else if (providerLower.includes("mistral")) {
        return "mistral-large-latest";
      } else if (providerLower.includes("grok") || providerLower.includes("xai")) {
        return "grok-2";
      } else if (providerLower.includes("perplexity")) {
        return "sonar";
      } else if (providerLower.includes("deepseek")) {
        return "deepseek-chat";
      } else {
        // Fallback to default model
        return "gpt-4.1";
      }
    }
    
    
    // Function to update available providers in dropdown based on API keys
    // Export to window scope for access from websocket.js
    window.updateAvailableProviders = function() {
      // Hide all options first
      $("#ai_user_provider option").hide();
      
      // Loop through providers to check which ones have API keys available
      if (verified === "full") {
        // OpenAI is available for sure if verified is full
        $("#ai_user_provider option[value='openai']").show();
      }
      
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
        } else if (group.includes("mistral")) {
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
    
    // Load saved provider from cookie
    const savedProvider = getCookie("ai_user_provider");
    if (savedProvider) {
      $("#ai_user_provider").val(savedProvider);
      updateProviderStyle(savedProvider);
      // Set the display text in status panel
      const providerName = $("#ai_user_provider option:selected").text();
      const model = getDefaultModelForProvider(savedProvider);
      $("#ai-user-model").text(`${providerName} (${model})`);
    } else {
      // Use default provider style (OpenAI)
      updateProviderStyle("openai");
      // Set default display text
      const model = getDefaultModelForProvider("openai");
      $("#ai-user-model").text(`OpenAI (${model})`);
    }
    
    // Set up model change handler to update the AI Assistant info badge
    $("#model").on("change", function() {
      const selectedModel = $(this).val();
      // Extract provider from the current app group
      let provider = "OpenAI";
      const currentApp = $("#apps").val();
      if (apps[currentApp] && apps[currentApp].group) {
        const group = apps[currentApp].group.toLowerCase();
        if (group.includes("anthropic") || group.includes("claude")) {
          provider = "Anthropic";
        } else if (group.includes("gemini") || group.includes("google")) {
          provider = "Google";
        } else if (group.includes("cohere")) {
          provider = "Cohere";
        } else if (group.includes("mistral")) {
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
      $("#ai-assistant-info").html('<span style="color: #DC4C64;">AI Assistant</span> <span style="color: inherit; font-weight: normal;">' + provider + '</span>').attr("data-model", selectedModel);
      
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
      console.log("AI User button clicked");
      
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
      const alertMessage = `<i class='fas fa-spinner fa-spin'></i> Analyzing conversation`;
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
      $("#monadic-spinner span").html('<i class="fas fa-robot fa-pulse"></i> Generating AI user response');
      
      // Show a tooltip explaining the process
      $("#alert-message").attr("title", "AI User is analyzing the entire conversation to generate a natural user response");
      
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

    // Improved resize event - store timer in data attribute
    $(window).on("resize", function () {
      const $window = $(window);
      const existingTimer = $window.data('resizeTimer');
      if (existingTimer) {
        clearTimeout(existingTimer);
      }
      $window.data('resizeTimer', setTimeout(function() {
        // Use the UI utilities module if available, otherwise fall back
        if (uiUtils && uiUtils.adjustScrollButtons) {
          uiUtils.adjustScrollButtons();
        } else {
          adjustScrollButtonsFallback();
        }
        // Force nav reflow to apply correct styles on rapid resize
        const $nav = $('#main-nav');
        $nav.hide();
        $nav[0].offsetHeight; // force reflow
        $nav.show();
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

  // Call these functions on document ready
  $(function () {
    setupToggleHandlers();
    setupEventListeners();
  });

  $("#model").on("change", function() {
    const selectedModel = $("#model").val();
    const defaultModel = apps[$("#apps").val()]["model"];
    if (selectedModel !== defaultModel) {
      $("#model-non-default").show();
    } else {
      $("#model-non-default").hide();
    }

    if (modelSpec[selectedModel]) {
      if (modelSpec[selectedModel].hasOwnProperty("tool_capability") && modelSpec[selectedModel]["tool_capability"]) {
        $("#websearch").prop("disabled", false);
      } else {
        $("#websearch-badge").hide();
        $("#websearch").prop("disabled", true);
      }

      if (modelSpec[selectedModel].hasOwnProperty("reasoning_effort")) {
        $("#reasoning-effort").prop("disabled", false);
        $("#reasoning-effort").val(modelSpec[selectedModel]["reasoning_effort"]);
      } else {
        $("#reasoning-effort").prop("disabled", true);
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
    // Get current app's provider
    const currentApp = $("#apps").val();
    const provider = getProviderFromGroup(apps[currentApp]["group"]);
    
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
    } else {
      adjustImageUploadButtonFallback(selectedModel);
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
    // Reset messages array
    messages = [];
    // Clear the discourse area
    $("#discourse").html("");
    proceedWithAppChange(newAppValue);
  });
  
  // Function to handle the actual app change
  function proceedWithAppChange(appValue) {
    // All providers now support AI User functionality
    const selectedApp = apps[appValue];
    
    // Always enable AI User toggle for all providers
    $("#ai-user-toggle").prop("disabled", false);
    
    // Always enable AI User button (error message will be shown if conversation not started)
    $("#ai_user").prop("disabled", false).attr("title", "Generate AI user response based on conversation");

    if (messages.length > 0) {
      if (appValue === lastApp) {
        return;
      }
    }
    lastApp = appValue;
    // Preserve the current state of mathjax checkbox if not defined in app
    const currentMathjax = $("#mathjax").prop('checked');
    Object.assign(params, apps[appValue]);
    // Default 'initiate_from_assistant' to false if not explicitly set in app parameters
    if (!apps[appValue].hasOwnProperty('initiate_from_assistant')) {
      params['initiate_from_assistant'] = false;
    }
    // Restore mathjax state if not explicitly set in app parameters
    if (!apps[appValue].hasOwnProperty('mathjax')) {
      params['mathjax'] = currentMathjax;
    }
    loadParams(params, "changeApp");
    
    // Update app icon in the select dropdown
    updateAppSelectIcon(appValue);

    if (apps[appValue]["pdf"] || apps[appValue]["pdf_vector_storage"]) {
      $("#file-div").show();
      $("#pdf-panel").show();
      ws.send(JSON.stringify({ message: "PDF_TITLES" }));
    } else {
      $("#file-div").hide();
      $("#pdf-panel").hide();
    }

    if (apps[appValue]["image"]) {
      $("#image-file").show();
    } else {
      $("#image-file").hide();
    }

    let model;
    let models = [];

    if (apps[appValue]["models"] && apps[appValue]["models"].length > 0) {
      let models_text = apps[appValue]["models"];
      models = JSON.parse(models_text);
    }

    if (models.length > 0) {
      let openai = apps[appValue]["group"].toLowerCase() === "openai";
      let modelList = listModels(models, openai);
      $("#model").html(modelList);
      // For Ollama apps without a specific model, select the first available model
      // For other apps, select models[1] if available (to skip the disabled option)
      const isOllama = apps[appValue]["group"].toLowerCase() === "ollama";
      if (isOllama && !apps[appValue]["model"]) {
        model = models[0]; // Select first available model for Ollama
      } else {
        model = models[1] || models[0]; // Select second model if available, otherwise first
      }
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

      if (modelSpec[model] && modelSpec[model].hasOwnProperty("tool_capability") && modelSpec[model]["tool_capability"]) {
        $("#websearch").prop("disabled", false);
      } else {
        $("#websearch-badge").hide();
        $("#websearch").prop("disabled", true);
      }

      $("#model").val(model);
      // Use UI utilities module if available, otherwise fallback
      if (uiUtils && uiUtils.adjustImageUploadButton) {
        uiUtils.adjustImageUploadButton(model);
      } else {
        adjustImageUploadButtonFallback(model);
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
      adjustImageUploadButton(model);
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
  });
  
  // Also ensure positions are set on load event
  $(window).on("load", function() {
    if ($(window).width() < 600) {
      // Note: Removed inline CSS injection for toggle-menu on load
    }
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

  // Handle toggle-menu button click
  $("#toggle-menu").on("click", function (e) {
    // Prevent any default behavior
    e.preventDefault();
    e.stopPropagation();
    
    // Check if we're on mobile
    const isMobile = $(window).width() < 600;
    
    // Removed inline CSS injection for toggle-menu on click
    
    // Toggle menu visibility and change icon to indicate state
    if ($("#menu").is(":visible")) {
      // Menu is visible, will be hidden
      $(this).addClass("menu-hidden").html('<i class="fas fa-bars"></i>'); // Change to bars when menu closed
      
      if (isMobile) {
        // On mobile: hide menu and show main
        $("#menu").hide();
        $("#main").show();
        $("body").removeClass("menu-visible");
      } else {
        // On desktop: normal column behavior
        $("#main").removeClass("col-md-8").addClass("col-md-12");
        $("#menu").hide();
      }
    } else {
      // Menu is hidden, will be shown
      $(this).removeClass("menu-hidden").html('<i class="fas fa-times"></i>'); // Change to X when menu open
      
      if (isMobile) {
        // On mobile: show menu and hide main completely
        $("#menu").show();
        $("#main").hide();
        $("body").addClass("menu-visible"); 
      } else {
        // On desktop: normal column behavior
        $("#main").removeClass("col-md-12").addClass("col-md-8");
        $("#menu").show();
      }
    }
    
    // Reset scroll position
    $("body, html").animate({ scrollTop: 0 }, 0);
    
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
        setTimeout(optimizeMobileScrolling, 100);
      }
    }, 10); // Very small timeout
    
    return false; // Prevent event bubbling
  })

  $("#interaction-check-all").on("click", function () {
    $("#check-auto-speech").prop("checked", true);
    $("#check-easy-submit").prop("checked", true);
  });

  $("#interaction-uncheck-all").on("click", function () {
    $("#check-auto-speech").prop("checked", false);
    $("#check-easy-submit").prop("checked", false);
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
        setAlert("<i class='fa-solid fa-circle-check'></i> Ready for input", "success");
      }
    }, 3000); // 3 second timeout is enough for normal operations to complete

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
      }));

      // Initialize audio before showing the UI
      audioInit();
      
      $("#config").hide();
      $("#back-to-settings").show();
      $("#parameter-panel").show();
      $("#main-panel").show();
      $("#discourse").show();

      if (!$("#ai-user-toggle").is(":checked") && $("#initiate-from-assistant").is(":checked")) {
        $("#temp-card").show();
        $("#user-panel").hide();
        $("#monadic-spinner").show(); // Show spinner for initial assistant message
        setAlert("<i class='fas fa-spinner fa-spin'></i> Generating response from assistant...", "info");
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
    setAlert("<i class='fa-solid fa-ban' style='color: #ffc107;'></i> Operation canceled", "warning");
    ttsStop();

    responseStarted = false;
    callingFunction = false;

    // Reset AI user state if active
    $("#message").attr("placeholder", "Type your message . . .");
    $("#message").prop("disabled", false);
    $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import").prop("disabled", false);
    $("#ai_user_provider").prop("disabled", false);
    $("#ai_user").prop("disabled", false);

    // Send cancel message to server
    ws.send(JSON.stringify({ message: "CANCEL" }));
    
    // Reset UI
    $("#chat").html("");
    $("#temp-card").hide();
    $("#user-panel").show();
    $("#cancel_query").hide();
    
    // Set focus back to input
    setInputFocus();
  });

  $("#send").on("click", function (event) {
    event.preventDefault();
    if (message.value === "") {
      return;
    }
    audioInit();
    setAlert("<i class='fas fa-robot'></i> THINKING", "warning");
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
      messages.push({ role: "user", text: userMessageText, mid: tempMid, temp: true });
      
      // Show loading indicators but don't create a card yet
      // The actual card will be created when server responds
      $("#temp-card").show();
      $("#temp-card .status").hide();
      $("#indicator").show();
    }

    if ($("#select-role").val() !== "user") {
      // Show spinner to indicate processing
      setAlert("<i class='fas fa-spinner fa-spin'></i> Processing sample message", "warning");
      
      // Set a reasonable timeout to avoid UI getting stuck
      let sampleTimeoutId = setTimeout(function() {
        $("#monadic-spinner").hide();
        $("#cancel_query").hide();
        setAlert("Sample message timed out. Please try again.", "error");
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
    $("#message").css("height", "96px").val("");
    setInputFocus()
  });

  $("#settings").on("click", function () {
    ttsStop();
    audioInit();
    $("#config").show();
    $("#back-to-settings").hide();
    $("#main-panel").hide();
    $("#parameter-panel").hide();
    if (messages.length > 0) {
      $("#start-label").text("Continue Session");
    } else {
      $("#start-label").text("Start Session");
    }
    adjustScrollButtons();
    setInputFocus()
  });


  $("#reset, .reset-area").on("click", function (event) {
    ttsStop();
    audioInit();
    resetEvent(event);
    $("#select-role").val("user").trigger("change");
    $("#start-label").text("Start Session");
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
  });

  let fileTitle = "";

  // Ensure event handler is properly attached when document is ready
  $(document).on("click", "#uploadFile", async function (e) {
    e.preventDefault();
    
    const fileInput = $("#fileFile")[0];
    const file = fileInput.files[0];
    
    // Check if formHandlers is available
    if (typeof formHandlers === 'undefined' || !formHandlers.uploadPdf) {
      setAlert("Upload functionality not available", "error");
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
        
        // Refresh PDF titles and show success message with filename
        ws.send(JSON.stringify({ message: "PDF_TITLES" }));
        const uploadedFilename = response.filename || "PDF file";
        setAlert(`<i class='fa-solid fa-circle-check'></i> "${uploadedFilename}" uploaded successfully`, "success");
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
      setAlert(`Error uploading file: ${errorMessage}`, "error");
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
      setAlert(`Error converting document: ${errorMessage}`, "error");
    }
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
      setAlert(`Error fetching webpage: ${errorMessage}`, "error");
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
  $("#back_to_top").on("click", function (e) {
    e.preventDefault();
    $("#main").animate({ scrollTop: 0 }, 500);
  });

  $("#back_to_bottom").on("click", function (e) {
    e.preventDefault();
    $("#main").animate({ scrollTop: $("#main").prop("scrollHeight") }, 500);
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

  $("#asr-lang").on("change", function () {
    params["asr_lang"] = $("#asr-lang option:selected").val();
    setCookie("asr-lang", params["asr_lang"], 30);
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

  $("#initial-prompt-toggle").on("change", function () {
    if (this.checked) {
      $("#initial-prompt").css("display", "");
      autoResize(document.getElementById('initial-prompt'), 100);
    } else {
      $("#initial-prompt").css("display", "none");
    }
  });

  $("#ai-user-initial-prompt-toggle").on("change", function () {
    if (this.checked) {
      $("#ai-user-initial-prompt").css("display", "");
      autoResize(document.getElementById('ai-user-initial-prompt'), 100);
    } else {
      $("#ai-user-initial-prompt").css("display", "none");
    }
  });

  // Disable voice features for browsers that don't support them, and for iOS/iPadOS
  if (!runningOnChrome && !runningOnEdge && !runningOnSafari || 
     /iPad|iPhone|iPod/.test(navigator.userAgent)) {
    // Hide the entire voice input row instead of just the button
    $("#voice-input-row").hide();
    $("#auto-speech").hide();
    $("#auto-speech-form").hide();
    // Set message placeholder to standard text
    $("#message").attr("placeholder", "Type your message . . .");
  } else {
    // Show voice input row
    $("#voice-input-row").show();
    // Set message placeholder to include voice input instructions
    $("#message").attr("placeholder", "Type your message or click Speech Input button to use voice . . .");
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
      setAlert("Please select a file to import", "error");
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
        setAlert("<i class='fa-solid fa-circle-check'></i> Session imported successfully", "success");
        
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
      setAlert(`Error importing session: ${errorMessage}`, "error");
      
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

  $(document).ready(function () {
    $("#initial-prompt").css("display", "none");
    $("#initial-prompt-toggle").prop("checked", false);
    $("#ai-user-initial-prompt").css("display", "none");
    $("#ai-user-initial-prompt-toggle").prop("checked", false);
    $("#ai-user-toggle").prop("checked", false);
    
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
        setTimeout(optimizeMobileScrolling, 500);
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
    } else {
      adjustImageUploadButtonFallback($("#model").val());
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
