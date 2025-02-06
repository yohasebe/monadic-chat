// This needs to be included to suppress errors regarding modal dialogs 
document.addEventListener("DOMContentLoaded", function () {
  document.addEventListener('hide.bs.modal', function (event) {
    if (document.activeElement) {
      document.activeElement.blur();
    }
  });
});

$(function () {

  elemAlert.draggable({ cursor: "move" });

  const backToTop = $("#back_to_top");
  const backToBottom = $("#back_to_bottom");

  // button#browser is disabled when the system has started
  $("#browser").prop("disabled", true);

  $("#send, #clear, #voice, #tts-voice, #tts-speed, #asr-lang, #ai-user-initial-prompt-toggle, #ai-user-toggle, #check-auto-speech, #check-easy-submit").prop("disabled", true);

  //////////////////////////////
  // UI event handlers
  //////////////////////////////

  let lastApp = defaultApp;

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
  }

  // Setup optimized event listeners
  function setupEventListeners() {
    const $document = $(document);
    const $main = $("#main");

    // Event delegation for dynamically added elements
    $document.on("click", ".contBtn", function () {
      $("#message").val("Continue");
      $("#send").trigger("click");
    });

    // Add MutationObserver for handling image errors
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.addedNodes.length) {
          mutation.addedNodes.forEach((node) => {
            if (node.nodeType === 1 && node.classList.contains('card')) {
              $(node).find(".generated_image img").each(function() {
                const $img = $(this);

                $img.on("error", function() {
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
      observer.observe(discourseElement, {
        childList: true,
        subtree: true
      });
    }

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
    // Optimize scroll event
    let scrollTimer;
    $main.on("scroll", function () {
      clearTimeout(scrollTimer);
      scrollTimer = setTimeout(adjustScrollButtons, 100);
    });

    // Optimize resize event
    let resizeTimer;
    $(window).on("resize", function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(adjustScrollButtons, 250);
    });
  }

  // Call these functions on document ready
  $(function () {
    setupToggleHandlers();
    setupEventListeners();
  });

  $("#apps").on("change", function (event) {
    if (stop_apps_trigger) {
      stop_apps_trigger = false;
      return
    }

    event.preventDefault();
    if (messages.length > 0) {
      if (this.value === lastApp) {
        return;
      }

      $("#clearConfirmation").modal("show");
      setTimeout(function () {
        $("#clearConfirmed").focus();
      }, 500);

      // if `#clearConfirmed` button is clicked, clear the current conversation
      $("#clearConfirmed").on("click", function () {
        ws.send(JSON.stringify({ "message": "RESET" }));
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
      $("#file-div").show();
      $("#pdf-panel").show();
      ws.send(JSON.stringify({ message: "PDF_TITLES" }));
    } else {
      $("#file-div").hide();
      $("#pdf-panel").hide();
    }

    if (apps[$(this).val()]["image"]) {
      $("#image-file").show();
    } else {
      $("#image-file").hide();
    }

    let model;
    let models = [];

    if (apps[$(this).val()]["models"] && apps[$(this).val()]["models"].length > 0) {
      let models_text = apps[$(this).val()]["models"];
      models = JSON.parse(models_text);
    }

    if (models.length > 0) {
      let openai = apps[$(this).val()]["group"].toLowerCase() === "openai";
      let modelList = listModels(models, openai);
      $("#model").html(modelList);
      model = models[1];
      if (params["model"] && models.includes(params["model"])) {
        model = params["model"];
      }

      $("#model-selected").text(model);
      $("#model").val(model);

      // Manually trigger the change event
      $("#model").trigger("change");
    } else if (!apps[$(this).val()]["model"] || apps[$(this).val()]["model"].length === 0) {
      $("#model_and_file").hide();
      $("#model_parameters").hide();
    } else {
      // The following code is for backward compatibility

      let models_text = apps[$(this).val()]["models"];
      let models = JSON.parse(models_text);
      model = params["model"];

      if (params["model"] && models && models.includes(params["model"])) {
        $("#model").html(model_options);
        $("#model").val(params["model"]);
      } else {
        let model_options = `<option disabled="disabled" selected="selected">Models not available</option>`;
        $("#model").html(model_options);
      }

      $("#model-selected").text(params["model"]);
      $("#model_and_file").show();
      $("#model_parameters").show();

      // Manually trigger the change event
      $("#model").trigger("change");
    }

    if (apps[$(this).val()]["max_tokens"]) {
      $("#max-tokens-toggle").prop("checked", true);
      $("#max-tokens").prop("disabled", false);
    } else {
      $("#max-tokens-toggle").prop("checked", false);
      $("#max-tokens").prop("disabled", true);
    }

    if (apps[$(this).val()]["context_size"]) {
      $("#context-size-toggle").prop("checked", true);
      $("#context-size").prop("disabled", false);
    } else {
      $("#context-size-toggle").prop("checked", false);
      $("#context-size").prop("disabled", true);
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

    if (apps[$(this).val()]["mathjax"]) {
      $("#math-badge").show();
      $("#mathjax").prop("checked", true);
      $("#math-badge").show();
    } else {
      $("#math-badge").hide();
      $("#mathjax").prop("checked", false);
      $("#math-badge").hide();
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

  $("#mathjax").on("change", function () {
    if ($(this).is(":checked")) {
      params["mathjax"] = true;
      $("#math-badge").show();
    } else {
      params["mathjax"] = false;
      $("#math-badge").hide();
    }
  });

  $("#toggle-menu").on("click", function () {
    // toggle shoe/hide menu and adjust main panel width
    if ($("#menu").is(":visible")) {
      $("#main").toggleClass("col-md-8", "col-md-12");
      $("#menu").hide();
    } else {
      $("#main").toggleClass("col-md-8", "col-md-12");
      // show menu after #main width has been fully adjusted
      $("body, html").animate({ scrollTop: 0 }, 0);
      $("#menu").show();
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
      // create secure random 4-digit number
      ws.send(JSON.stringify({
        message: "SYSTEM_PROMPT",
        content: $("#initial-prompt").val(),
        mathjax: $("#mathjax").is(":checked"),
        monadic: params["monadic"],
        jupyter: params["jupyter"],
      }));

      $("#config").hide();
      $("#back-to-settings").show();
      $("#parameter-panel").show();
      $("#main-panel").show();
      $("#discourse").show();

      if (!$("#ai-user-toggle").is(":checked") && $("#initiate-from-assistant").is(":checked")) {
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
    setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
    ttsStop();

    responseStarted = false;
    callingFunction = false;

    // send cancel message to server
    ws.send(JSON.stringify({ message: "CANCEL" }));
    // reset UI
    $("#chat").html("");
    $("#temp-card").hide();
    $("#user-panel").show();
    $("#cancel_query").hide();
    setInputFocus();
  });

  $("#send").on("click", function (event) {
    audioInit();
    setAlert("<i class='fas fa-robot'></i> THINKING", "warning");
    event.preventDefault();
    if (message.value === "") {
      return;
    }
    params = setParams();
    params["message"] = $("#message").val();

    $("#cancel_query").show();
    
    // Hide message input and show spinner
    $("#message").hide();
    $("#monadic-spinner").show();

    if ($("#select-role").val() !== "user") {
      reconnect_websocket(ws, function (ws) {
        const role = $("#select-role").val().split("-")[1];
        const msg_object = { message: "SAMPLE", content: $("#message").val(), role: role }
        ws.send(JSON.stringify(msg_object));
      });
      $("#message").css("height", "96px").val("");
      $("#select-role").val("").trigger("change");
    } else {
      reconnect_websocket(ws, function (ws) {
        // Create a copy of the current images array to preserve the state
        let currentImages = [...images];

        // Add PDF to the array if it exists and isn't already included
        if (currentPdfData && !images.some(img => img.type === 'application/pdf')) {
          currentImages.push(currentPdfData);
        }

        // Set the images parameter for the request
        if (currentImages.length > 0) {
          params.images = currentImages;
        } else {
          params.images = [];
        }

        ws.send(JSON.stringify(params));
        $("#message").css("height", "96px").val("");

        // Update images array and display to maintain PDF attachment
        images = currentPdfData ? [currentPdfData] : [];
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
      let message_obj = {"role": message.role, "text": message.text, "mid": message.mid};
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
    $("#loadModal").modal("show");
    setTimeout(function () {
      $("#file-load").focus();
    }, 500);
  });

  $("#loadModal").on("shown.bs.modal", function () {
    $("#file-title").focus();
  });

  $("#file").on("click", function (event) {
    event.preventDefault();
    $("#file-title").val("");
    $("#fileFile").val("");
    $("#fileModal").modal("show");
  });

  let fileTitle = "";

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
        }).done(function (_filename) {
          $("#file-spinner").hide();
          $("#fileModal button").prop('disabled', false);
          $("#fileModal").modal("hide");
          ws.send(JSON.stringify({ message: "PDF_TITLES" }));
          setAlert("<i class='fa-solid fa-circle-check'></i> File uploaded successfully", "success");
        }).fail(function (error) {
          $("#file-spinner").hide();
          $("#fileModal button").prop("disabled", false);
          $("#fileModal").modal("hide");
          setAlert(`Error uploading file: ${error}`, "error");
        }).always(function () {
          console.log('complete');
        });
      }
    } else {
      alert("Please select a PDF file to upload");
    }
  });

  $("#doc").on("click", function (event) {
    event.preventDefault();
    $("#docLabel").val("");
    $("#docFile").val("");
    $("#docModal").modal("show");
    setTimeout(() => {
      $("#docFile").focus();
    }, 500);
  });

  $("#docModal").on("hidden.bs.modal", function () {
    $('#docFile').val('');
    $('#convertDoc').prop('disabled', true);
  });

  $("#docFile").on("change", function() {
    const file = this.files[0];
    $('#convertDoc').prop('disabled', !file);
  });

  $("#convertDoc").on("click", function () {
    const docInput = $("#docFile")[0];
    const doc = docInput.files[0];

    if (doc) {
      // check if the file is a doc file (pdf, docx, xlsx, pptx, and any text-based file such as rb, py, etc.)
      if (doc.type !== "application/octet-stream") {
        const docLabel =$("#docaLabel").val() || ""
        $("#docModal button").prop("disabled", true);
        $("#doc-spinner").show();
        const formData = new FormData();
        formData.append("docFile", doc);
        formData.append("docLabel", docLabel);

        $.ajax({
          url: "/document",
          type: "POST",
          data: formData,
          processData: false,
          contentType: false
        }).done(function (markdown) {
          const message = $("#message").val().replace(/\n+$/, "");
          $("#message").val(`${message}\n\n${markdown}`);
          $("#doc-spinner").hide();
          $("#docModal button").prop('disabled', false);
          $("#docModal").modal("hide");
          // $("#select-role").val("sample-system").trigger("change");
          autoResize($("#message"));
          $("#back_to_bottom").trigger("click");
          $("#message").focus();
        }).fail(function (error) {
          $("#doc-spinner").hide();
          $("#fdocModal button").prop("disabled", false);
          $("#docModal").modal("hide");
          setAlert(`Error converting file: ${error}`, "error");
        }).always(function () {
          // console.log('complete');
        });
      }
    } else {
      alert("Please select a document file to convert");
    }
  });

  $("#url").on("click", function (event) {
    event.preventDefault();
    $("#urlLabel").val("");
    $("#pageURL").val("");
    $("#urlModal").modal("show");
    // sleep 1 second before focusing on the input field
    setTimeout(() => {
      $("#pageURL").focus();
    }, 500);
  });

  $("#urlModal").on("hidden.bs.modal", function () {
    $('#pageURL').val('');
    $('#fetchPage').prop('disabled', true);
  });

  $("#pageURL").on("change keyup input", function() {
    const url = this.value;
    // check if url is a valid url starting with http or https
    const validUrl = url.match(/^(http|https):\/\/[^ "]+$/);
    $('#fetchPage').prop('disabled', !validUrl);
  });

  $("#fetchPage").on("click", function () {
    const url = $("#pageURL").val();

    if (url) {
      const urlLabel =$("#urlLabel").val() || ""
      $("#urlModal button").prop("disabled", true);
      $("#url-spinner").show();
      const formData = new FormData();
      formData.append("pageURL", url);
      formData.append("urlLabel", urlLabel);

      $.ajax({
        url: "/fetch_webpage",
        type: "POST",
        data: formData,
        processData: false,
        contentType: false
      }).done(function (markdown) {
        const message = $("#message").val().replace(/\n+$/, "");
        $("#message").val(`${message}\n\n${markdown}`);
        $("#url-spinner").hide();
        $("#urlModal button").prop('disabled', false);
        $("#urlModal").modal("hide");
        autoResize($("#message"));
        $("#back_to_bottom").trigger("click");
        $("#message").focus();
      }).fail(function (error) {
        $("#url-spinner").hide();
        $("#urlModal button").prop("disabled", false);
        $("#urlModal").modal("hide");
        setAlert(`Error converting file: ${error}`, "error");
      }).always(function () {
        // console.log('complete');
      });
    } else {
      alert("Please specify the URL of the page to fetch");
    }
  });

  $("#temperature").on("input", function () {
    $("#temperature-value").text(parseFloat($(this).val()).toFixed(1));
  });

  $("#top-p").on("input", function () {
    $("#top-p-value").text(parseFloat($(this).val()).toFixed(1));
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

  backToTop.click(function (e) {
    e.preventDefault();
    $("#main").animate({ scrollTop: 0 }, 500);
  });

  backToBottom.click(function (e) {
    e.preventDefault();
    $("#main").animate({ scrollTop: $("#main").prop("scrollHeight") }, 500);
  });

  resetParams();

  $("#tts-provider").on("change", function () {
    params["tts_provider"] = $("#tts-provider option:selected").val();
    // show/hide #xi-voices and hide #openai-voices based on the selected provider
    if (params["tts_provider"] === "xi") {
      $("#xi-voices").show();
      $("#openai-voices").hide();
    } else if (params["tts_provider"] === "openai") {
      $("#xi-voices").hide();
      $("#openai-voices").show();
    }

    setCookie("userProvider", params["tts_provider"], 30);
  });

  $("#tts-voice").on("change", function () {
    params["tts_voice"] = $("#tts-voice option:selected").val();
    setCookie("userVoice", params["tts_voice"], 30);
  });

  $("#xi-tts-voice").on("change", function () {
    params["xi_tts_voice"] = $("#xi-tts-voice option:selected").val();
    setCookie("userXIVoice", params["xi_tts_voice"], 30);
  });

  $("#asr-lang").on("change", function () {
    params["asr_lang"] = $("#asr-lang option:selected").val();
    setCookie("asrLang", params["asr-lang"], 30);
  });

  $("#tts-speed").on("input", function () {
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

  $("#message, #initial-prompt, #ai-user-initial-prompt").on("input", function () {
    if (message.dataset.ime !== "true") {
      autoResize($(this));
    }
  });

  $("#initial-prompt-toggle").on("change", function () {
    if (this.checked) {
      $("#initial-prompt").css("display", "");
      autoResize($("#initial-prompt"));
    } else {
      $("#initial-prompt").css("display", "none");
    }
  });

  $("#ai-user-initial-prompt-toggle").on("change", function () {
    if (this.checked) {
      $("#ai-user-initial-prompt").css("display", "");
      autoResize($("#ai-user-initial-prompt"));
    } else {
      $("#ai-user-initial-prompt").css("display", "none");
    }
  });

  if (!runningOnChrome && !runningOnEdge) {
    voiceButton.hide();
    $("#auto-speech").hide();
    $("#auto-speech-form").hide();
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

  // loadButton click event handler
  loadButton.on('click', function () {
    $("#monadic-spinner").show();
  });

  fileInput.on('change', function () {
    if (fileInput[0].files.length > 0) {
      loadButton.prop('disabled', false);
    } else {
      loadButton.prop('disabled', true);
    }
  });

  const fileFile = $('#fileFile');
  const fileButton = $('#uploadFile');

  fileFile.on('change', function () {
    if (fileFile[0].files.length > 0) {
      fileButton.prop('disabled', false);
    } else {
      fileButton.prop('disabled', true);
    }
  });

  $("#model").on("change", function() {
    const selectedModel = $("#model").val();

    // check if selected mode has data-model-type attribute and its value is "reasoning"
    const modelType = $("#model option:selected").attr("data-model-type");
    if (modelType && modelType === "reasoning") {
      const reasoningEffort = $("#reasoning-effort").val();
      $("#model-selected").text(selectedModel + " (" + reasoningEffort + ")");
    } else {
      $("#model-selected").text(selectedModel);
    }
    adjustImageUploadButton(selectedModel);
  });

  $("#reasoning-effort").on("change", function () {
    const selectedModel = $("#model").val();
    const modelType = $("#model option:selected").attr("data-model-type");
    if (modelType && modelType === "reasoning") {
      const reasoningEffort = $("#reasoning-effort").val();
      $("#model-selected").text(selectedModel + " (" + reasoningEffort + ")");
    }
  });

  $("#discourse").tooltip({
    selector: '.card-header [title]',
    delay: { show: 0, hide: 0 },
    show: 100
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
    adjustScrollButtons();
    $("#monadic-spinner").show();
  });
});
