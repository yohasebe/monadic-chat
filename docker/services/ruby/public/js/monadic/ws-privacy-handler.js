// The export dialog.
(function () {
  // ---- Unified Export Dialog (2 orthogonal axes) ----------------------
  //
  // Encryption is always offered (encrypts the file at rest). The "content"
  // axis (restored or with the chat's words hidden) is shown only for a chat
  // that hides words: otherwise there is nothing to hide.
  function isActive() {
    return !!(window.WordTable && window.WordTable.hidesWords());
  }

  function shownChat() {
    return window.WordTable && window.WordTable.chat ? window.WordTable.chat() : null;
  }

  // Whether the user picked the content themselves, and the chat the dialog
  // was opened for: the word table can arrive or change while it is open.
  let _contentChosen = false;
  let _chatShown = null;

  // A chat that hides words defaults to "masked", so the words are not
  // written to disk by accident; "restored" stays available. The content
  // axis is shown only for such a chat.
  function applyContentChoice() {
    const hidesWords = isActive();
    const restored = document.getElementById('privacyExportContentRestored');
    const masked = document.getElementById('privacyExportContentMasked');
    if (restored) restored.checked = !hidesWords;
    if (masked) masked.checked = hidesWords;
    const contentSection = document.getElementById('privacy-export-content-section');
    if (contentSection) contentSection.style.display = hidesWords ? '' : 'none';
  }

  function followWordTable() {
    const modalEl = document.getElementById('privacyExportModal');
    if (!modalEl || !modalEl.classList.contains('show')) return;
    const chat = shownChat();
    if (_chatShown !== null && chat !== _chatShown) {
      resetExportDialog();
      return;
    }
    _chatShown = chat;
    const section = document.getElementById('privacy-export-content-section');
    if (_contentChosen && section && (section.style.display !== 'none') === isActive()) return;
    applyContentChoice();
    updateExportModeUI();
  }
  document.addEventListener('wordtable:changed', followWordTable);

  function openExportDialog() {
    const modalEl = document.getElementById('privacyExportModal');
    if (!modalEl || !window.bootstrap || !window.bootstrap.Modal) return;
    resetExportDialog();
    window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
  }

  function resetExportDialog() {
    const encryptToggle = document.getElementById('export-encrypt-toggle');
    if (encryptToggle) encryptToggle.checked = false;
    _contentChosen = false;
    _chatShown = shownChat();
    const pass = document.getElementById('privacy-export-passphrase');
    const conf = document.getElementById('privacy-export-passphrase-confirm');
    if (pass) pass.value = '';
    if (conf) conf.value = '';
    applyContentChoice();
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
    //     - the chat hides words: red `alert-danger`, because the user is
    //       overriding the safer default and the file will hold the words.
    //     - otherwise: yellow `alert-warning` (the file is still cleartext).
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
      // Strong warning: the words of the chat, restored and unencrypted.
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
    // to a red "PII export" alert for a chat that hides words) and the
    // continue-button enable state.
    if (ev.target.name === 'privacyExportContent') {
      _contentChosen = true;
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
  });

  window.WsPrivacyHandler = {
    isActive: isActive,
    openExportDialog: openExportDialog,
    resetExportDialog: resetExportDialog,
    handleExportData: handleExportData,
    handleExportError: handleExportError,
  };
})();
