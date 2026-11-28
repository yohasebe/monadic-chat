// frozen-by-convention; module-pattern, no globals beyond window.libraryPanel
//
// The Library tab of the side column (#library-pane: search, sort, pages,
// open on the work screen, delete, import a file, put the chat's record on
// the work screen) and the Conversation Viewer. All actions go through the
// WebSocket; the list is the one `library_conversations` gives (every entry).
(function () {
  'use strict';

  // ─── Module state ────────────────────────────────────────────────────

  var state = {
    allRows: [],            // last received full inventory
    filteredRows: [],       // after applying the search
    page: 0,                // 0-indexed page in browse modal
    pageSize: 50,
    sortKey: 'created_desc',
    searchTerm: '',
    selectedId: null        // for detail modal
  };


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

  // Delegates to the canonical implementation in text-utils.js
  // (window.escapeHtml). Same semantics as the former local copy:
  // null/undefined → "", escapes & < > " '.
  function escapeHtml(value) {
    return window.escapeHtml(value == null ? '' : value);
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

  // Library tab row: full table row with three inline icon-only buttons
  // on the right (open on the work screen / details / delete).
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

  // Render the Privacy badge column. A heuristic catches entries whose title
  // / source obviously looks
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

  // An entry as a row, as the history lists chats: its kind, its title
  // (opening it on the work screen) over where it came from, its language,
  // turns and when it was kept, and a menu of what is done with it.
  function browseRowMarkup(row, idx) {
    var convId = escapeHtml(row.conversation_id || '');
    var title = row.title && row.title.length > 0 ? row.title : '(untitled)';
    var turns = (typeof row.turns_count === 'number') ? row.turns_count : '?';
    var rel = relativeTime(row.created_at);
    var privacyBadge = privacyBadgeHtml(row);
    var openLabel = t('ui.libOpenOnWorkScreen', 'Open on the work screen');
    var meta = [row.source || '', row.language || '', turns + ' ' + t('ui.libColTurns', 'Turns'), rel]
      .filter(function (part) { return String(part).length > 0; }).join(' · ');
    var actions = t('ui.libActionsOf', 'Actions for {title}').replace('{title}', truncate(title, 80));
    return (
      '<li class="sfp-row library-row" data-conversation-id="' + convId + '" data-row-index="' + idx + '">'
      +   '<span class="sfp-check sfp-check-none library-row-kind">' + typeIconHtml(row.content_type, row.topics) + '</span>'
      +   '<button type="button" class="sfp-name library-name" title="' + escapeHtml(openLabel) + '">'
      +     '<span class="sfp-text">'
      +       '<span class="sfp-label">' + (privacyBadge ? privacyBadge + ' ' : '') + escapeHtml(truncate(title, 80)) + '</span>'
      +       '<span class="sfp-meta">' + escapeHtml(meta) + '</span>'
      +     '</span>'
      +   '</button>'
      +   '<button type="button" class="btn btn-sm btn-icon sfp-row-menu library-row-menu" aria-haspopup="menu" aria-expanded="false" '
      +     'aria-label="' + escapeHtml(actions) + '"><i class="fa-solid fa-ellipsis" aria-hidden="true"></i></button>'
      + '</li>'
    );
  }

  // What is done with an entry, from its row's menu.
  function browseRowMenu(row, more) {
    if (!window.RowMenu || !row) return;
    var convId = row.conversation_id;
    var items = [
      { label: t('ui.libOpenOnWorkScreen', 'Open on the work screen'), icon: 'fa-solid fa-display',
        action: function () { if (window.Workbench && typeof window.Workbench.openLibrary === 'function') window.Workbench.openLibrary(convId); } }
    ];
    // A record of a chat that is still in the history: that chat goes on there.
    if (row.source_chat_resumable && row.source_chat_id) {
      items.push({ label: t('ui.libOpenSourceChat', 'Open the original chat'), icon: 'fa-solid fa-clock-rotate-left',
        action: function () { if (window.HistoryPanel && typeof window.HistoryPanel.resume === 'function') window.HistoryPanel.resume(row.source_chat_id); } });
    }
    items.push({ label: t('ui.libViewDetails', 'View details'), icon: 'fa-solid fa-circle-info',
      action: function () { openDetailModal(convId); } });
    items.push('divider');
    items.push({ label: t('ui.libDelete', 'Delete'), icon: 'fa-regular fa-trash-can', danger: true,
      action: function () { confirmAndDelete(convId); } });
    window.RowMenu.open(more, items);
  }

  // ─── Filtering / sorting / paging ────────────────────────────────────

  function applyFilters() {
    var rows = (state.allRows || []).slice();
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

  function browseTbody() {
    return (typeof document !== 'undefined') ? document.getElementById('library-browse-list') : null;
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
    renderBrowseTable();
  }

  // ─── Browse-row action wiring ────────────────────────────────────────

  function wireBrowseRowActions(scope) {
    if (!scope) return;
    scope.querySelectorAll('li[data-conversation-id]').forEach(function (li) {
      var convId = li.getAttribute('data-conversation-id');
      var row = (state.allRows || []).find(function (r) { return r.conversation_id === convId; });
      var name = li.querySelector('.library-name');
      if (name) {
        name.addEventListener('click', function (e) {
          e.preventDefault();
          if (window.Workbench && typeof window.Workbench.openLibrary === 'function') window.Workbench.openLibrary(convId);
        });
      }
      var more = li.querySelector('.library-row-menu');
      if (more) more.addEventListener('click', function () { browseRowMenu(row, more); });
    });
  }

  function confirmAndDelete(convId) {
    var row = state.allRows.find(function (r) { return r.conversation_id === convId; });
    var label = (row && row.title) ? row.title : convId;
    var prompt = t('ui.libDeleteConfirm', 'Permanently delete "{title}" from the Library?')
      .replace('{title}', label);
    var ok = window.confirm ? window.confirm(prompt) : true;
    if (ok) deleteConversation(convId);
  }

  // ─── Conversation Viewer modal ───────────────────────────────────────

  // Viewer subsumes the old "detail" modal: it shows metadata, actions
  // (delete), and verbatim messages all in one surface.
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
    return bits.join(' · ');
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
    var deleteBtn = viewerEl('library-viewer-delete');
    if (deleteBtn) deleteBtn.style.display = '';
    closeRenameEditor();
    var metaEl = viewerEl('library-viewer-meta');
    if (metaEl) metaEl.innerHTML = row ? viewerMetaLine(row) : '';
    var emptyEl = viewerEl('library-viewer-empty');
    if (emptyEl) emptyEl.style.display = 'none';
    var messagesEl = viewerEl('library-viewer-messages');
    if (messagesEl) messagesEl.innerHTML = '';

    setViewerLoading(true);

    // Fire the WS request — handleConversationData renders the body when
    // the server responds. We fall through to an empty state if the
    // record has no verbatim messages stored.
    send('LIBRARY_GET_CONVERSATION', { contents: { conversation_id: conversationId } });

    var viewer = dialogOf(viewerEl('libraryViewerModal'));
    if (viewer) viewer.open();
  }

  // A passage as it was read for a reply (its record), shown when its copy
  // on the work screen is gone: what the reply read, whatever the entry
  // holds now. Without a record of it, that it is no longer there.
  function showExcerpt(excerpt) {
    if (typeof document === 'undefined') return;
    state.selectedId = null;
    var text = excerpt && typeof excerpt.text === 'string' ? excerpt.text : '';
    var titleEl = viewerEl('library-viewer-title');
    if (titleEl) titleEl.textContent = (excerpt && excerpt.title) || '(untitled)';
    ['library-viewer-rename', 'library-viewer-delete'].forEach(function (id) {
      var el = viewerEl(id);
      if (el) el.style.display = 'none';
    });
    closeRenameEditor();
    setViewerLoading(false);
    var metaEl = viewerEl('library-viewer-meta');
    if (metaEl) metaEl.textContent = t('ui.libExcerptRecorded', 'The passage as it was read for this reply.');
    var emptyEl = viewerEl('library-viewer-empty');
    if (emptyEl) emptyEl.style.display = 'none';
    var messagesEl = viewerEl('library-viewer-messages');
    if (messagesEl) {
      messagesEl.innerHTML = '';
      if (text) renderMarkdownInto(text, messagesEl);
      else messagesEl.textContent = t('ui.libExcerptGone', 'This passage is no longer available.');
    }
    var viewer = dialogOf(viewerEl('libraryViewerModal'));
    if (viewer) viewer.open();
  }

  // Backwards-compat alias retained so older call sites and tests still
  // function. The viewer fully subsumes the old detail-only surface.
  function openDetailModal(conversationId) { return openViewerModal(conversationId); }

  function closeViewerModalIfOpen() {
    var viewer = dialogOf(viewerEl('libraryViewerModal'));
    if (viewer) viewer.close('done');
  }
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

  // ─── The Library tab of the side column ─────────────────────────────

  // Opens the Library tab (the side column shown) with a fresh list.
  function openBrowseModal() {
    requestList();

    if (typeof document === 'undefined') return;
    state.page = 0;
    rerenderAll();
    var lc = window.LayoutController;
    if (lc) {
      if (lc.isMenuHidden()) lc.setMenuHidden(false);
      lc.setPane('library');
    }
  }

  // ─── WebSocket message handlers ──────────────────────────────────────

  function handleConversations(data) {
    var rows = (data && Array.isArray(data.content)) ? data.content : [];
    state.allRows = rows;
    rerenderAll();
  }

  function handleDeletedMessage(data) {
    if (data && data.res === 'success') {
      var convId = data.conversation_id;
      if (convId) {
        state.allRows = state.allRows.filter(function (r) { return r.conversation_id !== convId; });
        rerenderAll();
      }
    } else {
      // Surface the failure instead of leaving the row in place with no
      // explanation (the click otherwise looks like it did nothing).
      var msg = (data && data.content) ? String(data.content) : 'Failed to delete the entry.';
      flashAlert("<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(msg), 'error');
    }
    requestList();
  }

  // ─── Save modal helpers (unchanged from prior iteration) ─────────────

  // The dialog (MonadicDialog) of an element, when there are both.
  function dialogOf(el) {
    return el && typeof window.MonadicDialog !== 'undefined' ? window.MonadicDialog.of(el) : null;
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
      return t('ui.libImportingMessage', 'Importing file into the Library...');
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
    if (options.license) formData.append('libraryLicense', options.license);

    var following = false;
    setImportPending(true);
    flashAlert(
      "<i class='fas fa-spinner fa-spin'></i> " +
        escapeHtml(t('ui.libImportingMessage', 'Importing file into the Library...')),
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
        following = true;
        return followImport(out.data.import_id, file.name);
      })
      .catch(function (err) {
        clearTimeout(postTimer);
        // followImport has said how it ended; a failure before it is said here.
        if (!following) {
          setImportPending(false);
          var msg = (err && err.message) ? err.message : 'Network error';
          flashAlert(
            "<i class='fa-solid fa-triangle-exclamation'></i> " +
              escapeHtml(t('ui.libImportFailure', 'Failed to import')) + ': ' + escapeHtml(msg),
            'warning'
          );
        }
        throw err;
      });
  }

  // Follows an import (its id) to its end, saying how it goes, and then
  // shows the Library as it is (an upload, or a document of the work
  // screen kept in the Library).
  function followImport(importId, filename) {
    setImportPending(true);
    return pollImportStatus(importId, function (entry) {
      flashAlert(
        "<i class='fas fa-spinner fa-spin'></i> " +
          escapeHtml(importStageMessage(entry.stage)) +
          ' (' + escapeHtml(entry.filename || filename) + ')',
        'info'
      );
    })
      .then(function (entry) {
        setImportPending(false);
        if (entry.leftover) {
          flashAlert("<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(t('ui.libUpdatePartial',
            'Updated the Library entry, but part of the earlier version could not be removed and may still appear.')), 'warning');
        } else {
          var done = entry.updated ? t('ui.libUpdateSuccess', 'Updated existing Library entry.')
            : t('ui.libImportSuccess', 'Imported to the Library') + ': ' + (entry.filename || filename);
          flashAlert("<i class='fa-solid fa-circle-check'></i> " + escapeHtml(done), 'success');
        }
        requestList();
            return entry;
      })
      .catch(function (err) {
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

  // ─── Keeping the conversation ────────────────────────────────────────

  // The chat as a document (the server writes it), put on the work screen
  // as a draft: the user keeps it in the Library from there.
  function draftConversation() {
    send('LIBRARY_CONVERSATION_DRAFT', {});
  }

  // The server put the record of the chat on its work screen (or says why
  // not): the work screen is shown, to keep it in the Library from there.
  var DRAFT_REASONS = {
    hides_words: ['ui.libDraftHidesWords', 'A chat that hides words cannot be kept in the Library.'],
    empty: ['ui.libDraftEmpty', 'There is nothing in this conversation to keep yet.'],
    not_saved_by_app: ['ui.workbench.toLibraryNotByApp', 'This app does not keep its conversations in the Library.']
  };
  function handleConversationDraft(data) {
    if (!data || !data.item_id) {
      var reason = data && DRAFT_REASONS[data.error];
      flashAlert("<i class='fa-solid fa-triangle-exclamation'></i> " + escapeHtml(reason
        ? t(reason[0], reason[1]) : t('ui.libDraftFailed', 'The conversation could not be put on the work screen.')), 'warning');
      return;
    }
    var lc = window.LayoutController;
    if (lc) lc.setPane('work');
    flashAlert("<i class='fa-solid fa-circle-info'></i> " +
      escapeHtml(t('ui.libDraftPut', 'The conversation is on the work screen as a document: keep it in the Library from there.')), 'info');
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

  // ─── DOM bootstrap ───────────────────────────────────────────────────

  // Drive the body capability classes from the SessionState `app:changed`
  // path: this function fans out the single SSOT entry point
  // (applyAppCapabilityClasses) to one more caller.
  function updateCapabilityClasses() {
    if (typeof window === 'undefined') return;
    if (typeof window.applyAppCapabilityClasses === 'function') {
      window.applyAppCapabilityClasses(currentAppName());
    }
  }

  function init() {
    if (typeof document === 'undefined') return;

    updateCapabilityClasses();
    if (window.SessionState && typeof window.SessionState.on === 'function') {
      window.SessionState.on('app:changed', updateCapabilityClasses);
    }

    var importBtn = document.getElementById('library-browse-import');
    if (importBtn) importBtn.onclick = triggerImportPicker;
    var importInput = document.getElementById('library-import-input');
    if (importInput) importInput.addEventListener('change', handleImportFileChange);

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
    var draftBtn = document.getElementById('library-draft-conversation');
    if (draftBtn) draftBtn.addEventListener('click', draftConversation);
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

    // Viewer-modal action button (delete)
    var viewerDelete = document.getElementById('library-viewer-delete');
    if (viewerDelete) viewerDelete.onclick = function () {
      if (state.selectedId) {
        confirmAndDelete(state.selectedId);
        closeViewerModalIfOpen();
      }
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
  }

  window.libraryPanel = {
    init: init,
    send: send,
    requestList: requestList,
    deleteConversation: deleteConversation,
    uploadLibraryFile: uploadLibraryFile,
    followImport: followImport,
    draftConversation: draftConversation,
    handleConversationDraft: handleConversationDraft,
    triggerImportPicker: triggerImportPicker,
    openRenameEditor: openRenameEditor,
    closeRenameEditor: closeRenameEditor,
    submitRename: submitRename,
    handleRenamedMessage: handleRenamedMessage,
    openBrowseModal: openBrowseModal,
    openDetailModal: openDetailModal,
    applyFilters: applyFilters,
    handleConversations: handleConversations,
    handleDeletedMessage: handleDeletedMessage,
    handleConversationData: handleConversationData,
    openViewerModal: openViewerModal,
    showExcerpt: showExcerpt,
    renderViewerMessages: renderViewerMessages,
    browseRowMarkup: browseRowMarkup,
    privacyBadgeHtml: privacyBadgeHtml,
    rowLikelyHasPii: rowLikelyHasPii,
    updateCapabilityClasses: updateCapabilityClasses,
    relativeTime: relativeTime,
    truncate: truncate,
    escapeHtml: escapeHtml,
    typeIconHtml: typeIconHtml,
    _state: state
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.libraryPanel;
  }
})();
