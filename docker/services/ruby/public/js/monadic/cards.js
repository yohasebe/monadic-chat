const mids = [];

function createCard(role, badge, html, lang = "en", mid = "", status = true, images = [], monadic = false) {
  const status_class = status === true ? "active" : "";

  // fix jupyter notebook URL issue
  const replaced_html = html.replaceAll("/lab/tree/monadic/data/", "/lab/tree/");

  let className
  if (role === "user") {
    className = "role-user";
  } else if(role === "assistant"){
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

  if (mid !== "" && mids.includes(mid)){
    return;
  } else if (mid !== "") {
    mids.push(mid);
    card.attr("id", mid);

    if (runningOnFirefox) {
      card.find(".card-header").append(`
          <div class="me-1 text-secondary d-flex align-items-center">
            <span title="Copy" class="func-copy me-3"><i class="fas fa-copy"></i></span>
            <span title="Delete" class="func-delete me-3" ><i class="fas fa-xmark"></i></span>
            <span title="Edit" class="func-edit me-3"><i class="fas fa-pen-to-square"></i></span>
            <span class="status ${status_class}"></span>
          </div>
        `);
    } else {
      card.find(".card-header").append(`
          <div class="me-1 text-secondary d-flex align-items-center">
            <span title="Copy" class="func-copy me-3"><i class="fas fa-copy"></i></span>
            <span title="Start TTS" class="func-play me-3"><i class="fas fa-play"></i></span>
            <span title="Stop TTS" class="func-stop me-3"><i class="fas fa-stop"></i></span>
            <span title="Delete" class="func-delete me-3" ><i class="fas fa-xmark"></i></span>
            <span title="Edit" class="func-edit me-3"><i class="fas fa-pen-to-square"></i></span>
            <span class="status ${status_class}"></span>
          </div>
        `);
    }
  }

  if (mid === "") {
    return card;
  }

  $(document).on("click", `#${mid} .func-play`, function () {
    $(this).tooltip('hide');
    const $this = $(this); // Store the reference to the clicked element
    const content = $(`#${mid} .card-text`);
    let text; 
    try {
      text = $(content.html().split(/<hr\s*\/?>/, 1)[0]).text()
    } catch (e) {
      text = content.text()
    }
    text = removeCode(text);
    text = removeMarkdown(text);
    text = removeEmojis(text);
    ttsSpeak(text, true, false, function (){} );
  });

  $(document).on("click", `#${mid} .func-stop`, function () {
    $(this).tooltip('hide');
    ttsStop();
  });

  // click on the copy icon will copy the message
  $(document).on("click", `#${mid} .func-copy`, function () {
    $(this).tooltip('hide');
    const $this = $(this); // Store the reference to the clicked element
    const text = $(`#${mid} .card-text`).text();
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

  // click on the edit icon will enable editing the message
  $(document).on("click", `#${mid} .func-edit`, function () {
    $(this).tooltip('hide');
    const $this = $(this); // Store the reference to the clicked element
    const text = messages.find((m) => m.mid === mid).text;

    // check if text is JSON
    let json = false;
    try {
      JSON.parse(text);
      json = true;
    } catch (e) {
      ;
    }
    if (json) {
      alert("The current app is monadic. You can't edit JSON messages");
      return;
    }

    const confirmed = confirm(`Are you sure to edit this message?\nThis will delete all the messages after it.`);
    if (confirmed) {
      $this.find("i").removeClass("fa-square-pen").addClass("fa-check").css("color", "#DC4C64");
      // "#message" textbox should automatically expand according to the size of the text
      $("#message").val(text).trigger("input").focus();
      let role = messages.find((m) => m.mid === mid).role;
      if(role !== "user") {
        role = "sample-" + role;
      }
      $("#select-role").val(role).trigger("change");

      // add any attached images to the image list
      const images = messages.find((m) => m.mid === mid).images;

      let image_used = "";
      if (images && images.length > 0) {
        updateImageDisplay(images);
      }

      // remove this message and all the messages after this message
      const index = messages.findIndex((m) => m.mid === mid);
      const following = messages.splice(index, messages.length - index);
      // remove the cards of the messages after this message
      following.forEach((m) => {
        $(`#${m.mid}`).remove();
        ws.send(JSON.stringify({"message": "DELETE", "mid": m.mid}));
      });
      // remove this card
      $(`#${mid}`).remove();
      ws.send(JSON.stringify({"message": "DELETE", "mid": mid}));
    }
  });

  // click on the delete icon will delete the message after confirmation
  // the card will be removed from the DOM and the message will be removed from the message list
  // also, the deletion is notified via websocket

  $(document).on("click", `#${mid} .func-delete`, function () {
    const text = $(`#${mid} .card-text`).text();

    ttsStop();

    const confirmed = confirm(`Are you sure to delete the message "${text}"?`);
    if (confirmed) {
      $(this).tooltip('hide');
      $(`#${mid}`).remove();
      const index = messages.findIndex((m) => m.mid === mid);
      messages.splice(index, 1);
      ws.send(JSON.stringify({"message": "DELETE", "mid": mid}));
    }
  });

  // when the mouse cursor hover eather the copy, play, or delete icon, the color of the icon is changed
  // the color will be reset when the mouse cursor leaves the icon
  // this feature is disabled when the text to speech is playing

  $(document).on("mouseenter", `#${mid} .func-play`, function () {
    // if (speechSynthesis.speaking) {
    //   return;
    // }
    $(this).find("i").css("color", "#DC4C64");
  });

  $(document).on("mouseleave", `#${mid} .func-play`, function () {
    // if (speechSynthesis.speaking) {
    //   return;
    // }
    $(this).find("i").css("color", "");
  });

  $(document).on("mouseenter", `#${mid} .func-copy, #${mid} .func-delete, #${mid} .func-edit`, function () {
    $(this).find("i").css("color", "#DC4C64");
  });

  $(document).on("mouseleave", `#${mid} .func-copy, #${mid} .func-delete, #${mid} .func-edit`, function () {
    $(this).find("i").css("color", "");
  });

  return card;
}
