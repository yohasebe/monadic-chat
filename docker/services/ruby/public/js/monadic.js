$(function () {
  elemAlert.draggable({ cursor: "move" });

  const backToTop = $("#back_to_top");
  const backToBottom = $("#back_to_bottom");

  // button#broser is disabled when the system has started
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

    if (!apps[$(this).val()]["model"] || apps[$(this).val()]["model"].length === 0) {
      $("#model").prop("disabled", true);
      $("#top-p").prop("disabled", true);
      $("#presence-penalty").prop("disabled", true);
      $("#frequency-penalty").prop("disabled", true);
    } else {
      $("#model").prop("disabled", false);
      $("#top-p").prop("disabled", false);
      $("#presence-penalty").prop("disabled", false);
      $("#frequency-penalty").prop("disabled", false);
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
    audioInit();
    elemError.hide();
    if (checkParams()) {
      params = setParams();
    } else {
      return;
    }
    // $("#paramList").html("").append(listParams(setParams()));
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
    setAlert("Ready to start.", "secondary");

    responseStarted = false;
    callingFunction = false;

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
      ws.send(JSON.stringify({ message: "CHECK_TOKEN", initial: false, contents: $("#api-token").val() }));
    });
  })

  $("#send").on("click", function(event) {
    setAlert("<i class='fas fa-robot'></i> THINKING", "info");
    elemError.hide();
    event.preventDefault();
    if (message.value === "") {
      return;
    }
    params["message"] = $("#message").val();
    if ($("#select-role").val() !== "user") {
      reconnect_websocket(ws, function (ws) {
        const role = $("#select-role").val().split("-")[1];
        const msg_object = { message: "SAMPLE", content: $("#message").val(), role: role}
        console.log(msg_object);
        ws.send(JSON.stringify(msg_object));
      });
      $("#message").css("height", "96px").val("");
      $("#select-role").val("").trigger("change");
    } else {
      reconnect_websocket(ws, function (ws) {
        if(imageData) {
          params.image = { data: imageData, title: imageTitle, type: imageType }
        } else {
          params.image = null;
        }
        ws.send(JSON.stringify(params));
        imageData = null;
        imageTitle = null;
        imageType = null;
      });
      $("#message").css("height", "96px").val("");
      $("#image-used").html("");
      $("#image-base64").html("");
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
          setAlert(`File uploaded successfully.<br /><b>${fileTitle}</b>`, "success");
        }).fail(function(error) {
          $("#file-spinner").hide();
          $("#fileModal button").prop("disabled", false);
          $("#fileModal").modal("hide");
          setAlert(`Error uploading file: ${error}`, "danger");
        }).always(function() {
          console.log('complete');
        });
      } else {
        // if it is not pdf, it is a plain text file 
        // read the contents and store it in a variable
        const reader = new FileReader();
        reader.onload = function(e) {
          $("#fileModal button").prop("disabled", true);
          $("#file-spinner").show();
          const contents = e.target.result;
          fileTitle = $("#file-title").val();
          // if fileTitle is empty, use the file name
          if (fileTitle === "") {
            fileTitle = file.name;
          }
          fileContents = e.target.result;
          fileContents = "\n\nTARGET DOCUMENT: " + fileTitle + "\n\n```\n" + fileContents + "\n```";
          $("#initial-prompt").val($("#initial-prompt").val() + fileContents);
          autoResize($("#initial-prompt"));
        }
        // once the file is read, send the contents to the server
        reader.readAsText(file);
        reader.onloadend = function() {
          $("#fileModal button").prop("disabled", false);
          $("#file-spinner").hide();
          $("#fileModal").modal("hide");
          setAlert(`File contents have been successfully appended to the initial prompt.<br /><b>${fileTitle}</b>`, "success");
        }
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

  $("#message, #initial-prompt").on("input", function() {
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

  const fileFile = $('#fileFile');
  const fileButton = $('#uploadFile');

  fileFile.on('change', function() {
    if (fileFile[0].files.length > 0) {
      fileButton.prop('disabled', false);
    } else {
      fileButton.prop('disabled', true);
    }
  });

  $("#discourse").tooltip({
    selector: '.card-header [title]',
    delay: { show: 0, hide: 0 },
    show: 100
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
    document.getElementById("initial-prompt-toggle").addEventListener("change", function() {
      if (this.checked) {
        $("#initial-prompt").css("display", "");
        autoResize($("#initial-prompt"));
      } else {
        $("#initial-prompt").css("display", "none");
      }
    });
    $("#initial-prompt").css("display", "none");
    $("#initial-prompt-toggle").prop("checked", false);
    adjustScrollButtons();
  });
});
