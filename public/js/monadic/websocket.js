//////////////////////////////
// set up the websocket
//////////////////////////////

let ws = connect_websocket();

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
    ws.close();
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
      ws.send(JSON.stringify({ message: 'PING' }));
    }
  }, 30000);
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
  if (!/\$[^$]+\$/.test(element.text())) {
    return;
  }

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

function connect_websocket(callback) {
  const ws = new WebSocket('ws://localhost:4567');

  let loadedApp = "Chat";
  let infoHtml = "";

  ws.onopen = function () {
    console.log('WebSocket connected');
    ws.send(JSON.stringify({"message": "LOAD"}));
    ws.send(JSON.stringify({"message": "CHECK_TOKEN", "contents": $("#token").val()}));
    startPing();
    if (callback) {
      callback(ws);
    }
  }

  ws.onmessage = function (event) {
    const data = JSON.parse(event.data);
    switch (data["type"]) {
      case "pong":
        console.log("Received PONG");
        break;
      case "error":
        msgBuffer.length = 0;
        $("#send, #clear, #voice").prop("disabled", false);
        $("#chat").html("");
        $("#chat-card").hide();
        $("#spinner-gpt").hide();
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
        if (messages.length === 0) {
          const token_verified = `\
            <p>${data['content']}</p>\
            <div class='like-h5'><i class='fa-solid fa-robot'></i> Available Models</div>\
            <p>\
              ${data['models'].join('<br />')}\
            </p>\
          `
          setAlert(token_verified, "info");
        }
        $("#start").prop("disabled", false);

        // filter out the models that are not available from the dropdown
        const available_models = data['models']
        $("#apps option").each(function () {
          if (!available_models.includes(apps[$(this).val()]["model"])) {
            $(this).remove();
          }
        });

        break;
      case "token_not_found":
        if (messages.length === 0) {
          const not_found = "<p>Please set a valid API token and press Verify Token.</p>"
          setAlert(not_found, "warning");
          $("#start").prop("disabled", true);
        }
        $("#api-token-form").show();
        $("#api-token").focus();
        break;
      case "apps":
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
        $("#pdf-db").show();
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
              const userElement = createCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", msg["html"], msg["lang"], msg["mid"], msg["active"]);
              $("#discourse").append(userElement);
              break;
            case "assistant":
              const gptElement = createCard("gpt", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 gpt-color'>Assistant</span>", msg["html"], msg["lang"], msg["mid"], msg["active"]);
              $("#discourse").append(gptElement);
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
          $("#chat-card .status").hide();
          $("#spinner-gpt").show();
        }
        break;
      case "html":
        messages.push(data["content"]);
        msgBuffer.length = 0;
        let htmlElement;
        if (data["content"]["role"] === "assistant") {
          htmlElement = createCard("gpt", "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 gpt-color'>Assistant</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
        } else if (data["content"]["role"] === "user") {
          htmlElement = createCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
        } else if (data["content"]["role"] === "system") {
          htmlElement = createCard("system", "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
        }

        $("#discourse").append(htmlElement);

        const htmlContent = $("#discourse div.card:last");

        if (params["mathjax"] === "true") {
          applyMathJax(htmlContent);
        }

        $("#chat").html("");
        $("#chat-card").hide();
        $("#spinner-gpt").hide();
        $("#user-panel").show();
        if (!isElementInViewport(mainPanel)){
          mainPanel.scrollIntoView(false);
        }
        setInputFocus()
        break;
      case "user":
        messages.push({ "role": "user", "text": data["content"]["text"], "html": data["content"]["html"], "mid": data["content"]["mid"] });
        const userElement = createCard("user", "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>", data["content"]["html"], data["content"]["lang"], data["content"]["mid"], true);
        $("#discourse").append(userElement);
        $("#chat-card").show();
        $("#chat-card .status").hide();
        $("#spinner-gpt").show();
        $("#user-panel").hide();
        break;
      case "sentence":
        // speak the text if auto_speak is enabled
        if (data["content"] !== null) {
          const text = removeEmojis(data["content"]).trim();
          // if ($("#check-auto-speech").is(":checked")) {
          if (params["auto_speech"]) {
            speak(text, data["lang"], function () {});
          }
        }
        break;
      default:
        $("#spinner-gpt").show();
        msgBuffer.push(data["content"]);
        $("#chat").html($("#chat").html() + data["content"].replace(/\n/g, "<br />"));
        if (!isElementInViewport(chatBottom)){
          chatBottom.scrollIntoView(false);
        }
    };
  }

  ws.onclose = function (e) {
    console.log(`Socket is closed. Reconnect will be attempted in ${reconnectDelay} second.`, e.reason);
    reconnect_websocket(ws);
  }

  ws.onerror = function (err) {
    console.error('Socket encountered error: ', err.message, 'Closing socket');
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
