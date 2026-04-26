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

  // ---- Block D.3: export dialog ---------------------------------------

  // Privacy is "active" when the indicator is currently visible (any non-OFF
  // state). Used by monadic.js #save handler to intercept the normal export.
  function isActive() {
    const el = findIndicator();
    return !!(el && el.style.display !== 'none');
  }

  function openExportDialog() {
    const modalEl = document.getElementById('privacyExportModal');
    if (!modalEl || !window.bootstrap || !window.bootstrap.Modal) return;
    resetExportDialog();
    window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
  }

  function resetExportDialog() {
    const enc = document.getElementById('privacyExportModeEncrypted');
    if (enc) enc.checked = true;
    const pass = document.getElementById('privacy-export-passphrase');
    const conf = document.getElementById('privacy-export-passphrase-confirm');
    if (pass) pass.value = '';
    if (conf) conf.value = '';
    setExportStatus('');
    updateExportModeUI('encrypted');
    updateStrengthMeter('');
  }

  // Inline strength scoring (Phase 2.1 minimum viable; replace with
  // zxcvbn in Phase 2.2 if richer scoring is needed).
  // Score 0-4 based on length and character class diversity.
  function scorePassphrase(pw) {
    if (!pw) return { score: 0, label: 'Enter a passphrase' };
    if (pw.length < 8) return { score: 0, label: 'Too short (need ≥ 8 chars)' };
    let classes = 0;
    if (/[a-z]/.test(pw)) classes++;
    if (/[A-Z]/.test(pw)) classes++;
    if (/[0-9]/.test(pw)) classes++;
    if (/[^a-zA-Z0-9]/.test(pw)) classes++;
    let score;
    if (pw.length >= 16 && classes >= 3) score = 4;
    else if (pw.length >= 12 && classes >= 3) score = 3;
    else if (pw.length >= 12 || classes >= 3) score = 2;
    else if (pw.length >= 10 || classes >= 2) score = 1;
    else score = 0;
    const labels = ['Very weak', 'Weak', 'Fair', 'Good', 'Strong'];
    return { score: score, label: labels[score] };
  }

  function updateStrengthMeter(pw) {
    const bar = document.querySelector('.privacy-strength-bar');
    const label = document.getElementById('privacy-strength-label');
    if (!bar || !label) return;
    const { score, label: text } = scorePassphrase(pw);
    bar.className = 'privacy-strength-bar score-' + score;
    label.textContent = text;
    label.className = score >= 3 ? 'text-success' : (score >= 2 ? 'text-warning' : 'text-danger');
  }

  function updateExportModeUI(mode) {
    const passSection = document.getElementById('privacy-export-pass-section');
    const restoredWarn = document.getElementById('privacy-export-restored-warning');
    const continueBtn = document.getElementById('privacy-export-continue');
    if (!passSection || !restoredWarn || !continueBtn) return;

    if (mode === 'encrypted') {
      passSection.style.display = '';
      restoredWarn.style.display = 'none';
      // Continue enabled only if passphrase is strong enough AND matches
      checkContinueEnabled();
    } else if (mode === 'restored') {
      passSection.style.display = 'none';
      restoredWarn.style.display = '';
      continueBtn.disabled = false;
    } else {
      passSection.style.display = 'none';
      restoredWarn.style.display = 'none';
      continueBtn.disabled = false;
    }
  }

  function checkContinueEnabled() {
    const continueBtn = document.getElementById('privacy-export-continue');
    if (!continueBtn) return;
    const mode = currentMode();
    if (mode !== 'encrypted') {
      continueBtn.disabled = false;
      return;
    }
    const pass = (document.getElementById('privacy-export-passphrase') || {}).value || '';
    const conf = (document.getElementById('privacy-export-passphrase-confirm') || {}).value || '';
    const { score } = scorePassphrase(pass);
    continueBtn.disabled = !(score >= 3 && pass === conf && pass.length > 0);
  }

  function currentMode() {
    const checked = document.querySelector('input[name="privacyExportMode"]:checked');
    return checked ? checked.value : 'encrypted';
  }

  function setExportStatus(msg, klass) {
    const status = document.getElementById('privacy-export-status');
    if (!status) return;
    status.textContent = msg || '';
    status.className = 'small mt-2 ' + (klass || 'text-muted');
  }

  function sendExport() {
    if (typeof window.ws === 'undefined' || !window.ws) return;
    const mode = currentMode();
    const payload = { message: 'PRIVACY_EXPORT', mode: mode };
    if (mode === 'encrypted') {
      payload.passphrase = (document.getElementById('privacy-export-passphrase') || {}).value || '';
    }
    setExportStatus('Preparing export...', 'text-muted');
    window.ws.send(JSON.stringify(payload));
  }

  function handleExportData(data) {
    if (!data || !data.content_base64) return;
    try {
      const binary = atob(data.content_base64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      const blob = new Blob([bytes], { type: data.mime || 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = data.filename || 'monadic-export.json';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(function () { URL.revokeObjectURL(url); }, 5000);
      setExportStatus('Downloaded: ' + a.download, 'text-success');
      // Auto-close after a brief delay so the user sees the success message
      setTimeout(function () {
        const modalEl = document.getElementById('privacyExportModal');
        if (modalEl && window.bootstrap && window.bootstrap.Modal) {
          window.bootstrap.Modal.getInstance(modalEl)?.hide();
        }
      }, 800);
    } catch (e) {
      setExportStatus('Download failed: ' + e.message, 'text-danger');
    }
  }

  function handleExportError(data) {
    const detail = (data && (data.detail || data.error)) || 'unknown error';
    setExportStatus('Export error: ' + detail, 'text-danger');
  }

  // Wire dialog interactions (document-level delegation, idempotent).
  document.addEventListener('change', function (ev) {
    if (ev.target && ev.target.name === 'privacyExportMode') {
      updateExportModeUI(ev.target.value);
    }
  });
  document.addEventListener('input', function (ev) {
    if (ev.target && (ev.target.id === 'privacy-export-passphrase' || ev.target.id === 'privacy-export-passphrase-confirm')) {
      if (ev.target.id === 'privacy-export-passphrase') {
        updateStrengthMeter(ev.target.value);
      }
      checkContinueEnabled();
    }
  });
  document.addEventListener('click', function (ev) {
    if (ev.target && ev.target.id === 'privacy-export-continue') {
      sendExport();
    }
    if (ev.target && (ev.target.id === 'privacy-registry-export-btn' || ev.target.closest('#privacy-registry-export-btn'))) {
      // Close registry modal first, then open export dialog.
      const regEl = document.getElementById('privacyRegistryModal');
      if (regEl && window.bootstrap && window.bootstrap.Modal) {
        window.bootstrap.Modal.getInstance(regEl)?.hide();
      }
      setTimeout(openExportDialog, 250);
    }
  });

  window.WsPrivacyHandler = {
    handleState: handleState,
    handleRegistry: handleRegistry,
    openRegistryModal: openRegistryModal,
    isActive: isActive,
    openExportDialog: openExportDialog,
    handleExportData: handleExportData,
    handleExportError: handleExportError
  };
})();
