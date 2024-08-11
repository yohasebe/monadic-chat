$(function () {
  const aiUserInitialPrompt = `The user is currently answering various types of questions, writing computer program code, making decent suggestions, and giving helpful advice on your message. Give the user requests, suggestions, or questions so that the conversation is engaging and interesting. If there are any errors in the responses you get, point them out and ask for correction. Use the same language as the user.

Keep on pretending as if you were the "user" and as if the user were the "assistant" throughout the conversation.

Do your best to make the conversation as natural as possible. Do not change subjects abruptly, and keep the conversation going by asking questions or making comments relevant to the preceding and current topics.

Your response should be consice and clear. Even if the preceding messages are formatted as json, you keep your response as plain text. do not use parentheses or brackets in your response.

Remember you are the one who inquires for information, not providing the answers.`;

  elemAlert.draggable({ cursor: "move" });

  const backToTop = $("#back_to_top");
  const backToBottom = $("#back_to_bottom");

  // button#browser is disabled when the system has started
  $("#browser").prop("disabled", true);

  //////////////////////////////
  // UI event handlers
  //////////////////////////////
  
  function listModels(models) {
    let modelList = "";
    for (let model of models) {
      modelList += `<option value="${model}">${model}</option>`;
    }
    return modelList;
  }

  let lastApp = defaultApp;

  $("#auto-scroll-toggle").on("change", function() {
    if ($(this).is(":checked")) {
      autoScroll = true;
    } else {
      autoScroll = false;
    }
  });

  $("#max-tokens-toggle").on("change", function() {
    if ($(this).is(":checked")) {
      $("#max-tokens").prop("disabled", false);
    } else {
      $("#max-tokens").prop("disabled", true);
    }
  });

  $("#apps").on("change", function(event) {
    event.preventDefault();
    if (messages.length > 0) {
      if (this.value === lastApp) {
        return;
      }

      $("#clearConfirmation").modal("show");
      // if `#clearConfirmed` button is clicked, clear the current conversation
      $("#clearConfirmed").on("click", function () {
        ws.send(JSON.stringify({"message": "RESET"}));
        messages = [];
        $("#discourse").html("");
        $("#clearConfirmation").modal("hide");
      });
      // if `#clearNotConfirmed` button is clicked, just hide the modal
      $("#clearNotConfirmed").on("click", function () {
        $("#clearConfirmation").modal("hide");
      });
    }
    lastApp = this.value;
    Object.assign(params, apps[$(this).val()]);
    loadParams(params, "changeApp");

    if (apps[$(this).val()]["pdf"]){
      $("#file-div").show();
      $("#pdf-panel").show();
      ws.send(JSON.stringify({message: "PDF_TITLES"}));
    } else if (apps[$(this).val()]["file"]){
      $("#pdf-panel").hide();
      $("#file-div").show();
    } else {
      $("#file-div").hide();
      $("#pdf-panel").hide();
    }

    if (apps[$(this).val()]["image"]){
      $("#image-file").show();
    } else {
      $("#image-file").hide();
    }

    if (apps[$(this).val()]["models"] && apps[$(this).val()]["models"].length > 0) {
      let models_text = apps[$(this).val()]["models"]
      let models = JSON.parse(models_text);
      let modelList = listModels(models);
      $("#model").html(modelList);
      let model = models[0];
      if (params["model"] && models.includes(params["model"])) {
        model = params["model"];
      }

      $("#model-selected").text(model);
      $("#model").val(model);
    } else if (!apps[$(this).val()]["model"] || apps[$(this).val()]["model"].length === 0) {
      $("#model_and_file").hide();
      $("#model_parameters").hide();
    } else {
      $("#model").html(model_options);
      $("#model").val(params["model"]);
      $("#model-selected").text(params["model"]);
      $("#model_and_file").show();
      $("#model_parameters").show();
    }

    if (apps[$(this).val()]["max_tokens"]) {
      $("#max-tokens-toggle").prop("checked", true);
      $("#max-tokens").prop("disabled", false);
    } else {
      $("#max-tokens-toggle").prop("checked", false);
      $("#max-tokens").prop("disabled", true);
    }
    $("#base-app-title").text(apps[$(this).val()]["app_name"]);
    $("#base-app-icon").html(apps[$(this).val()]["icon"]);
    if (apps[$(this).val()]["monadic"]) {
      $("#monadic-badge").show();
    } else {
      $("#monadic-badge").hide();
    }

    if (apps[$(this).val()]["tools"]) {
      $("#tools-badge").show();
    } else {
      $("#tools-badge").hide();
    }
    $("#base-app-desc").html(apps[$(this).val()]["description"]);

    $("#initial-prompt-toggle").prop("checked", false).trigger("change");
    $("#ai-user-initial-prompt-toggle").prop("checked", false).trigger("change");

    $("#start").focus();
  })

  $("#show-notification").on("change", function () {
    if ($(this).is(":checked")) {
      params["show_notification"] = true;
      elemAlert.show();
    } else {
      params["show_notification"] = false;
      elemAlert.hide();
    }
  });

  $("#check-auto-speech").on("change", function () {
    if ($(this).is(":checked")) {
      params["auto_speech"] = true;
    } else {
      params["auto_speech"] = false;
    }
  })

  $("#check-easy-submit").on("change", function () {
    if ($(this).is(":checked")) {
      params["easy_submit"] = true;
    } else {
      params["easy_submit"] = false;
    }
  })

  $("#toggle-menu").on("click", function () {
    // toggle shoe/hide menu and adjust main panel width
    if ($("#menu").is(":visible")) {
      $("#main").toggleClass("col-md-8", "col-md-12");
      $("#menu").hide();
    } else {
      $("#main").toggleClass("col-md-8", "col-md-12");
      // show menu after #main width has been fully adjusted
      $("body, html").animate({scrollTop: 0}, 0);
      setTimeout(() => {
        $("#menu").show();
      }, 500);
    }
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

    if (messages.length > 0) {
      $("#config").hide();
      $("#back-to-settings").show();
      $("#main-panel").show();
      $("#discourse").show();
      $("#chat").html("")
      $("#temp-card").hide();
      $("#parameter-panel").show();
      $("#user-panel").show();
      setInputFocus()
    } else {
      $("#config").hide();
      $("#back-to-settings").show();
      $("#parameter-panel").show();
      $("#main-panel").show();
      $("#discourse").show();

      if(!$("#ai-user-toggle").is(":checked") && $("#initiate-from-assistant").is(":checked")) {
        $("#temp-card").show();
        $("#user-panel").hide();
        reconnect_websocket(ws, function (ws) {
          ws.send(JSON.stringify(params));
        });
      } else {
        $("#user-panel").show();
        setInputFocus()
      }
    }
  });

  // if $ai-user-toggle is enabled, $ai-user-initial-prompt will be automatically disabled
  $("#ai-user-toggle").on("change", function() {
    if ($(this).is(":checked")) {
      $("#initiate-from-assistant").prop("checked", false).trigger("change");
    }
  });
  // if $ai-user-initial-prompt is enabled, $ai-user-toggle will be automatically disabled
  $("#initiate-from-assistant").on("change", function() {
    if ($(this).is(":checked")) {
      $("#ai-user-toggle").prop("checked", false);
    }
  });

  $("#cancel_query").on("click", function () {
    setAlert("Ready to start.", "success");
    ttsStop();

    responseStarted = false;
    callingFunction = false;

    // send cancel message to server
    ws.send(JSON.stringify({message: "CANCEL"}));
    // reset UI
    $("#chat").html("");
    $("#temp-card").hide();
    $("#user-panel").show();
    $("#cancel_query").css("opacity", "0.0");
    setInputFocus();
  });

$("#send").on("click", function(event) {
  audioInit();
  setAlert("<i class='fas fa-robot'></i> THINKING", "warning");
  event.preventDefault();
  if (message.value === "") {
    return;
  }
  params = setParams();
  params["message"] = $("#message").val();

  $("#cancel_query").css("opacity", "1");

  if ($("#select-role").val() !== "user") {
    reconnect_websocket(ws, function (ws) {
      const role = $("#select-role").val().split("-")[1];
      const msg_object = { message: "SAMPLE", content: $("#message").val(), role: role}
      ws.send(JSON.stringify(msg_object));
    });
    $("#message").css("height", "96px").val("");
    $("#select-role").val("").trigger("change");
  } else {
    reconnect_websocket(ws, function (ws) {
      if (images && images.length > 0) {
        params.images = images;
      } else {
        params.images = [];
      }

      ws.send(JSON.stringify(params));
      images = []; // Clear images after sending
    });
    $("#message").css("height", "96px").val("");
    $("#image-used").html("");
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
    setInputFocus()
  });


  $("#reset, .navbar-brand").on("click", function (event) {
    ttsStop();
    audioInit();
    resetEvent(event);
    $("#select-role").val("user").trigger("change");
    $("#start-label").text("Start Session");
    $("#model").prop("disabled", false);
  });

  $("#save").on("click", function () {
    const textOnly = messages.map(function (message) {
      let message_obj = { "role": message.role, "text": message.text, "mid": message.mid };
      if(message.image){
        message_obj.image = message.image;
      }
      return message_obj;
    });
    obj = { "parameters": setParams(), "messages": textOnly };
    saveObjToJson(obj, "monadic.json");
  });

  $("#load").on("click", function (event) {
    event.preventDefault();
    $("#loadModal").modal("show");
  });

  $("#file").on("click", function (event) {
    event.preventDefault();
    $("#file-title").val("");
    $("#fileFile").val("");
    $("#fileModal").modal("show");
  });

  $("#loadModal").on("shown.bs.modal", function () {
    $("#file-title").focus();
  });

  let fileTitle = "";
  let fileContents = "";

  $("#uploadFile").on("click", function () {
    const fileInput = $("#fileFile")[0];
    const file = fileInput.files[0];

    if (file) {
      // check if the file is a PDF file
      if (file.type === "application/pdf") {
        fileTitle = $("#file-title").val()
        $("#fileModal button").prop("disabled", true);
        $("#file-spinner").show();
        const formData = new FormData();
        formData.append("pdfFile", file);
        formData.append("pdfTitle", fileTitle);

        $.ajax({
          url: "/pdf",
          type: "POST",
          data: formData,
          processData: false,
          contentType: false
        }).done(function(_filename) {
          $("#file-spinner").hide();
          $("#fileModal button").prop('disabled', false);
          $("#fileModal").modal("hide");
          ws.send(JSON.stringify({message: "PDF_TITLES"}));
          setAlert(`File uploaded successfully.<br />`, "success");
        }).fail(function(error) {
          $("#file-spinner").hide();
          $("#fileModal button").prop("disabled", false);
          $("#fileModal").modal("hide");
          setAlert(`Error uploading file: ${error}`, "error");
        }).always(function() {
          console.log('complete');
        });
      }
    } else {
      alert("Please select a PDF file to upload");
    }
  });

  $("#temperature").on("input", function() {
    $("#temperature-value").text(parseFloat($(this).val()).toFixed(1));
  });

  $("#top-p").on("input", function() {
    $("#top-p-value").text(parseFloat($(this).val()).toFixed(1));
  });

  $("#presence-penalty").on("input", function() {
    $("#presence-penalty-value").text(parseFloat($(this).val()).toFixed(1));
  });

  $("#frequency-penalty").on("input", function() {
    $("#frequency-penalty-value").text(parseFloat($(this).val()).toFixed(1));
  });

  //////////////////////////////
  // Set up the initial state of the UI
  //////////////////////////////

  // if scrollbar inside `#main` is visible, show the back-to-top and back-to-bottom buttons
  function adjustScrollButtons() {
    if ($(this).scrollTop() > 200) {
      backToTop.css("opacity", "0.5");
    } else {
      backToTop.css("opacity", "0.0");
    }
    if ($(this).scrollTop() < $(this).prop("scrollHeight") - $(this).height() - 200) {
      backToBottom.css("opacity", "0.5");
    } else {
      backToBottom.css("opacity", "0.0");
    }
  }

  backToTop.click(function (e) {
    e.preventDefault();
    $("#main").animate({scrollTop: 0}, 500);
  });

  backToBottom.click(function (e) {
    e.preventDefault();
    $("#main").animate({scrollTop: $("#main").prop("scrollHeight")}, 500);
  });

  resetParams();

  $("#tts-voice").on("change", function(){
    params["tts_voice"] = $("#tts-voice option:selected").val();
    setCookie("userVoice", params["tts_voice"], 30);
  });

  $("#asr-lang").on("change", function(){
    params["asr_lang"] = $("#asr-lang option:selected").val();
    setCookie("asrLang", params["asr-lang"], 30);
  });

  $("#tts-speed").on("input", function() {
    $("#tts-speed-value").text(parseFloat($(this).val()).toFixed(2));
    params["tts_speed_rate"] = parseFloat($(this).val());
    setCookie("userSpeed", params["tts_speed_rate"], 30);
  });

  $("#error-close").on("click", function (event) {
    event.preventDefault();
  })

  $("#alert-close").on("click", function (event) {
    event.preventDefault();
    elemAlert.hide();
  })

  $("#message, #initial-prompt, #ai-user-initial-prompt").on("input", function() {
    if (message.dataset.ime !== "true") {
      autoResize($(this));
    }
  });

  $("#initial-prompt-toggle").on("change", function() {
    if (this.checked) {
      $("#initial-prompt").css("display", "");
      autoResize($("#initial-prompt"));
    } else {
      $("#initial-prompt").css("display", "none");
    }
  });

  $("#ai-user-initial-prompt-toggle").on("change", function() {
    if (this.checked) {
      $("#ai-user-initial-prompt").css("display", "");
    } else {
      $("#ai-user-initial-prompt").css("display", "none");
    }
  });

  if (!runningOnChrome && !runningOnEdge && !runningOnSafari && !runningOnFirefox) {
    voiceButton.hide();
    $("#auto-speech").hide();
    $("#auto-speech-form").hide();
  }

  $("#select-role").on("change", function () {
    const role = $("#select-role option:selected").val();
    if (role === "user" || role === "sample-user") {
      $("#role-icon i").removeClass("fa-robot fa-bars").addClass("fa-face-smile");
    } else if (role === "sample-assistant"){
      $("#role-icon i").removeClass("fa-face-smile fa-bars").addClass("fa-robot");
    } else if (role === "sample-system"){
      $("#role-icon i").removeClass("fa-face-smile fa-robot").addClass("fa-bars");
    }
  });

  const selectedApp = $('#apps');
  if (selectedApp.prop('selectedIndex') === -1) {
    selectedApp.prop('selectedIndex', 0);
  }

  const fileInput = $('#file-load');
  const loadButton = $('#import-button');

  fileInput.on('change', function() {
    if (fileInput[0].files.length > 0) {
      loadButton.prop('disabled', false);
    } else {
      loadButton.prop('disabled', true);
    }
  });

  const fileFile = $('#fileFile');
  const fileButton = $('#uploadFile');

  fileFile.on('change', function() {
    if (fileFile[0].files.length > 0) {
      fileButton.prop('disabled', false);
    } else {
      fileButton.prop('disabled', true);
    }
  });

  // if #model value is changed, update the value #model-selected
  $("#model").on("change", function() {
    $("#model-selected").text($("#model option:selected").val());
  });

  $("#discourse").tooltip({
    selector: '.card-header [title]',
    delay: { show: 0, hide: 0 },
    show: 100
  });

  $(document).on("click", ".contBtn", function() {
    $("#message").val("continue");
    $("#send").click();
  });

  $(document).on("click", ".base64-image", function () {
    // open a new window to show the image
    const w = window.open();
    w.document.write(this.outerHTML);
  });

  $("#main").scroll(adjustScrollButtons);
  $(window).resize(adjustScrollButtons);
  $(document).click(adjustScrollButtons);

  $(document).ready(function() {
    $("#ai-user-initial-prompt").val(aiUserInitialPrompt);
    autoResize($("#ai-user-initial-prompt"));
    $("#initial-prompt").css("display", "none");
    $("#initial-prompt-toggle").prop("checked", false);
    $("#ai-user-initial-prompt").css("display", "none");
    $("#ai-user-initial-prompt-toggle").prop("checked", false);
    $("#ai-user-toggle").prop("checked", false);
    adjustScrollButtons();
  });
});
