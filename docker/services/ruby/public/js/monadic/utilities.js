const runningOnChrome = navigator.userAgent.includes("Chrome");
const runningOnEdge = navigator.userAgent.includes("Edge");
const runningOnFirefox = navigator.userAgent.includes("Firefox");
const runningOnSafari = navigator.userAgent.includes("Safari");

const textError = $("#error-message")

const elemAlert = $("#alert-box")
const textAlert = $("#alert-message")
const textStats = $("#stats-message")

const DEFAULT_MAX_INPUT_TOKENS = 4000;
const DEFAULT_MAX_OUTPUT_TOKENS = 4000;
const DEFAULT_CONTEXT_SIZE = 100;

let currentPdfData = null;

// Adjust scroll buttons visibility
function adjustScrollButtons() {
  const $main = $("#main");
  const scrollTop = $main.scrollTop();
  const scrollHeight = $main.prop("scrollHeight");
  const clientHeight = $main.height();

  // Check if content is actually scrollable
  const isScrollable = scrollHeight > clientHeight;

  // Only show buttons if content is scrollable
  if (isScrollable) {
    $("#back_to_top").css("opacity", scrollTop > 200 ? "0.5" : "0.0");
    $("#back_to_bottom").css("opacity", 
      scrollTop < scrollHeight - clientHeight - 200 ? "0.5" : "0.0");
  } else {
    // Hide both buttons if content is not scrollable
    $("#back_to_top, #back_to_bottom").css("opacity", "0.0");
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
  const properties = ["tts-provider", "tts-voice", "tts-speed", "asr-lang"];
  properties.forEach(property => {
    const value = getCookie(property);
    if (value) {
      // check if the value is a valid option
      if ($(`#${property} option[value="${value}"]`).length > 0) {
        if (property === "tts-provider" && value === "elevenlabs") {
          // check if #elevenlabs-tts-voice option exists and not empty
          if ($("#elevenlabs-tts-voice option").length > 0) {
            $(`#${property}`).val(value).trigger("change");
          }
        } else {
          $(`#${property}`).val(value).trigger("change");
        }
      }
    }
  });
}

function listModels(models, openai = false) {
  // Array of strings to identify beta models
  const regularModelPatterns = [/^\b(?:gpt-4o|gpt-4\.5)\b/];
  const betaModelPatterns = [/^\bo\d\b/];

  // Separate regular models and beta models
  const regularModels = [];
  const betaModels = [];
  const otherModels = [];

  for (let model of models) {
    if (regularModelPatterns.some(pattern => pattern.test(model))) {
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
    // Include dummy options when openai is true
    modelOptions = [
      '<option disabled>──gpt-models──</option>',
      ...regularModels.map(model =>
        `<option value="${model}">${model}</option>`
      ),
      '<option disabled>──reasoning models──</option>',
      ...betaModels.map(model =>
        `<option value="${model}" data-model-type="reasoning">${model}</option>`
      ),
      '<option disabled>──other models──</option>',
      ...otherModels.map(model =>
        `<option value="${model}">${model}</option>`
      )
    ];
  } else {
    // Exclude dummy options when openai is false
    modelOptions = [
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
    elemAlert.removeClass(function (_index, className) {
      return (className.match(/\balert-\S+/g) || []).join(' ');
    });
    elemAlert.addClass(`alert-${alertType}`);
  } else {
    textAlert.removeClass(function (_index, className) {
      return (className.match(/\btext-\S+/g) || []).join(' ');
    });
    textAlert.addClass(`text-${alertType}`);
  }
}

function setAlert(text = "", alertType = "success") {
  if (alertType === "error") {
    $("#monnadic-spinner").hide();
    // check if text["content"] exists
    let msg = text;
    if (text["content"]) {
      msg = text["content"];
    } else if (msg === "") {
      msg = "Something went wrong.";
    }
    const errorCard = createCard("system", "<span class='text text-warning'><i class='fa-solid fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>", msg);
    $("#discourse").append(errorCard);
  } else {
    textAlert.html(`${text}`);
    setAlertClass(alertType);
  }
}

function setStats(text = "") {
  textStats.html(`${text}`);
}

function deleteMessage(mid) {
  $(`#${mid}`).remove();
  const index = messages.findIndex((m) => m.mid === mid);
  messages.splice(index, 1);
  ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
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
    if (reasoning_effort) {
      $("#reasoning-effort").val(reasoning_effort);
      $("#reasoning-effort").prop('disabled', false);
      $("#max-tokens").prop("disabled", true);
    } else {
      if (spec["reasoning_effort"]) {
        $("#reasoning-effort").val(reasoning_effort[1]);
        $("#reasoning-effort").prop('disabled', false);
        $("#max-tokens-toggle").prop("checked", false).prop("disabled", true);
      } else {
        $("#reasoning-effort").prop('disabled', true);
        $("#max-tokens-toggle").prop("disabled", false).prop("checked", true);
      }
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

  $("#context-size").val(params["context_size"] || DEFAULT_CONTEXT_SIZE);
  $("#context-size").val(params["context_size"] || "10");
}

function resetParams() {
  $("#pdf-titles").empty();
  params = Object.assign({}, originalParams);
  loadParams(params, "reset");
  // wait for loadParams to finish
  setTimeout(function () {
    $("#apps select").val(params["app_name"]);
    if (params["pdf"] === "true") {
      $("#file-div").show();
      $("#pdf-panel").show();
    } else if (params["file"] === "true") {
      $("#file-div").show();
    } else {
      $("#file-div").hide();
      $("#pdf-panel").hide();
    }
  }, 500);
}

function setParams() {
  const app_name = $("#apps").val();
  params = Object.assign({}, apps[app_name]);
  params["app_name"] = app_name;

  if ($("#ai-user-toggle").is(":checked")) {
    if ($("#ai-user-initial-prompt").val().trim() !== "") {
      params["ai_user_initial_prompt"] = $("#ai-user-initial-prompt").val();
    }
  } else {
    params["initiate_from_assistant"] = $("#initiate-from-assistant").prop('checked');
  }

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
  params["tts_speed"] = $("#tts-speed").val();
  params["asr_lang"] = $("#asr-lang").val();
  params["easy_submit"] = $("#check-easy-submit").prop('checked');
  params["auto_speech"] = $("#check-auto-speech").prop('checked');

  const spec = modelSpec[model];
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

function adjustImageUploadButton(selectedModel) {
  // Update image/PDF upload UI based on model
  const isPdfEnabled = selectedModel && selectedModel.includes("sonnet");
  const imageFileBtn = $("#image-file");
  const imageFileInput = $('#imageFile');

  if (isPdfEnabled) {
    imageFileBtn.html('<i class="fas fa-image"></i> Upload Image/PDF');
    imageFileInput.attr('accept', '.jpg,.jpeg,.png,.gif,.pdf');
  } else {
    imageFileBtn.html('<i class="fas fa-image"></i> Upload Image');
    imageFileInput.attr('accept', '.jpg,.jpeg,.png,.gif');
    // Remove any PDF files from images array when switching to non-PDF model
    images = images.filter(img => !img.type.includes('pdf'));
    updateFileDisplay(images);
  }
}

function resetEvent(_event) {
  audioInit();

  $("#image-used").children().remove();
  images = [];

  $("#resetConfirmation").modal("show");
  $("#resetConfirmation").on("shown.bs.modal", function () {
    $("#resetConfirmed").focus();
  });
  $("#resetConfirmed").on("click", function (event) {
    event.preventDefault();

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

    if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
      $("#model-selected").text(model + " (" + $("#reasoning-effort").val() + ")");
    } else {
      $("#model-selected").text(model);
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
    $("#base-app-title").text(apps[$("#apps").val()]["app_name"]);

    if (apps[$("#apps").val()]["monadic"]) {
      $("#monadic-badge").show();
    } else {
      $("#monadic-badge").hide();
    }

    if (apps[$("#apps").val()]["tools"]) {
      $("#tools-badge").show();
    } else {
      $("#tools-badge").hide();
    }

    if (apps[$("#apps").val()]["mathjax"]) {
      $("#math-badge").show();
    } else {
      $("#math-badge").hide();
    }

    $("#base-app-icon").html(apps[$("#apps").val()]["icon"]);
    $("#base-app-desc").html(apps[$("#apps").val()]["description"]);

    $("#model_and_file").show();
    $("#model_parameters").show();

    $("#image-file").show();

    $("#initial-prompt-toggle").prop("checked", false).trigger("change");
    $("#ai-user-initial-prompt-toggle").prop("checked", false).trigger("change");

    setStats("No data available");

    // select the second option item in the apps dropdown
    $("#apps").val($("#apps option:eq(1)").val()).trigger("change");

    adjustImageUploadButton($("#model").val());
    adjustScrollButtons();

    if (ws) {
      reconnect_websocket(ws);
    }
    window.scroll({ top: 0 });
    messages.length = 0;
  });
}

let collapseStates = {};

function toggleItem(element) {
  const content = element.nextElementSibling;
  const chevron = element.querySelector('.fa-chevron-down, .fa-chevron-right');
  const toggleText = element.querySelector('.toggle-text');

  if (!content || !chevron || !toggleText) {
    console.error("Element not found");
    return;
  }

  const isOpening = content.style.display === 'none';

  if (isOpening) {
    content.style.display = 'block';
    chevron.classList.replace('fa-chevron-right', 'fa-chevron-down');
  } else {
    content.style.display = 'none';
    chevron.classList.replace('fa-chevron-down', 'fa-chevron-right');
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
