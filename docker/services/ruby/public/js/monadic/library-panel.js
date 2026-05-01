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
    filteredRows: [],       // after applying search/visibility filter
    page: 0,                // 0-indexed page in browse modal
    pageSize: 50,
    sortKey: 'created_desc',
    visibilityFilter: 'all',
    searchTerm: '',
    selectedId: null,       // for detail modal
    viewerOpenedFromBrowse: false  // re-open Browse after Viewer closes
  };

  var SIDEBAR_RECENT_LIMIT = 5;

  // ─── Sending ─────────────────────────────────────────────────────────

  function send(message, payload) {
    if (typeof window.ws === 'undefined' || !window.ws) return false;
    var body = Object.assign({ message: message }, payload || {});
    try {
      window.ws.send(JSON.stringify(body));
      return true;
    } catch (e) {
      return false;
    }
  }

  function requestList() { return send('LIBRARY_LIST'); }
  function requestStats() { return send('LIBRARY_STATS'); }
  function requestRagState() { return send('LIBRARY_RAG_QUERY'); }
  function setRagToggle(enabled) {
    return send('LIBRARY_RAG_TOGGLE', { contents: { enabled: !!enabled } });
  }
  function setVisibility(conversationId, visibility) {
    return send('LIBRARY_TOGGLE_VISIBILITY', {
      contents: { conversation_id: conversationId, visibility: visibility }
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

  function visibilityBadge(visibility) {
    var v = (visibility || '').toLowerCase();
    // Bootstrap 5.3 subtle/emphasis variants give a pastel pill (soft
    // background with darker text) that reads as a tag rather than a
    // status alert. Older sibling tests still match the substring
    // "bg-success" / "bg-secondary" so they remain valid.
    var cls = v === 'shareable'
      ? 'badge bg-success-subtle text-success-emphasis'
      : 'badge bg-secondary-subtle text-secondary-emphasis';
    return '<span class="' + cls + '">' + escapeHtml(v || 'unknown') + '</span>';
  }

  // Map a content_type token to a FontAwesome icon class plus a colour
  // tone. The Library currently stores "conversation" plus the
  // file-import content_types (markdown / code / pdf / document) added
  // in Phase 1c. The Browse modal renders a single icon per row using
  // this mapping plus a tooltip carrying the readable type name.
  // Sub-formats of "document" (docx / xlsx / pptx) are detected via
  // the `topics` array.
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

  // Compact colored dot used in sidebar rows where horizontal space is tight.
  function visibilityDot(visibility) {
    var v = (visibility || '').toLowerCase();
    var color = v === 'shareable' ? '#198754' : '#6c757d';
    var label = v || 'unknown';
    return '<span class="library-vis-dot d-inline-block rounded-circle me-1" '
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

  // Sidebar markup: 1-line. Title + visibility dot + turns + relative time.
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
      +   visibilityDot(row.visibility)
      +   '<span class="flex-grow-1 text-truncate me-2">' + escapeHtml(truncate(title, 40)) + '</span>'
      +   '<span class="text-secondary text-nowrap">' + turns + 'T · ' + escapeHtml(rel) + '</span>'
      + '</div>'
    );
  }

  // Browse-modal row: full table row with three inline icon-only buttons
  // on the right (details / toggle visibility / delete). The modal is wide
  // enough that a popover dropdown adds clicks without saving space, so we
  // expose the actions directly instead.
  function browseRowMarkup(row, idx) {
    var convId = escapeHtml(row.conversation_id || '');
    var title = row.title && row.title.length > 0 ? row.title : '(untitled)';
    var turns = (typeof row.turns_count === 'number') ? row.turns_count : '?';
    var rel = relativeTime(row.created_at);
    var visLower = (row.visibility || '').toLowerCase();
    var toggleLabel = visLower === 'shareable'
      ? t('ui.libMakePersonal', 'Make personal')
      : t('ui.libMakeShareable', 'Make shareable');
    var nextVis = visLower === 'shareable' ? 'personal' : 'shareable';
    var detailLabel = t('ui.libViewDetails', 'View details');
    var deleteLabel = t('ui.libDelete', 'Delete');
    return (
      '<tr data-conversation-id="' + convId + '" data-row-index="' + idx + '">'
      +   '<td class="text-center">' + typeIconHtml(row.content_type, row.topics) + '</td>'
      +   '<td>'
      +     '<div class="fw-medium text-truncate" style="max-width: 380px; color: #374151;">' + escapeHtml(truncate(title, 80)) + '</div>'
      +     '<div class="text-secondary small text-truncate" style="max-width: 380px;">' + escapeHtml(row.source || '') + (row.language ? ' · ' + escapeHtml(row.language) : '') + '</div>'
      +   '</td>'
      +   '<td>' + visibilityBadge(row.visibility) + '</td>'
      +   '<td class="text-end small">' + turns + '</td>'
      +   '<td class="text-nowrap small text-secondary">' + escapeHtml(rel) + '</td>'
      +   '<td class="text-end text-nowrap">'
      +     '<button type="button" class="btn btn-sm btn-outline-secondary me-1 library-action-detail" '
      +       'title="' + escapeHtml(detailLabel) + '" aria-label="' + escapeHtml(detailLabel) + '">'
      +       '<i class="fa-solid fa-circle-info"></i>'
      +     '</button>'
      +     '<button type="button" class="btn btn-sm btn-outline-secondary me-1 library-action-toggle" '
      +       'data-next-vis="' + nextVis + '" '
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
    if (state.visibilityFilter !== 'all') {
      rows = rows.filter(function (r) { return (r.visibility || '').toLowerCase() === state.visibilityFilter; });
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
    renderBrowseTable();
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
      if (toggleLink) {
        toggleLink.addEventListener('click', function (e) {
          e.preventDefault();
          var nextVis = toggleLink.getAttribute('data-next-vis') || 'shareable';
          setVisibility(convId, nextVis);
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
  // (delete / toggle visibility), and verbatim messages all in one
  // surface. This keeps the user from juggling two modals when reading a
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
    var vis = (row.visibility || '').toLowerCase();
    var visClass = vis === 'shareable'
      ? 'badge bg-success-subtle text-success-emphasis'
      : 'badge bg-secondary-subtle text-secondary-emphasis';
    return bits.join(' · ')
      + ' <span class="' + visClass + ' ms-2">' + escapeHtml(vis || 'unknown') + '</span>';
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

    var toggleBtn = viewerEl('library-viewer-toggle-vis');
    var toggleLabel = viewerEl('library-viewer-toggle-label');
    if (row) {
      var visLower = (row.visibility || '').toLowerCase();
      if (toggleBtn) toggleBtn.setAttribute('data-next-vis',
        visLower === 'shareable' ? 'personal' : 'shareable');
      if (toggleLabel) {
        toggleLabel.textContent = visLower === 'shareable'
          ? t('ui.libMakePersonal', 'Make personal')
          : t('ui.libMakeShareable', 'Make shareable');
      }
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
      }
    }
    requestList();
    requestStats();
  }

  function handleSavedMessage(data) {
    if (!data) return;
    setSavePending(false);
    if (data.res === 'success') {
      requestList();
      requestStats();
      var modalEl = (typeof document !== 'undefined') ? document.getElementById('librarySaveModal') : null;
      if (modalEl && typeof window.bootstrap !== 'undefined' && window.bootstrap.Modal) {
        var inst = window.bootstrap.Modal.getInstance(modalEl);
        if (inst) inst.hide();
      }
      var label = t('ui.libSaveSuccess', 'Saved to Knowledge Base.');
      flashAlert("<i class='fa-solid fa-circle-check'></i> " + escapeHtml(label), 'success');
    } else {
      var msg = (data && data.content) ? data.content : 'Save failed';
      var prefix = t('ui.libSaveFailure', 'Failed to save');
      flashAlert(
        "<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(prefix) + ': ' + escapeHtml(msg),
        'warning'
      );
    }
  }

  function handleRagState(data) {
    var el = (typeof document !== 'undefined') ? document.getElementById('library-rag-toggle') : null;
    if (!el) return;
    var enabled = !!(data && data.enabled);
    if (el.checked !== enabled) el.checked = enabled;
  }

  function handleVisibilityUpdated(data) {
    if (!data) return;
    if (data.res === 'success') {
      var convId = data.conversation_id;
      var visibility = data.visibility;
      state.allRows.forEach(function (r) {
        if (r.conversation_id === convId) r.visibility = visibility;
      });
      rerenderAll();
      // Refresh stats so personal/shareable counters update.
      requestStats();
      // If the Viewer is showing this conversation, refresh metadata
      // and toggle-button label only (no re-fetch — messages did not
      // change). This avoids the loading flicker of a full modal reopen.
      if (state.selectedId === convId) {
        var row = state.allRows.find(function (r) { return r.conversation_id === convId; });
        if (row) {
          var metaEl = viewerEl('library-viewer-meta');
          if (metaEl) metaEl.innerHTML = viewerMetaLine(row);
          var toggleBtn = viewerEl('library-viewer-toggle-vis');
          var toggleLabel = viewerEl('library-viewer-toggle-label');
          var visLower = (row.visibility || '').toLowerCase();
          if (toggleBtn) toggleBtn.setAttribute('data-next-vis',
            visLower === 'shareable' ? 'personal' : 'shareable');
          if (toggleLabel) {
            toggleLabel.textContent = visLower === 'shareable'
              ? t('ui.libMakePersonal', 'Make personal')
              : t('ui.libMakeShareable', 'Make shareable');
          }
        }
      }
      flashAlert(
        "<i class='fa-solid fa-circle-check'></i> " + escapeHtml(t('ui.libVisibilityUpdated', 'Visibility updated.')),
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
    var personal = stats.conversations_personal || 0;
    var shareable = stats.conversations_shareable || 0;
    return 'Knowledge Base: ' + total + ' total ('
      + personal + ' personal, ' + shareable + ' shareable)';
  }

  // ─── Save modal helpers (unchanged from prior iteration) ─────────────

  function setSavePending(pending) {
    if (typeof document === 'undefined') return;
    var btn = document.getElementById('library-save-confirm');
    var cancelBtn = document.querySelector('#librarySaveModal [data-bs-dismiss="modal"]');
    var titleInput = document.getElementById('library-save-title');
    var radios = document.querySelectorAll('input[name="librarySaveVisibility"]');
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
    var modalEl = document.getElementById('librarySaveModal');
    if (!modalEl) return;

    var titleInput = document.getElementById('library-save-title');
    if (titleInput) {
      titleInput.value = '';
      titleInput.placeholder = currentAppName() || '';
    }
    var pers = document.getElementById('library-vis-personal');
    if (pers) pers.checked = true;

    var note = document.getElementById('library-save-privacy-note');
    if (note) note.style.display = privacyOn() ? '' : 'none';

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
      parameters: params,
      visibility: opts.visibility || 'personal'
    };
    if (opts.title && String(opts.title).trim().length > 0) {
      payload.title = String(opts.title).trim();
    }
    if (opts.monadicState && typeof opts.monadicState === 'object') {
      payload.monadic_state = opts.monadicState;
    }
    return payload;
  }

  function readModalSelections() {
    var titleEl = document.getElementById('library-save-title');
    var title = (titleEl && titleEl.value) ? titleEl.value : '';
    var visEl = document.querySelector('input[name="librarySaveVisibility"]:checked');
    var visibility = (visEl && visEl.value) ? visEl.value : 'personal';
    return { title: title, visibility: visibility };
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
        title: sel.title, visibility: sel.visibility, monadicState: state2
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

  // POST a single file to /library/import and refresh the panel on
  // success. The endpoint dispatches to the right importer based on file
  // extension (FileImporter.build_conversation on the Ruby side).
  function uploadLibraryFile(file, options) {
    if (!file) return Promise.reject(new Error('No file selected'));
    options = options || {};

    var formData = new FormData();
    formData.append('libraryFile', file);
    if (options.title) formData.append('libraryTitle', options.title);
    if (options.visibility) formData.append('libraryVisibility', options.visibility);
    if (options.license) formData.append('libraryLicense', options.license);

    setImportPending(true);
    flashAlert(
      "<i class='fas fa-spinner fa-spin'></i> " +
        escapeHtml(t('ui.libImportingMessage', 'Importing file into Knowledge Base...')),
      'info'
    );

    // Cap upload + extraction at 5 minutes — pymupdf4llm can be slow on
    // very large PDFs, but a runaway request shouldn't lock the UI.
    var controller = new AbortController();
    var timer = setTimeout(function () { controller.abort(); }, 300000);

    return fetch('/library/import', {
      method: 'POST', body: formData, signal: controller.signal
    })
      .then(function (res) {
        clearTimeout(timer);
        return res.json().then(function (data) { return { ok: res.ok, data: data }; });
      })
      .then(function (out) {
        setImportPending(false);
        if (!out.ok || !out.data || out.data.success === false) {
          var err = (out.data && (out.data.message || out.data.error)) || ('HTTP ' + (out.ok ? 'parse' : 'upload') + ' error');
          flashAlert(
            "<i class='fa-solid fa-triangle-exclamation'></i> " +
              escapeHtml(t('ui.libImportFailure', 'Failed to import')) + ': ' + escapeHtml(err),
            'warning'
          );
          return out.data;
        }
        flashAlert(
          "<i class='fa-solid fa-circle-check'></i> " +
            escapeHtml(t('ui.libImportSuccess', 'Imported to Knowledge Base') + ': ' + (out.data.filename || file.name)),
          'success'
        );
        requestList();
        requestStats();
        return out.data;
      })
      .catch(function (err) {
        clearTimeout(timer);
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

  function init() {
    if (typeof document === 'undefined') return;

    var saveBtn = document.getElementById('library-save');
    if (saveBtn) saveBtn.onclick = openSaveModal;

    var browseBtn = document.getElementById('library-browse');
    if (browseBtn) browseBtn.onclick = openBrowseModal;

    var importBtn = document.getElementById('library-browse-import');
    if (importBtn) importBtn.onclick = triggerImportPicker;
    var importInput = document.getElementById('library-import-input');
    if (importInput) importInput.addEventListener('change', handleImportFileChange);

    var confirmBtn = document.getElementById('library-save-confirm');
    if (confirmBtn) confirmBtn.onclick = submitSave;

    var ragToggle = document.getElementById('library-rag-toggle');
    if (ragToggle) ragToggle.onchange = function () { setRagToggle(ragToggle.checked); };

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
    var visFilter = document.getElementById('library-browse-visibility');
    if (visFilter) {
      visFilter.addEventListener('change', function () {
        state.visibilityFilter = visFilter.value || 'all';
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

    // Viewer-modal action buttons (delete / toggle visibility)
    var viewerDelete = document.getElementById('library-viewer-delete');
    if (viewerDelete) viewerDelete.onclick = function () {
      if (state.selectedId) {
        confirmAndDelete(state.selectedId);
        closeViewerModalIfOpen();
      }
    };
    var viewerToggle = document.getElementById('library-viewer-toggle-vis');
    if (viewerToggle) viewerToggle.onclick = function () {
      if (!state.selectedId) return;
      var nextVis = viewerToggle.getAttribute('data-next-vis') || 'shareable';
      setVisibility(state.selectedId, nextVis);
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
          ev.preventDefault(); ev.stopPropagation(); submitRename();
        }
        if (ev.key === 'Escape') {
          // stopPropagation so Bootstrap's modal ESC handler does not
          // also fire and close the Viewer when the user only meant to
          // dismiss the inline rename editor.
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
  }

  window.libraryPanel = {
    init: init,
    send: send,
    requestList: requestList,
    requestStats: requestStats,
    requestRagState: requestRagState,
    setRagToggle: setRagToggle,
    setVisibility: setVisibility,
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
    handleRagState: handleRagState,
    handleVisibilityUpdated: handleVisibilityUpdated,
    handleConversationData: handleConversationData,
    openViewerModal: openViewerModal,
    renderViewerMessages: renderViewerMessages,
    render: render,
    compactRowMarkup: compactRowMarkup,
    browseRowMarkup: browseRowMarkup,
    relativeTime: relativeTime,
    truncate: truncate,
    formatStats: formatStats,
    escapeHtml: escapeHtml,
    visibilityBadge: visibilityBadge,
    visibilityDot: visibilityDot,
    typeIconHtml: typeIconHtml,
    _state: state
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.libraryPanel;
  }
})();
