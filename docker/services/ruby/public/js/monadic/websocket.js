/////////////////////////////
// set up the websocket
//////////////////////////////

let ws = connect_websocket();
let model_options;
let initialLoadComplete = false; // Flag to track initial load

// OpenAI API token verification
let verified = null;

// message is submitted upon pressing enter
const message = $("#message")[0];

message.addEventListener("compositionstart", function () {
  message.dataset.ime = "true";
});

message.addEventListener("compositionend", function () {
  message.dataset.ime = "false";
});

document.addEventListener("keydown", function (event) {
  if ($("#check-easy-submit").is(":checked") && !$("#message").is(":focus") && event.key === "ArrowRight") {
    event.preventDefault();
    if ($("#voice").prop("disabled") === false) {
      $("#voice").click();
    }
  }
});

message.addEventListener("keydown", function (event) {
  if ($("#check-easy-submit").is(":checked") && (event.key === "Enter") && message.dataset.ime !== "true") {
    event.preventDefault();
    $("#send").click();
  }
});

// Function to handle visibility change
function handleVisibilityChange() {
  if (document.hidden) {
    // If the document is not visible, close the WebSocket connection
    // ws.close();
  } else {
    // If the document becomes visible again, you can reconnect the WebSocket if needed
    // Make sure to check if the socket is already connected before attempting to reconnect
    if (ws.readyState === WebSocket.CLOSED) {
      ws = connect_websocket();
    }
  }
}

// Set the copy code button for each code block
function setCopyCodeButton(element) {
  // check element if it exists
  if (!element) {
    return;
  }
  element.find("div.card-text pre > code").each(function () {
    const codeElement = $(this);
    const copyButton = `<div class="copy-code-button"><i class="fa-solid fa-copy"></i></div>`;
    codeElement.after(copyButton);
    codeElement.next().click(function () {
      const text = codeElement.text();
      navigator.clipboard.writeText(text).then(function () {
        codeElement.next().find("i").removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
        setTimeout(function () {
          codeElement.next().find("i").removeClass("fa-check").addClass("fa-copy").css("color", "");
        }, 1000);
      });
    });
  });
}

// Add event listener for visibility change
document.addEventListener('visibilitychange', handleVisibilityChange);

//////////////////////////////
// WebSocket event handlers
//////////////////////////////

const apps = {}
let messages = [];
let originalParams = {};
let params = {}

let reconnectDelay = 1000;

let pingInterval;

function startPing() {
  if (pingInterval) {
    clearInterval(pingInterval);
  }
  pingInterval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ message: 'PING' }));
    }
  }, 30000);
}

function stopPing() {
  if (pingInterval) {
    clearInterval(pingInterval);
  }
}

const chatBottom = $("#chat-bottom").get(0);
let autoScroll = true;
/* exported autoScroll */

const mainPanel = $("#main-panel").get(0);
const defaultApp = "Chat";

function isElementInViewport(element) {
  // Convert the jQuery element to a native DOM element
  // Get the element's bounding rectangle
  const rect = element.getBoundingClientRect();

  // Check if the element is within the viewport
  return (
    rect.top >= 0 &&
    rect.left >= 0 &&
    rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
    rect.right <= (window.innerWidth || document.documentElement.clientWidth)
  );
}

function applyMathJax(element) {

  // do the following only outside <div class="diagram"> elements
  if (element.hasClass("diagram")) {
    return;
  }

  if (typeof MathJax === 'undefined') {
    console.error('MathJax is not loaded. Please make sure to include the MathJax script in your HTML file.');
    return;
  }

  // Get the DOM element from the jQuery object
  let domElement = element.get(0);

  // Typeset the element using MathJax
  MathJax.typesetPromise([domElement])
    .then(() => {
      // console.log('MathJax element re-rendered successfully.');
    })
    .catch((err) => {
      console.error('Error re-rendering MathJax element:', err);
    });
}

const mermaid_config = {
  startOnLoad: true,
  securityLevel: 'strict',
  theme: 'default'
};

$(document).on("click", ".copy-button", function () {
  const codeElement = $(this).prev().find("code");
  const text = codeElement.text();
  navigator.clipboard.writeText(text).then(function () {
    $(this).find("i").removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
    setTimeout(function () {
      $(this).find("i").removeClass("fa-check").addClass("fa-copy").css("color", "");
    }, 1000);
  }, function () {
    $(this).find("i").removeClass("fa-copy").addClass("fa-times").css("color", "#DC4C64");
    setTimeout(function () {
      $(this).find("i").removeClass("fa-times").addClass("fa-copy").css("color", "");
    }, 1000);
  });
});

async function applyMermaid(element) {
  // Initialize mermaid with configuration
  mermaid.initialize(mermaid_config);

  // Process each mermaid code block
  element.find(".mermaid-code").each(function (index) {
    const mermaidElement = $(this);
    mermaidElement.addClass("sourcecode");
    mermaidElement.find("pre").addClass("sourcecode");
    let mermaidText = mermaidElement.text().trim();
    mermaidElement.find("pre").text(mermaidText);
    addToggleSourceCode(mermaidElement, "Toggle Mermaid Diagram");

    // Create container for diagram and error message
    const containerId = `diagram-${index}`;
    const diagramContainer = $(`<div class="diagram-wrapper">
      <div class="diagram" id="${containerId}"><mermaid>${mermaidText}</mermaid></div>
      <div class="error-message" id="error-${containerId}" style="display: none;"></div>
    </div>`);
    mermaidElement.after(diagramContainer);

    // Validate mermaid syntax
    try {
      const type = mermaid.detectType(mermaidText);
      if (!type) {
        throw new Error("Invalid diagram type");
      }
    } catch (error) {
      const errorElement = diagramContainer.find(`#error-${containerId}`);
      errorElement.html(`<div class="alert alert-danger">
        <strong>Mermaid Syntax Error:</strong><br>
        ${error.message}
      </div>`).show();
      diagramContainer.find('.diagram').hide();
    }
  });

  // Render valid diagrams
  try {
    await mermaid.run({
      querySelector: 'mermaid'
    });
  } catch (error) {
    console.error('Mermaid rendering error:', error);
  }

  // Add download functionality
  element.find(".diagram").each(function (index) {
    const diagram = $(this);
    if (diagram.is(':visible')) {  // Only add download button for successfully rendered diagrams
      const downloadButton = $('<div class="mb-3"><button class="btn btn-secondary btn-sm">Download SVG</button></div>');
      downloadButton.on('click', function () {
        const svgElement = diagram.find('svg')[0];
        if (svgElement) {
          const serializer = new XMLSerializer();
          const source = serializer.serializeToString(svgElement);
          const blob = new Blob([source], { type: 'image/svg+xml;charset=utf-8' });
          const url = URL.createObjectURL(blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = `diagram-${index + 1}.svg`;
          document.body.appendChild(a);
          a.click();
          document.body.removeChild(a);
          URL.revokeObjectURL(url);
        }
      });
      diagram.after(downloadButton);
    }
  });
}

function abcCursorControl(element_id) {
  var self = this;

  self.onStart = function () {
    var svg = document.querySelector(`${element_id} svg`);
    var cursor = document.createElementNS("http://www.w3.org/2000/svg", "line");
    cursor.setAttribute("class", "abcjs-cursor");
    cursor.setAttributeNS(null, 'x1', 0);
    cursor.setAttributeNS(null, 'y1', 0);
    cursor.setAttributeNS(null, 'x2', 0);
    cursor.setAttributeNS(null, 'y2', 0);
    svg.appendChild(cursor);

  };
  self.beatSubdivisions = 2;
  self.onEvent = function (ev) {
    if (ev.measureStart && ev.left === null)
      return; // this was the second part of a tie across a measure line. Just ignore it.

    var lastSelection = document.querySelectorAll(`${element_id} svg .highlight`);
    for (var k = 0; k < lastSelection.length; k++)
      lastSelection[k].classList.remove("highlight");

    for (var i = 0; i < ev.elements.length; i++) {
      var note = ev.elements[i];
      for (var j = 0; j < note.length; j++) {
        note[j].classList.add("highlight");
      }
    }

    var cursor = document.querySelector(`${element_id} svg .abcjs-cursor`);
    if (cursor) {
      cursor.setAttribute("x1", ev.left - 2);
      cursor.setAttribute("x2", ev.left - 2);
      cursor.setAttribute("y1", ev.top);
      cursor.setAttribute("y2", ev.top + ev.height);
    }
  };
  self.onFinished = function () {
    var els = document.querySelectorAll("svg .highlight");
    for (var i = 0; i < els.length; i++) {
      els[i].classList.remove("highlight");
    }
    var cursor = document.querySelector(`${element_id} svg .abcjs-cursor`);
    if (cursor) {
      cursor.setAttribute("x1", 0);
      cursor.setAttribute("x2", 0);
      cursor.setAttribute("y1", 0);
      cursor.setAttribute("y2", 0);
    }
  };
}

function abcClickListener(abcElem, tuneNumber, classes, analysis, drag, mouseEvent) {
  var lastClicked = abcElem.midiPitches;
  if (!lastClicked)
    return;

  ABCJS.synth.playEvent(lastClicked, abcElem.midiGraceNotePitches);
}

function applyToggle(element, nl2br = false) {
  // return if element is already applied with toggle
  if (element.find(".sourcecode-toggle").length > 0) {
    return;
  }
  element.find(".toggle").each(function () {
    const toggleElement = $(this);
    toggleElement.addClass("sourcecode");
    toggleElement.find("pre").addClass("sourcecode");

    if (nl2br) {
      let toggleText = toggleElement.text().trim().replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, "&nbsp;");
      toggleElement.find("pre").text(toggleText);
    }
    addToggleSourceCode(toggleElement, toggleElement.data("label"));
  });
}

function addToggleSourceCode(element, title = "Toggle Show/Hide") {
  // if element has data-title attribute, use that as the title
  if (element.data("title")) {
    title = element.data("title");
  }
  const toggleHide = `<i class='fa-solid fa-toggle-on'></i> ${title}`
  const toggleShow = `<i class='fa-solid fa-toggle-off'></i> ${title}`
  const controlDiv = `<div class="sourcecode-toggle unselectable">${toggleShow}</div>`;
  element.before(controlDiv);
  element.prev().click(function () {
    const sourcecode = $(this).next();
    sourcecode.toggle();
    if (sourcecode.is(":visible")) {
      $(this).html(toggleHide);
    } else {
      $(this).html(toggleShow);
    }
  });
  element.hide();
}

function formatSourceCode(element) {
  element.find(".sourcecode").each(function () {
    const sourceCodeElement = $(this);
    let sourceCode = sourceCodeElement.text().trim();
    sourceCodeElement.find("code").text(sourceCode);
  })
}

function applyAbc(element) {
  element.find(".abc-code").each(function () {
    $(this).addClass("sourcecode");
    $(this).find("pre").addClass("sourcecode");
    const abcElement = $(this);
    const abcId = `${Date.now()}`;
    let abcText = abcElement.find("pre").text().trim();
    abcText = abcText.split("\n").map((line) => line.trim()).join("\n");
    let instrument = "";
    const instrumentMatch = abcText.match(/^%%tablature\s+(.*)/);
    if (instrumentMatch) {
      instrument = instrumentMatch[1];
    }

    abcElement.find("pre").text(abcText);
    const abcSVG = `abc-svg-${abcId}`;
    const abcMidi = `abc-midi-${abcId}`;
    addToggleSourceCode(abcElement, "Toggle ABC Notation");
    abcElement.after(`<div>&nbsp;</div>`);
    abcElement.after(`<div id="${abcMidi}" class="abc-midi"></div>`);
    abcElement.after(`<div id="${abcSVG}" class="abc-svg"></div>`);
    const abcOptions = {
      add_classes: true,
      clickListener: self.abcClickListener,
      responsive: "resize",
      soundfont: "https://paulrosen.github.io/midi-js-soundfonts/FluidR3_GM/",
      format: {
        titlefont: '"itim-music,Itim" 16',
        gchordfont: '"itim-music,Itim" 10',
        vocalfont: '"itim-music,Itim" 10',
        annotationfont: '"itim-music,Itim" 10',
        composerfont: '"itim-music,Itim" 10',
        partsfont: '"itim-music,Itim" 10',
        tempoFont: '"itim-music,Itim" 10',
        wordsfont: '"itim-music,Itim" 10',
        infofont: '"itim-music,Itim" 10',
        tablabelfont: "Helvetica 10 box",
        tabnumberfont: "Times 10",
        dynamicVAlign: false,
        dynamicHAlign: false
      }
    };
    if (instrument === "violin" || instrument === "mandolin" || instrument === "fiddle" || instrument === "guitar" || instrument === "fiveString") {
      abcOptions.tablature = [{ instrument: instrument }];
    } else if (instrument === "bass") {
      abcOptions.tablature = [{ instrument: "bass", label: "Base (%T)", tuning: ["E,", "A,", "D", "G"] }]
    }
    const visualObj = ABCJS.renderAbc(abcSVG, abcText, abcOptions)[0];
    if (ABCJS.synth.supportsAudio()) {
      const synthControl = new ABCJS.synth.SynthController();
      const cursorControl = new abcCursorControl(`#${abcSVG}`);
      synthControl.load(`#${abcMidi}`, cursorControl, {
        displayLoop: true,
        displayRestart: true,
        displayPlay: true,
        displayProgress: true,
        displayWarp: true
      });
      synthControl.setTune(visualObj, false, {});

    } else {
      document.querySelector(abcMidi).innerHTML = "<div class='audio-error'>Audio is not supported in this browser.</div>";
    }
  })
}

let mediaSource = null;
let audio = null;
let sourceBuffer = null;
let audioDataQueue = [];

function processAudioDataQueue() {
  if (mediaSource.readyState === 'open' && audioDataQueue.length > 0 && sourceBuffer && !sourceBuffer.updating) {
    const audioData = audioDataQueue.shift();
    try {
      sourceBuffer.appendBuffer(audioData);
    } catch (e) {
      console.error('Error appending buffer:', e);
    }
  }
}

let responseStarted = false;
let callingFunction = false;

function connect_websocket(callback) {
  const ws = new WebSocket('ws://localhost:4567');

  let loadedApp = "Chat";
  let infoHtml = "";

  ws.onopen = function () {
    // console.log('WebSocket connected');
    setAlert("<i class='fa-solid fa-bolt'></i> Verifying token . . .", "warning");
    ws.send(JSON.stringify({ message: "CHECK_TOKEN", initial: true, contents: $("#token").val() }));

    if (!mediaSource) {
      mediaSource = new MediaSource();
      mediaSource.addEventListener('sourceopen', () => {
        // console.log('MediaSource opened');
        if (runningOnFirefox) {
          sourceBuffer = mediaSource.addSourceBuffer('audio/mp4; codecs="mp4a.40.2"');
        } else {
          sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
        }
        sourceBuffer.addEventListener('updateend', processAudioDataQueue);
      });
    }

    if (!audio) {
      audio = new Audio();
      audio.src = URL.createObjectURL(mediaSource);
    }

    if (!verified) {
      setAlert("<i class='fa-solid fa-bolt'></i> Verifying token . . .", "warning");
      ws.send(JSON.stringify({ message: "CHECK_TOKEN", initial: true, contents: $("#token").val() }));
    }

    // check verified at a regular interval
    let verificationCheckTimer = setInterval(function () {
      if (verified) {
        if (!initialLoadComplete) {  // Only send LOAD on initial connection
          ws.send(JSON.stringify({ "message": "LOAD" }));
          initialLoadComplete = true; // Set the flag after the initial load
        }
        startPing();
        if (callback) {
          callback(ws);
        }
        clearInterval(verificationCheckTimer);
      }
    }, 1000);
  }

  function updateAppAndModelSelection(parameters) {
    if (parameters.app_name) {
      $("#apps").val(parameters.app_name).trigger('change');
    }
    if (parameters.model) {
      $("#model").val(parameters.model).trigger('change');
    }
  }

  // Helper function to append a card to the discourse
  function appendCard(role, badge, html, lang, mid, status, images) {
    const htmlElement = createCard(role, badge, html, lang, mid, status, images);
    $("#discourse").append(htmlElement);
    updateItemStates();

    const htmlContent = $("#discourse div.card:last");

    if (params["toggle"] === "true") {
      applyToggle(htmlContent);
    }

    if (params["mermaid"] === "true") {
      applyMermaid(htmlContent);
    }

    if (params["mathjax"] === "true") {
      applyMathJax(htmlContent);
    }

    if (params["abc"] === "true") {
      applyAbc(htmlContent);
    }

    if (params["sourcecode"] === "true") {
      formatSourceCode(htmlContent);
    }

    setCopyCodeButton(htmlContent);
  }

  // Helper function to display an error message
  function displayErrorMessage(message) {
    if (message === "") {
      message = "Something went wrong.";
    }
    console.log("Error message:", message);
    setAlert(message, "error");
  }

  ws.onmessage = function (event) {
    const data = JSON.parse(event.data);
    switch (data["type"]) {
      case "wait": {
        callingFunction = true;
        setAlert(data["content"], "warning");
        break;
      }

      case "audio": {
        $("#monadic-spinner").hide();

        const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));
        audioDataQueue.push(audioData);
        processAudioDataQueue();
        break;
      }

      case "pong": {
        // console.log("Received PONG");
        break;
      }

      case "error": {
        $("#send, #clear, #voice").prop("disabled", false);
        $("#alert-message").html("Input a message.");
        $("#temp-card").hide();
        $("#indicator").hide();
        $("#user-panel").show();
        $("#cancel_query").hide();
        
        // Show message input and hide spinner
        $("#message").show();
        $("#monadic-spinner").hide();

        const lastCard = $("#discourse .card").last();
        if (lastCard.find(".user-color").length !== 0) {
          deleteMessage(lastCard.attr('id'));
        }

        $("#message").val(params["message"]);
        displayErrorMessage(data["content"]);
        setInputFocus();
        break;
      }

      case "token_verified": {
        $("#api-token").val(data["token"]);
        $("#ai-user-initial-prompt").val(data["ai_user_initial_prompt"]);

        if (!verified) {
          // Array of strings to identify beta models
          const regularModelPatterns = [/^gpt-4o/];
          const betaModelPatterns = [/^o1/];

          // Separate regular models and beta models
          const regularModels = [];
          const betaModels = [];
          const otherModels = [];

          data['models'].forEach(model => {
            if (regularModelPatterns.some(pattern => pattern.test(model))) {
              regularModels.push(model);
            } else if (betaModelPatterns.some(pattern => pattern.test(model))) {
              betaModels.push(model);
            } else {
              otherModels.push(model);
            }
          });

          // Combine regular models and beta models to generate options
          model_options = [
            '<option disabled>──gpt-4o──</option>',
            ...regularModels.map(model =>
              `<option value="${model}">${model}</option>`
            ),
            '<option disabled>──o1──</option>',
            ...betaModels.map(model =>
              `<option value="${model}">${model}</option>`
            ),
            '<option disabled>──other──</option>',
            ...otherModels.map(model =>
              `<option value="${model}">${model}</option>`
            )
          ].join('');

          $("#model").html(model_options);
          $("#model").val(DEFAULT_MODEL);
          $("#model-selected").text(DEFAULT_MODEL);
        }

        verified = "full";
        setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");

        $("#start").prop("disabled", false);
        $("#send, #clear, #voice, #tts-voice, #tts-speed, #asr-lang, #ai-user-initial-prompt-toggle, #ai-user-toggle, #check-auto-speech, #check-easy-submit").prop("disabled", false);

        // console.log("Token verified");

        break;
      }

      case "open_ai_api_error": {
        verified = "partial";

        $("#start").prop("disabled", false);
        $("#send, #clear").prop("disabled", false);

        // console.log("OpenAI API error");
        $("#api-token").val("");

        setAlert("<i class='fa-solid fa-bolt'></i> Cannot connect to OpenAI API", "warning");
        break;
      }
      case "token_not_verified": {

        verified = "partial";

        $("#start").prop("disabled", false);
        $("#send, #clear").prop("disabled", false);

        // console.log("Token not verified");
        $("#api-token").val("");

        setAlert("<i class='fa-solid fa-bolt'></i> Valid OpenAI token not set", "warning");
        break;
      }
      case "apps": {
        let version_string = data["version"]
        data["docker"] ? version_string += " (Docker)" : version_string += " (Local)"
        $("#monadic-version-number").html(version_string);
        
        if (Object.keys(apps).length === 0) {
          // Prepare arrays for app classification
          let regularApps = [];
          let specialApps = {};

          // Classify apps into regular and special groups
          for (const [key, value] of Object.entries(data["content"])) {
            const group = value["group"];
            
            // Check if app belongs to special group
            if (group && group.trim() !== "" && ["Regular", "OpenAI"].includes(group.trim())) {
              regularApps.push([key, value]);
            } else if (group && group.trim() !== "") {
              if (!specialApps[group]) {
                specialApps[group] = [];
              }
              specialApps[group].push([key, value]);
            } else {
              // create a group called "Extra" for apps without a group
              if (!specialApps["Extra"]) {
                specialApps["Extra"] = [];
              }
              specialApps["Extra"].push([key, value]);
            }
          }

          // Sort regular apps alphabetically
          regularApps.sort((a, b) => a[1]["app_name"].localeCompare(b[1]["app_name"]));

          // Sort apps within each special group alphabetically
          for (const group of Object.keys(specialApps)) {
            specialApps[group].sort((a, b) => a[1]["app_name"].localeCompare(b[1]["app_name"]));
          }

          // Add apps to selector
          // First add the OpenAI Apps label and regular apps
          if (verified === "full") {
            $("#apps").append('<option disabled>──OpenAI──</option>');
            for (const [key, value] of regularApps) {
              apps[key] = value;
              $("#apps").append(`<option value="${key}">${value["app_name"]}</option>`);
            }
          }

          // sort specialApps by group name in the order:
          // "Anthropic", "Google", "Cohere", "Mistral", "Extra"
          // and set it to the specialApps object
          specialApps = Object.fromEntries(Object.entries(specialApps).sort((a, b) => {
            const order = ["Anthropic", "xAI Grok", "Google", "Cohere", "Mistral", "Extra"];
            return order.indexOf(a[0]) - order.indexOf(b[0]);
          }));

          // Add special groups with their labels
          for (const group of Object.keys(specialApps)) {
            if (specialApps[group].length > 0) {
              $("#apps").append(`<option disabled>──${group}──</option>`);
              for (const [key, value] of specialApps[group]) {
                apps[key] = value;
                $("#apps").append(`<option value="${key}">${value["app_name"]}</option>`);
              }
            }
          }

          // select the first option item in the #apps dropdown that is not disabled
          $("#apps").val($("#apps option:eq(1)").val()).trigger('change')

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

          if ($("#apps").val() === "PDF") {
            ws.send(JSON.stringify({ message: "PDF_TITLES" }));
          }
        }
        originalParams = apps["Chat"];
        resetParams();
        break;
      }
      case "parameters": {
        loadedApp = data["content"]["app_name"];
        setAlert("<i class='fa-solid fa-hourglass-half'></i> Please wait . . .", "warning");
        loadParams(data["content"], "loadParams");
        const currentApp = apps[$("#apps").val()] || apps[defaultApp];

        if (currentApp["models"] && currentApp["models"].length > 0) {
          let models_text = currentApp["models"]
          let models = JSON.parse(models_text);
          let modelList = listModels(models);
          $("#model").html(modelList);
          let model = currentApp["models"][0];
          if (currentApp["model"] && models.includes(currentApp["model"])) {
            model = currentApp["model"];
          }
          $("#model-selected").text(model);
          $("#model").val(model);
        }

        $("#base-app-title").text(currentApp["app_name"]);
        $("#base-app-icon").html(currentApp["icon"]);
        if (currentApp["monadic"]) {
          $("#monadic-badge").show();
        } else {
          $("#monadic-badge").hide();
        }
        if (currentApp["tools"]) {
          $("#tools-badge").show();
        } else {
          $("#tools-badge").hide();
        }
        $("#base-app-desc").html(currentApp["description"]);
        $("#start").focus();

        updateAppAndModelSelection(data["content"]);
        break;
      }
      case "whisper": {
        $("#message").val($("#message").val() + " " + data["content"]);
        let logprob = "Last ASR p-value: " + data["logprob"];
        $("#asr-p-value").text(logprob);
        $("#send, #clear, #voice").prop("disabled", false);
        if ($("#check-easy-submit").is(":checked")) {
          $("#send").click();
        }
        setAlert("<i class='fa-solid fa-circle-check'></i> Voice recognition finished", "secondary");
        setInputFocus()
        break;
      }
      case "info": {
        infoHtml = formatInfo(data["content"]);
        if (infoHtml !== "") {
          setStats(infoHtml);
        }

        if ($("#apps option").length === 0) {
          setAlert("<i class='fa-solid fa-bolt'></i> Valid API token not set", "warning");
        } else {
          setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
        }

        $("#monadic-spinner").hide();
        break;
      }
      case "pdf_titles": {
        const pdf_table = "<div class='like-h6'><i class='fas fa-file-pdf'></i> Uploaded PDF</div>" +
          "<table class='table mt-1 mb-3'><tbody>" +
          data["content"].map((title, index) => {
            return `<tr><td>${title}</td><td class="align-middle text-end"><button id='pdf-del-${index}' type='button' class='btn btn-sm btn-secondary'><i class='fas fa-trash'></i></button></td></tr>`;
          }).join("") +
          "</tbody></table>";
        $("#pdf-titles").html(pdf_table);
        data["content"].map((title, index) => {
          $(`#pdf-del-${index}`).click(function () {
            $("#pdfDeleteConfirmation").modal("show");
            $("#pdfToDelete").text(title);
            $("#pdfDeleteConfirmed").on("click", function (event) {
              event.preventDefault();
              ws.send(JSON.stringify({ message: "DELETE_PDF", contents: title }));
              $("#pdfDeleteConfirmation").modal("hide");
              $("#pdfToDelete").text("");
            });
          });
        })
        break
      }
      case "pdf_deleted": {
        if (data["res"] === "success") {
          setAlert(`<i class='fa-solid fa-circle-check'></i> ${data["content"]}`, "info");
        } else {
          setAlert(data["content"], "error");
        }
        ws.send(JSON.stringify({ "message": "PDF_TITLES" }));
        break;
      }
      case "change_status": {
        // change the status of each of the cards according to the data content
        // if the active status of the card is changed, add or remove "active" class from the child span containing "status" class
        data["content"].forEach((msg) => {
          const card = $(`#${msg["mid"]}`);
          if (card.length) {
            if (msg["active"]) {
              card.find(".status").addClass("active");
            } else {
              card.find(".status").removeClass("active");
            }
          }
        });
        break;
      }
      case "past_messages": {
        messages.length = 0;
        $("#discourse").empty();

        data["content"].forEach((msg, index) => {
          if (mids.has(msg["mid"])) {
            return;
          }

          messages.push(msg);

          if (index === 0 && msg["role"] === "system") {
            return;
          }

          switch (msg["role"]) {
            case "user": {
              let msg_text = msg["text"].trim()

              if (msg_text.startsWith("{") && msg_text.endsWith("}")) {
                const json = JSON.parse(msg_text);
                msg_text = json.message;
              }
              msg_text = msg_text.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, " ");

              let images
              if (msg["images"] !== undefined) {
                images = msg["images"]
              } else {
                images = []
              }
              const userElement = createCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + msg_text + "</p>", msg["lang"], msg["mid"], msg["active"], images);
              $("#discourse").append(userElement);
              break;
            }
            case "assistant": {
              const gptElement = createCard("assistant", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>", msg["html"], msg["lang"], msg["mid"], msg["active"]);
              $("#discourse").append(gptElement);

              const htmlContent = $("#discourse div.card:last");

              if (apps[loadedApp]["toggle"] === "true") {
                applyToggle(htmlContent);
              }

              if (apps[loadedApp]["mermaid"] === "true") {
                applyMermaid(htmlContent);
              }

              if (apps[loadedApp]["mathjax"] === "true") {
                applyMathJax(gptElement);
              }

              if (apps[loadedApp]["abc"] === "true") {
                applyAbc(gptElement);
              }

              if (apps[loadedApp]["sourcecode"] === "true") {
                formatSourceCode(gptElement);
              }

              setCopyCodeButton(gptElement);

              break;
            }
            case "system": {
              const systemElement = createCard("system", "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 text-success'>System</span>", msg["html"], msg["lang"], msg["mid"], msg["active"]);
              $("#discourse").append(systemElement);
              break;
            }
          }

          mids.add(msg["mid"]);
        });
        setStats(formatInfo(data["content"]), "info");

        if (messages.length > 0) {
          $("#start-label").text("Continue Session");
        } else {
          $("#start-label").text("Start Session");
        }

        // After loading past messages, set initialLoadComplete to true
        initialLoadComplete = true;
        break;
      }
      case "message": {
        if (data["content"] === "DONE") {
          ws.send(JSON.stringify({ "message": "HTML" }));
        } else if (data["content"] === "CLEAR") {
          $("#chat").html("");
          $("#temp-card .status").hide();
          $("#indicator").show();
        }
        break;
      }
      case "ai_user": {
        $("#message").val($("#message").val() + data["content"].replace(/\\n/g, "\n"));
        autoResize($("#message"));
        if (autoScroll && !isElementInViewport(mainPanel)) {
          mainPanel.scrollIntoView(false);
        }
        break
      }
      case "ai_user_finished": {
        $("#message").attr("placeholder", "Type your message . . .");
        $("#message").prop("disabled", false);
        autoResize($("#message"));
        $("#cancel_query").hide();
        $("#send, #clear, #image-file, #voice").prop("disabled", false);

        if (!isElementInViewport(mainPanel)) {
          mainPanel.scrollIntoView(false);
        }

        setInputFocus();
        break;
      }

      case "html": {
        responseStarted = false;
        callingFunction = false;
        messages.push(data["content"]);

        if (data["content"]["role"] === "assistant") {
          appendCard("assistant", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);

          // Show message input and hide spinner
          $("#message").show();
          $("#monadic-spinner").hide();

          if (params["ai_user_initial_prompt"] && params["ai_user_initial_prompt"] !== "") {
            $("#message").attr("placeholder", "Waiting for AI-user input . . .");
            $("#message").prop("disabled", true);
            let simple_messages = messages.map(msg => {
              return { "role": msg["role"], "text": msg["text"] }
            });
            let ai_user_query = {
              message: "AI_USER_QUERY",
              contents: {
                params: params,
                messages: simple_messages
              }
            };
            $("#send, #clear, #image-file, #voice").prop("disabled", true);
            ws.send(JSON.stringify(ai_user_query));
          } else {
            $("#cancel_query").hide();
            setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
          }

        } else if (data["content"]["role"] === "user") {
          let content_text = data["content"]["text"].trim().replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, " ");
          let images;
          if (data["content"]["images"] !== undefined) {
            images = data["content"]["images"]
          }
          // Use the appendCard helper function
          appendCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + content_text + "</p>", data["content"]["lang"], data["content"]["mid"], true, images);
          $("#message").show();
          $("#monadic-spinner").hide();
          $("#cancel_query").hide();
          setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
        } else if (data["content"]["role"] === "system") {
          // Use the appendCard helper function
          appendCard("system", "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
          $("#message").show();
          $("#monadic-spinner").hide();
          $("#cancel_query").hide();
          setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
        }

        $("#chat").html("");
        $("#temp-card").hide();
        $("#indicator").hide();
        $("#user-panel").show();

        if (!isElementInViewport(mainPanel)) {
          mainPanel.scrollIntoView(false);
        }

        setInputFocus();

        break;
      }
      case "user": {
        let message_obj = { "role": "user", "text": data["content"]["text"], "html": data["content"]["html"], "mid": data["content"]["mid"] }
        if (data["content"]["images"] !== undefined) {
          message_obj.images = data["content"]["images"];
        }
        messages.push(message_obj);
        let content_text = data["content"]["text"].trim().replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, " ");
        let images;
        if (data["content"]["images"] !== undefined) {
          images = data["content"]["images"];
        }
        // Use the appendCard helper function
        appendCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + content_text + "</p>", data["content"]["lang"], data["content"]["mid"], true, images);
        $("#temp-card").show();
        $("#temp-card .status").hide();
        $("#indicator").show();
        $("#user-panel").hide();
        $("#cancel_query").show();
        break;
      }

      case "cancel": {
        $("#message").val("");
        $("#message").attr("placeholder", "Type your message...");
        $("#message").prop("disabled", false);
        $("#alert-message").html("Input a message.");
        $("#cancel_query").hide();
        
        // Show message input and hide spinner
        $("#message").show();
        $("#monadic-spinner").hide();
        
        setInputFocus();
        break;
      }

      default: {
        if (!responseStarted || callingFunction) {
          setAlert("<i class='fas fa-pencil-alt'></i> RESPONDING", "warning");
          callingFunction = false;
          responseStarted = true;
        }
        $("#indicator").show();
        if (data["content"] !== undefined) {
          $("#chat").html($("#chat").html() + data["content"].replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>"));
        }
        if (autoScroll && !isElementInViewport(chatBottom)) {
          chatBottom.scrollIntoView(false);
        }
      }
    }
  }

  ws.onclose = function (_e) {
    // console.log(`Socket is closed. Reconnect will be attempted in ${reconnectDelay} second.`, e.reason);
    initialLoadComplete = false;
    reconnect_websocket(ws);
  }

  ws.onerror = function (err) {
    console.error('Socket encountered error: ', err.message, 'Closing socket');
    // set a message in the alert box
    setAlert("<i class='fa-solid fa-circle-exclamation'></i> Connection terminated.", "danger");
    ws.close();
  }
  return ws;
}

function reconnect_websocket(ws, callback) {
  switch (ws.readyState) {
    case WebSocket.CLOSED:
      ws = connect_websocket(callback);
      break;
    case WebSocket.CLOSING:
      setTimeout(() => {
        reconnect_websocket(ws, callback);
      }, reconnectDelay);
      break;
    case WebSocket.CONNECTING:
      setTimeout(() => {
        reconnect_websocket(ws, callback);
      }, reconnectDelay);
      break;
    case WebSocket.OPEN:
      if (callback) {
        callback(ws);
      }
      break;
  }
}

function handleVisibilityChange() {
  if (!document.hidden) {
    if (ws.readyState === WebSocket.CLOSED) {
      ws = connect_websocket(() => {
        // 再接続後に過去のメッセージを再取得
        ws.send(JSON.stringify({ message: "LOAD" }));
      });
    }
  }
}

document.addEventListener('visibilitychange', handleVisibilityChange);
