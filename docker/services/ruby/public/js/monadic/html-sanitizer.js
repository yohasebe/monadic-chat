/**
 * HTML Sanitizer for Monadic Chat
 *
 * Central DOMPurify wrapper for model-controlled HTML before it reaches
 * innerHTML sinks (createCard, server-rendered edit HTML, renderAndApply,
 * Verify panel). The allowlist is driven by the intentional HTML the app
 * itself emits — see tmp/memo/xss_display_compat_audit.md:
 *
 *   - div.generated_image > img (image generation tools)
 *   - div.generated_video > video[controls] > source[src,type] (video tools)
 *   - KaTeX MathML/SVG output (default html+svg+mathMl profile; needs
 *     annotation[encoding], span style/class/aria-hidden — all default-allowed)
 *   - mc: scheme citation links with data-mc-link (ALLOWED_URI_REGEXP)
 *   - div.{mermaid,abc,drawio}-code > pre wrappers
 *   - Monadic JSON tree (div.json-item[data-depth][data-key], inline style)
 *   - highlight.js code classes, base64 image attachments
 *
 * Inline event handlers (onclick etc.) are stripped by DOMPurify by design;
 * interactive elements rely on delegated listeners instead.
 *
 * Fail-closed fallback: if DOMPurify failed to load (vendor file missing,
 * CDN blocked), sanitizeModelHtml escapes the entire input rather than
 * passing unsanitized HTML through, and logs an error. Display degrades to
 * escaped text instead of exposing an XSS sink.
 */
(function() {
'use strict';

// DOMPurify default profile (html + svg + mathMl) is kept as the base —
// KaTeX output depends on MathML/SVG tags surviving.
var PURIFY_CONFIG = {
  // video/source/audio are in DOMPurify 3.x defaults; listed explicitly so
  // the generated-video block does not depend on default-set drift.
  // semantics/annotation (KaTeX MathML source annotation) were dropped from
  // DOMPurify 3.x default MathML tags (mXSS hardening around annotation-xml)
  // and must be re-added — KaTeX renderToString output loses its
  // <annotation encoding="application/x-tex"> source otherwise. The mXSS
  // vector is annotation-xml (namespace confusion), NOT annotation, so
  // allowing it here does not reopen that hole.
  ADD_TAGS: ['video', 'source', 'audio', 'semantics', 'annotation'],
  ADD_ATTR: [
    'controls', 'width', 'type', // video/source
    'data-mc-link',              // mc: citation links (data-* is default-allowed; explicit for clarity)
    'data-depth', 'data-key',    // Monadic JSON tree
    'encoding',                  // KaTeX <annotation encoding="application/x-tex">
    'target', 'rel'              // link_open renderer / createCard link rewriting
  ],
  // Default URI regexp extended with the in-app mc: scheme and data:image/*
  // (base64 attachments, generated images). Relative /data/... paths already
  // match the final "no scheme" alternative of the default pattern.
  // NOTE: the dashes inside the character classes MUST stay escaped (\-).
  // Written as [a-z+.-:] the ".-:" parses as a character RANGE (. – :)
  // that includes '/', which silently rejects values like "video/mp4"
  // (DOMPurify then strips type="video/mp4" from <source>).
  ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto|tel|mc):|(?:data:image\/(?:png|jpe?g|gif|webp|svg\+xml);)|(?:[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$)))/i,
  FORBID_TAGS: ['script', 'style', 'iframe', 'object', 'embed', 'form', 'input', 'textarea', 'select', 'button', 'meta', 'link', 'base'],
  FORBID_ATTR: ['srcset']
  // NOTE: never FORBID the style attribute — generated_image, KaTeX spans,
  // and the Monadic JSON tree all rely on inline styles.
};

// Detect DOMPurify once per call rather than caching at load time, so a
// lazily-injected DOMPurify (tests, late vendor load) is picked up.
function getPurify() {
  if (typeof window !== 'undefined' && window.DOMPurify &&
      typeof window.DOMPurify.sanitize === 'function') {
    return window.DOMPurify;
  }
  return null;
}

/**
 * Sanitize model-controlled HTML against the app allowlist.
 * @param {string} html - Untrusted HTML string
 * @returns {string} Sanitized HTML (or fully-escaped text when DOMPurify
 *   is unavailable — fail closed, never pass-through)
 */
function sanitizeModelHtml(html) {
  if (html === null || html === undefined) {
    return '';
  }
  var purify = getPurify();
  if (!purify) {
    console.error('[html-sanitizer] DOMPurify is not loaded; falling back to full escaping (display will degrade). Load vendor/js/purify.min.js before the app bundle.');
    return window.escapeHtml(String(html));
  }
  return purify.sanitize(String(html), PURIFY_CONFIG);
}

// Export for browser environment
window.sanitizeModelHtml = sanitizeModelHtml;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { sanitizeModelHtml, PURIFY_CONFIG };
}
})();
