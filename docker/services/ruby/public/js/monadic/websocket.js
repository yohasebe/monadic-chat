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
    // Only activate voice button if session has begun (config is hidden and main panel is visible)
    if ($("#voice").prop("disabled") === false && !$("#config").is(":visible") && $("#main-panel").is(":visible")) {
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

// Set the copy code button for each code block
function setCopyCodeButton(element) {
  // check element if it exists
  if (!element) {
    return;
  }
  element.find("div.card-text div.highlighter-rouge").each(function () {
    const highlighterElement = $(this);
    // Only add the button if it doesn't already exist
    if (highlighterElement.find(".copy-code-button").length === 0) {
      // Find the code element inside highlighter-rouge
      const codeElement = highlighterElement.find("code");
      if (codeElement.length) {
        // Add the copy button directly to the highlighter-rouge container
        const copyButton = $(`<div class="copy-code-button"><i class="fa-solid fa-copy"></i></div>`);
        highlighterElement.append(copyButton);
        
        // Add click event to the button
        copyButton.click(async function () {
          try {
            const text = codeElement.text();
            await navigator.clipboard.writeText(text);
            
            // Show success indicator
            const icon = copyButton.find("i");
            icon.removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
            
            // Return to normal state after delay
            setTimeout(() => {
              icon.removeClass("fa-check").addClass("fa-copy").css("color", "");
            }, 1000);
          } catch (err) {
            console.error("Failed to copy text: ", err);
            
            // Show error indicator
            const icon = copyButton.find("i");
            icon.removeClass("fa-copy").addClass("fa-xmark").css("color", "#DC4C64");
            
            // Return to normal state after delay
            setTimeout(() => {
              icon.removeClass("fa-xmark").addClass("fa-copy").css("color", "");
            }, 1000);
          }
        });
      }
    }
  });
}

// Note: Visibility change handler is defined later in the file

//////////////////////////////
// WebSocket event handlers
//////////////////////////////

// In browser environments, wsHandlers is defined globally in websocket-handlers.js
let wsHandlers = window.wsHandlers;

const apps = {}
let messages = [];
let originalParams = {};
let params = {}

let reconnectDelay = 1000;

let pingInterval;

function startPing() {
  // Clear any existing ping interval to avoid duplicates
  stopPing();
  
  // Start new ping interval
  pingInterval = setInterval(() => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ message: 'PING' }));
    } else {
      // If the websocket is no longer open, stop pinging
      stopPing();
    }
  }, 30000);
}

function stopPing() {
  if (pingInterval) {
    clearInterval(pingInterval);
    pingInterval = null; // Properly null out the reference
  }
}

const chatBottom = $("#chat-bottom").get(0);
let autoScroll = true;
/* exported autoScroll */

const mainPanel = $("#main-panel").get(0);
const defaultApp = DEFAULT_APP;

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
const MAX_AUDIO_QUEUE_SIZE = 50; // Maximum number of audio chunks to keep in queue

// Function to add audio data to queue with size limit enforcement
function addToAudioQueue(data) {
  // Limit the queue size to prevent memory leaks
  if (audioDataQueue.length >= MAX_AUDIO_QUEUE_SIZE) {
    // Remove oldest audio data (half of the queue) to make room for new data
    audioDataQueue = audioDataQueue.slice(Math.floor(MAX_AUDIO_QUEUE_SIZE / 2));
    }
  audioDataQueue.push(data);
}

// Function to clear the audio queue
function clearAudioQueue() {
  audioDataQueue = [];
}

function processAudioDataQueue() {
  if (!mediaSource || !sourceBuffer) {
    return;
  }
  
  if (mediaSource.readyState === 'open' && audioDataQueue.length > 0 && !sourceBuffer.updating) {
    const audioData = audioDataQueue.shift();
    try {
      sourceBuffer.appendBuffer(audioData);
    } catch (e) {
      console.error('Error appending buffer:', e);
      
      if (e.name === 'QuotaExceededError') {
        if (sourceBuffer.buffered.length > 0) {
          sourceBuffer.remove(0, sourceBuffer.buffered.end(0));
        }
        audioDataQueue = [];
      }
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
    setAlert("<i class='fa-solid fa-bolt'></i> Verifying token", "warning");
    ws.send(JSON.stringify({ message: "CHECK_TOKEN", initial: true, contents: $("#token").val() }));

    if (!mediaSource) {
      mediaSource = new MediaSource();
      mediaSource.addEventListener('sourceopen', () => {
        try {
          if (runningOnFirefox) {
            window.firefoxAudioMode = true;
            window.firefoxAudioQueue = [];
            
            processAudioDataQueue = function() {
              if (window.firefoxAudioQueue && window.firefoxAudioQueue.length > 0) {
                const audioData = window.firefoxAudioQueue.shift();
                try {
                  const blob = new Blob([audioData], { type: 'audio/mpeg' });
                  const url = URL.createObjectURL(blob);
                  
                  const tempAudio = new Audio(url);
                  tempAudio.onended = function() {
                    URL.revokeObjectURL(url);
                    if (window.firefoxAudioQueue.length > 0) {
                      processAudioDataQueue();
                    }
                  };
                  
                  tempAudio.play().catch(e => console.error("Firefox audio playback error:", e));
                } catch (e) {
                  console.error("Firefox audio processing error:", e);
                }
              }
            };
          } else {
            // Chrome and others work well with mpeg
            sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
            sourceBuffer.addEventListener('updateend', processAudioDataQueue);
          }
        } catch (e) {
          console.error("Error setting up MediaSource: ", e);
        }
      });
    }

    if (!audio) {
      audio = new Audio();
      audio.src = URL.createObjectURL(mediaSource);
    }

    // Only verify token once
    if (!verified) {
      setAlert("<i class='fa-solid fa-bolt'></i> Verifying token", "warning");
      ws.send(JSON.stringify({ message: "CHECK_TOKEN", initial: true, contents: $("#token").val() }));
    }

    // Check verified status at a regular interval
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
    setAlert(message, "error");
  }

  ws.onmessage = function (event) {
    
    let data;
    try {
      data = JSON.parse(event.data);
    } catch (error) {
      console.error("Error parsing WebSocket message:", error, event.data);
      return;
    }
    switch (data["type"]) {
      case "wait": {
        callingFunction = true;
        setAlert(data["content"], "warning");
        
        // Update spinner message for function calls
        $("#monadic-spinner span").html('<i class="fas fa-brain fa-pulse"></i> Processing request');
        break;
      }

      case "audio": {
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleAudioMessage === 'function') {
          // Custom audio processor for the extracted handler
          const processAudio = (audioData) => {
            // Handle Firefox special case
            if (window.firefoxAudioMode) {
              // Add to the Firefox queue instead
              if (!window.firefoxAudioQueue) {
                window.firefoxAudioQueue = [];
              }
              // Limit Firefox queue size as well
              if (window.firefoxAudioQueue.length >= MAX_AUDIO_QUEUE_SIZE) {
                window.firefoxAudioQueue = window.firefoxAudioQueue.slice(Math.floor(MAX_AUDIO_QUEUE_SIZE / 2));
              }
              window.firefoxAudioQueue.push(audioData);
              processAudioDataQueue();
            } else {
              // Regular MediaSource approach for other browsers
              audioDataQueue.push(audioData);
              processAudioDataQueue();
              
              // Make sure audio is playing
              if (audio && audio.paused) {
                audio.play();
              }
            }
          };
          
          handled = wsHandlers.handleAudioMessage(data, processAudio);
        }
        
        if (!handled) {
          // Fallback to inline handling
          $("#monadic-spinner").hide();

          try {
            // Check if response contains an error
            if (data.content && typeof data.content === 'string' && data.content.includes('error')) {
              try {
                const errorData = JSON.parse(data.content);
                if (errorData.error) {
                  console.error("TTS error:", errorData.error);
                  break;
                }
              } catch (e) {
                // If not valid JSON, continue with regular processing
              }
            }

            const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));
            
            // Handle Firefox special case
            if (window.firefoxAudioMode) {
              // Add to the Firefox queue instead
              if (!window.firefoxAudioQueue) {
                window.firefoxAudioQueue = [];
              }
              // Limit Firefox queue size as well
              if (window.firefoxAudioQueue.length >= MAX_AUDIO_QUEUE_SIZE) {
                window.firefoxAudioQueue = window.firefoxAudioQueue.slice(Math.floor(MAX_AUDIO_QUEUE_SIZE / 2));
              }
              window.firefoxAudioQueue.push(audioData);
              processAudioDataQueue();
            } else {
              // Regular MediaSource approach for other browsers
              audioDataQueue.push(audioData);
              processAudioDataQueue();
              
              // Make sure audio is playing
              if (audio && audio.paused) {
                audio.play();
              }
            }
            
          } catch (e) {
            console.error("Error processing audio data:", e);
          }
        }
        break;
      }

      case "pong": {
        break;
      }

      case "error": {
        // Check if error during AI User generation (message starts with AI User error)
        const isAIUserError = data.content && data.content.toString().includes("AI User error");
        
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleErrorMessage === 'function') {
          handled = wsHandlers.handleErrorMessage(data);
        } else {
          // Fallback to inline handling
          $("#send, #clear, #image-file, #voice, #doc, #url, #ai_user").prop("disabled", false);
          $("#message").show();
          $("#message").prop("disabled", false);
          $("#monadic-spinner").hide();
          setAlert(data.content, 'error');
          handled = true;
        }
        
        // Additional UI operations specific to our application context
        if (handled) {
          $("#select-role").prop("disabled", false);
          $("#alert-message").html("Input a message.");
          
          // Reset UI panels and indicators
          $("#temp-card").hide();
          $("#indicator").hide();
          $("#user-panel").show();
          $("#cancel_query").hide();
  
          // For AI User errors, don't delete messages but re-enable the AI User button
          if (isAIUserError) {
            // Explicitly re-enable the AI User button - critical fix for Perplexity
            $("#ai_user").prop("disabled", false);
            // Also update the AI User button state based on messages
            updateAIUserButtonState(messages);
          } else {
            // For non-AI User errors, remove user message that caused error (if it exists)
            const lastCard = $("#discourse .card").last();
            if (lastCard.find(".user-color").length !== 0) {
              deleteMessage(lastCard.attr('id'));
            }
    
            // Restore the message content so user can edit and retry
            $("#message").val(params["message"]);
          }
          
          // Reset response tracking flags to ensure clean state
          responseStarted = false;
          callingFunction = false;
          
          // Set focus back to input field
          setInputFocus();
        }
        
        break;
      }

      case "token_verified": {
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleTokenVerification === 'function') {
          handled = wsHandlers.handleTokenVerification(data);
        } else {
          // Fallback to inline handling
          $("#api-token").val(data["token"]);
          $("#ai-user-initial-prompt").val(data["ai_user_initial_prompt"]);
          handled = true;
        }

        // These operations are still needed regardless of which path handled the message
        if (handled) {
          verified = "full";
          setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
          $("#start").prop("disabled", false);
          $("#send, #clear, #voice, #tts-provider, #elevenlabs-tts-voice, #tts-voice, #tts-speed, #asr-lang, #ai-user-initial-prompt-toggle, #ai-user-toggle, #check-auto-speech, #check-easy-submit").prop("disabled", false);
          
          // Update the available AI User providers when token is verified
          // Always call the function directly from window's scope
          window.updateAvailableProviders();
        }

        break;
      }

      case "open_ai_api_error": {
        verified = "partial";

        $("#start").prop("disabled", false);
        $("#send, #clear").prop("disabled", false);

        $("#api-token").val("");

        setAlert("<i class='fa-solid fa-bolt'></i> Cannot connect to OpenAI API", "warning");
        break;
      }
      case "token_not_verified": {

        verified = "partial";

        $("#start").prop("disabled", false);
        $("#send, #clear").prop("disabled", false);

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
            if (group && group.trim() !== "" && ["openai"].includes(group.trim().toLowerCase())) {
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

          // Sort regular apps alphabetically by displayed text value
          regularApps.sort((a, b) => {
            const textA = a[1]["display_name"] || a[1]["app_name"];
            const textB = b[1]["display_name"] || b[1]["app_name"];
            return textA.localeCompare(textB);
          });

          // Sort apps within each special group alphabetically by displayed text value
          for (const group of Object.keys(specialApps)) {
            specialApps[group].sort((a, b) => {
              const textA = a[1]["display_name"] || a[1]["app_name"];
              const textB = b[1]["display_name"] || b[1]["app_name"];
              return textA.localeCompare(textB);
            });
          }

          // Add apps to selector
          // First add the OpenAI Apps label and regular apps
          if (verified === "full") {
            $("#apps").append('<option disabled>──OpenAI──</option>');
            for (const [key, value] of regularApps) {
              apps[key] = value;
              // Use display_name if available, otherwise fall back to app_name
              const displayText = value["display_name"] || value["app_name"];
              $("#apps").append(`<option value="${key}">${displayText}</option>`);
            }
          }

          // sort specialApps by group name in the order:
          // "Anthropic", "Google", "Cohere", "Mistral", "Extra"
          // and set it to the specialApps object
          specialApps = Object.fromEntries(Object.entries(specialApps).sort((a, b) => {
            const order = ["Anthropic", "xAI Grok", "Google", "Cohere", "Mistral", "Perplexity", "DeepSeek", "Extra"];
            return order.indexOf(a[0]) - order.indexOf(b[0]);
          }));

          // Add special groups with their labels
          for (const group of Object.keys(specialApps)) {
            if (specialApps[group].length > 0) {
              $("#apps").append(`<option disabled>──${group}──</option>`);
              for (const [key, value] of specialApps[group]) {
                apps[key] = value;
                // Use display_name if available, otherwise fall back to app_name
                const displayText = value["display_name"] || value["app_name"];
                $("#apps").append(`<option value="${key}">${displayText}</option>`);
              }
            }
          }

          // select the first available (non-disabled) app in the dropdown
          $("#apps").val($("#apps option:not([disabled]):first").val()).trigger('change')

          // Use display_name if available, otherwise fall back to app_name
          const displayText = apps[$("#apps").val()]["display_name"] || apps[$("#apps").val()]["app_name"];
          $("#base-app-title").text(displayText);

          if (apps[$("#apps").val()]["monadic"]) {
            $("#monadic-badge").show();
          } else {
            $("#monadic-badge").hide();
          }

          if (apps[$("#apps").val()]["websearch"]) {
            $("#websearch-badge").show();
          } else {
            $("#websearch-badge").hide();
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
          
          // Update the AI User provider dropdown
          // Always call the function directly from window's scope
          window.updateAvailableProviders();
        }
        originalParams = apps["Chat"];
        resetParams();
        break;
      }
      case "parameters": {
        loadedApp = data["content"]["app_name"];
        setAlert("<i class='fa-solid fa-hourglass-half'></i> Please wait", "warning");
        loadParams(data["content"], "loadParams");
        
        // All providers now support AI User functionality
        
        const currentApp = apps[$("#apps").val()] || apps[defaultApp];

        let models = [];
        if (currentApp["models"] && currentApp["models"].length > 0) {
          let models_text = currentApp["models"]
          models = JSON.parse(models_text);
        } else if (currentApp["model"]) {
          models = [currentApp["model"]];
        } else {
          models = [];
        }

        let openai = currentApp["group"].toLowerCase() === "openai";
        let modelList = listModels(models, openai);
        $("#model").html(modelList);
        let model = currentApp["models"][0];
        if (currentApp["model"] && models.includes(currentApp["model"])) {
          model = currentApp["model"];
        }
        
        // Extract provider name from current app group using shared function if available
        let provider;
        if (typeof getProviderFromGroup === 'function') {
          provider = getProviderFromGroup(currentApp["group"]);
        } else {
          // Fallback implementation if the function is not available
          provider = "OpenAI";
          if (currentApp["group"]) {
            const group = currentApp["group"].toLowerCase();
            if (group.includes("anthropic") || group.includes("claude")) {
              provider = "Anthropic";
            } else if (group.includes("gemini") || group.includes("google")) {
              provider = "Gemini";
            } else if (group.includes("cohere")) {
              provider = "Cohere";
            } else if (group.includes("mistral")) {
              provider = "Mistral";
            } else if (group.includes("perplexity")) {
              provider = "Perplexity";
            } else if (group.includes("deepseek")) {
              provider = "DeepSeek";
            } else if (group.includes("grok") || group.includes("xai")) {
              provider = "Grok";
            }
          }
        }
        
        // Update model display with Provider (Model) format
        if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
          $("#model-selected").text(`${provider} (${model} - ${modelSpec[model]["reasoning_effort"]})`);
        } else {
          $("#model-selected").text(`${provider} (${model})`);
        }

        $("#model").val(model);

        // Use display_name if available, otherwise fall back to app_name
        $("#base-app-title").text(currentApp["display_name"] || currentApp["app_name"]);
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
      case "elevenlabs_voices": {
        const cookieValue = getCookie("elevenlabs-tts-voice");
        let voices = data["content"];
        if (voices.length > 0) {
          // set #elevenlabs-provider-option enabled
          $("#elevenlabs-provider-option").prop("disabled", false);
          // Do not set ElevenLabs as default - prefer openai-tts-4o
        } else {
          // set #elevenlabs-provider-option disabled
          $("#elevenlabs-provider-option").prop("disabled", true);
        }
        $("#elevenlabs-tts-voice").empty();
        voices.forEach((voice) => {
          if (cookieValue === voice.voice_id) {
            $("#elevenlabs-tts-voice").append(`<option value="${voice.voice_id}" selected>${voice.name}</option>`);
          } else {
            $("#elevenlabs-tts-voice").append(`<option value="${voice.voice_id}">${voice.name}</option>`);
          }
        });
        
        // Apply saved cookie value for voice if it exists
        const savedVoice = getCookie("elevenlabs-tts-voice");
        if (savedVoice && $(`#elevenlabs-tts-voice option[value="${savedVoice}"]`).length > 0) {
          $("#elevenlabs-tts-voice").val(savedVoice);
        }
        
        // Apply saved cookie value for provider if it was elevenlabs
        const savedProvider = getCookie("tts-provider");
        if (savedProvider === "elevenlabs") {
          $("#tts-provider").val("elevenlabs").trigger("change");
        }
        break;
      }
      case "stt": {
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleSTTMessage === 'function') {
          handled = wsHandlers.handleSTTMessage(data);
        }
        
        if (!handled) {
          // Fallback to inline handling
          $("#message").val($("#message").val() + " " + data["content"]);
          let logprob = "Last Speech-to-Text p-value: " + data["logprob"];
          $("#asr-p-value").text(logprob);
          $("#send, #clear, #voice").prop("disabled", false);
          if ($("#check-easy-submit").is(":checked")) {
            $("#send").click();
          }
          setAlert("<i class='fa-solid fa-circle-check'></i> Voice recognition finished", "secondary");
          setInputFocus()
        }
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
        const pdf_table = "<table class='table mt-1 mb-1'><tbody>" +
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
              let html = msg["html"];
              if (msg["thinking"]) {
                html = "<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>" + msg["thinking"] + "</div></div>" + html
              } 

              const gptElement = createCard("assistant", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>", html, msg["lang"], msg["mid"], msg["active"]);
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
        
        // Update AI User button state
        updateAIUserButtonState(messages);

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
      case "ai_user_started": {
        setAlert("<i class='fas fa-spinner fa-spin'></i> Generating AI user response...", "warning");
        
        // Show the cancel button
        $("#cancel_query").css("display", "block");
        
        // Show spinner and update its message with robot animation
        $("#monadic-spinner").css("display", "block");
        $("#monadic-spinner span").html('<i class="fas fa-robot fa-pulse"></i> Generating AI user response');
        
        // Disable the input elements
        $("#message").prop("disabled", true);
        $("#send").prop("disabled", true);
        $("#clear").prop("disabled", true);
        $("#image-file").prop("disabled", true);
        $("#voice").prop("disabled", true);
        $("#doc").prop("disabled", true);
        $("#url").prop("disabled", true);
        $("#ai_user").prop("disabled", true);
        $("#select-role").prop("disabled", true);
        
        break;
      }
      case "ai_user": {
        // Append AI user content to the message field
        $("#message").val($("#message").val() + data["content"].replace(/\\n/g, "\n"));
        
        // Make sure the message panel is visible
        if (autoScroll && !isElementInViewport(mainPanel)) {
          mainPanel.scrollIntoView(false);
        }
        break;
      }
      case "ai_user_finished": {
        console.log("AI User finished");
        
        // Trim extra whitespace from the final message
        const trimmedContent = data["content"].trim();
        
        // Set the message content
        $("#message").val(trimmedContent);
        
        // Hide cancel button and spinner
        $("#cancel_query").hide();
        $("#monadic-spinner").css("display", "none");

        // Re-enable all input elements individually
        $("#message").prop("disabled", false);
        $("#send").prop("disabled", false);
        $("#clear").prop("disabled", false);
        $("#image-file").prop("disabled", false);
        $("#voice").prop("disabled", false);
        $("#doc").prop("disabled", false);
        $("#url").prop("disabled", false);
        $("#ai_user").prop("disabled", false);
        $("#select-role").prop("disabled", false);

        // Update alert message to success state
        setAlert("<i class='fa-solid fa-circle-check'></i> AI user response generated", "success");

        // Ensure the panel is visible
        if (!isElementInViewport(mainPanel)) {
          mainPanel.scrollIntoView(false);
        }

        // Focus on the input field
        setInputFocus();
        break;
      }
      
      case "success": {
        // Handle success messages from the server
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${data.content}`, "success");
        break;
      }
      
      case "edit_success": {
        // Handle successful message edit
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${data.content}`, "success");
        
        // Get the message card by mid
        const $card = $(`#${data.mid}`);
        if (!$card.length) return;
        
        const $cardText = $card.find(".card-text");
        
        // Update the HTML content for assistant messages
        if (data.role === "assistant" && data.html) {
          // Update the card with the HTML from server
          $cardText.html(data.html);
          
          // Apply all the required processing for assistant messages
          const htmlContent = $card;
          
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
        break;
      }

      case "html": {
        responseStarted = false;
        callingFunction = false;
        
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleHtmlMessage === 'function') {
          handled = wsHandlers.handleHtmlMessage(data, messages, appendCard);
          if (handled) {
            $("#cancel_query").hide();
          }
        }
        
        // Update AI User button state
        updateAIUserButtonState(messages);
        
        if (!handled) {
          // Fallback to inline handling
          messages.push(data["content"]);

          let html = data["content"]["html"];

          if (data["content"]["thinking"]) {
            html = "<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>" + data["content"]["thinking"] + "</div></div>" + html
          } else if(data["content"]["reasoning_content"]) {
            html = "<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>" + data["content"]["reasoning_content"] + "</div></div>" + html
          }
          
          if (data["content"]["role"] === "assistant") {
            appendCard("assistant", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>", html, data["content"]["lang"], data["content"]["mid"], true);

            // Show message input and hide spinner
            $("#message").show();
            $("#message").val(""); // Clear the message after successful response
            $("#message").prop("disabled", false);
            // Re-enable all input controls
            $("#send, #clear, #image-file, #voice, #doc, #url").prop("disabled", false);
            $("#select-role").prop("disabled", false);
            $("#monadic-spinner").hide();
            $("#cancel_query").hide();
          }

          // AI User is no longer automatically triggered
          $("#cancel_query").hide();
          setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");

        } else if (data["content"]["role"] === "user") {
          let content_text = data["content"]["text"].trim().replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, " ");
          let images;
          if (data["content"]["images"] !== undefined) {
            images = data["content"]["images"]
          }
          // Use the appendCard helper function
          appendCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + content_text + "</p>", data["content"]["lang"], data["content"]["mid"], true, images);
          $("#message").show();
          $("#message").prop("disabled", false);
          $("#monadic-spinner").hide();
          $("#cancel_query").hide();
          setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
        } else if (data["content"]["role"] === "system") {
          // Use the appendCard helper function
          appendCard("system", "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
          $("#message").show();
          $("#message").prop("disabled", false);
          $("#monadic-spinner").hide();
          $("#cancel_query").hide();
          setAlert("<i class='fa-solid fa-circle-check'></i> Ready to start", "success");
        }

        $("#chat").html("");
        $("#temp-card").hide();
        $("#indicator").hide();
        $("#user-panel").show();
        
        // Make sure message input is enabled
        $("#message").prop("disabled", false);

        if (!isElementInViewport(mainPanel)) {
          mainPanel.scrollIntoView(false);
        }

        setInputFocus();

        break;
      }
      case "user": {
        // Check if we have a temporary message to remove first
        const tempMessageIndex = messages.findIndex(msg => msg.temp === true);
        if (tempMessageIndex !== -1) {
          messages.splice(tempMessageIndex, 1);
        }
        
        // Create the proper message object
        let message_obj = { "role": "user", "text": data["content"]["text"], "html": data["content"]["html"], "mid": data["content"]["mid"] }
        if (data["content"]["images"] !== undefined) {
          message_obj.images = data["content"]["images"];
        }
        messages.push(message_obj);
        
        // Format content for display
        let content_text = data["content"]["text"].trim().replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, " ");
        let images;
        if (data["content"]["images"] !== undefined) {
          images = data["content"]["images"];
        }
        
        // Use the appendCard helper function to show the user message
        appendCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + content_text + "</p>", data["content"]["lang"], data["content"]["mid"], true, images);
        
        // Scroll down immediately after showing user message to make it visible
        if (!isElementInViewport(mainPanel)) {
          mainPanel.scrollIntoView(false);
        }
        
        // Show loading indicators
        $("#temp-card").show();
        $("#temp-card .status").hide();
        $("#indicator").show();
        // Keep the user panel visible but disable interactive elements
        $("#message").prop("disabled", true);
        $("#send, #clear, #image-file, #voice, #doc, #url").prop("disabled", true);
        $("#select-role").prop("disabled", true);
        $("#cancel_query").css("display", "block");
        
        // Show informative spinner message with brain animation icon
        $("#monadic-spinner span").html('<i class="fas fa-brain fa-pulse"></i> Processing request...');
        break;
      }

      case "display_sample": {
        // Immediately display the sample message
        const content = data.content;
        if (!content || !content.mid || !content.role || !content.html || !content.badge) {
          console.error("Invalid display_sample message format:", data);
          break;
        }
        
        // First check if this message already exists
        if ($("#" + content.mid).length > 0) {
          break;
        }
        
        // Create appropriate element based on role
        const cardElement = createCard(
          content.role, 
          content.badge,
          content.html,
          "en", // Default language
          content.mid,
          true  // Always active
        );
        
        // Append to discourse
        $("#discourse").append(cardElement);
        
        // Add message to messages array to ensure edit functionality works correctly
        // This ensures sample messages are treated consistently with API-generated messages
        if (content.text) {
          const messageObj = {
            "role": content.role,
            "text": content.text,
            "mid": content.mid
          };
          
          // For assistant role, also include HTML content
          if (content.role === "assistant") {
            messageObj.html = content.html;
          }
          
          // Add to messages array - this ensures last message detection works correctly
          messages.push(messageObj);
        }
        
        // Apply appropriate styling based on current settings
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
        
        // Scroll to bottom
        if (autoScroll && !isElementInViewport(chatBottom)) {
          chatBottom.scrollIntoView(false);
        }
        
        break;
      }
      
      case "sample_success": {
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleSampleSuccess === 'function') {
          handled = wsHandlers.handleSampleSuccess(data);
        }
        
        if (!handled) {
          // Clear any pending timeout to prevent error message
          if (window.currentSampleTimeout) {
            clearTimeout(window.currentSampleTimeout);
            window.currentSampleTimeout = null;
          }
          
          // Hide UI elements
          $("#monadic-spinner").hide();
          $("#cancel_query").hide();
          
          // Show success alert
          const roleText = data.role === "user" ? "User" : 
                          data.role === "assistant" ? "Assistant" : "System";
          setAlert(`<i class='fas fa-check-circle'></i> Sample ${roleText} message added`, "success");
        }
        break;
      }
      
      case "cancel": {
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleCancelMessage === 'function') {
          handled = wsHandlers.handleCancelMessage(data);
        }
        
        if (!handled) {
          // Remove temporary message if it exists
          const tempMessageIndex = messages.findIndex(msg => msg.temp === true);
          if (tempMessageIndex !== -1) {
            messages.splice(tempMessageIndex, 1);
          }
          
          // Remove any UI cards that may have been created during this initial message
          if (messages.length === 0) {
            $("#discourse").empty();
          }
          
          // Don't clear the message so users can edit and resubmit
          $("#message").attr("placeholder", "Type your message...");
          $("#message").prop("disabled", false);
          
          // Re-enable all the UI elements individually
          $("#send").prop("disabled", false);
          $("#clear").prop("disabled", false);
          $("#image-file").prop("disabled", false);
          $("#voice").prop("disabled", false);
          $("#doc").prop("disabled", false);
          $("#url").prop("disabled", false);
          $("#ai_user").prop("disabled", false);
          $("#select-role").prop("disabled", false);
          
          $("#alert-message").html("Input a message.");
          $("#cancel_query").hide();
          
          // Hide loading indicators
          $("#temp-card").hide();
          $("#indicator").hide();
          
          // Show message input and hide spinner
          $("#message").show();
          $("#monadic-spinner").css("display", "none");
          
          // Update AI User button state
          updateAIUserButtonState(messages);
          
          // Show canceled message
          setAlert("<i class='fa-solid fa-ban' style='color: #ffc107;'></i> Operation canceled", "warning");
          
          setInputFocus();
        }
        break;
      }

      
      default: {
        let content = data["content"];
        if (!responseStarted || callingFunction) {
          setAlert("<i class='fas fa-pencil-alt'></i> RESPONDING", "warning");
          callingFunction = false;
          responseStarted = true;
          // Update spinner message for streaming
          $("#monadic-spinner span").html('<i class="fas fa-brain fa-pulse"></i> Receiving response');
          // remove the leading new line characters from content
          content = content.replace(/^\n+/, "");
        }
        $("#indicator").show();
        if (content !== undefined) {
          $("#chat").html($("#chat").html() + content.replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>"));
        }
        if (autoScroll && !isElementInViewport(chatBottom)) {
          chatBottom.scrollIntoView(false);
        }
      }
    }
  }

  ws.onclose = function (_e) {
    initialLoadComplete = false;
    reconnect_websocket(ws);
  }

  ws.onerror = function (err) {
    console.error('Socket encountered error: ', err.message, 'Closing socket');
    // set a message in the alert box - this happens when the server is actually down
    setAlert("<i class='fa-solid fa-circle-exclamation'></i> Connection to server lost.", "danger");
    ws.close();
  }
  return ws;
}

// WebSocket connection management
const maxReconnectAttempts = 20; // Maximum number of reconnection attempts
const baseReconnectDelay = 1000; // Base delay in milliseconds
let reconnectionTimer = null; // Store the timer to allow cancellation

// Improved WebSocket reconnection logic with proper cleanup and retry handling
function reconnect_websocket(ws, callback) {
  // Store reconnection attempts in the WebSocket object itself
  // This ensures each WebSocket manages its own reconnection state
  if (ws._reconnectAttempts === undefined) {
    ws._reconnectAttempts = 0;
  }
  
  // Limit maximum reconnection attempts
  if (ws._reconnectAttempts >= maxReconnectAttempts) {
    console.error(`Maximum reconnection attempts (${maxReconnectAttempts}) reached.`);
    setAlert("<i class='fa-solid fa-server'></i> Server closed", "danger");
    
    // Properly clean up any pending timers
    if (reconnectionTimer) {
      clearTimeout(reconnectionTimer);
      reconnectionTimer = null;
    }
    return;
  }

  // Calculate exponential backoff delay
  const delay = baseReconnectDelay * Math.pow(1.5, ws._reconnectAttempts);
  
  // Clear any existing reconnection timer
  if (reconnectionTimer) {
    clearTimeout(reconnectionTimer);
    reconnectionTimer = null;
  }
  
  try {
    // Check WebSocket state
    switch (ws.readyState) {
      case WebSocket.CLOSED:
        // Socket is closed, create a new one
        ws._reconnectAttempts++;
        
        // Show server closed status instead of reconnecting
        setAlert("<i class='fa-solid fa-server'></i> Server closed", "danger");
        
        // Stop any active ping interval
        stopPing();
        
        // Create new connection
        ws = connect_websocket(callback);
        break;
        
      case WebSocket.CLOSING:
        // Wait for socket to fully close before reconnecting
        console.log(`Socket is closing. Waiting ${delay}ms before reconnection attempt.`);
        reconnectionTimer = setTimeout(() => {
          reconnect_websocket(ws, callback);
        }, delay);
        break;
        
      case WebSocket.CONNECTING:
        // Socket is still trying to connect, wait a bit before checking again
        console.log(`Socket is connecting. Checking again in ${delay}ms.`);
        reconnectionTimer = setTimeout(() => {
          reconnect_websocket(ws, callback);
        }, delay);
        break;
        
      case WebSocket.OPEN:
        // Connection is successful, reset counters
        console.log('WebSocket connection established.');
        ws._reconnectAttempts = 0;
        
        // Start ping to keep connection alive
        startPing();
        
        // Update UI
        setAlert("<i class='fa-solid fa-circle-check'></i> Connected", "success");
        
        // Execute callback if provided
        if (callback && typeof callback === 'function') {
          callback(ws);
        }
        break;
    }
  } catch (error) {
    console.error("Error during WebSocket reconnection:", error);
    
    // Schedule another attempt with backoff on error
    reconnectionTimer = setTimeout(() => {
      // Increment attempt counter on error
      ws._reconnectAttempts++;
      reconnect_websocket(ws, callback);
    }, delay);
  }
}

function handleVisibilityChange() {
  // Only take action when tab becomes visible again
  if (!document.hidden) {
    try {
      // Clear any existing reconnection timer to prevent duplicate reconnection attempts
      if (reconnectionTimer) {
        clearTimeout(reconnectionTimer);
        reconnectionTimer = null;
      }
      
      // Handle different WebSocket states
      switch (ws.readyState) {
        case WebSocket.CLOSED:
        case WebSocket.CLOSING:
          
          // Reset reconnection attempts for a fresh start when user returns to tab
          if (ws._reconnectAttempts !== undefined) {
            ws._reconnectAttempts = 0;
          }
          
          // Notify the user that server is closed
          setAlert("<i class='fa-solid fa-server'></i> Server closed", "danger");
          
          // Establish a new connection with proper callback
          ws = connect_websocket((newWs) => {
            if (newWs && newWs.readyState === WebSocket.OPEN) {
              // Reload data from server
              newWs.send(JSON.stringify({ message: "LOAD" }));
              // Restart ping to keep connection alive
              startPing();
              // Update UI
              setAlert("<i class='fa-solid fa-circle-check'></i> Connected", "success");
            }
          });
          break;
          
        case WebSocket.CONNECTING:
          // Already attempting to connect, let the process continue
          break;
          
        case WebSocket.OPEN:
          // Connection is already open, verify it's still active
          ws.send(JSON.stringify({ message: "PING" }));
          setAlert("<i class='fa-solid fa-circle-check'></i> Connected", "success");
          break;
      }
    } catch (error) {
      console.error("Error handling visibility change:", error);
      
      // Cleanup any pending timers
      if (reconnectionTimer) {
        clearTimeout(reconnectionTimer);
      }
      
      // Reset reconnection counter and attempt to reconnect on error
      if (ws && ws._reconnectAttempts !== undefined) {
        ws._reconnectAttempts = 0;
      }
      
      // Start a new reconnection attempt with a fresh counter
      reconnectionTimer = setTimeout(() => {
        reconnect_websocket(ws);
      }, 1000); // Short delay before reconnection
    }
  }
}

document.addEventListener('visibilitychange', handleVisibilityChange);

// Clean up WebSocket when page is unloaded
window.addEventListener('beforeunload', function() {
  // Stop pinging
  stopPing();
  
  // Clear any reconnection timers to prevent memory leaks
  if (reconnectionTimer) {
    clearTimeout(reconnectionTimer);
    reconnectionTimer = null;
  }
  
  // Clear audio resources
  clearAudioQueue();
  if (window.firefoxAudioQueue) {
    window.firefoxAudioQueue = [];
  }
  
  // Release MediaSource and SourceBuffer
  if (sourceBuffer) {
    try {
      if (sourceBuffer.updating) {
        sourceBuffer.abort();
      }
    } catch (e) {
      console.error("Error aborting source buffer:", e);
    }
  }
  
  if (mediaSource && mediaSource.readyState === 'open') {
    try {
      mediaSource.endOfStream();
    } catch (e) {
      console.error("Error ending media source stream:", e);
    }
  }
  
  // Release audio element
  if (audio) {
    audio.pause();
    audio.src = '';
    audio.load();
    audio = null;
  }
  
  // Close WebSocket connection if it's open
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    ws.close();
  }
});

// Export functions for browser environment
window.connect_websocket = connect_websocket;
window.reconnect_websocket = reconnect_websocket;
window.handleVisibilityChange = handleVisibilityChange;
window.startPing = startPing;
window.stopPing = stopPing;

// Function to update AI User button enabled state based on conversation status
function updateAIUserButtonState(messages) {
  const aiUserBtn = $("#ai_user");
  if (!aiUserBtn) return;
  
  // AI User should only be enabled if there are at least 2 messages in the conversation
  // (meaning user and assistant have exchanged at least one message)
  const hasConversation = Array.isArray(messages) && messages.length >= 2;
  
  // Get the current provider for proper handling
  const currentProvider = $("#ai-user-provider").val() || "";
  const isPerplexity = currentProvider.toLowerCase() === "perplexity";
  
  // Set disabled state and add tooltip for better UX
  if (hasConversation) {
    // Enable AI User button and update its appearance
    aiUserBtn.prop("disabled", false);
    aiUserBtn.attr("title", "Generate AI user response based on conversation");
    aiUserBtn.removeClass("disabled");
    
    // Add special tooltip for Perplexity
    if (isPerplexity) {
      aiUserBtn.attr("title", "Generate AI user response (Perplexity requires alternating user/assistant messages)");
    }
  } else {
    // Disable AI User button when there's no sufficient conversation
    aiUserBtn.prop("disabled", true);
    aiUserBtn.attr("title", "Start a conversation first to enable AI User");
    aiUserBtn.addClass("disabled");
  }
  
  // Button state updated
}

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    connect_websocket,
    reconnect_websocket,
    handleVisibilityChange,
    startPing,
    stopPing,
    updateAIUserButtonState
  };
}
