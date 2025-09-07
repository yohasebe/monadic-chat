/////////////////////////////
// set up the websocket
//////////////////////////////

let ws = connect_websocket();
window.ws = ws;  // Make ws globally accessible
let model_options;
let initialLoadComplete = false; // Flag to track initial load

// Lightweight timeline logger to trace initialization order
if (!window.logTL) {
  window.logTL = function(event, payload) {
    try {
      const ts = new Date().toISOString();
      const entry = Object.assign({ ts, event }, payload || {});
      window._timeline = window._timeline || [];
      window._timeline.push(entry);
      // Keep console concise
      console.log('[TL]', event, entry);
    } catch (_) {}
  };
}

// OpenAI API token verification
let verified = null;

// For iOS audio buffering
let iosAudioBuffer = [];
let isIOSAudioPlaying = false;
let iosAudioQueue = [];
let iosAudioElement = null;

// Global audio queue for managing TTS playback order
let globalAudioQueue = [];
let isProcessingAudioQueue = false;
let currentAudioSequenceId = null;
let currentSegmentAudio = null; // Track current playing segment
let currentPCMSource = null; // Track current PCM audio source

// Audio queue processing delays (configurable)
const AUDIO_QUEUE_DELAY = window.AUDIO_QUEUE_DELAY || 20; // Default 20ms instead of 100ms
const AUDIO_ERROR_DELAY = window.AUDIO_ERROR_DELAY || 50; // Error retry delay

// message is submitted upon pressing enter
const message = $("#message")[0];

message.addEventListener("compositionstart", function () {
  message.dataset.ime = "true";
});

message.addEventListener("compositionend", function () {
  message.dataset.ime = "false";
});

document.addEventListener("keydown", function (event) {
  // Right Arrow key - activate voice input when Easy Submit is enabled
  if ($("#check-easy-submit").is(":checked") && !$("#message").is(":focus") && event.key === "ArrowRight") {
    event.preventDefault();
    // Only activate voice button if session has begun (config is hidden and main panel is visible)
    if ($("#voice").prop("disabled") === false && !$("#config").is(":visible") && $("#main-panel").is(":visible")) {
      $("#voice").click();
    }
  }
  
  // Enter key - submit message when focus is not in textarea
  if ($("#check-easy-submit").is(":checked") && !$("#message").is(":focus") && event.key === "Enter" && message.dataset.ime !== "true") {
    // Only submit if message is not empty
    if (message.value.trim() !== "") {
      event.preventDefault();
      $("#send").click();
    }
  }
});

// No longer handling Enter key in textarea - allow normal line break behavior
message.addEventListener("keydown", function (event) {
  // Enter key behavior in textarea is left to default (line break)
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
        copyButton.click(function () {
          const text = codeElement.text();
          const icon = copyButton.find("i");
          
          try {
            // Copy text to clipboard
            // Use document.execCommand directly
            const textarea = document.createElement('textarea');
            textarea.value = text;
            textarea.style.position = 'fixed';  // Fixed position to prevent scrolling on mobile
            textarea.style.opacity = 0;
            document.body.appendChild(textarea);
            textarea.select();
            
            const success = document.execCommand('copy');
            document.body.removeChild(textarea);
            
            if (!success) {
              throw new Error('execCommand copy failed');
            }
            
            // Show success indicator
            icon.removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
            
            // Return to normal state after delay
            setTimeout(() => {
              icon.removeClass("fa-check").addClass("fa-copy").css("color", "");
            }, 1000);
          } catch (err) {
            console.error("Failed to copy text: ", err);
            
            // Try fallback methods if execCommand fails
            try {
              if (window.electronAPI && typeof window.electronAPI.writeClipboard === 'function') {
                window.electronAPI.writeClipboard(text);
                
                // Show success indicator
                icon.removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
                
                // Return to normal state after delay
                setTimeout(() => {
                  icon.removeClass("fa-check").addClass("fa-copy").css("color", "");
                }, 1000);
              } else if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text)
                  .then(() => {
                    // Show success indicator
                    icon.removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
                    
                    // Return to normal state after delay
                    setTimeout(() => {
                      icon.removeClass("fa-check").addClass("fa-copy").css("color", "");
                    }, 1000);
                  })
                  .catch(() => {
                    // Show error indicator
                    icon.removeClass("fa-copy").addClass("fa-xmark").css("color", "#DC4C64");
                    
                    // Return to normal state after delay
                    setTimeout(() => {
                      icon.removeClass("fa-xmark").addClass("fa-copy").css("color", "");
                    }, 1000);
                  });
              } else {
                throw new Error('No clipboard API available');
              }
            } catch (fallbackErr) {
              console.error("All clipboard methods failed: ", fallbackErr);
              
              // Show error indicator
              icon.removeClass("fa-copy").addClass("fa-xmark").css("color", "#DC4C64");
              
              // Return to normal state after delay
              setTimeout(() => {
                icon.removeClass("fa-xmark").addClass("fa-copy").css("color", "");
              }, 1000);
            }
          }
        });
      }
    }
  });
}

// (reverted) removed OpenAI PDF manager refresh hook on model change

// Note: Visibility change handler is defined later in the file

//////////////////////////////
// WebSocket event handlers
//////////////////////////////

// In browser environments, wsHandlers is defined globally in websocket-handlers.js
let wsHandlers = window.wsHandlers;

const apps = {}
// Use global variables which are proxied to SessionState
// let messages = []; // Removed - using global messages instead
// let originalParams = {}; // Removed - using global originalParams instead  
// let params = {} // Removed - using global params instead

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

const mainPanel = $("#main-panel").get(0);

// Handle fragment message from streaming response
// This function will be used by the fragment_with_audio handler and all vendor helpers
window.handleFragmentMessage = function(fragment) {
  if (fragment && fragment.type === 'fragment') {
    const text = fragment.content || '';
    
    // Debug logging for GPT-5 duplicate issue
    if (window.debugFragments) {
      console.log('[Fragment Debug]', {
        content: text,
        index: fragment.index,
        timestamp: fragment.timestamp || Date.now(),
        is_first: fragment.is_first,
        lastIndex: window._lastProcessedIndex
      });
    }
    
    // Skip empty fragments
    if (!text) return;
    
    // Create or get temporary card
    let tempCard = $("#temp-card");
    if (!tempCard.length) {
      // Initialize tracking
      window._lastProcessedIndex = -1;
      
      // Only clear #chat if it exists and has content from old streaming approach
      if ($("#chat").length && $("#chat").html().trim() !== "") {
        $("#chat").empty();
      }
      
      // Create a new temporary card for streaming text
      tempCard = $(`
        <div id="temp-card" class="card mt-3 streaming-card"> 
          <div class="card-header p-2 ps-3 d-flex justify-content-between">
            <div class="fs-5 card-title mb-0">
              <span><i class="fas fa-robot" style="color: #DC4C64;"></i></span> <span class="fw-bold fs-6" style="color: #DC4C64;">Assistant</span>
            </div>
          </div>
          <div class="card-body role-assistant">
            <div class="card-text"></div>
          </div>
        </div>
      `);
      $("#discourse").append(tempCard);
    } else if (fragment.start === true || fragment.is_first === true) {
      // If this is marked as the first fragment of a streaming response, clear the existing content
      $("#temp-card .card-text").empty();
      window._lastProcessedIndex = -1;
    }
    
    // Check for duplicate fragments by index
    if (fragment.index !== undefined) {
      if (window._lastProcessedIndex !== undefined && window._lastProcessedIndex >= fragment.index) {
        // Skip duplicate or out-of-order fragments
        if (window.debugFragments) {
          console.log('[Fragment Debug] Skipping duplicate - index:', fragment.index, 'lastIndex:', window._lastProcessedIndex);
        }
        return;
      }
      window._lastProcessedIndex = fragment.index;
    } else {
      // If no index is provided, use timestamp-based duplicate detection
      // This is a fallback for providers that don't send index
      const now = Date.now();
      const fragmentKey = `${text}_${fragment.timestamp || now}`;
      
      // Check if we've seen this exact fragment (content + timestamp) recently
      if (window._recentFragments && window._recentFragments[fragmentKey]) {
        if (window.debugFragments) {
          console.log('[Fragment Debug] Skipping duplicate fragment - content:', text);
        }
        return;
      }
      
      // Store this fragment temporarily
      window._recentFragments = window._recentFragments || {};
      window._recentFragments[fragmentKey] = now;
      
      // Clean up old entries after 1 second
      setTimeout(() => {
        delete window._recentFragments[fragmentKey];
      }, 1000);
    }
    
    // Add to streaming text display
    const tempText = $("#temp-card .card-text");
    if (tempText.length) {
      // Debug: Log current text content before adding
      if (window.debugFragments) {
        console.log('[Fragment Debug] Before append - DOM text length:', tempText[0].textContent.length);
        console.log('[Fragment Debug] Adding fragment:', text);
      }
      
      // Use DocumentFragment for efficient DOM manipulation while preserving newlines
      const docFrag = document.createDocumentFragment();
      const lines = text.split('\n');
      
      lines.forEach((line, index) => {
        // Add line break for all lines except the first
        if (index > 0) {
          docFrag.appendChild(document.createElement('br'));
        }
        // Add text node for each line (automatically escapes HTML)
        if (line) {
          docFrag.appendChild(document.createTextNode(line));
        }
      });
      
      // Append all at once for better performance
      tempText[0].appendChild(docFrag);
      
      // Debug: Log after append
      if (window.debugFragments) {
        console.log('[Fragment Debug] After append - DOM text length:', tempText[0].textContent.length);
      }
    }
    
    // If this is a final fragment, clean up
    if (fragment.final) {
      window._lastProcessedIndex = -1;
    }
  }
};
// Make defaultApp globally available
window.defaultApp = DEFAULT_APP;

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

// Media Source Extensions support detection
const hasMediaSourceSupport = typeof MediaSource !== 'undefined';

// Audio Context API support detection (broader compatibility than MediaSource)
const hasAudioContextSupport = typeof (window.AudioContext || window.webkitAudioContext) !== 'undefined';

// iOS detection
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
const isIPad = /iPad/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const isMobileIOS = isIOS && !isIPad;

// Additional useful browser detection
const isChrome = /Chrome/.test(navigator.userAgent) && !/Edge/.test(navigator.userAgent);
const isSafari = /Safari/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent);
const isFirefox = /Firefox/.test(navigator.userAgent);

// Log platform detection for debugging
// Browser capabilities detected: MediaSource, AudioContext, device type, and browser

// Create an AudioContext for iOS fallback if MediaSource isn't available but AudioContext is
let audioContext = null;
if (!hasMediaSourceSupport && hasAudioContextSupport && isIOS) {
  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    audioContext = new AudioContextClass();
    
  } catch (e) {
    console.error("[Audio] Failed to create AudioContext:", e);
  }
}

// Initialize mediaSource only if supported
let mediaSource = null;
let audio = null;
let sourceBuffer = null;
let audioDataQueue = [];
const MAX_AUDIO_QUEUE_SIZE = 50; // Maximum number of audio chunks to keep in queue

// Export to window for global access
window.mediaSource = mediaSource;
window.audio = audio;


// Function to add to global audio queue (used for segmented playback)
window.addToGlobalAudioQueue = function(audioItem) {
  globalAudioQueue.push(audioItem);
  
  // Process the queue if not already processing
  if (!isProcessingAudioQueue) {
    processGlobalAudioQueue();
  }
};


// Initialize MediaSource for audio playback
function initializeMediaSourceForAudio() {
  if ('MediaSource' in window && !window.basicAudioMode) {
    try {
      mediaSource = new MediaSource();
      
      mediaSource.addEventListener('sourceopen', function() {
        
        
        if (!sourceBuffer && mediaSource.readyState === 'open') {
          try {
            // Check browser and set appropriate codec
            if (navigator.userAgent.toLowerCase().indexOf('firefox') > -1) {
              
              window.firefoxAudioMode = true;
              window.firefoxAudioQueue = [];
            } else {
              
              sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
              sourceBuffer.addEventListener('updateend', processAudioDataQueue);
            }
          } catch (e) {
            console.error("Error setting up MediaSource: ", e);
            window.basicAudioMode = true;
          }
        }
      });
      
      // Create audio element
      if (!audio) {
        audio = new Audio();
        audio.src = URL.createObjectURL(mediaSource);
        window.audio = audio; // Export to window for global access
        
        
        // Set up event listener for automatic playback
        audio.addEventListener('canplay', function() {
          // If auto-speech is active or play button was pressed, start playback automatically
          if (window.autoSpeechActive || window.autoPlayAudio) {
            const playPromise = audio.play();
            if (playPromise !== undefined) {
              playPromise.then(() => {
                
              }).catch(err => {
                // Debug log removed
                if (err.name === 'NotAllowedError') {
                  // Create a one-time click handler to enable audio
                  const enableAudio = function() {
                    audio.play().then(() => {
                      
                      document.removeEventListener('click', enableAudio);
                    }).catch(e => {
                      console.error("[Audio] Failed to start playback:", e);
                    });
                  };
                  document.addEventListener('click', enableAudio);
                  const clickAudioText = getTranslation('ui.messages.clickToEnableAudio', 'Click anywhere to enable audio');
          setAlert(`<i class="fas fa-volume-up"></i> ${clickAudioText}`, 'info');
                }
              });
            }
          }
        });
      }
      
    } catch (e) {
      console.error("Error creating MediaSource: ", e);
      window.basicAudioMode = true;
    }
  } else {
    
    window.basicAudioMode = true;
  }
}

// Reset audio elements when switching TTS modes
function resetAudioElements() {
  
  
  // Stop and clean up current audio completely
  if (audio) {
    if (!audio.paused) {
      audio.pause();
    }
    audio.currentTime = 0;
    if (audio.src) {
      // Don't revoke immediately, let the browser clean up
      const srcToRevoke = audio.src;
      setTimeout(() => URL.revokeObjectURL(srcToRevoke), 100);
      audio.src = '';
    }
    audio.load(); // Force the audio element to release resources
    audio = null;
  }
  
  // Clean up MediaSource
  if (mediaSource) {
    if (sourceBuffer && mediaSource.readyState === 'open') {
      try {
        sourceBuffer.abort();
        mediaSource.removeSourceBuffer(sourceBuffer);
      } catch (e) {
        // Debug log removed
      }
    }
    
    // End the media source if still open
    if (mediaSource.readyState === 'open') {
      try {
        mediaSource.endOfStream();
      } catch (e) {
        // Debug log removed
      }
    }
  }
  
  // Reset all variables
  mediaSource = null;
  sourceBuffer = null;
  audioDataQueue = [];
  
  // Reset browser-specific flags
  window.basicAudioMode = false;
  window.firefoxAudioMode = false;
  window.firefoxAudioQueue = [];
  
  // Clear any iOS-specific state
  iosAudioBuffer = [];
  isIOSAudioPlaying = false;
  iosAudioQueue = [];
  if (iosAudioElement) {
    iosAudioElement.pause();
    iosAudioElement = null;
  }
  
  
}

// Direct audio playback for iOS devices or browsers without MediaSource support
function playAudioDirectly(audioData) {
  try {
    // For iOS devices, use the specialized iOS playback method
    if (isIOS) {
      playWithAudioElement(audioData);
      return;
    }
    
    // For other platforms with AudioContext support
    if (audioContext && hasAudioContextSupport) {
      if (audioContext.state === 'suspended') {
        audioContext.resume();
      }
      
      // Make sure we're working with a Uint8Array
      const uint8Data = (audioData instanceof Uint8Array) ? audioData : new Uint8Array(audioData);
      
      // Create ArrayBuffer from the data
      const arrayBuffer = uint8Data.buffer.slice(uint8Data.byteOffset, uint8Data.byteOffset + uint8Data.byteLength);
      
      // Decode and play the audio
      audioContext.decodeAudioData(arrayBuffer)
        .then(buffer => {
          const source = audioContext.createBufferSource();
          source.buffer = buffer;
          source.connect(audioContext.destination);
          source.start(0);
        })
        .catch(() => {
          // Fall back to Audio element on decoding error
          playWithAudioElement(audioData);
        });
        
      // Timeout failsafe
      setTimeout(() => {
        if (audioContext.state === 'running') {
          playWithAudioElement(audioData);
        }
      }, 3000); 
    } else {
      // No AudioContext support, use basic Audio element
      playWithAudioElement(audioData);
    }
  } catch (e) {
    // Final fallback
    playWithAudioElement(audioData);
  }
}

// Helper function for audio element playback (fallback method)
function playWithAudioElement(audioData) {
  // For iOS Safari, use a different approach
  if (isIOS) {
    playAudioForIOS(audioData);
    return;
  }
  
  // For other browsers, use standard Audio API
  try {
    // Create a Blob from the audio data
    const mimeTypes = ['audio/mpeg', 'audio/mp3', 'audio/aac', 'audio/ogg'];
    let blob = null;
    
    // Try mime types until one works
    for (const mimeType of mimeTypes) {
      try {
        blob = new Blob([audioData], { type: mimeType });
        break;
      } catch (e) {
        // Continue to next mime type
      }
    }
    
    // Default fallback
    if (!blob) {
      blob = new Blob([audioData], { type: 'audio/mpeg' });
    }
    
    const audioUrl = URL.createObjectURL(blob);
    const audioElement = new Audio();
    
    // Clean up when finished
    audioElement.onended = function() {
      URL.revokeObjectURL(audioUrl);
    };
    
    audioElement.onerror = function() {
      URL.revokeObjectURL(audioUrl);
    };
    
    // Play audio
    audioElement.src = audioUrl;
    audioElement.play().catch(() => {
      URL.revokeObjectURL(audioUrl);
    });
  } catch (e) {
    // Silent fail - no further fallback needed
  }
}

// Global audio queue management
function addToAudioQueue(audioData, sequenceId, mimeType) {
  globalAudioQueue.push({
    data: audioData,
    sequenceId: sequenceId,
    timestamp: Date.now(),
    mimeType: mimeType // Store MIME type if provided
  });
  
  // Start processing if not already running
  if (!isProcessingAudioQueue) {
    processGlobalAudioQueue();
  }
}

// Process the global audio queue to ensure sequential playback
function processGlobalAudioQueue() {
  if (globalAudioQueue.length === 0) {
    isProcessingAudioQueue = false;
    currentAudioSequenceId = null;
    return;
  }
  
  isProcessingAudioQueue = true;
  const audioItem = globalAudioQueue.shift();
  currentAudioSequenceId = audioItem.sequenceId;
  
  // Choose appropriate playback method based on device
  if (window.isIOS || window.basicAudioMode) {
    playAudioForIOSFromQueue(audioItem.data);
  } else {
    playAudioFromQueue(audioItem); // Pass full item including mimeType
  }
}

// Clear the audio queue (used by stop button)
function clearAudioQueue() {
  globalAudioQueue = [];
  isProcessingAudioQueue = false;
  currentAudioSequenceId = null;
  
  // Stop current segment if playing
  if (currentSegmentAudio) {
    try {
      currentSegmentAudio.pause();
      currentSegmentAudio.src = "";
      currentSegmentAudio = null;
    } catch (e) {
      console.warn("Error stopping current segment:", e);
    }
  }
  
  // Stop current PCM source if playing
  if (currentPCMSource) {
    try {
      currentPCMSource.stop();
      currentPCMSource = null;
    } catch (e) {
      console.warn("Error stopping PCM source:", e);
    }
  }
  
  // Also clear iOS-specific buffers
  iosAudioBuffer = [];
  isIOSAudioPlaying = false;
  
  // Clear other audio queues
  if (typeof audioDataQueue !== 'undefined') {
    audioDataQueue = [];
  }
  if (typeof window.firefoxAudioQueue !== 'undefined') {
    window.firefoxAudioQueue = [];
  }
}

// Main audio processing function
function processAudio(audioData) {
  try {
    // Initialize audioDataQueue if not already initialized
    if (!audioDataQueue) {
      audioDataQueue = [];
    }
    
    // Ensure MediaSource is initialized if not already
    if (!mediaSource && 'MediaSource' in window && !window.basicAudioMode) {
      
      initializeMediaSourceForAudio();
    }
    
    // Handle based on browser environment
    if (window.firefoxAudioMode) {
      if (!window.firefoxAudioQueue) {
        window.firefoxAudioQueue = [];
      }
      
      // Firefox audio queue management
      window.firefoxAudioQueue.push(audioData);
      processAudioDataQueue();
    } else if (window.basicAudioMode || window.isIOS) {
      // For iOS and other devices without MediaSource
      playAudioDirectly(audioData);
    } else {
      // Standard approach for modern browsers
      audioDataQueue.push(audioData);
      processAudioDataQueue();
      
      // Ensure audio playback starts automatically
      if (audio && audio.paused) {
        audio.play().catch(err => {
          // Debug log removed
          // User interaction might be required
          if (err.name === 'NotAllowedError') {
            const clickAudioText = getTranslation('ui.messages.clickToEnableAudioSimple', 'Click to enable audio');
            setAlert(`<i class="fas fa-volume-up"></i> ${clickAudioText}`, 'info');
          }
        });
      }
    }
  } catch (e) {
    console.error("Error in audio processing:", e);
  }
}

// Play audio from queue for standard browsers
function playAudioFromQueue(audioItem) {
  try {
    // Extract data and mimeType from audioItem
    const audioData = audioItem.data || audioItem;
    const mimeType = audioItem.mimeType;
    
    // Check if this is PCM audio from Gemini
    if (mimeType && mimeType.includes("audio/L16")) {
      // Extract sample rate from MIME type
      const mimeMatch = mimeType.match(/rate=(\d+)/);
      const sampleRate = mimeMatch ? parseInt(mimeMatch[1]) : 24000;
      
      // Use the PCM playback function
      playPCMAudio(audioData, sampleRate);
      
      // Handle queue processing after PCM playback
      // Note: playPCMAudio handles its own completion callback
      // so we need to modify it to continue queue processing
      window.ttsPlaybackCallback = function() {
        // Process next segment immediately
        isProcessingAudioQueue = false;
        processGlobalAudioQueue();
      };
      return;
    }
    
    // For non-PCM audio, use standard blob playback
    const blob = new Blob([audioData], { type: mimeType || 'audio/mpeg' });
    const audioUrl = URL.createObjectURL(blob);
    
    // Create a new audio element for this segment
    const segmentAudio = new Audio();
    currentSegmentAudio = segmentAudio; // Track current segment
    
    segmentAudio.onended = function() {
      // Clean up
      URL.revokeObjectURL(audioUrl);
      currentSegmentAudio = null; // Clear reference
      // Process next segment in queue immediately
      isProcessingAudioQueue = false;
      processGlobalAudioQueue();
    };
    
    segmentAudio.onerror = function(e) {
      console.error("Segment audio error:", e);
      URL.revokeObjectURL(audioUrl);
      currentSegmentAudio = null; // Clear reference
      // Try next segment immediately
      isProcessingAudioQueue = false;
      processGlobalAudioQueue();
    };
    
    // Set source and play
    segmentAudio.src = audioUrl;
    segmentAudio.play().then(() => {
      // Playing TTS segment
    }).catch(err => {
      console.error("Failed to play segment:", err);
      URL.revokeObjectURL(audioUrl);
      currentSegmentAudio = null; // Clear reference
      // Try next segment immediately
      isProcessingAudioQueue = false;
      processGlobalAudioQueue();
    });
    
  } catch (e) {
    console.error("Error in playAudioFromQueue:", e);
    // Try next segment immediately
    isProcessingAudioQueue = false;
    processGlobalAudioQueue();
  }
}

// Special function for iOS audio playback with queue support
function playAudioForIOSFromQueue(audioData) {
  try {
    // Add to iOS buffer
    iosAudioBuffer.push(audioData);
    
    // Process if not already playing
    if (!isIOSAudioPlaying) {
      processIOSAudioBufferWithQueue();
    }
  } catch (e) {
    // Continue with next item on error
    setTimeout(() => processGlobalAudioQueue(), AUDIO_ERROR_DELAY);
  }
}

// Modified iOS buffer processor with queue support
function processIOSAudioBufferWithQueue() {
  if (iosAudioBuffer.length === 0) {
    isIOSAudioPlaying = false;
    // Process next item in global queue
    setTimeout(() => processGlobalAudioQueue(), AUDIO_QUEUE_DELAY);
    return;
  }
  
  isIOSAudioPlaying = true;
  
  try {
    // Combine all buffered chunks
    let totalLength = 0;
    iosAudioBuffer.forEach(chunk => totalLength += chunk.length);
    
    const combinedData = new Uint8Array(totalLength);
    let offset = 0;
    
    iosAudioBuffer.forEach(chunk => {
      combinedData.set(chunk, offset);
      offset += chunk.length;
    });
    
    iosAudioBuffer = [];
    
    // Create and play audio
    const blob = new Blob([combinedData], { type: 'audio/mpeg' });
    const blobUrl = URL.createObjectURL(blob);
    
    if (!iosAudioElement) {
      iosAudioElement = new Audio();
    }
    
    iosAudioElement.onended = function() {
      isIOSAudioPlaying = false;
      URL.revokeObjectURL(blobUrl);
      // Process next item in global queue
      setTimeout(() => processGlobalAudioQueue(), AUDIO_QUEUE_DELAY);
    };
    
    iosAudioElement.onerror = function() {
      isIOSAudioPlaying = false;
      URL.revokeObjectURL(blobUrl);
      // Process next item in global queue even on error
      setTimeout(() => processGlobalAudioQueue(), AUDIO_QUEUE_DELAY);
    };
    
    iosAudioElement.src = blobUrl;
    iosAudioElement.play().catch(err => {
      isIOSAudioPlaying = false;
      URL.revokeObjectURL(blobUrl);
      // Process next item in global queue
      setTimeout(() => processGlobalAudioQueue(), AUDIO_QUEUE_DELAY);
    });
    
  } catch (e) {
    isIOSAudioPlaying = false;
    // Process next item in global queue
    setTimeout(() => processGlobalAudioQueue(), AUDIO_QUEUE_DELAY);
  }
}

// Special function for iOS audio playback with buffering (legacy support)
function playAudioForIOS(audioData) {
  try {
    // Add current chunk to our global buffer
    iosAudioBuffer.push(audioData);
    
    // Don't start playback if we're already playing
    if (isIOSAudioPlaying) {
      return;
    }
    
    // Process the buffer
    processIOSAudioBuffer();
  } catch (e) {
    // Silent error handling
  }
}

// Process the iOS audio buffer to play chunks in sequence
function processIOSAudioBuffer() {
  // If no data in buffer, we're done
  if (iosAudioBuffer.length === 0) {
    isIOSAudioPlaying = false;
    return;
  }
  
  // Set playing flag
  isIOSAudioPlaying = true;
  
  try {
    // Combine all buffered chunks into a single Uint8Array
    let totalLength = 0;
    iosAudioBuffer.forEach(chunk => totalLength += chunk.length);
    
    const combinedData = new Uint8Array(totalLength);
    let offset = 0;
    
    iosAudioBuffer.forEach(chunk => {
      combinedData.set(chunk, offset);
      offset += chunk.length;
    });
    
    // Clear buffer now that we've combined the data
    iosAudioBuffer = [];
    
    // Create blob with audio data
    const mimeTypes = ['audio/mpeg', 'audio/mp3', 'audio/aac', 'audio/mp4'];
    let blob = null;
    
    // Try each MIME type
    for (const type of mimeTypes) {
      try {
        blob = new Blob([combinedData], { type });
        break;
      } catch (e) {
        // Try next type
      }
    }
    
    // Fallback if needed
    if (!blob) {
      blob = new Blob([combinedData], { type: 'audio/mpeg' });
    }
    
    const blobUrl = URL.createObjectURL(blob);
    
    // Create or reuse audio element
    if (!iosAudioElement) {
      iosAudioElement = new Audio();
      
      // Set up handlers
      iosAudioElement.onended = function() {
        isIOSAudioPlaying = false;
        
        // Process any new chunks that arrived during playback
        if (iosAudioBuffer.length > 0) {
          setTimeout(processIOSAudioBuffer, AUDIO_QUEUE_DELAY);
        }
        
        // Clean up URL
        if (iosAudioElement.src) {
          URL.revokeObjectURL(iosAudioElement.src);
        }
      };
      
      iosAudioElement.onerror = function() {
        isIOSAudioPlaying = false;
        
        // Clean up URL
        if (iosAudioElement.src) {
          URL.revokeObjectURL(iosAudioElement.src);
        }
        
        // Check if we have more chunks to try
        if (iosAudioBuffer.length > 0) {
          setTimeout(processIOSAudioBuffer, AUDIO_QUEUE_DELAY);
        }
      };
    } else if (iosAudioElement.src) {
      // Clean up previous URL if needed
      URL.revokeObjectURL(iosAudioElement.src);
    }
    
    // Configure for iOS
    iosAudioElement.controls = false;
    iosAudioElement.playsinline = true;
    iosAudioElement.muted = false;
    iosAudioElement.autoplay = false;  // iOS requires user interaction
    
    // Set new source and load
    iosAudioElement.src = blobUrl;
    iosAudioElement.load();
    
    // Play with error handling - ensure autoplay for auto_speech
    iosAudioElement.play()
      .then(() => {
        // Playback started successfully
        
      })
      .catch((err) => {
        // Debug log removed
        isIOSAudioPlaying = false;
        URL.revokeObjectURL(blobUrl);
        
        // Show indicator if user interaction is required
        if (err.name === 'NotAllowedError') {
          const tapAudioText = getTranslation('ui.messages.tapToEnableIOSAudio', 'Tap to enable iOS audio');
          setAlert(`<i class="fas fa-volume-up"></i> ${tapAudioText}`, 'info');
        }
      });
      
  } catch (e) {
    isIOSAudioPlaying = false;
    
    // Try to process any remaining chunks
    if (iosAudioBuffer.length > 0) {
      setTimeout(processIOSAudioBuffer, AUDIO_QUEUE_DELAY);
    }
  }
}

// Function to play PCM audio data from Gemini
function playPCMAudio(pcmData, sampleRate) {
  try {
    // Initialize audio context if needed
    if (typeof audioInit === 'function') {
      audioInit();
    }
    
    // Create AudioContext if not exists
    if (!window.audioCtx) {
      window.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    
    // PCM is 16-bit linear, so we need to convert from bytes to float32
    const numSamples = pcmData.length / 2; // 2 bytes per sample
    const audioBuffer = window.audioCtx.createBuffer(1, numSamples, sampleRate);
    const channelData = audioBuffer.getChannelData(0);
    
    // Convert 16-bit PCM to float32
    for (let i = 0; i < numSamples; i++) {
      // Read 16-bit signed integer (little-endian)
      const sample = (pcmData[i * 2] | (pcmData[i * 2 + 1] << 8));
      // Convert to signed value
      const signedSample = sample < 0x8000 ? sample : sample - 0x10000;
      // Normalize to [-1, 1] range
      channelData[i] = signedSample / 32768.0;
    }
    
    // Create a buffer source and play it
    const source = window.audioCtx.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(window.audioCtx.destination);
    currentPCMSource = source; // Track the current source
    
    // Handle playback end
    source.onended = function() {
      $("#monadic-spinner").hide();
      currentPCMSource = null; // Clear reference
      
      // Trigger any callbacks if needed
      if (window.ttsPlaybackCallback) {
        window.ttsPlaybackCallback(true);
      }
    };
    
    // Start playback
    source.start(0);
    
  } catch (error) {
    console.error("Error playing PCM audio:", error);
    $("#monadic-spinner").hide();
    
    // Try fallback method - convert to WAV format
    try {
      const wavBlob = createWAVFromPCM(pcmData, sampleRate);
      const blobUrl = URL.createObjectURL(wavBlob);
      
      // Use standard audio element as fallback
      const audio = new Audio(blobUrl);
      audio.onended = function() {
        URL.revokeObjectURL(blobUrl);
        $("#monadic-spinner").hide();
      };
      audio.play().catch(err => {
        console.error("Fallback audio playback failed:", err);
        $("#monadic-spinner").hide();
      });
    } catch (fallbackError) {
      console.error("WAV fallback also failed:", fallbackError);
      $("#monadic-spinner").hide();
    }
  }
}

// Helper function to create WAV file from PCM data
function createWAVFromPCM(pcmData, sampleRate) {
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * bitsPerSample / 8;
  const blockAlign = numChannels * bitsPerSample / 8;
  const dataSize = pcmData.length;
  
  // Create WAV header
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);
  
  // "RIFF" chunk descriptor
  const writeString = (offset, string) => {
    for (let i = 0; i < string.length; i++) {
      view.setUint8(offset + i, string.charCodeAt(i));
    }
  };
  
  writeString(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeString(8, 'WAVE');
  
  // "fmt " sub-chunk
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true); // Subchunk1Size
  view.setUint16(20, 1, true); // AudioFormat (PCM)
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);
  
  // "data" sub-chunk
  writeString(36, 'data');
  view.setUint32(40, dataSize, true);
  
  // Copy PCM data
  const dataArray = new Uint8Array(buffer, 44);
  dataArray.set(pcmData);
  
  return new Blob([buffer], { type: 'audio/wav' });
}

function processAudioDataQueue() {
  if (window.basicAudioMode) {
    // In basic mode (iOS), audio is handled differently via playAudioDirectly
    return;
  }
  
  if (!mediaSource || !sourceBuffer) {
    return;
  }
  
  if (mediaSource.readyState === 'open' && audioDataQueue.length > 0 && !sourceBuffer.updating) {
    const audioData = audioDataQueue.shift();
    try {
      sourceBuffer.appendBuffer(audioData);
      
      // For segmented playback, ensure continuous playback
      if (audio && audio.paused && audio.readyState >= 2) {
        audio.play().catch(err => {
          // Debug log removed
        });
      }
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
// Track if we're currently streaming a response
let streamingResponse = false; // Keep local variable for backward compatibility
// Track spinner check interval to prevent duplicates
window.spinnerCheckInterval = null;

function connect_websocket(callback) {
  // Use current hostname if available, otherwise default to localhost
  let wsUrl = 'ws://localhost:4567';
  
  // If accessing from a non-localhost address, use that instead
  if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
    const host = window.location.hostname;
    const port = window.location.port || '4567';
    wsUrl = `ws://${host}:${port}`;
    console.log(`[WebSocket] Using hostname from browser: ${wsUrl}`);
  }
  
  console.log(`[WebSocket] Connecting to: ${wsUrl}`);
  const ws = new WebSocket(wsUrl);

// Tracks which app was loaded from server parameters/import. Keep empty by default.
let loadedApp = "Chat";
  let infoHtml = "";

  ws.onopen = function () {
    console.log(`[WebSocket] Connection established successfully to ${wsUrl}`);
    // Update state if available
    if (window.UIState) {
      window.UIState.set('wsConnected', true);
      window.UIState.set('wsReconnecting', false);
    }
    const verifyingText = typeof webUIi18n !== 'undefined' ? 
      webUIi18n.t('ui.messages.verifyingToken') : 'Verifying token';
    setAlert(`<i class='fa-solid fa-bolt'></i> ${verifyingText}`, "warning");
    // Get UI language from cookie or default to 'en'
    const uiLanguage = document.cookie.match(/ui-language=([^;]+)/)?.[1] || 'en';
    ws.send(JSON.stringify({ 
      message: "CHECK_TOKEN", 
      initial: true, 
      contents: $("#token").val(),
      ui_language: uiLanguage 
    }));

    // Detect browser/device capabilities for audio handling
    const runningOnFirefox = navigator.userAgent.indexOf('Firefox') !== -1;
    
    console.log(`[Device Detection] Details - hasMediaSourceSupport: ${hasMediaSourceSupport}, isIOS: ${isIOS}, isIPad: ${isIPad}, isMobileIOS: ${isMobileIOS}, Firefox: ${runningOnFirefox}`);
    
    // Setup media handling based on browser capabilities
    if (hasMediaSourceSupport && !isMobileIOS) {
      // Full MediaSource support available (desktop browsers, iPad)
      if (!mediaSource) {
        
        try {
          mediaSource = new MediaSource();
          mediaSource.addEventListener('sourceopen', function() {
            try {
              // Check if mediaSource is still valid and in correct state
              if (!mediaSource || mediaSource.readyState !== 'open') {
                // This is expected during sourceopen event - MediaSource transitions to 'open'
                // No warning needed as this is normal behavior
                if (mediaSource && mediaSource.readyState === 'closed') {
                  // MediaSource was closed, fall back to basic mode
                  window.basicAudioMode = true;
                  return;
                }
                // Otherwise, continue - sourceopen event means it's transitioning to open
              }
              
              if (runningOnFirefox) {
                // Firefox needs special handling
                
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
                // Check if mediaSource is valid before using it
                if (!mediaSource) {
                  console.warn("MediaSource is null, falling back to basic audio mode");
                  window.basicAudioMode = true;
                  return;
                }
                
                sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
                sourceBuffer.addEventListener('updateend', processAudioDataQueue);
              }
            } catch (e) {
              console.error("Error setting up MediaSource: ", e);
              // Fallback to basic audio mode if MediaSource setup fails
              
              window.basicAudioMode = true;
            }
          });
        } catch (e) {
          console.error("Error creating MediaSource: ", e);
          // Fallback to basic audio mode if MediaSource creation fails
          
          window.basicAudioMode = true;
        }
      }

      if (!audio && mediaSource) {
        try {
          // Reset if switching from Web Speech API mode
          if (window.lastTTSMode === 'web_speech') {
            resetAudioElements();
            // Re-create MediaSource after reset
            if ('MediaSource' in window && !window.basicAudioMode) {
              try {
                mediaSource = new MediaSource();
              } catch (e) {
                console.error("Error creating MediaSource after reset: ", e);
                window.basicAudioMode = true;
              }
            }
          }
          
          audio = new Audio();
          audio.src = URL.createObjectURL(mediaSource);
          window.audio = audio; // Export to window for global access
        } catch (e) {
          console.error("Error creating audio element: ", e);
          // Fallback to basic audio mode
          
          window.basicAudioMode = true;
        }
      }
    } else {
      // No MediaSource support (iOS Safari) - use basic audio mode
      
      window.basicAudioMode = true;
      
      // Add a CSS class to body for iOS-specific styling if needed
      if (isIOS) {
        $("body").addClass("ios-device");
        if (isMobileIOS) {
          $("body").addClass("mobile-ios-device");
        } else if (isIPad) {
          $("body").addClass("ipad-device");
        }
      }
    }

    // Only verify token once
    if (!verified) {
      const verifyingText = typeof webUIi18n !== 'undefined' ? 
      webUIi18n.t('ui.messages.verifyingToken') : 'Verifying token';
    setAlert(`<i class='fa-solid fa-bolt'></i> ${verifyingText}`, "warning");
      // Get UI language from cookie or default to 'en'
    const uiLanguage = document.cookie.match(/ui-language=([^;]+)/)?.[1] || 'en';
    ws.send(JSON.stringify({ 
      message: "CHECK_TOKEN", 
      initial: true, 
      contents: $("#token").val(),
      ui_language: uiLanguage 
    }));
    }

    // Check verified status at a regular interval
    let verificationCheckTimer = setInterval(function () {
      if (verified) {
        if (!initialLoadComplete) {  // Only send LOAD on initial connection
          // Get UI language from cookie or default to 'en'
          const uiLanguage = document.cookie.match(/ui-language=([^;]+)/)?.[1] || 'en';
          ws.send(JSON.stringify({ "message": "LOAD", "ui_language": uiLanguage }));
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
    // Mark import flow to preserve app/model/group during proceedWithAppChange
    if (typeof window !== 'undefined') {
      window.isImporting = true;
      window.lastImportTime = Date.now();
    }
    // Only update if the values are not already set correctly
    if (parameters.app_name && $("#apps").val() !== parameters.app_name) {
      $("#apps").val(parameters.app_name).trigger('change');
      // Update overlay icon immediately to avoid blank state until proceedWithAppChange runs
      if (typeof updateAppSelectIcon === 'function') {
        setTimeout(() => updateAppSelectIcon(parameters.app_name), 0);
      }
    }
    // Wait for app change to complete before setting model
    setTimeout(() => {
      if (parameters.model && $("#model").val() !== parameters.model) {
        $("#model").val(parameters.model).trigger('change');
      }
      // End of import flow; allow normal app/model changes afterwards
      if (typeof window !== 'undefined') {
        setTimeout(() => { window.isImporting = false; }, 500);
      }
    }, 200);
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
    // Register a safety timeout to prevent UI getting stuck in disabled state
    // This will be cleared for normal responses but will run if something goes wrong
    // Use longer timeout for providers known to have slower initial responses
    const currentProvider = window.currentLLMProvider || '';
    const isSlowProvider = ['deepseek', 'perplexity'].includes(currentProvider.toLowerCase());
    const timeoutDuration = isSlowProvider ? 60000 : 30000; // 60s for slow providers, 30s for others
    
    const messageTimeout = setTimeout(function() {
      if ($("#user-panel").is(":visible") && $("#send").prop("disabled")) {
        
        $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import, #ai_user").prop("disabled", false);
        $("#message").prop("disabled", false);
        $("#select-role").prop("disabled", false);
        $("#monadic-spinner").hide();
        $("#cancel_query").hide();
        
        // Reset state flags
        if (window.responseStarted !== undefined) window.responseStarted = false;
        if (window.callingFunction !== undefined) window.callingFunction = false;
        if (window.streamingResponse !== undefined) window.streamingResponse = false;
        
        const providerInfo = isSlowProvider ? ` (${currentProvider} may have slower initial responses)` : '';
        const timedOutText = typeof webUIi18n !== 'undefined' ? 
          webUIi18n.t('ui.messages.operationTimedOut') : 'Operation timed out. UI reset.';
        setAlert(`<i class='fas fa-exclamation-triangle'></i> ${timedOutText}${providerInfo}`, "warning");
      }
    }, timeoutDuration);  // Dynamic timeout based on provider
    
    let data;
    try {
      data = JSON.parse(event.data);
      
      // Clear the safety timeout for valid responses
      clearTimeout(messageTimeout);
    } catch (error) {
      console.error("Error parsing WebSocket message:", error, event.data);
      clearTimeout(messageTimeout);
      return;
    }
    switch (data["type"]) {
      case "fragment_with_audio": {
        // Handle the optimized combined fragment and audio message
        let handled = false;
        
        if (wsHandlers && typeof wsHandlers.handleFragmentWithAudio === 'function') {
          // Create audio processing function similar to the one in handleAudioMessage
          const processAudio = (audioData) => {
            try {
              // Ensure MediaSource is initialized if not already
              if (!mediaSource && 'MediaSource' in window && !window.basicAudioMode) {
                
                initializeMediaSourceForAudio();
              }
              
              // Handle based on browser environment
              if (window.firefoxAudioMode) {
                if (!window.firefoxAudioQueue) {
                  window.firefoxAudioQueue = [];
                }
                
                if (window.firefoxAudioQueue.length >= MAX_AUDIO_QUEUE_SIZE) {
                  window.firefoxAudioQueue = window.firefoxAudioQueue.slice(Math.floor(MAX_AUDIO_QUEUE_SIZE / 2));
                }
                
                window.firefoxAudioQueue.push(audioData);
                processAudioDataQueue();
              } else if (window.basicAudioMode) {
                // For iOS and other devices without MediaSource
                playAudioDirectly(audioData);
              } else {
                // Standard approach for modern browsers
                audioDataQueue.push(audioData);
                processAudioDataQueue();
                
                // Ensure audio playback starts automatically for auto_speech
              if (audio) {
                // Always attempt to play, even if not paused (may be needed for some browsers)
                audio.play().catch(err => {
                  // Debug log removed
                  
                  // User interaction might be required, show indicator
                  if (err.name === 'NotAllowedError') {
                    const clickAudioText = getTranslation('ui.messages.clickToEnableAudioSimple', 'Click to enable audio');
            setAlert(`<i class="fas fa-volume-up"></i> ${clickAudioText}`, 'info');
                  }
                });
              }
              }
            } catch (e) {
              console.error("Error in audio processing:", e);
            }
          };
          
          // Pass the message and processing function to the handler
          handled = wsHandlers.handleFragmentWithAudio(data, processAudio);
        }
        
        if (!handled) {
          console.warn("Combined fragment_with_audio message was not handled properly");
        }
        
        break;
      }
      
      case "wait": {
        callingFunction = true;
        
        // Check if content is a translation key
        let waitContent = data["content"];
        if (waitContent === 'generating_ai_user_response') {
          waitContent = getTranslation('ui.messages.generatingAIUserResponse', 'Generating AI user response...');
        }
        
        setAlert(waitContent, "warning");
        
        // Show the spinner and update its message based on the content
        $("#monadic-spinner").show();
        
        // Customize spinner message based on wait content
        if (data["content"].includes("CALLING FUNCTIONS")) {
          const callingFunctionsText = getTranslation('ui.messages.spinnerCallingFunctions', 'Calling functions');
          $("#monadic-spinner span").html(`<i class="fas fa-cogs fa-pulse"></i> ${callingFunctionsText}`);
        } else if (data["content"].includes("SEARCHING WEB")) {
          const searchingWebText = getTranslation('ui.messages.spinnerSearchingWeb', 'Searching web');
          $("#monadic-spinner span").html(`<i class="fas fa-search fa-pulse"></i> ${searchingWebText}`);
        } else if (data["content"].includes("PROCESSING")) {
          const processingText = getTranslation('ui.messages.spinnerProcessing', 'Processing');
          $("#monadic-spinner span").html(`<i class="fas fa-spinner fa-pulse"></i> ${processingText}`);
        } else {
          const processingRequestText = getTranslation('ui.messages.spinnerProcessingRequest', 'Processing request');
          $("#monadic-spinner span").html(`<i class="fas fa-brain fa-pulse"></i> ${processingRequestText}`);
        }
        break;
      }

      case "web_speech": {
        // Handle Web Speech API text
        window.lastTTSMode = 'web_speech';
        $("#monadic-spinner").hide();
        
        if (window.speechSynthesis && typeof window.ttsSpeak === 'function') {
          try {
            // Get text from data
            const text = data.content || '';
            
            // Use the browser's Web Speech API directly
            const utterance = new SpeechSynthesisUtterance(text);
            
            // Get voice settings from UI
            const voiceElement = document.getElementById('webspeech-voice');
            if (voiceElement && voiceElement.value) {
              // Find the matching voice object
              const selectedVoice = window.speechSynthesis.getVoices().find(v => 
                v.name === voiceElement.value);
              
              if (selectedVoice) {
                utterance.voice = selectedVoice;
              }
            }
            
            // Get speed setting
            const speedElement = document.getElementById('tts-speed');
            if (speedElement && speedElement.value) {
              utterance.rate = parseFloat(speedElement.value) || 1.0;
            }
            
            // Speak the text
            window.speechSynthesis.speak(utterance);
          } catch (e) {
            console.error("Error using Web Speech API:", e);
            setAlert("Web Speech API error: " + e.message, "warning");
          }
        } else {
          console.error("Web Speech API not available");
          const notAvailableText = typeof webUIi18n !== 'undefined' ? 
            webUIi18n.t('ui.messages.webSpeechNotAvailable') : 'Web Speech API not available in this browser';
          setAlert(notAvailableText, "warning");
        }
        break;
      }
        
      case "audio": {
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleAudioMessage === 'function') {
          // Custom audio processor for the extracted handler
          const processAudio = (audioData) => {
            // Ensure MediaSource is initialized if not already
            if (!mediaSource && 'MediaSource' in window && !window.basicAudioMode) {
              
              initializeMediaSourceForAudio();
            }
            
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
            } else if (window.basicAudioMode) {
              // Basic mode for iOS and other devices without MediaSource support
              playAudioDirectly(audioData);
            } else {
              // Regular MediaSource approach for other browsers
              audioDataQueue.push(audioData);
              processAudioDataQueue();
              
              // Make sure audio is playing with error handling
              if (audio) {
                const playPromise = audio.play();
                if (playPromise !== undefined) {
                  playPromise.catch(err => {
                    // Debug log removed
                    if (err.name === 'NotAllowedError') {
                      const clickAudioText = getTranslation('ui.messages.clickToEnableAudioSimple', 'Click to enable audio');
            setAlert(`<i class="fas fa-volume-up"></i> ${clickAudioText}`, 'info');
                    }
                  });
                }
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
            if (data.content) {
              // Handle error that might be an object
              if (typeof data.content === 'object' && (data.content.error || data.content.type === 'error')) {
                console.error("API error:", data.content.error || data.content.message || data.content);
                // Convert to error message format that handleErrorMessage expects
                data.type = 'error';
                data.content = data.content.message || data.content.error || JSON.stringify(data.content);
                handleErrorMessage(data);
                break;
              }
              // Handle error in string format
              else if (typeof data.content === 'string' && data.content.includes('error')) {
                try {
                  const errorData = JSON.parse(data.content);
                  if (errorData.error || errorData.type === 'error') {
                    console.error("API error:", errorData.error || errorData.message);
                    // Convert to standard error format
                    data.type = 'error';
                    data.content = errorData.message || errorData.error || JSON.stringify(errorData);
                    handleErrorMessage(data);
                    break;
                  }
                } catch (e) {
                  // If not valid JSON, continue with regular processing
                }
              }
            }

            // Check if this is PCM audio from Gemini
            const provider = $("#tts-provider").val();
            const isPCMFromGemini = (provider === "gemini-flash" || provider === "gemini-pro") && data.mime_type && data.mime_type.includes("audio/L16");
            
            if (isPCMFromGemini) {
              // Handle PCM audio from Gemini
              const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));
              
              // Extract PCM parameters from MIME type (e.g., "audio/L16;codec=pcm;rate=24000")
              const mimeMatch = data.mime_type.match(/rate=(\d+)/);
              const sampleRate = mimeMatch ? parseInt(mimeMatch[1]) : 24000;
              
              // Convert PCM to playable audio using Web Audio API
              playPCMAudio(audioData, sampleRate);
              break;
            }
            
            const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));
            
            // Device/browser specific audio processing
            if (window.firefoxAudioMode) {
              // Firefox special case
              if (!window.firefoxAudioQueue) {
                window.firefoxAudioQueue = [];
              }
              // Limit Firefox queue size as well
              if (window.firefoxAudioQueue.length >= MAX_AUDIO_QUEUE_SIZE) {
                window.firefoxAudioQueue = window.firefoxAudioQueue.slice(Math.floor(MAX_AUDIO_QUEUE_SIZE / 2));
              }
              window.firefoxAudioQueue.push(audioData);
              processAudioDataQueue();
            } else if (window.basicAudioMode) {
              // iOS and other devices without MediaSource support
              playAudioDirectly(audioData);
            } else {
              // Standard MediaSource approach for modern browsers
              audioDataQueue.push(audioData);
              processAudioDataQueue();
              
              // Make sure audio is playing with error handling
              if (audio) {
                const playPromise = audio.play();
                if (playPromise !== undefined) {
                  playPromise.catch(err => {
                    // Debug log removed
                    if (err.name === 'NotAllowedError') {
                      const clickAudioText = getTranslation('ui.messages.clickToEnableAudioSimple', 'Click to enable audio');
            setAlert(`<i class="fas fa-volume-up"></i> ${clickAudioText}`, 'info');
                    }
                  });
                }
              }
            }
            
          } catch (e) {
            console.error("Error processing audio data:", e);
          }
        }
        break;
      }

      case "tts_progress": {
        // Update the TTS progress in the spinner
        const progress = data.progress || 0;
        const segmentIndex = data.segment_index || 0;
        const totalSegments = data.total_segments || 1;
        
        // Update spinner text to show progress
        $("#monadic-spinner")
          .find("span")
          .html(`<i class="fas fa-headphones fa-pulse"></i> Processing audio (${segmentIndex + 1}/${totalSegments})`);
        
        break;
      }
      
      case "tts_complete": {
        // TTS processing is complete, hide the spinner
        $("#monadic-spinner").hide();
        
        // Reset spinner to default state for other operations
        $("#monadic-spinner")
          .find("span i")
          .removeClass("fa-headphones")
          .addClass("fa-comment");
        $("#monadic-spinner")
          .find("span")
          .html('<i class="fas fa-comment fa-pulse"></i> Starting');
        
        break;
      }
      
      case "tts_stopped": {
        // TTS was stopped, reset the UI state
        $("#monadic-spinner").hide();
        
        // Reset response state
        responseStarted = false;
        
        // Set alert to ready state
        const readyToStartText = typeof webUIi18n !== 'undefined' ? 
          webUIi18n.t('ui.messages.readyToStart') : 'Ready to start';
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyToStartText}`, "success");
        
        break;
      }
      
      case "pong": {
        break;
      }
      
      case "language_updated": {
        // Show notification about language change
        const languageName = data.language_name || data.language;
        const languageChangedText = typeof webUIi18n !== 'undefined' ? 
          webUIi18n.t('ui.messages.languageChanged') : 'Language changed to';
        setAlert(`<i class='fa-solid fa-globe'></i> ${languageChangedText} ${languageName}`, "success");
        
        // Update the selector if needed (in case it was changed server-side)
        if (data.language && $("#conversation-language").val() !== data.language) {
          $("#conversation-language").val(data.language);
        }
        
        // Update RTL/LTR for message areas based on text direction
        if (data.text_direction) {
          if (data.text_direction === "rtl") {
            $("body").addClass("rtl-messages");
            console.log("RTL messages enabled for:", data.language);
          } else {
            $("body").removeClass("rtl-messages");
            console.log("LTR messages enabled for:", data.language);
          }
        }
        break;
      }

      case "processing_status": {
        // Show processing status as alert, not in connection-status
        setAlert(`<i class='fas fa-hourglass-half'></i> ${data.content}`, "info");
        
        // Ensure spinner remains visible
        if (!$("#monadic-spinner").is(":visible")) {
          $("#monadic-spinner").show();
        }
        
        // Also show as system message
        const $systemDiv = $('<div class="system-info-message"><i class="fas fa-hourglass-half"></i> </div>');
        // Handle case where content might be an object
        const contentText = typeof data.content === 'object' ? JSON.stringify(data.content) : data.content;
        $systemDiv.append($('<span>').text(contentText));
        
        const systemElement = createCard("system", 
          "<span class='text-success'><i class='fas fa-database'></i></span> <span class='fw-bold fs-6 text-success'>System</span>", 
          $systemDiv[0].outerHTML, 
          "en", 
          null, 
          true, 
          []
        );
        $("#discourse").append(systemElement);
        
        // Auto-scroll if enabled
        if (autoScroll) {
          const chatBottom = document.getElementById('chat-bottom');
          if (!isElementInViewport(chatBottom)) {
            chatBottom.scrollIntoView(false);
          }
        }
        break;
      }

      case "system_info": {
        // Display system information in the conversation
        // Use jQuery's text() method to properly escape the content
        const $systemDiv = $('<div class="system-info-message"><i class="fas fa-info-circle"></i> </div>');
        // Handle case where content might be an object
        const contentText = typeof data.content === 'object' ? JSON.stringify(data.content) : data.content;
        $systemDiv.append($('<span>').text(contentText));
        
        const systemElement = createCard("system", 
          "<span class='text-success'><i class='fas fa-database'></i></span> <span class='fw-bold fs-6 text-success'>System</span>", 
          $systemDiv[0].outerHTML, 
          "en", 
          null, 
          true, 
          []
        );
        $("#discourse").append(systemElement);
        
        // Auto-scroll if enabled
        if (autoScroll) {
          const chatBottom = document.getElementById('chat-bottom');
          if (!isElementInViewport(chatBottom)) {
            chatBottom.scrollIntoView(false);
          }
        }
        break;
      }

      case "error": {
        // Clear any pending spinner check interval on error
        if (window.spinnerCheckInterval) {
          clearInterval(window.spinnerCheckInterval);
          window.spinnerCheckInterval = null;
        }
        
        // Reset streaming flags
        streamingResponse = false;
        if (window.UIState) {
          window.UIState.set('streamingResponse', false);
          window.UIState.set('isStreaming', false);
        }
        responseStarted = false;
        callingFunction = false;
        
        // Re-enable toggle menu
        $("#toggle-menu").removeClass("streaming-active").css("cursor", "");
        
        // Check if content is a translation key or an object with key and details
        let errorContent = data.content;
        
        // Handle various error message formats
        if (typeof errorContent === 'object' && errorContent.key) {
          // Handle structured error with key and details
          if (errorContent.key === 'ai_user_error') {
            errorContent = `${getTranslation('ui.messages.aiUserError', 'AI User error')}: ${errorContent.details}`;
          }
        } else if (typeof errorContent === 'string') {
          // Map translation keys to translated messages
          const errorTranslations = {
            'ai_user_requires_conversation': 'ui.messages.aiUserRequiresConversation',
            'message_not_found_for_editing': 'ui.messages.messageNotFoundForEditing',
            'voice_input_empty': 'ui.messages.voiceInputEmpty',
            'text_input_empty': 'ui.messages.textInputEmpty',
            'invalid_message_format': 'ui.messages.invalidMessageFormat',
            'api_stopped_safety': 'ui.messages.apiStoppedSafety',
            'something_went_wrong': 'ui.messages.somethingWentWrong',
            'error_processing_sample': 'ui.messages.errorProcessingSample',
            'content_not_found': 'ui.messages.contentNotFound',
            'empty_response': 'ui.messages.emptyResponse'
          };
          
          if (errorTranslations[errorContent]) {
            // Get the English fallback from the key
            const fallbacks = {
              'ai_user_requires_conversation': 'AI User requires an existing conversation. Please start a conversation first.',
              'message_not_found_for_editing': 'Message not found for editing',
              'voice_input_empty': 'Voice input is empty',
              'text_input_empty': 'The text input is empty',
              'invalid_message_format': 'Invalid message format received',
              'api_stopped_safety': 'The API stopped responding because of safety reasons',
              'something_went_wrong': 'Something went wrong',
              'error_processing_sample': 'Error processing sample message',
              'content_not_found': 'Content not found in response',
              'empty_response': 'Empty response from API'
            };
            errorContent = getTranslation(errorTranslations[errorContent], fallbacks[errorContent] || errorContent);
          }
        }
        
        // Check if error during AI User generation (message starts with AI User error)
        const isAIUserError = errorContent && errorContent.toString().includes(getTranslation('ui.messages.aiUserError', 'AI User error'));
        
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleErrorMessage === 'function') {
          // Pass the translated content to the handler
          const translatedData = { ...data, content: errorContent };
          handled = wsHandlers.handleErrorMessage(translatedData);
        } else {
          // Fallback to inline handling
          $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import, #ai_user").prop("disabled", false);
          $("#message").show();
          $("#message").prop("disabled", false);
          $("#monadic-spinner").hide();
          setAlert(errorContent, 'error');
          handled = true;
        }
        
        // Additional UI operations specific to our application context
        if (handled) {
          $("#select-role").prop("disabled", false);
          $("#status-message").html(getTranslation('ui.messages.inputMessage', 'Input a message.'));
          
          // Reset UI panels and indicators
          $("#temp-card").hide();
          $("#indicator").hide();
          $("#user-panel").show();
          document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
  
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
          streamingResponse = false;
          if (window.UIState) {
            window.UIState.set('streamingResponse', false);
            window.UIState.set('isStreaming', false);
          }
          
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
          const readyMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.ready') : 'Ready';
          setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyMsg}`, "success");
          
          // Enable OpenAI TTS options when token is verified
          $("#openai-tts-4o").prop("disabled", false);
          $("#openai-tts").prop("disabled", false);
          $("#openai-tts-hd").prop("disabled", false);
          
          // Set OpenAI TTS as default when it becomes available
          // (unless user has already selected another provider)
          const currentProvider = $("#tts-provider").val();
          if (currentProvider === "webspeech") {
            $("#tts-provider").val("openai-tts-4o").trigger("change");
          }
          $("#start").prop("disabled", false);
          $("#send, #clear, #voice, #tts-provider, #elevenlabs-tts-voice, #tts-voice, #conversation-language, #ai-user-initial-prompt-toggle, #ai-user-toggle, #check-auto-speech, #check-easy-submit").prop("disabled", false);
          // TTS speed is already enabled by default and should remain enabled
          
          // Update the available AI User providers when token is verified
          // Check if the function exists before calling it
          if (typeof window.updateAvailableProviders === 'function') {
            window.updateAvailableProviders();
          } else {
            
          }
        }

        break;
      }

      case "open_ai_api_error": {
        verified = "partial";

        $("#start").prop("disabled", false);
        $("#send, #clear").prop("disabled", false);

        $("#api-token").val("");
        
        // Disable OpenAI TTS options when API connection fails
        $("#openai-tts-4o").prop("disabled", true);
        $("#openai-tts").prop("disabled", true);
        $("#openai-tts-hd").prop("disabled", true);

        const cannotConnectText = getTranslation('ui.messages.cannotConnectToAPI', 'Cannot connect to OpenAI API');
        setAlert(`<i class='fa-solid fa-bolt'></i> ${cannotConnectText}`, "warning");
        break;
      }
      case "token_not_verified": {

        verified = "partial";

        $("#start").prop("disabled", false);
        $("#send, #clear").prop("disabled", false);

        $("#api-token").val("");
        
        // Disable OpenAI TTS options when token is not verified
        $("#openai-tts-4o").prop("disabled", true);
        $("#openai-tts").prop("disabled", true);
        $("#openai-tts-hd").prop("disabled", true);

        const tokenNotSetText = getTranslation('ui.messages.validTokenNotSet', 'Valid OpenAI token not set');
        setAlert(`<i class='fa-solid fa-bolt'></i> ${tokenNotSetText}`, "warning");
        break;
      }
      case "apps": {
        console.log("=== APPS MESSAGE RECEIVED ===");
        console.log("Apps message count:", ++window.appsMessageCount || (window.appsMessageCount = 1));
        console.log("Current pendingParameters:", window.pendingParameters);
        console.log("Current #apps value:", $("#apps").val());
        console.log("isUpdate check: apps has", Object.keys(apps).length, "keys");
        window.logTL('apps_received', {
          count: window.appsMessageCount,
          hasAppsKeys: Object.keys(apps).length,
          currentSelect: $("#apps").val()
        });
        
        let version_string = data["version"]
        data["docker"] ? version_string += " (Docker)" : version_string += " (Local)"
        $("#monadic-version-number").html(version_string);
        
        // Check if this is an update to existing apps (e.g., from language change)
        const isUpdate = Object.keys(apps).length > 0;
        
        if (isUpdate) {
          // Update existing apps data with new content (for language updates or reset)
          for (const [key, value] of Object.entries(data["content"])) {
            apps[key] = value;  // Update or add the app data
          }
          
          // Update the currently displayed app description if needed
          const currentApp = $("#apps").val();
          if (currentApp && apps[currentApp]) {
            $("#base-app-desc").html(apps[currentApp]["description"]);
            
            // If this is after a reset, re-initialize the app
            // Check if parameters message hasn't been received yet
            if (!data["from_parameters"]) {
              // Re-initialize the current app with proceedWithAppChange
              setTimeout(function() {
                if (typeof window.proceedWithAppChange === 'function') {
                  window.proceedWithAppChange(currentApp);
                }
              }, 100);
            }
          }
        } else {
          // Persist full app data to the global map so downstream code can read system_prompt, etc.
          try {
            for (const [key, value] of Object.entries(data["content"])) {
              apps[key] = value;
            }
            window.logTL && window.logTL('apps_cached_to_global', { keys: Object.keys(apps).length });
          } catch (_) {}

          // Prepare arrays for app classification
          let regularApps = [];
          let specialApps = {};

          // Classify apps into regular and special groups
          for (const [key, value] of Object.entries(data["content"])) {
            const group = value["group"];
            
            // Check if app belongs to OpenAI group (regular apps)
            if (group && group.trim().toLowerCase() === "openai") {
              regularApps.push([key, value]);
            } else if (group && group.trim() !== "") {
              // Other groups go to special apps
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
          // Always show OpenAI apps, regardless of verification status
          
          // Check if all OpenAI apps are disabled
          const allOpenAIAppsDisabled = regularApps.every(([key, value]) => value.disabled === "true");
          
          // Add OpenAI separator to standard select
          $("#apps").append('<option disabled>──OpenAI──</option>');
          // Add OpenAI separator to custom dropdown with conditional styling
          const openAIGroupClass = allOpenAIAppsDisabled ? ' all-disabled' : '';
          const openAIGroupTitle = allOpenAIAppsDisabled ? ' title="API key required for this provider"' : '';
          $("#custom-apps-dropdown").append(`<div class="custom-dropdown-group${openAIGroupClass}" data-group="OpenAI"${openAIGroupTitle}>
            <span>──OpenAI──${allOpenAIAppsDisabled ? '<span class="api-key-required">(API key required)</span>' : ''}</span>
            <span class="group-toggle-icon"><i class="fas fa-chevron-down"></i></span>
          </div>`);
          // Create a container for the OpenAI apps
          $("#custom-apps-dropdown").append(`<div class="group-container" id="group-OpenAI"></div>`);
          
          for (const [key, value] of regularApps) {
            apps[key] = value;
            // Use display_name if available, otherwise fall back to app_name
            const displayText = value["display_name"] || value["app_name"];
            const appIcon = value["icon"] || "";
            const isDisabled = value.disabled === "true";
            
            // Add option to standard select
            if (isDisabled) {
                $("#apps").append(`<option value="${key}" disabled>${displayText}</option>`);
              } else {
                $("#apps").append(`<option value="${key}">${displayText}</option>`);
              }
              
              // Add the same option to custom dropdown with icon
              const disabledClass = isDisabled ? ' disabled' : '';
              const disabledTitle = isDisabled ? ' title="API key required"' : '';
              const $option = $(`<div class="custom-dropdown-option${disabledClass}" data-value="${key}"${disabledTitle}>
                <span style="margin-right: 8px;">${appIcon}</span>
                <span>${displayText}</span></div>`);
              $("#group-OpenAI").append($option);
            }

          // sort specialApps by group name in the order:
          // "Anthropic", "xAI", "Google", "Cohere", "Mistral", "Perplexity", "DeepSeek", "Ollama", "Extra"
          // and set it to the specialApps object
          specialApps = Object.fromEntries(Object.entries(specialApps).sort((a, b) => {
            const order = ["Anthropic", "xAI", "Google", "Cohere", "Mistral", "Perplexity", "DeepSeek", "Ollama", "Extra"];
            return order.indexOf(a[0]) - order.indexOf(b[0]);
          }));
          
          // Normalize group names to be HTML-id friendly
          const normalizeGroupId = (name) => name.replace(/\s+/g, '-');

          // Add special groups with their labels
          for (const group of Object.keys(specialApps)) {
            if (specialApps[group].length > 0) {
              // Check if all apps in this group are disabled
              const allAppsDisabled = specialApps[group].every(([key, value]) => value.disabled === "true");
              
              // Always show groups even if all apps are disabled
              // This allows users to see what apps exist but are unavailable
              if (true) {
                // Add group header to standard select
                $("#apps").append(`<option disabled>──${group}──</option>`);
                
                // Add group header to custom dropdown with conditional styling
                const groupClass = allAppsDisabled ? ' all-disabled' : '';
                // Special handling for Ollama - it doesn't require an API key
                const disabledMessage = group === "Ollama" ? "(Ollama container not available)" : "(API key required)";
                const groupTitle = allAppsDisabled ? 
                  (group === "Ollama" ? ' title="Ollama container not available"' : ' title="API key required for this provider"') : '';
                $("#custom-apps-dropdown").append(`<div class="custom-dropdown-group${groupClass}" data-group="${group}"${groupTitle}>
                  <span>──${group}──${allAppsDisabled ? `<span class="api-key-required">${disabledMessage}</span>` : ''}</span>
                  <span class="group-toggle-icon"><i class="fas fa-chevron-down"></i></span>
                </div>`);
                
                // Create container for this group's apps
                const normalizedGroupId = normalizeGroupId(group);
                $("#custom-apps-dropdown").append(`<div class="group-container" id="group-${normalizedGroupId}"></div>`);
                
                for (const [key, value] of specialApps[group]) {
                  apps[key] = value;
                  // Use display_name if available, otherwise fall back to app_name
                  const displayText = value["display_name"] || value["app_name"];
                  const appIcon = value["icon"] || "";
                  const isDisabled = value.disabled === "true";
                  
                  // Add option to standard select
                  if (isDisabled) {
                    $("#apps").append(`<option value="${key}" disabled>${displayText}</option>`);
                  } else {
                    $("#apps").append(`<option value="${key}">${displayText}</option>`);
                  }
                  
                  // Add the same option to custom dropdown with icon
                  const disabledClass = isDisabled ? ' disabled' : '';
                  // Special handling for Ollama apps
                  const disabledTitle = isDisabled ? 
                    (group === "Ollama" ? ' title="Ollama container not available"' : ' title="API key required"') : '';
                  const $option = $(`<div class="custom-dropdown-option${disabledClass}" data-value="${key}"${disabledTitle}>
                    <span style="margin-right: 8px;">${appIcon}</span>
                    <span>${displayText}</span></div>`);
                  const normalizedGroupId = normalizeGroupId(group);
                  $(`#group-${normalizedGroupId}`).append($option);
                }
              }
            }
          }

          // Set up group toggle functionality
          $(".custom-dropdown-group").on("click", function() {
            const group = $(this).data("group");
            const normalizedGroupId = normalizeGroupId(group);
            const container = $(`#group-${normalizedGroupId}`);
            const icon = $(this).find(".group-toggle-icon i");
            
            container.toggleClass("collapsed");
            
            if (container.hasClass("collapsed")) {
              icon.removeClass("fa-chevron-down").addClass("fa-chevron-right");
            } else {
              icon.removeClass("fa-chevron-right").addClass("fa-chevron-down");
            }
          });
          
          // Find the currently selected app's group and ensure it's expanded
          const currentApp = $("#apps").val();
          if (currentApp) {
            setTimeout(() => {
              const currentAppOption = $(`.custom-dropdown-option[data-value="${currentApp}"]`);
              if (currentAppOption.length > 0) {
                const parentGroup = currentAppOption.parent(".group-container");
                if (parentGroup.length > 0) {
                  // Ensure this group is expanded
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
            }, 100);
          }
          
          // If import payload specifies an app_name, or there is already a valid selection in #apps,
          // skip auto-selection to avoid overriding an existing choice (import or user selection).
          const importRequestedApp = data && data["content"] && data["content"]["app_name"];
          const currentSelectVal = $("#apps").val();
          const hasCurrentValidSelection = !!(currentSelectVal && $("#apps option[value='" + currentSelectVal + "']").length);
          // Select the default app only when not importing and no valid selection exists
          let firstValidApp;
          
          // First, try to find a Chat app from OpenAI (if API key is available)
          const openAIChatOption = $("#apps option").filter(function() {
            return $(this).val() === 'ChatOpenAI' && !$(this).prop('disabled');
          }).first();
          
          if (!importRequestedApp && !hasCurrentValidSelection && openAIChatOption.length > 0) {
            firstValidApp = openAIChatOption.val();
          } else {
            // Look for any Chat app from other providers
            const anyChatOption = $("#apps option").filter(function() {
              const val = $(this).val();
              return val && val.includes('Chat') && !$(this).prop('disabled') && !$(this).text().includes('──');
            }).first();
            
            if (!importRequestedApp && !hasCurrentValidSelection && anyChatOption.length > 0) {
              firstValidApp = anyChatOption.val();
            } else {
              // Fallback: select the first available non-disabled app
              if (!importRequestedApp && !hasCurrentValidSelection) {
                firstValidApp = $("#apps option").filter(function() {
                  return !$(this).prop('disabled') && !$(this).text().includes('──');
                }).first().val();
              }
            }
          }
          
          if (!importRequestedApp && !hasCurrentValidSelection && firstValidApp) {
            $("#apps").val(firstValidApp);
            
            // Set lastApp to prevent confirmation dialog on initial load
            lastApp = firstValidApp;
            
            // Ensure stop_apps_trigger is false so change event will be processed
            stop_apps_trigger = false;
            
            // Use display_name if available, otherwise fall back to app_name
            const selectedApp = apps[firstValidApp];
            if (selectedApp) {
              const displayText = selectedApp["display_name"] || selectedApp["app_name"];
              $("#base-app-title").text(displayText);
              
              // Update badges immediately
              if (selectedApp["monadic"]) {
                $("#monadic-badge").show();
              } else {
                $("#monadic-badge").hide();
              }

              if (selectedApp["websearch"]) {
                $("#websearch-badge").show();
              } else {
                $("#websearch-badge").hide();
              }

              if (selectedApp["tools"]) {
                $("#tools-badge").show();
              } else {
                $("#tools-badge").hide();
              }

              if (selectedApp["mathjax"]) {
                $("#math-badge").show();
              } else {
                $("#math-badge").hide();
              }

              $("#base-app-icon").html(selectedApp["icon"]);
              $("#base-app-desc").html(selectedApp["description"]);

              if (firstValidApp === "PDF") {
                ws.send(JSON.stringify({ message: "PDF_TITLES" }));
              }
              
              // Call proceedWithAppChange directly to ensure proper initialization
              // Use setTimeout to ensure DOM and all dependencies are ready
              setTimeout(function() {
                const recentlyImported = (typeof window !== 'undefined' && window.lastImportTime) ? (Date.now() - window.lastImportTime < 1000) : false;
                if (typeof window !== 'undefined' && (window.isImporting || recentlyImported || hasCurrentValidSelection)) {
                  // Skip auto-selection during or right after import
                  return;
                }
                window.logTL('auto_select_app', { firstValidApp });
                if (typeof window.proceedWithAppChange === 'function') {
                  // Call proceedWithAppChange directly for reliable initialization
                  window.proceedWithAppChange(firstValidApp);
                  window.logTL('proceedWithAppChange_called_from_apps', { app: firstValidApp });
                  
                } else {
                  // Fallback to triggering change event if function not available
                  $("#apps").trigger('change');
                  window.logTL('apps_change_triggered');
                }
              }, 100);
            }
          }

          // One-time initialization: if first APPS build resulted in a selected value but we didn't auto-select above
          // (e.g., because hasCurrentValidSelection was true due to default selection), explicitly initialize.
          setTimeout(function() {
            try {
              if (window.appsMessageCount === 1 && !importRequestedApp && !window.initialAppLoaded) {
                const sel = $("#apps").val();
                if (sel) {
                  window.initialAppLoaded = true;
                  window.logTL && window.logTL('proceedWithAppChange_on_first_selected', { app: sel });
                  if (typeof window.proceedWithAppChange === 'function') {
                    window.proceedWithAppChange(sel);
                  } else {
                    $("#apps").trigger('change');
                  }
                }
              }
            } catch (_) {}
          }, 150);
          
          // Update the AI User provider dropdown if the function is available
          if (typeof window.updateAvailableProviders === 'function') {
            window.updateAvailableProviders();
          } else {
            
          }
        }
        // Set originalParams to the first valid app or Chat if available
        originalParams = apps["Chat"] || apps[$("#apps").val()] || {};
        
        // Process pending parameters if any
        if (window.pendingParameters) {
          const params = window.pendingParameters;
          window.pendingParameters = null;
          
          // Process the stored parameters after a delay to ensure DOM is ready
          if (params.app_name) {
            loadedApp = params.app_name;
            console.log("Processing pending parameters for app:", params.app_name);
            // Add delay to ensure dropdown is fully populated
            setTimeout(() => {
              console.log("Calling loadParams with pending parameters");
              // Call loadParams which will handle the app and model selection
              loadParams(params, "loadParams");
            }, 100);
          }
        } else {
          // Only reset params if we don't have pending parameters to load
          // AND if we're not in a loaded session (after import)
          // AND if this is truly the first APPS message
          const currentApp = $("#apps").val();
          const isFirstAppsMessage = window.appsMessageCount === 1;
          
          console.log("Deciding whether to call resetParams:");
          console.log("  - currentApp:", currentApp);
          console.log("  - isFirstAppsMessage:", isFirstAppsMessage);
          console.log("  - loadedApp:", loadedApp);
          window.logTL('post_apps_maybe_reset', { currentApp, isFirstAppsMessage, loadedApp });
          
          // Only reset if this is the first apps message and no app is selected
          // OR if there's no loaded app from import
          if (isFirstAppsMessage && (!currentApp || currentApp === "") && !loadedApp) {
            console.log("Conditions met, calling resetParams");
            resetParams();
            window.logTL('resetParams_called_after_apps');
          } else {
            console.log("Skipping resetParams - app already configured");
          }
        }
        break;
      }
      case "parameters": {
        // Check if we have valid content
        if (!data["content"] || Object.keys(data["content"]).length === 0) {
          // Empty parameters, this is normal for initial load
          break;
        }
        
        // Store parameters for later processing if apps not loaded yet
        if (!apps || Object.keys(apps).length === 0) {
          window.pendingParameters = data["content"];
          break;
        }
        
        // Only process if we have an app_name
        if (data["content"]["app_name"]) {
          console.log("=== WEBSOCKET PARAMETERS MESSAGE ===");
          console.log("app_name from server:", data["content"]["app_name"]);
          console.log("model from server:", data["content"]["model"]);
          console.log("group from server:", data["content"]["group"]);
          console.log("Full content:", data["content"]);
          
          loadedApp = data["content"]["app_name"];
          const pleaseWaitText = getTranslation('ui.messages.pleaseWait', 'Please wait');
          setAlert(`<i class='fa-solid fa-hourglass-half'></i> ${pleaseWaitText}`, "warning");
          
          // Call loadParams which will handle everything including model selection
          console.log("About to call loadParams...");
          window.logTL('parameters_received', {
            app_name: data["content"]["app_name"],
            has_initial_prompt: !!data["content"]["initial_prompt"],
            model: data["content"]["model"],
            group: data["content"]["group"]
          });
          
          // Check if loadParams is defined
          if (typeof loadParams === 'function') {
            loadParams(data["content"], "loadParams");
            window.logTL('loadParams_called_from_parameters', { calledFor: 'loadParams' });
          } else if (typeof window.loadParams === 'function') {
            window.loadParams(data["content"], "loadParams");
          } else {
            console.error("loadParams function not found! Attempting direct app/model setting...");
            
            // Direct fallback approach
            const appName = data["content"]["app_name"];
            const model = data["content"]["model"];
            
            console.log("Direct setting app:", appName, "model:", model);
            
            // Set the app directly
            if (appName) {
              $("#apps").val(appName);
              // Trigger change to update model list
              $("#apps").trigger('change');
              
              // Set model after a delay
              setTimeout(() => {
                if (model) {
                  $("#model").val(model);
                  if ($("#model").val() !== model) {
                    console.error("Failed to set model:", model);
                    // Try again with a longer delay
                    setTimeout(() => {
                      $("#model").val(model);
                      $("#model").trigger('change');
                    }, 500);
                  } else {
                    $("#model").trigger('change');
                  }
                }
              }, 300);
            }
          }
          
          console.log("loadParams handling complete, breaking...");
          
          // Don't rebuild the model list here - loadParams already handles it
          // The code below was causing the model selector to be reset
          break;
        }
        
        // This code should only run if there's no app_name in parameters
        // (which means it's not a loaded session)
        
        // All providers now support AI User functionality
        
        const currentApp = apps[$("#apps").val()] || apps[window.defaultApp];

        // Use shared utility function to get models for the app
        let models = currentApp ? getModelsForApp(currentApp) : [];

        if (currentApp) {
          let openai = currentApp["group"] && currentApp["group"].toLowerCase() === "openai";
          let modelList = listModels(models, openai);
          $("#model").html(modelList);
        }
        
        // Select the appropriate model using shared utility function
        let model;
        if (currentApp) {
          // Use the model from parameters if available, otherwise use default
          if (data["content"]["model"] && models.includes(data["content"]["model"])) {
            model = data["content"]["model"];
          } else {
            model = getDefaultModelForApp(currentApp, models);
          }
        }
          
          // Extract provider name from current app group using shared function if available
          let provider;
          if (typeof getProviderFromGroup === 'function' && currentApp && currentApp["group"]) {
            provider = getProviderFromGroup(currentApp["group"]);
          } else {
            // Fallback implementation if the function is not available
            provider = "OpenAI";
            if (currentApp && currentApp["group"]) {
              const group = currentApp["group"].toLowerCase();
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
            } else if (group.includes("ollama")) {
              provider = "Ollama";
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
          if (currentApp) {
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
          }
        }
        
        $("#start").focus();

        updateAppAndModelSelection(data["content"]);
        break;
      case "elevenlabs_voices": {
        const cookieValue = getCookie("elevenlabs-tts-voice");
        let voices = data["content"];
        if (voices.length > 0) {
          // set ElevenLabs provider options enabled
          $("#elevenlabs-flash-provider-option").prop("disabled", false);
          $("#elevenlabs-multilingual-provider-option").prop("disabled", false);
          // Do not set ElevenLabs as default - prefer openai-tts-4o
        } else {
          // set ElevenLabs provider options disabled
          $("#elevenlabs-flash-provider-option").prop("disabled", true);
          $("#elevenlabs-multilingual-provider-option").prop("disabled", true);
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
      case "gemini_voices": {
        const cookieValue = getCookie("gemini-tts-voice");
        let voices = data["content"];
        if (voices.length > 0) {
          // set both gemini provider options enabled
          $("#gemini-flash-provider-option").prop("disabled", false);
          $("#gemini-pro-provider-option").prop("disabled", false);
          
          // Populate the gemini voice select element
          $("#gemini-tts-voice").empty();
          voices.forEach((voice) => {
            if (cookieValue === voice.voice_id) {
              $("#gemini-tts-voice").append(`<option value="${voice.voice_id}" selected>${voice.name}</option>`);
            } else {
              $("#gemini-tts-voice").append(`<option value="${voice.voice_id}">${voice.name}</option>`);
            }
          });
          
          // Apply saved cookie value for voice if it exists
          const savedVoice = getCookie("gemini-tts-voice");
          if (savedVoice && $(`#gemini-tts-voice option[value="${savedVoice}"]`).length > 0) {
            $("#gemini-tts-voice").val(savedVoice);
          }
        } else {
          // set both gemini provider options disabled
          $("#gemini-flash-provider-option").prop("disabled", true);
          $("#gemini-pro-provider-option").prop("disabled", true);
        }
        
        // Apply saved cookie value for provider if it was gemini
        const savedProvider = getCookie("tts-provider");
        if (savedProvider === "gemini-flash" || savedProvider === "gemini-pro") {
          $("#tts-provider").val(savedProvider).trigger("change");
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
          
          // Restore original placeholder
          const origPlaceholder = $("#message").data("original-placeholder") || (typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message or click Speech Input button to use voice . . .");
          $("#message").attr("placeholder", origPlaceholder);
          
          // Ensure amplitude chart is hidden after processing
          $("#amplitude").hide();
          
          if ($("#check-easy-submit").is(":checked")) {
            $("#send").click();
          }
          const voiceFinishedText = getTranslation('ui.messages.voiceRecognitionFinished', 'Voice recognition finished');
          setAlert(`<i class='fa-solid fa-circle-check'></i> ${voiceFinishedText}`, "secondary");
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
          const noAppsMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.noAppsAvailable') : 'No apps available - check API keys in settings';
          setAlert(`<i class='fa-solid fa-bolt'></i> ${noAppsMsg}`, "warning");
        } else {
          const readyMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.ready') : 'Ready';
          setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyMsg}`, "success");
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
            // Detect iOS/iPadOS
            const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || 
                         (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
            
            if (isIOS) {
              // Use standard confirm dialog on iOS
              if (confirm("Are you sure you want to delete PDF: " + title + "?")) {
                ws.send(JSON.stringify({ message: "DELETE_PDF", contents: title }));
              }
            } else {
              // Use Bootstrap modal on other platforms
              $("#pdfDeleteConfirmation").modal("show");
              $("#pdfToDelete").text(title);
              $("#pdfDeleteConfirmed").off("click").on("click", function (event) {
                event.preventDefault();
                ws.send(JSON.stringify({ message: "DELETE_PDF", contents: title }));
                $("#pdfDeleteConfirmation").modal("hide");
                $("#pdfToDelete").text("");
              });
            }
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
        // If we just reset, ignore past messages completely
        if (window.SessionState.shouldForceNewSession()) {
          window.SessionState.clearMessages();
          $("#discourse").empty();
          setStats(formatInfo([]), "info");
          // Ensure i18n is ready before updating text
          if (window.i18nReady) {
            window.i18nReady.then(() => {
              const startText = webUIi18n.t('ui.session.startSession');
              $("#start-label").text(startText);
            });
          } else {
            $("#start-label").text('Start Session');
          }
          break;
        }
        
        window.SessionState.clearMessages();
        $("#discourse").empty();

        data["content"].forEach((msg, index) => {
          if (mids.has(msg["mid"])) {
            return;
          }

          window.SessionState.addMessage(msg);

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
                // Use the unified thinking block renderer if available
                if (typeof renderThinkingBlock === 'function') {
                  const thinkingTitle = typeof webUIi18n !== 'undefined' ? 
                    webUIi18n.t('ui.messages.thinkingProcess') : "Thinking Process";
                  html = renderThinkingBlock(msg["thinking"], thinkingTitle) + html;
                } else {
                  // Fallback to old style if function not available
                  html = "<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>" + msg["thinking"] + "</div></div>" + html;
                }
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
          // Ensure i18n is ready before updating text
          if (window.i18nReady) {
            window.i18nReady.then(() => {
              const continueText = webUIi18n.t('ui.session.continueSession');
              $("#start-label").text(continueText);
            });
          } else {
            $("#start-label").text('Continue Session');
          }
        } else {
          // Ensure i18n is ready before updating text
          if (window.i18nReady) {
            window.i18nReady.then(() => {
              const startText = webUIi18n.t('ui.session.startSession');
              $("#start-label").text(startText);
            });
          } else {
            $("#start-label").text('Start Session');
          }
        }
        
        // Update AI User button state
        updateAIUserButtonState(messages);

        // After loading past messages, set initialLoadComplete to true
        initialLoadComplete = true;
        break;
      }
      case "message": {
        if (data["content"] === "DONE") {
          // Check if tool calls are pending
          if (data["finish_reason"] === "tool_calls") {
            // Keep spinner visible for tool calls
            callingFunction = true;
            $("#monadic-spinner").show();
            const processingToolsText = getTranslation('ui.messages.spinnerProcessingTools', 'Processing tools');
            $("#monadic-spinner span").html(`<i class="fas fa-cogs fa-pulse"></i> ${processingToolsText}`);
          } else {
            // No tool calls, ensure callingFunction is false
            callingFunction = false;
          }
          ws.send(JSON.stringify({ "message": "HTML" }));
        } else if (data["content"] === "CLEAR") {
          $("#chat").html("");
          $("#temp-card .status").hide();
          $("#indicator").show();
        }
        break;
      }
      case "ai_user_started": {
        const generatingText = getTranslation('ui.messages.generatingAIUserResponse', 'Generating AI user response...');
        setAlert(`<i class='fas fa-spinner fa-spin'></i> ${generatingText}`, "warning");
        
        // Show the cancel button
        document.getElementById('cancel_query').style.setProperty('display', 'flex', 'important');
        
        // Show spinner and update its message with robot animation
        $("#monadic-spinner").css("display", "block");
        const aiUserText = typeof webUIi18n !== 'undefined' && webUIi18n.initialized ? 
          webUIi18n.t('ui.messages.spinnerGeneratingAIUser') : 'Generating AI user response';
        $("#monadic-spinner span").html(`<i class="fas fa-robot fa-pulse"></i> ${aiUserText}`);
        
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
        
        
        // Trim extra whitespace from the final message
        const trimmedContent = data["content"].trim();
        
        // Set the message content
        $("#message").val(trimmedContent);
        
        // Hide cancel button and spinner
        document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
        $("#monadic-spinner").css("display", "none");

        // Re-enable all input elements individually
        $("#message").prop("disabled", false);
        $("#send").prop("disabled", false);
        $("#clear").prop("disabled", false);
        $("#image-file").prop("disabled", false);
        $("#voice").prop("disabled", false);
        $("#doc").prop("disabled", false);
        $("#url").prop("disabled", false);
        $("#pdf-import").prop("disabled", false);
        $("#ai_user").prop("disabled", false);
        $("#select-role").prop("disabled", false);

        // Update alert message to success state
        const generatedText = getTranslation('ui.messages.aiUserResponseGenerated', 'AI user response generated');
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${generatedText}`, "success");

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
        if (!$card.length) {
          return;
        }
        
        const $cardText = $card.find(".card-text");
        
        // Update the HTML content
        if (data.html) {
          // Update the card with the HTML from server
          $cardText.html(data.html);
          
          // Check if we have preserved images from before editing
          const $preservedImages = $cardText.data('preservedImages');
          
          // Add images if they exist
          if (data.images && Array.isArray(data.images) && data.images.length > 0) {
            // Group mask images with their original images
            const imageMap = new Map();
            const maskImages = [];
            
            // First pass - identify all mask images and base images
            data.images.forEach(image => {
              if (image.is_mask || (image.title && image.title.startsWith("mask__"))) {
                // Store mask images separately with reference to their base image
                maskImages.push(image);
              } else {
                // Store base images in a map with their title as key
                imageMap.set(image.title, image);
              }
            });
            
            // Second pass - create HTML for each base image, with its mask if available
            let image_data = "";
            
            // Process regular images first
            imageMap.forEach((image, title) => {
              // Check if this image has a mask
              const maskImage = maskImages.find(mask => 
                mask.mask_for === title || 
                (mask.title && mask.title.includes(title.replace(/\.[^.]+$/, "")))
              );
              
              if (maskImage) {
                // This image has a mask - render as overlay
                image_data += `
                  <div class="mask-overlay-container mb-3">
                    <img class='base-image' alt='${image.title}' src='${image.data}' />
                    <img class='mask-overlay' alt='${maskImage.title}' src='${maskImage.display_data || maskImage.data}' style="opacity: 0.6;" />
                    <div class="mask-overlay-label">MASK</div>
                  </div>
                `;
              } else if (image.type === 'application/pdf') {
                // PDF file
                image_data += `
                  <div class="pdf-preview mb-3">
                    <i class="fas fa-file-pdf text-danger"></i>
                    <span class="ms-2">${image.title}</span>
                  </div>
                `;
              } else {
                // Regular image without mask
                image_data += `
                  <img class='base64-image mb-3' src='${image.data}' alt='${image.title}' style='max-width: 100%; height: auto;' />
                `;
              }
            });
            
            // Finally, add any mask images that don't have a matching base image
            maskImages.forEach(mask => {
              if (!imageMap.has(mask.mask_for)) {
                image_data += `
                  <img class='base64-image mb-3' src='${mask.display_data || mask.data}' alt='${mask.title}' style='max-width: 100%; height: auto;' />
                `;
              }
            });
            
            $cardText.append(image_data);
          } else if ($preservedImages && $preservedImages.length > 0) {
            // If no images from server but we have preserved images, restore them
            $cardText.append($preservedImages);
          }
          
          // Clean up the preserved images data
          $cardText.removeData('preservedImages');
          
          // Update the messages array with the new images
          const messageIndex = messages.findIndex((m) => m.mid === data.mid);
          if (messageIndex !== -1 && data.images) {
            messages[messageIndex].images = data.images;
          }
          
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
        
        // If we receive an HTML message while callingFunction is true,
        // this is likely the result of a tool call, so reset the flag
        if (callingFunction && data.content && data.content.role === 'assistant') {
          callingFunction = false;
        }
        
        // Hide the temp-card as we're about to show the final HTML
        $("#temp-card").hide();
        
        // Use the handler if available, otherwise use inline code
        let handled = false;
        if (wsHandlers && typeof wsHandlers.handleHtmlMessage === 'function') {
          handled = wsHandlers.handleHtmlMessage(data, messages, appendCard);
          if (handled) {
            document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
          }
        }
        
        // Update AI User button state
        updateAIUserButtonState(messages);
        
        if (!handled) {
          // Fallback to inline handling
          window.SessionState.addMessage(data["content"]);

          let html = data["content"]["html"];

          if (data["content"]["thinking"]) {
            // Use the unified thinking block renderer if available
            if (typeof renderThinkingBlock === 'function') {
              const thinkingTitle = typeof webUIi18n !== 'undefined' ? 
                webUIi18n.t('ui.messages.thinkingProcess') : "Thinking Process";
              html = renderThinkingBlock(data["content"]["thinking"], thinkingTitle) + html;
            } else {
              // Fallback to old style if function not available
              html = "<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>" + data["content"]["thinking"] + "</div></div>" + html;
            }
          } else if(data["content"]["reasoning_content"]) {
            // Use the unified thinking block renderer if available
            if (typeof renderThinkingBlock === 'function') {
              const reasoningTitle = typeof webUIi18n !== 'undefined' ? 
                webUIi18n.t('ui.messages.reasoningProcess') : "Reasoning Process";
              html = renderThinkingBlock(data["content"]["reasoning_content"], reasoningTitle) + html;
            } else {
              // Fallback to old style if function not available
              html = "<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>" + data["content"]["reasoning_content"] + "</div></div>" + html;
            }
          }
          
          if (data["content"]["role"] === "assistant") {
            appendCard("assistant", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>", html, data["content"]["lang"], data["content"]["mid"], true);

            // Show message input and hide spinner
            $("#message").show();
            $("#message").val(""); // Clear the message after successful response
            $("#message").prop("disabled", false);
            // Re-enable all input controls
            $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import").prop("disabled", false);
            $("#select-role").prop("disabled", false);
            
            // Reset streaming flag as response is done
            streamingResponse = false;
            if (window.UIState) {
              window.UIState.set('streamingResponse', false);
              window.UIState.set('isStreaming', false);
            }
            
            // Clear any pending spinner check interval
            if (spinnerCheckInterval) {
              clearInterval(spinnerCheckInterval);
              spinnerCheckInterval = null;
            }
            
            // Only hide spinner if we're not waiting for function calls
            if (!callingFunction) {
              $("#monadic-spinner").hide();
            }
            
            // If this is the first assistant message (from initiate_from_assistant), show user panel
            if (!$("#user-panel").is(":visible") && $("#temp-card").is(":visible")) {
              $("#user-panel").show();
              setInputFocus();
            }
            
            document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
            
            // For assistant messages, don't show "Ready to start" immediately
            // Wait for streaming to complete
            const receivedText = typeof webUIi18n !== 'undefined' ? 
              webUIi18n.t('ui.messages.responseReceived') : 'Response received';
            setAlert(`<i class='fa-solid fa-circle-check'></i> ${receivedText}`, "success");
            
            // Handle auto_speech for TTS auto-playback
            if (window.autoSpeechActive || (params && params["auto_speech"] === "true")) {
              // Use setTimeout to ensure the card is fully rendered before triggering TTS
              setTimeout(() => {
                const lastCard = $("#discourse div.card:last");
                const playButton = lastCard.find(".func-play");
                if (playButton.length > 0) {
                  // Simulate a click on the play button to trigger TTS
                  playButton.click();
                }
                // Reset the auto speech flag
                window.autoSpeechActive = false;
              }, 100);
            }
          } else {
            // For non-assistant messages, show "Ready for input" only if not calling functions
            document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
            if (!callingFunction) {
              const readyText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
              setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
            }
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
          $("#message").prop("disabled", false);
          // Reset streaming flag as response is done
          streamingResponse = false;
          if (window.UIState) {
            window.UIState.set('streamingResponse', false);
            window.UIState.set('isStreaming', false);
          }
          
          // Clear any pending spinner check interval
          if (spinnerCheckInterval) {
            clearInterval(spinnerCheckInterval);
            spinnerCheckInterval = null;
          }
          
          // Only hide spinner if we're not waiting for function calls
          if (!callingFunction) {
            $("#monadic-spinner").hide();
          }
          document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
          // Only show "Ready for input" if we're not waiting for function calls
          if (!callingFunction) {
            const readyText = typeof webUIi18n !== 'undefined' ? 
              webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
            setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
          }
        } else if (data["content"]["role"] === "system") {
          // Use the appendCard helper function
          appendCard("system", "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
          $("#message").show();
          $("#message").prop("disabled", false);
          // Reset streaming flag as response is done
          streamingResponse = false;
          if (window.UIState) {
            window.UIState.set('streamingResponse', false);
            window.UIState.set('isStreaming', false);
          }
          
          // Clear any pending spinner check interval
          if (spinnerCheckInterval) {
            clearInterval(spinnerCheckInterval);
            spinnerCheckInterval = null;
          }
          
          // Only hide spinner if we're not waiting for function calls
          if (!callingFunction) {
            $("#monadic-spinner").hide();
          }
          document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
          // Only show "Ready for input" if we're not waiting for function calls
          if (!callingFunction) {
            const readyText = typeof webUIi18n !== 'undefined' ? 
              webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
            setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
          }
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
          window.SessionState.removeMessage(tempMessageIndex);
        }
        
        // Create the proper message object
        let message_obj = { "role": "user", "text": data["content"]["text"], "html": data["content"]["html"], "mid": data["content"]["mid"] }
        if (data["content"]["images"] !== undefined) {
          message_obj.images = data["content"]["images"];
        }
        window.SessionState.addMessage(message_obj);
        
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
        
        // Show loading indicators and clear any previous card content
        if ($("#temp-card").length) {
          $("#temp-card .card-text").empty(); // Clear any existing content
          $("#temp-card").show();
          window._lastProcessedIndex = -1; // Reset index tracking
        } else {
          // Create a new temp card if it doesn't exist
          const tempCard = $(`
            <div id="temp-card" class="card mt-3 streaming-card"> 
              <div class="card-header p-2 ps-3 d-flex justify-content-between">
                <div class="fs-5 card-title mb-0">
                  <span><i class="fas fa-robot" style="color: #DC4C64;"></i></span> <span class="fw-bold fs-6" style="color: #DC4C64;">Assistant</span>
                </div>
              </div>
              <div class="card-body role-assistant">
                <div class="card-text"></div>
              </div>
            </div>
          `);
          $("#discourse").append(tempCard);
        }
        
        $("#temp-card .status").hide();
        $("#indicator").show();
        // Keep the user panel visible but disable interactive elements
        $("#message").prop("disabled", true);
        $("#send, #clear, #image-file, #voice, #doc, #url").prop("disabled", true);
        $("#select-role").prop("disabled", true);
        document.getElementById('cancel_query').style.setProperty('display', 'flex', 'important');
        
        // Show informative spinner message with brain animation icon
        const processingRequestText = typeof webUIi18n !== 'undefined' ? 
          webUIi18n.t('ui.messages.spinnerProcessingRequest') : 'Processing request';
        $("#monadic-spinner span").html(`<i class="fas fa-brain fa-pulse"></i> ${processingRequestText}...`);
        $("#monadic-spinner").show(); // Ensure spinner is visible
        
        // Mark that we're starting a response process
        streamingResponse = true;
        if (window.UIState) {
          window.UIState.set('streamingResponse', true);
          window.UIState.set('isStreaming', true);
        }
        responseStarted = false; // Will be set to true when streaming starts
        
        // Disable toggle menu during streaming
        $("#toggle-menu").addClass("streaming-active").css("cursor", "not-allowed");
        
        // Clear any existing interval first
        if (window.spinnerCheckInterval) {
          clearInterval(window.spinnerCheckInterval);
          window.spinnerCheckInterval = null;
        }
        
        // Keep spinner visible during the initial gap between processing and receiving
        // Only check for a short period (3 seconds max) to prevent infinite loops
        let checkCount = 0;
        window.spinnerCheckInterval = setInterval(() => {
          checkCount++;
          
          // Stop checking after 3 seconds or if response has started
          if (checkCount > 30 || responseStarted || !streamingResponse) {
            clearInterval(window.spinnerCheckInterval);
            window.spinnerCheckInterval = null;
            return;
          }
          
          // Only re-show spinner if it's hidden and we're still waiting for first fragment
          if (streamingResponse && !responseStarted && !$("#monadic-spinner").is(":visible")) {
            const processingRequestText = typeof webUIi18n !== 'undefined' ? 
              webUIi18n.t('ui.messages.spinnerProcessingRequest') : 'Processing request';
            $("#monadic-spinner span").html(`<i class="fas fa-brain fa-pulse"></i> ${processingRequestText}...`);
            $("#monadic-spinner").show();
          }
        }, 100); // Check every 100ms
        
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
          window.SessionState.addMessage(messageObj);
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
          document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
          
          // Show success alert
          const roleText = data.role === "user" ? "User" : 
                          data.role === "assistant" ? "Assistant" : "System";
          const sampleAddedText = getTranslation('ui.messages.sampleMessageAdded', 'Sample message added');
          setAlert(`<i class='fas fa-check-circle'></i> ${sampleAddedText}`, "success");
        }
        break;
      }
      
      case "streaming_complete": {
        // Handle streaming completion
        streamingResponse = false;
        if (window.UIState) {
          window.UIState.set('streamingResponse', false);
          window.UIState.set('isStreaming', false);
        }
        
        // Re-enable toggle menu
        $("#toggle-menu").removeClass("streaming-active").css("cursor", "");
        
        // Clear any pending spinner check interval
        if (window.spinnerCheckInterval) {
          clearInterval(window.spinnerCheckInterval);
          window.spinnerCheckInterval = null;
        }
        
        // Hide the spinner unless we're still processing function calls
        if (!callingFunction) {
          $("#monadic-spinner").hide();
        }
        
        // Check if there are any pending operations before showing "Ready for input"
        // This includes checking for active spinners or recent DOM updates
        let pendingOperations = false;
        
        // Check if any spinner is still visible (in case of multiple spinners) or if we're calling functions
        if ($(".spinner:visible").length > 0 || $(".fa-spinner:visible").length > 0 || callingFunction) {
          pendingOperations = true;
        }
        
        // Set a proper delay to ensure all DOM updates are complete
        // Increased delay to avoid premature "Ready for input" display
        setTimeout(function() {
          // Re-check for pending operations after delay
          pendingOperations = false;
          if ($(".spinner:visible").length > 0 || $(".fa-spinner:visible").length > 0 || callingFunction) {
            pendingOperations = true;
          }
          
          // Only show "Ready for input" if no pending operations detected
          if (!pendingOperations && !streamingResponse) {
            const readyText = typeof webUIi18n !== 'undefined' ? 
              webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
            setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
          } else {
            // If operations are still pending, wait and check again
            let checkInterval = setInterval(function() {
              if ($(".spinner:visible").length === 0 && $(".fa-spinner:visible").length === 0 && !callingFunction && !streamingResponse) {
                clearInterval(checkInterval);
                const readyText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
                setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
              }
            }, 500); // Check every 500ms
            
            // Safety timeout to prevent infinite checking
            setTimeout(function() {
              clearInterval(checkInterval);
              const readyText = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
              setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyText}`, "success");
            }, 10000); // Maximum wait of 10 seconds
          }
          
          // Always ensure UI elements are enabled
          $("#message").prop("disabled", false);
          $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import").prop("disabled", false);
          $("#select-role").prop("disabled", false);
          
          // Focus on the message input
          setInputFocus();
        }, 250); // Initial 250ms delay
        
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
            window.SessionState.removeMessage(tempMessageIndex);
          }
          
          // Remove any UI cards that may have been created during this initial message
          if (messages.length === 0) {
            $("#discourse").empty();
          }
          
          // Don't clear the message so users can edit and resubmit
          $("#message").attr("placeholder", typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message...");
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
          
          $("#status-message").html(getTranslation('ui.messages.inputMessage', 'Input a message.'));
          document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');
          
          // Hide loading indicators
          $("#temp-card").hide();
          $("#indicator").hide();
          
          // Show message input and hide spinner
          $("#message").show();
          $("#monadic-spinner").css("display", "none");
          
          // Update AI User button state
          updateAIUserButtonState(messages);
          
          // Show canceled message
          const operationCanceledText = getTranslation('ui.messages.operationCanceled', 'Operation canceled');
          setAlert(`<i class='fa-solid fa-ban' style='color: #FF7F07;'></i> ${operationCanceledText}`, "warning");
          
          setInputFocus();
        }
        break;
      }

      case "mcp_status": {
        // Handle MCP server status
        handleMCPStatus(data["content"]);
        break;
      }
      
      default: {
        // Check if this is a fragment message
        if (data.type === "fragment") {
          // Handle fragment messages from all vendors
          if (!responseStarted) {
            const respondingText = typeof webUIi18n !== 'undefined' ? 
              webUIi18n.t('ui.messages.responding') : 'RESPONDING';
            setAlert(`<i class='fas fa-pencil-alt'></i> ${respondingText}`, "warning");
            responseStarted = true;
            streamingResponse = true; // Mark that we're streaming
            if (window.UIState) {
              window.UIState.set('streamingResponse', true);
              window.UIState.set('isStreaming', true);
            }
          }
          
          // Always update spinner for fragments to ensure continuity
          if (streamingResponse) {
            const receivingResponseText = typeof webUIi18n !== 'undefined' ? 
              webUIi18n.t('ui.messages.spinnerReceivingResponse') : 'Receiving response';
            $("#monadic-spinner span").html(`<i class="fa-solid fa-circle-nodes fa-pulse"></i> ${receivingResponseText}`);
            $("#monadic-spinner").show(); // Ensure spinner is visible
          }
          
          // Use the dedicated fragment handler
          window.handleFragmentMessage(data);
          
          $("#indicator").show();
          if (autoScroll && !isElementInViewport(chatBottom)) {
            chatBottom.scrollIntoView(false);
          }
        } else {
          // Handle other default messages (for backward compatibility)
          let content = data["content"];
          if (!responseStarted || callingFunction) {
            const respondingText = typeof webUIi18n !== 'undefined' ? 
              webUIi18n.t('ui.messages.responding') : 'RESPONDING';
            setAlert(`<i class='fas fa-pencil-alt'></i> ${respondingText}`, "warning");
            callingFunction = false;
            responseStarted = true;
            streamingResponse = true; // Mark that we're streaming
            if (window.UIState) {
              window.UIState.set('streamingResponse', true);
              window.UIState.set('isStreaming', true);
            }
            // Show and update spinner message for streaming
            const receivingResponseText = typeof webUIi18n !== 'undefined' ? 
              webUIi18n.t('ui.messages.spinnerReceivingResponse') : 'Receiving response';
            $("#monadic-spinner span").html(`<i class="fa-solid fa-circle-nodes fa-pulse"></i> ${receivingResponseText}`);
            $("#monadic-spinner").show(); // Ensure spinner is visible
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
  }

  ws.onclose = function (_e) {
    initialLoadComplete = false;
    // Update state if available
    if (window.UIState) {
      window.UIState.set('wsConnected', false);
      window.UIState.set('wsReconnecting', true);
    }
    reconnect_websocket(ws);
  }

  ws.onerror = function (err) {
    console.error(`[WebSocket] Socket error for ${wsUrl}:`, err.message || 'Unknown error');
    // Update state if available
    if (window.UIState) {
      window.UIState.set('wsConnected', false);
    }
    
    // Get connection details if not localhost
    if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
      const host = window.location.hostname;
      const port = window.location.port || "4567";
      
      // Show helpful error message
      const connectionFailedText = getTranslation('ui.messages.connectionFailed', 'Connection failed');
      setAlert(`<i class='fa-solid fa-circle-exclamation'></i> ${connectionFailedText} - ${host}:${port}`, "danger");
    } else {
      // Generic error for localhost
      const connectionFailedText = getTranslation('ui.messages.connectionFailed', 'Connection failed');
      setAlert(`<i class='fa-solid fa-circle-exclamation'></i> ${connectionFailedText}`, "danger");
    }
    
    ws.close();
  }
  return ws;
}

// WebSocket connection management
const maxReconnectAttempts = 5; // Maximum number of reconnection attempts
const baseReconnectDelay = 1000; // Base delay in milliseconds
let reconnectionTimer = null; // Store the timer to allow cancellation

// Improved WebSocket reconnection logic with proper cleanup and retry handling
function reconnect_websocket(ws, callback) {
  // Prevent multiple reconnection attempts for the same WebSocket
  if (ws._isReconnecting) {
    console.log("Already attempting to reconnect, skipping duplicate attempt");
    return;
  }
  
  // Store reconnection attempts in the WebSocket object itself
  // This ensures each WebSocket manages its own reconnection state
  if (ws._reconnectAttempts === undefined) {
    ws._reconnectAttempts = 0;
  }
  
  // Limit maximum reconnection attempts
  if (ws._reconnectAttempts >= maxReconnectAttempts) {
    console.error(`Maximum reconnection attempts (${maxReconnectAttempts}) reached.`);
    const connectionFailedRefreshText = getTranslation('ui.messages.connectionFailedRefresh', 'Connection failed - please refresh page');
    setAlert(`<i class='fa-solid fa-server'></i> ${connectionFailedRefreshText}`, "danger");
    
    // Properly clean up any pending timers
    ws._isReconnecting = false;
    if (reconnectionTimer) {
      clearTimeout(reconnectionTimer);
      reconnectionTimer = null;
    }
    return;
  }
  
  // Mark as reconnecting
  ws._isReconnecting = true;

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
        
        // Stop any active ping interval
        stopPing();
        
        // After maximum attempts, just show final error and don't reconnect
        if (ws._reconnectAttempts >= maxReconnectAttempts) {
          const connectionFailedRefreshText = getTranslation('ui.messages.connectionFailedRefresh', 'Connection failed - please refresh page');
    setAlert(`<i class='fa-solid fa-server'></i> ${connectionFailedRefreshText}`, "danger");
          return; // Exit without creating new connection
        }
        
        // Get connection details
        let connectionDetails = "";
        let host = "localhost";
        let port = "4567";
        
        // Get hostname from browser URL if not localhost
        if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
          host = window.location.hostname;
          port = window.location.port || "4567";
          connectionDetails = ` to ${host}:${port}`;
        }
        
        // Show retry message
        const message = `<i class='fa-solid fa-sync fa-spin'></i> Connecting${connectionDetails}...`;
        
        setAlert(message, "warning");
        
        // Create new connection
        ws = connect_websocket(callback);
        window.ws = ws;  // Update global reference
        break;
        
      case WebSocket.CLOSING:
        // Wait for socket to fully close before reconnecting
        console.log(`Socket is closing. Waiting ${delay}ms before reconnection attempt.`);
        reconnectionTimer = setTimeout(() => {
          ws._isReconnecting = false; // Reset flag before next attempt
          reconnect_websocket(ws, callback);
        }, delay);
        break;
        
      case WebSocket.CONNECTING:
        // Socket is still trying to connect, wait a bit before checking again
        console.log(`Socket is connecting. Checking again in ${delay}ms.`);
        reconnectionTimer = setTimeout(() => {
          ws._isReconnecting = false; // Reset flag before next attempt
          reconnect_websocket(ws, callback);
        }, delay);
        break;
        
      case WebSocket.OPEN:
        // Connection is successful, reset counters
        ws._reconnectAttempts = 0;
        ws._isReconnecting = false;
        
        // Start ping to keep connection alive
        startPing();
        
        // Update UI
        const connectedMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.connected') : 'Connected';
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${connectedMsg}`, "info");
        
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
      ws._isReconnecting = false; // Reset flag before next attempt
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
          
          // Get connection details if not using localhost
          let connectionMessage = "";
          if (window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
            const host = window.location.hostname;
            const port = window.location.port || "4567";
            connectionMessage = ` to ${host}:${port}`;
          }
          
          // Show reconnection message
          const alertMessage = `<i class='fa-solid fa-server'></i> Connection lost${connectionMessage}`;
            
          setAlert(alertMessage, "warning");
          
          // Establish a new connection with proper callback
          ws = connect_websocket((newWs) => {
            if (newWs && newWs.readyState === WebSocket.OPEN) {
              // Reload data from server
              newWs.send(JSON.stringify({ message: "LOAD" }));
              // Restart ping to keep connection alive
              startPing();
              // Update UI with connection info if appropriate
              const successMessage = connectionMessage
                ? `<i class='fa-solid fa-circle-check'></i> Connected${connectionMessage}`
                : "<i class='fa-solid fa-circle-check'></i> Connected";
                
              setAlert(successMessage, "info");
            }
          });
          break;
          
        case WebSocket.CONNECTING:
          // Already attempting to connect, let the process continue
          break;
          
        case WebSocket.OPEN:
          // Connection is already open, verify it's still active
          ws.send(JSON.stringify({ message: "PING" }));
          const connectedMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.connected') : 'Connected';
        setAlert(`<i class='fa-solid fa-circle-check'></i> ${connectedMsg}`, "info");
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

// Helper function to get a cookie by name
function getCookie(name) {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) return parts.pop().split(';').shift();
  return null;
}

// Export functions for browser environment
window.connect_websocket = connect_websocket;
window.reconnect_websocket = reconnect_websocket;
window.handleVisibilityChange = handleVisibilityChange;
window.startPing = startPing;
window.stopPing = stopPing;

// Function to handle MCP server status updates
function handleMCPStatus(status) {
  if (!status) return;
  
  // Create or update MCP status display
  let mcpStatusEl = $("#mcp-status");
  if (!mcpStatusEl.length) {
    // Create MCP status element in messages panel
    $("#messages").append(`
      <div id="mcp-status" class="alert alert-info mt-2" style="display: none;">
        <h6><i class="fas fa-server"></i> MCP Server Status</h6>
        <div id="mcp-status-content"></div>
      </div>
    `);
    mcpStatusEl = $("#mcp-status");
  }
  
  if (status.enabled) {
    const apps = status.apps || [];
    const port = status.port || 3100;
    const statusText = status.status || (status.running ? "running" : "stopped");
    
    let content = `
      <div><strong>Status:</strong> ${statusText}</div>
      <div><strong>Port:</strong> ${port}</div>
      <div><strong>Enabled Apps:</strong> ${apps.length > 0 ? apps.join(", ") : "none"}</div>
    `;
    
    // Add Claude Desktop configuration example
    if (apps.includes("help")) {
      content += `
        <div class="mt-2">
          <small class="text-muted">
            Configure in Claude Desktop settings:<br>
            <code>http://localhost:${port}/mcp</code>
          </small>
        </div>
      `;
    }
    
    $("#mcp-status-content").html(content);
    mcpStatusEl.show();
  } else {
    mcpStatusEl.hide();
  }
}

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
    // Set AI user button title with translation
    if (window.i18nReady) {
      window.i18nReady.then(() => {
        const aiUserTitle = webUIi18n.t('ui.generateAIUserResponse') || "Generate AI user response based on conversation";
        aiUserBtn.attr("title", aiUserTitle);
      });
    } else {
      aiUserBtn.attr("title", "Generate AI user response based on conversation");
    }
    aiUserBtn.removeClass("disabled");
    
    // Add special tooltip for Perplexity
    if (isPerplexity) {
      // Special case for Perplexity
      if (window.i18nReady) {
        window.i18nReady.then(() => {
          const perplexityTitle = webUIi18n.t('ui.generateAIUserResponsePerplexity') || 
            "Generate AI user response (Perplexity requires alternating user/assistant messages)";
          aiUserBtn.attr("title", perplexityTitle);
        });
      } else {
        aiUserBtn.attr("title", "Generate AI user response (Perplexity requires alternating user/assistant messages)");
      }
    }
  } else {
    // Disable AI User button when there's no sufficient conversation
    aiUserBtn.prop("disabled", true);
    aiUserBtn.attr("title", "Start a conversation first to enable AI User");
    aiUserBtn.addClass("disabled");
  }
  
  // Button state updated
}

// Export functions for browser environment
window.playAudioDirectly = playAudioDirectly;
window.playWithAudioElement = playWithAudioElement;
window.playAudioForIOS = playAudioForIOS;
window.processIOSAudioBuffer = processIOSAudioBuffer;
window.clearAudioQueue = clearAudioQueue;
window.resetAudioElements = resetAudioElements;
window.initializeMediaSourceForAudio = initializeMediaSourceForAudio;
window.addToAudioQueue = addToAudioQueue;

// Export audio element as global for compatibility
window.audio = audio;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    connect_websocket,
    reconnect_websocket,
    handleVisibilityChange,
    startPing,
    stopPing,
    updateAIUserButtonState,
    playAudioDirectly,
    playWithAudioElement,
    playAudioForIOS,
    processIOSAudioBuffer,
    clearAudioQueue,
    resetAudioElements,
    initializeMediaSourceForAudio,
    addToAudioQueue
  };
}
