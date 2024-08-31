// Use a Set for faster searching
const mids = new Set();

function createCard(role, badge, html, lang = "en", mid = "", status = true, images = [], monadic = false) {
  const status_class = status === true ? "active" : "";

  // Fix jupyter notebook URL issue
  const replaced_html = html.replaceAll("/lab/tree/monadic/data/", "/lab/tree/");

  let className
  if (role === "user") {
    className = "role-user";
  } else if (role === "assistant") {
    className = "role-assistant";
  } else {
    className = "role-system";
  }

  let image_data = "";
  if (images.length > 0) {
    image_data = images.map((image) => {
      return `<img class='base64-image' src='${image.data}' style='margin-right: 10px;' />`;
    }).join("");
  }

  const card = $(`
    <div class="card mt-3">
      <div class="card-header p-2 ps-3 d-flex justify-content-between">
        <div class="fs-5 card-title mb-0">${badge}</div>
      </div>
      <div class="card-body ${className} pb-1">
        <div class="card-text">${replaced_html}${image_data}</div>
      </div>
    </div>
    `);

  // Check if the card already exists
  if (mid !== "" && mids.has(mid)) {
    return;
  } else if (mid !== "") {
    mids.add(mid);
    card.attr("id", mid);

    // Store header buttons HTML in a variable
    const headerButtons = runningOnFirefox ? `
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
    `;

    card.find(".card-header").append(headerButtons);

    // Attach event listeners directly here
    attachEventListeners(card);
  }

  return card;
}

// Function to attach all event listeners
function attachEventListeners($card) {
  $card.on("click", ".func-play", function () {
    $(this).tooltip('hide');
    const content = $card.find(".card-text");
    let text;
    try {
      text = content.html().replace(/<script[\s\S]*?<\/script>/g, "");
      text = $(text.split(/<hr\s*\/?>/, 1)[0]).text()
    } catch (e) {
      text = content.text()
    }
    text = removeCode(text);
    text = removeMarkdown(text);
    text = removeEmojis(text);
    ttsSpeak(text, true, false, function () { });
  });

  $card.on("click", ".func-stop", function () {
    $(this).tooltip('hide');
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
    const text = messages.find((m) => m.mid === mid).text;
    $card.find("img").each((_i, img) => {
      const src = $(img).attr("src");
      const title = $(img).attr("title");
      const type = $(img).attr("type");
      images.push({ title: title, data: src, type: type });
    });

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
      let role = messages.find((m) => m.mid === mid).role;
      if (role !== "user") {
        role = "sample-" + role;
      }
      $("#select-role").val(role).trigger("change");

      if (images && images.length > 0) {
        updateImageDisplay(images);
      }

      const index = messages.findIndex((m) => m.mid === mid);
      const following = messages.splice(index, messages.length - index);
      following.forEach((m) => {
        $(`#${m.mid}`).remove();
        ws.send(JSON.stringify({ "message": "DELETE", "mid": m.mid }));
      });
      $card.remove();
      ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    }
  });

  $card.on("click", ".func-delete", function () {
    const text = $card.find(".card-text").text();
    const mid = $card.attr('id');

    ttsStop();

    const confirmed = confirm(`Are you sure to delete the message "${text}"?`);
    if (confirmed) {
      $(this).tooltip('hide');
      $card.remove();
      const index = messages.findIndex((m) => m.mid === mid);
      messages.splice(index, 1);
      ws.send(JSON.stringify({ "message": "DELETE", "mid": mid }));
    }
  });

  // Combine mouse events into a single listener
  $card.on("mouseenter mouseleave", ".func-play, .func-copy, .func-delete, .func-edit", function (event) {
    const $icon = $(this).find("i");
    $icon.css("color", event.type === "mouseenter" ? "#DC4C64" : "");
  });
}
