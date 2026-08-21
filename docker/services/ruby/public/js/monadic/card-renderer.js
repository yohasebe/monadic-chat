/**
 * Card Renderer for Monadic Chat
 *
 * Generates HTML card elements for chat messages.
 * Handles role-specific styling, image rendering, mask overlays,
 * and turn number badges.
 *
 * Dependencies (runtime, via window.*):
 *   getTranslation (utilities.js)
 *   runningOnChrome, runningOnEdge, runningOnSafari (utilities.js)
 *   attachEventListeners, detachEventListeners (cards.js)
 *   mids (cards.js)
 *   webUIi18n (i18n)
 *
 * Extracted from cards.js for modularity.
 */
(function() {
'use strict';

// HTML escaping delegates to the canonical window.escapeHtml (text-utils.js).
// NOTE: never re-declare a top-level `function escapeHtml` here — in classic
// scripts that declaration IS window.escapeHtml, so a delegating wrapper
// overwrites the canonical implementation with itself and recurses infinitely.

// Count distinct providers that have an API key configured, from the SSOT
// payload (/api/ai_user_defaults, cached on window.aiUserDefaults). Used to
// decide whether cross-provider verification is possible. Returns a large
// number when the payload isn't loaded yet, so we never wrongly discourage
// verification before startup data arrives.
function countConfiguredProviders() {
  var defs = (typeof window !== 'undefined') ? window.aiUserDefaults : null;
  if (!defs || typeof defs !== 'object') return Infinity;
  var n = 0;
  Object.keys(defs).forEach(function(k) {
    var ent = defs[k];
    if (ent && ent.has_key) n++;
  });
  return n;
}

/**
 * Create an HTML card element for a chat message.
 * @param {string} role - Message role (user, assistant, system, info)
 * @param {string} badge - HTML for role icon/label
 * @param {string} html - Message content HTML
 * @param {string} [_lang="en"] - Language code
 * @param {string} [mid=""] - Message ID
 * @param {boolean} [status=true] - Active/inactive in context
 * @param {Array} [images=[]] - Image objects with data, title, masks
 * @param {boolean} [_monadic=false] - Monadic app flag
 * @param {number|null} [turnNumber=null] - Conversation turn number
 * @returns {HTMLElement} Card DOM element
 */
function createCard(role, badge, html, _lang, mid, status, images, _monadic, turnNumber) {
  if (_lang === undefined) _lang = "en";
  if (mid === undefined) mid = "";
  if (status === undefined) status = true;
  if (images === undefined) images = [];
  if (_monadic === undefined) _monadic = false;
  if (turnNumber === undefined) turnNumber = null;

  var status_class = status === true ? "active" : "";
  var statusTooltip = status === true
    ? getTranslation('ui.messages.messageActive', 'Active (within context)')
    : getTranslation('ui.messages.messageInactive', 'Inactive (outside context)');

  // Ensure html is a string
  if (html === undefined || html === null) {
    html = '';
  }

  var replaced_html;
  if (role === "system") {
    if (html.indexOf('<') === -1 && html.indexOf('>') === -1) {
      replaced_html = window.escapeHtml(html).replace(/\n/g, "<br>");
    } else {
      // System messages containing markup pass through raw by design
      // (app-generated error/info cards). Not model-controlled, so the
      // DOMPurify step below is skipped for this role.
      replaced_html = html;
    }
  } else {
    // Central sanitization point for model-controlled HTML (DOMPurify).
    // Fails closed (full escaping) when DOMPurify is unavailable.
    replaced_html = window.sanitizeModelHtml(html);
  }

  // Cache-bust images
  replaced_html = replaced_html.replace(/<img src="([^"]+)"/g, '<img src="$1?dummy=' + Date.now() + '"');

  // Ensure all links open in new tab
  replaced_html = replaced_html.replace(/<a\s([^>]*?)>/gi, function(fullMatch, attrs) {
    if (/target\s*=/i.test(attrs)) return fullMatch;
    return '<a ' + attrs + ' target="_blank" rel="noopener noreferrer">';
  });

  var className, roleIcon;
  if (role === "user") {
    className = "role-user";
    roleIcon = "fa-face-smile";
  } else if (role === "assistant") {
    className = "role-assistant";
    roleIcon = "fa-robot";
  } else if (role === "info") {
    className = "role-info";
    roleIcon = "fa-info-circle";
  } else {
    className = "role-system";
    roleIcon = "fa-bars";
  }

  var image_data = "";
  if (images && images.length > 0) {
    var imageMap = new Map();
    var maskImages = [];

    images.forEach(function(image) {
      if (image.is_mask || (image.title && image.title.startsWith("mask__"))) {
        maskImages.push(image);
      } else {
        imageMap.set(image.title, image);
      }
    });

    var renderedImages = [];

    imageMap.forEach(function(image, title) {
      var maskImage = maskImages.find(function(mask) {
        return mask.mask_for === title ||
          (mask.title && mask.title.includes(title.replace(/\.[^.]+$/, "")));
      });

      if (maskImage) {
        renderedImages.push(
          '<div class="mask-overlay-container mb-3">' +
          '<img class="base-image" alt="' + window.escapeHtml(image.title) + '" src="' + image.data + '" />' +
          '<img class="mask-overlay" alt="' + window.escapeHtml(maskImage.title) + '" src="' + (maskImage.display_data || maskImage.data) + '" style="opacity: 0.6;" />' +
          '<div class="mask-overlay-label">MASK</div>' +
          '</div>'
        );
      } else if (image.type === 'application/pdf') {
        renderedImages.push(
          '<div class="pdf-preview mb-3">' +
          '<i class="fas fa-file-pdf text-danger"></i>' +
          '<span class="ms-2">' + window.escapeHtml(image.title) + '</span>' +
          '</div>'
        );
      } else {
        renderedImages.push(
          '<img class="base64-image mb-3" src="' + image.data + '" alt="' + window.escapeHtml(image.title) + '" style="max-width: 100%; height: auto;" />'
        );
      }
    });

    maskImages.forEach(function(mask) {
      if (!renderedImages.some(function(html) { return html.includes('alt="' + window.escapeHtml(mask.title) + '"'); })) {
        if (!imageMap.has(mask.mask_for)) {
          renderedImages.push(
            '<img class="base64-image mb-3" src="' + (mask.display_data || mask.data) + '" alt="' + window.escapeHtml(mask.title) + '" style="max-width: 100%; height: auto;" />'
          );
        }
      }
    });

    image_data = renderedImages.join("");
  }

  // Update badge with colored icon
  var enhancedBadge = badge.replace(/class=['"]text-secondary['"]/g, 'class="card-role-icon"');
  var enhancedBadge2 = enhancedBadge.replace(/<i class=['"]fas (fa-face-smile|fa-robot|fa-bars)['"]><\/i>/g,
    '<i class="fas ' + roleIcon + '"></i>');

  // Turn number badge
  var turnLabelText = typeof webUIi18n !== "undefined"
    ? webUIi18n.t("ui.messages.contextTurnLabel")
    : "Turn";
  var turnBadge = '';
  if ((role === "assistant" || role === "user") && turnNumber !== null && turnNumber > 0) {
    var badgeClass = role === "user" ? "card-turn-badge card-turn-badge-user" : "card-turn-badge";
    turnBadge = '<span class="' + badgeClass + '" data-turn="' + turnNumber + '" title="' + turnLabelText + ' ' + turnNumber + '">T' + turnNumber + '</span>';
  }

  // Build card HTML
  // Verify (confidence-via-agreement) applies only to AI answers; it lives below
  // the response (not in the header cluster) as a labeled action.
  var verifyLabel = getTranslation('ui.verify.action', 'Verify this response');
  // Tooltip explains what verify does; when fewer than two providers have API
  // keys, a real cross-provider check isn't possible, so say so up front (the
  // button still works — it degrades to a labeled weak self-consistency check).
  var configuredProviderCount = countConfiguredProviders();
  var verifyTip = (configuredProviderCount >= 2)
    ? getTranslation('ui.verify.tip', 'Cross-checks this answer against your other configured providers.')
    : getTranslation('ui.verify.tipSingle', "Add a second provider's API key for a cross-provider check (with one provider it is a weaker self-consistency check).");
  var verifyTitle = window.escapeHtml(verifyLabel + ' — ' + verifyTip);
  // Live Conversation cards carry no verify bar: second-opinion verification
  // targets the typed pipeline's request shape, and a realtime speech
  // transcript is not a verifiable answer. Decided at render time (not CSS)
  // so it holds regardless of stylesheet state.
  var inLiveConversation = document.body.classList.contains('lc-app');
  var verifyBar = (role === "assistant" && !inLiveConversation)
    ? '<div class="verify-bar"><span class="func-verify" title="' + verifyTitle + '">' +
      '<i class="fas fa-check-double"></i> ' + verifyLabel + '</span></div>'
    : '';
  var headerButtons;
  if (!runningOnChrome && !runningOnEdge && !runningOnSafari) {
    headerButtons =
      '<div class="me-1 text-secondary d-flex align-items-center">' +
      '<span title="Copy" class="func-copy me-3"><i class="fas fa-copy"></i></span>' +
      '<span title="Delete" class="func-delete me-3"><i class="fas fa-xmark"></i></span>' +
      '<span title="Edit" class="func-edit me-3"><i class="fas fa-pen-to-square"></i></span>' +
      turnBadge +
      '<span title="' + statusTooltip + '" class="status ' + status_class + '"></span>' +
      '</div>';
  } else {
    headerButtons =
      '<div class="me-1 text-secondary d-flex align-items-center">' +
      '<span title="Copy" class="func-copy me-3"><i class="fas fa-copy"></i></span>' +
      '<span title="Start TTS" class="func-play me-3"><i class="fas fa-play"></i></span>' +
      '<span title="Stop TTS" class="func-stop me-3"><i class="fas fa-stop"></i></span>' +
      '<span title="Delete" class="func-delete me-3"><i class="fas fa-xmark"></i></span>' +
      '<span title="Edit" class="func-edit me-3"><i class="fas fa-pen-to-square"></i></span>' +
      turnBadge +
      '<span title="' + statusTooltip + '" class="status ' + status_class + '"></span>' +
      '</div>';
  }

  var wrapper = document.createElement('div');
  wrapper.innerHTML =
    '<div class="card mt-3" id="' + mid + '"' + (turnNumber ? ' data-turn="' + turnNumber + '"' : '') + '>' +
    '<div class="card-header p-2 ps-3 d-flex justify-content-between align-items-center">' +
    '<div class="fs-5 card-title mb-0">' + enhancedBadge2 + '</div>' +
    headerButtons +
    '</div>' +
    '<div class="card-body ' + className + '">' +
    '<div class="card-text">' + replaced_html + image_data + '</div>' +
    verifyBar +
    '</div>' +
    '</div>';
  var card = wrapper.firstChild;

  // Remove existing duplicate card
  if (mid !== "") {
    var existingCard = $id(mid);
    if (existingCard) {
      detachEventListeners(existingCard);
      existingCard.remove();
    }
  }

  // Attach event listeners
  attachEventListeners(card);

  // Initialize Bootstrap tooltips
  try {
    if (card) {
      card.querySelectorAll('[title]').forEach(function(el) {
        new bootstrap.Tooltip(el, {
          trigger: 'hover',
          delay: { show: 500, hide: 0 },
          container: 'body',
          html: false
        });
      });
    }
  } catch (e) {
    console.warn('Tooltip initialization error:', e);
  }

  // Track message ID
  if (mid !== "") {
    mids.add(mid);
  }

  return card;
}

/**
 * Build the role label shown at the top of an assistant card.
 *
 * This exists because the same markup was previously inlined at three call
 * sites (the live WebSocket path, its fallback, and session restore). When
 * the "interrupted" marker was added it landed in one of them, so the flag
 * rendered in tests and never in the product.
 *
 * @param {Object} [content] - the message content hash from the server
 * @returns {string} badge markup
 */
function assistantBadge(content) {
  let badge = "<span class='text-secondary'><i class='fas fa-robot'></i></span> " +
              "<span class='fw-bold fs-6 assistant-color'>Assistant</span>";

  // A speech-to-speech turn cut short by barge-in carries only the text the
  // model produced before it was stopped. Saying so on the card matters: the
  // text reads as a complete answer otherwise, and the user cannot tell that
  // the rest was never spoken.
  if (content && content.interrupted) {
    const label = (typeof webUIi18n !== 'undefined')
      ? webUIi18n.t('ui.messages.responseInterrupted')
      : 'Interrupted';
    // mc-badge (the app's muted badge vocabulary — soft grey fill, quiet
    // text, dark-mode aware) instead of Bootstrap's solid bg-secondary,
    // which read too loud next to the card header.
    badge += " <span class='mc-badge mc-badge--grey ms-1 align-middle'>" +
             "<i class='fas fa-hand'></i> " + window.escapeHtml(label) + "</span>";
  }

  // Tools used in a speech-to-speech turn (function calling wave 1): the
  // server attaches them to the card as tools_used metadata. Entries WITH a
  // paragraph position (`at`) render as INLINE badges at that boundary
  // (insertInlineToolBadge, §37-3) — the header stays clean. Only entries
  // WITHOUT a position (older canon, non-folded cards) fall back to this
  // header badge, so no tool is ever invisible and none is shown twice
  // (§37-4: the two render paths are exclusive per entry).
  if (content && Array.isArray(content.tools_used) && content.tools_used.length > 0) {
    const unpositioned = content.tools_used.filter((t) => !t || typeof t.at !== 'number');
    if (unpositioned.length > 0) {
      const names = [...new Set(unpositioned.map((t) => t.name))];
      const hasError = unpositioned.some((t) => t.status === 'error');
      const cls = hasError ? 'mc-badge--red' : 'mc-badge--grey';
      badge += " <span class='mc-badge " + cls + " ms-1 align-middle'>" +
               "<i class='fas fa-tools'></i> " + window.escapeHtml(names.join(', ')) + "</span>";
    }
  }
  return badge;
}

/**
 * Insert a tool badge at a paragraph boundary inside a card body (§37-3).
 *
 * Live Conversation folds a tool-bridged exchange into ONE card whose
 * paragraphs are joined by "\n\n"; each tools_used entry then carries
 * `at` = the paragraph index where the tool call happened (= the bridge
 * part's paragraph count). The badge is display-only: the canonical
 * message text stays plain, and entries without `at` (older data, or the
 * initial non-folded card) are skipped — the header badge covers those.
 *
 * Accepts either a CARD element (badges go into its .card-text) or a live
 * view TEXT container (.lc-live-text, §37-5) directly.
 *
 * @param {HTMLElement} cardEl - the card element or .lc-live-text container
 * @param {Array} toolsUsed - tools_used entries ({name, status, at?})
 */
function insertInlineToolBadge(cardEl, toolsUsed) {
  if (!cardEl || !Array.isArray(toolsUsed) || toolsUsed.length === 0) return;
  const isTextContainer = cardEl.classList && cardEl.classList.contains('lc-live-text');
  const body = isTextContainer ? cardEl : cardEl.querySelector('.card-text');
  if (!body) return;
  // §40: consecutive calls at the SAME boundary merge into ONE badge —
  // a batch (one response emitting several calls) otherwise stacked one
  // badge per call, which read as noise (dogfood: search_web twice).
  // Merging is a render concern only: the underlying entries stay separate
  // so call_id status correlation keeps working.
  const groups = new Map(); // at → [tool, ...] in arrival order
  toolsUsed.forEach(function(tool) {
    if (!tool || typeof tool.at !== 'number') return;
    if (!groups.has(tool.at)) groups.set(tool.at, []);
    groups.get(tool.at).push(tool);
  });
  groups.forEach(function(tools, at) {
    const names = [...new Set(tools.map(function(t) { return t.name; }))];
    // Worst status wins: any error turns the badge red; any still-running
    // call keeps the spinner going.
    const anyError = tools.some(function(t) { return t.status === 'error'; });
    const anyRunning = tools.some(function(t) { return t.status === 'running'; });
    const span = document.createElement('span');
    // No ms-1/align-middle here: those belong to a badge sitting NEXT TO a
    // card title. Between paragraphs the badge is its own block, where a
    // left offset reads as a stray indent and vertical-align does nothing —
    // spacing comes from the .lc-tools-badge rule in monadic.css instead.
    span.className = 'mc-badge ' + (anyError ? 'mc-badge--red' : 'mc-badge--grey') +
      ' lc-tools-badge';
    // §37-12: a call still running shows the app's canonical busy glyph
    // (fa-spinner + fa-spin, as used for Saving/Importing/Loading; the
    // reduce-motion carve-out lives in monadic.css). Once it finishes the
    // icon becomes the tool glyph — a spinning wrench read as decoration
    // rather than progress, so the glyph itself carries the state.
    const icon = anyRunning ? 'fa-spinner fa-spin' : 'fa-tools';
    span.innerHTML = "<i class='fas " + icon + "'></i> ";
    span.appendChild(document.createTextNode(names.join(', ')));
    const paras = body.querySelectorAll(':scope > p');
    const target = paras[at];
    if (target) {
      body.insertBefore(span, target);
    } else {
      // Paragraph structure differs from the canon split (e.g. Markdown
      // extras) — fall back to the end rather than dropping the badge.
      body.appendChild(span);
    }
  });
}

// Export for browser environment.
// NOTE: window.escapeHtml is owned by text-utils.js (loaded earlier); this
// module only delegates to it and must not re-export its local delegate
// onto window (that would shadow the canonical implementation).
window.createCard = createCard;
window.assistantBadge = assistantBadge;
window.insertInlineToolBadge = insertInlineToolBadge;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { escapeHtml, createCard, assistantBadge, insertInlineToolBadge };
}
})();
