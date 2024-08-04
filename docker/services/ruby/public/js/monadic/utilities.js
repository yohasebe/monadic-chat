const runningOnChrome = navigator.userAgent.includes("Chrome");
const runningOnEdge = navigator.userAgent.includes("Edge");
const runningOnFirefox = navigator.userAgent.includes("Firefox");
const runningOnSafari = navigator.userAgent.includes("Safari");

const textError = $("#error-message")

const elemAlert = $("#alert-box")
const textAlert = $("#alert-message")

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

function listModels(models) {
  let modelList = "";
  for (let model of models) {
    modelList += `<option value="${model}">${model}</option>`;
  }
  return modelList;
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
        case "count_tokens":
          noValue = false;
          label = "Tokens in all messages";
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
          label = "Token encoding";
          break;
      }

      if (value && !isNaN(value) && label){
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
    <table class="table table-sm mt-2 mb-0">
      <tbody>
        ${textRows}
        ${numRows}
      </tbody>
    </table>
  `;
}

//////////////////////////////
// save the javascript object to a json file
//////////////////////////////

function saveObjToJson(obj, fileName) {
  const objToSave = Object.assign({}, obj);
  delete objToSave["parameters"]["message"];
  delete objToSave["parameters"]["pdf"];
  delete objToSave["parameters"]["tts_voice"];
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
  } else {
    $("#message").focus();
  }
}

//////////////////////////////
// format a message to show in the chat
//////////////////////////////

function removeCode(text) {
  let replaced = text.replace(/```[\s\S]+?[\s]```/g, " ");
  replaced = replaced.replace(/<script>[\s\S]+?<\/script>/g, " ");
  replaced = replaced.replace(/<style>[\s\S]+?<\/style>/g, " ");
  replaced = replaced.replace(/<img [\s\S]+?\/>/g, " ");
  return replaced;
}

function removeEmojis(text){
  // in case of error, return the original text
  try {
    return text.replace(/\p{Extended_Pictographic}/gu, "");
  }
  catch (error) {
    return text;
  }
}

function removeMarkdown(text) {
  let replaced = text.replace(/\*\*|__|\*|_/g, "");
  replaced = replaced.replace(/`/g, "");
  return replaced;
}

function setAlertClass(alertType = "error") {
  if(alertType === "error"){
    elemAlert.removeClass(function(_index, className) {
      return (className.match(/\balert-\S+/g) || []).join(' ');
    });
    elemAlert.addClass(`alert-${alertType}`);
  } else {
    textAlert.removeClass(function(_index, className) {
      return (className.match(/\btext-\S+/g) || []).join(' ');
    });
    textAlert.addClass(`text-${alertType}`);
  }
}

function setAlert(text = "", alertType = "success") {
  if (alertType === "error") {
    try {
      msg = text["content"];
    } catch {
      msg = text;
    }
    const errorCard = createCard("system", "<span class='text text-warning'><i class='fa-solid fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>", "<p>Something went wrong. Please try again.</p><pre><code>" + msg + "</code></pre>");
    $("#discourse").append(errorCard);
  } else {
    textAlert.html(text);
    setAlertClass(alertType);
    if ($("#show-notification").is(":checked")) {
      elemAlert.show();
    } else {
      elemAlert.hide();
    }
  }
}

function deleteMessage(mid) {
  $(`#${mid}`).remove();
  const index = messages.findIndex((m) => m.mid === mid);
  messages.splice(index, 1);
  ws.send(JSON.stringify({"message": "DELETE", "mid": mid}));
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

function loadParams(params, calledFor = "loadParams") {
  $("#initial-prompt").val(params["initial_prompt"]).trigger("input");
  if (params["ai_user_initial_prompt"]) {
    $("#ai-user-initial-prompt-toggle").prop("checked", true).trigger("change");
    $("#ai-user-initial-prompt").val(params["ai_user_initial_prompt"]).trigger("input");
    $("#ai-user-toggle").prop("checked", true)
  } else {
    $("#ai-user-initial-prompt-toggle").prop("checked", false).trigger("change");
    $("#ai-user-toggle").prop("checked", false)
  }
  $("#temperature").val(params["temperature"] || "0.3");
  $("#temperature-value").text(params["temperature"] || "0.3");
  $("#top-p").val(params["top_p"] || "0.0");
  $("#top-p-value").text(params["top_p"] || "0.0");
  $("#max-tokens").val(params["max_tokens"] || "1000");
  $("#presence-penalty").val(params["presence_penalty"] || "0.0");
  $("#presence-penalty-value").text(params["presence_penalty"] || "0.0");
  $("#frequency-penalty").val(params["frequency_penalty"] || "0.0");
  $("#frequency-penalty-value").text(params["frequency_penalty"] || "0.0");
  $("#context-size").val(params["context_size"] || "10");

  if (calledFor === "reset") {
    $("#file-div").hide();
    $("#apps").val(defaultApp);
    $(`#apps option[value="${defaultApp}"]`).attr('selected','selected');
  } else if (calledFor === "loadParams" || calledFor === "changeApp") {
    let app_name = params["app_name"];
    $("#apps").val(app_name);
    $(`#apps option[value="${params['app_name']}"]`).attr('selected','selected');
  }
  if (params["easy_submit"]) {
    $("#check-easy-submit").prop('checked', true);
  } else {
    $("#check-easy-submit").prop('checked', false);;
  }
  if (params["auto_speech"]) {
    $("#check-auto-speech").prop('checked', true);
  } else{
    $("#check-auto-speech").prop('checked', false);;
  }
  if (params["initiate_from_assistant"]) {
    $("#initiate-from-assistant").prop('checked', true);
  } else{
    $("#initiate-from-assistant").prop('checked', false);
  }
  $("#model").val(params["model"]);
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

  params["initial_prompt"] = $("#initial-prompt").val();
  params["model"] = $("#model").val();
  params["temperature"] = $("#temperature").val();
  params["top_p"] = $("#top-p").val();
  params["presence_penalty"] = $("#presence-penalty").val();
  params["frequency_penalty"] = $("#frequency-penalty").val();
  params["max_tokens"] = $("#max-tokens").val();
  params["context_size"] = $("#context-size").val();
  params["tts_speed"] = $("#tts-speed").val();
  params["tts_voice"] = $("#tts-voice").val();
  params["asr_lang"] = $("#asr-lang").val();
  params["easy_submit"] = $("#check-easy-submit").prop('checked');
  params["auto_speech"] = $("#check-auto-speech").prop('checked');
  params["show_notification"] = $("#show-notification").prop('checked');
  return params;
}

function checkParams() {
  if (!$("#initial-prompt").val()) {
    alert("Please enter an initial prompt.");
    $("#initial-prompt").focus();
    return false;
  } else if (!$("#max-tokens").val()) {
    alert("Please enter a max tokens value.");
    $("#max-tokens").focus();
    return false;
  } else if (!$("#model").val()) {
    alert("Please select a model.");
    $("#model").focus();
    return false;
  } else if (!$("#context-size").val()) {
    alert("Please enter a context size.");
    $("#context-size").focus();
    return false;
  } else if (!$("#temperature").val()) {
    alert("Please enter a temperature.");
    $("#temperature").focus();
    return false;
  } else if (!$("#top-p").val()) {
    alert("Please enter a top p value.");
    $("#top-p").focus();
    return false;
  }
  return true;
}

function resetEvent(event) {
  audioInit();

  $("#image-used").children().remove();
  images = [];

  $("#message").css("height", "96px").val("");
  $("#resetConfirmation").modal("show");
  $("#resetConfirmation").on("shown.bs.modal", function () {
    $("#resetConfirmed").focus();
  });
  $("#resetConfirmed").on("click", function (event) {
    event.preventDefault();
    ws.send(JSON.stringify({"message": "RESET"}));
    ws.send(JSON.stringify({"message": "LOAD"}));
    resetParams();
    console.log(model_options);
    $("#model").html(model_options);
    $("#model-selected").text($("#model option:selected").text());
    $("#resetConfirmation").modal("hide");
    $("#main-panel").hide();
    $("#discourse").html("").hide();
    $("#chat").html("")
    $("#temp-card").hide();
    $("#config").show();
    $("#back-to-settings").hide();
    $("#parameter-panel").hide();
    setAlert("Ready to start.", "success");
    $("#base-app-title").text(apps[$("#apps").val()]["app_name"]);
    $("#base-app-icon").html(apps[$("#apps").val()]["icon"]);
    $("#base-app-desc").html(apps[$("#apps").val()]["description"]);

    $("#model_and_file").show();
    $("#model_parameters").show();

    $("#image-file").show();

    $("#initial-prompt-toggle").prop("checked", false).trigger("change");
    $("#ai-user-initial-prompt-toggle").prop("checked", false).trigger("change");

    if (ws) {
      reconnect_websocket(ws);
    }
    window.scroll({top: 0});
    messages.length = 0;
  });
}

function autoResize(textarea) {
  textarea.css('height', 'auto');
  textarea.css('height', textarea.prop('scrollHeight') + 'px');
}

