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

// Function to update app icon in select dropdown
function updateAppSelectIcon(appValue) {
  // If no appValue is provided, use current selected app
  if (!appValue && $("#apps").val()) {
    appValue = $("#apps").val();
  }
  
  // If apps object is not yet populated or app not found, do nothing
  if (!appValue || !apps || !apps[appValue] || !apps[appValue]["icon"]) {
    return;
  }
  
  // Get the icon HTML from the apps object
  const iconHtml = apps[appValue]["icon"];
  
  // Update the icon in the static icon span
  $("#app-select-icon").html(iconHtml);
  
  // Apply the gray color to the icon - this affects the icon's color regardless of its original color
  $("#app-select-icon i").css("color", "#777");
  
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
  // Note: gpt-5-chat-latest is excluded from GPT-5 category as it doesn't support reasoning_effort
  const gpt5ModelPatterns = [/^gpt-5(?:-(?:mini|nano))?(?:-(?:latest|\d{4}-\d{2}-\d{2}))?$/];
  const regularModelPatterns = [/^\b(?:gpt-4o|gpt-4\.\d)\b/];
  const betaModelPatterns = [/^\bo\d\b/];

  // Separate models by type
  const gpt5Models = [];
  const regularModels = [];
  const betaModels = [];
  const otherModels = [];

  for (let model of models) {
    // Special case: gpt-5-chat-latest goes to other models
    if (model === 'gpt-5-chat-latest') {
      otherModels.push(model);
    } else if (gpt5ModelPatterns.some(pattern => pattern.test(model))) {
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
            label = "Number of all messages";
            break;
          case "count_active_messages":
            noValue = false;
            label = "Number of active messages";
            break;
          case "count_all_tokens":
            noValue = false;
            label = "Tokens in all messages";
            break;
          case "count_total_system_tokens":
            noValue = false;
            label = "Tokens in all system prompts";
            break;
          case "count_total_input_tokens":
            noValue = false;
            label = "Tokens in all user messages";
            break;
          case "count_total_output_tokens":
            noValue = false;
            label = "Tokens in all assistant messages";
            break;
          case "count_total_active_tokens":
            noValue = false;
            label = "Tokens in all active messages";
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
      <i class="fas fa-chevron-right"></i> <span class="toggle-text">click to toggle</span>
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
  if (alertType === "error") {
    // Direct DOM access without global references
    $("#alert-box").removeClass(function (_index, className) {
      return (className.match(/\balert-\S+/g) || []).join(' ');
    });
    $("#alert-box").addClass(`alert-${alertType}`);
  } else {
    // Direct DOM access without global references
    $("#alert-message").removeClass(function (_index, className) {
      return (className.match(/\btext-\S+/g) || []).join(' ');
    });
    $("#alert-message").addClass(`text-${alertType}`);
  }
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
      $("#alert-message").html("<i class='fas fa-circle-check'></i> Error message removed");
      setAlertClass("success");
      
      return false;
    });
    
    // Disable the edit button for error cards
    errorCard.find(".func-edit").prop("disabled", true).css("opacity", "0.5");
    
    // Append to discourse area
    $("#discourse").append(errorCard);
  } else {
    // Direct DOM access
    $("#alert-message").html(`${text}`);
    setAlertClass(alertType);
  }
}

function setStats(text = "") {
  // Direct DOM access without global reference
  $("#stats-message").html(`${text}`);
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

function loadParams(params, calledFor = "loadParams") {
  $("#model-non-default").hide();
  // check if params is not empty
  if (Object.keys(params).length === 0) {
    return;
  }
  
  // Set flag to prevent model change handler from resetting reasoning_effort
  window.isLoadingParams = true;
  
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
    $("#ai-assistant-info").html('<span style="color: #DC4C64;">AI Assistant</span> <span style="color: inherit; font-weight: normal;">' + provider + '</span>').attr("data-model", selectedModel);
  }
  
  stop_apps_trigger = false;
  if (calledFor === "reset") {
    $("#file-div").hide();
    // $("#apps").val(defaultApp);
    $(`#apps option[value="${defaultApp}"]`).attr('selected', 'selected');
  } else if (calledFor === "loadParams") {
    stop_apps_trigger = true;
    let app_name = params["app_name"];
    $("#apps").val(app_name);
    $(`#apps option[value="${params['app_name']}"]`).attr('selected', 'selected');
    $("#model").val(params["model"]);
  } else if (calledFor === "changeApp") {
    let app_name = params["app_name"];
    $("#apps").val(app_name);
    $(`#apps option[value="${params['app_name']}"]`).attr('selected', 'selected');
    $("#model").val(params["model"]);
  }

  if (params["easy_submit"]) {
    $("#check-easy-submit").prop('checked', true);
  } else {
    $("#check-easy-submit").prop('checked', false);;
  }
  if (params["auto_speech"]) {
    $("#check-auto-speech").prop('checked', true);
  } else {
    $("#check-auto-speech").prop('checked', false);;
  }
  if (params["initiate_from_assistant"]) {
    $("#initiate-from-assistant").prop('checked', true);
  } else {
    $("#initiate-from-assistant").prop('checked', false);
  }
  if (params["mathjax"]) {
    $("#mathjax").prop('checked', true);
    $("#math-badge").show();
  } else {
    $("#mathjax").prop('checked', false);
    $("#math-badge").hide();
  }

  $("#initial-prompt").val(params["initial_prompt"]).trigger("input");

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
    
    // Debug: Log reasoning_effort processing
    console.log(`\n=== loadParams Debug for ${params["app_name"]} ===`);
    console.log(`Model:`, model);
    console.log(`Model spec has reasoning_effort:`, spec["reasoning_effort"] ? "YES" : "NO");
    console.log(`reasoning_effort from params:`, reasoning_effort);
    console.log(`Model spec reasoning_effort:`, spec["reasoning_effort"]);
    
    // Check if the model supports reasoning_effort
    if (spec["reasoning_effort"]) {
      // Model supports reasoning_effort
      let effortValue;
      
      if (reasoning_effort) {
        // Use the value from params (from MDSL or user selection)
        effortValue = reasoning_effort;
      } else {
        // Use the default from model spec
        let defaultEffort = 'medium';
        try {
          if (Array.isArray(spec["reasoning_effort"]) && spec["reasoning_effort"].length > 1) {
            defaultEffort = spec["reasoning_effort"][1];
          }
        } catch (e) {
          // Could not get default reasoning effort from model spec
        }
        effortValue = defaultEffort;
      }
      
      $("#reasoning-effort").val(effortValue);
      $("#reasoning-effort").prop('disabled', false);
      $("#max-tokens-toggle").prop("checked", false).prop("disabled", true);
    } else {
      // Model doesn't support reasoning_effort
      $("#reasoning-effort").prop('disabled', true);
      $("#reasoning-effort").val('');  // Clear the value
      $("#max-tokens-toggle").prop("disabled", false).prop("checked", true);
      $("#max-tokens").prop("disabled", false);
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

  // Set context size from configuration or use default
  $("#context-size").val(params["context_size"] || DEFAULT_CONTEXT_SIZE);
  
  // Reset the flag after loading is complete
  window.isLoadingParams = false;
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
    console.log("Debug: params['pdf']:", params["pdf"]);
    console.log("Debug: params['pdf_vector_storage']:", params["pdf_vector_storage"]);
    
    if (params["pdf"] === "true" || params["pdf_vector_storage"] === true || params["pdf_vector_storage"] === "true") {
      console.log("Debug: Showing PDF controls");
      $("#file-div").show();
      $("#pdf-panel").show();
    } else if (params["file"] === "true") {
      $("#file-div").show();
    } else {
      console.log("Debug: Hiding PDF controls");
      $("#file-div").hide();
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
    params["mathjax"] = "true";
  } else {
    params["mathjax"] = "false";
  }

  if ($("#websearch").is(":checked") && modelSpec[params["model"]]["tool_capability"]) {
    params["websearch"] = "true";
  } else {
    params["websearch"] = "false";
  }

  if ($("#prompt-caching").prop('checked') && !$("#prompt-caching").prop('disabled')) {
    params["prompt_caching"] = true;
  }

  // params["initial_prompt"] = $("#initial-prompt").val();
  params["model"] = $("#model").val();

  if (!$("#reasoning-effort").prop('disabled')) {
    params["reasoning_effort"] = $("#reasoning-effort").val();
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
  params["asr_lang"] = $("#asr-lang").val();
  params["easy_submit"] = $("#check-easy-submit").prop('checked');
  params["auto_speech"] = $("#check-auto-speech").prop('checked');

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
  } else if (!$("#reasoning-effort").val()) {
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

// Check if a model supports PDF input
// PDF is supported only by OpenAI, Anthropic (Claude), and Google (Gemini) models with vision capability
function isPdfSupportedForModel(selectedModel) {
  return /^(gpt-|o\d|o4|claude-|gemini-)/.test(selectedModel);
}

// Check if the current app supports image generation
function isImageGenerationApp(appName) {
  if (!appName) {
    appName = $("#apps").val();
  }
  return apps[appName] && 
    (apps[appName].image_generation === true || 
     apps[appName].image_generation === "true");
}

// Check if the current app supports mask editing (distinct from basic image generation)
function isMaskEditingEnabled(appName) {
  if (!appName) {
    appName = $("#apps").val();
  }
  return apps[appName] && 
    (apps[appName].image_generation === true || 
     apps[appName].image_generation === "true") &&
    apps[appName].image_generation !== "upload_only";
}

function resetEvent(_event) {
  audioInit();

  $("#image-used").children().remove();
  images = [];

  // Detect iOS/iPadOS
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
               (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  
  // For iOS devices, bypass the modal and use standard confirm dialog
  if (isIOS) {
    if (confirm("Are you sure you want to reset the chat?")) {
      doResetActions();
    }
  } else {
    // For other platforms, use the Bootstrap modal
    $("#resetConfirmation").modal("show");
    $("#resetConfirmation").on("shown.bs.modal", function () {
      $("#resetConfirmed").focus();
    });
    $("#resetConfirmed").on("click", function (event) {
      event.preventDefault();
      doResetActions();
    });
  }
}

// Function to handle the actual reset logic
function doResetActions() {
  // Store the current app selection before reset
  const currentApp = $("#apps").val();

  $("#message").css("height", "96px").val("");

  ws.send(JSON.stringify({ "message": "RESET" }));
  ws.send(JSON.stringify({ "message": "LOAD" }));

  currentPdfData = null;
  resetParams();

  const model = $("#model").val();

  if (modelSpec[model] && modelSpec[model].hasOwnProperty("tool_capability") && modelSpec[model]["tool_capability"]) {
    $("#websearch").prop("disabled", false)
    if ($("#websearch").is(":checked")) {
      $("#websearch-badge").show();
    } else {
      $("#websearch-badge").hide();
    }
  } else {
    $("#websearch").prop("disabled", true)
    $("#websearch-badge").hide();
  }

  // Extract provider from app_name parameter
  let provider = "OpenAI";
  if (apps[currentApp] && apps[currentApp].group) {
    const group = apps[currentApp].group.toLowerCase();
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
  $("#config").show();
  $("#back-to-settings").hide();
  $("#parameter-panel").hide();
  setAlert("<i class='fa-solid fa-circle-check'></i> Reset successful.", "success");
  
  // Set flags to indicate reset happened using centralized state management
  window.SessionState.setResetFlags();
  
  // Set app selection back to current app instead of default
  $("#apps").val(currentApp);
  
  // Update lastApp to match the current app to prevent app change dialog from appearing
  lastApp = currentApp;
  
  // Trigger app change to reset all settings to defaults
  $("#apps").trigger("change");
  
  $("#base-app-title").text(apps[currentApp]["display_name"] || apps[currentApp]["app_name"]);

  if (apps[currentApp]["monadic"]) {
    $("#monadic-badge").show();
  } else {
    $("#monadic-badge").hide();
  }

  if (apps[currentApp]["tools"]) {
    $("#tools-badge").show();
  } else {
    $("#tools-badge").hide();
  }

  if (apps[currentApp]["mathjax"]) {
    $("#math-badge").show();
  } else {
    $("#math-badge").hide();
  }

  $("#base-app-icon").html(apps[currentApp]["icon"]);
  $("#base-app-desc").html(apps[currentApp]["description"]);

  $("#model_and_file").show();
  $("#model_parameters").show();

  $("#image-file").show();

  $("#initial-prompt-toggle").prop("checked", false).trigger("change");
  $("#ai-user-initial-prompt-toggle").prop("checked", false).trigger("change");

  setStats("No data available");

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

  const isOpening = content.style.display === 'none';

  if (isOpening) {
    content.style.display = 'block';
    chevron.classList.replace('fa-chevron-right', 'fa-chevron-down');
    if (toggleText) {
      toggleText.textContent = toggleText.textContent.replace('Show', 'Hide');
    }
  } else {
    content.style.display = 'none';
    chevron.classList.replace('fa-chevron-down', 'fa-chevron-right');
    if (toggleText) {
      toggleText.textContent = toggleText.textContent.replace('Hide', 'Show');
    }
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
