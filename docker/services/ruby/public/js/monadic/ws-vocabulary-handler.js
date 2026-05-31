// Vocabulary token decoration layer.
//
// The backend ships a `vocabulary_map` ({ "SHARED": "/resolved/path", ... })
// with the assistant message. This walker decorates each `${TOKEN}` occurrence
// in the rendered discourse so the user sees what the shared symbol points to
// (hover) and can open it in the OS file explorer (click). Unlike the privacy
// unmask walker it deliberately decorates inside inline <code> too, because the
// LLM tends to wrap paths in backticks — doing it post-render (on the DOM)
// sidesteps the backtick-escape that suppresses backend decoration.
//
// Click: in the Electron app, `window.electronAPI.revealPath` opens the path in
// Finder/Explorer/file-manager (cross-platform via the main-process `shell`).
// In a plain browser there is no Electron bridge, so we fall back to copying the
// resolved path to the clipboard.
(function () {
  "use strict";

  // ${TOKEN} where TOKEN is single-word UPPER_CASE (matches the backend).
  var TOKEN_RE = /\$\{([A-Z][A-Z_]*)\}/;
  var TOKEN_RE_G = /\$\{([A-Z][A-Z_]*)\}/g;

  // Text inside these is left alone: block code (<pre>), scripts/styles, and
  // anything already decorated. Inline <code> is intentionally NOT skipped.
  function isInsideSkippedAncestor(node, root) {
    var p = node.parentNode;
    while (p && p !== root) {
      if (p.classList && p.classList.contains("vocab-token")) return true;
      var tag = p.nodeName;
      if (tag === "PRE" || tag === "SCRIPT" || tag === "STYLE") return true;
      p = p.parentNode;
    }
    return false;
  }

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

  // Replace every `${TOKEN}` in a text node (where map[TOKEN] exists) with a
  // decorated span, splitting the node around each match.
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
      var resolved = map[name];
      if (resolved === undefined || resolved === null) continue; // unowned token: leave literal
      matched = true;
      if (m.index > pos) {
        fragment.appendChild(doc.createTextNode(text.substring(pos, m.index)));
      }
      fragment.appendChild(makeTokenSpan(doc, name, String(resolved)));
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
