// Privacy Filter UI handler.
// Listens for "privacy_state" WebSocket messages from the server and updates
// the indicator in the chat header. Four visual states:
//   OFF        — privacy not enabled for this app (indicator hidden)
//   ready      — enabled, registry empty (gray unlock icon)
//   active(N)  — enabled, N entries in registry (green lock + count)
//   error      — backend reachable failure (red triangle)

(function () {
  // Last enabled state observed from a server-pushed `privacy_state` message.
  // Tracks the *toggle* state (Privacy ON regardless of registry count), not
  // the *active* state (registry has entries). Save-button hiding (CSS rule
  // `body.app-privacy-on #library-save`) needs the toggle, not the activity.
  var _lastEnabled = false;

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

  // When the server has auto-detected a conversation language and locked
  // the session to it, surface the language code so the user can see what
  // the privacy backend is actually using. We only render the badge when
  // a lock is in effect — for sidebar-selected languages the value is
  // already explicit in the dropdown and adding it here would be noise.
  function detectionBadge(detection) {
    if (!detection || detection.locked !== true) return '';
    var code = detection.language;
    if (!code) return '';
    var safe = escapeHtml(String(code));
    return ' <span class="privacy-lang-badge" title="Auto-detected language">'
      + '<i class="fas fa-language"></i> ' + safe
      + '</span>';
  }

  // Notify document-level listeners when the privacy state flips. Other
  // panels (e.g. library-panel.js) hide their controls when Privacy is
  // active, so they need a hook independent of SessionState events. The
  // current toggle state is carried in `event.detail.enabled` so listeners
  // can react without a second WsPrivacyHandler.isEnabled() call.
  function emitStateChanged() {
    try {
      document.dispatchEvent(new CustomEvent('privacy:state-changed', {
        detail: { enabled: _lastEnabled }
      }));
    } catch (_) { /* CustomEvent unavailable in some test envs */ }
  }

  function handleState(data) {
    _lastEnabled = !!(data && data.enabled);
    const el = findIndicator();
    if (!el) {
      emitStateChanged();
      return;
    }

    if (!data || !data.enabled) {
      // Reconciliation: the backend resets privacy to OFF on app change /
      // reset and pushes this privacy_state. If the user's toggle is still
      // ON (and editable), the intended state is ON — but the toggle was
      // restored programmatically (no `change` event) so it never re-armed
      // the backend. Without this the user must manually toggle off/on.
      // Re-assert ON once here. This fires *after* the backend reset, so it
      // is immune to the app-setup vs reset ordering race. Health-failure
      // rejections come back via privacy_toggle_ack (which unchecks the
      // toggle), so this cannot loop.
      const toggleEl = document.getElementById('check-privacy-session');
      if (toggleEl && toggleEl.checked && !toggleEl.disabled &&
          typeof window.safeWsSend === 'function') {
        window.safeWsSend({ message: 'PRIVACY_TOGGLE', enabled: true });
      }
      el.style.display = 'none';
      el.removeAttribute('title');
      el.innerHTML = '';
      el.style.cursor = 'default';
      emitStateChanged();
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

    const langBadge = detectionBadge(data.detection);
    const count = Number(data.registry_count) || 0;
    if (count === 0) {
      setVisualState(
        el,
        'ready',
        '<i class="fas fa-unlock"></i> Privacy ready' + langBadge,
        'Privacy Filter is enabled. Click to view registry (currently empty).'
      );
    } else {
      setVisualState(
        el,
        'active',
        '<i class="fas fa-lock"></i> Privacy ON (' + count + ')' + langBadge,
        'Click to view ' + count + ' masked placeholder' + (count === 1 ? '' : 's')
      );
    }
    el.style.cursor = 'pointer';
    emitStateChanged();
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
    // PRIVACY_REGISTRY is a pure read (idempotent, in default set);
    // user just clicked to open the registry modal so default failure
    // behavior — show "Reconnecting..." toast and queue, or alert on
    // hard failure — matches their intent to see the data.
    window.safeWsSend({ message: 'PRIVACY_REGISTRY' });
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // Dedicated reply for PRIVACY_TOGGLE round-trips. Carries the
  // backend-confirmed enabled state plus an error code on rejection
  // (e.g., privacy_container_unreachable). A separate event from
  // privacy_state means we never confuse a toggle reply with an
  // unrelated indicator update from app-change / reset / import.
  function handleToggleAck(data) {
    const toggleEl = document.getElementById('check-privacy-session');
    const desired = !!(data && data.enabled);

    if (data && data.error) {
      // Backend rejected — sync visual state to "off" and surface the
      // reason so the user understands why their toggle bounced back.
      if (toggleEl) toggleEl.checked = false;

      const msg = data.error === 'privacy_container_unreachable'
        ? 'Privacy container is not running. Try restarting the application.'
        : ('Privacy Filter error: ' + String(data.error).substring(0, 200));
      if (typeof window.setAlert === 'function') {
        window.setAlert(
          "<i class='fas fa-triangle-exclamation'></i> " + msg,
          'error'
        );
      } else {
        console.warn('[Privacy]', msg);
      }
      return;
    }

    if (toggleEl && toggleEl.checked !== desired) {
      toggleEl.checked = desired;
    }
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
        + '<td><span class="mc-badge mc-badge--grey">' + escapeHtml(e.type) + '</span></td>'
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

  // ---- Unified Export Dialog (2 orthogonal axes) ----------------------
  //
  // Encryption is always offered (encrypts the file at rest). The "content"
  // axis (restored vs masked placeholders) is only shown when the Privacy
  // Filter has produced registry entries in this session — otherwise there
  // is nothing to mask.

  // Privacy is "active" when the indicator is currently visible AND shows
  // a non-zero registry count. The indicator label format is
  // "Privacy ON (N)"; the regex extracts N.
  function isActive() {
    const el = findIndicator();
    if (!el || el.style.display === 'none') return false;
    const m = (el.textContent || '').match(/\((\d+)\)/);
    return !!(m && Number(m[1]) > 0);
  }

  function openExportDialog() {
    const modalEl = document.getElementById('privacyExportModal');
    if (!modalEl || !window.bootstrap || !window.bootstrap.Modal) return;
    resetExportDialog();
    window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
  }

  function resetExportDialog() {
    const encryptToggle = document.getElementById('export-encrypt-toggle');
    if (encryptToggle) encryptToggle.checked = false;
    const restored = document.getElementById('privacyExportContentRestored');
    const masked = document.getElementById('privacyExportContentMasked');
    // When the Privacy Filter is active in this session, default to
    // "masked" so the user does not accidentally write plaintext PII to
    // disk. The "restored" radio is still available for users who do
    // need the original values (e.g. backing up a personal notebook).
    // When Privacy is OFF, default to "restored" — there are no
    // placeholders to substitute anyway.
    const privacyOn = isActive();
    if (restored) restored.checked = !privacyOn;
    if (masked) masked.checked = privacyOn;
    const pass = document.getElementById('privacy-export-passphrase');
    const conf = document.getElementById('privacy-export-passphrase-confirm');
    if (pass) pass.value = '';
    if (conf) conf.value = '';
    // Show the content axis only when the privacy filter produced placeholders
    // in this session. Without entries, there is nothing meaningful to mask.
    const contentSection = document.getElementById('privacy-export-content-section');
    if (contentSection) contentSection.style.display = privacyOn ? '' : 'none';
    setExportStatus('');
    updateExportModeUI();
    updateStrengthMeter('');
  }

  // Inline passphrase strength scoring: 0-4 based on length and the
  // diversity of character classes (lower / upper / digit / symbol).
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

  function updateExportModeUI() {
    const passSection = document.getElementById('privacy-export-pass-section');
    const restoredWarn = document.getElementById('privacy-export-restored-warning');
    const continueBtn = document.getElementById('privacy-export-continue');
    if (!passSection || !restoredWarn || !continueBtn) return;

    const encrypt = isEncryptChecked();
    passSection.style.display = encrypt ? '' : 'none';

    // Three-tier warning depending on what actually leaves disk:
    //   encrypt ON                        → no warning (file is sealed)
    //   encrypt OFF + masked content      → no warning (no original PII present)
    //   encrypt OFF + restored content    → WARNING:
    //     - Privacy active:  red `alert-danger` ("PII export") because the
    //       user is overriding the safer default; the file will contain
    //       names, emails, phone numbers in plaintext.
    //     - Privacy inactive: yellow `alert-warning` (no registry entries
    //       so no tracked PII is being un-masked, but the file is still
    //       cleartext content).
    if (encrypt) {
      restoredWarn.style.display = 'none';
      restoredWarn.classList.remove('alert-danger');
      restoredWarn.classList.add('alert-warning');
      return checkContinueEnabled();
    }
    const isRestoredContent = (currentContent() === 'restored');
    if (!isRestoredContent) {
      restoredWarn.style.display = 'none';
      return checkContinueEnabled();
    }
    restoredWarn.style.display = '';
    const defaultBlock = document.getElementById('privacy-export-restored-warning-default');
    const strongBlock = document.getElementById('privacy-export-restored-warning-strong');
    if (isActive()) {
      // Strong warning: user picked the high-risk combination explicitly
      // (Privacy active + Restored + unencrypted).
      restoredWarn.classList.remove('alert-warning');
      restoredWarn.classList.add('alert-danger');
      if (defaultBlock) defaultBlock.style.display = 'none';
      if (strongBlock) strongBlock.style.display = '';
    } else {
      restoredWarn.classList.remove('alert-danger');
      restoredWarn.classList.add('alert-warning');
      if (defaultBlock) defaultBlock.style.display = '';
      if (strongBlock) strongBlock.style.display = 'none';
    }
    checkContinueEnabled();
  }

  function checkContinueEnabled() {
    const continueBtn = document.getElementById('privacy-export-continue');
    if (!continueBtn) return;
    if (!isEncryptChecked()) {
      // Plain export: always allowed (user has been warned via the alert box).
      continueBtn.disabled = false;
      return;
    }
    // Minimum bar: 8+ chars and confirm matches. The strength meter informs
    // the user about quality but does not block — Argon2id KDF makes
    // brute-forcing expensive even for shorter passphrases, and a stricter
    // gate pushes users toward the worse choice of "no encryption at all".
    const pass = (document.getElementById('privacy-export-passphrase') || {}).value || '';
    const conf = (document.getElementById('privacy-export-passphrase-confirm') || {}).value || '';
    continueBtn.disabled = !(pass.length >= 8 && pass === conf);
  }

  function isEncryptChecked() {
    const el = document.getElementById('export-encrypt-toggle');
    return !!(el && el.checked);
  }

  function currentContent() {
    const checked = document.querySelector('input[name="privacyExportContent"]:checked');
    return checked ? checked.value : 'restored';
  }

  function setExportStatus(msg, klass) {
    const status = document.getElementById('privacy-export-status');
    if (!status) return;
    status.textContent = msg || '';
    status.className = 'small mt-2 ' + (klass || 'text-muted');
  }

  function sendExport() {
    const encrypt = isEncryptChecked();
    const content = currentContent();
    const payload = {
      message: 'PRIVACY_EXPORT',
      encrypt: encrypt,
      content: content
    };
    if (encrypt) {
      payload.passphrase = (document.getElementById('privacy-export-passphrase') || {}).value || '';
    }
    setExportStatus('Preparing export...', 'text-muted');
    // PRIVACY_EXPORT is non-idempotent (server re-runs encryption +
    // streams a base64 blob; replay would re-do that work and emit a
    // second response the UI wouldn't expect). Default safeWsSend
    // behavior (fail-fast alert when WS is not OPEN) is the honest
    // outcome — strictly better than the prior silent `return` that
    // left "Preparing export..." stuck in the dialog.
    window.safeWsSend(payload);
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
    if (!ev.target) return;
    // Encryption toggle (always present)
    if (ev.target.id === 'export-encrypt-toggle') {
      updateExportModeUI();
    }
    // Content radio drives both the warning style/text (Restored escalates
    // to a red "PII export" alert when Privacy is active) and the
    // continue-button enable state.
    if (ev.target.name === 'privacyExportContent') {
      updateExportModeUI();
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

  // ---- Unmask highlight ------------------------------------------------
  //
  // After each turn the server ships the full registry as
  // `privacy_known_entities`. We walk every card in #discourse (user and
  // assistant alike) and wrap each occurrence of a tracked PII value in
  // a marker span. The walker is idempotent so passing the whole list on
  // every turn does not pile up wrappers — already-wrapped subtrees are
  // skipped.
  //
  // Matching is done by text content rather than by character offsets:
  // markdown rendering shifts offsets and computing them on the rendered
  // HTML is brittle. Substring search is unambiguous because the LLM
  // never saw the original — any occurrence in the rendered text traces
  // back to user input or to a placeholder restoration.
  //
  // Skipped subtrees: <code>, <pre> — restored values inside those are
  // literal/markup and highlighting them is just syntax noise. <script> and
  // <style> are skipped for sanity. <a> is NOT skipped: markdown auto-links
  // restored PII (e.g. an email becomes a mailto: link), and the user still
  // needs to see that it is tracked. We wrap only the link's text node, so
  // the href and click behavior stay intact.
  //
  // Color assignment: each placeholder hashes to one of UNMASK_PALETTE_SIZE
  // slots (data-color="0..N-1"). The mapping is deterministic so the
  // **same name keeps the same color across every card**, and the same
  // hash also flows through any future references to the same placeholder.
  // The actual color values live in CSS so dark theme can re-skin without
  // rebuilding the bundle.

  var UNMASK_PALETTE_SIZE = 8;

  // djb2-style hash → palette slot. Tiny and deterministic; enough to
  // distribute the small number of placeholders we typically see.
  function unmaskColorIndex(placeholder) {
    if (!placeholder) return 0;
    var hash = 0;
    for (var i = 0; i < placeholder.length; i++) {
      hash = ((hash << 5) - hash) + placeholder.charCodeAt(i);
      hash |= 0;
    }
    return Math.abs(hash) % UNMASK_PALETTE_SIZE;
  }

  function isInsideSkippedAncestor(node, root) {
    var p = node.parentNode;
    while (p && p !== root) {
      if (p.classList && p.classList.contains('privacy-unmasked')) return true;
      var tag = p.nodeName;
      if (tag === 'CODE' || tag === 'PRE' || tag === 'SCRIPT' || tag === 'STYLE') return true;
      p = p.parentNode;
    }
    return false;
  }

  function splitAndWrap(textNode, needle, entityType, placeholder) {
    var text = textNode.nodeValue;
    var parent = textNode.parentNode;
    if (!parent) return;

    var doc = textNode.ownerDocument || document;
    var fragment = doc.createDocumentFragment();
    var pos = 0;
    var idx;
    var colorIdx = unmaskColorIndex(placeholder);

    while ((idx = text.indexOf(needle, pos)) !== -1) {
      if (idx > pos) {
        fragment.appendChild(doc.createTextNode(text.substring(pos, idx)));
      }
      var span = doc.createElement('span');
      span.className = 'privacy-unmasked';
      // data-color drives the underline color via CSS palette rules so the
      // SAME placeholder produces the SAME visual treatment in every card.
      span.setAttribute('data-color', String(colorIdx));
      if (entityType) span.setAttribute('data-entity-type', entityType);
      if (placeholder) {
        span.setAttribute('data-placeholder', placeholder);
        // Title doubles as the native browser tooltip; the visible row is
        // styled via CSS (gray background + colored underline).
        span.setAttribute('title', 'Tracked as ' + placeholder);
      }
      span.textContent = needle;
      fragment.appendChild(span);
      pos = idx + needle.length;
    }

    if (pos === 0) return; // Nothing matched — leave the original node intact.
    if (pos < text.length) {
      fragment.appendChild(doc.createTextNode(text.substring(pos)));
    }
    parent.replaceChild(fragment, textNode);
  }

  function wrapAllOccurrences(root, needle, entityType, placeholder) {
    if (!needle) return;
    var doc = root.ownerDocument || document;
    var walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node.nodeValue || node.nodeValue.indexOf(needle) === -1) {
          return NodeFilter.FILTER_REJECT;
        }
        if (isInsideSkippedAncestor(node, root)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });

    // Collect first; we mutate during the wrap step which would invalidate
    // the walker mid-iteration.
    var nodes = [];
    var n;
    while ((n = walker.nextNode())) nodes.push(n);

    nodes.forEach(function (textNode) {
      splitAndWrap(textNode, needle, entityType, placeholder);
    });
  }

  function highlightUnmaskedSpans(root, spans) {
    if (!root || !spans || !spans.length) return;
    // Sort by length descending so multi-word originals ("Alice Smith")
    // are wrapped before any shorter substring ("Alice") that would
    // otherwise consume their text first and prevent the longer match.
    var sorted = spans.slice().sort(function (a, b) {
      var la = (a && a.original) ? a.original.length : 0;
      var lb = (b && b.original) ? b.original.length : 0;
      return lb - la;
    });
    sorted.forEach(function (span) {
      if (!span || !span.original) return;
      wrapAllOccurrences(root, span.original, span.entity_type, span.placeholder);
    });
  }

  window.WsPrivacyHandler = {
    handleState: handleState,
    handleToggleAck: handleToggleAck,
    handleRegistry: handleRegistry,
    openRegistryModal: openRegistryModal,
    isActive: isActive,
    isEnabled: function () { return _lastEnabled; },
    openExportDialog: openExportDialog,
    resetExportDialog: resetExportDialog,
    handleExportData: handleExportData,
    handleExportError: handleExportError,
    highlightUnmaskedSpans: highlightUnmaskedSpans
  };
})();
