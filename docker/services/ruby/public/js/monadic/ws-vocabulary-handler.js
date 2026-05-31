// Vocabulary token transformation layer.
//
// The backend ships a `vocabulary_map` with the assistant message, mapping each
// owned `${TOKEN}` to a { value, display } object, e.g.
//   { "SHARED": { value: "/resolved/path", display: "decorate" },
//     "TODAY":  { value: "2026-05-31",     display: "expand" } }
// This walker transforms each `${TOKEN}` occurrence in the rendered discourse
// by per-token display mode (decision E):
//   * decorate — keep the literal ${TOKEN} symbol visible, wrapped in a
//                .vocab-token span with a hover tooltip + click-to-reveal
//                (path-like values, e.g. ${SHARED}).
//   * expand   — replace the token with its resolved VALUE, wrapped in a
//                .vocab-value span whose title is the source token for
//                traceability (value-like tokens, e.g. ${TODAY}).
// A plain-string map value (legacy shape) is treated as decorate.
//
// Unlike the privacy unmask walker it deliberately works inside inline <code>
// too, because the LLM tends to wrap paths in backticks — doing it post-render
// (on the DOM) sidesteps the backtick-escape that suppresses backend output.
//
// Click (decorate spans only): in the Electron app,
// `window.electronAPI.revealPath` opens the path in Finder/Explorer/file-manager
// (cross-platform via the main-process `shell`). In a plain browser there is no
// Electron bridge, so we fall back to copying the resolved path to the
// clipboard. Expand (.vocab-value) spans are plain text and not clickable.
(function () {
  "use strict";

  // ${TOKEN} where TOKEN is single-word UPPER_CASE (matches the backend).
  var TOKEN_RE = /\$\{([A-Z][A-Z_]*)\}/;
  var TOKEN_RE_G = /\$\{([A-Z][A-Z_]*)\}/g;

  // Text inside these is left alone: block code (<pre>), scripts/styles, and
  // anything already transformed (a .vocab-token decorate span or a .vocab-value
  // expand span). Inline <code> is intentionally NOT skipped.
  function isInsideSkippedAncestor(node, root) {
    var p = node.parentNode;
    while (p && p !== root) {
      if (p.classList &&
          (p.classList.contains("vocab-token") ||
           p.classList.contains("vocab-value"))) return true;
      var tag = p.nodeName;
      if (tag === "PRE" || tag === "SCRIPT" || tag === "STYLE") return true;
      p = p.parentNode;
    }
    return false;
  }

  // decorate: keep the literal symbol, hover tooltip + click-to-reveal.
  function makeTokenSpan(doc, name, resolved) {
    var span = doc.createElement("span");
    span.className = "vocab-token";
    span.setAttribute("role", "button");
    span.setAttribute("tabindex", "0");
    span.setAttribute("data-vocab-path", resolved);
    // setAttribute escapes the value, so no manual HTML-escaping needed.
    span.setAttribute("title", resolved + " — click to open in file explorer");
    span.textContent = "${" + name + "}";
    return span;
  }

  // expand: replace the token with its resolved value; title carries the source
  // token for traceability. Not clickable.
  function makeValueSpan(doc, name, value) {
    var span = doc.createElement("span");
    span.className = "vocab-value";
    // setAttribute escapes the value; textContent never injects markup.
    span.setAttribute("title", "${" + name + "}");
    span.textContent = value;
    return span;
  }

  // Replace every owned `${TOKEN}` in a text node with the appropriate span
  // (decorate symbol or expand value), splitting the node around each match.
  function splitAndWrap(textNode, map) {
    var text = textNode.nodeValue;
    if (!text || text.indexOf("${") === -1) return;
    var doc = textNode.ownerDocument || document;
    var parent = textNode.parentNode;
    if (!parent) return;

    var fragment = doc.createDocumentFragment();
    var pos = 0;
    var matched = false;
    var m;
    TOKEN_RE_G.lastIndex = 0;
    while ((m = TOKEN_RE_G.exec(text)) !== null) {
      var name = m[1];
      var entry = map[name];
      if (entry === undefined || entry === null) continue; // unowned token: leave literal
      // Tolerate a legacy plain-string value (treated as decorate).
      var value = (typeof entry === "object") ? entry.value : entry;
      var mode = (typeof entry === "object") ? entry.display : "decorate";
      if (value === undefined || value === null) continue; // no resolved value: leave literal
      matched = true;
      if (m.index > pos) {
        fragment.appendChild(doc.createTextNode(text.substring(pos, m.index)));
      }
      if (mode === "expand") {
        fragment.appendChild(makeValueSpan(doc, name, String(value)));
      } else {
        fragment.appendChild(makeTokenSpan(doc, name, String(value)));
      }
      pos = m.index + m[0].length;
    }
    if (!matched) return;
    if (pos < text.length) {
      fragment.appendChild(doc.createTextNode(text.substring(pos)));
    }
    parent.replaceChild(fragment, textNode);
  }

  function decorateTokens(root, map) {
    if (!root || !map) return;
    var names = Object.keys(map);
    if (names.length === 0) return;

    var doc = root.ownerDocument || document;
    var walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node.nodeValue || !TOKEN_RE.test(node.nodeValue)) {
          return NodeFilter.FILTER_REJECT;
        }
        if (isInsideSkippedAncestor(node, root)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });

    // Collect first; mutating during iteration invalidates the walker.
    var nodes = [];
    var n;
    while ((n = walker.nextNode())) nodes.push(n);
    nodes.forEach(function (textNode) {
      splitAndWrap(textNode, map);
    });

    ensureClickHandler();
  }

  // Single delegated click/keyboard handler for all decorated tokens.
  var clickHandlerInstalled = false;
  function ensureClickHandler() {
    if (clickHandlerInstalled) return;
    clickHandlerInstalled = true;
    document.addEventListener("click", function (ev) {
      var el = ev.target && ev.target.closest && ev.target.closest(".vocab-token");
      if (el) activate(el);
    });
    document.addEventListener("keydown", function (ev) {
      if (ev.key !== "Enter" && ev.key !== " ") return;
      var el = ev.target && ev.target.closest && ev.target.closest(".vocab-token");
      if (el) { ev.preventDefault(); activate(el); }
    });
  }

  function activate(el) {
    var path = el.getAttribute("data-vocab-path");
    if (!path) return;
    var api = typeof window !== "undefined" ? window.electronAPI : null;
    if (api && typeof api.revealPath === "function") {
      api.revealPath(path);
      return;
    }
    // Browser fallback: copy the resolved path.
    copyToClipboard(path);
    flash("Copied path: " + path);
  }

  function copyToClipboard(text) {
    try {
      if (window.electronAPI && typeof window.electronAPI.writeClipboard === "function") {
        window.electronAPI.writeClipboard(text);
        return;
      }
    } catch (_) { /* fall through */ }
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text);
      }
    } catch (_) { /* no-op */ }
  }

  function flash(msg) {
    try {
      if (typeof window.setAlert === "function") {
        window.setAlert("<i class='fa-solid fa-clipboard'></i> " + msg, "info");
      }
    } catch (_) { /* no-op */ }
  }

  window.WsVocabularyHandler = {
    decorateTokens: decorateTokens
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = window.WsVocabularyHandler;
  }
})();
