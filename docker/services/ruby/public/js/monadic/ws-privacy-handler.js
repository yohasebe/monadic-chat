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
  // The export asked for and not answered yet: its id, so an answer to an
  // earlier request (or after the dialog was opened again) is not taken
  // for this one.
  let _pendingExport = null;

  function t(key, fallback) {
    return typeof webUIi18n !== 'undefined' ? webUIi18n.t(key) : fallback;
  }

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
    if (!modalEl || !modalEl.open) return;
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
    if (!modalEl || !window.MonadicDialog) return;
    resetExportDialog();
    window.MonadicDialog.of(modalEl).open();
  }

  function resetExportDialog() {
    const encryptToggle = document.getElementById('export-encrypt-toggle');
    if (encryptToggle) encryptToggle.checked = false;
    _contentChosen = false;
    _chatShown = shownChat();
    _pendingExport = null;
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
    if (!pw) return { score: 0, label: t('ui.exportStrengthEmpty', 'Enter a passphrase') };
    if (pw.length < 8) return { score: 0, label: t('ui.exportStrengthShort', 'Too short (8 characters or more)') };
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
    const fallbacks = ['Very weak', 'Weak', 'Fair', 'Good', 'Strong'];
    return { score: score, label: t('ui.exportStrength' + score, fallbacks[score]) };
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
    if (_pendingExport) {
      continueBtn.disabled = true;
      return;
    }
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
    if (_pendingExport) return;
    _pendingExport = 'exp-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
    payload.request_id = _pendingExport;
    setExportStatus(t('ui.exportPreparing', 'Preparing the export…'), 'text-muted');
    checkContinueEnabled();
    // PRIVACY_EXPORT is non-idempotent (server re-runs encryption +
    // streams a base64 blob), so it is not queued for replay: when it
    // could not be sent, the dialog says so and the user tries again.
    const sent = window.safeWsSend(payload);
    if (sent && sent.sent === false && sent.queued === false) {
      _pendingExport = null;
      setExportStatus(t('ui.exportNotSent', 'The export could not be sent. Check the connection and try again.'), 'text-danger');
      checkContinueEnabled();
    }
  }

  // Whether an answer belongs to the export this dialog is waiting for;
  // when it does, the dialog stops waiting.
  function answersPending(data) {
    if (!_pendingExport || !data || data.request_id !== _pendingExport) return false;
    _pendingExport = null;
    checkContinueEnabled();
    return true;
  }

  function handleExportData(data) {
    if (!answersPending(data)) return;
    if (!data.content_base64) {
      setExportStatus(t('ui.exportFailed', 'The export failed. Try again.'), 'text-danger');
      return;
    }
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
      // The browser was handed the file; whether it was saved (or the
      // save was cancelled) is not known here.
      setExportStatus(t('ui.exportStarted', 'Download started: {name}').replace('{name}', a.download), 'text-success');
    } catch (_e) {
      setExportStatus(t('ui.exportFailed', 'The export failed. Try again.'), 'text-danger');
    }
  }

  function handleExportError(data) {
    if (!answersPending(data)) return;
    const message = data.error === 'passphrase_required'
      ? t('ui.exportPassphraseRequired', 'A passphrase is needed.')
      : t('ui.exportFailed', 'The export failed. Try again.');
    setExportStatus(message, 'text-danger');
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
