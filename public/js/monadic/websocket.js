//////////////////////////////
// set up the websocket
//////////////////////////////

let ws = connect_websocket();
let verified = false;

// message is submitted upon pressing enter
const message = $("#message")[0];

message.addEventListener("compositionstart", function() {
  message.dataset.ime = "true";
});

message.addEventListener("compositionend", function() {
  message.dataset.ime = "false";
});


document.addEventListener("keydown", function(event) {
  if($("#check-easy-submit").is(":checked") && !$("#message").is(":focus") && event.key === "ArrowRight") {
    event.preventDefault();
    if ($("#voice").prop("disabled") === false) {
      $("#voice").click();
    }
  }
});

message.addEventListener("keydown", function(event) {
  if($("#check-easy-submit").is(":checked") && (event.key === "Enter") && message.dataset.ime !== "true") {
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

// Add event listener for visibility change
document.addEventListener('visibilitychange', handleVisibilityChange);


//////////////////////////////
// WebSocket event handlers
//////////////////////////////

const msgBuffer = [];
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
      ws.send(JSON.stringify({message: 'PING'}));
    }
  }, 30000);
}

function stopPing() {
  if (pingInterval) {
    clearInterval(pingInterval);
  }
}

const chatBottom = $("#chat-bottom").get(0);
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

  // if (!/\$[^$]+\$/.test(element.text())) {
  //   return;
  // }

  if (typeof MathJax === 'undefined') {
    console.error('MathJax is not loaded. Please make sure to include the MathJax script in your HTML file.');
    return;
  }

  // Get the DOM element from the jQuery object
  const domElement = element.get(0);

  // Typeset the element using MathJax
  MathJax.typesetPromise([domElement])
    .then(() => {
      console.log('MathJax element re-rendered successfully.');
    })
    .catch((err) => {
      console.error('Error re-rendering MathJax element:', err);
    });
}

const mermaid_config = {
  startOnLoad: true,
  securityLevel: 'strict',
  theme: 'default',
  themeVariables: {
    arrowheadSize: '1.5em', // Larger arrowheads
    classBackground: '#ffffff',
    classBorder: '1px solid #333333',
    classText: '#333333',
    edgeLabelBackground: '#ffffff', // White background for edge labels
    flowchartNodeSpacing: '50px', // Spacing between nodes in flowcharts
    fontFamily: '"Arial", sans-serif',
    fontSize: '16px',
    ganttLineColor: '#0077CC',
    gitBranchLabelBackground: '#DDDDDD',
    gitBranchLabelColor: '#333333',
    gitCommitDotColor: '#0077CC',
    lineColor: '#0077CC', // Use a consistent color for lines
    nodeBackground: '#ffffff', // Background color for nodes
    nodeBorder: '1px solid #333333',
    noteBackgroundColor: '#DDDDDD',
    noteBorderColor: '#333333',
    pie1: '#FFCC00', // Custom color for the first slice
    pie2: '#0077CC', // Custom color for the second slice
    primaryBorderColor: '#333333',
    primaryColor: '#0077CC', // Color for entities
    primaryTextColor: '#333333',  textColor: '#333333',
    relationshipLineColor: '#333333', // Color for lines
    sequenceDiagramMargin: '50px', // Margin around sequence diagrams
    sequenceNumberColor: '#333333',
    stateBorderColor: '#333333',
    stateLabelBackground: '#ffffff',
    stateTextColor: '#333333',
    strokeWidth: '2px', // Thicker lines for visibility
    textColor: '#333333', // Ensure text is readable
  },
  flowchart: {
    useMaxWidth: true,
    htmlLabels: true,
    curve: 'linear' // Makes the paths straight
  },
  sequence: {
    diagramMarginX: 50,
    diagramMarginY: 10,
    actorMargin: 50,
    width: 150,
    height: 65,
    boxMargin: 10,
    boxTextMargin: 5,
    noteMargin: 10,
    messageMargin: 35,
    mirrorActors: true
  },
  gantt: {
    titleTopMargin: 25,
    barHeight: 20,
    barGap: 4,
    topPadding: 50,
    leftPadding: 75,
    gridLineStartPadding: 35,
    fontSize: 11,
    numberSectionStyles: 4,
    axisFormat: '%Y-%m-%d'
  },
  class: {
    arrowMarkerAbsolute: true
  },
  state: {
    dividerMargin: 10,
    sizeUnit: 5,
    padding: 8,
    textHeight: 10,
    titleShift: -15
  },
  pie: {
    useMaxWidth: true
  },
  er: {
    layoutDirection: 'TB' // Top-Bottom layout
  },
  gitGraph: {
    showCommitLabel: true // Show commit messages
  }
};

async function applyMermaid(element) {
  // Get the DOM element from the jQuery object
  const domElement = element.get(0);
  element.find("mermaid").each(function () {
    const mermaidElement = $(this);
    const mermaidText = mermaidElement.text();
    mermaidElement.replaceWith(`<pre class='mermaid'>${mermaidText}</pre>`);
  });

  mermaid.initialize({ startOnLoad: true });
  await mermaid.run({
    querySelector: '.mermaid'
  });
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

function connect_websocket(callback) {
  const ws = new WebSocket('ws://localhost:4567');


  let loadedApp = "Chat";
  let infoHtml = "";

  ws.onopen = function () {
    console.log('WebSocket connected');
    setAlert("<p>Verifying token . . .</p>", "info");
    ws.send(JSON.stringify({message: "CHECK_TOKEN", initial: true, contents: $("#token").val()}));

    if (!mediaSource) {
      mediaSource = new MediaSource();
      mediaSource.addEventListener('sourceopen', () => {
        console.log('MediaSource opened');
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

    // check verified at a regular interval
    let verificationCheckTimer = setInterval(function () {
      if (verified) {
        ws.send(JSON.stringify({"message": "LOAD"}));
        startPing();
        if (callback) {
          callback(ws);
        }
        clearInterval(verificationCheckTimer);
      }
    }, 1000);
  }

  ws.onmessage = function (event) {
    const data = JSON.parse(event.data);
    switch (data["type"]) {
      case "audio":
        const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));
        audioDataQueue.push(audioData);
        processAudioDataQueue();
      case "pong":
        console.log("Received PONG");
        break;
      case "error":
        msgBuffer.length = 0;
        $("#send, #clear, #voice").prop("disabled", false);
        $("#chat").html("");
        $("#temp-card").hide();
        $("#indicator").hide();
        $("#user-panel").show();

        // check if $("#discourse .card").last() is a user card
        const lastCard = $("#discourse .card").last();
        if (lastCard.find(".user-color").length !== 0) {
          deleteMessage(lastCard.attr('id'));
        }

        $("#message").val(params["message"]);

        setAlert(data["content"], "danger");

        setInputFocus()

        break;
      case "token_verified":
        console.log("Token verified");
        // insert data["token"] into the api-token input field
        $("#api-token").val(data["token"]);

        const model_options = data['models'].map(
          model => `<option value="${model}">${model}</option>`
        );
        $("#model").html(model_options);
        $("#model").val("gpt-3.5-turbo-0125");

        const token_verified = `\
              <p>${data['content']}</p>\
              <div class='like-h5'><i class='fa-solid fa-robot'></i> Available Models</div>\
              <div>\
                ${data['models'].join('<br />')}\
              </div>\
            `
        setAlert(token_verified, "success");
        verified = true;

        $("#start").prop("disabled", false);
        $("#send, #clear, #voice").prop("disabled", false);

        // filter out the models that are not available from the dropdown
        const available_models = data['models']
        $("#apps option").each(function () {
          if (!available_models.includes(apps[$(this).val()]["model"])) {
            $(this).remove();
          }
        });

        break;
      case "token_not_verified":
        console.log("Token not verified");
        $("#api-token").val("");

        const message = "<p>Please set a valid API token and press Verify Token.</p>"
        $("#start").prop("disabled", true);
        $("#send, #clear, #voice").prop("disabled", true);
        $("#api-token").focus();
        setAlert(message, "warning");

        break;
      case "apps":
        let version_string = data["version"]
        data["docker"] ? version_string += " (Docker)" : version_string += " (Local)"
        $("#monadic-version-number").html(version_string);
        if (Object.keys(apps).length === 0) {
          for (const [key, value] of Object.entries(data["content"])) {
            apps[key] = value;
            const default_label = value["app_name"] === defaultApp ? " (Default)" : "";
            $("#apps").append(`<option value="${key}">${value["app_name"]}${default_label}</option>`);
          }
          $("#base-app-title").text(apps[$("#apps").val()]["app_name"]);
          $("#base-app-icon").html(apps[$("#apps").val()]["icon"]);
          $("#base-app-desc").html(apps[$("#apps").val()]["description"]);

          if ($("#apps").val() === "PDF") {
            ws.send(JSON.stringify({message: "PDF_TITLES"}));
          }

        }
        originalParams = apps["Chat"];
        resetParams();
        break;
      case "parameters":
        loadedApp = data["content"]["app_name"];
        setAlert("Please wait...", "secondary");
        loadParams(data["content"], "loadParams");
        const currentApp = apps[$("#apps").val()] || apps[defaultApp];
        $("#base-app-title").text(currentApp["app_name"]);
        $("#base-app-icon").html(currentApp["icon"]);
        $("#base-app-desc").html(currentApp["description"]);
        $("#start").focus();
        break;
      case "whisper":
        infoHtml = formatInfo(data["content"]);
        if (data["content"] !== infoHtml) {
          setAlert(infoHtml, "info");
        }
        $("#message").val($("#message").val() + " " + data["content"]);

        $("#send, #clear, #voice").prop("disabled", false);
        if ($("#check-easy-submit").is(":checked")) {
          $("#send").click();
        }
        setInputFocus()
        break;
      case "info":
        infoHtml = formatInfo(data["content"]);
        if (infoHtml !== "") {
          setAlert(infoHtml, "info");
        }
        break;
      case "pdf_titles":
        const pdf_table = "<div class='like-h6'><i class='fas fa-file-pdf'></i> Uploaded PDF</div>" +
          "<table class='table mt-1 mb-3'><tbody>" +
          data["content"].map((title, index) => {
            return `<tr><td>${title}</td><td class="align-middle text-end"><button id='pdf-del-${index}' type='botton' class='btn btn-sm btn-secondary'><i class='fas fa-trash'></i></button></td></tr>`;
          }).join("") +
          "</tbody></table>";
        $("#pdf-titles").html(pdf_table);
        data["content"].map((title, index) => {
          $(`#pdf-del-${index}`).click(function () {
            $("#pdfDeleteConfirmation").modal("show");
            $("#pdfToDelete").text(title);
            $("#pdfDeleteConfirmed").on("click", function (event) {
              event.preventDefault();
              ws.send(JSON.stringify({message: "DELETE_PDF", contents: title}));
              $("#pdfDeleteConfirmation").modal("hide");
              $("#pdfToDelete").text("");
            });
          });
        })
        break
      case "pdf_deleted":
        if(data["res"] === "success") {
          setAlert(data["content"], "info");
        } else {
          setAlert(data["content"], "danger");
        }
        ws.send(JSON.stringify({"message": "PDF_TITLES"}));
        break;
      case "change_status":
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
      case "past_messages":
        messages.length = 0;
        data["content"].forEach((msg) => {
          messages.push(msg);
          switch (msg["role"]) {
            case "user":
              let msg_text = msg["text"].replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br />");
              let image_data;
              if(msg["image"] !== undefined){
                image_data = msg["image"]["data"];
              } else {
                image_data = ""
              }
              const userElement = createCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + msg_text + "</p>", msg["lang"], msg["mid"], msg["active"], image_data);
              $("#discourse").append(userElement);
              break;
            case "assistant":
              const gptElement = createCard("gpt", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>", msg["html"], msg["lang"], msg["mid"], msg["active"]);
              $("#discourse").append(gptElement);

              if (apps[loadedApp]["mermaid"] === "true") {
                applyMermaid(htmlContent);
              }

              if (apps[loadedApp]["mathjax"] === "true") {
                applyMathJax(gptElement);
              }

              break;
            case "system":
              const systemElement = createCard("system", "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 text-success'>System</span>", msg["html"], msg["lang"], msg["mid"], msg["active"]);
              $("#discourse").append(systemElement);
              break;
          }
        });
        setAlert(formatInfo(data["content"]), "info");

        if (messages.length > 0) {
          $("#start-label").text("Continue Session");
        } else {
          $("#start-label").text("Start Session");
        }

        break;
      case "message":
        if (data["content"] === "DONE") {
          ws.send(JSON.stringify({"message": "HTML"}));
        } else if (data["content"] === "CLEAR") {
          $("#chat").html("");
          $("#temp-card .status").hide();
          $("#indicator").show();
        }
        break;
      case "html":
        messages.push(data["content"]);
        msgBuffer.length = 0;
        let htmlElement;
        if (data["content"]["role"] === "assistant") {
          htmlElement = createCard("assistant", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
        } else if (data["content"]["role"] === "user") {
          let content_text = data["content"]["text"].replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br />");
          let image_data;
          if(data["image"] !== undefined){
            image_data = data["image"]["data"];
          }
          htmlElement = createCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + content_text + "</p>", data["content"]["lang"], data["content"]["mid"], true, image_data);
        } else if (data["content"]["role"] === "system") {
          htmlElement = createCard("system", "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
        }

        $("#discourse").append(htmlElement);

        const htmlContent = $("#discourse div.card:last");

        if (params["mermaid"] === "true") {
          applyMermaid(htmlContent);
        }

        if (params["mathjax"] === "true") {
          applyMathJax(htmlContent);
        }

        $("#chat").html("");
        $("#temp-card").hide();
        $("#indicator").hide();
        $("#user-panel").show();
        if (!isElementInViewport(mainPanel)){
          mainPanel.scrollIntoView(false);
        }
        setInputFocus()
        break;
      case "user":
        let message_obj = { "role": "user", "text": data["content"]["text"], "html": data["content"]["html"], "mid": data["content"]["mid"] }
        if(data["image"] !== undefined) {
          message_obj.image = data["image"];
        }
        messages.push(message_obj);
        let content_text = data["content"]["text"].replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br />");
        let image_data;
        if(data["image"] !== undefined){
          image_data = data["image"]["data"];
        }
        const userElement = createCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", "<p>" + content_text + "</p>", data["content"]["lang"], data["content"]["mid"], true, image_data);
        $("#discourse").append(userElement);
        $("#temp-card").show();
        $("#temp-card .status").hide();
        $("#indicator").show();
        $("#user-panel").hide();
        break;
      case "sentence":
        console.log("sentence: " + data["content"]);
        if (data["content"] !== null) {
          let text = data["content"].trim().replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br />");

          if (params["auto_speech"]) {
            text = removeCode(text);
            text = removeEmojis(text);
            ttsSpeak(text, false, function () {});
          }

        }
        break;
      default:
        $("#indicator").show();
        msgBuffer.push(data["content"]);
        if (data["content"] !== undefined) {
          $("#chat").html($("#chat").html() + data["content"].replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br />"));
        }
        if (!isElementInViewport(chatBottom)){
          chatBottom.scrollIntoView(false);
        }
    }
  }

  ws.onclose = function (e) {
    console.log(`Socket is closed. Reconnect will be attempted in ${reconnectDelay} second.`, e.reason);
    reconnect_websocket(ws);
  }

  ws.onerror = function (err) {
    console.error('Socket encountered error: ', err.message, 'Closing socket');
    // set a message in the alert box
    setAlert("<p>Connection terminated.</p>", "warning");
    ws.close();
  }
  return ws;
}

function reconnect_websocket(ws, callback) {
  switch (ws.readyState) {
    case WebSocket.CLOSED:
      console.log('WebSocket is closed.');
      ws = connect_websocket(callback);
      break;
    case WebSocket.CLOSING:
      console.log('WebSocket is closing.');
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
      console.log('WebSocket is open.');
      if (callback) {
        callback(ws);
      }
      break;
  }
}
