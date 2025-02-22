// Use a Set for faster searching
const mids = new Set();

function escapeHtml(unsafe)
{
    if (unsafe === null || unsafe === undefined) {
        return "";
    }

    return unsafe
         .replace(/&/g, "&amp;")
         .replace(/</g, "&lt;")
         .replace(/>/g, "&gt;")
         .replace(/"/g, "&quot;")
         .replace(/'/g, "&#039;");
 }

function createCard(role, badge, html, _lang = "en", mid = "", status = true, images = [], _monadic = false) {
  const status_class = status === true ? "active" : "";

  // Fix jupyter notebook URL issue
  let replaced_html;
  if (role === "system") {
    replaced_html = escapeHtml(html);
  } else {
    replaced_html = html.replaceAll("/lab/tree/", "/lab/tree/");
  }

  // add "?dummy=TIMESTAMP" to the end of the URL to prevent the browser from caching the image
  replaced_html = replaced_html.replace(/<img src="([^"]+)"/g, '<img src="$1?dummy=' + Date.now() + '"');

  let className;
  if (role === "user") {
    className = "role-user";
  } else if (role === "assistant") {
    className = "role-assistant";
  } else {
    className = "role-system";
  }

  let image_data = "";
  if (images && images.length > 0) {
    image_data = images.map((image) => {
      if (image.type === 'application/pdf') {
        return `
          <div class="pdf-preview mb-3">
          <i class="fas fa-file-pdf text-danger"></i>
          <span class="ms-2">${image.title}</span>
          </div>
          `;
      } else {
        return `<img class='base64-image mb-3' src='${image.data}' alt='${image.title}' style='max-width: 100%; height: auto;' />`;
      }
    }).join("");
  }

  // Create the card element with the mid attribute
  const card = $(`
    <div class="card mt-3" id="${mid}"> 
    <div class="card-header p-2 ps-3 d-flex justify-content-between">
    <div class="fs-5 card-title mb-0">${badge}</div>
    ${(!runningOnChrome && !runningOnEdge && !runningOnSafari) ? `
        <div class="me-1 text-secondary d-flex align-items-center">
        <span title="Copy" class="func-copy me-3"><i class="fas fa-copy"></i></span>
        <span title="Delete" class="func-delete me-3" ><i class="fas fa-xmark"></i></span>
        <span title="Edit" class="func-edit me-3"><i class="fas fa-pen-to-square"></i></span>
        <span class="status ${status_class}"></span>
        </div>
        ` : `
        <div class="me-1 text-secondary d-flex align-items-center">
        <span title="Copy" class="func-copy me-3"><i class="fas fa-copy"></i></span>
        <span title="Start TTS" class="func-play me-3"><i class="fas fa-play"></i></span>
        <span title="Stop TTS" class="func-stop me-3"><i class="fas fa-stop"></i></span>
        <span title="Delete" class="func-delete me-3" ><i class="fas fa-xmark"></i></span>
        <span title="Edit" class="func-edit me-3"><i class="fas fa-pen-to-square"></i></span>
        <span class="status ${status_class}"></span>
        </div>
        `}
    </div>
    <div class="card-body ${className} pb-1">
    <div class="card-text">${replaced_html}${image_data}</div>
    </div>
    </div>
    `);

  // Attach event listeners
  attachEventListeners(card);

  // Add to mids Set if mid is not empty
  if (mid !== "") {
    mids.add(mid);
  }

  return card;
}

// Function to attach all event listeners
function attachEventListeners($card) {
  $card.on("click", ".func-play", function () {
    $(this).tooltip('hide');

    $("#monadic-spinner").show();

    const content = $card.find(".card-text");
    let text;
    try {
      text = content.html().replace(/<style>[\s\S]*?<\/style>/g, "");
      text = text.replace(/<script>[\s\S]*?<\/script>/g, "");
      text = $(text.split(/<hr\s*\/?>/, 1)[0]).text()
    } catch (e) {
      text = content.text()
    }
    text = removeCode(text);
    text = removeMarkdown(text);
    text = removeEmojis(text);
    ttsSpeak(text, true);
  });

  $card.on("click", ".func-stop", function () {
    $(this).tooltip('hide');
    $("#monadic-spinner").hide();
    ttsStop();
  });

  $card.on("click", ".func-copy", function () {
    $(this).tooltip('hide');
    const $this = $(this);
    const text = $card.find(".card-text").text();
    navigator.clipboard.writeText(text).then(function () {
      $this.find("i").removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
      setTimeout(function () {
        $this.find("i").removeClass("fa-check").addClass("fa-copy").css("color", "");
      }, 1000);
    }, function () {
      $this.find("i").removeClass("fa-copy").addClass("fa-times").css("color", "#DC4C64");
      setTimeout(function () {
        $this.find("i").removeClass("fa-times").addClass("fa-copy").css("color", "");
      }, 1000);
    });
  });

  $card.on("click", ".func-edit", function () {
    $(this).tooltip('hide');
    const $this = $(this);
    const mid = $card.attr('id');
    const messageIndex = messages.findIndex((m) => m.mid === mid);
    const currentMessage = messages[messageIndex];

    if (!currentMessage || !currentMessage.text) {
      alert("The current message can't be edited");
      return;
    }

    const text = currentMessage.text;

    // Handle attached files
    if (currentMessage.images) {
      images = [...currentMessage.images];
      updateFileDisplay(images);
    } else {
      images = [];
      $("#image-used").empty();
    }

    let json = false;
    try {
      JSON.parse(text);
      json = true;
    } catch (e) {
      // Not JSON, continue
    }

    if (json) {
      alert("The current app is monadic. You can't edit JSON messages");
      return;
    }

    const confirmed = confirm(`Are you sure to edit this message?\nThis will delete all the messages after it.`);
    if (confirmed) {
      $this.find("i").removeClass("fa-square-pen").addClass("fa-check").css("color", "#DC4C64");
      $("#message").val(text).trigger("input").focus();

      let role = currentMessage.role;
      if (role !== "user") {
        role = "sample-" + role;
      }
      $("#select-role").val(role).trigger("change");

      // Delete all subsequent messages
      const subsequentMessages = messages.slice(messageIndex + 1);
      subsequentMessages.forEach((m) => {
        $(`#${m.mid}`).remove();
        ws.send(JSON.stringify({ "message": "DELETE", "mid": m.mid }));
        mids.delete(m.mid);
      });

      // Delete current message
      messages.splice(messageIndex);
      $card.remove();
      ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
      mids.delete(mid);
    }
  });

  $card.on("click", ".func-delete", function () {
    const mid = $card.attr('id');
    const messageIndex = messages.findIndex((m) => m.mid === mid);

    let confirmed = false

    if (!messages[messageIndex] || !messages[messageIndex].text) {
      confirmed = true;
    } else {
      const text = messages[messageIndex].text;
      ttsStop();
      confirmed = confirm(`Are you sure to delete the message "${text}"?`);
    }

    if (confirmed) {
      $(this).tooltip('hide');

      // Delete all subsequent messages
      const subsequentMessages = messages.slice(messageIndex + 1);
      subsequentMessages.forEach((m) => {
        $(`#${m.mid}`).remove();
        ws.send(JSON.stringify({ "message": "DELETE", "mid": m.mid }));
        mids.delete(m.mid);
      });

      // Delete current message
      messages.splice(messageIndex);
      $card.remove();
      ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
      mids.delete(mid);
    }
  });

  // Combine mouse events into a single listener
  $card.on("mouseenter", ".func-play, .func-stop, .func-copy, .func-delete, .func-edit", function () {
    $(this).tooltip('show');
    const $icon = $(this).find("i");
    $icon.css("color", "#DC4C64");
  });

  $card.on("mouseleave", ".func-play, .func-stop, .func-copy, .func-delete, .func-edit", function () {
    $(this).tooltip('hide');
    const $icon = $(this).find("i");
    $icon.css("color", "");
  });
}
