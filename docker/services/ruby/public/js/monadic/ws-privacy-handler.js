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
      el.style.cursor = 'default';
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
        'Privacy Filter is enabled. Click to view registry (currently empty).'
      );
    } else {
      setVisualState(
        el,
        'active',
        '<i class="fas fa-lock"></i> Privacy ON (' + count + ')',
        'Click to view ' + count + ' masked placeholder' + (count === 1 ? '' : 's')
      );
    }
    el.style.cursor = 'pointer';
  }

  function openRegistryModal() {
    if (typeof window.ws === 'undefined' || !window.ws) {
      console.warn('[Privacy] WebSocket not available');
      return;
    }
    // Show modal first so the user gets immediate feedback; populate on response.
    const modalEl = document.getElementById('privacyRegistryModal');
    if (!modalEl) return;
    if (window.bootstrap && window.bootstrap.Modal) {
      window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
    }
    window.ws.send(JSON.stringify({ message: 'PRIVACY_REGISTRY' }));
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function handleRegistry(data) {
    const tbody = document.querySelector('#privacy-registry-table tbody');
    const wrapper = document.getElementById('privacy-registry-table-wrapper');
    const empty = document.getElementById('privacy-registry-empty');
    if (!tbody || !wrapper || !empty) return;

    const entries = (data && Array.isArray(data.entries)) ? data.entries : [];
    if (entries.length === 0) {
      wrapper.style.display = 'none';
      empty.style.display = '';
      tbody.innerHTML = '';
      return;
    }
    empty.style.display = 'none';
    wrapper.style.display = '';
    tbody.innerHTML = entries.map(function (e) {
      return '<tr>'
        + '<td><code>' + escapeHtml(e.placeholder) + '</code></td>'
        + '<td>' + escapeHtml(e.original) + '</td>'
        + '<td><span class="badge bg-secondary">' + escapeHtml(e.type) + '</span></td>'
        + '</tr>';
    }).join('');
  }

  // Wire indicator click → modal open. Document-level delegation so the
  // listener survives re-renders of #privacy-indicator.
  document.addEventListener('click', function (ev) {
    const el = ev.target.closest && ev.target.closest('#privacy-indicator');
    if (!el) return;
    if (el.style.display === 'none') return;
    openRegistryModal();
  });

  window.WsPrivacyHandler = {
    handleState: handleState,
    handleRegistry: handleRegistry,
    openRegistryModal: openRegistryModal
  };
})();
