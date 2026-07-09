// frozen-by-convention; module-pattern, no globals beyond window.libraryPanel
//
// Library (Knowledge Base) sidebar + browse modal + detail modal.
//
// Two surfaces share the same data cache:
//   - Sidebar  (#library-recent, 5 most recent rows, compact one-line).
//   - Browse modal (#libraryBrowseModal, search/filter/sort/paginate).
// Detail modal (#libraryDetailModal) shows full metadata + actions.
//
// All actions are routed through the WebSocket. The cache is populated
// from `library_conversations` events; sidebar + browse modal both
// re-render whenever new data arrives or filters change.
//
// Public API (full surface):
//   window.libraryPanel.init()                 - DOM bootstrap
//   window.libraryPanel.send(msg, payload?)    - low-level WS send
//   window.libraryPanel.requestList()
//   window.libraryPanel.requestStats()
//   window.libraryPanel.requestRagState()
//   window.libraryPanel.openSaveModal()
//   window.libraryPanel.submitSave()
//   window.libraryPanel.openBrowseModal()
//   window.libraryPanel.openDetailModal(conversationId)
//   window.libraryPanel.setRagToggle(enabled)
//   window.libraryPanel.handleConversations(data)
//   window.libraryPanel.handleStats(data)
//   window.libraryPanel.handleSavedMessage(data)
//   window.libraryPanel.handleDeletedMessage(data)
//   window.libraryPanel.handleRagState(data)
//   window.libraryPanel.handleVisibilityUpdated(data)
//   window.libraryPanel.formatStats(stats)
//   window.libraryPanel.relativeTime(iso)
//   window.libraryPanel.compactRowMarkup(row)
//   window.libraryPanel.applyFilters()
(function () {
  'use strict';

  // ─── Module state ────────────────────────────────────────────────────

  var state = {
    allRows: [],            // last received full inventory
    filteredRows: [],       // after applying search/scope filter
    page: 0,                // 0-indexed page in browse modal
    pageSize: 50,
    sortKey: 'created_desc',
    scopeFilter: 'all',     // 'all' | 'Global' | a literal app class name
    searchTerm: '',
    selectedId: null,       // for detail modal
    viewerOpenedFromBrowse: false, // re-open Browse after Viewer closes
    // The conversation_id assigned by the server on the most recent
    // Save of the *current* chat session. While this is set, subsequent
    // Saves replace the same KB entry instead of creating a new one.
    // Cleared by clearCurrentConversation() on Reset, app switch, or
    // when the matching entry is deleted from Browse.
    currentConversationId: null,
    // Set while a LIBRARY_SUGGEST_TITLE request is in flight. We use
    // it to (a) prevent duplicate requests when the user closes and
    // re-opens the modal quickly, and (b) ignore stale responses if
    // the user has started typing a title in the meantime.
    titleSuggestionPending: false,
    // Cached suggestion + the message count at the moment we received
    // it. If the user opens Save, gets a suggestion, cancels, then
    // re-opens Save without sending any new chat turns, we reuse the
    // cached value rather than burning another LLM call. The cache is
    // invalidated when the conversation grows (new messages) or when
    // clearCurrentConversation() fires (Reset / app switch).
    cachedTitleSuggestion: null,
    cachedTitleSuggestionMessageCount: 0
  };

  var SIDEBAR_RECENT_LIMIT = 5;

  // ─── Sending ─────────────────────────────────────────────────────────

  function send(message, payload, opts) {
    // All LIBRARY_* messages route through the central safeWsSend
    // wrapper so we inherit the null/CONNECTING/CLOSED handling, the
    // reconnect-and-replay queue, and the idempotency classification.
    // Most LIBRARY_* messages are idempotent and are listed in the
    // wrapper's default set; non-idempotent ones (e.g. SUGGEST_TITLE)
    // pass `silentDrop: true` at the call site so a transient WS
    // outage does not surface a fail-fast alert for a background
    // request the user did not explicitly trigger.
    if (typeof window.safeWsSend !== 'function') return false;
    var body = Object.assign({ message: message }, payload || {});
    var result = window.safeWsSend(body, opts || {});
    return !!(result && (result.sent || result.queued));
  }

  function requestList() { return send('LIBRARY_LIST'); }
  function requestStats() { return send('LIBRARY_STATS'); }
  function requestRagState() { return send('LIBRARY_RAG_QUERY'); }
  function setRagToggle(enabled) {
    return send('LIBRARY_RAG_TOGGLE', { contents: { enabled: !!enabled } });
  }
  function requestTitleSuggestion() {
    var msgs = (Array.isArray(window.messages) ? window.messages : []).map(function (m) {
      return { role: m.role, text: m.text };
    });
    // SUGGEST_TITLE is non-idempotent (LLM call) AND background
    // (auto-fired when the Save modal opens, not user-clicked).
    // silentDrop avoids alerting the user about a "nice to have"
    // pre-fill if the WS happens to be reconnecting.
    return send('LIBRARY_SUGGEST_TITLE', { contents: { messages: msgs } }, { silentDrop: true });
  }

  // Persist the user's preferred default for the RAG toggle across
  // sessions/page loads. The server still owns the per-session state
  // (and the first-message lock), but this lets users avoid flipping
  // the toggle every time they open a new session. Stored as 'on' or
  // 'off' so unset/legacy values fall through to the server default.
  var RAG_DEFAULT_KEY = 'monadic.library.ragDefault';
  function readRagDefault() {
    try {
      if (typeof window === 'undefined' || !window.localStorage) return null;
      return window.localStorage.getItem(RAG_DEFAULT_KEY);
    } catch (e) { return null; }
  }
  function writeRagDefault(enabled) {
    try {
      if (typeof window === 'undefined' || !window.localStorage) return;
      window.localStorage.setItem(RAG_DEFAULT_KEY, enabled ? 'on' : 'off');
    } catch (e) { /* private mode / quota — silently ignore */ }
  }
  function setScopeApp(conversationId, scopeApp) {
    return send('LIBRARY_SET_SCOPE', {
      contents: { conversation_id: conversationId, scope_app: scopeApp }
    });
  }
  function deleteConversation(conversationId) {
    return send('LIBRARY_DELETE', { contents: conversationId });
  }

  // ─── i18n helper ─────────────────────────────────────────────────────

  function t(key, fallback) {
    try {
      if (typeof window.webUIi18n === 'object' && typeof window.webUIi18n.t === 'function') {
        var v = window.webUIi18n.t(key);
        if (v && v !== key) return v;
      }
    } catch (_) {}
    return fallback;
  }

  // ─── DOM helpers ─────────────────────────────────────────────────────

  function escapeHtml(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // Provider class-suffixes used to split app class names back into a
  // pretty "Base (Provider)" pair. Order is irrelevant since the suffix
  // set is disjoint.
  var SCOPE_PROVIDERS = ['OpenAI', 'Claude', 'Gemini', 'Grok', 'Cohere',
                          'Mistral', 'DeepSeek', 'Ollama'];

  // Convert a scope_app payload value into the human-friendly label used
  // by every UI surface. "Global" stays as-is. "ChatOpenAI" splits into
  // "Chat (OpenAI)". "JupyterNotebookGrok" splits into
  // "Jupyter Notebook (Grok)". Unknown shapes pass through verbatim.
  function formatScopeApp(scopeApp) {
    if (!scopeApp) return 'Global';
    if (scopeApp === 'Global') return 'Global';
    for (var i = 0; i < SCOPE_PROVIDERS.length; i++) {
      var p = SCOPE_PROVIDERS[i];
      if (scopeApp.length > p.length &&
          scopeApp.slice(scopeApp.length - p.length) === p) {
        var base = scopeApp.slice(0, scopeApp.length - p.length);
        var pretty = base.replace(/([a-z0-9])([A-Z])/g, '$1 $2');
        return pretty + ' (' + p + ')';
      }
    }
    return scopeApp;
  }

  function scopeBadge(scopeApp) {
    var label = formatScopeApp(scopeApp);
    // "Global" stays the soft-green pill (cross-app reach is the
    // expansive case); per-app scopes use the muted secondary pill.
    var cls = label === 'Global'
      ? 'mc-badge mc-badge--green'
      : 'mc-badge mc-badge--grey';
    return '<span class="' + cls + '">' + escapeHtml(label) + '</span>';
  }

  // Compute "what scope should clicking the toggle button switch to"
  // based on the row's current scope_app and the active app from
  // window.params. Updates the data-next-scope attribute and the visible
  // label so the user sees the action that will happen, not the
  // current state.
  function applyScopeToggleState(row, toggleBtn, toggleLabel) {
    if (!toggleBtn) return;
    var current = row.scope_app || 'Global';
    var nextScope, label;
    if (current === 'Global') {
      var currentApp = (typeof window.params === 'object' && window.params && window.params.app_name) || '';
      nextScope = currentApp;
      label = currentApp
        ? t('ui.libMakeAppOnly', 'Make app-only ({app})').replace('{app}', formatScopeApp(currentApp))
        : t('ui.libMakeAppOnlyDisabled', 'Switch to an app to scope this entry');
    } else {
      nextScope = 'Global';
      label = t('ui.libMakeGlobal', 'Make Global');
    }
    toggleBtn.setAttribute('data-next-scope', nextScope);
    toggleBtn.disabled = (nextScope === '');
    if (toggleLabel) toggleLabel.textContent = label;
  }

  // Map a content_type token to a FontAwesome icon class plus a colour
  // tone. The Library stores "conversation" plus file-import content
  // types (markdown / code / pdf / document). The Browse modal renders a
  // single icon per row using this mapping plus a tooltip carrying the
  // readable type name. Sub-formats of "document" (docx / xlsx / pptx)
  // are detected via the `topics` array.
  //
  // Colour palette: Material Design 300/400 tones — light enough that
  // the icons read as soft type indicators rather than dominating the
  // Title column.
  var TYPE_ICONS = {
    conversation: { icon: 'fa-comments',   color: '#90A4AE' }, // blue grey 300
    pdf:          { icon: 'fa-file-pdf',   color: '#E57373' }, // red 300
    document:     { icon: 'fa-file-word',  color: '#64B5F6' }, // blue 300
    office:       { icon: 'fa-file-word',  color: '#64B5F6' },
    code:         { icon: 'fa-file-code',  color: '#BA68C8' }, // purple 300
    markdown:     { icon: 'fa-file-lines', color: '#4FC3F7' }, // light blue 300
    text:         { icon: 'fa-file-lines', color: '#4FC3F7' },
    audio:        { icon: 'fa-file-audio', color: '#AED581' }, // light green 300
    transcript:   { icon: 'fa-file-audio', color: '#AED581' },
    image:        { icon: 'fa-file-image', color: '#FFB74D' }, // orange 300
    video:        { icon: 'fa-file-video', color: '#E57373' }
  };

  // Office sub-formats stored in conversation_metadata.topics.
  var OFFICE_SUBFORMAT_ICONS = {
    docx: { icon: 'fa-file-word',       color: '#64B5F6', label: 'docx (Word)' },
    xlsx: { icon: 'fa-file-excel',      color: '#81C784', label: 'xlsx (Excel)' },       // green 300
    pptx: { icon: 'fa-file-powerpoint', color: '#FF8A65', label: 'pptx (PowerPoint)' }   // deep orange 300
  };

  function typeIconHtml(contentType, topics) {
    var t = (contentType || 'conversation').toString().toLowerCase();
    var def = TYPE_ICONS[t] || { icon: 'fa-file', color: '#6c757d' };
    var icon = def.icon;
    var color = def.color;
    var label = t;
    if (t === 'document' && Array.isArray(topics)) {
      for (var i = 0; i < topics.length; i++) {
        var sub = OFFICE_SUBFORMAT_ICONS[String(topics[i]).toLowerCase()];
        if (sub) { icon = sub.icon; color = sub.color; label = sub.label; break; }
      }
    }
    // fa-solid (filled) keeps the icon legible at small sizes; size is
    // only modestly larger than body text so it does not shout.
    return '<i class="fa-solid ' + icon + '" '
      + 'style="color: ' + color + '; font-size: 1.1rem;" '
      + 'title="' + escapeHtml(label) + '" aria-label="' + escapeHtml(label) + '"></i>';
  }

  // Compact colored dot used in sidebar rows where horizontal space is
  // tight. "Global" entries glow green, app-scoped entries get a muted
  // grey dot. The tooltip carries the formatted scope label.
  function scopeDot(scopeApp) {
    var label = formatScopeApp(scopeApp);
    var color = label === 'Global' ? '#198754' : '#6c757d';
    return '<span class="library-scope-dot d-inline-block rounded-circle me-1" '
      + 'style="width: 8px; height: 8px; background:' + color + ';" '
      + 'title="' + escapeHtml(label) + '" aria-label="' + escapeHtml(label) + '"></span>';
  }

  // Truncate to a given length with an ellipsis. Used so long titles do
  // not push the action menu offscreen on narrow sidebars.
  function truncate(text, max) {
    if (!text) return '';
    text = String(text);
    if (text.length <= max) return text;
    return text.slice(0, max - 1) + '…';
  }

  // Render a localized relative time stamp (e.g. "2h ago", "3d ago").
  // Falls back to the original ISO string if parsing fails.
  function relativeTime(iso) {
    if (!iso) return '';
    var d;
    try { d = new Date(iso); } catch (_) { return String(iso); }
    if (!d || isNaN(d.getTime())) return String(iso);
    var diffMs = Date.now() - d.getTime();
    var diffSec = Math.max(1, Math.floor(diffMs / 1000));
    if (diffSec < 60) return diffSec + 's';
    var diffMin = Math.floor(diffSec / 60);
    if (diffMin < 60) return diffMin + 'm';
    var diffH = Math.floor(diffMin / 60);
    if (diffH < 24) return diffH + 'h';
    var diffD = Math.floor(diffH / 24);
    if (diffD < 30) return diffD + 'd';
    var diffMo = Math.floor(diffD / 30);
    if (diffMo < 12) return diffMo + 'mo';
    var diffY = Math.floor(diffMo / 12);
    return diffY + 'y';
  }

  // ─── Compact row markup (used in sidebar AND browse modal table) ─────

  // Sidebar markup: 1-line. Title + scope dot + turns + relative time.
  // No inline action button — sidebar is read-only; for actions the user
  // opens Browse modal.
  function compactRowMarkup(row) {
    var title = row.title && row.title.length > 0 ? row.title : '(untitled)';
    var turns = (typeof row.turns_count === 'number') ? row.turns_count : '?';
    var rel = relativeTime(row.created_at);
    var fullId = row.conversation_id || '';
    var sourceMeta = [row.source, row.language].filter(Boolean).join(' · ');
    var tooltip = fullId + (sourceMeta ? ' · ' + sourceMeta : '');
    return (
      '<div class="library-row-compact d-flex align-items-center py-1 small border-bottom" '
        + 'data-conversation-id="' + escapeHtml(fullId) + '" '
        + 'title="' + escapeHtml(tooltip) + '">'
      +   scopeDot(row.scope_app)
      +   '<span class="flex-grow-1 text-truncate me-2">' + escapeHtml(truncate(title, 40)) + '</span>'
      +   '<span class="text-secondary text-nowrap">' + turns + 'T · ' + escapeHtml(rel) + '</span>'
      + '</div>'
    );
  }

  // Browse-modal row: full table row with three inline icon-only buttons
  // on the right (details / toggle scope / delete). Shows the scope badge
  // ("Chat (OpenAI)" / "Global" / etc.) so the user can see at a glance
  // which app the entry belongs to.
  // Cheap heuristics for "this row likely contains PII" — used for legacy
  // entries that were saved before pii_status was tracked at save time.
  // Both regexes are deliberately permissive: a false positive (warning
  // shown for an entry that does not actually carry PII) costs the user
  // a glance, while a false negative (no warning for an entry that does)
  // would defeat the point of the badge. Restricted to title + source so
  // the cost stays O(rows) per render.
  var PII_EMAIL_RE = /[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}/;
  var PII_PHONE_RE = /(?:\+?\d{1,3}[\s-]?)?\(?\d{2,4}\)?[\s-]\d{2,4}[\s-]?\d{3,4}/;

  function rowLikelyHasPii(row) {
    var corpus = '';
    if (row.title) corpus += row.title + ' ';
    if (row.source) corpus += row.source + ' ';
    return PII_EMAIL_RE.test(corpus) || PII_PHONE_RE.test(corpus);
  }

  // Render the Privacy badge column. Privacy Filter and Knowledge Base
  // save are mutually exclusive at the app level: apps that declare
  // `privacy do; enabled true; end` in their MDSL have library_save
  // forced to false by dsl.rb#finalize_capabilities!, so saved KB
  // entries never go through the Privacy registry — there is no
  // `pii_status` field to surface. The remaining heuristic catches
  // legacy or imported entries whose title / source obviously looks
  // like PII (email or phone patterns), giving the user a glance-level
  // warning before clicking in.
  function privacyBadgeHtml(row) {
    if (rowLikelyHasPii(row)) {
      var label = t('ui.libBadgePiiHeuristic', 'May contain PII (email or phone pattern detected in title/source)');
      return '<span title="' + escapeHtml(label) + '" aria-label="' + escapeHtml(label) + '">'
        + '<i class="fa-solid fa-triangle-exclamation text-secondary"></i></span>';
    }
    return '';
  }

  function browseRowMarkup(row, idx) {
    var convId = escapeHtml(row.conversation_id || '');
    var title = row.title && row.title.length > 0 ? row.title : '(untitled)';
    var turns = (typeof row.turns_count === 'number') ? row.turns_count : '?';
    var rel = relativeTime(row.created_at);
    var privacyBadge = privacyBadgeHtml(row);
    // Toggle flips between Global and the app's literal class name. We
    // need the app's class name (whatever the entry was last scoped to,
    // or whatever app is currently active). Falling back via the row
    // payload covers normal flow; the toggle is hidden for legacy
    // entries with no recognisable app class.
    var currentScope = row.scope_app || 'Global';
    var nextScope, toggleLabel;
    if (currentScope === 'Global') {
      // Flipping to app-only requires a target app. Use the most recent
      // app the user touched (window.params.app_name) when available.
      var currentApp = (typeof window.params === 'object' && window.params && window.params.app_name) || null;
      nextScope = currentApp || '';
      toggleLabel = currentApp
        ? t('ui.libMakeAppOnly', 'Make app-only ({app})').replace('{app}', formatScopeApp(currentApp))
        : t('ui.libMakeAppOnlyDisabled', 'Switch to an app to scope this entry');
    } else {
      nextScope = 'Global';
      toggleLabel = t('ui.libMakeGlobal', 'Make Global');
    }
    var detailLabel = t('ui.libViewDetails', 'View details');
    var deleteLabel = t('ui.libDelete', 'Delete');
    var toggleDisabled = (nextScope === '') ? 'disabled' : '';
    return (
      '<tr data-conversation-id="' + convId + '" data-row-index="' + idx + '">'
      +   '<td class="text-center">' + typeIconHtml(row.content_type, row.topics) + '</td>'
      +   '<td>'
      +     '<div class="fw-medium text-truncate" style="max-width: 380px; color: #374151;">'
      +       (privacyBadge ? privacyBadge + ' ' : '')
      +       escapeHtml(truncate(title, 80))
      +     '</div>'
      +     '<div class="text-secondary small text-truncate" style="max-width: 380px;">' + escapeHtml(row.source || '') + (row.language ? ' · ' + escapeHtml(row.language) : '') + '</div>'
      +   '</td>'
      +   '<td>' + scopeBadge(row.scope_app) + '</td>'
      +   '<td class="text-end small">' + turns + '</td>'
      +   '<td class="text-nowrap small text-secondary">' + escapeHtml(rel) + '</td>'
      +   '<td class="text-end text-nowrap">'
      +     '<button type="button" class="btn btn-sm btn-outline-secondary me-1 library-action-detail" '
      +       'title="' + escapeHtml(detailLabel) + '" aria-label="' + escapeHtml(detailLabel) + '">'
      +       '<i class="fa-solid fa-circle-info"></i>'
      +     '</button>'
      +     '<button type="button" class="btn btn-sm btn-outline-secondary me-1 library-action-toggle" ' + toggleDisabled + ' '
      +       'data-next-scope="' + escapeHtml(nextScope) + '" '
      +       'title="' + escapeHtml(toggleLabel) + '" aria-label="' + escapeHtml(toggleLabel) + '">'
      +       '<i class="fa-solid fa-arrows-rotate"></i>'
      +     '</button>'
      +     '<button type="button" class="btn btn-sm btn-outline-danger library-action-delete" '
      +       'title="' + escapeHtml(deleteLabel) + '" aria-label="' + escapeHtml(deleteLabel) + '">'
      +       '<i class="fa-regular fa-trash-can"></i>'
      +     '</button>'
      +   '</td>'
      + '</tr>'
    );
  }

  // ─── Filtering / sorting / paging ────────────────────────────────────

  function applyFilters() {
    var rows = (state.allRows || []).slice();
    if (state.scopeFilter && state.scopeFilter !== 'all') {
      rows = rows.filter(function (r) { return (r.scope_app || 'Global') === state.scopeFilter; });
    }
    var q = (state.searchTerm || '').trim().toLowerCase();
    if (q.length > 0) {
      rows = rows.filter(function (r) {
        var hay = [r.title, r.source, r.language, r.conversation_id, r.content_type]
          .filter(Boolean).join(' ').toLowerCase();
        return hay.indexOf(q) !== -1;
      });
    }
    rows.sort(function (a, b) {
      switch (state.sortKey) {
        case 'created_asc': return String(a.created_at || '').localeCompare(String(b.created_at || ''));
        case 'title_asc':   return String(a.title || '').localeCompare(String(b.title || ''));
        case 'turns_desc':  return (b.turns_count || 0) - (a.turns_count || 0);
        case 'created_desc':
        default:            return String(b.created_at || '').localeCompare(String(a.created_at || ''));
      }
    });
    state.filteredRows = rows;
    var maxPage = Math.max(0, Math.ceil(rows.length / state.pageSize) - 1);
    if (state.page > maxPage) state.page = maxPage;
  }

  // ─── Renderers ───────────────────────────────────────────────────────

  function recentContainer() {
    return (typeof document !== 'undefined') ? document.getElementById('library-recent') : null;
  }
  function statsContainer() {
    return (typeof document !== 'undefined') ? document.getElementById('library-stats-info') : null;
  }
  function totalBadge() {
    return (typeof document !== 'undefined') ? document.getElementById('library-total-badge') : null;
  }
  function browseTbody() {
    return (typeof document !== 'undefined') ? document.getElementById('library-browse-tbody') : null;
  }
  function browseCountEl() {
    return (typeof document !== 'undefined') ? document.getElementById('library-browse-count') : null;
  }
  function browsePageInfoEl() {
    return (typeof document !== 'undefined') ? document.getElementById('library-browse-pageinfo') : null;
  }
  function browseEmptyEl() {
    return (typeof document !== 'undefined') ? document.getElementById('library-browse-empty') : null;
  }
  function browsePrevBtn() {
    return (typeof document !== 'undefined') ? document.getElementById('library-browse-prev') : null;
  }
  function browseNextBtn() {
    return (typeof document !== 'undefined') ? document.getElementById('library-browse-next') : null;
  }

  function emptyText() {
    return t('ui.libEmpty', 'The Knowledge Base is empty.');
  }

  function renderSidebarRecent() {
    var container = recentContainer();
    if (!container) return;
    var rows = state.allRows.slice(0, SIDEBAR_RECENT_LIMIT);
    if (rows.length === 0) {
      container.innerHTML = '<div class="small text-secondary fst-italic">' + escapeHtml(emptyText()) + '</div>';
      return;
    }
    container.innerHTML = rows.map(compactRowMarkup).join('');
  }

  function renderTotalBadge() {
    var el = totalBadge();
    if (!el) return;
    el.textContent = String(state.allRows.length);
  }

  function renderBrowseTable() {
    var tbody = browseTbody();
    if (!tbody) return;
    var rows = state.filteredRows;
    var start = state.page * state.pageSize;
    var slice = rows.slice(start, start + state.pageSize);

    if (slice.length === 0) {
      tbody.innerHTML = '';
      var empty = browseEmptyEl();
      if (empty) empty.style.display = '';
    } else {
      var emptyHide = browseEmptyEl();
      if (emptyHide) emptyHide.style.display = 'none';
      tbody.innerHTML = slice.map(function (r, i) { return browseRowMarkup(r, start + i); }).join('');
      wireBrowseRowActions(tbody);
    }

    var countEl = browseCountEl();
    if (countEl) {
      var total = state.allRows.length;
      var shown = state.filteredRows.length;
      var label = total === shown
        ? shown + ' / ' + total
        : shown + ' / ' + total + ' ' + t('ui.libFiltered', 'filtered');
      countEl.textContent = label;
    }

    var pageInfo = browsePageInfoEl();
    if (pageInfo) {
      var first = rows.length === 0 ? 0 : (start + 1);
      var last = Math.min(rows.length, start + slice.length);
      pageInfo.textContent = t('ui.libShowing', 'Showing') + ' ' + first + '-' + last + ' / ' + rows.length;
    }
    var prev = browsePrevBtn();
    if (prev) prev.disabled = state.page <= 0;
    var next = browseNextBtn();
    if (next) next.disabled = ((state.page + 1) * state.pageSize) >= rows.length;
  }

  function rerenderAll() {
    applyFilters();
    renderSidebarRecent();
    renderTotalBadge();
    renderScopeFilterOptions();
    renderBrowseTable();
  }

  // Refresh the Browse modal's scope filter <select> so it offers one
  // option per distinct scope_app currently in the table, sorted with
  // "Global" first. Preserves the active selection when possible.
  function renderScopeFilterOptions() {
    if (typeof document === 'undefined') return;
    var select = document.getElementById('library-browse-scope');
    if (!select) return;

    var scopes = {};
    (state.allRows || []).forEach(function (r) {
      var s = r.scope_app || 'Global';
      scopes[s] = true;
    });
    var sorted = Object.keys(scopes).sort(function (a, b) {
      if (a === 'Global') return -1;
      if (b === 'Global') return 1;
      return a.localeCompare(b);
    });

    var current = state.scopeFilter || 'all';
    var html = '<option value="all">' +
      escapeHtml(t('ui.libBrowseAllScopes', 'All scopes')) + '</option>';
    sorted.forEach(function (s) {
      var sel = (s === current) ? ' selected' : '';
      html += '<option value="' + escapeHtml(s) + '"' + sel + '>' +
              escapeHtml(formatScopeApp(s)) + '</option>';
    });
    // Restore the "all" selection after replacing innerHTML.
    select.innerHTML = html;
    if (current !== 'all' && !scopes[current]) {
      // The previously selected scope is no longer in the row set
      // (e.g., the only entry in that scope was deleted). Reset to all.
      state.scopeFilter = 'all';
    }
    select.value = state.scopeFilter;
  }

  // ─── Browse-row action wiring ────────────────────────────────────────

  function wireBrowseRowActions(scope) {
    if (!scope) return;
    scope.querySelectorAll('tr[data-conversation-id]').forEach(function (tr) {
      var convId = tr.getAttribute('data-conversation-id');
      var detailLink = tr.querySelector('.library-action-detail');
      if (detailLink) {
        detailLink.addEventListener('click', function (e) {
          e.preventDefault();
          openDetailModal(convId);
        });
      }
      var toggleLink = tr.querySelector('.library-action-toggle');
      if (toggleLink && !toggleLink.disabled) {
        toggleLink.addEventListener('click', function (e) {
          e.preventDefault();
          var nextScope = toggleLink.getAttribute('data-next-scope') || 'Global';
          if (!nextScope) return; // disabled when there's no current app context
          setScopeApp(convId, nextScope);
        });
      }
      var deleteLink = tr.querySelector('.library-action-delete');
      if (deleteLink) {
        deleteLink.addEventListener('click', function (e) {
          e.preventDefault();
          confirmAndDelete(convId);
        });
      }
    });
  }

  function confirmAndDelete(convId) {
    var row = state.allRows.find(function (r) { return r.conversation_id === convId; });
    var label = (row && row.title) ? row.title : convId;
    var prompt = t('ui.libDeleteConfirm', 'Permanently delete "{title}" from the Knowledge Base?')
      .replace('{title}', label);
    var ok = window.confirm ? window.confirm(prompt) : true;
    if (ok) deleteConversation(convId);
  }

  // ─── Conversation Viewer modal ───────────────────────────────────────

  // Viewer subsumes the old "detail" modal: it shows metadata, actions
  // (delete / toggle scope), and verbatim messages all in one surface.
  // This keeps the user from juggling two modals when reading a
  // conversation and acting on it.

  function viewerEl(id) {
    return (typeof document !== 'undefined') ? document.getElementById(id) : null;
  }

  function viewerMetaLine(row) {
    var bits = [];
    if (row.source) bits.push(escapeHtml(row.source));
    if (row.language) bits.push('lang=' + escapeHtml(row.language));
    if (typeof row.turns_count === 'number') bits.push(row.turns_count + 'T');
    if (typeof row.messages_count === 'number') bits.push(row.messages_count + ' msgs');
    if (row.created_at) bits.push(escapeHtml(relativeTime(row.created_at)));
    return bits.join(' · ')
      + ' <span class="ms-2">' + scopeBadge(row.scope_app) + '</span>';
  }

  // Render an array of monadic-conversation v1 messages into the viewer
  // body. Each message becomes a `.library-viewer-message` block tagged
  // with `data-role` so per-role CSS can color it like the live chat
  // cards. System prompts are wrapped in <details> and collapsed by
  // default so the user is not blasted with a multi-paragraph system
  // prompt when they just want to read the conversation.
  function renderViewerMessages(messages, container) {
    if (!container) return;
    container.innerHTML = '';
    if (!Array.isArray(messages) || messages.length === 0) return;

    messages.forEach(function (msg, idx) {
      var role = msg && msg.speaker && msg.speaker.id ? String(msg.speaker.id) : 'other';
      var icon = role === 'human' ? 'fa-user'
        : role === 'assistant' ? 'fa-robot'
        : role === 'system' ? 'fa-cog' : 'fa-comment';
      var roleColor = role === 'human' ? 'primary'
        : role === 'assistant' ? 'danger'
        : role === 'system' ? 'secondary' : 'secondary';
      var text = (msg && typeof msg.text === 'string') ? msg.text : '';

      var wrap = document.createElement('div');
      wrap.className = 'library-viewer-message';
      wrap.setAttribute('data-message-index', String(idx));
      wrap.setAttribute('data-role', role);

      if (role === 'system') {
        // Collapse system prompts behind <details> so the body of the
        // conversation is what the user sees first.
        var details = document.createElement('details');
        details.className = 'library-viewer-system';
        var summary = document.createElement('summary');
        summary.className = 'fw-bold text-' + roleColor;
        summary.innerHTML = '<i class="fas ' + icon + ' me-1"></i>'
          + escapeHtml(t('ui.libViewerSystemPrompt', 'System prompt')) + ' '
          + '<span class="text-secondary fw-normal">(' + escapeHtml(t('ui.libViewerClickToExpand', 'click to expand')) + ')</span>';
        details.appendChild(summary);
        var sysBody = document.createElement('div');
        sysBody.className = 'library-viewer-text';
        renderMarkdownInto(text, sysBody);
        details.appendChild(sysBody);
        wrap.appendChild(details);
      } else {
        var header = document.createElement('div');
        header.className = 'fw-bold small mb-1 text-' + roleColor;
        header.innerHTML = '<i class="fas ' + icon + ' me-1"></i>' + escapeHtml(role);
        wrap.appendChild(header);

        var body = document.createElement('div');
        body.className = 'library-viewer-text';
        renderMarkdownInto(text, body);
        wrap.appendChild(body);
      }
      container.appendChild(wrap);
    });
  }

  // Render markdown text into a container, falling back to plain text
  // when MarkdownRenderer is not loaded (e.g. in jsdom-based unit tests).
  function renderMarkdownInto(text, container) {
    if (typeof window.MarkdownRenderer === 'object'
        && typeof window.MarkdownRenderer.renderAndApply === 'function') {
      try {
        window.MarkdownRenderer.renderAndApply(text, container);
        return;
      } catch (_) { /* fall through */ }
    }
    container.textContent = text;
  }

  function setViewerLoading(isLoading) {
    var loadingEl = viewerEl('library-viewer-loading');
    if (loadingEl) loadingEl.style.display = isLoading ? '' : 'none';
  }

  function openViewerModal(conversationId) {
    if (typeof document === 'undefined') return;
    state.selectedId = conversationId;
    var row = state.allRows.find(function (r) { return r.conversation_id === conversationId; });

    var titleEl = viewerEl('library-viewer-title');
    if (titleEl) {
      var title = (row && row.title) ? row.title : '(untitled)';
      titleEl.textContent = title;
    }
    // Show the rename pencil only when we have a real conversation row
    // bound; the static "Conversation Viewer" placeholder shouldn't be
    // editable.
    var renameBtn = viewerEl('library-viewer-rename');
    if (renameBtn) renameBtn.style.display = row ? '' : 'none';
    closeRenameEditor();
    var metaEl = viewerEl('library-viewer-meta');
    if (metaEl && row) metaEl.innerHTML = viewerMetaLine(row);
    var emptyEl = viewerEl('library-viewer-empty');
    if (emptyEl) emptyEl.style.display = 'none';
    var messagesEl = viewerEl('library-viewer-messages');
    if (messagesEl) messagesEl.innerHTML = '';

    var toggleBtn = viewerEl('library-viewer-toggle-scope');
    var toggleLabel = viewerEl('library-viewer-toggle-label');
    if (row && toggleBtn) {
      applyScopeToggleState(row, toggleBtn, toggleLabel);
    }

    setViewerLoading(true);

    // Fire the WS request — handleConversationData renders the body when
    // the server responds. We fall through to an empty state if the
    // record has no verbatim messages stored.
    send('LIBRARY_GET_CONVERSATION', { contents: { conversation_id: conversationId } });

    var modalEl = viewerEl('libraryViewerModal');
    if (modalEl && typeof window.bootstrap !== 'undefined' && window.bootstrap.Modal) {
      // Bootstrap does not reliably route ESC to the topmost stacked
      // modal, so layering Viewer over Browse leads to ESC closing
      // Browse while Viewer stays. Avoid the stacking problem entirely
      // by hiding Browse first; we'll re-open it when the Viewer is
      // closed (see init's hidden.bs.modal listener).
      var browseEl = document.getElementById('libraryBrowseModal');
      if (browseEl && browseEl.classList.contains('show')) {
        state.viewerOpenedFromBrowse = true;
        var browseInst = window.bootstrap.Modal.getInstance(browseEl);
        if (browseInst) browseInst.hide();
      }
      window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
    }
  }

  // Backwards-compat alias retained so older call sites and tests still
  // function. The viewer fully subsumes the old detail-only surface.
  function openDetailModal(conversationId) { return openViewerModal(conversationId); }

  function closeViewerModalIfOpen() {
    var modalEl = viewerEl('libraryViewerModal');
    if (modalEl && typeof window.bootstrap !== 'undefined' && window.bootstrap.Modal) {
      var inst = window.bootstrap.Modal.getInstance(modalEl);
      if (inst) inst.hide();
    }
  }
  // Legacy alias for the previously-removed detail modal close hook.
  function closeDetailModalIfOpen() { return closeViewerModalIfOpen(); }

  function handleConversationData(data) {
    setViewerLoading(false);
    if (!data || data.res !== 'success') {
      var emptyEl = viewerEl('library-viewer-empty');
      if (emptyEl) {
        emptyEl.style.display = '';
        emptyEl.textContent = (data && data.content)
          ? data.content
          : t('ui.libViewerLoadFailure', 'Could not load this conversation.');
      }
      return;
    }
    var conv = (data.conversation || {});
    var msgs = conv.messages;
    if (!Array.isArray(msgs) || msgs.length === 0) {
      var empty2 = viewerEl('library-viewer-empty');
      if (empty2) {
        empty2.style.display = '';
        empty2.textContent = conv.skipped_reason
          ? t('ui.libViewerSkipped', 'Verbatim messages were not stored (')
              + conv.skipped_reason + ').'
          : t('ui.libViewerEmpty', 'No verbatim messages were stored for this conversation. Re-save it to enable the Viewer.');
      }
      return;
    }
    renderViewerMessages(msgs, viewerEl('library-viewer-messages'));
  }

  // ─── Browse modal ────────────────────────────────────────────────────

  function openBrowseModal() {
    // Auto-refresh on open: this replaces the explicit Refresh button on
    // the sidebar. The user's intent ("show me what's saved right now")
    // maps 1:1 to opening the Browse modal, so we treat that click as
    // the implicit refresh trigger and always pull a fresh snapshot.
    // Fired before the DOM check so the request goes out even if the
    // modal element is absent (e.g. embedded widget surfaces in tests).
    requestList();
    requestStats();

    if (typeof document === 'undefined') return;
    var modalEl = document.getElementById('libraryBrowseModal');
    if (!modalEl) return;
    state.page = 0;
    rerenderAll();
    if (typeof window.bootstrap !== 'undefined' && window.bootstrap.Modal) {
      window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
    }
  }

  // ─── WebSocket message handlers ──────────────────────────────────────

  function handleConversations(data) {
    var rows = (data && Array.isArray(data.content)) ? data.content : [];
    state.allRows = rows;
    rerenderAll();
  }

  function handleStats(data) {
    var el = statsContainer();
    if (!el) return;
    var stats = (data && typeof data.content === 'object') ? data.content : null;
    el.textContent = formatStats(stats);
  }

  function handleDeletedMessage(data) {
    if (data && data.res === 'success') {
      var convId = data.conversation_id;
      if (convId) {
        state.allRows = state.allRows.filter(function (r) { return r.conversation_id !== convId; });
        rerenderAll();
        // If the user just deleted the same entry the current session
        // was bound to, drop the binding so the next Save creates a new
        // entry rather than failing to replace a non-existent one.
        if (state.currentConversationId === convId) {
          state.currentConversationId = null;
        }
      }
    } else {
      // Surface the failure instead of leaving the row in place with no
      // explanation (the click otherwise looks like it did nothing).
      var msg = (data && data.content) ? String(data.content) : 'Failed to delete the entry.';
      flashAlert("<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(msg), 'error');
    }
    requestList();
    requestStats();
  }

  function handleSavedMessage(data) {
    if (!data) return;
    setSavePending(false);
    // Broadcast the save result so external flows (e.g. Reset → Save &
    // Reset) can react without coupling directly to handleSavedMessage.
    if (typeof window !== 'undefined' && typeof window.dispatchEvent === 'function') {
      try {
        window.dispatchEvent(new CustomEvent('library:save:result', { detail: data }));
      } catch (e) { /* IE/test envs without CustomEvent — ignore */ }
    }
    if (data.res === 'success') {
      // Remember the server-assigned id so subsequent Saves on this
      // session update-in-place. The same id is reused across Save
      // clicks until the user resets the session, switches apps, or
      // deletes the entry from Browse.
      if (data.conversation_id) {
        state.currentConversationId = data.conversation_id;
      }
      requestList();
      requestStats();
      var modalEl = (typeof document !== 'undefined') ? document.getElementById('librarySaveModal') : null;
      if (modalEl && typeof window.bootstrap !== 'undefined' && window.bootstrap.Modal) {
        var inst = window.bootstrap.Modal.getInstance(modalEl);
        if (inst) inst.hide();
      }
      var defaultLabel = data.updated
        ? t('ui.libUpdateSuccess', 'Updated existing Knowledge Base entry.')
        : t('ui.libSaveSuccess', 'Saved to Knowledge Base.');
      flashAlert("<i class='fa-solid fa-circle-check'></i> " + escapeHtml(defaultLabel), 'success');
    } else {
      var msg = (data && data.content) ? data.content : 'Save failed';
      var prefix = t('ui.libSaveFailure', 'Failed to save');
      flashAlert(
        "<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(prefix) + ': ' + escapeHtml(msg),
        'warning'
      );
    }
  }

  // External hook: reset the binding so the next Save creates a brand
  // new KB entry. Called from the conversation reset path and from the
  // app-switch handler. Exported via window.libraryPanel.
  function clearCurrentConversation() {
    state.currentConversationId = null;
    // The cached title suggestion belongs to the previous logical
    // conversation; clearing it here ensures a fresh session asks the
    // LLM for a new title rather than recycling a stale one.
    state.cachedTitleSuggestion = null;
    state.cachedTitleSuggestionMessageCount = 0;
  }

  // Apply an LLM-suggested title to the Save modal's title input. We
  // intentionally do *not* overwrite anything the user has already
  // typed: the suggestion is a default, not an override. The placeholder
  // and spinner are reset whether the suggestion succeeded or not, so
  // the loading state never lingers.
  function handleTitleSuggested(data) {
    state.titleSuggestionPending = false;
    if (typeof document === 'undefined') return;
    var input = document.getElementById('library-save-title');
    if (!input) return;
    // Reset placeholder so "Suggesting title…" doesn't stick around if
    // the LLM returned nothing or the user already started typing.
    input.placeholder = currentAppName() || '';
    var spinnerEl = document.getElementById('library-save-title-spinner');
    if (spinnerEl) spinnerEl.style.display = 'none';
    if (!data || data.res !== 'success') return;
    var title = (data.title || '').toString().trim();
    if (!title) return;
    // Cache the suggestion against the conversation length so that
    // canceling and re-opening the modal does not fire another LLM
    // call. The cache is invalidated implicitly when the conversation
    // grows (count mismatch) and explicitly on Reset / app switch.
    var count = Array.isArray(window.messages)
      ? window.messages.filter(function (m) { return m && (m.role === 'user' || m.role === 'assistant'); }).length
      : 0;
    state.cachedTitleSuggestion = title;
    state.cachedTitleSuggestionMessageCount = count;
    // Race protection: if the user typed a title while the request
    // was in flight, leave their input alone.
    if (input.value && input.value.trim().length > 0) return;
    input.value = title;
  }

  function handleRagState(data) {
    var el = (typeof document !== 'undefined') ? document.getElementById('library-rag-toggle') : null;
    if (!el) return;
    var enabled = !!(data && data.enabled);
    if (el.checked !== enabled) el.checked = enabled;
  }

  function handleScopeUpdated(data) {
    if (!data) return;
    if (data.res === 'success') {
      var convId = data.conversation_id;
      var scopeApp = data.scope_app;
      state.allRows.forEach(function (r) {
        if (r.conversation_id === convId) r.scope_app = scopeApp;
      });
      rerenderAll();
      // Refresh stats so per-scope counters update.
      requestStats();
      // If the Viewer is showing this conversation, refresh metadata
      // + toggle-button label in place. No re-fetch needed.
      if (state.selectedId === convId) {
        var row = state.allRows.find(function (r) { return r.conversation_id === convId; });
        if (row) {
          var metaEl = viewerEl('library-viewer-meta');
          if (metaEl) metaEl.innerHTML = viewerMetaLine(row);
          var toggleBtn = viewerEl('library-viewer-toggle-scope');
          var toggleLabel = viewerEl('library-viewer-toggle-label');
          applyScopeToggleState(row, toggleBtn, toggleLabel);
        }
      }
      flashAlert(
        "<i class='fa-solid fa-circle-check'></i> " + escapeHtml(t('ui.libScopeUpdated', 'Scope updated.')),
        'success'
      );
    } else {
      flashAlert(
        "<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(data.content || 'Update failed'),
        'warning'
      );
    }
  }

  function formatStats(stats) {
    if (!stats || typeof stats !== 'object') return '';
    var total = stats.conversations_total || 0;
    var byScope = stats.conversations_by_scope || {};
    // Render the per-scope breakdown as a compact "Global=N, App=M"
    // tail. Sorted with Global first so the cross-app pool is the
    // user's first read.
    var scopes = Object.keys(byScope);
    var withGlobalFirst = scopes.sort(function (a, b) {
      if (a === 'Global') return -1;
      if (b === 'Global') return 1;
      return a.localeCompare(b);
    });
    var parts = withGlobalFirst.map(function (s) {
      return formatScopeApp(s) + ' ' + byScope[s];
    });
    if (parts.length === 0) return 'Knowledge Base: ' + total + ' total';
    // Use an em dash separator instead of wrapping the breakdown in
    // outer parens — formatScopeApp("ChatOpenAI") already injects its
    // own parens for the provider, and a second pair around the list
    // produces a confusing "( ... ( ... ) ... )" reading.
    return 'Knowledge Base: ' + total + ' total — ' + parts.join(', ');
  }

  // ─── Save modal helpers (unchanged from prior iteration) ─────────────

  function setSavePending(pending) {
    if (typeof document === 'undefined') return;
    var btn = document.getElementById('library-save-confirm');
    var cancelBtn = document.querySelector('#librarySaveModal [data-bs-dismiss="modal"]');
    var titleInput = document.getElementById('library-save-title');
    var radios = document.querySelectorAll('input[name="librarySaveScope"]');
    if (btn) {
      btn.disabled = !!pending;
      if (pending) {
        btn.dataset.origLabel = btn.innerHTML;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + t('ui.libSavingButton', 'Saving...');
      } else if (btn.dataset.origLabel) {
        btn.innerHTML = btn.dataset.origLabel;
        delete btn.dataset.origLabel;
      }
    }
    if (cancelBtn) cancelBtn.disabled = !!pending;
    if (titleInput) titleInput.disabled = !!pending;
    radios.forEach(function (r) { r.disabled = !!pending; });
  }

  function flashAlert(html, severity) {
    if (typeof window.setAlert === 'function') {
      window.setAlert(html, severity);
    }
  }

  function currentAppName() {
    try {
      var el = document.getElementById('apps');
      if (el && el.value) return el.value;
    } catch (_) {}
    try {
      var p = (typeof window.params === 'object') ? window.params : null;
      if (p && p.app_name) return p.app_name;
    } catch (_) {}
    return '';
  }

  function privacyOn() {
    try {
      if (window.WsPrivacyHandler && typeof window.WsPrivacyHandler.isEnabled === 'function') {
        return !!window.WsPrivacyHandler.isEnabled();
      }
    } catch (_) {}
    try { return !!window.privacyEnabled; } catch (_) { return false; }
  }

  function openSaveModal() {
    if (typeof document === 'undefined') return;
    // Defense in depth: the Save button is disabled when no messages exist,
    // but this function is also exposed via window.libraryPanel — refuse
    // programmatic opens against an empty session too.
    if (!hasSessionMessages()) {
      flashAlert(
        "<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(t('ui.libNoMessages', 'There are no messages to save yet.')),
        'warning'
      );
      return;
    }
    var modalEl = document.getElementById('librarySaveModal');
    if (!modalEl) return;

    // Pre-fill the title with the most recent title we know for the
    // current session's KB entry. This covers the case where the user
    // saved with an auto-generated name, then renamed the entry from
    // the Viewer, then continued the conversation — re-Save should keep
    // the user's chosen title rather than reverting to a blank field.
    var existingRow = null;
    if (state.currentConversationId) {
      existingRow = state.allRows.find(function (r) {
        return r.conversation_id === state.currentConversationId;
      }) || null;
    }
    var titleInput = document.getElementById('library-save-title');
    if (titleInput) {
      titleInput.value = (existingRow && existingRow.title) ? existingRow.title : '';
      titleInput.placeholder = currentAppName() || '';
    }

    // Reset the in-input spinner each time the modal opens; it gets
    // re-shown below if a suggestion request is fired.
    var spinnerEl = document.getElementById('library-save-title-spinner');
    if (spinnerEl) spinnerEl.style.display = 'none';

    // First-save case: ask the active provider's LLM for a concise
    // title suggestion. We only do this when the title is blank and
    // there is real conversation content to summarise — otherwise the
    // request would be wasted (placeholder/app-name is already a fine
    // default for an empty session).
    var conversationCount = Array.isArray(window.messages)
      ? window.messages.filter(function (m) { return m && (m.role === 'user' || m.role === 'assistant'); }).length
      : 0;
    var hasConversation = conversationCount > 0;
    if (titleInput && !state.currentConversationId && !titleInput.value && hasConversation && !state.titleSuggestionPending) {
      // Cached-suggestion fast path: if we already asked the LLM for a
      // title at the same conversation length and got a result, reuse
      // it instead of firing another request when the user re-opens
      // the modal after Cancel.
      if (state.cachedTitleSuggestion && state.cachedTitleSuggestionMessageCount === conversationCount) {
        titleInput.value = state.cachedTitleSuggestion;
      } else {
        state.titleSuggestionPending = true;
        titleInput.placeholder = t('ui.libSuggestingTitle', 'Suggesting title…');
        // Show the inline spinner so the user sees motion while the LLM
        // works — a static placeholder reads as "frozen" especially on
        // slower providers. The matching cleanup happens in
        // handleTitleSuggested regardless of success/failure.
        if (spinnerEl) spinnerEl.style.display = '';
        requestTitleSuggestion();
      }
    }
    // Default the radio to "App-only" and inject the active app's
    // formatted label so the user sees which app the conversation is
    // about to be scoped to.
    var appOnlyRadio = document.getElementById('library-scope-app');
    if (appOnlyRadio) appOnlyRadio.checked = true;
    var appNameEl = document.getElementById('library-scope-app-name');
    if (appNameEl) {
      var appName = currentAppName();
      // Use ": Chat (OpenAI)" rather than " (Chat (OpenAI))" because
      // formatScopeApp itself returns parentheses around the provider —
      // wrapping the whole thing in another set of parens looks like
      // unbalanced punctuation to a casual reader.
      appNameEl.textContent = appName ? ': ' + formatScopeApp(appName) : '';
    }

    // Live-update the Global-scope warning. The default radio is
    // "App-only" so the warning is hidden initially; flipping the radio
    // to Global makes it visible. Listener is attached once per modal
    // open via a data flag so reopen doesn't accumulate handlers.
    var globalWarn = document.getElementById('library-scope-global-warning');
    var scopeRadios = document.querySelectorAll('input[name="librarySaveScope"]');
    function syncGlobalWarning() {
      if (!globalWarn) return;
      var checked = document.querySelector('input[name="librarySaveScope"]:checked');
      var isGlobal = checked && checked.value === 'Global';
      globalWarn.style.display = isGlobal ? '' : 'none';
    }
    scopeRadios.forEach(function (r) {
      if (!r.dataset.scopeWarningWired) {
        r.addEventListener('change', syncGlobalWarning);
        r.dataset.scopeWarningWired = '1';
      }
    });
    syncGlobalWarning();

    // Update mode: when this session has already been saved, swap the
    // dialog's title + confirm button + show a warning banner so the
    // user understands the next click will replace, not duplicate.
    var isUpdate = !!state.currentConversationId;
    var titleEl = document.getElementById('library-save-modal-title-text');
    var confirmEl = document.getElementById('library-save-confirm-text');
    var updateNote = document.getElementById('library-save-update-note');
    if (titleEl) {
      titleEl.textContent = isUpdate
        ? t('ui.libSaveModalTitleUpdate', 'Update Conversation in Knowledge Base')
        : t('ui.libSaveModalTitle', 'Save Conversation to Knowledge Base');
    }
    if (confirmEl) {
      confirmEl.textContent = isUpdate
        ? t('ui.libUpdateButton', 'Update')
        : t('ui.libSaveButton', 'Save');
    }
    if (updateNote) updateNote.style.display = isUpdate ? '' : 'none';

    if (typeof window.bootstrap !== 'undefined' && window.bootstrap.Modal) {
      var inst = window.bootstrap.Modal.getOrCreateInstance(modalEl);
      inst.show();
    }
  }

  function buildSavePayload(opts) {
    opts = opts || {};
    var initialPromptEl = document.getElementById('initial-prompt');
    var initial = (initialPromptEl && typeof initialPromptEl.value === 'string') ? initialPromptEl.value : '';
    var sysid = Math.floor(1000 + Math.random() * 9000);
    var msgs = [];
    msgs.push({ role: 'system', text: initial, mid: sysid });

    var src = (Array.isArray(window.messages)) ? window.messages : [];
    src.forEach(function (m, idx) {
      if (idx === 0 && m && m.role === 'system') return;
      var entry;
      if (m.role === 'assistant') {
        entry = { role: m.role, text: m.text, mid: m.mid, thinking: m.thinking };
      } else {
        entry = { role: m.role, text: m.text, mid: m.mid };
      }
      if (m.image) entry.image = m.image;
      msgs.push(entry);
    });

    var params = (typeof window.setParams === 'function') ? window.setParams() : {};
    if (params && Object.prototype.hasOwnProperty.call(params, 'initiate_from_assistant')) {
      delete params.initiate_from_assistant;
    }

    var payload = {
      messages: msgs,
      parameters: params
    };
    // scope_app is set explicitly when the user picked "Global". When
    // the user keeps the default "App-only" radio, we omit scope_app
    // and let the server fall back to params.app_name (the currently
    // active app's class name).
    if (opts.scopeApp && opts.scopeApp !== 'app') {
      payload.scope_app = opts.scopeApp;
    }
    if (opts.title && String(opts.title).trim().length > 0) {
      payload.title = String(opts.title).trim();
    }
    if (opts.monadicState && typeof opts.monadicState === 'object') {
      payload.monadic_state = opts.monadicState;
    }
    // Carry the existing conversation_id forward when the current
    // session has already been saved once. The server reads this and
    // performs delete-then-insert, replacing the prior version in place.
    var stickyId = (opts.conversationId !== undefined)
      ? opts.conversationId
      : state.currentConversationId;
    if (stickyId) {
      payload.conversation_id = stickyId;
    }
    return payload;
  }

  function readModalSelections() {
    var titleEl = document.getElementById('library-save-title');
    var title = (titleEl && titleEl.value) ? titleEl.value : '';
    var scopeEl = document.querySelector('input[name="librarySaveScope"]:checked');
    var scope = (scopeEl && scopeEl.value) ? scopeEl.value : 'app';
    return { title: title, scopeApp: scope };
  }

  function submitSave() {
    var sel = readModalSelections();
    var hasMessages = Array.isArray(window.messages) && window.messages.length > 0;
    if (!hasMessages) {
      flashAlert(
        "<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(t('ui.libNoMessages', 'There are no messages to save yet.')),
        'warning'
      );
      return false;
    }

    setSavePending(true);
    flashAlert(
      "<i class='fas fa-spinner fa-spin'></i> " + escapeHtml(t('ui.libSavingMessage', 'Saving conversation to Knowledge Base...')),
      'info'
    );

    var afterState = function (state2) {
      var payload = buildSavePayload({
        title: sel.title, scopeApp: sel.scopeApp, monadicState: state2
      });
      var ok = send('LIBRARY_SAVE', { contents: payload });
      if (!ok) {
        setSavePending(false);
        flashAlert(
          "<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(t('ui.libSaveFailure', 'Failed to save')) + ': WebSocket not connected',
          'warning'
        );
      }
    };

    try {
      fetch('/monadic_state').then(function (resp) {
        if (!resp || !resp.ok) { afterState(null); return; }
        return resp.json().then(function (data) {
          afterState((data && data.monadic_state) ? data.monadic_state : null);
        });
      }).catch(function () { afterState(null); });
    } catch (_) {
      afterState(null);
    }
    return true;
  }

  // ─── Rename conversation (Viewer modal pencil + inline editor) ──────

  function openRenameEditor() {
    if (typeof document === 'undefined') return;
    if (!state.selectedId) return;
    var row = state.allRows.find(function (r) { return r.conversation_id === state.selectedId; });
    var titleEl = viewerEl('library-viewer-title');
    var renameBtn = viewerEl('library-viewer-rename');
    var form = viewerEl('library-viewer-rename-form');
    var input = viewerEl('library-viewer-rename-input');
    if (!form || !input || !titleEl) return;
    titleEl.style.display = 'none';
    if (renameBtn) renameBtn.style.display = 'none';
    form.classList.remove('d-none');
    input.value = (row && row.title) ? row.title : '';
    input.focus();
    input.select();
  }

  function closeRenameEditor() {
    if (typeof document === 'undefined') return;
    var titleEl = viewerEl('library-viewer-title');
    var renameBtn = viewerEl('library-viewer-rename');
    var form = viewerEl('library-viewer-rename-form');
    if (titleEl) titleEl.style.display = '';
    if (renameBtn) renameBtn.style.display = state.selectedId ? '' : 'none';
    if (form) form.classList.add('d-none');
  }

  function submitRename() {
    if (!state.selectedId) return;
    var input = viewerEl('library-viewer-rename-input');
    if (!input) return;
    var newTitle = (input.value || '').trim();
    if (!newTitle) {
      flashAlert(
        "<i class='fa-solid fa-triangle-exclamation'></i> " +
          escapeHtml(t('ui.libRenameEmpty', 'Title must not be empty')),
        'warning'
      );
      return;
    }
    send('LIBRARY_RENAME', {
      contents: { conversation_id: state.selectedId, title: newTitle }
    });
  }

  function handleRenamedMessage(data) {
    if (!data) return;
    if (data.res === 'success') {
      var convId = data.conversation_id;
      var newTitle = data.title || '';
      // Patch the local cache so renderBrowseTable / sidebar / Viewer
      // reflect the change without waiting for a full LIBRARY_LIST.
      state.allRows.forEach(function (r) {
        if (r.conversation_id === convId) r.title = newTitle;
      });
      rerenderAll();
      // Update the modal title display in place.
      var titleEl = viewerEl('library-viewer-title');
      if (titleEl && state.selectedId === convId) titleEl.textContent = newTitle;
      closeRenameEditor();
      flashAlert(
        "<i class='fa-solid fa-circle-check'></i> " +
          escapeHtml(t('ui.libRenameSuccess', 'Title updated.')),
        'success'
      );
    } else {
      var msg = (data && data.content) ? data.content : 'Rename failed';
      flashAlert(
        "<i class='fa-solid fa-triangle-exclamation'></i> " +
          escapeHtml(t('ui.libRenameFailure', 'Failed to rename')) + ': ' + escapeHtml(msg),
        'warning'
      );
    }
  }

  // ─── Import file (Markdown / Code / PDF / Office) ────────────────────

  function setImportPending(pending) {
    if (typeof document === 'undefined') return;
    var btn = document.getElementById('library-browse-import');
    if (!btn) return;
    btn.disabled = !!pending;
    if (pending) {
      btn.dataset.origLabel = btn.innerHTML;
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' +
        escapeHtml(t('ui.libImportingButton', 'Importing...'));
    } else if (btn.dataset.origLabel) {
      btn.innerHTML = btn.dataset.origLabel;
      delete btn.dataset.origLabel;
    }
  }

  // Stage labels rendered in the alert while a background import runs.
  // Backend stage values are documented in import_tracker.rb (STAGES)
  // and produced by library_import_routes.rb's worker thread.
  var IMPORT_STAGE_LABELS = {
    queued: 'libImportStageQueued',
    extracting: 'libImportStageExtracting',
    embedding_storing: 'libImportStageEmbedding'
  };

  function importStageMessage(stage) {
    var key = IMPORT_STAGE_LABELS[stage];
    if (!key) {
      return t('ui.libImportingMessage', 'Importing file into Knowledge Base...');
    }
    var fallback = {
      libImportStageQueued: 'Queued for import…',
      libImportStageExtracting: 'Extracting text…',
      libImportStageEmbedding: 'Generating embeddings & saving…'
    }[key];
    return t('ui.' + key, fallback);
  }

  // Poll /library/import/status/:id with exponential backoff until the
  // import reaches a terminal stage (`done` or `error`) or the hard
  // timeout fires. Resolves with the final status payload on success;
  // rejects with an Error on failure or timeout.
  function pollImportStatus(importId, onProgress) {
    return new Promise(function (resolve, reject) {
      var delay = 800;          // initial poll delay (ms)
      var maxDelay = 5000;      // cap at 5s once warmed up
      var growth = 1.4;         // multiplicative backoff
      var hardTimeoutMs = 30 * 60 * 1000;  // 30 min absolute cap
      var startedAt = Date.now();

      function tick() {
        if (Date.now() - startedAt > hardTimeoutMs) {
          return reject(new Error('Import timed out (over 30 minutes)'));
        }

        fetch('/library/import/status/' + encodeURIComponent(importId), {
          headers: { 'Accept': 'application/json' }
        })
          .then(function (res) {
            return res.json().then(function (data) {
              return { ok: res.ok, status: res.status, data: data };
            }, function () {
              return { ok: res.ok, status: res.status, data: null };
            });
          })
          .then(function (out) {
            if (out.status === 404) {
              return reject(new Error(
                'Import status not found — the import may have completed before the first poll, or the server restarted. Refresh the panel to verify.'
              ));
            }
            if (!out.ok || !out.data) {
              return reject(new Error('Status check failed (HTTP ' + out.status + ')'));
            }
            var entry = out.data;
            if (entry.stage === 'done') {
              return resolve(entry);
            }
            if (entry.stage === 'error') {
              return reject(new Error(entry.error || 'Unknown import error'));
            }
            // In-flight stage; surface to caller for UI updates.
            if (typeof onProgress === 'function') {
              try { onProgress(entry); } catch (_e) { /* never let UI throw cancel polling */ }
            }
            delay = Math.min(maxDelay, Math.round(delay * growth));
            setTimeout(tick, delay);
          })
          .catch(function (err) {
            // Network blip — retry a few times before giving up.
            if (Date.now() - startedAt > hardTimeoutMs) {
              return reject(err);
            }
            delay = Math.min(maxDelay, Math.round(delay * growth));
            setTimeout(tick, delay);
          });
      }
      tick();
    });
  }

  // POST a single file to /library/import (which now returns 202 +
  // import_id immediately) and poll the status endpoint until the
  // background worker reports `done` or `error`. The endpoint dispatches
  // to the right importer based on file extension
  // (FileImporter.build_conversation on the Ruby side).
  function uploadLibraryFile(file, options) {
    if (!file) return Promise.reject(new Error('No file selected'));
    options = options || {};

    var formData = new FormData();
    formData.append('libraryFile', file);
    if (options.title) formData.append('libraryTitle', options.title);
    if (options.scopeApp) formData.append('libraryScopeApp', options.scopeApp);
    if (options.license) formData.append('libraryLicense', options.license);

    setImportPending(true);
    flashAlert(
      "<i class='fas fa-spinner fa-spin'></i> " +
        escapeHtml(t('ui.libImportingMessage', 'Importing file into Knowledge Base...')),
      'info'
    );

    // POST is now lightweight (size check + disk write + tracker
    // registration); a 60s timeout is plenty. Polling then runs without
    // its own timeout — the backend tracker enforces the 30-min cap.
    var postController = new AbortController();
    var postTimer = setTimeout(function () { postController.abort(); }, 60000);

    return fetch('/library/import', {
      method: 'POST', body: formData, signal: postController.signal
    })
      .then(function (res) {
        clearTimeout(postTimer);
        return res.json().then(function (data) {
          return { ok: res.ok, status: res.status, data: data };
        });
      })
      .then(function (out) {
        // 202 = accepted; anything else surfaces as an error (validation
        // failures still come back as 200 with success=false from the
        // legacy error_json helper, so we accept that path too).
        if (out.status !== 202) {
          var err = (out.data && (out.data.message || out.data.error)) || ('HTTP ' + out.status);
          throw new Error(err);
        }
        if (!out.data || !out.data.import_id) {
          throw new Error('Server did not return an import_id');
        }
        return pollImportStatus(out.data.import_id, function (entry) {
          flashAlert(
            "<i class='fas fa-spinner fa-spin'></i> " +
              escapeHtml(importStageMessage(entry.stage)) +
              ' (' + escapeHtml(entry.filename || file.name) + ')',
            'info'
          );
        });
      })
      .then(function (entry) {
        setImportPending(false);
        flashAlert(
          "<i class='fa-solid fa-circle-check'></i> " +
            escapeHtml(t('ui.libImportSuccess', 'Imported to Knowledge Base') + ': ' + (entry.filename || file.name)),
          'success'
        );
        requestList();
        requestStats();
        return entry;
      })
      .catch(function (err) {
        clearTimeout(postTimer);
        setImportPending(false);
        var msg = (err && err.message) ? err.message : 'Network error';
        flashAlert(
          "<i class='fa-solid fa-triangle-exclamation'></i> " +
            escapeHtml(t('ui.libImportFailure', 'Failed to import')) + ': ' + escapeHtml(msg),
          'warning'
        );
        throw err;
      });
  }

  function triggerImportPicker() {
    var input = document.getElementById('library-import-input');
    if (input) {
      input.value = '';
      input.click();
    }
  }

  function handleImportFileChange(ev) {
    var file = ev && ev.target && ev.target.files && ev.target.files[0];
    if (!file) return;
    uploadLibraryFile(file).catch(function () { /* error already surfaced */ });
  }

  // Legacy alias retained for backwards compatibility with the original
  // single-pane sidebar render (used in older Jest tests).
  function render(container, rows) {
    if (!container) return;
    var safeRows = Array.isArray(rows) ? rows : [];
    if (safeRows.length === 0) {
      container.innerHTML =
        '<span class="text-secondary">' + escapeHtml(emptyText()) + '</span>';
      return;
    }
    container.innerHTML = safeRows.map(compactRowMarkup).join('');
  }

  // Legacy helper kept so existing Jest tests for the simple delete path
  // continue to pass.
  function handleDeleted(data, container) {
    if (data && data.res === 'success' && container) {
      var convId = data.conversation_id;
      if (convId) {
        var row = container.querySelector('[data-conversation-id="' + convId + '"]');
        if (row && row.parentNode) row.parentNode.removeChild(row);
      }
    }
    send('LIBRARY_LIST');
  }

  // ─── DOM bootstrap ───────────────────────────────────────────────────

  // True when there is at least one user/assistant message in the current
  // session. The Library Save flow gates on this so empty sessions cannot
  // produce empty Knowledge Base entries.
  function hasSessionMessages() {
    return Array.isArray(window.messages)
      && window.messages.some(function (m) { return m && (m.role === 'user' || m.role === 'assistant'); });
  }

  // Privacy Filter and Knowledge Base save are mutually exclusive at the
  // app level — see docs/basic-usage/basic-apps.md#privacy-kb-by-app.
  // The Save button is hidden in two cases:
  //   1. The current app is in the KB-save excluded list (artifact-centric
  //      apps and PF-only apps; flag set by DSL post-processing in
  //      lib/monadic/dsl.rb#library_save_eligible?).
  //   2. The Privacy Filter is active in this session — defense in depth
  //      so a misconfigured app cannot leak PII to disk.
  function isCurrentAppKbSaveEligible() {
    return readAppFeatureFlag('library_save');
  }

  // The "Use Knowledge Base for retrieval" toggle is gated on the same
  // app metadata as the library_search auto-injection. PF-only apps and
  // artifact-centric apps do not have library_search in their tool list,
  // so the toggle would be a no-op there — hiding it keeps the UI honest.
  function isCurrentAppKbRetrievalEligible() {
    return readAppFeatureFlag('library_search');
  }

  // Generic reader for boolean per-app feature flags. Treats absent
  // (legacy / user-defined custom apps without the flag) as ELIGIBLE so
  // an unknown app does not lose features it had before this gate
  // existed; only an explicit false / "false" disables.
  function readAppFeatureFlag(key) {
    try {
      var apps = window.apps;
      var name = (window.params && window.params.app_name) || null;
      if (!apps || !name) return true;
      var settings = apps[name];
      if (!settings) return true;
      return settings[key] !== false && settings[key] !== 'false';
    } catch (_) { return true; }
  }

  // The Save button is always present in the DOM (per CSS — see monadic.css
  // "App-capability declarative visibility gate"). This function owns its
  // `disabled` attribute and tooltip, picking the most informative reason
  // when more than one disable condition is in effect:
  //
  //   1. The current app does not support saving to the Knowledge Base
  //      (e.g. apps that declare `privacy do; enabled true; end` or
  //      `library_save false` in MDSL). Reported first because telling the
  //      user "no messages yet" is misleading when saving will never
  //      be allowed regardless of how many messages they have.
  //   2. Privacy Filter is currently ON in this session. Mutually
  //      exclusive with KB save by design — we refuse to ingest content
  //      that the user is actively asking us to mask before the LLM sees
  //      it. (Defense-in-depth on the backend side too.)
  //   3. There are simply no user/assistant messages to save yet.
  //
  // Driven by initial page load, SessionState events (message added /
  // cleared / app changed), and live `privacy:state-changed` pushes from
  // the backend so the button reflects backend-authoritative privacy
  // state without polling.
  function updateSaveButtonAvailability() {
    if (typeof document === 'undefined') return;
    var btn = document.getElementById('library-save');
    if (!btn) return;

    var appEligible = isCurrentAppKbSaveEligible();
    var privacyActive = privacyOn();
    var saveable = hasSessionMessages();

    var disabled = false;
    var titleKey = 'ui.libSaveCurrent';
    var titleFallback = 'Save current conversation to Knowledge Base';

    if (!appEligible) {
      disabled = true;
      titleKey = 'ui.libSaveAppUnsupported';
      titleFallback = 'This app does not support saving to the Knowledge Base.';
    } else if (privacyActive) {
      disabled = true;
      titleKey = 'ui.libSavePrivacyActive';
      titleFallback = 'Saving is disabled while the Privacy Filter is active in this session.';
    } else if (!saveable) {
      disabled = true;
      titleKey = 'ui.libNoMessages';
      titleFallback = 'There are no messages to save yet.';
    }

    btn.disabled = disabled;
    btn.setAttribute('title', t(titleKey, titleFallback));
  }

  // Drive the body capability classes from the SessionState `app:changed`
  // path. The CSS rule `body:not(.app-cap-kb-search) #library-rag-toggle-row`
  // then handles row visibility — this function exists only to fan out the
  // single SSOT entry point (applyAppCapabilityClasses) to one more caller.
  function updateRagToggleVisibility() {
    if (typeof window === 'undefined') return;
    if (typeof window.applyAppCapabilityClasses === 'function') {
      window.applyAppCapabilityClasses(currentAppName());
    }
  }

  function init() {
    if (typeof document === 'undefined') return;

    var saveBtn = document.getElementById('library-save');
    if (saveBtn) saveBtn.onclick = openSaveModal;
    updateSaveButtonAvailability();
    updateRagToggleVisibility();

    // Re-evaluate visibility whenever the conversation set or current
    // app changes. The Save button further reacts to Privacy state pushes
    // (PF mutually exclusive with KB save), while the RAG toggle row only
    // depends on the per-app library_search flag.
    if (window.SessionState && typeof window.SessionState.on === 'function') {
      ['message:added', 'messages:cleared', 'message:deleted', 'session:reset', 'session:new', 'app:changed']
        .forEach(function (ev) { window.SessionState.on(ev, updateSaveButtonAvailability); });
      window.SessionState.on('app:changed', updateRagToggleVisibility);
    }
    document.addEventListener('privacy:state-changed', updateSaveButtonAvailability);

    var browseBtn = document.getElementById('library-browse');
    if (browseBtn) browseBtn.onclick = openBrowseModal;

    var importBtn = document.getElementById('library-browse-import');
    if (importBtn) importBtn.onclick = triggerImportPicker;
    var importInput = document.getElementById('library-import-input');
    if (importInput) importInput.addEventListener('change', handleImportFileChange);

    var confirmBtn = document.getElementById('library-save-confirm');
    if (confirmBtn) confirmBtn.onclick = submitSave;

    var ragToggle = document.getElementById('library-rag-toggle');
    if (ragToggle) {
      ragToggle.onchange = function () {
        var on = ragToggle.checked;
        // Push the preference to localStorage *and* to the server so
        // the next session inherits the same default and the current
        // session reflects it immediately. The server handles the
        // first-message lock, so toggling here before the lock fires
        // is the user's last chance to change it.
        writeRagDefault(on);
        setRagToggle(on);
        // Refresh the header summary bar so its "Knowledge Base" badge
        // tracks the toggle immediately.
        if (typeof window.updateConfigSummary === 'function') window.updateConfigSummary();
      };
      // Apply the persisted default on first paint. We only push it
      // upstream when the user previously chose ON — pushing OFF would
      // be a no-op since OFF is the server's default anyway.
      if (readRagDefault() === 'on') {
        ragToggle.checked = true;
        setRagToggle(true);
      }
    }

    // Browse-modal controls
    var search = document.getElementById('library-browse-search');
    if (search) {
      search.addEventListener('input', function () {
        state.searchTerm = search.value || '';
        state.page = 0;
        applyFilters();
        renderBrowseTable();
      });
    }
    var scopeFilter = document.getElementById('library-browse-scope');
    if (scopeFilter) {
      scopeFilter.addEventListener('change', function () {
        state.scopeFilter = scopeFilter.value || 'all';
        state.page = 0;
        applyFilters();
        renderBrowseTable();
      });
    }
    var sortSel = document.getElementById('library-browse-sort');
    if (sortSel) {
      sortSel.addEventListener('change', function () {
        state.sortKey = sortSel.value || 'created_desc';
        state.page = 0;
        applyFilters();
        renderBrowseTable();
      });
    }
    var pageSel = document.getElementById('library-browse-pagesize');
    if (pageSel) {
      pageSel.addEventListener('change', function () {
        state.pageSize = parseInt(pageSel.value, 10) || 50;
        state.page = 0;
        applyFilters();
        renderBrowseTable();
      });
    }
    var prev = document.getElementById('library-browse-prev');
    if (prev) prev.onclick = function () {
      if (state.page > 0) { state.page -= 1; renderBrowseTable(); }
    };
    var next = document.getElementById('library-browse-next');
    if (next) next.onclick = function () {
      if (((state.page + 1) * state.pageSize) < state.filteredRows.length) {
        state.page += 1; renderBrowseTable();
      }
    };

    // Global click intercept: any markdown-rendered link of the form
    // <a href="mc:conv:abc-123"> becomes a viewer trigger instead of a
    // regular navigation. Handled at document level so it applies to
    // RAG citations rendered in any chat surface, not just the modals.
    document.addEventListener('click', function (ev) {
      var target = ev.target;
      while (target && target !== document) {
        if (target.tagName === 'A') {
          var href = target.getAttribute('href') || '';
          if (href.indexOf('mc:conv:') === 0) {
            ev.preventDefault();
            var convId = href.slice('mc:conv:'.length);
            if (convId) openViewerModal(convId);
            return;
          }
          break;
        }
        target = target.parentNode;
      }
    });

    // Viewer-modal action buttons (delete / toggle scope)
    var viewerDelete = document.getElementById('library-viewer-delete');
    if (viewerDelete) viewerDelete.onclick = function () {
      if (state.selectedId) {
        confirmAndDelete(state.selectedId);
        closeViewerModalIfOpen();
      }
    };
    var viewerToggle = document.getElementById('library-viewer-toggle-scope');
    if (viewerToggle) viewerToggle.onclick = function () {
      if (!state.selectedId) return;
      var nextScope = viewerToggle.getAttribute('data-next-scope');
      if (!nextScope) return; // disabled when there's no current app context
      setScopeApp(state.selectedId, nextScope);
    };

    var renameBtn = document.getElementById('library-viewer-rename');
    if (renameBtn) renameBtn.onclick = openRenameEditor;
    var renameSave = document.getElementById('library-viewer-rename-save');
    if (renameSave) renameSave.onclick = submitRename;
    var renameCancel = document.getElementById('library-viewer-rename-cancel');
    if (renameCancel) renameCancel.onclick = closeRenameEditor;
    var renameInput = document.getElementById('library-viewer-rename-input');
    if (renameInput) {
      renameInput.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter') {
          // Suppress Enter while an IME (Japanese/Chinese/Korean) is
          // composing — that Enter belongs to the IME confirming a
          // candidate, not to "submit the rename". Without this guard,
          // typing Japanese in the title would auto-save the moment
          // the user accepts a kana→kanji conversion.
          //   - ev.isComposing: standards-compliant flag
          //   - ev.keyCode === 229: legacy fallback (older Safari/IE)
          if (ev.isComposing || ev.keyCode === 229) return;
          ev.preventDefault(); ev.stopPropagation(); submitRename();
        }
        if (ev.key === 'Escape') {
          // stopPropagation so Bootstrap's modal ESC handler does not
          // also fire and close the Viewer when the user only meant to
          // dismiss the inline rename editor.
          if (ev.isComposing || ev.keyCode === 229) return;
          ev.preventDefault(); ev.stopPropagation(); closeRenameEditor();
        }
      });
    }

    // When the Viewer was opened from Browse, re-open Browse after the
    // user dismisses the Viewer (ESC, Close button, or backdrop click).
    // This restores the navigation context the user came from.
    var viewerModalEl = document.getElementById('libraryViewerModal');
    if (viewerModalEl) {
      viewerModalEl.addEventListener('hidden.bs.modal', function () {
        if (!state.viewerOpenedFromBrowse) return;
        state.viewerOpenedFromBrowse = false;
        var browseEl = document.getElementById('libraryBrowseModal');
        if (browseEl && typeof window.bootstrap !== 'undefined' && window.bootstrap.Modal) {
          window.bootstrap.Modal.getOrCreateInstance(browseEl).show();
        }
      });
    }

    // Tie the per-session conversation_id binding to the SessionState
    // lifecycle. Reset / new session / app switch all start a different
    // logical conversation, so the next Save should create a fresh KB
    // entry instead of replacing the previous one.
    if (window.SessionState && typeof window.SessionState.on === 'function') {
      window.SessionState.on('session:reset', clearCurrentConversation);
      window.SessionState.on('session:new', clearCurrentConversation);
      window.SessionState.on('app:changed', clearCurrentConversation);
    }
  }

  window.libraryPanel = {
    init: init,
    send: send,
    requestList: requestList,
    requestStats: requestStats,
    requestRagState: requestRagState,
    setRagToggle: setRagToggle,
    setScopeApp: setScopeApp,
    deleteConversation: deleteConversation,
    openSaveModal: openSaveModal,
    submitSave: submitSave,
    buildSavePayload: buildSavePayload,
    readModalSelections: readModalSelections,
    uploadLibraryFile: uploadLibraryFile,
    triggerImportPicker: triggerImportPicker,
    openRenameEditor: openRenameEditor,
    closeRenameEditor: closeRenameEditor,
    submitRename: submitRename,
    handleRenamedMessage: handleRenamedMessage,
    openBrowseModal: openBrowseModal,
    openDetailModal: openDetailModal,
    applyFilters: applyFilters,
    handleConversations: handleConversations,
    handleStats: handleStats,
    handleDeleted: handleDeleted,
    handleDeletedMessage: handleDeletedMessage,
    handleSavedMessage: handleSavedMessage,
    clearCurrentConversation: clearCurrentConversation,
    handleRagState: handleRagState,
    handleTitleSuggested: handleTitleSuggested,
    handleScopeUpdated: handleScopeUpdated,
    handleConversationData: handleConversationData,
    openViewerModal: openViewerModal,
    renderViewerMessages: renderViewerMessages,
    render: render,
    compactRowMarkup: compactRowMarkup,
    browseRowMarkup: browseRowMarkup,
    privacyBadgeHtml: privacyBadgeHtml,
    rowLikelyHasPii: rowLikelyHasPii,
    isCurrentAppKbSaveEligible: isCurrentAppKbSaveEligible,
    isCurrentAppKbRetrievalEligible: isCurrentAppKbRetrievalEligible,
    updateSaveButtonAvailability: updateSaveButtonAvailability,
    updateRagToggleVisibility: updateRagToggleVisibility,
    relativeTime: relativeTime,
    truncate: truncate,
    formatStats: formatStats,
    escapeHtml: escapeHtml,
    scopeBadge: scopeBadge,
    scopeDot: scopeDot,
    formatScopeApp: formatScopeApp,
    typeIconHtml: typeIconHtml,
    _state: state
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.libraryPanel;
  }
})();
