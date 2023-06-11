const mids = [];

function createCard(role, badge, html, lang = "en", mid = "", status = true) {

  const status_class = status === true ? "active" : "";
  let className
  if (role === "user") {
    className = "role-user";
  } else if(role === "assistant"){
    className = "role-assistant";
  } else {
    className = "role-system";
  }
  const card = $(`
    <div class="card mt-3">
      <div class="card-header p-2 ps-3 d-flex justify-content-between">
        <div class="fs-5 card-title mb-0">${badge}</div>
      </div>
      <div class="card-body ${className} pb-1">
        <div class="card-text">${html}</div>
      </div>
    </div>
    `);

  if (mid !== "" && mids.includes(mid)){
    return;
  } else if (mid !== "") {
    mids.push(mid);
    card.attr("id", mid);
    card.find(".card-header").append(`
        <div class="me-1 text-secondary d-flex align-items-center">
          <span class="func-copy me-3"><i class="fas fa-copy"></i></span>
          <span class="func-play me-3"><i class="fas fa-play"></i></span>
          <span class="func-delete me-3" ><i class="fas fa-xmark"></i></span>
          <span class="func-edit me-3"><i class="fas fa-pen-to-square"></i></span>
          <span class="status ${status_class}"></span>
        </div>
      `);
  }

  $(document).on("click", `#${mid} .func-play`, function () {
    // cutoff text after <hr> or <hr/> or <hr /> of text content and remove all HTML tags
    const content = html.split(/<hr\s*\/?>/, 1)[0].replace(/<[^>]*>?/gm, '');
    const $this = $(this); // Store the reference to the clicked element
    if (speechSynthesis.speaking) {
      speechSynthesis.cancel();
      $this.find("i").removeClass("fa-stop").addClass("fa-play").css("color", "");
    } else {
      $this.find("i").removeClass("fa-play").addClass("fa-stop").css("color", "#DC4C64");
      const sentences = removeEmojis(content).split(/[.?!:;。．？！]/).filter(Boolean);
      for (let i = 0; i < sentences.length; i++) {
        if(i === sentences.length - 1) {
          speak(sentences[i].trim(), lang, function () {
            $this.find("i").removeClass("fa-stop").addClass("fa-play").css("color", "");
          });
        } else {
          speak(sentences[i].trim(), lang, function (){} );
        }
      }
    }
  });

  // click on the copy icon will copy the message
  $(document).on("click", `#${mid} .func-copy`, function () {
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
    const $this = $(this); // Store the reference to the clicked element
    // confirm to delete this message and all the messages after this message
    const confirmed = confirm(`Are you sure to edit this message?\nThis will delete all the messages after it.`);
    if (confirmed) {
      $this.find("i").removeClass("fa-square-pen").addClass("fa-check").css("color", "#DC4C64");
      const text = messages.find((m) => m.mid === mid).text;
      // "#message" textbox should automatically expand according to the size of the text
      $("#message").val(text).trigger("input").focus();
      let role = messages.find((m) => m.mid === mid).role;
      if(role !== "user") {
        role = "sample-" + role;
      }
      $("#select-role").val(role).trigger("change");
      // remove this message and all the messages after this message
      const index = messages.findIndex((m) => m.mid === mid);
      messages.splice(index, messages.length - index);
      // remove this card
      $(`#${mid}`).nextAll().remove();
      $(`#${mid}`).remove();
      ws.send(JSON.stringify({"message": "DELETE", "mid": mid}));
    }
  });

  // click on the delete icon will delete the message after confirmation
  // the card will be removed from the DOM and the message will be removed from the message list
  // also, the deletion is notified via websocket

  $(document).on("click", `#${mid} .func-delete`, function () {
    const text = $(`#${mid} .card-text`).text();
    if (speechSynthesis.speaking) {
      speechSynthesis.cancel();
    }
    const confirmed = confirm(`Are you sure to delete the message "${text}"?`);
    if (confirmed) {
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
    if (speechSynthesis.speaking) {
      return;
    }
    $(this).find("i").css("color", "#DC4C64");
  });

  $(document).on("mouseleave", `#${mid} .func-play`, function () {
    if (speechSynthesis.speaking) {
      return;
    }
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
