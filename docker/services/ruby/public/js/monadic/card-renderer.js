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

/**
 * HTML-encode unsafe strings to prevent XSS.
 * @param {string} unsafe - Input string
 * @returns {string} Escaped HTML
 */
function escapeHtml(unsafe) {
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
      replaced_html = escapeHtml(html).replace(/\n/g, "<br>");
    } else {
      replaced_html = html;
    }
  } else {
    replaced_html = html;
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
          '<img class="base-image" alt="' + image.title + '" src="' + image.data + '" />' +
          '<img class="mask-overlay" alt="' + maskImage.title + '" src="' + (maskImage.display_data || maskImage.data) + '" style="opacity: 0.6;" />' +
          '<div class="mask-overlay-label">MASK</div>' +
          '</div>'
        );
      } else if (image.type === 'application/pdf') {
        renderedImages.push(
          '<div class="pdf-preview mb-3">' +
          '<i class="fas fa-file-pdf text-danger"></i>' +
          '<span class="ms-2">' + image.title + '</span>' +
          '</div>'
        );
      } else {
        renderedImages.push(
          '<img class="base64-image mb-3" src="' + image.data + '" alt="' + image.title + '" style="max-width: 100%; height: auto;" />'
        );
      }
    });

    maskImages.forEach(function(mask) {
      if (!renderedImages.some(function(html) { return html.includes('alt="' + mask.title + '"'); })) {
        if (!imageMap.has(mask.mask_for)) {
          renderedImages.push(
            '<img class="base64-image mb-3" src="' + (mask.display_data || mask.data) + '" alt="' + mask.title + '" style="max-width: 100%; height: auto;" />'
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

// Export for browser environment
window.escapeHtml = escapeHtml;
window.createCard = createCard;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { escapeHtml, createCard };
}
})();
