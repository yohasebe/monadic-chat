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
  if (!appValue) {
    const appsEl = document.getElementById("apps");
    if (appsEl && appsEl.value) {
      appValue = appsEl.value;
    }
  }

  // Try to obtain icon HTML from apps definition first
  let iconHtml = (appValue && apps && apps[appValue]) ? apps[appValue]["icon"] : null;

  // Fallback: derive icon from custom dropdown option if available
  if (!iconHtml) {
    const optEl = document.querySelector(`.custom-dropdown-option[data-value="${appValue}"] span:first-child`);
    if (optEl) {
      iconHtml = optEl.innerHTML;
    }
  }

  // Final fallback: use a generic chat icon
  if (!iconHtml) {
    iconHtml = '<i class="fas fa-comment"></i>';
  }

  // Update the icon in the static icon span
  const appSelectIcon = document.getElementById("app-select-icon");
  if (appSelectIcon) appSelectIcon.innerHTML = iconHtml;

  // Icon color is now controlled by CSS rule: #app-select-icon i { color: #777; }

  // Also update the active class in the custom dropdown if it exists
  const customDropdown = document.getElementById("custom-apps-dropdown");
  if (customDropdown) {
    document.querySelectorAll(".custom-dropdown-option").forEach(el => el.classList.remove("active"));
    const selectedOption = document.querySelector(`.custom-dropdown-option[data-value="${appValue}"]`);
    if (selectedOption) {
      selectedOption.classList.add("active");

      // Make sure the group containing the selected app is expanded
      const parentGroup = selectedOption.closest(".group-container");
      if (parentGroup) {
        // Remove collapsed class from the group
        parentGroup.classList.remove("collapsed");
        // Update the icon
        const groupId = parentGroup.getAttribute("id");
        const groupName = groupId.replace("group-", "");
        // Need to handle potential dashes in the group name for xAI Grok
        const groupHeader = document.querySelector(`.custom-dropdown-group[data-group="${groupName}"]`);
        if (groupHeader) {
          const toggleIcon = groupHeader.querySelector(".group-toggle-icon i");
          if (toggleIcon) {
            toggleIcon.classList.remove("fa-chevron-right");
            toggleIcon.classList.add("fa-chevron-down");
          }
        }
      }
    }
  }
}

// Update the "model-selected" badge text in the menu panel
// Uses current #model value, current app's provider group, and reasoning effort (if supported)
// (reverted) updateModelSelectedBadge helper was removed


  // setCookie, getCookie, setCookieValues → extracted to cookie-utils.js

function listModels(models, openai = false) {
  // Array of patterns to identify different model types
  // GPT-5: gpt-5, gpt-5.1, gpt-5.2, gpt-5-mini, gpt-5.2-pro, gpt-5.2-chat-latest, etc.
  const gpt5ModelPatterns = [/^gpt-5(?:\.\d)?(-(?:mini|nano|pro|chat-latest|codex(?:-mini|-max)?))?(?:-(?:latest|\d{4}-\d{2}-\d{2}))?$/];
  // GPT-4: gpt-4o, gpt-4o-mini, etc.
  const gpt4ModelPatterns = [/^(?:chatgpt-4o|gpt-4)/];

  // Separate models by type
  const gpt5Models = [];
  const gpt4Models = [];
  const otherModels = [];

  for (let model of models) {
    if (gpt5ModelPatterns.some(pattern => pattern.test(model))) {
      gpt5Models.push(model);
    } else if (gpt4ModelPatterns.some(pattern => pattern.test(model))) {
      gpt4Models.push(model);
    } else {
      otherModels.push(model);
    }
  }

  // Sort GPT-5 models: newer versions first (5.2 > 5.1 > 5)
  gpt5Models.sort((a, b) => {
    const getVersion = (model) => {
      const match = model.match(/^gpt-5(?:\.(\d))?/);
      return match ? (match[1] ? parseFloat(`5.${match[1]}`) : 5.0) : 0;
    };
    const versionDiff = getVersion(b) - getVersion(a);
    if (versionDiff !== 0) return versionDiff;
    return a.localeCompare(b);
  });

  // Sort GPT-4 models alphabetically
  gpt4Models.sort((a, b) => a.localeCompare(b));

  // Generate options based on the value of openai
  let modelOptions = [];

  if (openai) {
    // Include GPT-5 section at the top if GPT-5 models are available
    if (gpt5Models.length > 0) {
      modelOptions.push('<option disabled>──GPT-5──</option>');
      modelOptions.push(...gpt5Models.map(model =>
        `<option value="${model}" data-model-type="reasoning">${model}</option>`
      ));
    }

    // Include GPT-4 models
    if (gpt4Models.length > 0) {
      modelOptions.push('<option disabled>──GPT-4──</option>');
      modelOptions.push(...gpt4Models.map(model =>
        `<option value="${model}">${model}</option>`
      ));
    }

    // Include other models (o1, o3, codex, etc.)
    if (otherModels.length > 0) {
      modelOptions.push('<option disabled>──Other Models──</option>');
      modelOptions.push(...otherModels.map(model =>
        `<option value="${model}">${model}</option>`
      ));
    }
  } else {
    // Exclude dummy options when openai is false
    modelOptions = [
      ...gpt5Models.map(model =>
        `<option value="${model}">${model}</option>`
      ),
      ...gpt4Models.map(model =>
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
    const downloadLink = document.createElement('a');
    downloadLink.setAttribute('href', 'data:' + data);
    downloadLink.setAttribute('download', fileName);
    document.body.appendChild(downloadLink);
    downloadLink.click();
    downloadLink.remove();
  }

//////////////////////////////
  // set focus on the start button if it is visible
// if start button is not visible but voice button is,
  // set focus on the voice button only if easy_submit and auto_speech are both enabled
// otherwise set focus on the message input
//////////////////////////////

  function setInputFocus() {
    const startEl = document.getElementById("start");
    const easySubmitEl = document.getElementById("check-easy-submit");
    const autoSpeechEl = document.getElementById("check-auto-speech");
    if (startEl && startEl.offsetParent !== null) {
      startEl.focus();
    } else if (easySubmitEl && easySubmitEl.checked && autoSpeechEl && autoSpeechEl.checked) {
      const voiceEl = document.getElementById("voice");
      const voiceNoteEl = document.getElementById("voice-note");
      if (voiceEl) voiceEl.focus();
      // show #voice-note but set it to hide when the voice button is unfocused
      if (voiceNoteEl) voiceNoteEl.style.display = '';
      if (voiceEl) {
        voiceEl.addEventListener("blur", function () {
          if (voiceNoteEl) voiceNoteEl.style.display = 'none';
        });
        voiceEl.addEventListener("focusout", function () {
          if (voiceNoteEl) voiceNoteEl.style.display = 'none';
        });
      }
    } else {
      const messageEl = document.getElementById("message");
      if (messageEl) messageEl.focus();
    }
  }

//////////////////////////////
  // format a message to show in the chat
//////////////////////////////

  // removeCode, removeMarkdown, removeEmojis → extracted to text-utils.js

  // setAlertClass → extracted to alert-manager.js

  // setAlert, setStats, clearStatusMessage, clearErrorCards, deleteMessage → extracted to alert-manager.js

//////////////////////////////
  // convert a string to show in the parameter panel
// e.g. "initial_prompt" -> "Initial Prompt"
//////////////////////////////

  // convertString → extracted to text-utils.js

//////////////////////////////
  // Functions to load/reset/set parameters
//////////////////////////////

  let stop_apps_trigger = false;

function setBaseAppDescription(html) {
  const descEl = document.getElementById("base-app-desc");
  if (!descEl) return;
  const normalized = (html == null ? '' : String(html));
  const previous = descEl.dataset.renderedHtml;
  if (previous === normalized) {
    return;
  }
  descEl.dataset.renderedHtml = normalized;
  descEl.innerHTML = normalized;
}

window.setBaseAppDescription = setBaseAppDescription;

window.loadParams = function(params, calledFor = "loadParams") {
  const modelNonDefault = document.getElementById("model-non-default");
  if (modelNonDefault) modelNonDefault.style.display = 'none';
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
    const aiAssistantInfo = document.getElementById("ai-assistant-info");
    if (aiAssistantInfo) {
      aiAssistantInfo.innerHTML = '<span data-i18n="ui.aiAssistant">' + aiAssistantText + '</span> &nbsp;<span class="ai-assistant-provider">' + provider + '</span>';
      aiAssistantInfo.setAttribute("data-model", selectedModel);
    }
  }
  
  stop_apps_trigger = false;
  if (calledFor === "reset") {
    const fileDiv = document.getElementById("file-div");
    if (fileDiv) fileDiv.style.display = 'none';
    // Select the default app option
    const defaultOption = document.querySelector(`#apps option[value="${defaultApp}"]`);
    if (defaultOption) defaultOption.setAttribute('selected', 'selected');
  } else if (calledFor === "loadParams") {
    let app_name = params["app_name"];
    let modelToSet = params["model"];
    
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
    const appsSelect = document.getElementById("apps");
    const previousAppSelection = appsSelect ? appsSelect.value : null;
    const needsAppChange = previousAppSelection !== targetApp;
    if (appsSelect) appsSelect.value = targetApp;
    const targetOption = document.querySelector(`#apps option[value="${targetApp}"]`);
    if (targetOption) targetOption.setAttribute('selected', 'selected');

    // Helper to ensure a model option exists when we skip app change triggers
    const ensureModelOptionVisible = (modelValue) => {
      if (!modelValue || !apps || !apps[targetApp]) return;
      const modelSelect = document.getElementById("model");
      if (!modelSelect) return;
      if (modelSelect.querySelector(`option[value="${modelValue}"]`)) {
        return;
      }
      try {
        const showAllModelsEl = document.getElementById("show-all-models");
        const showAllModels = showAllModelsEl ? showAllModelsEl.checked : false;
        const modelsForApp = typeof getModelsForApp === 'function' ? getModelsForApp(apps[targetApp], showAllModels) : [];
        if (modelsForApp.length === 0) return;
        const isOpenAIGroup = (apps[targetApp]["group"] || "").toLowerCase() === "openai";
        const markup = typeof listModels === 'function' ? listModels(modelsForApp, isOpenAIGroup) : "";
        if (markup) {
          modelSelect.innerHTML = markup;
        }
      } catch (error) {
        console.error('Failed to rebuild model list while loading params:', error);
      }
    };
    
    // Check if apps object is available and app exists before triggering change
    if (typeof apps !== 'undefined' && apps && apps[targetApp]) {
      // Auto-migrate deprecated models to their successor
      if (modelToSet && typeof isModelDeprecated === 'function' && isModelDeprecated(modelToSet)) {
        const successor = typeof getModelSuccessor === 'function' ? getModelSuccessor(modelToSet) : null;
        if (successor) {
          const deprecatedModel = modelToSet;
          console.warn(`[Session] Model "${deprecatedModel}" is deprecated, migrating to successor "${successor}"`);
          modelToSet = successor;
          setTimeout(() => {
            if (typeof setAlert === 'function') {
              setAlert(`<i class="fas fa-exchange-alt"></i> Model "${deprecatedModel}" has been replaced with "${successor}" (deprecated model).`, "warning");
            }
          }, 1000);
        } else {
          console.warn(`[Session] Model "${modelToSet}" is deprecated but no successor defined`);
        }
      }

      // Store the model in params before triggering app change
      if (modelToSet) {
        params["model"] = modelToSet;
      }
      
      // Ensure stop_apps_trigger is false so the change event will be processed
      stop_apps_trigger = false;
      
      if (needsAppChange) {
        // Set a flag to indicate we're in the middle of loading params
        window.isLoadingParams = true;

        // Now trigger the change event after value is set
        if (appsSelect) appsSelect.dispatchEvent(new Event('change'));

        // Clear the flag after a longer delay to ensure model setting completes
        setTimeout(() => {
          window.isLoadingParams = false;
        }, 500);

        // Wait a moment for app change to complete, then set model
        setTimeout(() => {
          if (modelToSet) {
            const modelSelect = document.getElementById("model");
            if (!modelSelect) return;

            // Force set the model value even if the dropdown was rebuilt
            modelSelect.value = modelToSet;

            if (modelSelect.value !== modelToSet) {
              // Try once more with a longer delay
              setTimeout(() => {
                modelSelect.value = modelToSet;
                if (modelSelect.value === modelToSet) {
                  modelSelect.dispatchEvent(new Event('change'));
                }
              }, 300);
            } else {
              modelSelect.dispatchEvent(new Event('change'));
            }
          }
        }, 300); // Increased timeout
      } else if (modelToSet) {
        // Same app: ensure the requested model is present without retriggering app change
        ensureModelOptionVisible(modelToSet);
        const modelSelect = document.getElementById("model");
        if (modelSelect) {
          if (modelSelect.value !== modelToSet) {
            modelSelect.value = modelToSet;
          }
          if (modelSelect.value === modelToSet) {
            modelSelect.dispatchEvent(new Event('change'));
          } else {
            console.warn(`Model ${modelToSet} could not be selected for app ${targetApp}`);
            // Fallback to first available model to avoid stale/invalid state
            const firstOption = modelSelect.querySelector("option");
            const fallbackModel = firstOption ? firstOption.value : null;
            if (fallbackModel) {
              modelSelect.value = fallbackModel;
              modelSelect.dispatchEvent(new Event('change'));
              params["model"] = fallbackModel;
              // Clear stale reasoning_effort when model fallback happens
              if (params["reasoning_effort"]) {
                delete params["reasoning_effort"];
              }
            }
          }
        }
      }

      // IMPORTANT: Always update app icon/display even when needsAppChange is false
      // This ensures UI consistency when importing into tabs with the same app already selected
      if (typeof updateAppSelectIcon === 'function') {
        updateAppSelectIcon(targetApp);
      }

      // Verify that the select element actually shows the correct app
      // Sometimes browser rendering doesn't update immediately after value is set
      const currentAppVal = appsSelect ? appsSelect.value : null;
      if (currentAppVal !== targetApp) {
        console.warn(`[loadParams] #apps value mismatch: expected ${targetApp}, got ${currentAppVal}. Re-setting...`);
        // Re-set the value to force browser to update display
        if (appsSelect) appsSelect.value = targetApp;
        // Verify again
        if (appsSelect && appsSelect.value !== targetApp) {
          console.error(`[loadParams] Failed to set #apps to ${targetApp}. Option may not exist.`);
        }
      }

      // Also ensure model display is updated even if change event wasn't triggered
      if (modelToSet && apps[targetApp]) {
        const provider = (typeof getProviderFromGroup === 'function' && apps[targetApp]["group"])
          ? getProviderFromGroup(apps[targetApp]["group"])
          : "OpenAI";
        const modelEl = document.getElementById("model");
        const reasoningEffortEl = document.getElementById("reasoning-effort");
        const selectedModel = modelEl ? modelEl.value : null;
        const reasoning_effort = params["reasoning_effort"] || (reasoningEffortEl ? reasoningEffortEl.value : null);

        // Update model display badge
        const modelSelectedEl = document.getElementById("model-selected");
        if (modelSelectedEl) {
          if (modelSpec[selectedModel] && modelSpec[selectedModel].hasOwnProperty("reasoning_effort") && reasoning_effort) {
            modelSelectedEl.textContent = `${provider} (${selectedModel} - ${reasoning_effort})`;
          } else {
            modelSelectedEl.textContent = `${provider} (${selectedModel})`;
          }
        }
      }
    }
  } else if (calledFor === "changeApp") {
    let app_name = params["app_name"];
    const appsEl = document.getElementById("apps");
    if (appsEl) appsEl.value = app_name;
    const appOption = document.querySelector(`#apps option[value="${params['app_name']}"]`);
    if (appOption) appOption.setAttribute('selected', 'selected');
    // Model selection is handled by proceedWithAppChange after model list rebuild.
    // Setting it here is either redundant (sync) or harmful (deferred by ensureLoadParams).
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

  const easySubmitCb = document.getElementById("check-easy-submit");
  if (easySubmitCb) easySubmitCb.checked = toBool(params["easy_submit"]);

  // Force Auto TTS OFF during import (regardless of app settings)
  const autoSpeechCb = document.getElementById("check-auto-speech");
  if (autoSpeechCb) {
    if (window.isProcessingImport) {
      autoSpeechCb.checked = false;
    } else {
      autoSpeechCb.checked = toBool(params["auto_speech"]);
    }
  }

  // Force initiate_from_assistant OFF during import (regardless of app settings)
  const initiateFromAssistantCb = document.getElementById("initiate-from-assistant");
  if (initiateFromAssistantCb) {
    if (window.isProcessingImport) {
      initiateFromAssistantCb.checked = false;
    } else {
      initiateFromAssistantCb.checked = toBool(params["initiate_from_assistant"]);
    }
  }
  const mathjaxCb = document.getElementById("mathjax");
  const mathBadge = document.getElementById("math-badge");
  if (mathjaxCb) mathjaxCb.checked = toBool(params["mathjax"]);
  if (mathBadge) mathBadge.style.display = toBool(params["mathjax"]) ? '' : 'none';

  const initialPromptEl = document.getElementById("initial-prompt");
  if (initialPromptEl) {
    initialPromptEl.value = params["initial_prompt"] || '';
    initialPromptEl.dispatchEvent(new Event("input", {bubbles: true}));
  }
  if (window.logTL) window.logTL('initial_prompt_set', {
    calledFor,
    length: (params["initial_prompt"] || '').length
  });

  if (params["ai_user_initial_prompt"]) {
    const aiUserPromptEl = document.getElementById("ai-user-initial-prompt");
    if (aiUserPromptEl) {
      aiUserPromptEl.value = params["ai_user_initial_prompt"];
      aiUserPromptEl.dispatchEvent(new Event("input", {bubbles: true}));
    }
    if (typeof window.setPromptView === 'function') window.setPromptView('aiuser', false);
  } else {
    if (typeof window.setPromptView === 'function') window.setPromptView('hidden', false);
  }

  let model = params["model"];
  let spec = modelSpec[model];

  if (spec) {
    const reasoning_effort = params["reasoning_effort"];
    
    // Get provider from current app
    const currentAppEl = document.getElementById("apps");
    const currentApp = currentAppEl ? currentAppEl.value : null;
    const provider = (window.getProviderFromGroup && window.apps && window.apps[currentApp])
      ? window.getProviderFromGroup(window.apps[currentApp]["group"])
      : "OpenAI";

    // Update UI with provider-specific components and labels
    if (window.reasoningUIManager) {
      window.reasoningUIManager.updateUI(provider, model);
    }

    const reasoningDropdown = document.getElementById("reasoning-effort");
    const maxTokensEl = document.getElementById("max-tokens");
    const maxTokensToggle = document.getElementById("max-tokens-toggle");

    // Use ReasoningMapper to check if provider/model supports reasoning
    if (window.ReasoningMapper && ReasoningMapper.isSupported(provider, model)) {
      // Get current UI settings for feature constraint checking
      const websearchCb = document.getElementById("websearch");
      const currentSettings = {
        web_search: (websearchCb && websearchCb.checked) || false
      };

      // Get available options for this provider/model
      const availableOptions = ReasoningMapper.getAvailableOptions(provider, model, currentSettings);

      // Update dropdown options
      if (availableOptions) {
        if (reasoningDropdown) {
          reasoningDropdown.innerHTML = ''; // Clear existing options

          availableOptions.forEach(option => {
            const label = window.ReasoningLabels ?
              window.ReasoningLabels.getOptionLabel(provider, option) :
              option;
            reasoningDropdown.insertAdjacentHTML('beforeend', `<option value="${option}">${label}</option>`);
          });

          // Set value with safety: coerce to first available if default not supported
          let effortValue;
          if (reasoning_effort && availableOptions.includes(reasoning_effort)) {
            effortValue = reasoning_effort;
          } else {
            let suggested = ReasoningMapper.getDefaultValue(provider, model);
            effortValue = (suggested && availableOptions.includes(suggested)) ? suggested : availableOptions[0];
          }
          reasoningDropdown.value = effortValue;
          reasoningDropdown.disabled = false;
        }
        // For reasoning models, use model's max output tokens and lock the field
        if (spec["max_output_tokens"] && maxTokensEl) {
          maxTokensEl.value = spec["max_output_tokens"][1];
        }
        if (maxTokensToggle) { maxTokensToggle.checked = true; maxTokensToggle.disabled = true; }
        if (maxTokensEl) maxTokensEl.disabled = true;
      } else {
        // Fallback if options couldn't be determined
        if (reasoningDropdown) { reasoningDropdown.disabled = true; reasoningDropdown.value = ''; }
        if (maxTokensToggle) { maxTokensToggle.disabled = false; maxTokensToggle.checked = true; }
        if (maxTokensEl) maxTokensEl.disabled = false;
      }
    } else {
      // Model/provider doesn't support reasoning/thinking
      if (reasoningDropdown) { reasoningDropdown.disabled = true; reasoningDropdown.value = ''; }
      if (maxTokensToggle) { maxTokensToggle.disabled = false; maxTokensToggle.checked = true; }
      if (maxTokensEl) maxTokensEl.disabled = false;
    }

    // Update labels after options are set
    if (window.ReasoningLabels) {
      window.ReasoningLabels.updateUILabels(provider, model);
    }

    // Show/hide thinking display toggle based on model support
    // Only show for models with supports_thinking (Claude, Gemini, DeepSeek)
    // NOT for OpenAI reasoning_effort models (no display control API)
    const thinkingContainer = document.getElementById("thinking-display-container");
    const showThinkingCb = document.getElementById("show-thinking");
    if (spec["supports_thinking"]) {
      if (thinkingContainer) thinkingContainer.style.display = '';
      // Restore from params if available, default to checked (show thinking)
      if (showThinkingCb) {
        if (params["show_thinking"] !== undefined) {
          showThinkingCb.checked = params["show_thinking"] !== false && params["show_thinking"] !== "false";
        } else {
          showThinkingCb.checked = true;
        }
      }
    } else {
      if (thinkingContainer) thinkingContainer.style.display = 'none';
    }

    // Hide model_parameters row (temperature, penalties) — these legacy controls
    // are not useful for modern models and are hidden from the default UI.
    const modelParamsEl = document.getElementById("model_parameters");
    if (modelParamsEl) modelParamsEl.style.display = 'none';

    const temperatureEl = document.getElementById("temperature");
    const temperatureValueEl = document.getElementById("temperature-value");
    let temperature = params["temperature"];
    if (temperature) {
      if (!isNaN(temperature)) {
        temperature = parseFloat(temperature).toFixed(1);
      }
      if (temperatureEl) temperatureEl.value = temperature;
      if (temperatureValueEl) temperatureValueEl.textContent = temperature;
    } else {
      if (spec["temperature"]) {
        if (temperatureEl) temperatureEl.value = spec["temperature"][1];
        if (temperatureValueEl) temperatureValueEl.textContent = parseFloat(spec["temperature"][1]).toFixed(1);
      } else {
        if (temperatureEl) temperatureEl.disabled = true;
      }
    }

    const presencePenaltyEl = document.getElementById("presence-penalty");
    const presencePenaltyValueEl = document.getElementById("presence-penalty-value");
    let presence_penalty = params["presence_penalty"];
    if (presence_penalty) {
      if (!isNaN(presence_penalty)) {
        presence_penalty = parseFloat(presence_penalty).toFixed(1);
      }
      if (presencePenaltyEl) presencePenaltyEl.value = presence_penalty;
      if (presencePenaltyValueEl) presencePenaltyValueEl.textContent = presence_penalty;
    } else {
      if (spec["presence_penalty"]) {
        if (presencePenaltyEl) presencePenaltyEl.value = spec["presence_penalty"][1];
        if (presencePenaltyValueEl) presencePenaltyValueEl.textContent = parseFloat(spec["presence_penalty"][1]).toFixed(1);
      } else {
        if (presencePenaltyEl) presencePenaltyEl.disabled = true;
      }
    }

    const frequencyPenaltyEl = document.getElementById("frequency-penalty");
    const frequencyPenaltyValueEl = document.getElementById("frequency-penalty-value");
    let frequency_penalty = params["frequency_penalty"];
    if (frequency_penalty) {
      if (!isNaN(frequency_penalty)) {
        frequency_penalty = parseFloat(frequency_penalty).toFixed(1);
      }
      if (frequencyPenaltyEl) frequencyPenaltyEl.value = frequency_penalty;
      if (frequencyPenaltyValueEl) frequencyPenaltyValueEl.textContent = frequency_penalty;
    } else {
      if (spec["frequency_penalty"]) {
        if (frequencyPenaltyEl) frequencyPenaltyEl.value = spec["frequency_penalty"][1];
        if (frequencyPenaltyValueEl) frequencyPenaltyValueEl.textContent = parseFloat(spec["frequency_penalty"][1]).toFixed(1);
      } else {
        if (frequencyPenaltyEl) frequencyPenaltyEl.disabled = true;
      }
    }

    // Skip max_tokens UI setup if already locked by reasoning model logic above
    if (maxTokensToggle && !maxTokensToggle.disabled) {
      let max_tokens = params["max_tokens"];
      if (max_tokens) {
        if (maxTokensToggle) { maxTokensToggle.checked = true; maxTokensToggle.dispatchEvent(new Event("change", {bubbles: true})); }
        if (maxTokensEl) maxTokensEl.value = !isNaN(max_tokens) ? parseInt(max_tokens) : max_tokens;
      } else {
        if (spec["max_output_tokens"]) {
          if (maxTokensEl) maxTokensEl.value = spec["max_output_tokens"][1];
          if (maxTokensToggle) { maxTokensToggle.checked = true; maxTokensToggle.dispatchEvent(new Event("change", {bubbles: true})); }
        } else {
          if (maxTokensEl) maxTokensEl.value = DEFAULT_MAX_OUTPUT_TOKENS;
          if (maxTokensToggle) { maxTokensToggle.checked = false; maxTokensToggle.dispatchEvent(new Event("change", {bubbles: true})); }
        }
      }
    }
  } else {
    const reasoningDropdownFb = document.getElementById("reasoning-effort");
    const temperatureElFb = document.getElementById("temperature");
    const presencePenaltyElFb = document.getElementById("presence-penalty");
    const frequencyPenaltyElFb = document.getElementById("frequency-penalty");
    const modelParamsElFb = document.getElementById("model_parameters");
    const maxTokensElFb = document.getElementById("max-tokens");
    const maxTokensToggleFb = document.getElementById("max-tokens-toggle");
    if (reasoningDropdownFb) reasoningDropdownFb.disabled = true;
    if (temperatureElFb) temperatureElFb.disabled = true;
    if (presencePenaltyElFb) presencePenaltyElFb.disabled = true;
    if (frequencyPenaltyElFb) frequencyPenaltyElFb.disabled = true;
    if (modelParamsElFb) modelParamsElFb.style.display = 'none';
    if (maxTokensElFb) maxTokensElFb.value = DEFAULT_MAX_OUTPUT_TOKENS;
    if (maxTokensToggleFb) { maxTokensToggleFb.checked = false; maxTokensToggleFb.dispatchEvent(new Event("change", {bubbles: true})); }
  }

  // (reverted) removed OpenAI PDF manager refresh hook after model updates

  // Set context size from configuration or use default
  const contextSizeEl = document.getElementById("context-size");
  if (contextSizeEl) contextSizeEl.value = params["context_size"] || DEFAULT_CONTEXT_SIZE;

  // Ensure model row is always visible (guard against external hide calls)
  const modelAndFile = document.getElementById("model_and_file");
  if (modelAndFile) { modelAndFile.style.display = ''; modelAndFile.classList.remove("hidden"); }

  // Deferred guard: rebuild reasoning dropdown if empty after model change handler
  // Max_tokens lock and Show Thinking toggle are handled in monadic.js model change handler
  if (spec) {
    const guardSpec = spec;
    const guardModel = model;
    const hasReasoning = !!(guardSpec["reasoning_effort"] || guardSpec["supports_thinking"]);
    const guardDropdown = document.getElementById("reasoning-effort");
    if (hasReasoning && guardDropdown && guardDropdown.querySelectorAll("option").length === 0) {
      const guardAppsEl = document.getElementById("apps");
      const guardCurrentApp = guardAppsEl ? guardAppsEl.value : null;
      const guardProvider = (window.getProviderFromGroup && window.apps && window.apps[guardCurrentApp])
        ? window.getProviderFromGroup(window.apps[guardCurrentApp]["group"])
        : "OpenAI";
      if (window.ReasoningMapper) {
        const opts = ReasoningMapper.getAvailableOptions(guardProvider, guardModel, {});
        if (opts && opts.length > 0) {
          guardDropdown.innerHTML = '';
          opts.forEach(opt => {
            const label = window.ReasoningLabels ?
              window.ReasoningLabels.getOptionLabel(guardProvider, opt) : opt;
            guardDropdown.insertAdjacentHTML('beforeend', `<option value="${opt}">${label}</option>`);
          });
          const defaultVal = ReasoningMapper.getDefaultValue(guardProvider, guardModel);
          guardDropdown.value = (defaultVal && opts.includes(defaultVal)) ? defaultVal : opts[0];
          guardDropdown.disabled = false;
        }
      }
    }
  }

  // Reset the flag after loading is complete
  window.isLoadingParams = false;
  if (window.logTL) window.logTL('loadParams_exit', { calledFor });

  // Update toggle button text to reflect checkbox states
  if (typeof window.updateToggleButtonText === 'function') {
    window.updateToggleButtonText();
  }

  // Final enforcement of import-mode checkbox states
  if (window.isProcessingImport) {
    const autoSpeechFinal = document.getElementById("check-auto-speech");
    const initiateFinal = document.getElementById("initiate-from-assistant");
    if (autoSpeechFinal) autoSpeechFinal.checked = false;
    if (initiateFinal) initiateFinal.checked = false;
  }

  // (reverted) no deferred update here; proceedWithAppChange triggers model change as needed
}

function resetParams() {
  const pdfTitles = document.getElementById("pdf-titles");
  if (pdfTitles) pdfTitles.innerHTML = '';
  // Use a local copy of originalParams to avoid reference issues
  const originalParamsCopy = originalParams ? JSON.parse(JSON.stringify(originalParams)) : {};
  params = Object.assign({}, originalParamsCopy);
  // Keep the app_name from being reset in loadParams
  const currentAppEl = document.getElementById("apps");
  const currentApp = currentAppEl ? currentAppEl.value : null;
  loadParams(params, "reset");
  // wait for loadParams to finish
  setTimeout(function () {
    const toBool = window.toBool || ((value) => {
      if (typeof value === 'boolean') return value;
      if (typeof value === 'string') return value === 'true';
      return !!value;
    });

    const pdfPanel = document.getElementById("pdf-panel");
    if (pdfPanel) pdfPanel.style.display = (toBool(params["pdf"]) || toBool(params["pdf_vector_storage"])) ? '' : 'none';
    const audioUpload = document.getElementById("audio-upload");
    if (audioUpload) audioUpload.style.display = toBool(params["audio_upload"]) ? '' : 'none';
    // Reset the flag after loading is complete
    window.isLoadingParams = false;
  }, 500);
}

function setParams() {
  const appsEl = document.getElementById("apps");
  const app_name = appsEl ? appsEl.value : null;
  params = Object.assign({}, apps[app_name]);
  params["app_name"] = app_name;

  // Always use checkbox value if it exists (user can change it)
  const initiateFromAssistantEl = document.getElementById("initiate-from-assistant");
  if (initiateFromAssistantEl) {
    params["initiate_from_assistant"] = initiateFromAssistantEl.checked ? true : false;
  }
  // If checkbox doesn't exist, keep the value from apps[app_name]
  if (typeof window !== 'undefined' && window.skipAssistantInitiation) {
    params["initiate_from_assistant"] = false;
  }

  const mathjaxEl = document.getElementById("mathjax");
  params["mathjax"] = mathjaxEl ? mathjaxEl.checked : false;

  const websearchEl = document.getElementById("websearch");
  const modelEl = document.getElementById("model");
  params["model"] = modelEl ? modelEl.value : null;
  if (websearchEl && websearchEl.checked && modelSpec[params["model"]]?.["tool_capability"]) {
    params["websearch"] = true;
  } else {
    params["websearch"] = false;
  }

  // Handle reasoning/thinking parameters with provider-specific mapping
  const reasoningEffortEl = document.getElementById("reasoning-effort");
  if (reasoningEffortEl && !reasoningEffortEl.disabled) {
    const uiValue = reasoningEffortEl.value;

    // Get provider from current app
    const currentApp = appsEl ? appsEl.value : null;
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
    } catch (_) { console.warn("[ReasoningProvider] Provider detection failed:", _); }
    
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

  const spTemperature = document.getElementById("temperature");
  if (spTemperature && !spTemperature.disabled) {
    params["temperature"] = spTemperature.value;
  }

  const spPresencePenalty = document.getElementById("presence-penalty");
  if (spPresencePenalty && !spPresencePenalty.disabled) {
    params["presence_penalty"] = spPresencePenalty.value;
  }

  const spFrequencyPenalty = document.getElementById("frequency-penalty");
  if (spFrequencyPenalty && !spFrequencyPenalty.disabled) {
    params["frequency_penalty"] = spFrequencyPenalty.value;
  }

  // For reasoning/thinking models, always use the model's max output tokens
  const currentModelSpec = window.modelSpec ? window.modelSpec[params["model"]] : null;
  const isReasoningModel = currentModelSpec && (currentModelSpec["reasoning_effort"] || currentModelSpec["supports_thinking"]);
  const spMaxTokensToggle = document.getElementById("max-tokens-toggle");
  const spMaxTokens = document.getElementById("max-tokens");
  if (isReasoningModel && currentModelSpec["max_output_tokens"]) {
    params["max_tokens"] = Array.isArray(currentModelSpec["max_output_tokens"][0])
      ? currentModelSpec["max_output_tokens"][1]  // format: [[min, max], default]
      : currentModelSpec["max_output_tokens"][1]; // format: [min, max]
  } else if (spMaxTokensToggle && spMaxTokensToggle.checked) {
    params["max_tokens"] = spMaxTokens ? spMaxTokens.value : DEFAULT_MAX_OUTPUT_TOKENS;
  } else {
    params["max_tokens"] = DEFAULT_MAX_OUTPUT_TOKENS;
  }

  const spContextSize = document.getElementById("context-size");
  if (spContextSize && spContextSize.disabled) {
    // virtually unlimited context size
    params["context_size"] = DEFAULT_CONTEXT_SIZE;
  } else {
    params["context_size"] = spContextSize ? spContextSize.value : DEFAULT_CONTEXT_SIZE;
  }

  // Save thinking display preference
  const spThinkingContainer = document.getElementById("thinking-display-container");
  if (spThinkingContainer && spThinkingContainer.style.display !== 'none') {
    const spShowThinking = document.getElementById("show-thinking");
    params["show_thinking"] = spShowThinking ? spShowThinking.checked : false;
  }

  const getVal = (id) => { const el = document.getElementById(id); return el ? el.value : null; };
  params["tts_provider"] = getVal("tts-provider");
  params["tts_voice"] = getVal("tts-voice");
  params["elevenlabs_tts_voice"] = getVal("elevenlabs-tts-voice");
  params["gemini_tts_voice"] = getVal("gemini-tts-voice");
  params["mistral_tts_voice"] = getVal("mistral-tts-voice");
  params["tts_speed"] = getVal("tts-speed");
  params["conversation_language"] = getVal("conversation-language");
  // Update asr_lang for STT/TTS
  params["asr_lang"] = params["conversation_language"];
  const spEasySubmit = document.getElementById("check-easy-submit");
  const spAutoSpeech = document.getElementById("check-auto-speech");
  params["easy_submit"] = spEasySubmit ? spEasySubmit.checked : false;
  params["auto_speech"] = spAutoSpeech ? spAutoSpeech.checked : false;

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
  const cpInitialPrompt = document.getElementById("initial-prompt");
  const cpMaxTokens = document.getElementById("max-tokens");
  const cpContextSize = document.getElementById("context-size");
  const cpModel = document.getElementById("model");
  const cpReasoningEffort = document.getElementById("reasoning-effort");
  const cpTemperature = document.getElementById("temperature");
  // Only check initial-prompt if it's visible (not all apps require it)
  if (cpInitialPrompt && cpInitialPrompt.style.display !== 'none' && !cpInitialPrompt.value) {
    alert("Please enter an initial prompt.");
    cpInitialPrompt.focus();
    return false;
  } else if (cpMaxTokens && !cpMaxTokens.value) {
    alert("Please enter a max output tokens value.");
    cpMaxTokens.focus();
    return false;
  } else if (cpContextSize && !cpContextSize.value) {
    alert("Please enter a context size.");
    cpContextSize.focus();
    return false;
  } else if (cpModel && !cpModel.value) {
    alert("Please select a model.");
    cpModel.focus();
    return false;
  } else if (cpReasoningEffort && !cpReasoningEffort.disabled && !cpReasoningEffort.value) {
    alert("Please select a reasoning effort.");
    cpReasoningEffort.focus();
    return false
  } else if (cpTemperature && !cpTemperature.value) {
    alert("Please enter a temperature.");
    cpTemperature.focus();
    return false;
  }
  return true;
}

  // isPdfSupportedForModel, isImageGenerationApp, isMaskEditingEnabled → extracted to model-capabilities.js

function resetEvent(_event, resetToDefaultApp = false) {
  audioInit();

  const imageUsed = document.getElementById("image-used");
  if (imageUsed) imageUsed.innerHTML = '';
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
    const resetModal = document.getElementById("resetConfirmation");
    if (resetModal) {
      bootstrap.Modal.getOrCreateInstance(resetModal).show();
      resetModal.addEventListener("shown.bs.modal", function () {
        const resetConfirmed = document.getElementById("resetConfirmed");
        if (resetConfirmed) resetConfirmed.focus();
      }, { once: true });
    }
    const resetConfirmedBtn = document.getElementById("resetConfirmed");
    if (resetConfirmedBtn) {
      resetConfirmedBtn.onclick = function (event) {
        event.preventDefault();
        doResetActions(resetToDefaultApp);
      };
    }
  }
}

// Function to handle the actual reset logic
function doResetActions(resetToDefaultApp = false) {
  // Store the current app selection before reset
  const drApps = document.getElementById("apps");
  const currentApp = resetToDefaultApp ? null : (drApps ? drApps.value : null);

  const drMessage = document.getElementById("message");
  if (drMessage) { drMessage.style.height = "96px"; drMessage.value = ""; }

  ws.send(JSON.stringify({ "message": "RESET" }));
  // Get UI language from cookie or default to 'en'
  const uiLanguage = document.cookie.match(/ui-language=([^;]+)/)?.[1] || 'en';
  ws.send(JSON.stringify({ "message": "LOAD", "ui_language": uiLanguage }));

  // Reset Context Panel for monadic apps
  if (typeof ContextPanel !== "undefined" && ContextPanel.resetContext) {
    ContextPanel.resetContext();
  }

  currentPdfData = null;
  
  // Delay resetParams to ensure LOAD response is processed first
  setTimeout(function() {
    resetParams();
    
    // If resetting to default app, find and select the first available app
    if (resetToDefaultApp) {
      // Find the first non-disabled option that is not a separator
      const allOptions = drApps ? drApps.querySelectorAll("option") : [];
      let firstApp = null;
      for (const opt of allOptions) {
        if (!opt.disabled && !opt.textContent.startsWith('──')) {
          firstApp = opt.value;
          break;
        }
      }

      if (firstApp && drApps) {
        drApps.value = firstApp;
        drApps.dispatchEvent(new Event('change'));
      }
    }
    
    // After resetParams, trigger app change to reload models and initial prompt
    const currentAppVal = drApps ? drApps.value : null;
    if (currentAppVal && typeof window.proceedWithAppChange === 'function') {
      // Call proceedWithAppChange to properly initialize the app
      window.proceedWithAppChange(currentAppVal);
    }

    // Ensure app-specific flags (like initiate_from_assistant) are restored
    // proceedWithAppChange may be delayed by isLoadingParams, so explicitly
    // restore the checkbox state after a sufficient delay
    if (currentAppVal && window.apps && window.apps[currentAppVal]) {
      setTimeout(function() {
        var appData = window.apps[currentAppVal];
        if (appData && appData["initiate_from_assistant"]) {
          const iaCb = document.getElementById("initiate-from-assistant");
          if (iaCb) iaCb.checked = true;
        }
        if (appData && appData["auto_speech"]) {
          const asCb = document.getElementById("check-auto-speech");
          if (asCb) asCb.checked = true;
        }
      }, 800);
    }
  }, 300);

  const drModelEl = document.getElementById("model");
  const model = drModelEl ? drModelEl.value : null;

  const drWebsearch = document.getElementById("websearch");
  const drWebsearchBadge = document.getElementById("websearch-badge");
  if (modelSpec[model] && ((modelSpec[model]["supports_web_search"] === true) || (modelSpec[model]["tool_capability"] === true))) {
    if (drWebsearch) { drWebsearch.disabled = false; drWebsearch.removeAttribute('title'); }
    if (drWebsearchBadge) drWebsearchBadge.style.display = (drWebsearch && drWebsearch.checked) ? '' : 'none';
  } else {
    const tt3 = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.webSearchModelDisabled') : 'Model does not support Web Search'
    if (drWebsearch) { drWebsearch.disabled = true; drWebsearch.setAttribute('title', tt3); }
    if (drWebsearchBadge) drWebsearchBadge.style.display = 'none';
  }

  // Extract provider from app_name parameter
  // Use the final app value after potential reset
  const finalApp = resetToDefaultApp ? (drApps ? drApps.value : null) : currentApp;
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

  const drModelSelected = document.getElementById("model-selected");
  const drReasoningEffort = document.getElementById("reasoning-effort");
  if (drModelSelected) {
    if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
      drModelSelected.textContent = provider + " (" + model + " - " + (drReasoningEffort ? drReasoningEffort.value : '') + ")";
    } else {
      drModelSelected.textContent = provider + " (" + model + ")";
    }
  }

  const resetModalEl = document.getElementById("resetConfirmation");
  if (resetModalEl) bootstrap.Modal.getOrCreateInstance(resetModalEl).hide();
  const drMainPanel = document.getElementById("main-panel");
  if (drMainPanel) drMainPanel.style.display = 'none';
  const drDiscourse = document.getElementById("discourse");
  if (drDiscourse) { drDiscourse.innerHTML = ''; drDiscourse.style.display = 'none'; }
  const drChat = document.getElementById("chat");
  if (drChat) drChat.innerHTML = '';
  const drTempCard = document.getElementById("temp-card");
  if (drTempCard) drTempCard.style.display = 'none';
  const drTempReasoningCard = document.getElementById("temp-reasoning-card");
  if (drTempReasoningCard) drTempReasoningCard.remove();

  // Clear error cards and status message explicitly
  clearErrorCards();
  clearStatusMessage();

  if (typeof window.enterSettingsMode === 'function') {
    window.enterSettingsMode();
  } else {
    const drConfig = document.getElementById("config");
    if (drConfig) drConfig.style.display = '';
  }
  const resetSuccessText = getTranslation('ui.messages.resetSuccessful', 'Reset successful');
  setAlert(`<i class='fa-solid fa-circle-check'></i> ${resetSuccessText}.`, "success");

  // Clear session state (messages + flags) to avoid stale history
  if (window.SessionState) {
    if (typeof window.SessionState.clearMessages === 'function') {
      window.SessionState.clearMessages();
    }
    if (typeof window.SessionState.resetAllFlags === 'function') {
      window.SessionState.resetAllFlags();
    } else if (typeof window.SessionState.setResetFlags === 'function') {
      window.SessionState.setResetFlags();
    }
  }

  // Set app selection back to current app instead of default
  if (drApps) drApps.value = currentApp;

  // Update lastApp to match the current app to prevent app change dialog from appearing
  lastApp = currentApp;

  // Trigger app change to reset all settings to defaults
  if (drApps) drApps.dispatchEvent(new Event("change", {bubbles: true}));

  const drBaseAppTitle = document.getElementById("base-app-title");
  if (drBaseAppTitle) drBaseAppTitle.textContent = apps[currentApp]["display_name"] || apps[currentApp]["app_name"];

  const toBool = window.toBool || ((value) => {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') return value === 'true';
    return !!value;
  });

  const drMonadicBadge = document.getElementById("monadic-badge");
  if (drMonadicBadge) drMonadicBadge.style.display = toBool(apps[currentApp]["monadic"]) ? '' : 'none';

  const drToolsBadge = document.getElementById("tools-badge");
  if (drToolsBadge) drToolsBadge.style.display = apps[currentApp]["tools"] ? '' : 'none';

  const drMathBadge = document.getElementById("math-badge");
  if (drMathBadge) drMathBadge.style.display = toBool(apps[currentApp]["mathjax"]) ? '' : 'none';

  const drBaseAppIcon = document.getElementById("base-app-icon");
  if (drBaseAppIcon) drBaseAppIcon.innerHTML = apps[currentApp]["icon"];

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

  // Display description without badges; badge rendering handled by updateAppBadges
  const descriptionOnly = apps[currentApp]["description"] || "";
  setBaseAppDescription(descriptionOnly);
  if (typeof window.updateAppBadges === 'function') {
    window.updateAppBadges(currentApp);
  }

  const drModelAndFile = document.getElementById("model_and_file");
  if (drModelAndFile) drModelAndFile.style.display = '';
  const drModelParameters = document.getElementById("model_parameters");
  if (drModelParameters) drModelParameters.style.display = '';

  const drImageFile = document.getElementById("image-file");
  if (drImageFile) drImageFile.style.display = '';

  if (typeof window.setPromptView === 'function') window.setPromptView('hidden', false);

  const noDataText = getTranslation('ui.noDataAvailable', 'No data available');
  setStats(noDataText);

  // Instead of selecting the first available app, maintain the current selection
  // Use stop_apps_trigger flag to prevent app change dialog
  stop_apps_trigger = true;
  if (drApps) drApps.dispatchEvent(new Event("change", {bubbles: true}));

  // Use UI utilities module if available, otherwise fallback
  const drModelVal = drModelEl ? drModelEl.value : null;
  if (window.uiUtils && window.uiUtils.adjustImageUploadButton) {
    window.uiUtils.adjustImageUploadButton(drModelVal);
  } else if (window.shims && window.shims.uiUtils && window.shims.uiUtils.adjustImageUploadButton) {
    window.shims.uiUtils.adjustImageUploadButton(drModelVal);
  }
  adjustScrollButtons();

  if (ws) {
    reconnect_websocket(ws);
  }
  window.scroll({ top: 0 });
  
  // Clear messages using SessionState
  window.SessionState.clearMessages();
}

  // toggleItem, updateItemStates, onNewElementAdded, applyCollapseStates → extracted to json-tree-toggle.js

  // isFileInputsSupportedForModel, isResponsesApiModel → extracted to model-capabilities.js

  // updateAppBadges, filterToolBadges, filterCapabilityBadges, renderBadge,
  // getBadgeColorClass, getUserControlCheckbox, isToolGroupAvailable → extracted to badge-renderer.js

// Add event handler for app selection to update all badges
document.addEventListener("DOMContentLoaded", function() {
  // Handle app change events
  const rdApps = document.getElementById("apps");
  if (rdApps) {
    rdApps.addEventListener("change", function() {
      const selectedApp = this.value;

      // Save selected app to SessionState for restoration on reload
      if (selectedApp && window.SessionState) {
        window.SessionState.app.current = selectedApp;
        window.lastApp = selectedApp;
        window.SessionState.save();
      }

      setTimeout(function() {
        updateAppBadges(selectedApp);
      }, 100); // Small delay to ensure DOM is ready

      // Reload Workflow Viewer if open
      if (typeof WorkflowViewer !== "undefined" && WorkflowViewer.isOpen()) {
        WorkflowViewer.loadApp(selectedApp);
      }

      // Show/hide Context Panel based on monadic setting
      if (typeof ContextPanel !== "undefined" && apps && apps[selectedApp]) {
        const isMonadic = apps[selectedApp]["monadic"] === true ||
                          apps[selectedApp]["monadic"] === "true";
        if (isMonadic) {
          // Get context_schema from app settings if defined
          const contextSchema = apps[selectedApp]["context_schema"] || null;
          ContextPanel.show(selectedApp, contextSchema);
        } else {
          ContextPanel.hide();
        }
      }
    });
  }

  // Restore "All Models" toggle state from cookie BEFORE registering handlers
  // to ensure initial app load respects the saved preference
  const savedShowAll = getCookie("show-all-models");
  const showAllModelsEl = document.getElementById("show-all-models");
  if (savedShowAll === "true" && showAllModelsEl) {
    showAllModelsEl.checked = true;
  }

  // Handle "All Models" toggle — rebuild model dropdown on change
  if (showAllModelsEl) {
    showAllModelsEl.addEventListener("change", function() {
      const showAll = this.checked;
      setCookie("show-all-models", showAll ? "true" : "false", 365);

      const rdAppsEl = document.getElementById("apps");
      const selectedApp = rdAppsEl ? rdAppsEl.value : null;
      const currentApp = apps[selectedApp];
      if (!currentApp) return;

      const rdModelEl = document.getElementById("model");
      const currentModel = rdModelEl ? rdModelEl.value : null;
      const models = getModelsForApp(currentApp, showAll);
      const openai = (currentApp["group"] || "").toLowerCase() === "openai";
      if (rdModelEl) rdModelEl.innerHTML = listModels(models, openai);

      // Restore previous model selection if available in new list
      if (rdModelEl) {
        if (currentModel && models.includes(currentModel)) {
          rdModelEl.value = currentModel;
        } else {
          const defaultModel = getDefaultModelForApp(currentApp, models);
          if (defaultModel) rdModelEl.value = defaultModel;
        }
        rdModelEl.dispatchEvent(new Event("change", {bubbles: true}));
      }
    });
  }

  // Handle checkbox changes for user-controlled capabilities
  ["mathjax", "mermaid", "websearch"].forEach(id => {
    const el = document.getElementById(id);
    if (el) {
      el.addEventListener("change", function() {
        const rdAppsEl = document.getElementById("apps");
        const selectedApp = rdAppsEl ? rdAppsEl.value : null;
        if (selectedApp) {
          updateAppBadges(selectedApp);
        }

        // Update reasoning_effort options when websearch changes
        if (this.id === 'websearch' && window.ReasoningMapper) {
          const modelsEl = document.getElementById("models");
          const model = modelsEl ? modelsEl.value : null;
          const selectedOpt = modelsEl ? modelsEl.querySelector(":checked") : null;
          const parentOptgroup = selectedOpt ? selectedOpt.closest("optgroup") : null;
          const group = parentOptgroup ? parentOptgroup.getAttribute("label") : null;
          const provider = getProviderFromGroup(group);

          if (model && provider && ReasoningMapper.isSupported(provider, model)) {
            const wsEl = document.getElementById("websearch");
            const currentSettings = {
              web_search: (wsEl && wsEl.checked) || false
            };

            const availableOptions = ReasoningMapper.getAvailableOptions(provider, model, currentSettings);

            if (availableOptions) {
              const dropdown = document.getElementById("reasoning-effort");
              if (dropdown) {
                const currentValue = dropdown.value;

                // Rebuild options
                dropdown.innerHTML = '';
                availableOptions.forEach(option => {
                  const label = window.ReasoningLabels ?
                    window.ReasoningLabels.getOptionLabel(provider, option) :
                    option;
                  dropdown.insertAdjacentHTML('beforeend', `<option value="${option}">${label}</option>`);
                });

                // Restore value if still valid, otherwise use first available
                if (availableOptions.includes(currentValue)) {
                  dropdown.value = currentValue;
                } else {
                  const suggested = ReasoningMapper.getDefaultValue(provider, model);
                  const newValue = (suggested && availableOptions.includes(suggested)) ? suggested : availableOptions[0];
                  dropdown.value = newValue;
                }
              }
            }
          }
        }
      });
    }
  });
});

// updateAppBadges → badge-renderer.js

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    formatInfo,
    listModels,
    // setAlert → alert-manager.js
    // setCookie, getCookie → cookie-utils.js
    updateAppSelectIcon,
    // deleteMessage → alert-manager.js
    // applyCollapseStates → json-tree-toggle.js
    // isPdfSupportedForModel, isImageGenerationApp, isMaskEditingEnabled,
    // isFileInputsSupportedForModel, isResponsesApiModel → model-capabilities.js
  };
}
