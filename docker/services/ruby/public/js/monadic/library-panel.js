// frozen-by-convention; module-pattern, no globals beyond window.libraryPanel
//
// Library (Knowledge Base) sidebar panel renderer.
//
// Responsibilities:
//   - Send LIBRARY_LIST / LIBRARY_DELETE / LIBRARY_STATS WebSocket messages.
//   - Receive library_conversations / library_deleted / library_stats and
//     render conversation rows + delete buttons into a designated DOM
//     container.
//
// In Phase 1a this panel is mounted only when the host page exposes the
// expected container element (#library-panel). Phase 1b will wire it
// into the main sidebar alongside conversation persistence + RAG toggle.
//
// Public API:
//   window.libraryPanel.send(message, payload?) - send a WS message
//   window.libraryPanel.render(container, rows) - render rows into DOM
//   window.libraryPanel.handleDeleted(data, container) - refresh after delete
//   window.libraryPanel.formatStats(stats) - convert stats hash to text
(function () {
  'use strict';

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
    var cls = v === 'shareable' ? 'badge bg-success' : 'badge bg-secondary';
    return '<span class="' + cls + '">' + escapeHtml(v || 'unknown') + '</span>';
  }

  function rowMarkup(row, idx) {
    var title = row.title && row.title.length > 0 ? row.title : '(untitled)';
    var meta = [];
    if (row.source) meta.push('source=' + row.source);
    if (row.language) meta.push('lang=' + row.language);
    if (typeof row.turns_count === 'number') meta.push('turns=' + row.turns_count);
    if (typeof row.messages_count === 'number') meta.push('msgs=' + row.messages_count);
    var convId = escapeHtml(row.conversation_id || '');
    return (
      '<div class="library-row d-flex align-items-start justify-content-between py-1 border-bottom" '
        + 'data-conversation-id="' + convId + '">'
      +   '<div class="library-row-info flex-grow-1 me-2">'
      +     '<div class="library-row-title">' + escapeHtml(title) + ' '
      +       visibilityBadge(row.visibility)
      +     '</div>'
      +     '<div class="library-row-meta text-secondary small">'
      +       'id=' + convId + (meta.length ? ' · ' + escapeHtml(meta.join(' · ')) : '')
      +     '</div>'
      +   '</div>'
      +   '<button id="library-del-' + idx + '" type="button" '
      +     'class="btn btn-sm btn-outline-secondary library-row-delete" '
      +     'aria-label="Delete conversation">'
      +     '<i class="fa-regular fa-trash-can text-secondary"></i>'
      +   '</button>'
      + '</div>'
    );
  }

  // ─── Public renderers ────────────────────────────────────────────────

  // Render an inventory of conversations into a container element.
  // `rows` may be empty — we show a friendly empty-state message.
  // Each row's delete button gets an onclick that fires LIBRARY_DELETE.
  function render(container, rows) {
    if (!container) return;
    var safeRows = Array.isArray(rows) ? rows : [];
    if (safeRows.length === 0) {
      container.innerHTML =
        '<span class="text-secondary">The Knowledge Base is empty.</span>';
      return;
    }
    container.innerHTML = safeRows.map(rowMarkup).join('');

    safeRows.forEach(function (row, idx) {
      var btn = container.querySelector('#library-del-' + idx);
      if (!btn) return;
      btn.onclick = function () {
        var convId = row.conversation_id;
        var label = row.title || convId;
        var ok = window.confirm
          ? window.confirm('Permanently delete "' + label + '" from the Knowledge Base?')
          : true;
        if (ok) send('LIBRARY_DELETE', { contents: convId });
      };
    });
  }

  // After receiving 'library_deleted', request a refresh so the panel
  // reflects the post-delete state. Hosts that supply a container also
  // get the row removed optimistically for snappy UX.
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

  function formatStats(stats) {
    if (!stats || typeof stats !== 'object') return '';
    var total = stats.conversations_total || 0;
    var personal = stats.conversations_personal || 0;
    var shareable = stats.conversations_shareable || 0;
    return 'Knowledge Base: ' + total + ' total ('
      + personal + ' personal, ' + shareable + ' shareable)';
  }

  window.libraryPanel = {
    send: send,
    render: render,
    handleDeleted: handleDeleted,
    formatStats: formatStats,
    escapeHtml: escapeHtml,
    visibilityBadge: visibilityBadge
  };

  // CommonJS export for Jest.
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = window.libraryPanel;
  }
})();
