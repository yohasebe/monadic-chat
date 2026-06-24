// Confidence-via-agreement (Verify button) rendering + in-progress UI.
// Extracted from websocket.js so the rendering logic is unit-testable in
// isolation (websocket.js has load-time side effects and can't be required).
// Functions are plain globals in the concatenated bundle; the module.exports
// guard at the bottom is for the Jest environment only.

// Localized label for the verify UI (falls back to English).
function verifyT(key, fallback) {
  return (typeof getTranslation === 'function') ? getTranslation('ui.verify.' + key, fallback) : fallback;
}

// Attaches a confidence panel under the verified assistant card. `data.pending`
// shows a spinner; a full payload renders the verdict. All model-supplied text
// is HTML-escaped before insertion (panel answers go through the shared safe
// markdown renderer, identical to the main chat).
function renderVerifyConfidence(data) {
  const mid = data && data.mid;
  if (!mid) return;
  const card = (typeof $id === 'function') ? $id(mid) : document.getElementById(mid);
  if (!card) return;
  // Render inside the verify bar (below the response, by the trigger).
  const bar = card.querySelector('.verify-bar') ||
              card.querySelector('.card-text') || card.querySelector('.card-body');
  if (!bar) return;

  const prior = bar.querySelector('.verify-result');
  if (prior) prior.remove();

  const esc = (s) => String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  const panel = document.createElement('div');
  panel.className = 'verify-result';

  if (data.pending) {
    panel.classList.add('verify-result--pending');
    panel.innerHTML = '<i class="fas fa-circle-notch fa-spin"></i> ' + esc(verifyT('running', 'Verifying across models…'));
    bar.appendChild(panel);
    return;
  }

  const conf = data.confidence || 'unknown';
  const score = (typeof data.score === 'number') ? ' (' + data.score.toFixed(2) + ')' : '';
  const confLabel = verifyT('conf_' + conf, conf);

  // Collapsible: a summary header that toggles the detail body.
  const header =
    '<div class="verify-header" role="button" tabindex="0">' +
      '<i class="fas fa-chevron-down verify-caret"></i> ' +
      '<i class="fas fa-check-double"></i> ' +
      '<span class="verify-badge verify-badge--' + esc(conf) + '">' + esc(confLabel) + score + '</span>' +
      (data.corroboration
        ? ' <span class="verify-badge verify-badge--' + esc(data.corroboration) + '">' +
          esc(verifyT('corr_' + data.corroboration, data.corroboration)) + '</span>'
        : '') +
      (data.recommendation
        ? ' <span class="verify-rec">→ ' + esc(verifyT('rec_' + data.recommendation, data.recommendation)) + '</span>'
        : '') +
    '</div>';

  let bodyHtml = '';
  if (data.consensus) {
    bodyHtml += '<div class="verify-row"><strong>' + esc(verifyT('consensus', 'Consensus')) + ':</strong> ' +
      esc(data.consensus) + '</div>';
  }
  if (Array.isArray(data.disagreements) && data.disagreements.length) {
    bodyHtml += '<div class="verify-row"><strong>' + esc(verifyT('disagreements', 'Disagreements')) +
      ':</strong><ul class="verify-list">' +
      data.disagreements.map((d) => '<li>' + esc(d) + '</li>').join('') + '</ul></div>';
  }

  // Panel legend: decode "Response N" -> provider/model (the judge saw them
  // anonymized in this order), plus the moderator that judged them.
  if (Array.isArray(data.responses)) {
    const survivors = data.responses.filter((r) => r && r.success);
    if (survivors.length) {
      bodyHtml += '<div class="verify-row"><strong>' + esc(verifyT('panel', 'Panel')) + '</strong>' +
        (data.cross_provider ? '' : ' <span class="verify-weak">(' + esc(verifyT('weakSignal', 'single-provider — weak signal')) + ')</span>') +
        '<ul class="verify-list">' +
        survivors.map((r, i) => {
          const label = 'Response ' + (i + 1) + ' — ' + esc(r.provider) + (r.model ? ' / ' + esc(r.model) : '');
          const raw = r.text || '';
          // Render the member's answer with the SAME safe markdown pipeline the
          // chat uses (consistency, no new XSS surface); fall back to escaped
          // raw text (preserving line breaks) if the renderer is unavailable.
          let inner = '';
          if (raw) {
            if (window.MarkdownRenderer && typeof window.MarkdownRenderer.render === 'function') {
              try { inner = window.MarkdownRenderer.render(raw); }
              catch (_) { inner = '<pre class="verify-panel-raw">' + esc(raw) + '</pre>'; }
            } else {
              inner = '<pre class="verify-panel-raw">' + esc(raw) + '</pre>';
            }
          }
          return '<li class="verify-panel-item">' +
            '<span class="verify-panel-toggle" role="button" tabindex="0">' +
            '<i class="fas fa-caret-right verify-panel-caret"></i> ' + label + '</span>' +
            (inner ? '<div class="verify-panel-text">' + inner + '</div>' : '') +
            '</li>';
        }).join('') +
        '</ul></div>';
    }
  }
  if (data.moderator && data.moderator.provider) {
    bodyHtml += '<div class="verify-row"><strong>' + esc(verifyT('moderator', 'Moderator')) + ':</strong> ' +
      esc(data.moderator.provider) + (data.moderator.model ? ' / ' + esc(data.moderator.model) : '') + '</div>';
  }
  if (data.note) bodyHtml += '<div class="verify-row verify-muted"><small>' + esc(data.note) + '</small></div>';
  if (data.judge_error) bodyHtml += '<div class="verify-row verify-error"><small>' + esc(data.judge_error) + '</small></div>';

  panel.classList.add('verify-result--' + esc(conf));
  panel.innerHTML = header + '<div class="verify-body">' + bodyHtml + '</div>';

  // At-a-glance chip in the card header so the verdict is visible without
  // expanding (clicking it toggles the detail panel).
  const titleEl = card.querySelector('.card-header .card-title') || card.querySelector('.card-header');
  if (titleEl) {
    let chip = card.querySelector('.verify-chip');
    if (!chip) {
      chip = document.createElement('span');
      titleEl.appendChild(chip);
    }
    chip.className = 'verify-chip verify-badge--' + esc(conf);
    chip.title = confLabel + score;
    chip.innerHTML = '<i class="fas fa-check-double"></i> ' + esc(confLabel);
    chip.onclick = () => panel.classList.toggle('verify-collapsed');
  }

  const headerEl = panel.querySelector('.verify-header');
  const toggle = () => panel.classList.toggle('verify-collapsed');
  if (headerEl) {
    headerEl.addEventListener('click', toggle);
    headerEl.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(); }
    });
  }

  // Each panel member's raw answer expands on click (decode "Response N").
  panel.querySelectorAll('.verify-panel-toggle').forEach((t) => {
    const item = t.closest('.verify-panel-item');
    const txt = item ? item.querySelector('.verify-panel-text') : null;
    if (!txt) return;
    const tog = () => item.classList.toggle('verify-panel-open');
    t.addEventListener('click', tog);
    t.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); tog(); }
    });
  });

  bar.appendChild(panel);
}

// Verify-in-progress UI: the spinner makes isSystemBusy() true (blocking
// concurrent sends), plus a status message and a disabled send button. A
// watchdog clears the UI if the result frame never arrives.
function verifyUIStart(mid) {
  const running = verifyT('running', 'Verifying across models…');
  const spinner = (typeof $id === 'function') ? $id('monadic-spinner') : document.getElementById('monadic-spinner');
  if (spinner) {
    const span = spinner.querySelector('span');
    if (span) span.innerHTML = '<i class="fas fa-check-double fa-pulse"></i> ' + running;
    if (typeof $show === 'function') $show(spinner); else spinner.style.display = '';
  }
  if (typeof window.setAlert === 'function') {
    window.setAlert("<i class='fas fa-check-double fa-pulse'></i> " + running, 'info');
  }
  const send = (typeof $id === 'function') ? $id('send') : document.getElementById('send');
  if (send) send.disabled = true;
  document.body.classList.add('verifying');
  renderVerifyConfidence({ mid: mid, pending: true });

  // Watchdog kept LONGER than the backend's worst case (parallel fan-out
  // ~180s + a judge call) so it only fires on a genuine stall. A late real
  // result still renders fine — renderVerifyConfidence replaces this panel.
  if (window._verifyTimer) clearTimeout(window._verifyTimer);
  window._verifyTimer = setTimeout(function() {
    verifyUIEnd();
    renderVerifyConfidence({ mid: mid, confidence: 'unavailable', recommendation: 'verify',
                            note: verifyT('timedOut', 'Verification timed out') });
  }, 300000);
}

function verifyUIEnd() {
  if (window._verifyTimer) { clearTimeout(window._verifyTimer); window._verifyTimer = null; }
  const spinner = (typeof $id === 'function') ? $id('monadic-spinner') : document.getElementById('monadic-spinner');
  if (spinner) { if (typeof $hide === 'function') $hide(spinner); else spinner.style.display = 'none'; }
  const send = (typeof $id === 'function') ? $id('send') : document.getElementById('send');
  if (send) send.disabled = false;
  document.body.classList.remove('verifying');
  if (typeof window.setAlert === 'function') {
    window.setAlert("<i class='fa-solid fa-circle-check'></i> Ready", 'success');
  }
}

if (typeof window !== 'undefined') {
  window.verifyT = verifyT;
  window.renderVerifyConfidence = renderVerifyConfidence;
  window.verifyUIStart = verifyUIStart;
  window.verifyUIEnd = verifyUIEnd;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { verifyT, renderVerifyConfidence, verifyUIStart, verifyUIEnd };
}
