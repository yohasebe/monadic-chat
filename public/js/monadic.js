$(function () {
  elemAlert.draggable({ cursor: "move" });

  const backToTop = $("#back_to_top");
  const backToBottom = $("#back_to_bottom");

  // button#broser is disabled when the system has started
  $("#browser").prop("disabled", true);

  //////////////////////////////
  // UI event handlers
  //////////////////////////////

  let lastApp = defaultApp;
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
    if (apps[$(this).val()]["pdf"]) {
      $("#pdf-div").show();
      $("#pdf-panel").show();
      ws.send(JSON.stringify({message: "PDF_TITLES"}));
    } else {
      $("#pdf-div").hide();
      $("#pdf-panel").hide();
    }
    $("#base-app-title").text(apps[$(this).val()]["app_name"]);
    $("#base-app-icon").html(apps[$(this).val()]["icon"]);
    $("#base-app-desc").html(apps[$(this).val()]["description"]);

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

  $("#start").on("click", function () {
    elemError.hide();
    if (checkParams()) {
      params = setParams();
    } else {
      return;
    }
    $("#paramList").html("").append(listParams(setParams()));
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

      if($("#initiate-from-assistant").is(":checked")) {
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

  $("#cancel-query").on("click", function () {
    // send cancel message to server
    ws.send(JSON.stringify({message: "CANCEL"}));
    // reset UI
    $("#chat").html("");
    $("#temp-card").hide();
    $("#user-panel").show();
    setInputFocus();
  });

  $("#check-token").on("click", function (event) {
    event.preventDefault();
    reconnect_websocket(ws, function (ws) {
      setAlert("<p>Verifying token . . .</p>", "warning");
      ws.send(JSON.stringify({ message: "CHECK_TOKEN", contents: $("#api-token").val() }));
    });
  })

  $("#send").on("click", function(event) {
    elemError.hide();
    event.preventDefault();
    if (message.value === "") {
      return;
    }
    params["message"] = $("#message").val();
    if ($("#select-role").val() !== "user") {
      reconnect_websocket(ws, function (ws) {
        const role = $("#select-role").val().split("-")[1];
        ws.send(JSON.stringify({ message: "SAMPLE", content: $("#message").val(), role: role}));
      });
      $("#message").css("height", "96px").val("");
      $("#select-role").val("").trigger("change");
    } else {
      reconnect_websocket(ws, function (ws) {
        ws.send(JSON.stringify(params));
      });
      $("#message").css("height", "96px").val("");
    }
    $("#select-role").val("user");
  });

  $("#clear").on("click", function (event) {
    event.preventDefault();
    $("#message").css("height", "96px").val("");
    setInputFocus()
  });

  $("#settings").on("click", function () {
    elemError.hide();
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
    elemError.hide();
    resetEvent(event);
    $("#select-role").val("user").trigger("change");
    $("#start-label").text("Start Session");
  });

  $("#save").on("click", function () {
    const textOnly = messages.map(function (message) {
      return { "role": message.role, "text": message.text, "mid": message.mid };
    });
    obj = { "parameters": setParams(), "messages": textOnly };
    saveObjToJson(obj, "monadic.json");
  });

  $("#load").on("click", function (event) {
    event.preventDefault();
    $("#loadModal").modal("show");

  });

  $("#pdf").on("click", function (event) {
    event.preventDefault();
    $("#pdf-title").val("");
    $("#pdfFile").val("");
    $("#pdfModal").modal("show");
  });

  $("#pdfModal").on("shown.bs.modal", function () {
    $("#pdf-title").focus();
  });

  $("#uploadPDF").on("click", function () {
    const fileInput = $("#pdfFile")[0];
    const file = fileInput.files[0];

    if (file) {
      const title = $("#pdf-title").val()
      $("#pdfModal button").prop("disabled", true);
      $("#pdf-spinner").show();
      const formData = new FormData();
      formData.append("pdfFile", file);
      formData.append("pdfTitle", title);

      $.ajax({
        url: "/pdf",
        type: "POST",
        data: formData,
        processData: false,
        contentType: false
      }).done(function(_filename) {
        $("#pdf-spinner").hide();
        $("#pdfModal button").prop('disabled', false);
        $("#pdfModal").modal("hide");
        ws.send(JSON.stringify({message: "PDF_TITLES"}));
        setAlert(`File uploaded successfully.<br /><b>${title}</b>`, "success");
      }).fail(function(error) {
        $("#pdf-spinner").hide();
        $("#pdfModal button").prop("disabled", false);
        $("#pdfModal").modal("hide");
        setAlert(`Error uploading file: ${error}`, "danger");
      }).always(function() {
        console.log('complete');
      });
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

  window.scroll({top: 0});
  $(window).scroll(function () {
    if ($(this).scrollTop() > 200) {
      backToTop.fadeIn();
    } else {
      backToTop.fadeOut();
    }

    if ($(this).scrollTop() < $(document).height() - $(window).height() - 200) {
      backToBottom.fadeIn();
    } else {
      backToBottom.fadeOut();
    }
  });

  backToTop.click(function (e) {
    e.preventDefault();
    $("body, html").animate({scrollTop: 0}, 0);
    return false;
  });

  backToBottom.click(function (e) {
    e.preventDefault();
    window.scroll({ top: $(document).height() - $(window).height(), behavior: "smooth" });
  });

  resetParams();

  // let default_lang = "en-US";
  // let voices;
  // let waitCount = 0;
  // let timer = setInterval(function () {
  //   waitCount++;
  //   voices = window.speechSynthesis.getVoices();
  //   if (Object.keys(params).length > 0 && voices && voices.length > 0) {
  //     utterance = new SpeechSynthesisUtterance();
  //     setupLanguages(true, params["speech_lang"] || default_lang);
  //     window.speechSynthesis.onvoiceschanged = function () {
  //       setupLanguages(false, params["speech_lang"] || default_lang);
  //     };
  //     clearInterval(timer);
  //     $("#lang_controller").show();
  //     $("#voice_controller").show();
  //     setInputFocus()

  //   } else if (waitCount == 50) {
  //     clearInterval(timer);
  //     return false;
  //   }
  // }, 100);


  // $("#speech-lang").on("change", function(){
  //   setupVoices(true);
  //   params["speech_lang"] = $("#speech-lang option:selected").val();
  //   params["speech_voice"] = $("#speech-voice option:selected").val();
  //   setCookie("userLang", params["speech_lang"], 30);
  //   setCookie("userVoice", params["speech_voice"], 30);
  // });

  // $("#speech-voice").on("change", function(){
  //   params["speech_voice"] = $("#speech-voice option:selected").val();
  //   setCookie("userVoice", params["speech_voice"], 30);
  // });

  $("#tts-voice").on("change", function(){
    params["tts_voice"] = $("#tts-voice option:selected").val();
    setCookie("userVoice", params["tts_voice"], 30);
  });

  // $("#speech-rate").on("input", function() {
  //   $("#speech-rate-value").text(parseFloat($(this).val()).toFixed(1));
  //   params["speech_rate"] = parseFloat($(this).val());
  //   setCookie("userRate", params["speech_rate"], 30);
  // });

  $("#tts-speed").on("input", function() {
    $("#tts-speed-value").text(parseFloat($(this).val()).toFixed(2));
    params["tts_speed_rate"] = parseFloat($(this).val());
    setCookie("userSpeed", params["tts_speed_rate"], 30);
  });

  $("#error-close").on("click", function (event) {
    event.preventDefault();
    elemError.hide();
  })

  $("#alert-close").on("click", function (event) {
    event.preventDefault();
    elemAlert.hide();
  })

  $("#message").on("input", function() {
    if (message.dataset.ime !== "true") {
      autoResize($(this));
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

  const filePDF = $('#pdfFile');
  const pdfButton = $('#uploadPDF');

  filePDF.on('change', function() {
    if (filePDF[0].files.length > 0) {
      pdfButton.prop('disabled', false);
    } else {
      pdfButton.prop('disabled', true);
    }
  });

  // if $("#auto-lang") is checked, then disable the language selector
  // $("#auto-lang").on("change", function () {
  //   if ($(this).is(":checked")) {
  //     $("#speech-lang").prop("disabled", true);
  //     $("#speech-voice").prop("disabled", true);
  //   } else {
  //     $("#speech-lang").prop("disabled", false);
  //     $("#speech-voice").prop("disabled", false);
  //   }
  // });

  $("#discourse").tooltip({
    selector: '.card-header [title]',
    delay: { show: 0, hide: 0 },
    show: 100
  });
});
