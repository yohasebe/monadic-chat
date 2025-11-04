const runningOnChrome = navigator.userAgent.includes("Chrome");
const runningOnEdge = navigator.userAgent.includes("Edge");
const runningOnFirefox = navigator.userAgent.includes("Firefox");
const runningOnSafari = navigator.userAgent.includes("Safari");

// Remove global DOM references to prevent memory leaks
// Instead access DOM elements directly when needed

const DEFAULT_MAX_INPUT_TOKENS = 4000;
const DEFAULT_MAX_OUTPUT_TOKENS = 4000;
const DEFAULT_CONTEXT_SIZE = 100;
const DEFAULT_APP = ""; // Empty string to select first available app

let currentPdfData = null;

// Global variables for app state management
// These are used across multiple JS files
if (typeof window.apps === 'undefined') {
  window.apps = {};
}
if (typeof window.params === 'undefined') {
  window.params = {};
}
if (typeof window.originalParams === 'undefined') {
  window.originalParams = {};
}
if (typeof window.messages === 'undefined') {
  window.messages = [];
}
if (typeof window.lastApp === 'undefined') {
  window.lastApp = null;
}
if (typeof window.stop_apps_trigger === 'undefined') {
  window.stop_apps_trigger = false;
}

// Utility function for getting translations with fallback
function getTranslation(key, fallback) {
  // Check if webUIi18n is available and initialized
  if (typeof webUIi18n !== 'undefined' && webUIi18n.initialized) {
    return webUIi18n.t(key);
  }
  // Return fallback if translation system is not ready
  return fallback;
}

// Function to update app icon in select dropdown
function updateAppSelectIcon(appValue) {
  // If no appValue is provided, use current selected app
  if (!appValue && $("#apps").val()) {
    appValue = $("#apps").val();
  }
  
  // Try to obtain icon HTML from apps definition first
  let iconHtml = (appValue && apps && apps[appValue]) ? apps[appValue]["icon"] : null;

  // Fallback: derive icon from custom dropdown option if available
  if (!iconHtml) {
    const $opt = $(`.custom-dropdown-option[data-value="${appValue}"] span:first-child`).first();
    if ($opt && $opt.length) {
      iconHtml = $opt.html();
    }
  }

  // Final fallback: use a generic chat icon
  if (!iconHtml) {
    iconHtml = '<i class="fas fa-comment"></i>';
  }
  
  // Update the icon in the static icon span
  $("#app-select-icon").html(iconHtml);

  // Icon color is now controlled by CSS rule: #app-select-icon i { color: #777; }
  
  // Also update the active class in the custom dropdown if it exists
  if ($("#custom-apps-dropdown").length > 0) {
    $(".custom-dropdown-option").removeClass("active");
    const selectedOption = $(`.custom-dropdown-option[data-value="${appValue}"]`);
    selectedOption.addClass("active");
    
    // Make sure the group containing the selected app is expanded
    if (selectedOption.length > 0) {
      const parentGroup = selectedOption.parent(".group-container");
      if (parentGroup.length > 0) {
        // Remove collapsed class from the group
        parentGroup.removeClass("collapsed");
        // Update the icon
        const groupId = parentGroup.attr("id");
        const groupName = groupId.replace("group-", "");
        // Need to handle potential dashes in the group name for xAI Grok
        let groupSelector = groupName;
        const groupHeader = $(`.custom-dropdown-group[data-group="${groupSelector}"]`);
        groupHeader.find(".group-toggle-icon i").removeClass("fa-chevron-right").addClass("fa-chevron-down");
      }
    }
  }
}

// Update the "model-selected" badge text in the menu panel
// Uses current #model value, current app's provider group, and reasoning effort (if supported)
// (reverted) updateModelSelectedBadge helper was removed


function setCookie(name, value, days) {
  const date = new Date();
  date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
  const expires = "; expires=" + date.toUTCString();
  document.cookie = name + "=" + (value || "") + expires + "; path=/";
}

function getCookie(name) {
  const nameEQ = name + "=";
  const ca = document.cookie.split(';');
  for (let i = 0; i < ca.length; i++) {
    let c = ca[i];
    while (c.charAt(0) == ' ') c = c.substring(1, c.length);
    if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length, c.length);
  }
  return null;
}

// load document.cookie and set the values to the form elements
function setCookieValues() {
  const properties = ["tts-provider", "tts-voice", "elevenlabs-tts-voice", "webspeech-voice", "tts-speed", "asr-lang"];
  properties.forEach(property => {
    const value = getCookie(property);
    if (value) {
      // check if the value is a valid option
      if ($(`#${property} option[value="${value}"]`).length > 0) {
        $(`#${property}`).val(value).trigger("change");
      }
      // Special case for elevenlabs-tts-voice which may load after this function runs
      else if (property === "elevenlabs-tts-voice") {
        // We'll handle this when voices are loaded
      }
      // Special case for webspeech-voice which may load after this function runs
      else if (property === "webspeech-voice") {
        // Store the value to be set when voices are loaded
        window.savedWebspeechVoice = value;
      }
    } else if (property === "tts-provider") {
      // Always default to "openai-tts-4o" when no cookie exists
      $(`#${property}`).val("openai-tts-4o").trigger("change");
    }
  });
}

function listModels(models, openai = false) {
  // Array of patterns to identify different model types
  const gpt5ModelPatterns = [/^gpt-5(-(?:mini|nano|pro|chat-latest))?(?:-(?:latest|\d{4}-\d{2}-\d{2}))?$/];
  const regularModelPatterns = [/^\b(?:gpt-4o|gpt-4\.\d)\b/];
  const betaModelPatterns = [/^\bo\d\b/];

  // Separate models by type
  const gpt5Models = [];
  const regularModels = [];
  const betaModels = [];
  const otherModels = [];

  for (let model of models) {
    if (gpt5ModelPatterns.some(pattern => pattern.test(model))) {
      gpt5Models.push(model);
    } else if (regularModelPatterns.some(pattern => pattern.test(model))) {
      regularModels.push(model);
    } else if (betaModelPatterns.some(pattern => pattern.test(model))) {
      betaModels.push(model);
    } else {
      otherModels.push(model);
    }
  }

  // Generate options based on the value of openai
  let modelOptions = [];

  if (openai) {
    // Include GPT-5 section at the top if GPT-5 models are available
    if (gpt5Models.length > 0) {
      modelOptions.push('<option disabled>──GPT-5 (Latest)──</option>');
      modelOptions.push(...gpt5Models.map(model =>
        `<option value="${model}" data-model-type="reasoning">${model}</option>`
      ));
    }
    
    // Include regular GPT models
    modelOptions.push('<option disabled>──gpt-models──</option>');
    modelOptions.push(...regularModels.map(model =>
      `<option value="${model}">${model}</option>`
    ));
    
    // Include reasoning models
    modelOptions.push('<option disabled>──reasoning models──</option>');
    modelOptions.push(...betaModels.map(model =>
      `<option value="${model}" data-model-type="reasoning">${model}</option>`
    ));
    
    // Include other models
    modelOptions.push('<option disabled>──other models──</option>');
    modelOptions.push(...otherModels.map(model =>
      `<option value="${model}">${model}</option>`
    ));
  } else {
    // Exclude dummy options when openai is false
    modelOptions = [
      ...gpt5Models.map(model =>
        `<option value="${model}">${model}</option>`
      ),
      ...regularModels.map(model =>
        `<option value="${model}">${model}</option>`
      ),
      ...betaModels.map(model =>
        `<option value="${model}">${model}</option>`
      ),
      ...otherModels.map(model =>
        `<option value="${model}">${model}</option>`
      )
    ];
  }

  // Join the options into a single string and return
  return modelOptions.join('');
}

// convert an object to HTML changing snake_case to space case in the keys
//////////////////////////////

  function formatInfo(info) {
    let noValue = true;
    let textRows = "";
    let numRows = "";

    for (const [key, value] of Object.entries(info)) {
      if (value && value !== 0) {
        let label = "";
        switch (key) {
          case "count_messages":
            noValue = false;
            label = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.numberOfAllMessages') : "Number of all messages";
            break;
          case "count_active_messages":
            noValue = false;
            label = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.numberOfActiveMessages') : "Number of active messages";
            break;
          case "count_all_tokens":
            noValue = false;
            label = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.tokensInAllMessages') : "Tokens in all messages";
            break;
          case "count_total_system_tokens":
            noValue = false;
            label = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.tokensInSystemPrompts') : "Tokens in all system prompts";
            break;
          case "count_total_input_tokens":
            noValue = false;
            label = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.tokensInUserMessages') : "Tokens in all user messages";
            break;
          case "count_total_output_tokens":
            noValue = false;
            label = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.tokensInAssistantMessages') : "Tokens in all assistant messages";
            break;
          case "count_total_active_tokens":
            noValue = false;
            label = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.tokensInActiveMessages') : "Tokens in all active messages";
            break;
          case "encoding_name":
            // skip and go to next iteration
            continue;
        }

        if (value && !isNaN(value) && label) {
          numRows += `
            <tr>
            <td>${label}</td>
            <td align="right">${parseInt(value).toLocaleString('en')}</td>
            </tr>
            `;
        } else if (!noValue && label) {
          textRows += `
            <tr>
            <td>${label}</td>
            <td align="right">${value}</td>
            </tr>
            `;
        }
      }
    }

    if (noValue) {
      return "";
    }

    return `
      <div class="json-item" data-key="stats" data-depth="0">
      <div class="json-toggle" onclick="toggleItem(this)">
      <i class="fas fa-chevron-right"></i> <span class="toggle-text stats-toggle-button" title="${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.tokenCount.localEstimate') : 'Token count is estimated locally.'}">${typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.clickToToggle') : 'click to toggle'}</span>
      </div>
      <div class="json-content" style="display: none;">
      <table class="table table-sm mb-0">
      <tbody>
      ${textRows}
    ${numRows}
      </tbody>
      </table>
      </div>
      </div>
      `;
  }

//////////////////////////////
  // save the javascript object to a json file
//////////////////////////////

  function saveObjToJson(obj, fileName) {
    const objToSave = Object.assign({}, obj);
    delete objToSave["parameters"]["message"];
    delete objToSave["parameters"]["pdf"];
    delete objToSave["parameters"]["tts_provider"];
    delete objToSave["parameters"]["tts_voice"];
    delete objToSave["parameters"]["elevenlabs_tts_voice"];
    delete objToSave["parameters"]["tts_speed"];
    const data = "text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(objToSave));
    const downloadLink = $('<a></a>')
      .attr('href', 'data:' + data)
      .attr('download', fileName)
      .appendTo('body');
    downloadLink[0].click();
    downloadLink.remove();
  }

//////////////////////////////
  // set focus on the start button if it is visible
// if start button is not visible but voice button is,
  // set focus on the voice button only if easy_submit and auto_speech are both enabled
// otherwise set focus on the message input
//////////////////////////////

  function setInputFocus() {
    if ($("#start").is(":visible")) {
      $("#start").focus();
    } else if ($("#check-easy-submit").is(":checked") && $("#check-auto-speech").is(":checked")) {
      $("#voice").focus();
      // show #voice-note but set it to hide when the voice button is unfocused
      $("#voice-note").show();
      $("#voice").on("blur focusout", function () {
        $("#voice-note").hide();
      });
    } else {
      $("#message").focus();
    }
  }

//////////////////////////////
  // format a message to show in the chat
//////////////////////////////

  function removeCode(text) {
    return text.replace(/```[\s\S]+?```|\<(script|style)[\s\S]+?<\/\1>|\<img [\s\S]+?\/>/g, " ");
  }

function removeMarkdown(text) {
  return text.replace(/(\*\*|__|[\*_`])/g, "");
}

function removeEmojis(text) {
  // in case of error, return the original text
  try {
    return text.replace(/\p{Extended_Pictographic}/gu, "");
  }
  catch (error) {
    return text;
  }
}

function setAlertClass(alertType = "error") {
  // Apply classes to #status-message
  // Uses StatusConfig for centralized status type management
  // Styling is done via CSS in index.erb and monadic-improvements.css

  // Remove all existing text-* classes
  $("#status-message").removeClass(function (_index, className) {
    return (className.match(/\btext-\S+/g) || []).join(' ');
  });

  // Map error to danger for consistency with Bootstrap
  if (alertType === "error") {
    alertType = "danger";
  }

  // Validate status type if StatusConfig is available
  if (typeof window.StatusConfig !== 'undefined' && !window.StatusConfig.isValidStatusType(alertType)) {
    console.warn(`[setAlertClass] Invalid status type: "${alertType}". Valid types:`, window.StatusConfig.getValidStatusTypes());
    // Fall back to 'secondary' for unknown types
    alertType = 'secondary';
  }

  // Add the new class
  $("#status-message").addClass(`text-${alertType}`);
}

function setAlert(text = "", alertType = "success") {
  if (alertType === "error") {
    $("#monadic-spinner").hide();
    // check if text["content"] exists
    let msg = text;
    if (text["content"]) {
      msg = text["content"];
    } else if (msg === "") {
      msg = "Something went wrong.";
    }

    // Create error card with system styling
    const errorCard = createCard("system", "<span class='text text-warning'><i class='fa-solid fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>", msg);

    // Add special class to identify error cards
    errorCard.addClass("error-message-card");

    // Add special handler for the delete button directly on this card
    errorCard.find(".func-delete").off("click").on("click", function(e) {
      e.stopPropagation();

      // Hide the tooltip first to prevent it from staying on screen
      $(this).tooltip('hide');

      // Also remove any other tooltips that might be visible
      $('.tooltip').remove();

      // Get the card and its ID
      const $card = $(this).closest(".card");
      const mid = $card.attr("id");

      // Immediately remove from DOM
      $card.remove();

      // Notify server to maintain consistency
      if (mid) {
        ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
        mids.delete(mid);
      }

      // Success message - direct DOM access
      $("#status-message").html("<i class='fas fa-circle-check'></i> Error message removed");
      setAlertClass("success");

      return false;
    });

    // Disable the edit button for error cards
    errorCard.find(".func-edit").prop("disabled", true).css("opacity", "0.5");

    // Append to discourse area
    $("#discourse").append(errorCard);
  } else {
    // Translate known status messages
    let displayText = text;

    // Check for common status messages that need translation
    if (typeof text === 'string') {
      if (text.includes("CALLING FUNCTIONS")) {
        displayText = `<i class='fas fa-cogs'></i> ${getTranslation('ui.messages.spinnerCallingFunctions', 'Calling functions')}`;
      } else if (text.includes("FUNCTION CALLS COMPLETE") || text.includes("FUNCTIONS COMPLETE")) {
        displayText = `<i class='fas fa-check'></i> ${getTranslation('ui.messages.functionsComplete', 'Functions complete')}`;
      } else if (text.includes("SEARCHING WEB")) {
        displayText = `<i class='fas fa-search'></i> ${getTranslation('ui.messages.spinnerSearchingWeb', 'Searching web')}`;
      } else if (text.includes("SEARCHING FILES")) {
        displayText = `<i class='fas fa-file-search'></i> ${getTranslation('ui.messages.spinnerSearchingFiles', 'Searching files')}`;
      } else if (text.includes("GENERATING IMAGE")) {
        displayText = `<i class='fas fa-image'></i> ${getTranslation('ui.messages.spinnerGeneratingImage', 'Generating image')}`;
      } else if (text.includes("CALLING MCP TOOL")) {
        displayText = `<i class='fas fa-plug'></i> ${getTranslation('ui.messages.spinnerCallingMCP', 'Calling MCP tool')}`;
      } else if (text.includes("PROCESSING")) {
        displayText = `<i class='fas fa-spinner'></i> ${getTranslation('ui.messages.spinnerProcessing', 'Processing')}`;
      } else if (text.includes("THINKING")) {
        displayText = `<i class='fas fa-brain'></i> ${getTranslation('ui.messages.spinnerThinking', 'Thinking')}`;
      } else if (text === text.toUpperCase() && text.length > 10) {
        // Generic handler for any other all-caps messages longer than 10 characters
        // Convert to sentence case
        displayText = text.charAt(0) + text.slice(1).toLowerCase();
      }
    }

    // Direct DOM access
    $("#status-message").html(`${displayText}`);
    setAlertClass(alertType);

    // Add tooltip with full text if message is truncated
    // Strip HTML tags for tooltip text
    const plainText = displayText.replace(/<[^>]*>/g, '');
    $("#status-message").attr('title', plainText);

    // Initialize Bootstrap tooltip if available
    if (typeof $.fn.tooltip === 'function') {
      // Safely dispose existing tooltip if it exists
      try {
        const $statusMsg = $("#status-message");
        if ($statusMsg.data('bs.tooltip')) {
          $statusMsg.tooltip('dispose');
        }
        $statusMsg.tooltip({
          placement: 'bottom',
          trigger: 'hover',
          delay: { show: 500, hide: 100 }
        });
      } catch (e) {
        // Tooltip not initialized yet, just create new one
        $("#status-message").tooltip({
          placement: 'bottom',
          trigger: 'hover',
          delay: { show: 500, hide: 100 }
        });
      }
    }
  }
}

function setStats(text = "") {
  // Direct DOM access without global reference
  $("#stats-message").html(`${text}`);
}

/**
 * Clear status message text and remove all status type classes
 * Used during app switching and reset operations
 */
function clearStatusMessage() {
  $("#status-message").html("");
  $("#status-message").removeClass(function (_index, className) {
    return (className.match(/\btext-\S+/g) || []).join(' ');
  });
}

/**
 * Clear all error cards from the discourse area
 * Error cards are created by setAlert() with alertType="error"
 * They have class "error-message-card"
 */
function clearErrorCards() {
  $(".error-message-card").each(function() {
    const mid = $(this).attr("id");
    if (mid) {
      // Notify server to maintain consistency
      ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
      mids.delete(mid);
    }
  });
  // Remove from DOM
  $(".error-message-card").remove();
}

function deleteMessage(mid) {
  $(`#${mid}`).remove();
  const index = messages.findIndex((m) => m.mid === mid);
  
  // If the message exists, remove it from the messages array
  if (index !== -1) {
    window.SessionState.removeMessage(index);
    ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    mids.delete(mid);
  }
}

//////////////////////////////
  // convert a string to show in the parameter panel
// e.g. "initial_prompt" -> "Initial Prompt"
//////////////////////////////

  function convertString(str) {
    return str
      .split("_")
      .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
      .join(" ");
  }

//////////////////////////////
  // Functions to load/reset/set parameters
//////////////////////////////

  let stop_apps_trigger = false;

window.loadParams = function(params, calledFor = "loadParams") {
  $("#model-non-default").hide();
  // check if params is not empty
  if (Object.keys(params).length === 0) {
    return;
  }
  
  // Set flag to prevent model change handler from resetting reasoning_effort
  window.isLoadingParams = true;
  if (window.logTL) window.logTL('loadParams_enter', {
    calledFor,
    app_name: params["app_name"],
    has_initial_prompt: !!params["initial_prompt"]
  });
  
  // Update AI Assistant info badge when model is loaded
  if (params.model) {
    const selectedModel = params.model;
    // Extract provider from app_name parameter
    let provider = "OpenAI";
    if (params.app_name && apps[params.app_name] && apps[params.app_name].group) {
      const group = apps[params.app_name].group.toLowerCase();
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
    // Update the badge in the AI User section
    const aiAssistantText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.aiAssistant') : 'AI Assistant';
    $("#ai-assistant-info").html('<span data-i18n="ui.aiAssistant">' + aiAssistantText + '</span> &nbsp;<span class="ai-assistant-provider">' + provider + '</span>').attr("data-model", selectedModel);
  }
  
  stop_apps_trigger = false;
  if (calledFor === "reset") {
    $("#file-div").hide();
    // $("#apps").val(defaultApp);
    $(`#apps option[value="${defaultApp}"]`).attr('selected', 'selected');
  } else if (calledFor === "loadParams") {
    let app_name = params["app_name"];
    const modelToSet = params["model"];
    
    // Check if app_name is valid
    if (!app_name) {
      // This is normal for initial load without a saved session
      // Just return without warning
      return;
    }
    
    // First, check if the exact app exists
    let targetApp = app_name;
    
    // Log all available apps for debugging
    
    if (!(app_name in apps)) {
      
      // Try to identify the provider from the model  
      if (modelToSet) {
        let providerGroup = null;
        
        // Identify provider based on model pattern
        if (/^(gpt-|o[13]|chatgpt-)/.test(modelToSet)) {
          providerGroup = "OpenAI";
        } else if (/^claude-/.test(modelToSet)) {
          providerGroup = "Anthropic";
        } else if (/^gemini-|^gemma-/.test(modelToSet)) {
          providerGroup = "Google";
        } else if (/^command-/.test(modelToSet)) {
          providerGroup = "Cohere";
        } else if (/^(mistral-|pixtral-|magistral-|ministral-)/.test(modelToSet)) {
          providerGroup = "Mistral";
        } else if (/^(sonar|llama-)/.test(modelToSet)) {
          providerGroup = "Perplexity";
        } else if (/^deepseek-/.test(modelToSet)) {
          providerGroup = "DeepSeek";
        } else if (/^grok-/.test(modelToSet)) {
          providerGroup = "xAI";
        }
        
        if (providerGroup) {
          
          // Also check if the imported data has a group field
          if (params["group"]) {
            // Use the group from the imported data if available
            providerGroup = params["group"];
          }
          
          // Try to find a matching app for this provider
          // Extract the base app type from the original app_name (e.g., "MailComposer" from "MailComposerGemini")
          let baseAppType = app_name.replace(/(?:OpenAI|Claude|Anthropic|Gemini|Google|Cohere|Mistral|Perplexity|DeepSeek|Grok|xAI|Ollama)$/i, '');
          
          // Find an app that matches this provider and base type
          for (const [key, value] of Object.entries(apps)) {
            if (value.group === providerGroup) {
              // Check if this app key contains the base app type
              if (key.toLowerCase().includes(baseAppType.toLowerCase()) || 
                  (value.display_name && value.display_name.toLowerCase().includes(baseAppType.toLowerCase().replace(/([A-Z])/g, ' $1').trim().toLowerCase()))) {
                targetApp = key;
                break;
              }
            }
          }
          
          // If we still couldn't find a match, try to find any app from this provider
          if (targetApp === app_name) {
            for (const [key, value] of Object.entries(apps)) {
              if (value.group === providerGroup) {
                // Default to the first app from this provider
                targetApp = key;
                break;
              }
            }
          }
        }
      }
    }
    
    // Set the app selector WITHOUT triggering change event yet
    $("#apps").val(targetApp);
    $(`#apps option[value="${targetApp}"]`).attr('selected', 'selected');
    
    // Check if apps object is available and app exists before triggering change
    if (typeof apps !== 'undefined' && apps && apps[targetApp]) {
      // Store the model in params before triggering app change
      // This will be preserved by proceedWithAppChange
      if (modelToSet) {
        params["model"] = modelToSet;
      }
      
      // Ensure stop_apps_trigger is false so the change event will be processed
      stop_apps_trigger = false;
      
      // Set a flag to indicate we're in the middle of loading params
      window.isLoadingParams = true;
      
      // Now trigger the change event after value is set
      $("#apps").trigger('change');
      
      // Clear the flag after a longer delay to ensure model setting completes
      setTimeout(() => {
        window.isLoadingParams = false;
      }, 500);
      
      // Wait a moment for app change to complete, then set model
      setTimeout(() => {
        if (modelToSet) {
          
          // Force set the model value even if the dropdown was rebuilt
          $("#model").val(modelToSet);
          
          if ($("#model").val() !== modelToSet) {
            // Try once more with a longer delay
            setTimeout(() => {
              $("#model").val(modelToSet);
              if ($("#model").val() === modelToSet) {
                $("#model").trigger('change');
              }
            }, 300);
          } else {
            $("#model").trigger('change');
          }
        }
      }, 300); // Increased timeout
    }
  } else if (calledFor === "changeApp") {
    let app_name = params["app_name"];
    $("#apps").val(app_name);
    $(`#apps option[value="${params['app_name']}"]`).attr('selected', 'selected');
    $("#model").val(params["model"]);
  }

  // Helper function to normalize boolean values (handles both boolean and string types)
  // Make it available globally for use in other functions
  if (!window.toBool) {
    window.toBool = (value) => {
      if (typeof value === 'boolean') return value;
      if (typeof value === 'string') return value === 'true';
      return !!value;
    };
  }
  const toBool = window.toBool;

  if (toBool(params["easy_submit"])) {
    $("#check-easy-submit").prop('checked', true);
  } else {
    $("#check-easy-submit").prop('checked', false);;
  }
  if (toBool(params["auto_speech"])) {
    $("#check-auto-speech").prop('checked', true);
  } else {
    $("#check-auto-speech").prop('checked', false);;
  }
  if (toBool(params["initiate_from_assistant"])) {
    $("#initiate-from-assistant").prop('checked', true);
  } else {
    $("#initiate-from-assistant").prop('checked', false);
  }
  if (toBool(params["mathjax"])) {
    $("#mathjax").prop('checked', true);
    $("#math-badge").show();
  } else {
    $("#mathjax").prop('checked', false);
    $("#math-badge").hide();
  }

  $("#initial-prompt").val(params["initial_prompt"]).trigger("input");
  if (window.logTL) window.logTL('initial_prompt_set', {
    calledFor,
    length: (params["initial_prompt"] || '').length
  });

  if (params["ai_user_initial_prompt"]) {
    $("#ai-user-initial-prompt-toggle").prop("checked", true).trigger("change");
    $("#ai-user-initial-prompt").val(params["ai_user_initial_prompt"]).trigger("input");
    $("#ai-user-toggle").prop("checked", true)
  } else {
    $("#ai-user-initial-prompt-toggle").prop("checked", false).trigger("change");
    $("#ai-user-toggle").prop("checked", false)
  }

  let model = params["model"];
  let spec = modelSpec[model];

  if (spec) {
    const reasoning_effort = params["reasoning_effort"];
    
    // Get provider from current app
    const currentApp = $("#apps").val();
    const provider = (window.getProviderFromGroup && window.apps && window.apps[currentApp]) 
      ? window.getProviderFromGroup(window.apps[currentApp]["group"])
      : "OpenAI";
    
    // Update UI with provider-specific components and labels
    if (window.reasoningUIManager) {
      window.reasoningUIManager.updateUI(provider, model);
    }
    
    // Use ReasoningMapper to check if provider/model supports reasoning
    if (window.ReasoningMapper && ReasoningMapper.isSupported(provider, model)) {
      // Get available options for this provider/model
      const availableOptions = ReasoningMapper.getAvailableOptions(provider, model);
      
      // Update dropdown options
      if (availableOptions) {
        const $dropdown = $("#reasoning-effort");
        $dropdown.empty(); // Clear existing options
        
        availableOptions.forEach(option => {
          const label = window.ReasoningLabels ? 
            window.ReasoningLabels.getOptionLabel(provider, option) : 
            option;
          $dropdown.append(`<option value="${option}">${label}</option>`);
        });
        
        // Set value with safety: coerce to first available if default not supported
        let effortValue;
        if (reasoning_effort && availableOptions.includes(reasoning_effort)) {
          effortValue = reasoning_effort;
        } else {
          let suggested = ReasoningMapper.getDefaultValue(provider, model);
          effortValue = (suggested && availableOptions.includes(suggested)) ? suggested : availableOptions[0];
        }
        $dropdown.val(effortValue);
        $dropdown.prop('disabled', false);
        $("#max-tokens-toggle").prop("checked", false).prop("disabled", true);
      } else {
        // Fallback if options couldn't be determined
        $("#reasoning-effort").prop('disabled', true);
        $("#reasoning-effort").val('');
        $("#max-tokens-toggle").prop("disabled", false).prop("checked", true);
        $("#max-tokens").prop("disabled", false);
      }
    } else {
      // Model/provider doesn't support reasoning/thinking
      $("#reasoning-effort").prop('disabled', true);
      $("#reasoning-effort").val('');  // Clear the value
      $("#max-tokens-toggle").prop("disabled", false).prop("checked", true);
      $("#max-tokens").prop("disabled", false);
    }
    
    // Update labels and description after options are set
    if (window.ReasoningLabels) {
      window.ReasoningLabels.updateUILabels(provider, model);
      
      // Update description text
      const description = window.ReasoningLabels.getDescription(provider, model);
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

    let temperature = params["temperature"];
    if (temperature) {
      if (!isNaN(temperature)) {
        temperature = parseFloat(temperature).toFixed(1);
      }
      $("#temperature").val(temperature);
      $("#temperature-value").text(temperature);
    } else {
      if (spec["temperature"]) {
        $("#temperature").val(spec["temperature"][1]);
        $("#temperature-value").text(parseFloat(spec["temperature"][1]).toFixed(1));
      } else {
        $("#temperature").prop('disabled', true);
      }
    }

    let presence_penalty = params["presence_penalty"];
    if (presence_penalty) {
      if (!isNaN(presence_penalty)) {
        presence_penalty = parseFloat(presence_penalty).toFixed(1);
      }
      $("#presence-penalty").val(presence_penalty);
      $("#presence-penalty-value").text(presence_penalty);
    } else {
      if (spec["presence_penalty"]) {
        $("#presence-penalty").val(spec["presence_penalty"][1]);
        $("#presence-penalty-value").text(parseFloat(spec["presence_penalty"][1]).toFixed(1));
      } else {
        $("#presence-penalty").prop('disabled', true);
      }
    }

    let frequency_penalty = params["frequency_penalty"];
    if (frequency_penalty) {
      if (!isNaN(frequency_penalty)) {
        frequency_penalty = parseFloat(frequency_penalty).toFixed(1);
      }
      $("#frequency-penalty").val(frequency_penalty);
      $("#frequency-penalty-value").text(frequency_penalty);
    } else {
      if (spec["frequency_penalty"]) {
        $("#frequency-penalty").val(spec["frequency_penalty"][1]);
        $("#frequency-penalty-value").text(parseFloat(spec["frequency_penalty"][1]).toFixed(1));
      } else {
        $("#frequency-penalty").prop('disabled', true);
      }
    }

    let max_tokens = params["max_tokens"];
    if (max_tokens) {
      $("#max-tokens-toggle").prop("checked", true).trigger("change");
      if (!isNaN(max_tokens)) {
        $("#max-tokens").val(parseInt(max_tokens));
      } else {
        $("#max-tokens").val(max_tokens);
      } 
    } else {
      if (spec["max_output_tokens"]) {
        $("#max-tokens").val(spec["max_output_tokens"][1]);
        $("#max-tokens-toggle").prop("checked", true).trigger("change");
      } else {
        $("#max-tokens").val(DEFAULT_MAX_OUTPUT_TOKENS);
        $("#max-tokens-toggle").prop("checked", false).trigger("change");
      }
    }
  } else {
    $("#reasoning-effort").prop('disabled', true);
    $("#temperature").prop('disabled', true);
    $("#presence-penalty").prop('disabled', true);
    $("#frequency-penalty").prop('disabled', true);
    $("#max-tokens").val(DEFAULT_MAX_OUTPUT_TOKENS);
    $("#max-tokens-toggle").prop("checked", false).trigger("change");
  }

  // (reverted) removed OpenAI PDF manager refresh hook after model updates

  // Set context size from configuration or use default
  $("#context-size").val(params["context_size"] || DEFAULT_CONTEXT_SIZE);

  // Reset the flag after loading is complete
  window.isLoadingParams = false;
  if (window.logTL) window.logTL('loadParams_exit', { calledFor });

  // Update toggle button text to reflect checkbox states
  if (typeof window.updateToggleButtonText === 'function') {
    window.updateToggleButtonText();
  }

  // (reverted) no deferred update here; proceedWithAppChange triggers model change as needed
}

function resetParams() {
  $("#pdf-titles").empty();
  // Use a local copy of originalParams to avoid reference issues
  const originalParamsCopy = originalParams ? JSON.parse(JSON.stringify(originalParams)) : {};
  params = Object.assign({}, originalParamsCopy);
  // Keep the app_name from being reset in loadParams
  const currentApp = $("#apps").val();
  loadParams(params, "reset");
  // wait for loadParams to finish
  setTimeout(function () {
    // Don't change app selection to default - it will be preserved from the current app
    // $("#apps select").val(params["app_name"]);

    const toBool = window.toBool || ((value) => {
      if (typeof value === 'boolean') return value;
      if (typeof value === 'string') return value === 'true';
      return !!value;
    });

    if (toBool(params["pdf"]) || toBool(params["pdf_vector_storage"])) {
      $("#pdf-panel").show();
    } else {
      $("#pdf-panel").hide();
    }
    // Reset the flag after loading is complete
    window.isLoadingParams = false;
  }, 500);
}

function setParams() {
  const app_name = $("#apps").val();
  params = Object.assign({}, apps[app_name]);
  params["app_name"] = app_name;

  // Always use checkbox value if it exists (user can change it)
  if ($("#initiate-from-assistant").length > 0) {
    params["initiate_from_assistant"] = $("#initiate-from-assistant").prop('checked') ? true : false;
  }
  // If checkbox doesn't exist, keep the value from apps[app_name]

  if ($("#mathjax").is(":checked")) {
    params["mathjax"] = true;
  } else {
    params["mathjax"] = false;
  }

  if ($("#websearch").is(":checked") && modelSpec[params["model"]]["tool_capability"]) {
    params["websearch"] = true;
  } else {
    params["websearch"] = false;
  }

  if ($("#prompt-caching").prop('checked') && !$("#prompt-caching").prop('disabled')) {
    params["prompt_caching"] = true;
  }

  // params["initial_prompt"] = $("#initial-prompt").val();
  params["model"] = $("#model").val();

  // Handle reasoning/thinking parameters with provider-specific mapping
  if (!$("#reasoning-effort").prop('disabled')) {
    const uiValue = $("#reasoning-effort").val();
    
    // Get provider from current app
    const currentApp = $("#apps").val();
    let provider = (window.getProviderFromGroup && window.apps && window.apps[currentApp]) 
      ? window.getProviderFromGroup(window.apps[currentApp]["group"]) : "OpenAI";
    const model = params["model"];
    // If model family suggests a different provider, prefer model-based inference
    try {
      const m = (model || '').toLowerCase();
      const looksGemini = m.includes('gemini');
      const looksClaude = m.includes('claude');
      const looksGrok = m.includes('grok');
      const looksDeepseek = m.includes('deepseek');
      const looksPerplexity = m.includes('pplx') || m.includes('perplexity') || m.includes('sonar');
      if (looksGemini) provider = 'Google';
      else if (looksClaude) provider = 'Anthropic';
      else if (looksGrok) provider = 'xAI';
      else if (looksDeepseek) provider = 'DeepSeek';
      else if (looksPerplexity) provider = 'Perplexity';
      // Otherwise keep provider as-is (OpenAI or app group-derived)
    } catch (_) {}
    
    if (window.ReasoningMapper) {
      // Map UI value to provider-specific parameter
      const mappedParams = ReasoningMapper.mapToProviderParameter(provider, model, uiValue);
      
      if (mappedParams) {
        // Add all mapped parameters to params object
        Object.keys(mappedParams).forEach(key => {
          params[key] = mappedParams[key];
        });
        
      } else {
        console.warn(`Failed to map reasoning effort '${uiValue}' for provider ${provider}, model ${model}`);
      }
    } else {
      // Fallback: use original reasoning_effort parameter
      params["reasoning_effort"] = uiValue;
    }
  }

  if (!$("#temperature").prop('disabled')) {
    params["temperature"] = $("#temperature").val();
  }

  if (!$("#presence-penalty").prop('disabled')) {
    params["presence_penalty"] = $("#presence-penalty").val();
  }

  if (!$("#frequency-penalty").prop('disabled')) {
    params["frequency_penalty"] = $("#frequency-penalty").val();
  }

  if ($("#max-tokens").prop('disabled')) {
    // just a midium-sized default value
    params["max_tokens"] = DEFAULT_MAX_OUTPUT_TOKENS;
  } else {
    params["max_tokens"] = $("#max-tokens").val();
  }

  if ($("#context-size").prop('disabled')) {
    // virtually unlimited context size
    params["context_size"] = DEFAULT_CONTEXT_SIZE;
  } else {
    params["context_size"] = $("#context-size").val();
  }

  params["tts_provider"] = $("#tts-provider").val();
  params["tts_voice"] = $("#tts-voice").val();
  params["elevenlabs_tts_voice"] = $("#elevenlabs-tts-voice").val();
  params["gemini_tts_voice"] = $("#gemini-tts-voice").val();
  params["tts_speed"] = $("#tts-speed").val();
  params["conversation_language"] = $("#conversation-language").val();
  // Update asr_lang for STT/TTS
  params["asr_lang"] = params["conversation_language"];
  params["easy_submit"] = $("#check-easy-submit").prop('checked');
  params["auto_speech"] = $("#check-auto-speech").prop('checked');

  // Auto TTS mode: realtime (true) or post-completion (false, default)
  // This will be set from Electron settings
  if (typeof window.AUTO_TTS_REALTIME_MODE !== 'undefined') {
    params["auto_tts_realtime_mode"] = window.AUTO_TTS_REALTIME_MODE;
  } else {
    // Default to false (post-completion mode)
    params["auto_tts_realtime_mode"] = false;
  }

  const spec = modelSpec[params["model"]];
  if (spec && spec["context_window"]) {
    params["max_input_tokens"] = spec["context_window"][1];
  } else {
    params["max_input_tokens"] = DEFAULT_MAX_INPUT_TOKENS;
  }

  if (spec && spec["tool_capability"]) {
    params["tool_capability"] = spec["tool_capability"];
  } else {
    params["tool_capability"] = null;
  }

  if (spec && spec["vision_capability"]) {
    params["vision_capability"] = spec["vision_capability"];
  } else {
    params["vision_capability"] = null;
  }

  return params;
}

function checkParams() {
  if (!$("#initial-prompt").val()) {
    alert("Please enter an initial prompt.");
    $("#initial-prompt").focus();
    return false;
  } else if (!$("#max-tokens").val()) {
    alert("Please enter a max output tokens value.");
    $("#max-tokens").focus();
    return false;
  } else if (!$("#context-size").val()) {
    alert("Please enter a context size.");
    $("#context-size").focus();
    return false;
  } else if (!$("#model").val()) {
    alert("Please select a model.");
    $("#model").focus();
    return false;
  } else if (!$("#reasoning-effort").prop('disabled') && !$("#reasoning-effort").val()) {
    alert("Please select a reasoning effort.");
    $("#reasoning-effort").focus();
    return false
  } else if (!$("#temperature").val()) {
    alert("Please enter a temperature.");
    $("#temperature").focus();
    return false;
  }
  return true;
}

// Check if a model supports PDF file uploads (SSOT-driven)
// If `supports_pdf_upload` is explicitly false, return false.
// If `supports_pdf_upload` is true, return true.
// Otherwise, fall back to `supports_pdf` (legacy behavior) to avoid regressions.
function isPdfSupportedForModel(selectedModel) {
  try {
    if (typeof modelSpec !== 'undefined' && modelSpec[selectedModel]) {
      const spec = modelSpec[selectedModel];
      if (spec.hasOwnProperty('supports_pdf_upload')) {
        return spec.supports_pdf_upload === true;
      }
      return !!spec["supports_pdf"];
    }
  } catch (e) {
    // fall through to conservative default
  }
  // Conservative fallback if spec not loaded: disable
  return false;
}

// Check if the current app supports image generation
function isImageGenerationApp(appName) {
  if (!appName) {
    appName = $("#apps").val();
  }
  const toBool = window.toBool || ((value) => {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') return value === 'true';
    return !!value;
  });
  return apps[appName] && toBool(apps[appName].image_generation);
}

// Check if the current app supports mask editing (distinct from basic image generation)
function isMaskEditingEnabled(appName) {
  if (!appName) {
    appName = $("#apps").val();
  }
  
  // Disable mask editor for Gemini Image Generator (uses semantic masking instead)
  if (appName && appName.includes("ImageGeneratorGemini")) {
  return false;
}

// Helper: show/hide OpenAI PDF manager and refresh list
// (reverted) removed OpenAI PDF manager utilities and handlers
  
  return apps[appName] && 
    (apps[appName].image_generation === true || 
     apps[appName].image_generation === "true") &&
    apps[appName].image_generation !== "upload_only";
}

function resetEvent(_event, resetToDefaultApp = false) {
  audioInit();

  $("#image-used").children().remove();
  images = [];

  // Detect iOS/iPadOS
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
               (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  
  // For iOS devices, bypass the modal and use standard confirm dialog
  if (isIOS) {
    if (confirm("Are you sure you want to reset the chat?")) {
      doResetActions(resetToDefaultApp);
    }
  } else {
    // For other platforms, use the Bootstrap modal
    $("#resetConfirmation").modal("show");
    $("#resetConfirmation").on("shown.bs.modal", function () {
      $("#resetConfirmed").focus();
    });
    $("#resetConfirmed").off("click").on("click", function (event) {
      event.preventDefault();
      doResetActions(resetToDefaultApp);
    });
  }
}

// Function to handle the actual reset logic
function doResetActions(resetToDefaultApp = false) {
  // Store the current app selection before reset
  const currentApp = resetToDefaultApp ? null : $("#apps").val();

  $("#message").css("height", "96px").val("");

  ws.send(JSON.stringify({ "message": "RESET" }));
  // Get UI language from cookie or default to 'en'
  const uiLanguage = document.cookie.match(/ui-language=([^;]+)/)?.[1] || 'en';
  ws.send(JSON.stringify({ "message": "LOAD", "ui_language": uiLanguage }));

  currentPdfData = null;
  
  // Delay resetParams to ensure LOAD response is processed first
  setTimeout(function() {
    resetParams();
    
    // If resetting to default app, find and select the first available app
    if (resetToDefaultApp) {
      // Find the first non-disabled option that is not a separator
      const firstApp = $("#apps option").filter(function() {
        return !$(this).prop('disabled') && !$(this).text().startsWith('──');
      }).first().val();
      
      if (firstApp) {
        $("#apps").val(firstApp).trigger('change');
      }
    }
    
    // After resetParams, trigger app change to reload models and initial prompt
    const currentAppVal = $("#apps").val();
    if (currentAppVal && typeof window.proceedWithAppChange === 'function') {
      // Call proceedWithAppChange to properly initialize the app
      window.proceedWithAppChange(currentAppVal);
    }
  }, 300);

  const model = $("#model").val();

  if (modelSpec[model] && ((modelSpec[model]["supports_web_search"] === true) || (modelSpec[model]["tool_capability"] === true))) {
    $("#websearch").prop("disabled", false).removeAttr('title')
    if ($("#websearch").is(":checked")) {
      $("#websearch-badge").show();
    } else {
      $("#websearch-badge").hide();
    }
  } else {
    const tt3 = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.webSearchModelDisabled') : 'Model does not support Web Search'
    $("#websearch").prop("disabled", true).attr('title', tt3)
    $("#websearch-badge").hide();
  }

  // Extract provider from app_name parameter
  // Use the final app value after potential reset
  const finalApp = resetToDefaultApp ? $("#apps").val() : currentApp;
  let provider = "OpenAI";
  if (apps[finalApp] && apps[finalApp].group) {
    const group = apps[finalApp].group.toLowerCase();
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

  if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
    $("#model-selected").text(provider + " (" + model + " - " + $("#reasoning-effort").val() + ")");
  } else {
    $("#model-selected").text(provider + " (" + model + ")");
  }

  $("#resetConfirmation").modal("hide");
  $("#main-panel").hide();
  $("#discourse").html("").hide();
  $("#chat").html("")
  $("#temp-card").hide();
  $("#temp-reasoning-card").remove();

  // Clear error cards and status message explicitly
  clearErrorCards();
  clearStatusMessage();

  $("#config").show();
  $("#back-to-settings").hide();
  $("#parameter-panel").hide();
  const resetSuccessText = getTranslation('ui.messages.resetSuccessful', 'Reset successful');
  setAlert(`<i class='fa-solid fa-circle-check'></i> ${resetSuccessText}.`, "success");
  
  // Set flags to indicate reset happened using centralized state management
  window.SessionState.setResetFlags();
  
  // Set app selection back to current app instead of default
  $("#apps").val(currentApp);
  
  // Update lastApp to match the current app to prevent app change dialog from appearing
  lastApp = currentApp;
  
  // Trigger app change to reset all settings to defaults
  $("#apps").trigger("change");
  
  $("#base-app-title").text(apps[currentApp]["display_name"] || apps[currentApp]["app_name"]);

  const toBool = window.toBool || ((value) => {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') return value === 'true';
    return !!value;
  });

  if (toBool(apps[currentApp]["monadic"])) {
    $("#monadic-badge").show();
  } else {
    $("#monadic-badge").hide();
  }

  if (apps[currentApp]["tools"]) {
    $("#tools-badge").show();
  } else {
    $("#tools-badge").hide();
  }

  if (toBool(apps[currentApp]["mathjax"])) {
    $("#math-badge").show();
  } else {
    $("#math-badge").hide();
  }

  $("#base-app-icon").html(apps[currentApp]["icon"]);

  // Helper function to get icon for tool group
  function getToolGroupIcon(groupName) {
    const icons = {
      'jupyter_operations': '📓',
      'python_execution': '🐍',
      'file_operations': '📁',
      'file_reading': '📄',
      'web_tools': '🌐',
      'app_creation': '🛠️'
    };
    return icons[groupName] || '📦';
  }

  // Display description with tool group badges
  let descriptionHtml = apps[currentApp]["description"];
  if (apps[currentApp]["imported_tool_groups"]) {
    try {
      // Parse JSON string to array
      const toolGroups = JSON.parse(apps[currentApp]["imported_tool_groups"]);
      console.log(`[Tool Groups] ${currentApp}:`, toolGroups);
      if (toolGroups && toolGroups.length > 0) {
        const badges = toolGroups.map(group => {
          const icon = getToolGroupIcon(group.name);
          const visibilityClass = group.visibility === 'always' ? 'badge-always' : 'badge-conditional';
          return `<span class="tool-group-badge ${visibilityClass}" title="${group.tool_count} tools (${group.visibility})">${icon} ${group.name}</span>`;
        }).join(' ');
        descriptionHtml += `<div class="tool-groups-display">${badges}</div>`;
        console.log(`[Tool Groups] Badges HTML added for ${currentApp}`);
      }
    } catch (e) {
      console.warn('Failed to parse imported_tool_groups:', e);
    }
  } else {
    console.log(`[Tool Groups] No imported_tool_groups for ${currentApp}`);
  }
  $("#base-app-desc").html(descriptionHtml);

  $("#model_and_file").show();
  $("#model_parameters").show();

  $("#image-file").show();

  $("#initial-prompt-toggle").prop("checked", false).trigger("change");
  $("#ai-user-initial-prompt-toggle").prop("checked", false).trigger("change");

  const noDataText = getTranslation('ui.noDataAvailable', 'No data available');
  setStats(noDataText);

  // Instead of selecting the first available app, maintain the current selection
  // Use stop_apps_trigger flag to prevent app change dialog
  stop_apps_trigger = true;
  $("#apps").trigger("change");

  // Use UI utilities module if available, otherwise fallback
  if (window.uiUtils && window.uiUtils.adjustImageUploadButton) {
    window.uiUtils.adjustImageUploadButton($("#model").val());
  } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
    window.shims.uiUtils.adjustImageUploadButton($("#model").val());
  }
  adjustScrollButtons();

  if (ws) {
    reconnect_websocket(ws);
  }
  window.scroll({ top: 0 });
  
  // Clear messages using SessionState
  window.SessionState.clearMessages();
}

let collapseStates = {};

function toggleItem(element) {
  const content = element.nextElementSibling;
  const chevron = element.querySelector('.fa-chevron-down, .fa-chevron-right');
  const toggleText = element.querySelector('.toggle-text');

  if (!content || !chevron) {
    console.error("Element not found");
    return;
  }

  const isOpening = content.style.display === 'none' || content.style.maxHeight === '0px';

  if (isOpening) {
    // Opening: measure actual height and animate
    content.style.display = 'block';
    content.style.overflow = 'hidden';
    content.style.maxHeight = 'none';
    const actualHeight = content.scrollHeight;
    content.style.maxHeight = '0';
    content.style.transition = 'max-height 0.3s ease-out, opacity 0.3s ease-out';
    content.style.opacity = '0';

    // Force reflow
    content.offsetHeight;

    // Animate to actual height
    content.style.maxHeight = actualHeight + 'px';
    content.style.opacity = '1';

    chevron.classList.replace('fa-chevron-right', 'fa-chevron-down');
    if (toggleText) {
      toggleText.textContent = toggleText.textContent.replace('Show', 'Hide');
    }

    // Remove inline max-height after animation completes
    setTimeout(() => {
      if (content.style.maxHeight !== '0px') {
        content.style.maxHeight = 'none';
        content.style.overflow = 'visible';
      }
    }, 300);
  } else {
    // Closing: set current height first, then animate to 0
    const currentHeight = content.scrollHeight;
    content.style.maxHeight = currentHeight + 'px';
    content.style.overflow = 'hidden';
    content.style.transition = 'max-height 0.3s ease-in, opacity 0.3s ease-in';

    // Force reflow
    content.offsetHeight;

    // Animate to 0
    content.style.maxHeight = '0';
    content.style.opacity = '0';

    chevron.classList.replace('fa-chevron-down', 'fa-chevron-right');
    if (toggleText) {
      toggleText.textContent = toggleText.textContent.replace('Hide', 'Show');
    }

    // Hide element after animation
    setTimeout(() => {
      if (content.style.maxHeight === '0px') {
        content.style.display = 'none';
      }
    }, 300);
  }
}

document.addEventListener('DOMContentLoaded', () => {
  updateItemStates();
});

function updateItemStates() {
  const items = document.querySelectorAll('.json-item');
  const contextStates = {};

  items.forEach(item => {
    const key = item.dataset.key;
    const depth = parseInt(item.dataset.depth);
    const content = item.querySelector('.json-content');
    const chevron = item.querySelector('.fa-chevron-down, .fa-chevron-right');

    if (!content || !chevron) return;

    let isCollapsed;
    const context = item.closest('.context');

    if (depth === 2 && context) {
      const contextKey = `context_${key}`;
      const contextIndex = Array.from(context.parentElement.children).indexOf(context);

      if (contextIndex > 0) {
        const prevContextState = contextStates[contextKey];
        if (prevContextState !== undefined) {
          isCollapsed = prevContextState;
        } else {
          isCollapsed = collapseStates[contextKey];
          if (isCollapsed === undefined) {
            isCollapsed = false;
          }
        }
      } else {
        isCollapsed = collapseStates[contextKey];
        if (isCollapsed === undefined) {
          isCollapsed = false;
        }
      }

      contextStates[contextKey] = isCollapsed;
    } else {
      isCollapsed = collapseStates[key];
      if (isCollapsed === undefined) {
        isCollapsed = false;
      }
    }

    collapseStates[key] = isCollapsed;

    if (isCollapsed) {
      content.style.display = 'none';
      chevron.classList.replace('fa-chevron-down', 'fa-chevron-right');
    } else {
      content.style.display = 'block';
      chevron.classList.replace('fa-chevron-right', 'fa-chevron-down');
    }
  });
}

function onNewElementAdded() {
  updateItemStates();
}

function applyCollapseStates() {
  updateItemStates();
}

// Export functions to window for browser environment
window.isPdfSupportedForModel = isPdfSupportedForModel;
window.isImageGenerationApp = isImageGenerationApp;
window.isMaskEditingEnabled = isMaskEditingEnabled;

// Function to update badges for an app
function updateAppBadges(selectedApp) {
  if (!selectedApp || !apps[selectedApp]) {
    console.warn(`[Badges] App ${selectedApp} not found`);
    return;
  }

  const currentDesc = apps[selectedApp]["description"] || "";

  // DEFENSIVE: Parse badge data with multiple fallback strategies
  let allBadges = { tools: [], capabilities: [] };

  const rawBadges = apps[selectedApp]["all_badges"];

  if (!rawBadges) {
    // Strategy 1: No badges defined - use empty structure
    console.debug(`[Badges] No badges defined for ${selectedApp}`);
  } else if (typeof rawBadges === 'object') {
    // Strategy 2: Already an object (backend sent JSON object, not string)
    allBadges = rawBadges;
  } else if (typeof rawBadges === 'string') {
    // Strategy 3: JSON string - attempt parse with fallback
    if (rawBadges.trim() === '') {
      console.debug(`[Badges] Empty badge string for ${selectedApp}`);
    } else {
      try {
        const parsed = JSON.parse(rawBadges);

        // Validate structure
        if (parsed && typeof parsed === 'object') {
          if (Array.isArray(parsed.tools) && Array.isArray(parsed.capabilities)) {
            allBadges = parsed;
          } else {
            console.error(`[Badges] Invalid badge structure for ${selectedApp}:`, parsed);
            // Attempt to recover partial data
            allBadges.tools = Array.isArray(parsed.tools) ? parsed.tools : [];
            allBadges.capabilities = Array.isArray(parsed.capabilities) ? parsed.capabilities : [];
          }
        }
      } catch (e) {
        console.error(`[Badges] Failed to parse badges for ${selectedApp}:`, e);
        console.debug('[Badges] Raw badge data:', rawBadges);
        // Continue with empty badges (don't crash UI)
      }
    }
  } else {
    console.error(`[Badges] Unexpected badge data type for ${selectedApp}:`, typeof rawBadges);
  }

  // Defensive: ensure arrays even if structure partially failed
  allBadges.tools = allBadges.tools || [];
  allBadges.capabilities = allBadges.capabilities || [];

  // Filter badges
  const visibleToolBadges = filterToolBadges(allBadges.tools);
  const visibleCapabilityBadges = filterCapabilityBadges(allBadges.capabilities);

  // Separate tools by visibility (always vs conditional)
  const alwaysTools = visibleToolBadges.filter(b => b.visibility === 'always');
  const conditionalTools = visibleToolBadges.filter(b => b.visibility === 'conditional');

  // Render badges
  let badgeHtml = '';

  // Always tools
  if (alwaysTools.length > 0) {
    badgeHtml += '<div class="badge-category">';
    badgeHtml += '<span class="badge-category-label">Tools (Always):</span>';
    badgeHtml += '<div class="badge-container">';
    badgeHtml += alwaysTools.map(renderBadge).join('');
    badgeHtml += '</div>';
    badgeHtml += '</div>';
  }

  // Conditional tools
  if (conditionalTools.length > 0) {
    badgeHtml += '<div class="badge-category">';
    badgeHtml += '<span class="badge-category-label">Tools (Conditional):</span>';
    badgeHtml += '<div class="badge-container">';
    badgeHtml += conditionalTools.map(renderBadge).join('');
    badgeHtml += '</div>';
    badgeHtml += '</div>';
  }

  if (visibleCapabilityBadges.length > 0) {
    badgeHtml += '<div class="badge-category">';
    badgeHtml += '<span class="badge-category-label">Capabilities:</span>';
    badgeHtml += '<div class="badge-container">';
    badgeHtml += visibleCapabilityBadges.map(renderBadge).join('');
    badgeHtml += '</div>';
    badgeHtml += '</div>';
  }

  // Update DOM
  if (badgeHtml) {
    $("#base-app-desc").html(currentDesc + `<div class="tool-groups-display">${badgeHtml}</div>`);
    console.log(`[Badges] Added ${visibleToolBadges.length} tools + ${visibleCapabilityBadges.length} capabilities for ${selectedApp}`);
  } else {
    $("#base-app-desc").html(currentDesc);
  }
}

// Filter tool badges by visibility
function filterToolBadges(toolBadges) {
  return toolBadges.filter(badge => {
    // Filter conditional tool groups by availability
    if (badge.visibility === 'conditional') {
      // Check if tool group is available (placeholder - implement actual check)
      return isToolGroupAvailable(badge.id);
    }
    return true;
  });
}

// Filter capability badges by user control
function filterCapabilityBadges(capabilityBadges) {
  // IMPORTANT: Badges show app CAPABILITIES, not current settings
  // All capability badges should be visible regardless of checkbox state
  // The checkbox controls whether the feature is ENABLED, not whether the badge shows
  return capabilityBadges;
}

// Render individual badge
function renderBadge(badge) {
  const colorClass = getBadgeColorClass(badge);
  const icon = `<i class="fas ${badge.icon}"></i>`;

  return `<span class="tool-group-badge ${colorClass}" title="${badge.description}">
    ${icon} ${badge.label}
  </span>`;
}

// Get badge color class based on type
function getBadgeColorClass(badge) {
  // Tools: Red系
  if (badge.type === 'tools') {
    return 'badge-tools';
  }

  // Capabilities: Blue系
  if (badge.type === 'capabilities') {
    return 'badge-capabilities';
  }

  return 'badge-default';
}

// Get checkbox ID for user-controlled features
function getUserControlCheckbox(featureId) {
  // Use convention: feature ID === checkbox ID
  const element = $(`#${featureId}`);
  if (element.length > 0) {
    return featureId;
  }

  // Fallback: legacy mapping
  const legacyMapping = {
    'mathjax': 'mathjax',
    'mermaid': 'mermaid',
    'websearch': 'websearch'
  };
  return legacyMapping[featureId];
}

// Check if conditional tool group is available
function isToolGroupAvailable(groupId) {
  // Check if conditional tool group is available
  // For now, return true (implement actual availability check later)
  return true;
}

// Add event handler for app selection to update all badges
$(document).ready(function() {
  // Handle app change events
  $("#apps").on("change", function() {
    const selectedApp = $(this).val();
    setTimeout(function() {
      updateAppBadges(selectedApp);
    }, 100); // Small delay to ensure DOM is ready
  });

  // Handle checkbox changes for user-controlled capabilities
  $("#mathjax, #mermaid, #websearch").on("change", function() {
    const selectedApp = $("#apps").val();
    if (selectedApp) {
      updateAppBadges(selectedApp);
    }
  });
});

// Global function to trigger badge update (can be called from websocket.js)
window.updateAppBadges = updateAppBadges;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    removeCode,
    removeMarkdown,
    removeEmojis,
    convertString,
    formatInfo,
    listModels,
    setAlert,
    setCookie,
    getCookie,
    updateAppSelectIcon,
    deleteMessage,
    applyCollapseStates,
    isPdfSupportedForModel,
    isImageGenerationApp,
    isMaskEditingEnabled
  };
}
