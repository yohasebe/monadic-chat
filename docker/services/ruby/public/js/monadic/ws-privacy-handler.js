// Privacy Filter UI handler.
// Listens for "privacy_state" WebSocket messages from the server and updates
// the indicator in the chat header. Four visual states:
//   OFF        — privacy not enabled for this app (indicator hidden)
//   ready      — enabled, registry empty (gray unlock icon)
//   active(N)  — enabled, N entries in registry (green lock + count)
//   error      — backend reachable failure (red triangle)

(function () {
  function findIndicator() {
    return document.getElementById('privacy-indicator');
  }

  function setVisualState(el, kind, label, title) {
    el.style.display = '';
    el.className = 'privacy-indicator privacy-' + kind;
    el.innerHTML = label;
    if (title) {
      el.setAttribute('title', title);
    } else {
      el.removeAttribute('title');
    }
  }

  function handleState(data) {
    const el = findIndicator();
    if (!el) return;

    if (!data || !data.enabled) {
      el.style.display = 'none';
      el.removeAttribute('title');
      el.innerHTML = '';
      return;
    }

    if (data.error) {
      setVisualState(
        el,
        'error',
        '<i class="fas fa-exclamation-triangle"></i> Privacy error',
        String(data.error).substring(0, 200)
      );
      return;
    }

    const count = Number(data.registry_count) || 0;
    if (count === 0) {
      setVisualState(
        el,
        'ready',
        '<i class="fas fa-unlock"></i> Privacy ready',
        'Privacy Filter is enabled. No PII detected yet.'
      );
    } else {
      setVisualState(
        el,
        'active',
        '<i class="fas fa-lock"></i> Privacy ON (' + count + ')',
        count + ' placeholder' + (count === 1 ? '' : 's') + ' currently masked'
      );
    }
  }

  window.WsPrivacyHandler = { handleState: handleState };
})();
