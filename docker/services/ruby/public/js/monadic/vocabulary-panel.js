// "Available Variables" info-panel renderer.
//
// Renders the Substitution-Pipeline vocabulary tokens enabled for the current
// app into the right-side "Monadic Chat Info" panel. The data is 100%
// backend-driven: each app's `vocabulary_info` array (shipped on the `apps`
// WebSocket message — see lib/monadic/utils/websocket/app_data.rb, which calls
// Monadic::Substitution::Vocabulary.describe_for) is the single source of
// truth. No token names or descriptions are hardcoded here.
//
// Each entry has the shape:
//   { token: "SHARED", description: "...", display: "decorate"|"expand",
//     value: "/monadic/data" | null }
//
// A null value means "unavailable in this context" (e.g. ${MODEL} before a
// model is chosen); the token is still listed, just without a value.
//
// When the array is empty (app opted out via `vocabulary false`), the whole
// section is hidden. The list body is COLLAPSED BY DEFAULT — the heading
// toggle (mirroring the .sidebar-collapse-toggle chevron idiom) expands it.
(function () {
  "use strict";

  // Build a single row element for one vocabulary entry.
  //   ${TOKEN}   — monospace (.vocab-name), reference-only label
  //   description — muted text
  //   → value     — muted, only when present
  //
  // The label uses .vocab-name (NOT .vocab-token): panel chips are
  // documentation, not actions. The document-level delegated handler in
  // ws-vocabulary-handler.js matches .vocab-token, so a .vocab-name chip is
  // never a reveal/clipboard target. No role/tabindex/data-vocab-path is set.
  function buildRow(doc, entry) {
    if (!entry || !entry.token) return null;

    var row = doc.createElement("div");
    row.className = "vocab-row mb-2";
    // Tag the row so updateValues() can locate it later by token.
    row.setAttribute("data-vocab-token", entry.token);

    var tokenEl = doc.createElement("code");
    tokenEl.className = "vocab-name";
    // textContent never injects markup.
    tokenEl.textContent = "${" + entry.token + "}";
    row.appendChild(tokenEl);

    if (entry.description) {
      var desc = doc.createElement("div");
      desc.className = "vocab-desc small text-secondary";
      desc.textContent = entry.description;
      row.appendChild(desc);
    }

    // Always create the .vocab-resolved container so updateValues() can fill it
    // in later without rebuilding the row. When there is no value, the value
    // span is empty and the container is hidden.
    var hasValue =
      entry.value !== undefined && entry.value !== null && entry.value !== "";
    var valWrap = doc.createElement("div");
    valWrap.className = "vocab-resolved small text-secondary";
    var arrow = doc.createElement("span");
    arrow.className = "vocab-arrow";
    arrow.textContent = "→ "; // →
    var val = doc.createElement("span");
    val.className = "vocab-value";
    val.textContent = hasValue ? String(entry.value) : "";
    valWrap.appendChild(arrow);
    valWrap.appendChild(val);
    valWrap.style.display = hasValue ? "" : "none";
    row.appendChild(valWrap);

    return row;
  }

  // Collapse the list body and reset the heading's aria-expanded state (the
  // caret rotation is driven by CSS off [aria-expanded], like the sidebar
  // panels). Section visibility is owned by render() based on emptiness.
  function collapseBody(toggle, list) {
    if (list) list.style.display = "none";
    if (toggle) toggle.setAttribute("aria-expanded", "false");
  }

  // Wire the heading toggle once. Clicking the heading flips the list body and
  // aria-expanded; the CSS rotates the chevron accordingly.
  function wireToggle(toggle, list) {
    if (!toggle || toggle.dataset.vocabToggleWired === "1") return;
    toggle.dataset.vocabToggleWired = "1";
    toggle.addEventListener("click", function () {
      var collapsed = !list || list.style.display === "none";
      if (collapsed) {
        if (list) list.style.display = "";
        toggle.setAttribute("aria-expanded", "true");
      } else {
        collapseBody(toggle, list);
      }
    });
  }

  // Render the entries into the panel. `entries` is the backend array (or
  // anything falsy / non-array → treated as empty). Hides the whole section
  // when there is nothing to show. The list body is COLLAPSED BY DEFAULT and
  // re-collapsed on every (re)render (e.g. app switch).
  //
  // @param {Array} entries
  // @param {Document} [docArg] override document (for tests)
  function render(entries, docArg) {
    var doc = docArg || (typeof document !== "undefined" ? document : null);
    if (!doc) return;

    var section = doc.getElementById("available-variables");
    var list = doc.getElementById("available-variables-list");
    if (!section || !list) return;

    list.innerHTML = "";

    var rows = Array.isArray(entries) ? entries : [];
    var appended = 0;
    rows.forEach(function (entry) {
      var row = buildRow(doc, entry);
      if (row) {
        list.appendChild(row);
        appended += 1;
      }
    });

    // Empty → hide the whole section (heading + body).
    section.style.display = appended > 0 ? "" : "none";

    // Always reset to collapsed on (re)render; wire the toggle lazily.
    var toggle = doc.getElementById("available-variables-toggle");
    collapseBody(toggle, list);
    wireToggle(toggle, list);
  }

  // Convenience: render from the cached app object (window.apps[appName]).
  // Reads the backend-shipped `vocabulary_info` field; tolerant of a missing
  // app / field (renders empty → hides).
  function renderForApp(appName, docArg) {
    var apps = (typeof window !== "undefined" && window.apps) ? window.apps : {};
    var app = appName ? apps[appName] : null;
    var entries = app ? app["vocabulary_info"] : null;
    render(entries, docArg);
  }

  // Refresh the resolved values of already-rendered panel rows from a per-turn
  // `vocabulary_map` (shape: { TOKEN: { value, display } }; a legacy plain
  // string value is tolerated). Only existing (enabled) rows are touched — this
  // never creates new rows, and unknown tokens in the map are ignored.
  //
  // Collapse/visibility state is left untouched; only per-row value text and
  // the per-row .vocab-resolved visibility change.
  //
  // @param {Object} map  { TOKEN: {value, display} | "value" }
  // @param {Document} [docArg] override document (for tests)
  function updateValues(map, docArg) {
    var doc = docArg || (typeof document !== "undefined" ? document : null);
    if (!doc) return;
    if (!map || typeof map !== "object") return;

    Object.keys(map).forEach(function (token) {
      var entry = map[token];
      var value = (entry && typeof entry === "object") ? entry.value : entry;

      // token is single-word UPPER_CASE so it is selector-safe.
      var row = doc.querySelector(
        '#available-variables-list [data-vocab-token="' + token + '"]'
      );
      if (!row) return; // only update existing rows

      var valWrap = row.querySelector(".vocab-resolved");
      var val = row.querySelector(".vocab-value");
      if (!val) return;

      var hasValue = value !== undefined && value !== null && value !== "";
      val.textContent = hasValue ? String(value) : "";
      if (valWrap) valWrap.style.display = hasValue ? "" : "none";
    });
  }

  // Compute the DOM-derived value tokens (MODEL/APP/LANG) from the current UI
  // controls and push them into the panel immediately — used on app/model
  // switch so the panel reflects the new selection before the next message
  // round-trip. ${TODAY}/${SHARED} are static (set at load); ${LANG}=="auto"
  // is left to the server (it needs the UI language). updateValues only touches
  // existing rows, so tokens absent from the panel are silent no-ops.
  function liveValuesFromDom(doc) {
    var out = {};
    var modelEl = doc.getElementById("model");
    if (modelEl && modelEl.value) out.MODEL = modelEl.value;

    var appsEl = doc.getElementById("apps");
    var apps = (typeof window !== "undefined" && window.apps) ? window.apps : {};
    if (appsEl && appsEl.value && apps[appsEl.value]) {
      var dn = apps[appsEl.value]["display_name"];
      if (dn) out.APP = dn;
    }

    var langEl = doc.getElementById("conversation-language");
    if (langEl && langEl.value && langEl.value !== "auto") out.LANG = langEl.value;

    return out;
  }

  function updateLiveValues(docArg) {
    var doc = docArg || (typeof document !== "undefined" ? document : null);
    if (!doc) return;
    updateValues(liveValuesFromDom(doc), doc);
  }

  var api = {
    render: render,
    renderForApp: renderForApp,
    updateValues: updateValues,
    updateLiveValues: updateLiveValues
  };

  if (typeof window !== "undefined") {
    window.VocabularyPanel = api;
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
})();
