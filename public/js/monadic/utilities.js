const runningOnChrome = navigator.userAgent.includes("Chrome");
const runningOnEdge = navigator.userAgent.includes("Edge");
const runningOnFirefox = navigator.userAgent.includes("Firefox");
const runningOnSafari = navigator.userAgent.includes("Safari");

const elemError = $("#error-box")
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

//////////////////////////////
// convert an object to HTML changing snake_case to space case in the keys
//////////////////////////////

function formatInfo(info) {
  let noValue = true;
  let tableRows = "";

  for (const [key, value] of Object.entries(info)) {
    if (value && value !== 0 && !isNaN(value)) {
      noValue = false;
      let label = "";
      switch (key) {
        case "count_messages":
          label = "Num of all messages";
          break;
        case "count_active_messages":
          label = "Num of active messages";
          break;
        case "count_tokens":
          label = "Num of tokens in all messages";
          break;
        case "count_active_tokens":
          label = "Num of tokens in active messages";
          break;
      }
      if (label !== "") {
        tableRows += `
            <tr>
              <td>${label}</td>
              <td align="right">${parseInt(value).toLocaleString('en')}</td>
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
        ${tableRows}
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
  // delete objToSave["parameters"]["speech_lang"];
  // delete objToSave["parameters"]["speech_voice"];
  // delete objToSave["parameters"]["speech_rate"];
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
  console.log(replaced);
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

function setAlertClass(alertType = "danger") {
  if(alertType === "danger"){
    elemAlert.removeClass(function(_index, className) {
      return (className.match(/\balert-\S+/g) || []).join(' ');
    });
    elemAlert.addClass(`alert-${alertType}`);
  } else {
    textAlert.removeClass(function(_index, className) {
      return (className.match(/\bmessage-\S+/g) || []).join(' ');
    });
    textAlert.addClass(`message-${alertType}`);
  }
}

function setAlert(text = "", alertType = "success") {
  if (alertType === "danger") {
    textError.html(text);
    elemError.show();
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
// convert a paramter list to an HTML snippet
//////////////////////////////

function listParams(params) {
  const exp = /((?<!href="|href='|src="|src=')(https?|ftp|file):\/\/[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|])/ig;
  let table = `<table class="table table-sm text-secondary"><tbody>`;

  for (const [key, value] of Object.entries(params)) {
    const excluded_keys = [
      "app_name",
      "auto_speech",
      "desc",
      "easy_submit",
      "icon",
      "initiate_from_assistant",
      "message",
      "pdf",
      "show_notification",
      // "speech_lang",
      // "speech_voice",
      // "speech_rate",
      "tts_voice",
      "tts_speed",
      "initial_prompt",
      "description",
      "functions"
    ];
    if (excluded_keys.includes(key) || !value || value === "") {
      continue;
    }
    const html = value.replace(exp, "<a href='$1' target='_blank' rel='noopener noreferrer'>$1</a>");
    table += `\
      <tr>\
        <td style="font-weight: 500;">${convertString(key)}</td>\
        <td>${html.replace(/\n/g, "<br />")}</td>\
      </tr>\
      `;
  }
  table += `</tbody></table>`;
  return table;
}

//////////////////////////////
// Functions to load/reset/set parameters
//////////////////////////////

function loadParams(params, calledFor = "loadParams") {
  $("#initial-prompt").val(params["initial_prompt"]).trigger("input");
  $("#model").val(params["model"]);
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
    $("#pdf-div").hide();
    $("#apps").val(defaultApp);
    $(`#apps option[value="${defaultApp}"]`).attr('selected','selected');
  } else if (calledFor === "loadParams" || calledFor === "changeApp") {
    $("#apps").val(params["app_name"]);
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
}

function resetParams() {
  $("#pdf-titles").empty();
  params = Object.assign({}, originalParams);
  loadParams(params, "reset");
  // wait for loadParams to finish
  setTimeout(function () {
    $("#apps select").val(params["app_name"]);
    if (params["pdf"] === "true") {
      $("#pdf-div").show();
      $("#pdf-panel").show();
    } else {
      $("#pdf-div").hide();
      $("#pdf-panel").hide();
    }
  }, 500);
}

function setParams() {
  const app_name = $("#apps").val();
  params = Object.assign({}, apps[app_name]);
  params["app_name"] = app_name;
  params["initial_prompt"] = $("#initial-prompt").val();
  params["model"] = $("#model").val();
  params["temperature"] = $("#temperature").val();
  params["top_p"] = $("#top-p").val();
  params["presence_penalty"] = $("#presence-penalty").val();
  params["frequency_penalty"] = $("#frequency-penalty").val();
  params["max_tokens"] = $("#max-tokens").val();
  params["context_size"] = $("#context-size").val();
  // params["speech_rate"] = $("#speech-rate").val();
  params["tts_speed"] = $("#tts-speed").val();
  // params["speech_lang"] = $("#speech-lang").val();
  // params["speech_voice"] = $("#speech-voice").val();
  params["tts_voice"] = $("#tts-voice").val();
  params["easy_submit"] = $("#check-easy-submit").prop('checked');
  params["auto_speech"] = $("#check-auto-speech").prop('checked');
  params["initiate_from_assistant"] = $("#initiate-from-assistant").prop('checked');
  params["show_notification"] = $("#show-notification").prop('checked');
  console.log(params);
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
  event.preventDefault();
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
    $("#resetConfirmation").modal("hide");
    $("#main-panel").hide();
    $("#discourse").html("").hide();
    $("#chat").html("")
    $("#temp-card").hide();
    $("#config").show();
    $("#back-to-settings").hide();
    $("#paramList").html("")
    $("#parameter-panel").hide();
    setAlert("Ready to start.", "success");
    $("#base-app-title").text(apps[$("#apps").val()]["app_name"]);
    $("#base-app-icon").html(apps[$("#apps").val()]["icon"]);
    $("#base-app-desc").html(apps[$("#apps").val()]["description"]);
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

